# LLM Agent Integration

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-03
> **System Index**: #9
> **Layer**: Feature
> **Implements Pillar**: Human-AI Symbiosis, Simple Rules Deep Play

## Overview

LLM Agent Integration 是连接 LLM API 与游戏运行时的**决策引擎**。它为每个 Agent 维护一个独立的决策循环：在需要决策时（岔路口、死胡同、队列耗尽、新目标出现），向 LLM API 发送由 LLM Information Format 构建的 prompt，接收 LLM 返回的响应并通过 `parse_response()` 解析为 `ParseResult`（目标坐标优先，单步方向降级，解析失败为 NONE）。目标坐标通过 Maze Data Model 的 A* 寻路生成路径队列（path queue），每个 tick 从队列中消费一步交给 Grid Movement 执行。

本系统的关键设计决策是**路径队列 + 智能触发**模式：LLM 不需要每个 tick 都做决策，而是返回一个目标坐标，系统自动规划路径并连续执行。Agent 在直道上自动前进（不消耗 API 调用），只在到达决策点时才请求新的 LLM 决策。新的 API 请求在到达决策点时**预发起**，Agent 继续沿旧路径行进，API 响应到达后用新路径替换旧队列——这确保 Agent 全程保持移动，几乎不会因为 API 延迟而停顿。

本系统使用 OpenAI 兼容 API 格式（覆盖 GPT、Claude via proxy、本地 Ollama 等），玩家自带 API Key。每次 API 调用只发送 system message + 当前 state message（无历史累积），依赖 LLM Information Format 中已包含的 visited cells 和 explored cells 提供"记忆"。API 超时或错误不重试，等同于返回无效响应（Agent 在队列耗尽后原地等待直到下次成功响应）。

## Player Fantasy

**对于 prompt 策略师（Agent vs Agent 模式）**：比赛开始，你的 Agent 从起点冲了出去——它沿着走廊快速移动，到达第一个 T 字路口时稍微停顿了一下，然后果断选择了右边。你紧盯着屏幕：右边果然通向第一把钥匙。你的 prompt 里写了"优先探索未访问的方向，如果看到钥匙立刻前往"，它真的在执行你的策略。而对面的 Agent 在另一个岔路口犹豫了两个 tick 才动——那是 API 延迟，还是对手的 prompt 让它"想"太多了？每一次流畅的转弯都是你 prompt 质量的证明，每一次停顿都可能意味着对手的 LLM 在挣扎。这不是你在操控角色——是你写的文字在替你竞赛。

**对于系统设计者**：LLM Agent Integration 是"Human-AI Symbiosis"支柱的执行层。LLM Information Format 负责"让 LLM 看懂地图"，本系统负责"让 LLM 的决策变成行动"。路径队列机制让 Agent 看起来像一个有自主意识的探索者——在走廊中快速奔跑，在岔路口短暂思考，发现钥匙后立即改变方向。玩家看到的不是一个"每秒请求一次 API 的机器人"，而是一个"被 prompt 赋予性格的智能体"。好的 prompt 让它果断高效，差的 prompt 让它犹豫不决——这种差异就是游戏的乐趣来源。

## Detailed Design

### Core Rules

1. LLM Agent Integration 为每个 Agent 维护一个独立的 **AgentBrain**，包含：路径队列（path_queue）、API 请求状态（in-flight / idle）、LLM 会话配置（API endpoint, key, model）
2. 每个 tick，系统对每个 AgentBrain 执行以下逻辑（按优先级）：
   - 若有 API 响应刚到达 → 解析目标坐标，从当前位置 A* 寻路生成新 path_queue，替换旧队列
   - 若 path_queue 非空 → 消费队头方向，调用 `GridMovement.set_direction()`
   - 若 path_queue 为空且当前位置是直道 → 自动前进（不消耗 API）
   - 若 path_queue 为空且当前位置是决策点且无 in-flight 请求 → 发起 API 请求，原地等待
   - 若 path_queue 为空且有 in-flight 请求 → 原地等待
3. 移动执行后，检查当前位置是否为**决策点**（见下方定义）。若是且当前无 in-flight 请求 → 预发起新 API 请求（不清空队列，Agent 继续走旧路径）
4. API 响应到达时，从 Agent **当前位置**（非请求发起时的位置）到新目标重新 A* 寻路，生成的路径**替换**旧队列
5. 每次 API 调用只发送两条消息：system message（固定）+ state message（当前 tick 的状态），无历史累积
6. 使用 OpenAI 兼容的 Chat Completions API 格式，通过 Godot HTTPRequest 节点发送
7. API 超时或错误不重试，等同于无效响应——不更新队列，Agent 按现有队列/自动前进/原地等待继续运行

### 决策点定义

一个 cell 在以下任一条件满足时被视为**决策点（Decision Point）**：

| 条件 | 说明 | 示例 |
|------|------|------|
| 岔路口 | 除来路方向外，可通行方向 ≥ 2 | T 字路口、十字路口 |
| 死胡同 | 可通行方向 = 1（只有来路） | 走廊尽头 |
| 新目标可见 | 视野内出现了之前不可见的钥匙或宝箱 | 走着走着看到了钥匙 |

**"新目标可见"检测机制**：LLM Agent Manager 监听 Key Collection 的 `key_activated(key_type)` 信号和 `chest_unlocked(agent_id)` 信号。收到信号后，检查新目标的位置是否在该 Agent 当前 visible cells 中（调用 `FoW.get_cell_visibility(agent_id, x, y) == VISIBLE`）。若在视野内，视为决策点触发，预发起 API 请求。若不在视野内，不触发——Agent 继续当前路径，直到移动导致新目标进入视野或到达其他决策点时自然触发。此外，每次 `mover_moved` 后更新视野时，系统比较更新前后的 visible cells 中的标记差异：若新增了当前目标钥匙或宝箱的可见性（之前不在任何 visible cell 中，现在出现在某个 visible cell 中），同样视为决策点触发。
| 撞墙 | path_queue 头部方向不可通行 | LLM 给的路径有误 |

**非决策点（直道）**：除来路方向外，可通行方向 = 1。系统自动沿唯一方向前进。

### 路径队列机制

```
AgentBrain:
  path_queue: Array<MoveDirection>    # 待执行的方向队列
  last_move_direction: MoveDirection  # 上一步的移动方向（用于判断"来路"）

consume_queue(brain: AgentBrain) -> MoveDirection:
  if brain.path_queue.is_empty():
    return NONE
  return brain.path_queue.pop_front()

replace_queue(brain: AgentBrain, target: Vector2i):
  var current_pos = GridMovement.get_position(brain.agent_id)
  var path = MazeData.get_shortest_path(current_pos, target)
  if path.size() < 2:
    # 目标不可达或已在目标位置
    brain.path_queue.clear()
    return
  # path 包含起点和终点，转换为方向序列
  brain.path_queue.clear()
  for i in range(path.size() - 1):
    var dir = offset_to_direction(path[i+1] - path[i])
    brain.path_queue.append(dir)
```

### 直道自动前进

```
get_auto_direction(pos: Vector2i, last_dir: MoveDirection) -> MoveDirection:
  var reverse = opposite(last_dir)         # 来路的反方向
  # get_open_directions: 遍历 4 个方向调用 MazeData.can_move() 组装
  var open_dirs = []
  for dir in [NORTH, EAST, SOUTH, WEST]:
    if MazeData.can_move(pos.x, pos.y, dir):
      open_dirs.append(dir)
  var forward_dirs = open_dirs.filter(d -> d != reverse)

  if forward_dirs.size() == 1:
    return forward_dirs[0]                 # 直道：唯一前进方向
  return NONE                              # 非直道：需要决策
```

特殊情况：Agent 初始位置（比赛刚开始，`last_dir = NONE`）不视为直道，必须请求 LLM 决策。

### API 调用流程

```
┌─────────────────────────────────────────────────────────┐
│  发起请求                                                │
│  1. 调用 LLMInfoFormat.build_system_message(prompt)      │
│  2. 调用 LLMInfoFormat.build_state_message(agent_id)     │
│  3. 构建 HTTP 请求体（OpenAI Chat Completions 格式）       │
│  4. 通过 HTTPRequest 发送 POST 请求                       │
│  5. 标记 brain.request_state = IN_FLIGHT                 │
├─────────────────────────────────────────────────────────┤
│  收到响应                                                │
│  1. 解析 HTTP 响应，提取 LLM 文本内容                      │
│  2. 调用 LLMInfoFormat.parse_response(text)               │
│     → 返回 ParseResult: TARGET(pos) / DIRECTION(dir) / NONE │
│  3. TARGET: 从当前位置 A* 寻路到 pos，生成 path_queue       │
│     DIRECTION: 生成长度为 1 的 path_queue                   │
│     NONE: 不更新 path_queue                                │
│  4. 标记 brain.request_state = IDLE                      │
├─────────────────────────────────────────────────────────┤
│  超时 / 错误                                             │
│  1. 记录错误日志                                          │
│  2. 标记 brain.request_state = IDLE                      │
│  3. 不更新 path_queue（Agent 按现有状态继续）               │
└─────────────────────────────────────────────────────────┘
```

### LLM Response Format

LLM 返回目标坐标，系统自动寻路：

```
# 主要格式：目标坐标
{"target": [x, y]}

# 降级格式：单方向（兼容旧格式）
{"direction": "NORTH"}
```

解析优先级：
1. 若 JSON 包含 `target` 字段 → 提取坐标，A* 寻路生成路径
2. 若 JSON 包含 `direction` 字段 → 单步方向，path_queue 长度为 1
3. 均无 → 返回 NONE

目标坐标验证：
- 坐标必须在迷宫范围内：`0 <= x < width, 0 <= y < height`
- 坐标必须在 visible 或 explored 区域内（不允许指向 unknown cell）
- 坐标必须可达（A* 能找到路径）
- 不允许指向当前位置（原地不动无意义）
- 任何验证失败 → 等同于 NONE

**A* 寻路范围决策**：A* 在**完整迷宫**上运行（使用 `MazeData.get_shortest_path()`），而非仅在已知区域上运行。虽然 Agent 的 FoW 限制了它"看到"的范围，但路径规划使用完整墙壁数据。这本质上是"自动行走"功能——LLM 负责做高层决策（去哪里），系统负责底层执行（怎么走过去），与玩家在 RTS 游戏中点击目标后单位自动寻路相同。目标坐标已限制在 visible/explored 区域内，因此 LLM 无法指向它不知道的地方，公平性由目标验证保证而非寻路范围保证。

### Data Structures

```
enum RequestState { IDLE, IN_FLIGHT }

AgentBrain:
  agent_id: int                        # 对应的 mover_id（0 = A, 1 = B）
  path_queue: Array<MoveDirection>     # 待执行的方向队列
  last_move_direction: MoveDirection   # 上一步的移动方向
  request_state: RequestState          # API 请求状态
  pending_response: String             # 最新的待处理 API 响应文本（null = 无）。HTTPRequest 回调中写入，on_tick() 开始时检查并消费

  # --- API 配置 ---
  api_endpoint: String                 # OpenAI 兼容 API 地址
  api_key: String                      # API Key
  model: String                        # 模型名称（如 "gpt-4o", "claude-3-sonnet"）
  api_timeout: float                   # 请求超时时间（秒）

  # --- 会话数据 ---
  system_message: String               # 比赛开始时构建，全程不变
  total_api_calls: int                 # API 调用总次数（统计用）
  total_tokens_used: int               # 累计 token 使用量（从 API 响应的 usage 字段读取）
  total_idle_ticks: int                # Agent 因等待 API 而原地不动的 tick 数

LLMAgentManager:
  brains: Array<AgentBrain>            # 每个 Agent 一个 Brain
  info_format: LLMInformationFormat    # 信息格式转换器引用
  maze: MazeData                       # 迷宫数据引用
  movement: GridMovementManager        # 移动管理器引用
  fog: FogOfWar                        # 迷雾系统引用

  # --- 信号 ---
  signal api_request_sent(agent_id)           # API 请求发出
  signal api_response_received(agent_id)      # API 响应收到
  signal api_error(agent_id, error_type)      # API 错误
  signal decision_made(agent_id, target_pos)  # LLM 做出决策（目标坐标）
  signal auto_advance(agent_id, direction)    # 直道自动前进

  # --- 生命周期 ---
  initialize(config: MatchConfig)      # 赛前初始化：创建 Brain，构建 system message
  on_tick(tick_count: int)             # 每 tick 的核心处理逻辑
  reset()                             # 清空所有 Brain 数据

  # --- 查询接口 ---
  get_brain(agent_id) -> AgentBrain
  get_api_call_count(agent_id) -> int
  get_idle_tick_count(agent_id) -> int
```

### Interactions with Other Systems

| System | Direction | Interface | Data Flow |
|--------|-----------|-----------|-----------|
| **Match State Manager** | MSM → Agent | `tick` 信号 | 每 tick 触发 `on_tick()`，驱动决策循环 |
| **Match State Manager** | MSM → Agent | `state_changed` 信号 | COUNTDOWN 时调用 `initialize()`；FINISHED 时取消 in-flight 请求 |
| **LLM Information Format** | Agent → Format | `build_system_message()`, `build_state_message()`, `parse_response()` | 构建 prompt 和解析响应 |
| **Grid Movement** | Agent → Movement | `set_direction(mover_id, dir)` | 每 tick 将队列消费的方向或自动前进方向写入 |
| **Grid Movement** | Movement → Agent | `mover_moved` 信号 | 移动成功后更新 `last_move_direction`，检查是否为决策点 |
| **Grid Movement** | Movement → Agent | `mover_blocked` 信号 | 撞墙 → 清空 path_queue，发起新 API 请求 |
| **Maze Data Model** | Agent → Model | `get_shortest_path()`, `can_move()` | A* 寻路和决策点判断（通过遍历 4 方向 `can_move()` 获取可通行方向列表） |
| **Fog of War** | Agent → FoW | `get_cell_visibility(agent_id, x, y)`, `get_visible_cells(agent_id)` | 验证目标坐标在已知区域内；检查新目标是否出现在视野中 |
| **Key Collection** | Keys → Agent | `key_collected` 信号 | 收集钥匙后，下一个目标变更 → 可能触发新 API 请求 |
| **Match HUD** | HUD → Agent | `get_api_call_count()`, `get_idle_tick_count()` | 显示 API 调用统计 |
| **Result Screen** | Result → Agent | `get_api_call_count()`, `total_tokens_used` | 赛后统计展示 |

## Formulas

### API 调用频率估算

```
api_calls_per_match ≈ decision_points_encountered * 2
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| decision_points_encountered | int | 10 - 100 | 迷宫结构决定 | 一个 Agent 在一场比赛中遇到的决策点总数 |
| api_calls_per_match | int | 20 - 200 | 计算结果（两个 Agent） | 一场比赛的 API 调用总次数 |

**典型估算**：15x15 迷宫，约 30-50 个岔路口/死胡同，每个 Agent 遇到约 20-40 个决策点 → 一场比赛约 40-80 次 API 调用。对比旧方案（每 tick 一次）：200 tick × 2 Agent = 400 次调用，**减少约 80%**。

### Token 成本估算

```
total_tokens = (system_tokens + avg_state_tokens + avg_response_tokens) * api_calls_per_match
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| system_tokens | int | ~200 | LLM Information Format | System Message 固定 token 数 |
| avg_state_tokens | int | 100 - 300 | LLM Information Format | State Message 平均 token 数 |
| avg_response_tokens | int | ~15 | LLM 返回 | `{"target": [8, 5]}` 约 10-20 tokens |
| api_calls_per_match | int | 40 - 80 | 上方估算 | 一场比赛的 API 调用总次数 |
| total_tokens | int | 12,600 - 41,200 | 计算结果 | 一场比赛总 token 消耗 |

**典型估算**：60 次调用 × (200 + 200 + 15) = 24,900 tokens/场。对比旧方案 166,000 tokens/场，**减少约 85%**。

### Agent 等待率

```
idle_rate = total_idle_ticks / total_ticks
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| total_idle_ticks | int | 0+ | AgentBrain.total_idle_ticks | Agent 因等待 API 而原地不动的 tick 数 |
| total_ticks | int | 1+ | Match State Manager | 比赛总 tick 数 |
| idle_rate | float | 0.0 - 1.0 | 计算结果 | Agent 空转比例。理想值 < 0.1（不到 10% 时间在等待） |

### 路径队列平均长度

```
avg_queue_length = total_queue_steps / total_api_calls
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| total_queue_steps | int | 0+ | 累计每次 replace_queue 生成的路径长度 | 所有 API 调用生成的路径步数总和 |
| total_api_calls | int | 1+ | AgentBrain.total_api_calls | API 调用总次数 |
| avg_queue_length | float | 1.0 - 20.0 | 计算结果 | 每次决策平均规划多少步。预期 3-8 步（受视野限制） |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 比赛开始第一个 tick（Agent 无移动历史，`last_dir = NONE`） | 不视为直道，发起 API 请求，原地等待响应 | 初始位置可能是岔路口也可能是走廊，但没有"来路"无法判断前进方向，必须让 LLM 做第一个决策 |
| LLM 返回的 target 坐标指向 unknown cell（迷雾未探索区域） | 验证失败，等同于 NONE。不更新 path_queue，标记 request_state = IDLE，下一个决策点重新请求 | 不允许 Agent 利用未知信息。LLM 只能指向 visible 或 explored 的 cell |
| LLM 返回的 target 是当前位置 `{"target": [5, 3]}`（Agent 就在 (5,3)） | 验证失败，等同于 NONE | 原地不动无意义，浪费一次 API 调用。LLM 应该选择一个要去的地方 |
| LLM 返回的 target 可达但路径很长（穿越大片 explored 区域，20+ 步） | 正常生成 path_queue。路径队列安全上限 `max_queue_length`（默认 20），超出部分截断 | 战争迷雾天然限制了路径长度，但 explored 区域可能很大。截断防止 Agent 执行基于过时信息的超长路径，截断点自然成为新决策点 |
| A* 寻路失败（target 在 explored 区域内但被墙壁完全包围，不可达） | 等同于 NONE。记录警告日志 | 理论上 finalized 迷宫保证完全连通，不应发生。防御性处理 |
| API 请求超时（超过 `api_timeout` 秒无响应） | 标记 request_state = IDLE，记录 `api_error` 信号。不更新 path_queue，Agent 按现有队列/自动前进/原地等待继续 | 不重试，不阻塞。超时是网络或 LLM 服务的问题，重试可能加剧延迟 |
| API 返回 HTTP 429（限流） | 与超时相同处理：标记 IDLE，记录错误，不更新队列 | 限流期间重试会恶化问题。Agent 继续走现有路径，下一个决策点自然触发新请求（此时限流可能已解除） |
| API 返回 HTTP 500 / 其他服务端错误 | 与超时相同处理 | 统一的错误处理策略：所有 API 失败都不重试 |
| API 返回格式正确但 JSON 解析失败（LLM 返回非 JSON 文本） | 由 LLM Information Format 的 `parse_response()` 处理，返回 NONE | 职责分离：解析逻辑在 LLM Information Format，本系统只消费解析结果 |
| 两个 Agent 的 API 请求同时发出 | 各自独立的 HTTPRequest 节点，互不阻塞。Godot 的 HTTPRequest 是异步的 | 每个 AgentBrain 有自己的 HTTPRequest 实例，完全独立 |
| 比赛结束（FINISHED）时仍有 in-flight API 请求 | 取消请求（HTTPRequest.cancel_request()），标记 IDLE，清空 path_queue | 比赛已结束，不需要消费响应。避免响应在下一场比赛中被错误处理 |
| Agent 在走旧路径的过程中收集了钥匙 | Key Collection 发出 `key_collected` 信号 → LLM Agent Manager 收到后，若当前无 in-flight 请求，发起新 API 请求（不清空队列）。新响应到达后替换队列 | 收集钥匙后目标改变（下一把钥匙或宝箱），需要让 LLM 基于新目标重新决策 |
| 直道自动前进走进了死胡同 | 死胡同是决策点 → 发起 API 请求，原地等待（队列为空，且非直道） | 死胡同只有来路一个方向，不属于"直道"（直道定义要求除来路外有恰好 1 个前进方向） |
| LLM 返回 `{"direction": "NORTH"}` 而非 target 坐标 | 降级处理：生成长度为 1 的 path_queue，执行单步移动。下一个 tick 重新评估是否需要决策 | 兼容旧格式，不惩罚使用单方向格式的 LLM。但效率较低（几乎每步都需要 API 调用） |
| 预发起的 API 请求还没回来，Agent 又到达了另一个决策点 | 不发起新请求（已有 in-flight）。Agent 继续走队列或自动前进。响应到达后从最新位置重新寻路 | 同一时间只允许一个 in-flight 请求，避免 API 浪费和响应竞争 |
| `api_key` 为空或无效 | 第一次 API 调用返回 401 错误 → 按 API 错误处理（标记 IDLE，不重试）。Agent 永远在原地等待或自动前进 | 不崩溃。可以在 SETUP 阶段由 UI 验证 API Key 有效性（非本系统职责） |
| 两个 Agent 使用不同的 LLM 提供商 / 模型 | 正常支持——每个 AgentBrain 有独立的 api_endpoint / api_key / model 配置 | 设计上就是每个 Agent 独立配置，允许 GPT vs Claude 的对战 |
| 网络完全断开 | 所有 API 请求超时 → Agent 永远在自动前进（直道）或原地等待（决策点）。比赛不崩溃，但 Agent 无法做有意义的决策，最终超时平局 | 容错优先。网络恢复后下一次请求自然成功 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **LLM Information Format** | Agent depends on this | 调用 `build_system_message()` 构建赛前固定 prompt，调用 `build_state_message()` 构建每次决策时的状态描述，调用 `parse_response()` 解析 LLM 返回的目标坐标或方向 |
| **Grid Movement** | Agent depends on this | 调用 `set_direction()` 写入每 tick 的移动方向（队列消费或自动前进）；监听 `mover_moved` 信号更新 `last_move_direction` 和检查决策点；监听 `mover_blocked` 信号触发重新决策 |
| **Match State Manager** | Agent depends on this | 监听 `tick` 信号驱动 `on_tick()` 决策循环；监听 `state_changed` 信号管理生命周期（COUNTDOWN 初始化，FINISHED 清理） |
| **Maze Data Model** | Agent depends on this | 调用 `get_shortest_path()` 执行 A* 寻路生成路径队列；调用 `get_open_directions()` 判断决策点；调用 `can_move()` 验证路径合法性 |
| **Fog of War** | Agent depends on this | 调用 `get_cell_visibility()` 验证 LLM 返回的目标坐标在已知区域（visible/explored）内；检测视野内新目标出现触发决策 |
| **Key Collection** | Agent depends on this | 监听 `key_collected` 信号，收集钥匙后触发新的 API 请求（目标可能改变） |
| **Win Condition / Chest** | WinCon depends on this（间接） | LLM Agent 的移动最终触发 Win Condition 检查（通过 Grid Movement 的 `mover_moved` 信号） |
| **Match HUD** | HUD depends on this | 查询 `get_api_call_count()` / `get_idle_tick_count()` 显示 API 调用和等待统计 |
| **Result Screen** | Result depends on this | 赛后查询 `total_api_calls` / `total_tokens_used` / `total_idle_ticks` 展示 AI 决策统计 |
| **Observer Communication（Core 阶段）** | Observer depends on this | 未来的观察者通信系统可能需要与 Agent 的决策循环协调（如观察者消息打断 Agent 队列） |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `api_timeout` | 10.0 | 3.0 - 30.0 | 允许更慢的 LLM 响应，减少超时错误，但 Agent 在首次请求时等待更久 | 更快放弃慢响应，Agent 更快恢复决策循环，但可能错过本可成功的响应 |
| `max_queue_length` | 20 | 5 - 50 | 允许 LLM 做更长距离的规划，减少 API 调用次数，但长路径可能基于过时信息 | 更频繁的决策点，Agent 行为更具反应性，但 API 调用次数增加 |
| `model` | "gpt-4o" | 任何 OpenAI 兼容模型名 | 更强的模型（如 gpt-4o）导航能力更好但更贵更慢；更快的模型（如 gpt-4o-mini）响应快但可能决策质量低 | — |
| `api_endpoint` | "https://api.openai.com/v1/chat/completions" | 任何 OpenAI 兼容 URL | — | 可指向本地 Ollama（http://localhost:11434/v1/chat/completions）实现零延迟零成本 |
| `temperature` | 0.3 | 0.0 - 1.0 | 更随机的决策，Agent 行为更不可预测，可能发现意外好路径，也可能做出更多错误决策 | 更确定性的决策，Agent 行为更稳定可预测，但可能陷入重复模式 |
| `max_tokens` | 50 | 20 - 200 | 允许 LLM 返回更长响应（如包含推理过程），但增加 token 成本 | 强制 LLM 简洁回答，节省 token，但可能截断有效 JSON |

**注意事项**：

- `api_timeout` 和 `temperature` 是影响 Agent 行为最直观的参数。timeout 影响"Agent 停顿多久"，temperature 影响"Agent 有多果断"
- `model` 允许玩家选择不同模型进行对战，这本身就是游戏趣味点之一（便宜快速模型 vs 昂贵智能模型）
- 两个 Agent 的所有参数独立配置——允许一个用 GPT-4o 另一个用 Claude 3.5 Sonnet
- 所有值必须从配置文件读取，禁止硬编码

## Acceptance Criteria

### 路径队列与移动
- [ ] 比赛开始后第一个 tick，Agent 发起 API 请求并原地等待
- [ ] API 响应包含合法 target 坐标时，从当前位置 A* 寻路生成 path_queue
- [ ] 每个 tick 从 path_queue 头部消费一个方向，调用 `GridMovement.set_direction()`
- [ ] path_queue 消费完毕后，若当前位置是直道，自动沿唯一前进方向移动（不调用 API）
- [ ] path_queue 消费完毕后，若当前位置是决策点且无 in-flight 请求，发起新 API 请求
- [ ] path_queue 长度超过 `max_queue_length` 时，截断至该上限

### 决策点检测
- [ ] 岔路口（除来路外可通行方向 ≥ 2）正确识别为决策点
- [ ] 死胡同（可通行方向 = 1）正确识别为决策点
- [ ] 直道（除来路外可通行方向 = 1）正确识别为非决策点，自动前进
- [ ] 视野内新出现钥匙或宝箱时触发决策点
- [ ] 撞墙时（`mover_blocked` 信号）清空 path_queue 并触发新 API 请求

### 预发起与无缝衔接
- [ ] 到达决策点时预发起 API 请求，Agent 继续走旧 path_queue 不停顿
- [ ] API 响应到达后，从 Agent **当前位置**（非请求发起时的位置）重新 A* 寻路，替换旧队列
- [ ] 同一时间每个 Agent 最多一个 in-flight 请求
- [ ] 已有 in-flight 请求时到达新决策点，不发起新请求

### API 调用
- [ ] 使用 OpenAI 兼容 Chat Completions 格式（POST /v1/chat/completions）
- [ ] 请求体包含 `model`、`messages`（system + user）、`temperature`、`max_tokens`
- [ ] 每次调用只发送 system message + 当前 state message，无历史消息累积
- [ ] 两个 Agent 的 API 请求通过独立的 HTTPRequest 节点发送，互不阻塞
- [ ] 两个 Agent 可以配置不同的 api_endpoint / api_key / model

### 响应解析
- [ ] `{"target": [8, 5]}` 正确解析为目标坐标 (8, 5) 并生成路径队列
- [ ] `{"direction": "NORTH"}` 降级处理为长度 1 的 path_queue
- [ ] target 坐标越界（超出迷宫范围）→ 等同于 NONE
- [ ] target 坐标指向 unknown cell → 等同于 NONE
- [ ] target 坐标不可达（A* 无路径）→ 等同于 NONE
- [ ] target 坐标等于当前位置 → 等同于 NONE

### 错误处理
- [ ] API 超时后标记 IDLE，不重试，不更新 path_queue
- [ ] HTTP 429 / 500 / 其他错误后标记 IDLE，不重试，不更新 path_queue
- [ ] 每次 API 错误发出 `api_error(agent_id, error_type)` 信号
- [ ] 比赛结束时取消所有 in-flight 请求，清空 path_queue

### 统计
- [ ] `total_api_calls` 准确记录 API 调用总次数
- [ ] `total_tokens_used` 从 API 响应的 `usage` 字段累加
- [ ] `total_idle_ticks` 准确记录 Agent 因等待 API 或队列为空而原地不动的 tick 数
- [ ] `reset()` 后所有统计数据归零

### 性能
- [ ] 单次 `on_tick()` 处理（不含 API 等待）在 2ms 内完成
- [ ] A* 寻路生成 path_queue 在 5ms 内完成（50x50 迷宫）

### 配置
- [ ] 所有参数（api_endpoint, api_key, model, api_timeout, temperature, max_tokens, max_queue_length）从外部配置文件读取，禁止硬编码

## Action Items

| Item | Owner | Deadline | Description |
|------|-------|----------|-------------|
| ~~更新 LLM Information Format GDD~~ | ~~Game Designer~~ | ~~Sprint 1~~ | ~~同步修改 System Message Template 的 OUTPUT FORMAT 部分，从 `{"direction": "..."}` 改为 `{"target": [x, y]}`，保持 direction 作为降级选项。同步更新 `parse_response()` 返回类型和 Response Parsing 伪代码~~ **Resolved 2026-04-03**: LLM Information Format GDD 已更新——System Message OUTPUT FORMAT 改为 target 优先 + direction 降级，parse_response() 返回 ParseResult 三态（TARGET/DIRECTION/NONE） |

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| 直道自动前进是否应该有速度上限？如果一条超长走廊（10+ 格），Agent 会在 5 秒内飞速穿过，可能观感过快 | Game Designer | Prototype 阶段 | 可能不需要限制——快速穿越直道正是路径队列设计的优势，玩家会觉得"我的 Agent 跑得很快"。如果观感确实太快，可以通过 Match Renderer 的动画插值平滑处理，而非限制逻辑速度 |
| 是否需要"思考中"的视觉指示器？当 Agent 在决策点等待 API 响应时，是否显示一个思考气泡或加载动画？ | Game Designer | Sprint 1 | 建议实现——区分"在等 API"和"撞墙了"对观战体验很重要。由 Match Renderer 消费 `api_request_sent` / `api_response_received` 信号实现 |
| 本地 Ollama 模式是否需要特殊处理？Ollama 的响应速度和格式可能与云 API 不同 | Technical Director | Sprint 2 | MVP 使用统一的 OpenAI 兼容格式处理。如果 Ollama 的响应格式有差异，作为 bug 修复而非设计变更处理 |
| 是否需要支持 streaming 响应？某些 LLM API 支持 SSE streaming，可以更快获得第一个 token | Technical Director | Sprint 2 | MVP 不支持 streaming（Godot HTTPRequest 不原生支持 SSE）。如果延迟成为瓶颈，可以在 Full 阶段用 WebSocket 或自定义 HTTP 客户端实现 |
| 收集钥匙后是否应该立即中断当前路径？还是等旧路径走完 / 到达下一个决策点再请求新决策？ | Game Designer | Sprint 1 | 当前设计是预发起请求但不清空队列。可能需要分情况：如果下一把钥匙已在视野内，立即中断更自然；如果不在视野内，继续走到决策点再请求也合理 |
| 直道自动前进是否会削弱 prompt 质量的区分度？在岔路口很少的迷宫中，两个 Agent 的差异可能被稀释 | Game Designer | Prototype 阶段 | 原型阶段用不同复杂度的迷宫（岔路口多 vs 少）对比测试，验证 prompt 质量是否仍然显著影响 Agent 表现 |
