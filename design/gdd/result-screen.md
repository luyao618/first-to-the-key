# Result Screen

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-02
> **System Index**: #14
> **Layer**: Presentation
> **Implements Pillar**: Simple Rules Deep Play

## Overview

Result Screen 是比赛结束后的**独立场景**，展示胜负结果、比赛统计和双方 prompt，并提供重赛或退出的操作入口。当 Match State Manager 进入 FINISHED 状态后，Match 场景根脚本调用 `SceneManager.go_to("result")` 跳转至本场景。

Result Screen 复用 Prompt Input 定义的**三栏布局**（左 ~20% / 中 ~60% / 右 ~20%），保持视觉一致性——左栏展示 Agent A 的详细统计（API 调用、token 消耗、空转率、钥匙进度、prompt 文本），右栏展示 Agent B 的对应数据，中栏展示核心结果（胜负标题、比赛用时、tick 数）和操作按钮（Rematch / Quit）。所有数据从 Match State Manager 和 LLM Agent Integration 的 Autoload 实例中读取——这些 Autoload 在场景切换后仍保留数据（`reset()` 在玩家点击 Rematch 时才调用）。

MVP 阶段仅支持 Agent vs Agent 模式的结果展示，不支持回放功能。设计目标是让玩家在 5 秒内理解"谁赢了、为什么"，然后自然地点击 Rematch 调整 prompt 再来一局。

## Player Fantasy

**"复盘的快感"**：比赛结束，屏幕切换到结果页面——"Player 1 Wins!" 大字映入眼帘。你立刻看向右栏：对手的 Agent 空转了 15% 的 tick，API 调用了 58 次，而你的只用了 42 次。你向下滚到对手的 prompt："Always go north first, then explore east..." ——难怪他的 AI 在迷宫南半部分转了那么久。你对自己的策略更有信心了，但你也注意到自己的 token 消耗比对手低不少——也许你的 prompt 太短了，可以补充更多细节。

**"再来一局"的冲动**：结果页面不是终点，而是下一局的起点。你已经知道自己的 prompt 哪里好、哪里有改进空间。Rematch 按钮就在屏幕正中——一键回到 prompt 输入界面，一座全新的迷宫已经等着你。从"看结果"到"改 prompt"到"再比一场"的循环，是游戏留存的核心动力。

**"数据说话"**：不是"感觉"谁的 prompt 更好，而是数据明确告诉你——42 次 API 调用 vs 58 次，8% 空转 vs 15%，更少的调用意味着你的 Agent 在直道上更高效，更低的空转率意味着 API 响应更快或决策点更少。这些数字把"prompt 工程"从玄学变成了可量化的竞技。

## Detailed Rules

### Core Rules

1. Result Screen 是一个**独立 Godot 场景**（`result.tscn`），由 Scene Manager 加载/卸载
2. `_ready()` 时从 Autoload 系统读取所有数据：`MatchStateManager`（结果、配置、用时）和 `LLMAgentManager`（API 统计）
3. 数据读取是**一次性的**——`_ready()` 中完成全部读取并填充 UI，之后不再查询上游系统
4. 复用 Prompt Input 定义的三栏布局比例（左 ~20% / 中 ~60% / 右 ~20%）

### 三栏布局

```
┌──────────────┬────────────────────┬──────────────┐
│  Agent A     │                    │  Agent B     │
│  详细统计     │  ┌──────────────┐ │  详细统计     │
│              │  │ Player 1     │ │              │
│  API: 42     │  │   Wins!      │ │  API: 58     │
│  Tokens: 12K │  │              │ │  Tokens: 18K │
│  Idle: 8%    │  │ Time: 2:35   │ │  Idle: 15%   │
│  Keys: 3/3   │  │ Ticks: 310   │ │  Keys: 2/3   │
│              │  │              │ │              │
│  ── Prompt ──│  │ [ Rematch ]  │ │  ── Prompt ──│
│  "Explore    │  │ [ Quit ]     │ │  "Always go  │
│   unvisited  │  └──────────────┘ │   north..."  │
│   dirs..."   │                    │              │
└──────────────┴────────────────────┴──────────────┘
```

### 中栏 — 核心结果区

| 元素 | 内容 | 样式 |
|------|------|------|
| **结果标题** | "Player 1 Wins!" / "Player 2 Wins!" / "Draw!" | 大号字体，胜利者颜色对应 Agent 颜色（蓝/红），平局用中性色 |
| **比赛用时** | "Time: M:SS" 格式 | 中号字体 |
| **Tick 数** | "Ticks: N" | 中号字体 |
| **Rematch 按钮** | 点击 → `MatchStateManager.reset()` → `SceneManager.go_to("match")` | 主要按钮样式，居中显眼 |
| **Quit 按钮** | 点击 → `get_tree().quit()` | 次要按钮样式，位于 Rematch 下方 |

### 左右栏 — Agent 统计区

每个 Agent 的统计面板包含以下信息，从上到下：

| 元素 | 数据来源 | 格式 |
|------|----------|------|
| **Agent 标题** | agent_id | "Agent A" / "Agent B"，带对应颜色标识 |
| **胜负标记** | MatchStateManager.result | 胜利者显示 "Winner" / 失败者显示 "Defeated" / 平局双方显示 "Draw" |
| **API 调用次数** | AgentBrain.total_api_calls | "API Calls: 42" |
| **Token 消耗** | AgentBrain.total_tokens_used | "Tokens: 12,480" |
| **空转 tick 数** | AgentBrain.total_idle_ticks | "Idle Ticks: 25 (8%)"，百分比 = idle_ticks / total_ticks |
| **钥匙进度** | KeyCollection.get_agent_progress() | "Keys: 3/3" 或 "Keys: 2/3" |
| **分隔线** | — | 视觉分隔 |
| **Prompt 文本** | MatchConfig.prompt_a / prompt_b | 可滚动文本区域，显示完整 prompt。空 prompt 显示 "(empty)" |

### 数据读取流程

```
Result._ready():
  1. 从 MatchStateManager 读取：
     - result (WIN_A / WIN_B / DRAW)
     - winner_id (0 / 1 / -1)
     - config.prompt_a, config.prompt_b
     - tick_count
     - elapsed_time
  2. 从 LLMAgentManager 读取：
     - get_brain(0).total_api_calls, total_tokens_used, total_idle_ticks
     - get_brain(1).total_api_calls, total_tokens_used, total_idle_ticks
  3. 从 KeyCollection 读取：
     - get_agent_progress(0), get_agent_progress(1)
  4. 填充 UI 元素
```

### 按钮交互

```
Rematch 按钮 pressed:
  1. MatchStateManager.reset()    # 清空比赛数据，回到 SETUP
  2. SceneManager.go_to("match")  # 加载全新 Match 场景

Quit 按钮 pressed:
  1. get_tree().quit()            # 退出游戏
```

**关键约束**：`reset()` 必须在 `go_to("match")` 之前调用（Scene Manager GDD 已确认），确保新 Match 场景启动时 MatchStateManager 处于干净的 SETUP 状态。

## Formulas

Result Screen 是纯展示系统，游戏性公式不多。主要是数据格式化计算。

### 空转率

```
idle_rate = total_idle_ticks / tick_count * 100
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| total_idle_ticks | int | 0+ | AgentBrain.total_idle_ticks | 该 Agent 因等待 API 而原地不动的 tick 数 |
| tick_count | int | 1+ | MatchStateManager.tick_count | 比赛总 tick 数 |
| idle_rate | float | 0 - 100 | 计算结果 | 空转百分比，显示为 "8%" |

### 比赛用时格式化

```
minutes = floor(elapsed_time / 60)
seconds = floor(elapsed_time % 60)
display = "{minutes}:{seconds:02d}"
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| elapsed_time | float | 0+ | MatchStateManager.elapsed_time | 比赛总时长（秒） |
| minutes | int | 0+ | 计算结果 | 分钟数 |
| seconds | int | 0 - 59 | 计算结果 | 秒数（两位补零） |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 超时平局（DRAW, winner_id = -1） | 中栏标题显示 "Draw!"（中性色）。左右栏均显示 "Draw"，无胜利者标记。不显示胜利者高亮 | 超时平局是合法结果，两个 Agent 都没完成目标 |
| 某个 Agent 的 total_api_calls = 0（API key 无效，从未成功调用） | 正常显示 "API Calls: 0"，"Tokens: 0"，"Idle Ticks: N (100%)"。不崩溃 | 数据原样展示，玩家自行判断原因。Result Screen 不做诊断 |
| 双方 prompt 都为空 | 左右栏 prompt 区域显示 "(empty)" | 空 prompt 是合法输入（Match State Manager 已确认） |
| prompt 文本非常长（数千字符） | prompt 区域可滚动，不截断。面板高度固定，超出部分通过 ScrollContainer 查看 | 完整展示玩家的 prompt，不丢失信息 |
| tick_count = 0（比赛在 PLAYING 后立即结束，极端情况） | 空转率计算避免除零：若 tick_count == 0 则显示 "Idle: 0 (0%)" | 防御性处理。理论上至少有 1 个 tick 才能触发 finish_match |
| MatchStateManager 数据在 Result 场景 _ready() 前被意外 reset() | 所有数据为默认值（result = NONE, tick_count = 0 等）。显示空白或默认文本，不崩溃 | 不应发生——Canonical Flow 保证 reset() 在 Rematch 按钮点击时才调用。防御性处理 |
| LLMAgentManager 不可用（Autoload 未注册） | `_ready()` 中检查引用是否为 null。若不可用，左右栏 API 统计区域显示 "N/A"，其他数据正常显示 | 防御性处理。Result Screen 应在任何数据源缺失时优雅降级 |
| 快速连续点击 Rematch 按钮 | 第一次点击触发 `reset()` + `go_to("match")`。Scene Manager 进入 SWITCHING 状态，后续点击被忽略（Scene Manager 的重入保护） | Scene Manager GDD 已定义 SWITCHING 状态下 go_to() 被忽略 |
| 窗口被调整大小 | 三栏布局按比例自适应，与 Prompt Input 行为一致 | Godot Container 节点自动处理 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Match State Manager** | Result Screen depends on this | `_ready()` 中读取 `result` / `winner_id` / `config.prompt_a` / `config.prompt_b` / `tick_count` / `elapsed_time`。Rematch 按钮调用 `reset()` 清空数据。MatchStateManager 是 Autoload，场景切换后仍保留数据 |
| **LLM Agent Integration** | Result Screen depends on this | `_ready()` 中读取 `get_brain(0/1).total_api_calls` / `total_tokens_used` / `total_idle_ticks` 展示 API 统计。LLMAgentManager 是 Autoload |
| **Key Collection** | Result Screen depends on this | `_ready()` 中读取 `get_agent_progress(0/1)` 展示钥匙收集进度。KeyCollection 是 Autoload |
| **Scene Manager** | Result Screen depends on this | Rematch 按钮调用 `SceneManager.go_to("match")` 返回 Match 场景。Result 场景本身由 Scene Manager 加载 |
| **Prompt Input** | 共享设计规范 | Result Screen 复用 Prompt Input 定义的三栏布局比例（左 ~20% / 中 ~60% / 右 ~20%）。无代码依赖，仅视觉规范一致性 |
| **Match Renderer** | 无直接依赖 | Match Renderer 在 Match 场景中运行，Result Screen 在 Result 场景中运行，两者不共存。Result Screen 不渲染迷宫 |
| **(无下游依赖)** | — | Result Screen 是数据流终端和用户交互终端，不被任何其他系统依赖 |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `panel_ratio` | 0.20 | 0.15 - 0.25 | 左右栏更宽，统计数据和 prompt 文本更宽敞 | 左右栏更窄，中栏结果区更大 |
| `result_title_font_size` | 48 | 32 - 72 | 结果标题更醒目 | 标题更低调，留更多空间给其他元素 |
| `stat_font_size` | 16 | 12 - 24 | 统计数字更大易读 | 更紧凑，可显示更多信息 |
| `prompt_max_visible_lines` | 6 | 3 - 15 | prompt 区域更高，可见更多内容 | prompt 区域更矮，给统计数据更多空间 |
| `winner_color_a` | `#4488FF`（蓝） | 任意颜色 | N/A（颜色值） | N/A |
| `winner_color_b` | `#FF4444`（红） | 任意颜色 | N/A（颜色值） | N/A |
| `draw_color` | `#AAAAAA`（灰） | 任意中性色 | N/A（颜色值） | N/A |

**注意事项**：

- `panel_ratio` 与 Prompt Input 共享同一配置值，确保两个场景的三栏比例一致
- Agent 颜色应与 Match Renderer 的 `agent_a_color` / `agent_b_color` 保持一致，建议从同一配置源读取
- 所有值从配置文件读取，禁止硬编码

## Acceptance Criteria

### 数据读取
- [ ] `_ready()` 中从 MatchStateManager 正确读取 result、winner_id、prompt_a、prompt_b、tick_count、elapsed_time
- [ ] `_ready()` 中从 LLMAgentManager 正确读取双方的 total_api_calls、total_tokens_used、total_idle_ticks
- [ ] `_ready()` 中从 KeyCollection 正确读取双方的钥匙进度
- [ ] 任何 Autoload 数据源不可用时优雅降级（显示 "N/A"），不崩溃

### 三栏布局
- [ ] 复用 Prompt Input 定义的三栏比例（左 ~20% / 中 ~60% / 右 ~20%）
- [ ] 三栏比例从配置文件读取，窗口 resize 时按比例自适应

### 中栏 — 核心结果
- [ ] Player A 胜利时显示 "Player 1 Wins!"，标题颜色为 Agent A 颜色（蓝）
- [ ] Player B 胜利时显示 "Player 2 Wins!"，标题颜色为 Agent B 颜色（红）
- [ ] 平局时显示 "Draw!"，标题颜色为中性色
- [ ] 比赛用时以 "M:SS" 格式正确显示
- [ ] Tick 数正确显示

### 左右栏 — Agent 统计
- [ ] 胜利者栏显示 "Winner"，失败者栏显示 "Defeated"，平局双方显示 "Draw"
- [ ] API 调用次数、Token 消耗、空转 tick 数正确显示
- [ ] 空转率百分比正确计算（idle_ticks / tick_count * 100），tick_count 为 0 时不除零
- [ ] 钥匙进度正确显示（如 "Keys: 3/3" 或 "Keys: 2/3"）
- [ ] Prompt 文本完整显示，长文本可滚动
- [ ] 空 prompt 显示 "(empty)"

### 按钮交互
- [ ] 点击 Rematch 依次调用 `MatchStateManager.reset()` 和 `SceneManager.go_to("match")`
- [ ] 点击 Quit 调用 `get_tree().quit()`
- [ ] 快速连续点击 Rematch 不会重复触发场景切换（Scene Manager 重入保护）

### 完整重赛流程
- [ ] Rematch 后新 Match 场景加载，MatchStateManager 处于 SETUP 状态，tick_count == 0，无旧数据残留

### 配置
- [ ] 所有参数（panel_ratio、字体大小、颜色）从外部配置文件读取，禁止硬编码
