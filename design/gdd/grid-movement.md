# Grid Movement

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-03
> **System Index**: #5
> **Layer**: Core
> **Implements Pillar**: Fair Racing, Simple Rules Deep Play

## Overview

Grid Movement 是管理 Agent（和未来的玩家角色）在迷宫网格中移动的系统。每当 Match State Manager 发出 `tick` 信号，Grid Movement 为每个移动实体执行一次移动：接收移动方向（由 LLM Agent Integration 或玩家输入提供），通过 Maze Data Model 的 `can_move()` 验证通行性，合法则更新实体坐标，非法则原地不动并消耗该 tick。移动是离散的——每 tick 恰好 0 或 1 格，不存在"半格"状态。两个 Agent 可以站在同一 cell，互不影响。系统还维护每个实体的移动历史（已访问 cell 列表），供 Fog of War 和 LLM Information Format 下游消费。Grid Movement 本身不决定"往哪走"——它只执行和验证移动指令，是 LLM Agent Integration（决策）与 Maze Data Model（空间数据）之间的桥梁。

## Player Fantasy

Grid Movement 是玩家能直观感知到的第一个"游戏在运行"的系统——Agent 在迷宫中一格一格地移动，就是它在工作。

**对于 prompt 策略师（Agent vs Agent 模式）**：你盯着屏幕上两个小点在迷宫中交替前进。你的 Agent 到了一个 T 字路口——向左是死胡同，向右通往钥匙。它选了右边。你松了口气：你的 prompt 教会了它优先探索未知方向。而对面的 Agent 撞了墙，原地浪费了一个 tick。那一刻你知道，你写的 prompt 更好。每一步移动都是 prompt 质量的即时反馈——没有延迟，没有模糊，一格一格，清清楚楚。

**对于迷宫探索者（未来 Player vs Player 模式）**：WASD 按下的瞬间，你的角色流畅地滑入下一格。碰到墙壁？什么都不会发生——没有弹开、没有惩罚，只是安静地"此路不通"。这种简洁让你把注意力放在决策上：走哪条路？要不要叫观察员？而不是在操控上分心。

## Detailed Design

### Core Rules

1. Grid Movement 管理一组**移动实体（Mover）**，每个 Mover 代表迷宫中的一个可移动角色（MVP 阶段固定 2 个：Agent A 和 Agent B）
2. 每个 Mover 持有：当前坐标 `position: Vector2i`、待执行方向 `pending_direction: MoveDirection`、移动历史 `visited_cells: Array<Vector2i>`
3. 移动仅在 `PLAYING` 状态下发生——Grid Movement 监听 Match State Manager 的 `tick` 信号
4. 每个 tick 的处理流程（对每个 Mover 依次执行）：
   - 读取 `pending_direction`
   - 若为 `NONE`，原地不动
   - 若有方向，调用 `MazeData.can_move(pos.x, pos.y, direction)` 验证
   - 合法：更新 `position`，将新坐标加入 `visited_cells`（若未存在），发出 `mover_moved` 信号
   - 非法（撞墙）：原地不动，发出 `mover_blocked` 信号
   - 清空 `pending_direction` 为 `NONE`
5. 外部系统（LLM Agent Integration / 玩家输入）通过 `set_direction()` 写入 `pending_direction`，Grid Movement 在**同一 tick 的 Phase 2** 消费它（见 Tick Phase Model）。如果在 Phase 2 执行前被多次写入，以最后一次为准。Tick 间（Phase 2 执行后到下一 tick Phase 1 前）写入的方向将在下一个 tick 的 Phase 2 消费
6. 两个 Mover 可以占据同一 cell，不产生碰撞或交互
7. Mover 初始位置从 MazeData 的 `SPAWN_A` / `SPAWN_B` 标记读取。Grid Movement 监听 Match State Manager 的 `state_changed(_, COUNTDOWN)` 信号，收到后自动调用内部 `initialize()`，确保 Agent 在倒计时阶段已就位但不可移动（tick 仅在 PLAYING 状态触发）。`initialize()` 从已持有的 `maze` 和 `fog` 引用读取数据（见 Data Structures 中的字段定义），完成所有 Mover 就位后，为每个 Mover 调用 `fog.update_vision(mover_id, spawn_pos)` 触发初始视野计算——这保证比赛开始时 Agent 在 Spawn 周围已有视野，而非全黑状态
8. **Tick 原子性**：每个 tick 内，Grid Movement **先完成所有 Mover 的移动处理**，再由下游系统（Win Condition、Key Collection 等）统一响应信号。实现方式：`on_tick()` 先收集所有 Mover 的移动结果，处理完毕后再批量发出信号。这保证了同一 tick 内两个 Mover 同时到达宝箱时，Win Condition 能看到两者的最终位置并正确判定为 `DRAW`

### Tick Phase Model

每个 tick 的跨系统处理被划分为三个**确定性 phase**，按严格顺序执行。这消除了信号连接顺序带来的不确定性：

```
┌─────────────────────────────────────────────────────────────────┐
│  Phase 1 — Decision（决策写入）                                  │
│  LLM Agent Integration 的 on_tick()：                           │
│    - 检查 pending API 响应，更新 path_queue                      │
│    - 从 path_queue 消费方向 或 直道自动前进                       │
│    - 调用 GridMovement.set_direction(mover_id, dir) 写入方向     │
│  执行完毕后，所有 Mover 的 pending_direction 已就绪               │
├─────────────────────────────────────────────────────────────────┤
│  Phase 2 — Movement（移动执行 + 信号批量发出）                    │
│  Grid Movement 的 on_tick()：                                   │
│    - 读取每个 Mover 的 pending_direction                         │
│    - 验证通行性，更新位置                                         │
│    - 收集所有结果，批量发出 mover_moved / mover_blocked / stayed  │
├─────────────────────────────────────────────────────────────────┤
│  Phase 3 — Reaction（下游系统响应 mover_moved 信号）              │
│  按信号传播自然触发，无额外顺序约束：                               │
│    - Key Collection：检查钥匙拾取                                │
│    - Fog of War：update_vision()                                │
│    - Win Condition：收集 pending_openers                         │
│    - LLM Agent Integration：更新 last_move_direction，检查决策点  │
│    - Match Renderer / HUD：更新显示                              │
│                                                                 │
│  Phase 3 结束后（call_deferred / tick 末尾）：                    │
│    - Win Condition：批量判定 pending_openers → finish_match()    │
│    - LLM Agent Integration：检测"新目标可见"决策点触发            │
└─────────────────────────────────────────────────────────────────┘
```

**实现约束**：

- **Phase 1 → Phase 2 顺序保证**：Match State Manager 发出的 `tick` 信号中，LLM Agent Integration 的连接必须先于 Grid Movement 的连接。实现方式：使用 Godot 的 `connect()` 调用顺序（先连接 LLM Agent，后连接 Grid Movement），或使用两个分离信号（`tick_decision` → `tick_execute`）
- **Phase 3 即时 handler 无强制顺序依赖**：Key Collection、Fog of War 等系统对 `mover_moved` 的即时 handler 互不依赖，可以任意顺序执行。**依赖最新全局状态的判定统一 deferred 到 tick 末尾**：Win Condition 的 `pending_openers` 批量判定和 LLM Agent Integration 的"新目标可见"检测均使用 `call_deferred`，确保 Phase 3 的所有即时 handler（包括 FoW 视野更新、Key Collection 钥匙拾取）处理完毕后再执行
- **决策与移动的 tick 对齐**：LLM Agent Integration 在 Phase 1 写入的方向在**同一 tick 的 Phase 2** 被消费，不存在 1-tick 延迟。这保证了"本 tick 决策，本 tick 生效"的确定性行为

### Data Structures

```
enum MoveDirection { NORTH, EAST, SOUTH, WEST, NONE }

Mover:
  id: int                          # 0 = Agent A, 1 = Agent B
  position: Vector2i               # 当前网格坐标
  pending_direction: MoveDirection  # 待执行的方向（同一 tick Phase 2 消费，NONE = 不动）
  visited_cells: Array<Vector2i>   # 已访问过的 cell 坐标（有序，含重复访问则不重复记录）
  total_moves: int                 # 实际成功移动的次数
  blocked_count: int               # 撞墙次数

GridMovementManager:
  movers: Array<Mover>             # 所有移动实体
  maze: MazeData                   # 迷宫数据引用（只读）
  fog: FogOfWar                    # 迷雾系统引用（仅 initialize() 时使用，运行时不调用）

  # --- 信号 ---
  signal mover_moved(mover_id, old_pos, new_pos)    # 成功移动后发出
  signal mover_blocked(mover_id, pos, direction)     # 撞墙后发出
  signal mover_stayed(mover_id, pos)                 # pending 为 NONE，原地不动

  # --- 外部输入接口 ---
  set_direction(mover_id, direction: MoveDirection)  # 设置移动方向（同一 tick Phase 2 消费）

  # --- 查询接口 ---
  get_position(mover_id) -> Vector2i
  get_visited_cells(mover_id) -> Array<Vector2i>
  has_visited(mover_id, pos: Vector2i) -> bool
  get_total_moves(mover_id) -> int
  get_blocked_count(mover_id) -> int

  # --- 生命周期 ---
  initialize()                       # 从已持有的 maze/fog 引用读取 spawn 点，创建 Mover，记录初始位置，调用 fog.update_vision() 触发初始视野
  reset()                          # 清空所有 Mover 数据
```

### Tick Processing Flow

```
on_tick(tick_count):
  # Phase 1: 处理所有 Mover 的移动，收集结果
  var results = []
  for mover in movers:
    dir = mover.pending_direction
    mover.pending_direction = NONE

    if dir == NONE:
      results.append({type: "stayed", mover: mover})
      continue

    if maze.can_move(mover.position.x, mover.position.y, dir):
      old_pos = mover.position
      mover.position = old_pos + direction_to_offset(dir)
      mover.total_moves += 1
      if mover.position not in mover.visited_cells:
        mover.visited_cells.append(mover.position)
      results.append({type: "moved", mover: mover, old_pos: old_pos, new_pos: mover.position})
    else:
      mover.blocked_count += 1
      results.append({type: "blocked", mover: mover, dir: dir})

  # Phase 2: 所有 Mover 处理完毕后，批量发出信号
  for result in results:
    match result.type:
      "stayed":  emit mover_stayed(result.mover.id, result.mover.position)
      "moved":   emit mover_moved(result.mover.id, result.old_pos, result.new_pos)
      "blocked": emit mover_blocked(result.mover.id, result.mover.position, result.dir)
```

### Direction Offset Mapping

```
NORTH -> (0, -1)    # Y 轴向下，所以 North 是 y-1
EAST  -> (1, 0)
SOUTH -> (0, 1)
WEST  -> (-1, 0)
NONE  -> (0, 0)
```

### Initialization Flow

```
initialize():
  # maze 和 fog 为构造时注入的引用（Godot @export 或 @onready），已在场景就绪时绑定
  for mover in movers:
    var spawn_marker = SPAWN_A if mover.id == 0 else SPAWN_B
    mover.position = maze.get_marker_position(spawn_marker)
    mover.visited_cells.append(mover.position)
    mover.pending_direction = NONE
    mover.total_moves = 0
    mover.blocked_count = 0

  # 初始视野计算：所有 Mover 就位后，通知 FoW 刷新每个 Mover 的视野
  for mover in movers:
    fog.update_vision(mover.id, mover.position)
```

**设计说明**：

- **依赖注入**：`maze` 和 `fog` 引用在场景就绪时绑定（Godot `@export` 节点引用或 `@onready` 场景树查找），`initialize()` 从已持有的引用读取，无需参数传入。这与 LLM Agent Integration 持有 `maze`, `movement`, `fog` 引用的模式一致
- **初始化顺序**：初始视野计算放在 `initialize()` 末尾而非由 FoW 自行监听 `state_changed(COUNTDOWN)`，是因为 FoW 的 `update_vision()` 依赖 Mover 已经就位——如果 FoW 先于 Grid Movement 处理 COUNTDOWN 信号，Mover 位置还是 `(-1, -1)`。由 Grid Movement 在就位后主动通知 FoW，保证了正确的初始化顺序

### Interactions with Other Systems

| System | Direction | Interface | Data Flow |
|--------|-----------|-----------|-----------|
| **Match State Manager** | Manager -> Movement | `tick` 信号 | 每 tick 触发一次移动处理 |
| **Match State Manager** | Manager -> Movement | `state_changed` 信号 | COUNTDOWN 时初始化 Mover 位置；非 PLAYING 状态忽略移动 |
| **Maze Data Model** | Movement -> Model | `can_move()` | 查询移动方向是否可通行 |
| **Maze Data Model** | Movement -> Model | `get_marker_position(SPAWN_A/B)` | 初始化时读取起始位置 |
| **LLM Agent Integration** | Agent -> Movement | `set_direction(mover_id, dir)` | LLM 决策后写入移动方向 |
| **Key Collection** | Keys -> Movement | 监听 `mover_moved` 信号 | 每次移动后检查新位置是否有钥匙 |
| **Fog of War** | Movement → FoW（初始化）| `FoW.update_vision(mover_id, pos)` 直接调用 | `initialize()` 完成后为每个 Mover 调用，触发初始视野计算（此时无 `mover_moved` 信号可监听） |
| **Fog of War** | FoW → Movement（运行时）| 监听 `mover_moved` 信号 | FoW 自行监听 `mover_moved`，在 handler 中调用 `update_vision(agent_id, new_pos)` 更新视野。Grid Movement 不在运行时主动调用 FoW |
| **Win Condition** | WinCon -> Movement | 监听 `mover_moved` 信号 | 检查是否到达宝箱位置 |
| **Match Renderer** | Renderer -> Movement | `get_position()`, 监听 `mover_moved` | 渲染 Agent 位置和移动动画 |
| **LLM Information Format** | LLMFormat -> Movement | `get_visited_cells()`, `get_position()` | 将移动历史和当前位置序列化给 LLM |
| **Match HUD** | HUD -> Movement | `get_total_moves()` | 显示移动统计 |
| **Player Input（未来）** | Input -> Movement | `set_direction(mover_id, dir)` | 玩家按键转换为方向写入 |

## Formulas

### Position Update

```
new_position = old_position + direction_to_offset(direction)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| old_position | Vector2i | (0,0) to (width-1, height-1) | Mover.position | 移动前坐标 |
| direction | MoveDirection | NORTH/EAST/SOUTH/WEST | pending_direction | 移动方向 |
| new_position | Vector2i | (0,0) to (width-1, height-1) | 计算结果 | 移动后坐标 |

前置条件：`MazeData.can_move(old_position.x, old_position.y, direction) == true`。如果前置条件不满足，不执行计算，position 不变。

### Exploration Rate

```
exploration_rate = visited_cells.size() / total_reachable_cells
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| visited_cells.size() | int | 1 to total_reachable_cells | Mover.visited_cells | 已访问的不同 cell 数量 |
| total_reachable_cells | int | 1 to width * height | `MazeData.width * MazeData.height`（finalized 迷宫保证完全连通，所有 cell 均可达） | 迷宫中可达的 cell 总数 |
| exploration_rate | float | 0.0 to 1.0 | 计算结果 | 探索完成率（供 Result Screen 展示） |

### Movement Efficiency

```
efficiency = optimal_path_length / total_moves
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| optimal_path_length | int | 1+ | `MazeData.get_shortest_path(start, goal).size() - 1`（路径数组包含起点和终点，步数 = 节点数 - 1） | 起点到目标的最短路径步数 |
| total_moves | int | 1+ | Mover.total_moves | 实际成功移动的总步数 |
| efficiency | float | 0.0 to 1.0 | 计算结果 | 1.0 = 完美路径，越低越多冗余移动 |

注意：efficiency > 1.0 理论上不可能（除非目标在移动过程中改变）。efficiency 在 Agent 还未到达目标时无意义，仅用于赛后统计。未到达目标的 Agent（超时/平局）efficiency 显示为 `N/A`，由 Result Screen 负责处理。`total_moves == 0` 时 efficiency 未定义，同样显示为 `N/A`。

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| LLM 未在 tick 内响应（`pending_direction` 仍为 `NONE`） | Mover 原地不动，发出 `mover_stayed` 信号，消耗一个 tick | tick 是全局心跳，不为任何 Agent 暂停。这也是 prompt 质量的一部分——好的 prompt 应让 LLM 快速决策 |
| LLM 返回非法方向（撞墙） | Mover 原地不动，`blocked_count += 1`，发出 `mover_blocked` 信号，消耗一个 tick | 不重试、不回退。撞墙是 LLM 的错误决策，应被记录并反映在效率统计中 |
| 同一 tick 内 `set_direction()` 被调用多次 | 以最后一次写入为准 | 简单的覆盖语义，避免队列复杂性。实际场景中不太可能发生（一个 tick 内只有一个决策源） |
| `set_direction()` 在非 PLAYING 状态被调用 | `pending_direction` 被写入但不会被消费（tick 不触发），下次进入 PLAYING 时会被首个 tick 消费 | 防御性设计——不拒绝写入，但执行仍严格依赖状态 |
| `initialize()` 时 MazeData 中缺少 SPAWN_A 或 SPAWN_B | 打印错误日志，将缺失的 Mover 位置设为 `Vector2i(-1, -1)`（未初始化标记值），与 `reset()` 后的状态一致。该 Mover 在 PLAYING 阶段的任何移动都将因坐标越界被 `can_move()` 拒绝 | 不崩溃，保持与 MazeData 的 `get_marker_position()` 返回值一致（缺失标记返回 `(-1, -1)`）。不伪造合法坐标，避免掩盖 Maze Generator 的 bug（`is_valid()` 应已拦截） |
| Mover 已在边界 cell，尝试向边界外移动 | `MazeData.can_move()` 返回 `false`（边界墙始终存在），与普通撞墙处理一致 | 边界由 Maze Data Model 保证，Grid Movement 不需要额外检查 |
| `mover_id` 越界（如传入 `set_direction(5, NORTH)`） | 操作被忽略，打印警告日志 `"Invalid mover_id: 5"` | 防御性编程，不崩溃 |
| 两个 Mover 同一 tick 移动到同一 cell | 正常处理，两个 `mover_moved` 信号分别发出 | 无碰撞机制，Mover 之间互不可见 |
| 同一 tick 内两个 Mover 同时到达宝箱（或同时满足胜利条件） | Grid Movement 先完成两者的位置更新，再批量发出 `mover_moved` 信号。Win Condition 收到两个信号后判定为 `DRAW`，调用 `finish_match(DRAW, -1)` | Tick 原子性（Core Rule #8）保证了下游系统看到的是一个 tick 结束后的完整快照，而非中间状态。公平性由此保证 |
| 比赛结束（FINISHED）后仍有 `pending_direction` 残留 | 不消费，`reset()` 时清空 | tick 停止后不再处理移动 |
| `reset()` 后立即查询 `get_position()` | 返回 `Vector2i(-1, -1)`（未初始化标记值） | reset 清空所有状态，需要重新 `initialize()` 才有有效数据 |
| 超大迷宫（50x50）中 tick 处理时间 | 每 tick 处理 2 个 Mover，每个 1 次 `can_move()` 调用 + 1 次 visited_cells 查找。visited_cells 查找为 O(v)（v = 已访问 cell 数），最坏情况 v = 2500（50x50 全探索），仍远低于 1ms | 实现时建议用 Dictionary/Set 替代 Array 存储 visited_cells 以获得 O(1) 查找。即使用 Array，MVP 规模下性能无忧 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Maze Data Model** | Grid Movement depends on this | 查询 `can_move()` 验证通行性，查询 `get_marker_position(SPAWN_A/B)` 获取初始位置 |
| **Match State Manager** | Grid Movement depends on this | 监听 `tick` 信号驱动移动处理，监听 `state_changed(_, COUNTDOWN)` 信号触发 `initialize()` 完成 Mover 就位，监听 `state_changed` 信号管理生命周期（PLAYING 执行、FINISHED 停止） |
| **LLM Agent Integration** | Agent depends on this | 调用 `set_direction()` 写入 LLM 决策结果 |
| **Key Collection** | Keys depends on this | 监听 `mover_moved` 信号，检查新位置是否有可拾取的钥匙 |
| **Fog of War / Vision** | FoW depends on this（运行时）；Grid Movement depends on FoW（仅初始化） | **运行时**：FoW 监听 `mover_moved` 信号，自行调用 `update_vision()` 更新可见区域——Grid Movement 不主动调用 FoW。**初始化时**：Grid Movement 的 `initialize()` 直接调用 `FoW.update_vision()` 触发初始视野，因为此时无 `mover_moved` 信号。这是 Grid Movement 对 FoW 的唯一依赖点 |
| **Win Condition / Chest** | WinCon depends on this | 监听 `mover_moved` 信号检查是否到达宝箱 |
| **Match Renderer** | Renderer depends on this | 监听 `mover_moved` / `mover_blocked` 信号播放移动/撞墙动画，查询 `get_position()` 渲染 Agent 位置 |
| **LLM Information Format** | LLMFormat depends on this | 查询 `get_position()` 和 `get_visited_cells()` 序列化 Agent 状态给 LLM |
| **Match HUD** | HUD depends on this | 查询 `get_total_moves()` / `get_blocked_count()` 显示移动统计 |
| **Result Screen** | Result depends on this | 赛后查询统计数据（total_moves、blocked_count、visited_cells）及计算 exploration_rate 和 efficiency 展示比赛回顾 |
| **Player Input（未来）** | Input depends on this | 将玩家按键转换为 `set_direction()` 调用 |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `mover_count` | 2 | 2 - 4 | 支持更多同场竞技的 Agent（未来多人模式） | 最低 2（1v1 是核心玩法） |
| `visited_cells_tracking` | true | true / false | 启用移动历史记录，供 LLM Information Format 和 Fog of War 使用 | 关闭则节省内存，但下游系统失去已访问信息（不推荐） |

**注意事项**：

- Grid Movement 的"速度"不由本系统控制——它由 Match State Manager 的 `tick_interval` 决定（每 tick 一步是固定规则，不可调）
- 迷宫大小影响移动的"意义"（大迷宫每步更重要），但这是 Maze Data Model 的参数
- 如果未来需要不同 Mover 有不同移动速度（如道具加速），需要扩展为 per-Mover 的 `moves_per_tick` 参数，但 MVP 不需要
- 所有值必须从配置文件读取，禁止硬编码

## Visual/Audio Requirements

Grid Movement 本身是逻辑系统，不直接产生视觉或音频输出。以下需求由下游系统消费本系统的信号来实现：

| Event | Visual Feedback | Audio Feedback | Priority | Responsible System |
|-------|----------------|---------------|----------|--------------------|
| 成功移动（`mover_moved`） | Agent 精灵从旧格滑动到新格（补间动画） | 可选：轻微脚步音效 | MVP | Match Renderer |
| 撞墙（`mover_blocked`） | Agent 精灵轻微抖动 / 墙壁闪烁 | 可选：低沉碰撞音效 | MVP | Match Renderer |
| 原地不动（`mover_stayed`） | 无视觉反馈（Agent 保持静止） | 无 | MVP | Match Renderer |
| 初始化就位（`initialize`） | Agent 精灵出现在 spawn 点 | 无 | MVP | Match Renderer |

## Acceptance Criteria

- [ ] `initialize()` 后，Mover A 的位置等于 `MazeData.get_marker_position(SPAWN_A)`，Mover B 同理
- [ ] `initialize()` 后，两个 Mover 的 `visited_cells` 各包含自己的起始位置
- [ ] `initialize()` 后，`fog.update_vision()` 已为每个 Mover 调用，Spawn 周围 vision_radius 范围内的 cell 为 VISIBLE（非全黑）
- [ ] `set_direction(0, EAST)` 后，同一 tick 内 Mover 0 向东移动一格（若可通行）
- [ ] 向可通行方向移动后，`position` 正确更新，`total_moves` 递增 1
- [ ] 向可通行方向移动后，发出 `mover_moved(id, old_pos, new_pos)` 信号，坐标正确
- [ ] 向有墙方向移动后，`position` 不变，`blocked_count` 递增 1
- [ ] 向有墙方向移动后，发出 `mover_blocked(id, pos, direction)` 信号
- [ ] `pending_direction` 为 `NONE` 时，Mover 原地不动，发出 `mover_stayed(id, pos)` 信号
- [ ] 每次 tick 处理后，`pending_direction` 被重置为 `NONE`
- [ ] 同一 tick 内多次 `set_direction()` 调用，以最后一次为准
- [ ] 两个 Mover 可以同时占据同一 cell，各自独立发出信号
- [ ] `visited_cells` 不包含重复坐标——重复访问同一 cell 不重复记录
- [ ] `has_visited(mover_id, pos)` 对已访问坐标返回 `true`，未访问返回 `false`
- [ ] 仅在 `PLAYING` 状态下 tick 信号触发移动处理；其他状态下 tick 不触发移动
- [ ] `reset()` 后所有 Mover 的 position、visited_cells、total_moves、blocked_count 全部清空
- [ ] `mover_id` 越界时 `set_direction()` 和查询接口不崩溃，打印警告日志
- [ ] Direction offset 映射正确：NORTH=(0,-1), EAST=(1,0), SOUTH=(0,1), WEST=(-1,0)
- [ ] Performance: 50x50 迷宫中 2 个 Mover 的单次 tick 处理在 1ms 内完成
- [ ] Tick 原子性：同一 tick 内所有 Mover 的位置更新在信号发出之前全部完成，下游系统收到信号时看到的是该 tick 结束后的完整快照

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| 未来多人模式（3-4 个 Mover）时，tick 内的处理顺序是否影响公平性？是否需要随机化 Mover 处理顺序？ | Game Designer | Core 阶段 | MVP 固定 2 个 Mover，顺序无影响（同 cell 无碰撞）。Core 阶段评估 |
| 是否需要移动动画与逻辑解耦？即逻辑层立即更新坐标，渲染层异步播放补间动画 | Technical Director | Sprint 1 | 待定——建议逻辑与渲染解耦，但需在实现阶段验证 Godot 信号时序 |
