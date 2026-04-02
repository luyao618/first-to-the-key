# Win Condition / Chest

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-02
> **System Index**: #10
> **Layer**: Feature
> **Implements Pillar**: Simple Rules Deep Play, Fair Racing

## Overview

Win Condition / Chest 是判定比赛胜负的终局系统。当任意一方 Agent 集齐三把钥匙（由 Key Collection 的 `chest_unlocked(agent_id)` 信号通知），宝箱从 Inactive 变为 Active，出现在迷宫中由 Maze Generator 预设的 `CHEST` marker 位置。宝箱遵循 Fog of War 规则——Agent 只有进入视野范围后才能发现它的存在。集齐三把钥匙的 Agent 移动到宝箱所在 cell 时自动开启宝箱，比赛立即结束，该 Agent 获胜。未集齐三把钥匙的 Agent 即使站在宝箱 cell 上也无法开启。若同一 tick 内两个有资格的 Agent 同时到达宝箱 cell，判定为平局。该系统监听 Key Collection 的 `chest_unlocked` 信号管理宝箱激活状态，监听 Grid Movement 的 `mover_moved` 信号触发开启判定，通过调用 Match State Manager 的 `finish_match(result, winner_id)` 结束比赛。系统逻辑极其简洁——核心只有两个判定：宝箱是否 Active、到达的 Agent 是否有资格开启——体现了 Simple Rules Deep Play 的设计支柱。

## Player Fantasy

**"终点线的冲刺"**：三把钥匙全部集齐，宝箱在迷宫某处浮现——但你还不知道它在哪。你的 AI 已经跑了大半个迷宫，现在进入最后的搜索阶段。对手可能也在找，也可能还在追最后一把钥匙。这段从"集齐钥匙"到"找到宝箱"的间隙，是整场比赛最紧张的时刻：领先不等于胜利，你的 AI 必须高效搜索才能锁定胜局。

**"一锤定音的爽快"**：当你的 AI 踩上宝箱的那一刻，比赛瞬间结束——没有动画等待、没有二次确认、没有翻转机会。屏幕上宝箱打开，金蛋显现，胜利确定。这种干脆利落的终局感让每一次胜利都带着"就是这一步"的戏剧性。

**"公平到最后一步"**：宝箱位置由迷宫生成时就决定了，双方 Spawn 到宝箱的最短路径经过公平性验证。宝箱遵循迷雾规则，没有任何一方天然知道它在哪——即使你的 AI 先触发了宝箱出现，如果它恰好在对手的视野里而不在你的视野里，优势可能瞬间反转。胜负取决于整体导航效率，不取决于谁先捡到第三把钥匙。

## Detailed Design

### Core Rules

**宝箱激活机制**

1. 宝箱位置在 Maze Generator 生成时确定（`CHEST` marker 已放置在 MazeData 中），但初始状态为 **Inactive**
2. Inactive 的宝箱对所有系统不可见——Fog of War 不暴露、Renderer 不渲染、开启判定跳过
3. 当 Win Condition 收到第一个 `chest_unlocked(agent_id)` 信号时，宝箱变为 **Active**
4. 宝箱激活后发出 `chest_activated` 信号，通知 Fog of War / Renderer 等系统"宝箱已出现"
5. 宝箱激活是一次性全局事件——后续收到的 `chest_unlocked` 信号不再重复激活

**开启资格**

6. 每个 Agent 的开启资格独立跟踪：收到 `chest_unlocked(agent_id)` 后，该 Agent 标记为 `eligible`
7. 未收到 `chest_unlocked` 的 Agent 为 `ineligible`——即使站在宝箱 cell 上也不触发开启
8. 资格是永久的：一旦 `eligible`，不会退回 `ineligible`

**开启判定**

9. Win Condition 监听 Grid Movement 的 `mover_moved` 信号，每次 Agent 移动后检查新位置
10. 开启条件（全部满足才触发）：
    - 宝箱当前为 Active
    - 该 Agent 为 `eligible`
    - 该 Agent 的新位置 == 宝箱位置（`chest_position`）
11. 开启效果：调用 Match State Manager 的 `finish_match(result, winner_id)`
    - `result` = `PLAYER_A_WIN` 或 `PLAYER_B_WIN`
    - `winner_id` = 开启宝箱的 Agent ID

**同 tick 平局处理**

12. Grid Movement 在同一 tick 内按 mover_id 顺序逐个发出 `mover_moved`
13. 在同一 tick 的 `mover_moved` 处理中，Win Condition 收集所有满足开启条件的 Agent
14. 如果单个 Agent 满足条件：该 Agent 胜利
15. 如果同一 tick 内两个 Agent 都满足条件：调用 `finish_match(DRAW, -1)`，判定平局
16. 实现方式：不在每个 `mover_moved` 信号中立即调用 `finish_match()`，而是在 tick 结束时统一判定。监听 Match State Manager 的 `tick` 信号的**末尾**（或使用 `call_deferred`）进行批量处理

**生命周期**

17. Win Condition 监听 Match State Manager 的 `state_changed` 信号：COUNTDOWN 时初始化，PLAYING 时启用判定，FINISHED 后停止处理
18. `initialize(maze)` 时从 MazeData 读取 `CHEST` marker 位置并缓存

### Data Structures

```
# 枚举类型
enum ChestState { INACTIVE, ACTIVE }
enum AgentEligibility { INELIGIBLE, ELIGIBLE }

# 胜利条件管理器
WinConditionManager:
  chest_state: ChestState                          # 宝箱当前状态
  chest_position: Vector2i                         # 缓存的宝箱位置（initialize 时从 MazeData 读取）
  agent_eligibility: Dictionary<int, AgentEligibility>  # agent_id -> 开启资格
  pending_openers: Array<int>                      # 当前 tick 内满足开启条件的 agent_id 列表（tick 结束时批量判定）
  maze: MazeData                                   # 迷宫数据引用（只读）

  # --- 信号 ---
  signal chest_activated                           # 宝箱从 Inactive 变为 Active
  signal chest_opened(agent_id: int)               # 宝箱被某 Agent 开启（胜利判定前发出，供动画/音效使用）

  # --- 查询接口 ---
  is_chest_active() -> bool                        # 宝箱当前是否为 Active
  get_chest_position() -> Vector2i                 # 宝箱位置（Active 时有意义）
  is_agent_eligible(agent_id: int) -> bool         # 某 Agent 是否有资格开启宝箱

  # --- 生命周期 ---
  initialize(maze: MazeData)                       # 读取宝箱位置，初始化状态（COUNTDOWN 时调用）
  reset()                                          # 清空所有状态
```

**设计决策**：

- **`pending_openers` 缓冲区**：`mover_moved` 处理中不立即调用 `finish_match()`，而是将满足条件的 agent_id 加入缓冲区，tick 结束时统一判定。解决同 tick 平局问题
- **`chest_opened` 信号**：在调用 `finish_match()` 之前发出，给 Renderer / Audio 一个窗口播放宝箱开启动画。`finish_match()` 会触发状态切换到 FINISHED，此后 Renderer 可能进入结果展示模式
- **不持有 Match State Manager 引用**：通过信号监听 `state_changed` 和 `tick`，通过直接调用 `finish_match()` 结束比赛（单向依赖）

### States and Transitions

两个层面的状态：宝箱全局状态 + 每个 Agent 的开启资格。

**宝箱全局状态**

```
INACTIVE → ACTIVE
```

| State | Description | 触发条件 | 退出条件 |
|-------|-------------|---------|---------|
| **INACTIVE** | 宝箱未出现，所有系统不可见 | 比赛开始（PLAYING） | 收到第一个 `chest_unlocked(agent_id)` 信号 |
| **ACTIVE** | 宝箱已出现，遵循 Fog of War 可见性规则，可被 eligible Agent 开启 | 首次 `chest_unlocked` 触发 | 终态——宝箱被开启后比赛结束（FINISHED），不需要回到 INACTIVE |

**每个 Agent 的开启资格**

```
INELIGIBLE → ELIGIBLE
```

| State | Description | 触发条件 | 退出条件 |
|-------|-------------|---------|---------|
| **INELIGIBLE** | 该 Agent 尚未集齐三把钥匙，无法开启宝箱 | 初始状态 | 收到 `chest_unlocked(agent_id)` |
| **ELIGIBLE** | 该 Agent 已集齐三把钥匙，到达宝箱 cell 即可开启 | `chest_unlocked(agent_id)` | 终态——资格永久有效 |

**Tick 内判定流程**

```
每个 tick:
  1. Grid Movement 按 mover_id 顺序发出 mover_moved 信号
  2. Win Condition 收到 mover_moved → 检查开启条件 → 满足则加入 pending_openers
  3. Tick 结束时（deferred）Win Condition 检查 pending_openers:
     - 空：无事发生
     - 1 个 agent_id：该 Agent 胜利 → chest_opened(agent_id) → finish_match(WIN, agent_id)
     - 2 个 agent_id：平局 → finish_match(DRAW, -1)（不发出 chest_opened，因为没有单一开启者）
  4. 清空 pending_openers
```

### Interactions with Other Systems

| System | Direction | Interface | Data Flow |
|--------|-----------|-----------|-----------|
| **Key Collection** | Keys → WinCon | 监听 `chest_unlocked(agent_id)` 信号 | 某 Agent 集齐三把钥匙时通知 Win Condition：1) 激活宝箱（首次）；2) 标记该 Agent 为 eligible |
| **Grid Movement** | Movement → WinCon | 监听 `mover_moved(mover_id, old_pos, new_pos)` 信号 | 每次 Agent 移动后检查新位置是否为宝箱 cell，结合资格判定是否触发开启 |
| **Match State Manager** | WinCon → MSM | 调用 `finish_match(result, winner_id)` | 胜利或平局判定后调用，触发比赛结束 |
| **Match State Manager** | MSM → WinCon | 监听 `state_changed` 信号、`tick` 信号 | `state_changed`：COUNTDOWN 时初始化，PLAYING 时启用判定，FINISHED 后停止。`tick`：tick 结束时批量处理 `pending_openers` |
| **Maze Data Model** | WinCon → Model | `get_marker_position(CHEST)` | `initialize()` 时读取宝箱位置并缓存 |
| **Fog of War / Vision** | FoW → WinCon | `is_chest_active()` | FoW 查询宝箱是否 Active，决定是否向 Agent 暴露 CHEST marker 信息。Inactive 的宝箱不应出现在 Agent 视野中 |
| **Match Renderer** | Renderer → WinCon | `is_chest_active()`, `get_chest_position()` | 渲染宝箱图标（仅 Active 时）。监听 `chest_activated` 触发出现动画，监听 `chest_opened` 触发开启动画 |
| **Match HUD** | HUD → WinCon | `is_chest_active()` | 宝箱 Active 后可在 HUD 显示"宝箱已出现"提示 |
| **LLM Information Format** | LLMFormat → WinCon | `is_chest_active()`, `get_chest_position()` | 宝箱 Active 且在 Agent 视野内时，将宝箱位置序列化给 LLM |

## Formulas

Win Condition 是一个规则判定系统，没有复杂的数学公式。核心逻辑是布尔条件检查。

### Chest Open Check（每次 mover_moved 触发）

```
can_open(agent, new_pos) =
  chest_state == ACTIVE
  AND agent_eligibility[agent_id] == ELIGIBLE
  AND new_pos == chest_position
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| chest_state | enum | INACTIVE / ACTIVE | 内部状态 | 宝箱当前全局状态 |
| agent_eligibility | enum | INELIGIBLE / ELIGIBLE | 内部状态 | 该 Agent 的开启资格 |
| new_pos | Vector2i | (0,0) to (width-1, height-1) | `mover_moved` 信号参数 | Agent 移动后的新位置 |
| chest_position | Vector2i | (0,0) to (width-1, height-1) | MazeData `CHEST` marker | 宝箱所在 cell 坐标 |

### Tick-End Resolution（每个 tick 结束时）

```
resolve_pending() =
  if pending_openers.size() == 0: 无操作
  if pending_openers.size() == 1: finish_match(WIN, pending_openers[0])
  if pending_openers.size() >= 2: finish_match(DRAW, -1)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| pending_openers | Array\<int\> | 0 to 2 elements | 当前 tick 内 `can_open` 通过的 agent_id | 满足开启条件的 Agent 列表 |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| Agent 在宝箱 Inactive 时就站在宝箱 cell 上，随后宝箱被激活（另一方拾取 Crystal 触发） | 不自动开启。开启判定仅由 `mover_moved` 触发，宝箱激活事件不触发重新检查当前位置 | 与 Key Collection 的设计一致——拾取/开启判定严格绑定移动事件。Agent 需要离开再回来才能触发开启 |
| Agent 集齐三把钥匙（eligible）但宝箱尚未 Active（对方还没拿到 Crystal 触发激活） | 不可能发生。Agent 自己拾取 Crystal 时就会发出 `chest_unlocked(agent_id)`，这同时触发宝箱激活。所以 eligible Agent 出现时宝箱必然已 Active | `chest_unlocked` 信号同时完成两件事：激活宝箱 + 标记资格。逻辑上不存在"有资格但宝箱没出现"的状态 |
| Ineligible Agent 到达宝箱 cell | 无事发生。`can_open` 条件不满足（`agent_eligibility != ELIGIBLE`），不加入 `pending_openers` | 必须集齐三把钥匙才能开启宝箱，防止"蹲宝箱"策略 |
| 同一 tick 内 Agent A 拾取 Crystal（触发 `chest_unlocked`）并到达宝箱 cell | 不可能发生。每次 `mover_moved` 只移动一格，Crystal Key 和 Chest 不会在同一个 cell 上（Maze Generator 保证标记唯一性且不重叠关键标记）。因此一次移动不可能同时触发 Crystal 拾取和宝箱开启。Agent 拾取 Crystal 后需要至少一次额外移动才能到达宝箱 cell | Maze Generator 的放置约束保证了钥匙和宝箱分别在不同 cell 上（`is_valid()` 验证 6 个标记位置互不重复），从结构上消除了此时序问题 |
| 比赛超时（`max_match_duration` 到达）时宝箱仍为 Inactive | Match State Manager 自动调用 `finish_match(DRAW, -1)`。Win Condition 不需要特殊处理——超时平局由 MSM 负责 | 职责分离：Win Condition 只处理"宝箱开启"这一种胜利方式，超时是 MSM 的兜底逻辑 |
| 比赛超时时宝箱已 Active 但无人到达 | 同上，MSM 的 `finish_match(DRAW, -1)` 正常触发平局 | 宝箱出现了但没人找到——两个 AI 都迷路了，公平的平局 |
| `initialize()` 时 MazeData 中缺少 `CHEST` marker | `chest_position` 设为 `(-1, -1)`，打印错误日志。宝箱永远无法被到达，比赛最终超时平局 | 不崩溃，但游戏无法正常完成。这是 Maze Generator 的 bug——`MazeData.is_valid()` 应拦截此情况 |
| `mover_moved` 信号在非 PLAYING 状态下到达 Win Condition | 忽略，不处理开启判定 | 只在 PLAYING 状态下处理游戏逻辑 |
| `chest_unlocked` 信号在 FINISHED 状态下到达（极端时序） | 忽略。FINISHED 状态下不再修改任何内部状态 | 比赛已结束，所有后续信号无意义 |
| `pending_openers` 在 tick 结束前比赛就因超时结束 | MSM 的 `finish_match(DRAW, -1)` 先触发，状态变为 FINISHED。Win Condition 的 deferred 判定发现已不在 PLAYING 状态，清空 `pending_openers` 不执行 | 超时判定优先于宝箱判定——如果同一帧发生两件事，超时的 `finish_match` 先到先得 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Key Collection** | Win Condition depends on this | 监听 `chest_unlocked(agent_id)` 信号：首次收到时激活宝箱，每次收到时标记对应 Agent 为 eligible |
| **Grid Movement** | Win Condition depends on this | 监听 `mover_moved(mover_id, old_pos, new_pos)` 信号：每次 Agent 移动后检查是否满足宝箱开启条件 |
| **Match State Manager** | Win Condition depends on this | 监听 `state_changed` 信号管理生命周期——COUNTDOWN 时 `initialize(maze)` 读取宝箱位置，PLAYING 时启用判定，FINISHED 时停止处理。监听 `tick` 信号在 tick 结束时批量处理 `pending_openers`。调用 `finish_match(result, winner_id)` 结束比赛 |
| **Maze Data Model** | Win Condition depends on this | `initialize()` 时调用 `get_marker_position(CHEST)` 读取宝箱位置并缓存 |
| **Fog of War / Vision** | FoW depends on this | FoW 查询 `is_chest_active()` 判断是否向 Agent 暴露 CHEST marker 信息。Inactive 的宝箱不应出现在 Agent 可见信息中 |
| **Match Renderer** | Renderer depends on this | 查询 `is_chest_active()` 决定是否渲染宝箱图标。监听 `chest_activated` 播放出现动画，监听 `chest_opened` 播放开启动画 |
| **Match HUD** | HUD depends on this | 查询 `is_chest_active()` 显示"宝箱已出现"状态提示 |
| **LLM Information Format** | LLMFormat depends on this | 查询 `is_chest_active()` 和 `get_chest_position()` 将宝箱状态序列化给 LLM（仅 Active 且在视野内时） |

## Tuning Knobs

Win Condition 是一个纯规则判定系统，自身几乎没有可调参数——宝箱位置由 Maze Generator 决定，胜负逻辑是固定规则。唯一可能的调节来自宝箱放置策略，但那属于 Maze Generator 的职责。

| Knob | Type | Default | Safe Range | Affects | Owned By |
|------|------|---------|------------|---------|----------|
| `chest_placement_strategy` | enum | — | 由 Maze Generator 定义 | 宝箱放在迷宫中心、随机位置还是距离两方 Spawn 等距的位置，影响终局阶段的搜索时长和公平性 | Maze Generator |
| `chest_spawn_fairness_delta` | int | — | 由 Maze Generator 定义 | 双方 Spawn 到宝箱的最短路径差异上限（与钥匙的 `max_fairness_delta` 同理） | Maze Generator |

**设计说明**：

- Win Condition 本身没有运行时配置项——没有"开启延迟"、"开启冷却"、"宝箱血量"等机制，开启是即时的一次性判定
- 如果未来需要增加终局复杂度（如宝箱需要多次交互才能打开），可以在此系统中添加调节项，但 MVP 阶段保持极简
- 影响终局体验的主要调节在 Maze Generator 端：宝箱与钥匙的相对位置关系决定了"集齐钥匙后还要找多久"

## Visual/Audio Requirements

### Visual

| Element | Description | Priority |
|---------|-------------|----------|
| **宝箱图标（Inactive）** | 不渲染。Inactive 宝箱对渲染系统完全不可见 | MVP |
| **宝箱图标（Active）** | 宝箱在迷宫 cell 中显示，带轻微上下浮动动画（与钥匙风格一致）。颜色建议金色/木色，区别于钥匙的铜/绿/蓝 | MVP |
| **宝箱激活动画** | 宝箱出现时的动画：从无到有的淡入 + 光柱效果（比钥匙出现更隆重），持续约 0.5-0.8 秒 | MVP |
| **宝箱开启动画** | Agent 踩到宝箱时：宝箱盖弹开 → 金蛋升起 → 光芒扩散。持续约 1.0-1.5 秒，在 `chest_opened` 信号发出后、`finish_match` 调用前播放 | MVP |
| **金蛋** | 纯视觉元素，作为宝箱开启动画的一部分出现。金色发光球体，不需要独立数据模型 | MVP |
| **胜利者高亮** | 开启宝箱的 Agent 高亮/放大，失败者灰显（具体由 Match Renderer / Result Screen 负责） | MVP |

### Audio

| Element | Description | Priority |
|---------|-------------|----------|
| **宝箱出现音效** | 深沉的魔法浮现声，比钥匙激活音效更厚重，提示双方"终局阶段开始了" | MVP |
| **宝箱开启音效** | 木质宝箱打开的"咔嗒"声 + 金蛋出现时的华丽乐句，是全场比赛最隆重的音效 | MVP |
| **胜利音效** | 欢快的短旋律（约 2-3 秒），在 `finish_match` 触发后播放。由 Result Screen 或全局音效管理器负责 | MVP |

**设计说明**：

- 宝箱开启动画是比赛中最有戏剧性的时刻——视觉和音效应该比钥匙拾取更有仪式感
- 金蛋不需要独立的渲染逻辑或数据模型，它是宝箱开启动画的嵌入元素
- 动画播放窗口：`chest_opened` 信号 → 动画播放 → 动画完成后调用 `finish_match()`。或者 `finish_match()` 立即调用但 Renderer 在 FINISHED 状态下播放开启动画。具体实现由 Match Renderer 决定

## Acceptance Criteria

### 宝箱激活

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-1 | 比赛开始（PLAYING）时，宝箱为 Inactive | 单元测试：`initialize()` 后断言 `is_chest_active() == false` |
| AC-2 | 收到第一个 `chest_unlocked(agent_id)` 后，宝箱变为 Active | 单元测试：模拟 `chest_unlocked(0)` 信号，断言 `is_chest_active() == true` 且 `chest_activated` 信号发出 |
| AC-3 | 第二个 `chest_unlocked` 不重复激活宝箱 | 单元测试：连续发送两次 `chest_unlocked`，断言 `chest_activated` 信号只发出一次 |

### 开启资格

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-4 | 每个 Agent 初始资格为 Ineligible | 单元测试：`initialize()` 后断言 `is_agent_eligible(0) == false`，`is_agent_eligible(1) == false` |
| AC-5 | 收到 `chest_unlocked(agent_id)` 后该 Agent 变为 Eligible | 单元测试：发送 `chest_unlocked(0)` 后断言 `is_agent_eligible(0) == true`，`is_agent_eligible(1) == false` |
| AC-6 | 资格是永久的，不会退回 Ineligible | 单元测试：标记 eligible 后无论后续发生什么，`is_agent_eligible()` 始终返回 true |

### 开启判定

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-7 | Eligible Agent 移动到宝箱 cell 时触发开启 | 集成测试：宝箱 Active + Agent eligible + `mover_moved` 到宝箱位置，断言 `chest_opened` 信号发出且 `finish_match` 被调用 |
| AC-8 | Ineligible Agent 移动到宝箱 cell 时不触发开启 | 集成测试：宝箱 Active + Agent ineligible + `mover_moved` 到宝箱位置，断言无 `chest_opened` 信号 |
| AC-9 | 宝箱 Inactive 时任何 Agent 到达宝箱 cell 不触发开启 | 单元测试：宝箱 Inactive + Agent eligible + `mover_moved` 到宝箱位置，断言无 `chest_opened` 信号 |
| AC-10 | 非 PLAYING 状态下 `mover_moved` 不触发开启判定 | 单元测试：在 COUNTDOWN 状态下发送 `mover_moved`，断言无 `chest_opened` 信号 |

### 同 tick 平局

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-11 | 同一 tick 内单个 eligible Agent 到达宝箱：该 Agent 胜利 | 集成测试：模拟单 Agent `mover_moved` 到宝箱，tick 结束后断言 `finish_match` 参数为该 Agent 的 WIN |
| AC-12 | 同一 tick 内两个 eligible Agent 到达宝箱：判定平局 | 集成测试：模拟两个 Agent 同 tick `mover_moved` 到宝箱，tick 结束后断言 `finish_match(DRAW, -1)` |
| AC-13 | `pending_openers` 在每个 tick 结束后清空 | 单元测试：tick 结束判定后断言 `pending_openers` 为空 |

### 生命周期

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-14 | `initialize(maze)` 正确读取 MazeData 中的 CHEST marker 位置 | 单元测试：构造含 CHEST marker 的 MazeData，`initialize()` 后断言 `get_chest_position()` 返回正确坐标 |
| AC-15 | `reset()` 清空所有状态（宝箱回到 Inactive，所有 Agent 回到 Ineligible，pending_openers 清空） | 单元测试：完整流程后调用 `reset()`，断言所有状态恢复初始值 |
| AC-16 | MazeData 中缺少 CHEST marker 时 `initialize()` 不崩溃，打印错误日志 | 单元测试：构造缺少 CHEST 的 MazeData，`initialize()` 后断言无异常且错误日志被记录 |

## Open Questions

| # | Question | Impact | Status |
|---|----------|--------|--------|
| OQ-1 | 宝箱开启动画与 `finish_match()` 的时序：是先播放动画再调用 `finish_match()`（延迟结束），还是立即调用 `finish_match()` 让 Renderer 在 FINISHED 状态下播放动画？前者更有仪式感但需要延迟机制，后者实现更简单 | Medium | 推迟到 Match Renderer 设计时决定 |
| OQ-2 | Key Collection 的 OQ-2 现已解决：宝箱位置由 Maze Generator 预设在 MazeData 中，`chest_unlocked` 信号不需要携带位置。Win Condition 的 `initialize()` 从 MazeData 读取 | — | Resolved |
| OQ-3 | 是否需要记录"宝箱在第几 tick 被激活"和"在第几 tick 被开启"供 Result Screen 展示？可以为观战增加数据维度 | Low | 推迟到 Result Screen 设计时决定 |
| OQ-4 | 信号连接顺序：Key Collection 和 Win Condition 都监听 `mover_moved`。需要确保 Key Collection 先处理（触发 `chest_unlocked`），Win Condition 后处理（读取已更新的状态）。Godot 的信号连接顺序取决于 `connect()` 调用顺序——是否需要显式指定优先级？ | Medium | 推迟到实现阶段决定。备选方案：Win Condition 不直接监听 `mover_moved`，而是在 `chest_unlocked` handler 中检查该 Agent 当前位置是否为宝箱 cell |
