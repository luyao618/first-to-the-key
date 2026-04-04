# Prompt Input

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-02
> **System Index**: #12
> **Layer**: Presentation
> **Implements Pillar**: Human-AI Symbiosis, Simple Rules Deep Play

## Overview

Prompt Input 是 Match 场景内的 **UI 侧栏面板**，在 Match State Manager 的 SETUP 阶段显示，负责收集两位玩家的赛前 prompt 文本并写入 MatchConfig。它是玩家与游戏交互的**第一个接触点**——游戏启动后，玩家看到的第一个画面就是中央已生成的迷宫 God View + 左侧的 prompt 输入面板。

输入流程采用**轮流制**：P1 先在左侧面板编写 prompt 并点击 "Ready"，然后右侧面板切换为 P2 的输入界面，P2 写完后点击 "Ready"，系统自动触发 `MatchStateManager.start_countdown()` 进入倒计时。文本框提供 placeholder 示例 prompt 帮助新手理解"该写什么"，空 prompt 也是合法输入（LLM 将使用默认行为）。

API 配置（endpoint / api_key / model / temperature 等）不由本系统管理——由 `MatchStateManager.start_setup()` 从外部配置文件读取并写入 `MatchConfig.llm_config_a/b`（见 match-state-manager.md `AgentLLMConfig` 定义），Prompt Input 只专注于"写 prompt"这一件事。MVP 阶段仅支持 Agent vs Agent 模式的赛前 prompt 输入，不支持赛中消息发送。当 Match State Manager 离开 SETUP 状态时，Prompt Input overlay 自动隐藏。

## Player Fantasy

**"这座迷宫是我的棋盘，这段文字是我的棋手。"**

比赛还没开始，你已经在观察中央的迷宫——岔路口多不多？死胡同密集吗？结构开阔还是狭窄？这些信息流入你的大脑，转化为策略，最终凝聚成左侧面板文本框里的一段 prompt。你写下："优先探索未访问的方向，遇到死胡同立刻掉头，如果看到钥匙就直奔过去。" 点击 Ready，你的策略被封印——从这一刻起，你的 Agent 将完全按照你写的文字行动。

然后你看着对手坐到键盘前。他盯着同一座迷宫，写出完全不同的策略。你不知道他写了什么，但你知道：接下来的比赛，胜负取决于谁更懂得用文字指挥 AI。这不是打字速度的比拼，不是手速的较量——这是两段文字之间的思维对决。

**对于新手**：文本框里灰色的示例文字告诉你"prompt 长这样"——你可以直接用它开始第一场比赛，看看 AI 会怎么执行这个基础策略，然后在下一局写出你自己的版本。从模仿到创造，这就是学习曲线。

## Detailed Rules

### Core Rules

1. Prompt Input 是 Match 场景的子节点（`CanvasLayer` + `Panel`），管理 SETUP 阶段的左右两栏内容
2. Prompt Input 监听 `MatchStateManager.state_changed` 信号：进入 SETUP 时显示，离开 SETUP 时隐藏（左右栏内容交给 Match Renderer / Match HUD 接管）
3. 输入流程为**轮流制**，内部维护一个三阶段状态：`PLAYER_A_INPUT` → `PLAYER_B_INPUT` → `COMPLETED`

### Match 场景三栏布局规范

Match 场景采用固定三栏布局，**全程不变**——从 SETUP 到 PLAYING 到 FINISHED，栏位结构始终保持一致，只有栏内内容随比赛阶段切换。

```
┌──────────────┬────────────────────┬──────────────┐
│              │                    │              │
│   左栏 ~20%  │   中栏 ~60%        │   右栏 ~20%  │
│   Player A   │   迷宫 God View    │   Player B   │
│   相关内容    │   (全程不变)       │   相关内容    │
│              │                    │              │
└──────────────┴────────────────────┴──────────────┘
```

| 比赛阶段 | 左栏（Player A） | 中栏 | 右栏（Player B） |
|----------|-----------------|------|-----------------|
| **SETUP — P1 输入** | Prompt 输入界面（活跃） | 迷宫 God View | 等待提示 "Waiting for Player 1..." |
| **SETUP — P2 输入** | P1 已 Ready 提示 ✓ | 迷宫 God View | Prompt 输入界面（活跃） |
| **COUNTDOWN** | "Ready!" | 迷宫 + 3-2-1-GO | "Ready!" |
| **PLAYING** | Agent A 局部视野 / 状态（由 Match Renderer / HUD 接管） | 迷宫 God View | Agent B 局部视野 / 状态（由 Match Renderer / HUD 接管） |
| **FINISHED** | Agent A 赛后统计（由 Result Screen 接管） | 迷宫最终状态 | Agent B 赛后统计（由 Result Screen 接管） |

**布局约束**：
- 中栏宽度固定 ~60%，迷宫在其中居中渲染，不受左右栏影响
- 左右栏各 ~20%，宽度固定不随内容变化
- 左右栏之间视觉对称，强化双人对决的仪式感
- 三栏比例从配置文件读取，允许未来调整

**职责边界**：Prompt Input 系统仅管理 SETUP 阶段左右栏的内容（prompt 输入 + 等待提示 + Ready 状态）。COUNTDOWN 及之后阶段的栏内容由各自负责的系统管理。三栏容器本身是 Match 场景的节点结构，Prompt Input 和其他系统共享使用。

### 内部状态机

```
  ┌──────────────────┐   P1 点击 Ready   ┌──────────────────┐
  │  PLAYER_A_INPUT  │ ────────────────► │  PLAYER_B_INPUT  │
  └──────────────────┘                    └────────┬─────────┘
                                                   │ P2 点击 Ready
                                                   ▼
                                          ┌──────────────────┐
                                          │    COMPLETED     │
                                          └──────────────────┘
                                            写入 config.prompt_a/b
                                            调用 start_countdown()
```

| State | 左栏 | 右栏 | 行为 |
|-------|------|------|------|
| **PLAYER_A_INPUT** | 标题 "Player 1"，文本框（带 placeholder），Ready 按钮 | "Waiting for Player 1..." | 等待 P1 输入 prompt 并点击 Ready |
| **PLAYER_B_INPUT** | "Player 1 Ready ✓"（prompt 已锁定） | 标题 "Player 2"，文本框（带 placeholder），Ready 按钮 | P1 的 prompt 已暂存，等待 P2 输入 |
| **COMPLETED** | — | — | 将 prompt_a / prompt_b 写入 MatchConfig，调用 `start_countdown()` |

### UI 元素

每个玩家的输入面板包含：

```
┌──────────────┐
│  Player 1    │  ← 标题（含玩家编号）
│──────────────│
│ ┌──────────┐ │
│ │ Explore  │ │  ← TextEdit 多行文本框
│ │ unvisit- │ │     placeholder 灰色示例
│ │ ed dir.. │ │     支持滚动
│ │          │ │
│ └──────────┘ │
│              │
│    [ Ready ] │  ← 右下角按钮
└──────────────┘
```

### Placeholder 示例 Prompt

```
Explore unvisited directions first. When at a fork, prefer directions
you haven't been to. If you see a key, go to it immediately. Avoid
revisiting dead ends.
```

Placeholder 在玩家开始输入时消失。仅作为视觉提示，不会作为实际 prompt 提交。

### 数据流

```
1. Match 场景加载 → MatchStateManager 进入 SETUP
2. Prompt Input 显示左栏 P1 输入界面 + 右栏等待提示
3. P1 写 prompt，点 Ready → 暂存 prompt_a，左栏显示 "Ready ✓"，右栏切换为 P2 输入界面
4. P2 写 prompt，点 Ready → 暂存 prompt_b
5. 写入 MatchConfig.prompt_a / prompt_b
6. 调用 MatchStateManager.start_countdown()
7. state_changed(SETUP → COUNTDOWN) → Prompt Input 内容隐藏，左右栏交给后续系统
```

## Formulas

Prompt Input 是纯 UI 系统，不包含游戏性数学公式。唯一涉及"计算"的是布局比例和字符统计。

### 三栏布局尺寸

```
left_panel_width = viewport_width * panel_ratio
right_panel_width = viewport_width * panel_ratio
center_width = viewport_width - left_panel_width - right_panel_width
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| viewport_width | int | 1024 - 3840 | Godot 窗口设置 | 游戏窗口宽度（像素） |
| panel_ratio | float | 0.15 - 0.25 | 配置文件 | 左右栏占窗口宽度的比例（默认 0.20） |
| left_panel_width | float | 计算结果 | — | 左栏宽度（像素） |
| right_panel_width | float | 计算结果 | — | 右栏宽度（像素） |
| center_width | float | 计算结果 | — | 中栏宽度（像素） |

### Prompt 字符数统计（信息性，不限制输入）

```
char_count = prompt_text.length()
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| prompt_text | String | 0 - ∞ | 玩家输入 | 文本框中的 prompt 内容 |
| char_count | int | 0 - ∞ | 计算结果 | 当前字符数，显示在文本框下方作为参考信息（如 "142 characters"），不设上限 |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| P1 提交空 prompt | 允许。左栏显示 "Player 1 Ready ✓"，正常切换到 P2 输入。`prompt_a` 存储为空字符串 | Match State Manager GDD 已确认空 prompt 合法——LLM 使用默认行为。UI 不阻拦创意性输入 |
| P1 输入超长 prompt（数千字符） | 允许。文本框可滚动，不截断。字符计数器显示当前长度，但不设硬上限 | token 管理是 LLM Agent Integration 的职责，不是 UI 层的。长 prompt 可能导致 API 费用增加，但这是玩家的选择 |
| P1 点击 Ready 后想修改 prompt | 不支持回退。左栏已锁定显示 "Ready ✓"，P1 的 prompt 已暂存 | 简化流程。想改可以等这局结束后重赛。MVP 不需要回退功能——增加复杂度但使用频率低 |
| P2 输入阶段按 Escape 或关闭窗口 | Godot 默认行为（窗口关闭退出游戏）。不需要特殊处理 | MVP 不做退出确认对话框 |
| 窗口被调整大小（resize） | 三栏布局按比例自适应。文本框随面板宽度缩放，高度保持可滚动 | Godot 的 Container 节点自动处理布局自适应 |
| P2 阶段 MatchStateManager 被外部调用 reset() | Prompt Input 监听 `state_changed` 信号，若状态变为 SETUP 则重置内部状态为 `PLAYER_A_INPUT`，清空暂存的 prompt | 防御性处理，虽然正常流程不应发生 |
| 两个玩家输入完全相同的 prompt | 允许。正常写入 `prompt_a` 和 `prompt_b`，两个 Agent 使用相同策略 | 完全合法——玩家可能想测试同一策略在不同起点的表现 |
| prompt 包含特殊字符（emoji、Unicode、换行符） | 原样存储和传递。文本框支持所有 Unicode 输入。换行符保留在 prompt 中 | LLM API 支持 Unicode 和换行符，不需要 UI 层过滤 |
| MazeData 未 finalized 时 P2 点击 Ready | `start_countdown()` 的前置条件（MazeData finalized）由 Match State Manager 检查并拒绝。Prompt Input 不做此检查 | 职责分离：Prompt Input 负责收集 prompt，Match State Manager 负责校验倒计时前置条件。实际不应发生——SETUP 阶段迷宫早已生成完毕 |
| 配置文件中 API key 为空或无效 | Prompt Input 不检查 API 配置有效性。比赛开始后 LLM Agent Integration 处理 API 错误 | Prompt Input 只管 prompt 文本，API 配置不在其职责范围 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Match State Manager** | Prompt Input depends on this | 监听 `state_changed` 信号控制显示/隐藏。SETUP 阶段显示 prompt 输入界面，离开 SETUP 时隐藏。调用 `start_countdown()` 提交 prompt 并启动倒计时。写入 `MatchConfig.prompt_a` / `prompt_b` |
| **Scene Manager** | Scene Manager loads this（间接） | Prompt Input 是 Match 场景的子节点，随 Match 场景实例化/销毁。不直接调用 Scene Manager API |
| **Match Renderer** | 共享三栏布局容器 | Prompt Input 在 SETUP 阶段管理左右栏内容，PLAYING 阶段由 Match Renderer 接管左右栏显示 Agent 局部视野。两者通过 Match State Manager 的 `state_changed` 信号协调切换时机 |
| **Match HUD** | 共享三栏布局容器 | Match HUD 在 PLAYING 阶段使用左右栏显示钥匙进度、API 状态等信息，与 Match Renderer 的局部视野共存。Prompt Input 隐藏后 HUD 接管 |
| **Result Screen** | 共享三栏布局容器 | FINISHED 阶段 Result Screen 使用左右栏显示赛后统计。注意：当前设计中 Result 是独立场景（Scene Manager GDD），若改为 Match 场景内的 overlay 则共享三栏，否则不共享 |
| **Maze Generator** | 无直接依赖 | Maze Generator 在 SETUP 阶段早期生成迷宫，Prompt Input 在迷宫生成完毕后显示。两者都监听 Match State Manager 信号，无直接交互 |
| **LLM Agent Integration** | Agent 间接依赖 Prompt Input | Prompt Input 写入 `MatchConfig.prompt_a/b`，LLM Agent Integration 在 `initialize()` 时读取这些 prompt 构建 system message。两者通过 MatchConfig 数据传递，无直接引用 |
| **(无上游依赖)** | — | Prompt Input 仅依赖 Match State Manager（Foundation 层）。不依赖任何 Gameplay 或 AI 系统 |

**关于 Result Screen 的说明**：Scene Manager GDD 定义 Result 为独立场景（Match ↔ Result 切换）。但三栏布局规范暗示 FINISHED 阶段仍在 Match 场景内使用左右栏。这存在两种实现路径：
1. Result 仍为独立场景，三栏布局在 Result 场景中重新创建（与 Match 场景相同的栏位结构）
2. Result 改为 Match 场景内的 overlay，复用同一套三栏容器

此决策留待 Result Screen GDD 设计时确定。Prompt Input 系统不受此影响。

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `panel_ratio` | 0.20 | 0.15 - 0.25 | 左右栏更宽，文本框更宽敞，迷宫中栏变窄 | 左右栏更窄，文本框拥挤，迷宫中栏更大 |
| `placeholder_text` | "Explore unvisited directions first..." | 任意字符串 | N/A（文本值） | N/A |
| `text_edit_min_lines` | 8 | 4 - 20 | 文本框更高，可见行数更多，适合长 prompt | 文本框更矮紧凑，长 prompt 需要更多滚动 |
| `show_char_count` | true | true / false | 文本框下方显示字符计数 | 隐藏字符计数，界面更简洁 |

**注意事项**：

- `panel_ratio` 是三栏布局的全局参数，影响所有阶段（SETUP / PLAYING / FINISHED）的栏位宽度，不仅仅是 Prompt Input
- `placeholder_text` 的内容直接影响新手的第一局体验——应该是一个"能用但不最优"的策略，激发玩家改进的欲望
- 所有值从配置文件读取，禁止硬编码

## Acceptance Criteria

### 三栏布局
- [ ] Match 场景使用固定三栏布局（左 ~20%、中 ~60%、右 ~20%），全程不变
- [ ] 三栏比例从配置文件读取，窗口 resize 时按比例自适应

### 显示/隐藏
- [ ] Match State Manager 进入 SETUP 状态时，左右栏显示 Prompt Input 内容
- [ ] Match State Manager 离开 SETUP 状态时，Prompt Input 内容隐藏

### 轮流输入流程
- [ ] 初始状态为 `PLAYER_A_INPUT`：左栏显示 P1 输入界面，右栏显示 "Waiting for Player 1..."
- [ ] P1 点击 Ready 后切换到 `PLAYER_B_INPUT`：左栏显示 "Player 1 Ready ✓"，右栏显示 P2 输入界面
- [ ] P2 点击 Ready 后进入 `COMPLETED`：写入 `MatchConfig.prompt_a` / `prompt_b`，调用 `start_countdown()`
- [ ] P1 点击 Ready 后无法回退修改

### 文本输入
- [ ] 文本框为多行 `TextEdit`，支持滚动
- [ ] 文本框显示 placeholder 示例 prompt（灰色），玩家开始输入时消失
- [ ] 空 prompt 允许提交，不弹出错误
- [ ] 特殊字符（emoji、Unicode、换行符）原样存储和传递
- [ ] 字符计数器在文本框下方实时显示当前字符数

### 数据写入
- [ ] P1 的 prompt 正确写入 `MatchConfig.prompt_a`
- [ ] P2 的 prompt 正确写入 `MatchConfig.prompt_b`
- [ ] `COMPLETED` 后调用 `start_countdown()`，触发 SETUP → COUNTDOWN 状态转移

### 重赛
- [ ] 重新进入 SETUP 状态时（`reset()` 后），Prompt Input 重置为 `PLAYER_A_INPUT`，清空暂存 prompt
- [ ] 文本框恢复 placeholder 显示

### 配置
- [ ] 所有参数（`panel_ratio`、`placeholder_text`、`text_edit_min_lines`、`show_char_count`）从外部配置文件读取，禁止硬编码
