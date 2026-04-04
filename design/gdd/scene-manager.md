# Scene Manager

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-04
> **System Index**: #3
> **Layer**: Foundation
> **Implements Pillar**: Simple Rules Deep Play

## Overview

Scene Manager 是管理游戏顶层场景切换的全局系统（Godot Autoload）。它维护一个场景注册表，提供场景跳转接口，并处理切换时的资源加载与释放。MVP 阶段游戏仅有两个顶层场景：**Match**（比赛主场景，涵盖 prompt 输入、倒计时、比赛进行的全部阶段，Prompt Input 作为 Match 场景内的 UI overlay 存在）和 **Result**（赛后结果展示）。游戏启动后直接进入 Match 场景，Match State Manager 驱动 SETUP->COUNTDOWN->PLAYING->FINISHED 状态流转，其中 SETUP 阶段 Maze Generator 生成迷宫后 Match Renderer 立即渲染 God View（通过 `maze_generated` 信号触发 `initialize(maze)`），玩家在 God View 背景上编写 prompt。比赛结束后切换到 Result 场景展示结果，玩家可选择重赛（返回 Match）或退出。Scene Manager 本身不管理 UI 层级或游戏逻辑——它只负责"当前屏幕上是哪个顶层场景"这一件事，场景内部的 UI overlay 切换由各场景自行管理。

## Player Fantasy

Scene Manager 是玩家不会注意到的系统——除非它出问题。它塑造的体验是**无缝流转的比赛节奏**：

**"再来一局"的冲动不被打断**：比赛结束，结果闪过，你点击"重赛"——一秒钟后你已经在写新 prompt 了，背景是一张全新的迷宫。没有加载画面，没有等待，没有多余的菜单层级。这种从结果到下一局的零摩擦切换，让"one more round"变成自然反应。

**第一印象即游戏**：启动游戏后没有 logo 动画、没有主菜单——你直接看到一座迷宫和 prompt 输入框。Scene Manager 确保玩家的第一秒就是游戏体验本身，而非等待和点击。

## Detailed Design

### Core Rules

1. Scene Manager 是一个 **Godot Autoload**（全局单例），在游戏启动时自动加载，生命周期贯穿整个应用
2. Scene Manager 维护一个**场景注册表**，从外部配置文件（JSON）读取场景名称到 `.tscn` 路径的映射
3. **Eager Cache 加载策略**：`_ready()` 阶段一次性将注册表中所有场景预加载为 `PackedScene` 并缓存。`go_to()` 直接从缓存取用，不做运行时加载。如果某个路径在启动时加载失败，打印错误日志并从注册表中移除该条目
4. 切换场景使用 `get_tree().change_scene_to_packed()`，传入缓存的 `PackedScene`
5. 场景切换接口：`go_to(scene_name: String, transition: TransitionType = NONE)` — 通过注册名称跳转，不暴露文件路径
6. `TransitionType` 枚举预留扩展：MVP 仅实现 `NONE`（硬切），后续可添加 `FADE`、`SLIDE` 等
7. Scene Manager 在切换前发出 `scene_changing(old_name, new_name)` 信号（此时旧场景仍存在于场景树中）。切换完成后发出 `scene_changed(new_name)` 信号——**`scene_changed` 仅在新场景成为 `get_tree().current_scene` 且其 `_ready()` 已执行完毕后才发出**，确保监听者可以安全访问新场景树。实现方式：使用 `await get_tree().tree_changed` 或 deferred call 确认新场景就绪
8. Scene Manager 跟踪 `current_scene_name: String`，任何系统可查询当前处于哪个场景
9. 游戏启动时，Scene Manager 自动跳转到配置文件中指定的 `initial_scene`（MVP 默认为 `"match"`）
10. Scene Manager 不持有游戏数据——跨场景数据传递由其他 Autoload 系统负责（`MatchStateManager` 持有比赛配置和结果，`LLMAgentManager` 持有 API 统计，`KeyCollection` 持有钥匙进度——这三个 Autoload 在场景切换后数据仍可读取，Result Screen 依赖此特性）
11. Scene Manager 不管理场景内部的 UI overlay 切换——Match 场景内 Prompt Input overlay 的显示/隐藏由 Match 场景自身根据 Match State Manager 的状态信号控制

### States and Transitions

Scene Manager 本身有两层状态：**自身的运行状态**和**它管理的场景流转**。

**Scene Manager 运行状态：**

```
  ┌──────────┐   _ready() 加载配置   ┌────────┐
  │  (启动)   │ ──────────────────► │  READY │
  └──────────┘                      └───┬────┘
                                        │ go_to(initial_scene)
                                        ▼
                                   ┌─────────┐   go_to(scene_name)
                                   │  IDLE   │ ◄──────────────────┐
                                   └───┬─────┘                    │
                                       │ go_to() 被调用            │
                                       ▼                          │
                                  ┌───────────┐   切换完成         │
                                  │ SWITCHING │ ──────────────────┘
                                  └───────────┘
```

| State | Behavior |
|-------|----------|
| **READY** | `_ready()` 中加载配置文件、填充场景注册表、预加载场景资源。完成后自动跳转 `initial_scene` |
| **IDLE** | 场景已加载完毕，等待下一次 `go_to()` 调用。此状态下 `current_scene_name` 有效 |
| **SWITCHING** | 正在执行场景切换。此状态下再次调用 `go_to()` 被忽略并打印警告，防止重复切换 |

**MVP 场景流转：**

```
  ┌─────────┐  "重赛"   ┌─────────┐
  │  Match  │ ◄──────── │ Result  │
  └────┬────┘           └─────────┘
       │ 比赛结束              ▲
       │ go_to("result")       │
       └───────────────────────┘
```

- 游戏启动 -> Match 场景（SETUP 阶段：迷宫渲染 + Prompt Input overlay）
- 比赛结束 -> `go_to("result")` -> Result 场景
- 重赛 -> `go_to("match")` -> Match 场景（新一局）

### Interactions with Other Systems

| System | Direction | Interface | Data Flow |
|--------|-----------|-----------|-----------|
| **Match State Manager** | 间接关系，通过场景脚本中转 | Match State Manager 发出 `match_finished` 信号，**Match 场景的根脚本**监听该信号并调用 `SceneManager.go_to("result")` | Match State Manager 不直接引用 Scene Manager |
| **Result Screen** | Result -> Scene Manager | Result 场景中"重赛"按钮依次调用 `MatchStateManager.reset()` 然后 `SceneManager.go_to("match")`，"退出"按钮调用 `get_tree().quit()` | Result 场景通过 Scene Manager 跳回 Match |
| **Prompt Input** | 无直接交互 | Prompt Input 是 Match 场景内的 UI overlay，不经过 Scene Manager | Prompt Input 的显示/隐藏由 Match 场景监听 Match State Manager 的 `state_changed` 信号控制 |
| **Match Renderer** | 无直接交互 | Match Renderer 是 Match 场景的组成部分，随场景加载/卸载 | 场景切换时自动实例化/释放 |
| **Maze Generator** | 无直接交互 | Maze Generator 在 Match 场景的 SETUP 阶段运行，由 Match State Manager 信号触发 | Scene Manager 加载 Match 场景后，后续流程由 Match State Manager 驱动 |

**关键设计决策**：Scene Manager 和 Match State Manager 的职责边界清晰——Match State Manager 管理比赛生命周期（SETUP->COUNTDOWN->PLAYING->FINISHED），Scene Manager 管理顶层场景切换（Match<->Result）。两者通过信号松耦合：Match State Manager 不直接调用 Scene Manager，而是由监听方（Match 场景或 Result 场景）决定何时触发场景切换。

### Canonical Scene Flow（MVP 标准流程）

```
1. 游戏启动
   SceneManager._ready() -> 加载配置 -> eager cache 所有场景 -> go_to("match")

2. Match 场景加载
   Match._ready() -> 连接 MatchStateManager 信号
   -> MatchStateManager.start_setup(config) -> Maze Generator 生成迷宫
   -> Maze Generator 发出 maze_generated 信号 -> Match Renderer.initialize(maze) 渲染迷宫
   -> Prompt Input overlay 显示（左右栏显示输入界面，中栏已显示迷宫 God View）
   -> 玩家参考迷宫结构编写 prompt

3. 比赛开始
   Prompt 提交 -> MatchStateManager.start_countdown() -> 3-2-1-GO
   -> MatchStateManager.start_playing() -> tick 循环启动

4. 比赛结束
   Win Condition 调用 MatchStateManager.finish_match(result, winner_id)
   -> MatchStateManager 发出 match_finished 信号
   -> Match 场景根脚本监听该信号，调用 SceneManager.go_to("result")
   注意：此时 MatchStateManager 仍处于 FINISHED 状态，保留比赛数据

5. Result 场景加载
   Result._ready() -> 从 MatchStateManager 读取 result/winner_id/config/elapsed_time
   -> 从 LLMAgentManager 读取 API 统计（total_api_calls/total_tokens_used/total_idle_ticks）
   -> 从 KeyCollection 读取钥匙进度（get_agent_progress）
   -> 展示比赛结果

6. 重赛
   玩家点击"重赛" -> Result 场景调用 MatchStateManager.reset()（清空数据，回到 SETUP）
   -> 然后调用 SceneManager.go_to("match")（加载全新 Match 场景实例）
   -> 回到步骤 2
```

**关键约束**：`MatchStateManager.reset()` 必须在 `SceneManager.go_to("match")` 之前调用，确保新 Match 场景启动时 MatchStateManager 已处于干净的 SETUP 状态。Result 场景在调用 `reset()` 之前已完成所有数据读取。

## Formulas

Scene Manager 是纯逻辑调度系统，不包含游戏性相关的数学公式。

### 过渡时间（预留，MVP 不实现）

```
transition_progress = elapsed / transition_duration
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| elapsed | float | 0 to transition_duration | 内部计时 | 过渡效果已进行的时间（秒） |
| transition_duration | float | 0.1 - 2.0 | 配置文件 | 过渡效果总时长（秒） |
| transition_progress | float | 0.0 - 1.0 | 计算结果 | 过渡进度，用于驱动动画（0 = 开始，1 = 完成） |

**MVP 状态**：`TransitionType.NONE` 跳过所有过渡计算，`transition_duration` 无效。

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 未注册的场景名：`go_to("nonexistent")` | 操作被忽略，打印错误日志 `"Scene not found in registry: nonexistent"`，保持当前场景不变 | 防御性编程，不因拼写错误导致崩溃 |
| SWITCHING 状态中再次调用 `go_to()` | 操作被忽略，打印警告日志 `"Scene switch already in progress, ignoring go_to()"` | 防止快速连续点击导致重复切换 |
| `scene_changing` 信号监听者中调用 `go_to()`（重入） | 重入调用被忽略（此时仍处于 SWITCHING 状态），打印警告日志 | 防止信号回调中触发嵌套场景切换导致状态混乱 |
| `scene_changing` 信号监听者中释放节点或产生 GDScript 错误 | 场景切换继续执行。GDScript 错误会被引擎打印到控制台但不会中断 `go_to()` 的后续逻辑 | Godot 信号回调中的错误不会阻断调用者，但需确保 `go_to()` 在 emit 之后的逻辑不依赖监听者的成功执行 |
| 跳转到当前场景：`go_to("match")` 但已经在 Match 场景 | 正常执行切换——重新加载 Match 场景。这是"重赛"的标准路径（Result -> Match，或 Match 重新加载自身） | 重赛需要全新的 Match 场景实例（新迷宫、新状态） |
| 配置文件缺失或格式错误 | `_ready()` 中打印错误日志，使用内置 fallback 注册表（硬编码 Match + Result 路径），游戏继续运行 | 配置文件损坏不应阻止游戏启动 |
| 启动时某个 `.tscn` 路径无效（文件不存在） | eager cache 阶段检测到加载失败，打印错误日志 `"Failed to preload scene: [path]"`，该条目从注册表中移除，其他场景正常缓存 | 启动时暴露问题，比运行时发现更好 |
| `initial_scene` 配置的场景名不在注册表中（或已因加载失败被移除） | 打印错误日志，尝试加载注册表中的第一个场景作为 fallback | 确保游戏总能启动到某个场景 |
| 游戏启动时注册表为空（配置文件无有效场景且 fallback 也失败） | 打印致命错误日志，不执行场景切换。Godot 默认主场景（project.godot 中配置的）保持显示 | 极端异常情况，开发者需手动修复配置 |
| 重赛时 Result 场景在 `reset()` 之前读取数据 | 正常工作——`reset()` 由 Result 场景的重赛按钮触发，此前 MatchStateManager 仍处于 FINISHED 状态，所有数据可安全读取 | Canonical Scene Flow 保证了数据读取在 `reset()` 之前完成 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Match State Manager** | Match State Manager 间接触发 Scene Manager | Match State Manager 发出 `state_changed` / `match_finished` 信号，Match 场景或 Result 场景监听后调用 `SceneManager.go_to()`。两者无直接引用，通过场景脚本中转 |
| **Prompt Input** | Prompt Input depends on Scene Manager | Scene Manager 加载 Match 场景时，Prompt Input overlay 随场景实例化。但 Prompt Input 的显示/隐藏由 Match State Manager 信号控制，不经过 Scene Manager |
| **Result Screen** | Result depends on Scene Manager | Scene Manager 负责加载/卸载 Result 场景。Result 场景中的"重赛"按钮调用 `SceneManager.go_to("match")` |
| **Match Renderer** | Renderer 间接依赖 Scene Manager | Match Renderer 是 Match 场景的子节点，随场景加载/卸载而创建/销毁 |
| **(无上游依赖)** | — | Scene Manager 是 Foundation 层，不依赖任何其他游戏系统。仅依赖 Godot 引擎（`SceneTree`、`PackedScene`、`ResourceLoader`）和外部配置文件 |

**Hard vs Soft 依赖**：
- **Hard**: Scene Manager -> Godot SceneTree（没有它无法切换场景）
- **Hard**: Scene Manager -> 配置文件（但有内置 fallback，降级为 soft）
- **Soft**: 所有下游系统对 Scene Manager 的依赖——它们需要 Scene Manager 才能被加载，但不直接调用其 API（除了 Result Screen 的重赛按钮）

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `initial_scene` | `"match"` | 注册表中任意有效场景名 | N/A（字符串值，非数值） | N/A |
| `transition_duration` | 0.0（MVP 不使用） | 0.1 - 2.0 | 过渡动画更慢更从容，但玩家等待更久 | 过渡更快更干脆，接近硬切 |
| `config_file_path` | `"res://assets/data/scene_registry.json"` | 任意有效 `res://` 路径 | N/A（路径值） | N/A |

**注意事项**：

- `initial_scene` 修改后可以改变游戏启动的第一个画面，未来加入 Title Screen 时只需改配置
- `transition_duration` MVP 阶段无效（`TransitionType.NONE`），预留给后续 polish 阶段
- 场景注册表本身是最重要的"可调"数据——添加新场景只需在 JSON 中增加一行，无需改代码
- 所有值从外部配置文件读取，禁止硬编码

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|----------------|---------------|----------|
| 场景切换（NONE 模式） | 硬切，无过渡效果 | 无 | MVP |
| 场景切换（FADE 模式，未来） | 淡出到黑屏 -> 淡入新场景 | 可选：轻微的 whoosh 音效 | Full |
| 场景加载失败 | 无视觉反馈（保持当前场景） | 无 | MVP |

**注意**：Scene Manager 本身几乎不产生视觉/音频输出。场景切换在 MVP 中是硬切，视觉过渡是 Full 阶段的 polish 内容。各场景内部的视觉/音频由各自的系统负责（Match Renderer、Match HUD 等）。

## Acceptance Criteria

- [ ] Scene Manager 作为 Autoload 在游戏启动时自动加载
- [ ] `_ready()` 中从外部 JSON 配置文件加载场景注册表，并 eager cache 所有注册场景为 `PackedScene`
- [ ] 启动时加载失败的场景路径被移除并打印错误日志，不影响其他场景
- [ ] 配置文件缺失时使用内置 fallback 注册表，打印错误日志但不崩溃
- [ ] 游戏启动后自动跳转到 `initial_scene` 配置的场景
- [ ] `go_to("match")` 成功切换到 Match 场景，`get_tree().current_scene` 指向新 Match 场景实例
- [ ] `go_to("result")` 成功切换到 Result 场景
- [ ] `go_to("nonexistent")` 不崩溃，打印错误日志，保持当前场景不变
- [ ] SWITCHING 状态下重复调用 `go_to()` 被忽略并打印警告
- [ ] `scene_changing` 信号监听者中调用 `go_to()` 被忽略（重入保护）
- [ ] 跳转到当前场景（如 `go_to("match")` 在 Match 中）正常重新加载为全新实例
- [ ] `scene_changing(old_name, new_name)` 在旧场景仍存在于场景树时发出
- [ ] `scene_changed(new_name)` 仅在新场景成为 `get_tree().current_scene` 且其 `_ready()` 执行完毕后发出
- [ ] `current_scene_name` 在 `scene_changed` 发出时已更新为新场景名称
- [ ] `TransitionType.NONE` 执行硬切，无视觉过渡
- [ ] 完整重赛流程验证：Match(FINISHED) -> Match 根脚本调用 `go_to("result")` -> Result 读取 MatchStateManager 数据 -> 点击重赛 -> `reset()` + `go_to("match")` -> 新 Match 场景 `tick_count == 0` 且无旧结果数据
- [ ] Performance: 场景切换（`go_to()` 调用到 `scene_changed` 信号）在 500ms 内完成（eager cache 场景，无运行时加载）

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| 是否需要场景预加载机制？MVP 的 2 个场景体积很小，同步加载无感知延迟。但如果未来加入 Title Screen 或大型场景，可能需要后台预加载 | Technical Director | Sprint 2 | 已解决——MVP 使用 eager cache（启动时一次性预加载所有注册场景），不需要后台异步预加载 |
| 未来加入 Title Screen / Settings 时，是否需要引入场景栈（支持"返回上一个场景"）？ | Game Designer | Core 阶段 | MVP 不需要——只有 Match <-> Result 双向跳转。Core 阶段评估 |
| `go_to()` 是否需要支持传递参数（如 `go_to("result", {winner = "A"})`）？ | Technical Director | Sprint 1 | 待定——当前设计中跨场景数据由 Match State Manager Autoload 持有，不需要参数传递。但保持关注 |
