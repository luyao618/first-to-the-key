# Match State Manager

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-03
> **System Index**: #2
> **Layer**: Foundation
> **Implements Pillar**: Simple Rules Deep Play, Fair Racing

## Overview

Match State Manager 是驱动比赛生命周期的状态机系统。它管理一场比赛从配置到结束的全部阶段流转：进入 SETUP 阶段后迷宫生成，玩家在 God View 下查看迷宫并输入 prompt -> 比赛正式开始（tick 计时、Agent 行动）-> 某方达成胜利条件 -> 比赛结束并展示结果。该系统本身不执行迷宫生成、不移动 Agent、不判定钥匙拾取 -- 它仅维护"当前比赛处于哪个阶段"这一核心状态，并通过信号（signals）通知其他系统发生了阶段切换。作为 Foundation 层组件，它为 LLM Agent Integration 提供 tick 驱动、为 Prompt Input 和 Result Screen 提供阶段入口/出口、为 Win Condition 提供比赛结束的触发通道。MVP 阶段仅支持 Agent vs Agent 模式，但状态机设计应预留扩展到 Player vs Agent 和 Player vs Player 模式的能力。

## Player Fantasy

Match State Manager 和 Maze Data Model 类似，是一个"幕后"系统，玩家不会直接感知它的存在。但它塑造了比赛的节奏和仪式感：

**赛前准备的期待感**：迷宫生成完毕，你看着整张地图，思考该怎么指导你的 AI——写好 prompt 点击"开始"，倒计时的出现告诉你"比赛即将开始" -- 这个从准备到开赛的切换，就是状态机在工作。它创造了一个仪式化的"起跑线"瞬间。

**比赛中的紧张感**：Tick 计时器持续推进，你的 Agent 每秒都在做决策。Match State Manager 驱动着这个心跳般的节奏，让观战不是被动等待，而是一场有节奏的竞赛。

**胜负揭晓的戏剧性**：当一方 Agent 打开宝箱的瞬间，比赛从"进行中"切换到"结束" -- 所有系统同时响应：Agent 停止移动、胜利动画播放、结果界面弹出。这个"一锤定音"的干脆切换，就是状态机提供的。

## Detailed Design

### Core Rules

1. Match State Manager 是一个有限状态机（FSM），管理一场比赛的完整生命周期
2. 同一时刻只能处于一个状态，所有状态转移必须经过明确的转移条件
3. 状态转移通过 Godot 信号（signals）广播给所有监听系统，信号在状态切换后立即发出
4. Match State Manager 持有比赛级别的共享数据：游戏模式、双方 prompt、比赛结果、经过的 tick 数
5. Tick 驱动仅在 `Playing` 状态下激活 -- 一个基于 Timer 的循环，每隔 `tick_interval` 秒发出 `tick` 信号
6. 任何系统都可以读取当前状态，但只有特定系统可以触发状态转移（如 Win Condition 触发结束）
7. Match State Manager 不依赖任何其他游戏系统，但几乎所有系统都通过信号监听它

### Data Structures

```
enum MatchState { SETUP, COUNTDOWN, PLAYING, FINISHED }
enum GameMode { AGENT_VS_AGENT, PLAYER_VS_AGENT, PLAYER_VS_PLAYER }
enum MatchResult { NONE, PLAYER_A_WIN, PLAYER_B_WIN, DRAW }

MatchConfig:
  game_mode: GameMode              # 当前比赛模式
  prompt_a: String                 # 玩家 A 的 prompt（Agent 模式）
  prompt_b: String                 # 玩家 B 的 prompt（Agent 模式）
  maze_width: int                  # 迷宫宽度（传递给 Maze Generator）
  maze_height: int                 # 迷宫高度
  vision_strategy: VisionStrategy  # 视野策略（传递给 Fog of War）— 由 game_mode 自动决定，不由玩家配置

# game_mode → vision_strategy 映射规则（在 start_setup() 中自动设置）：
#   AGENT_VS_AGENT     → PATH_REACH      (LLM Agent 使用路径可达感知)
#   PLAYER_VS_AGENT    → LINE_OF_SIGHT   (人类玩家使用视线)
#   PLAYER_VS_PLAYER   → LINE_OF_SIGHT   (人类玩家使用视线)
# VisionStrategy 是共享枚举类型，定义在此处（MatchConfig 层），FoW 引用
enum VisionStrategy { PATH_REACH, LINE_OF_SIGHT }

MatchStateManager:
  current_state: MatchState        # 当前状态
  config: MatchConfig              # 比赛配置（Setup 阶段填充）
  result: MatchResult              # 比赛结果（Finished 时设置）
  winner_id: int                   # 胜利者 ID（0 = A, 1 = B, -1 = 无）
  tick_count: int                  # 已经过的 tick 数
  elapsed_time: float              # 已经过的实际时间（秒）

  # --- 信号 ---
  signal state_changed(old_state, new_state)
  signal tick(tick_count)           # 每个 tick 发出，携带当前 tick 编号
  signal match_finished(result)     # 比赛结束时发出，携带结果

  # --- 状态转移接口 ---
  start_setup(config: MatchConfig)  # 进入 Setup，加载配置
  start_countdown()                 # Setup -> Countdown
  start_playing()                   # Countdown -> Playing，启动 tick 计时器
  finish_match(result, winner_id)   # Playing -> Finished，停止 tick，记录结果
  reset()                           # 任意状态 -> Setup，重置所有数据

  # --- 查询接口 ---
  get_state() -> MatchState
  get_config() -> MatchConfig
  get_tick_count() -> int
  get_elapsed_time() -> float
  is_playing() -> bool              # 便捷方法：当前是否在 Playing 状态
```

### States and Transitions

```
  ┌─────────┐   start_setup()   ┌───────────┐
  │  (初始)  │ ───────────────► │   SETUP   │
  └─────────┘                    └─────┬─────┘
                                       │ start_countdown()
                                       ▼
                                ┌─────────────┐
                                │  COUNTDOWN  │
                                └──────┬──────┘
                                       │ start_playing() (倒计时结束自动触发)
                                       ▼
                                ┌─────────────┐
                                │   PLAYING   │ ◄── tick 循环在此状态运行
                                └──────┬──────┘
                                       │ finish_match(result, winner_id)
                                       ▼
                                ┌─────────────┐
                                │  FINISHED   │
                                └──────┬──────┘
                                       │ reset()
                                       ▼
                                ┌─────────────┐
                                │    SETUP    │ (可以开始新一局)
                                └─────────────┘
```

| State | Entry Condition | Behavior | Exit Condition |
|-------|----------------|----------|----------------|
| **SETUP** | `start_setup(config)` 或 `reset()` | 等待配置填充。Prompt Input UI 在此阶段活跃。Maze Generator 在此阶段生成迷宫 | `start_countdown()` 被调用（前置条件：配置完整且 MazeData 已 finalized） |
| **COUNTDOWN** | `start_countdown()` | 显示倒计时（3-2-1-GO）。Agent 和玩家已就位但不可移动 | 倒计时结束，自动调用 `start_playing()` |
| **PLAYING** | `start_playing()` | Tick 计时器启动，每隔 `tick_interval` 秒发出 `tick` 信号。Agent 可以移动，钥匙可以拾取 | `finish_match()` 被调用（Win Condition 触发） |
| **FINISHED** | `finish_match(result, winner_id)` | Tick 停止。记录结果和胜利者。Result Screen 展示比赛数据 | `reset()` 被调用（玩家选择重赛或返回） |

### Interactions with Other Systems

| System | Direction | Interface | Data Flow |
|--------|-----------|-----------|-----------|
| **Prompt Input** | Prompt Input -> Manager | `start_setup()`, 写入 `config.prompt_a/b` | UI 收集 prompt 后填入配置，配置完成后触发 countdown |
| **Maze Generator** | Manager -> Generator（通过信号） | `state_changed` 信号 | Setup 阶段，Generator 监听信号开始生成迷宫 |
| **LLM Agent Integration** | Agent -> Manager | 监听 `tick` 信号 | 每个 tick，Agent 系统读取信号执行一次 LLM 决策 + 移动 |
| **Grid Movement** | Movement -> Manager | 監听 `tick` 信号，查询 `is_playing()` | 仅在 Playing 状态下处理移动请求 |

**`tick` 信号处理顺序约束**：LLM Agent Integration 必须在 Grid Movement 之前处理 `tick` 信号——Agent 先写入 `pending_direction`（Phase 1 Decision），Grid Movement 再读取并执行移动（Phase 2 Movement）。实现方式：确保 LLM Agent Integration 的 `connect("tick", ...)` 调用先于 Grid Movement 的 `connect("tick", ...)`（Godot 信号按连接顺序同步分派），或改用两个分离信号（`tick_decision` → `tick_execute`）。详见 Grid Movement GDD 的 Tick Phase Model。

| **Fog of War** | FoW -> Manager（通过信号） | `state_changed` 信号 | COUNTDOWN 阶段，FoW 监听信号调用 `initialize(maze, agent_ids)` 创建 VisionMap 并刷新初始视野。`initialize()` 从 MazeData 读取 spawn 位置，并从 MatchConfig 读取 `vision_strategy`。Rematch 时相同流程（重新 initialize 即可） |
| **Win Condition** | WinCon -> Manager | `finish_match(result, winner_id)` | 检测到胜利条件后调用，触发比赛结束 |
| **Match HUD** | HUD -> Manager | 监听 `tick` 信号，查询 `get_tick_count()` / `get_elapsed_time()` | 显示比赛时间和 tick 数 |
| **Result Screen** | Result -> Manager | 监听 `match_finished` 信号，查询 `get_config()` | 展示比赛结果、双方 prompt、比赛时长 |
| **Scene Manager** | Manager <-> Scene | `reset()` 后通知 Scene Manager 切换场景 | 比赛结束后返回主菜单或重赛 |

## Formulas

### Tick Timing

```
next_tick_time = last_tick_time + tick_interval
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| last_tick_time | float | 0+ | 内部记录 | 上一次 tick 的时间戳（秒） |
| tick_interval | float | 0.1 - 5.0 | 配置文件 | 两次 tick 之间的间隔（秒） |
| next_tick_time | float | 0+ | 计算结果 | 下一次 tick 应触发的时间 |

**实现方式**：使用 Godot Timer 节点，`wait_time = tick_interval`，`autostart = false`，在 `start_playing()` 中启动，`finish_match()` 中停止。

### Elapsed Time

```
elapsed_time = current_time - playing_start_time
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| current_time | float | 0+ | `Time.get_ticks_msec() / 1000.0` | 当前引擎时间 |
| playing_start_time | float | 0+ | 进入 Playing 状态时记录 | Playing 阶段开始的时间戳 |
| elapsed_time | float | 0+ | 计算结果 | 比赛已进行的时长（秒） |

### Countdown Timer

```
countdown_remaining = countdown_duration - (current_time - countdown_start_time)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| countdown_duration | float | 1.0 - 10.0 | 配置文件 | 倒计时总时长（秒） |
| countdown_start_time | float | 0+ | 进入 Countdown 状态时记录 | 倒计时开始的时间戳 |
| countdown_remaining | float | 0 to countdown_duration | 计算结果 | 倒计时剩余秒数 |

**触发条件**：`countdown_remaining <= 0` 时自动调用 `start_playing()`。

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 非法状态转移：在 Playing 状态调用 `start_countdown()` | 操作被忽略，打印警告日志 `"Invalid transition: PLAYING -> COUNTDOWN"` | FSM 严格执行合法转移路径，防止状态混乱 |
| 双方同时到达宝箱（同一 tick 内两个 `finish_match()` 调用） | 第一次调用生效，状态切换为 Finished。第二次调用被忽略（已不在 Playing 状态） | 信号处理是同步的，第一个到达的先处理。极端情况下判定为平局需由 Win Condition 在同一次调用中指定 `DRAW` |
| 比赛超时：Playing 状态持续超过 `max_match_duration` | `finish_match(DRAW, -1)` 自动触发，比赛以平局结束 | 防止比赛无限进行（两个 Agent 都卡住的情况） |
| Prompt 为空：玩家未输入 prompt 就触发 `start_countdown()` | 允许 -- 空 prompt 是合法的（LLM 会使用默认行为）。但 UI 层可以显示警告 | 数据层不应限制创意性输入，包括空输入 |
| `reset()` 在 Playing 状态中被调用（玩家中途退出） | 立即停止 tick 计时器，清空所有数据，切换到 Setup 状态 | 支持玩家随时放弃当前比赛。不需要确认对话（由 UI 层负责） |
| `finish_match()` 在 Countdown 状态被调用 | 操作被忽略，打印警告日志。只有 Playing 状态可以结束比赛 | 比赛还没开始就不可能结束 |
| Tick 计时器在 LLM API 延迟期间继续触发 | 正常触发 tick 信号。Agent 若无响应则原地等待（由 LLM Agent Integration 处理） | Tick 是全局心跳，不因单个 Agent 的延迟而暂停 |
| 连续快速调用 `reset()` + `start_setup()` | 每次 `reset()` 完整清理状态后再执行 `start_setup()`，不会产生残留数据 | 支持快速重赛场景 |
| 迷宫未就绪时调用 `start_countdown()` | 操作被忽略，打印警告日志 `"Cannot start countdown: MazeData not finalized"` | Setup -> Countdown 的前置条件要求 MazeData 已 finalized，防止在迷宫未生成完成时开赛 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Prompt Input** | Prompt Input depends on this | 监听 `state_changed` 信号，仅在 Setup 状态显示 prompt 输入界面 |
| **Maze Generator** | Generator depends on this | 监听 `state_changed` 信号，在 Setup 阶段启动迷宫生成 |
| **LLM Agent Integration** | Agent depends on this | 监听 `tick` 信号驱动 LLM 决策循环，查询 `is_playing()` |
| **Grid Movement** | Movement depends on this | 监听 `tick` 信号，仅在 Playing 状态处理移动 |
| **Fog of War** | FoW depends on this | 监听 `state_changed` 信号，在 COUNTDOWN 阶段调用 `initialize(maze, agent_ids)` 创建 VisionMap、刷新初始视野（从 MazeData 读取 spawn 位置）、读取 `MatchConfig.vision_strategy` 选择视野算法 |
| **Win Condition / Chest** | WinCon depends on this | 调用 `finish_match()` 触发比赛结束 |
| **Match HUD** | HUD depends on this | 监听 `tick` 信号更新时间显示，查询 `get_elapsed_time()` |
| **Result Screen** | Result depends on this | 监听 `match_finished` 信号，读取 `result` / `winner_id` / `config` 展示结果 |
| **Scene Manager** | Scene depends on this | 监听 `state_changed` 信号协调场景切换 |
| **Observer Communication** | Observer depends on this（Core 阶段） | 监听 `tick` 信号，仅在 Playing 状态处理观察者通信 |
| **(无上游依赖)** | -- | Match State Manager 是 Foundation 层，不依赖任何其他游戏系统。仅依赖 Godot 引擎（Timer 节点、信号系统） |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `tick_interval` | 0.5 | 0.1 - 5.0 | Agent 决策间隔更长，比赛节奏更慢，LLM 有更多时间响应 | 节奏更快更紧张，LLM 可能来不及响应导致更多"原地等待" |
| `countdown_duration` | 3.0 | 1.0 - 10.0 | 赛前等待更久，增加仪式感但可能让玩家不耐烦 | 更快开赛，节奏更紧凑 |
| `max_match_duration` | 300.0 | 60.0 - 600.0 | 允许更长的比赛，适合大迷宫 | 更快触发超时平局，避免无聊的僵局 |

**注意事项**：

- `tick_interval` 是影响游戏体验最关键的参数，需要在原型阶段通过实际 LLM 响应速度来调优
- `max_match_duration` 应与迷宫大小成正比 -- 15x15 迷宫 300 秒可能足够，50x50 可能需要 600 秒
- 所有值必须从配置文件读取，禁止硬编码

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|----------------|---------------|----------|
| 进入 Countdown | 屏幕中央显示 3-2-1-GO 倒计时数字 | 每秒一个倒计时音效，GO 时更强烈 | MVP |
| 进入 Playing | 倒计时消失，迷宫和 Agent 完全可见 | 可选：比赛开始音效 | MVP |
| 进入 Finished | 胜利者高亮，失败者灰显 | 胜利音效 / 平局音效 | MVP |
| 超时触发 | 屏幕闪烁"TIME UP"提示 | 超时警告音效 | MVP |

## Acceptance Criteria

- [ ] 状态机初始状态为 SETUP
- [ ] `start_countdown()` 仅在 SETUP 状态有效，其他状态调用被忽略并打印警告
- [ ] `start_playing()` 仅在 COUNTDOWN 状态有效
- [ ] `finish_match()` 仅在 PLAYING 状态有效
- [ ] `reset()` 在任意状态均有效，重置后状态为 SETUP
- [ ] 每次状态转移都发出 `state_changed(old, new)` 信号
- [ ] Playing 状态下，`tick` 信号按 `tick_interval` 间隔持续发出
- [ ] Playing 状态下，`tick_count` 每次 tick 递增 1
- [ ] `elapsed_time` 在 Playing 状态下准确反映比赛已进行时长
- [ ] 超过 `max_match_duration` 后自动调用 `finish_match(DRAW, -1)`
- [ ] Countdown 结束后自动调用 `start_playing()`，不需要外部触发
- [ ] `finish_match()` 调用后 tick 计时器立即停止，不再发出 `tick` 信号
- [ ] `match_finished` 信号在 `finish_match()` 时发出，携带正确的 `result`
- [ ] `reset()` 后 `tick_count`、`elapsed_time`、`result`、`winner_id` 全部清零
- [ ] Performance: 状态转移和信号发送在 1ms 内完成
- [ ] 所有配置值（tick_interval, countdown_duration, max_match_duration）从外部配置读取，无硬编码

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| `tick_interval` 是否应该根据 LLM 实际响应时间动态调整？ | Game Designer | 原型阶段 | 待定 -- MVP 使用固定值，原型验证后决定是否需要自适应 |
| 是否需要暂停功能（Playing 状态中暂停 tick）？ | Game Designer | Sprint 1 | MVP 不需要暂停 -- 比赛时间短（<10 分钟），Agent vs Agent 无需暂停 |
| 比赛结果是否需要记录详细统计（每个 Agent 的移动次数、探索率等）？ | Game Designer | Sprint 2 | MVP 只记录胜负和时长。详细统计可在 Result Screen GDD 中定义 |
