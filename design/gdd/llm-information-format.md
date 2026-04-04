# LLM Information Format

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-04
> **System Index**: #8
> **Layer**: Feature
> **Implements Pillar**: Human-AI Symbiosis, Information Trade-off, Simple Rules Deep Play

## Overview

LLM Information Format 是将游戏运行时状态序列化为 LLM 可理解的文本提示、并将 LLM 文本响应解析为游戏动作的**双向翻译层**。在每个决策点（decision point），LLM Agent Integration 调用本系统为对应 Agent 构建一条 prompt message：包含 Agent 当前位置、可通行方向、视野范围内的迷宫结构（Visible cells 的墙壁和标记、Explored cells 的墙壁）、已访问历史、当前钥匙进度。LLM 返回一个 JSON 指令（主格式为目标坐标 `{"target": [x, y]}`，降级格式为单步方向 `{"direction": "NORTH"}`），本系统解析并转换为 `ParseResult`（TARGET / DIRECTION / NONE），交给 LLM Agent Integration 消费。

本系统是整个游戏的**核心假设验证点**——如果 LLM 无法从文本表示中有效导航迷宫，游戏概念不成立。因此设计目标是：信息表示必须对 LLM "友好"（结构化、无歧义、token 高效），同时严格遵循 Fog of War 的可见性规则（不泄露 Agent 不应知道的信息）。本系统不调用 LLM API（由 LLM Agent Integration 负责）、不处理移动逻辑（由 Grid Movement 负责）、不管理可见性（由 Fog of War 负责）——它只负责**格式转换**。

## Player Fantasy

LLM Information Format 是玩家不会直接看到的系统——但它决定了玩家最关心的事情：**我的 prompt 到底有没有用？**

**对于 prompt 策略师**：你在赛前精心编写了 prompt："当你在岔路口时，优先选择未访问过的方向；如果有多个未访问方向，优先向钥匙可能出现的方向移动。" 比赛开始，你的 Agent 在每个决策点（岔路口、死胡同等）收到一段描述当前环境的文本——它的位置、能看到的通道和墙壁、哪些地方已经走过、下一把要找的是什么钥匙。这段文本就是 LLM Information Format 构建的。你的 prompt 能否发挥作用，完全取决于这段环境描述是否清晰到让 LLM 把你的策略"映射"到当下的具体情况。当你的 Agent 在 T 字路口选择了正确方向，你知道：是这个系统把"左边已访问、右边未知"这个事实精确地传达给了 LLM，你的 prompt 才得以生效。

**对于系统设计者**：这是"Human-AI Symbiosis"支柱的核心实现。玩家的 prompt 是"战略层"——抽象的导航原则；LLM Information Format 是"战术层"——每个决策点的具体情报。好的信息格式让 prompt 中的策略有据可依，差的格式让 LLM 无所适从。这个系统的质量直接决定了"prompt 质量是否能转化为 Agent 表现差异"这一核心假设能否成立。

## Detailed Design

### Core Rules

1. LLM Information Format 是一个**无状态转换器**——每次调用 `build_state_message()` 时从上游系统实时读取数据，不缓存任何跨调用的状态
2. LLM Agent Integration 在**决策点**（而非每个 tick）为每个 Agent 调用 `build_state_message(agent_id)` 获取完整的 state message，发送给 LLM API。决策点包括：岔路口、死胡同、视野内新目标出现、撞墙等（详见 `llm-agent-integration.md` 决策点定义）。直道自动前进不触发 API 调用
3. LLM 的文本响应通过 `parse_response(text)` 解析。**主格式**为目标坐标 `{"target": [x, y]}`，由 LLM Agent Integration 进行 A* 寻路生成路径队列。**降级格式**为单方向 `{"direction": "NORTH"}`，生成长度为 1 的路径队列。任何无法解析为合法目标或方向的响应，等同于 `NONE`（原地不动）
4. **信息边界严格遵循 Fog of War 和 Marker 激活状态**：只有 `VISIBLE` 状态的 cell 会包含标记信息（钥匙/宝箱），`EXPLORED` cell 仅包含墙壁结构，`UNKNOWN` cell 完全不出现在 prompt 的结构化列表（Visible/Explored/Visited）中。ASCII 地图中使用 `?` 标记视野边界外的 cell 作为空间参照，但不包含任何结构或标记信息。**Marker 激活过滤由本系统负责**——FoW 只提供 cell 可见性，不判断 marker 是否 Active。`build_state_message()` 在构建 Visible cells 列表时，必须对每个 cell 的 markers 执行以下过滤：
   - 钥匙 marker：仅在 `KeyCollection.is_key_active(key_type)` 为 true 时包含
   - 宝箱 marker：仅在 `WinCondition.is_chest_active()` 为 true 时包含
   - 不满足条件的 marker 从 prompt 中完全排除，等效于该 cell 上不存在标记
5. Prompt 由**系统消息（System Message）**和**状态消息（State Message）**两部分组成。System Message 在比赛开始前由玩家的 prompt + 固定规则说明构成，State Message 在每次决策点触发 API 调用时动态生成
6. LLM 的输出格式优先级：**主格式** `{"target": [x, y]}`（目标坐标，由 LLM Agent Integration 执行 A* 寻路）；**降级格式** `{"direction": "NORTH|EAST|SOUTH|WEST"}`（单步方向）。JSON 中同时包含两者时，`target` 优先。任何无法解析为合法格式的响应，等同于 `NONE`（原地不动）
7. 所有坐标使用 `(x, y)` 格式，X 轴向右，Y 轴向下，与 Maze Data Model 一致

### Prompt Structure

完整的 LLM 会话由三部分组成：

```
┌─────────────────────────────────────┐
│  System Message（固定，比赛全程不变）  │
│  ┌─────────────────────────────────┐│
│  │ 1. 游戏规则说明                  ││
│  │ 2. 输出格式要求                  ││
│  │ 3. 坐标系说明                    ││
│  │ 4. 玩家的 Prompt（赛前输入）      ││
│  └─────────────────────────────────┘│
├─────────────────────────────────────┤
│  State Message（每次决策点动态生成）   │
│  ┌─────────────────────────────────┐│
│  │ 1. 当前位置和可通行方向           ││
│  │ 2. 局部 ASCII 地图               ││
│  │ 3. Visible cells 详情            ││
│  │ 4. Explored cells 概要           ││
│  │ 5. 已访问 cell 列表              ││
│  │ 6. 钥匙进度和目标                ││
│  └─────────────────────────────────┘│
├─────────────────────────────────────┤
│  LLM Response                       │
│  {"target": [8, 5]}                │
│  or: {"direction": "NORTH"}        │
└─────────────────────────────────────┘
```

### System Message Template

```
You are an AI agent navigating a maze. Your goal is to collect three keys in order (Brass → Jade → Crystal) and then reach the treasure chest to win.

RULES:
- You move one cell per turn in a cardinal direction: NORTH, EAST, SOUTH, or WEST.
- You can only move in directions without walls. Moving into a wall wastes your turn.
- You have limited vision: you can see cells within {vision_radius} steps along open paths from your position.
- "Visible" cells show walls AND items (keys, chest). "Explored" cells show walls only (you saw them before but can't currently see items there).
- Keys must be collected in order. You can only pick up the key matching your current progress.
- You share the maze with an opponent agent. First to open the chest wins.

COORDINATE SYSTEM:
- (x, y) where x increases rightward, y increases downward.
- (0, 0) is the top-left corner.
- NORTH = y-1, SOUTH = y+1, EAST = x+1, WEST = x-1.

OUTPUT FORMAT:
- Respond with ONLY a JSON object.
- Preferred: {"target": [x, y]} — specify a visible or explored cell to navigate to. The system will auto-pathfind.
- Fallback: {"direction": "NORTH|EAST|SOUTH|WEST"} — move one step in a cardinal direction.
- Do NOT include any explanation, reasoning, or extra text.

PLAYER STRATEGY:
{player_prompt}
```

### State Message Template

```
TURN {tick_count}
Position: ({x}, {y})
Open directions: {open_directions}

MAP (your vision, # = wall, . = open, ? = unknown, K = current target key, C = chest, @ = you):
{ascii_map}

VISIBLE CELLS:
{visible_cells_list}

EXPLORED CELLS (walls only, items may have changed):
{explored_cells_list}

VISITED (cells you have been to):
{visited_list}

OBJECTIVE: {objective_text}
Keys collected: {keys_collected}/3
```

### ASCII Map Format

以 Agent 当前位置为中心，渲染一个 `(2 * vision_radius + 1)` 大小的局部 ASCII 地图。使用紧凑的墙壁+通道表示法：

```
示例（Agent 在 (5, 3)，vision_radius = 3，7x7 视野区域）：

     2   3   4   5   6   7   8
  ┌───┬───┬───┬───┬───┬───┬───┐
0 │ ? │ ? │ ? │ . │ . │ ? │ ? │
  ├───┼   ┼───┼   ┼───┼───┼───┤
1 │ ? │ .   . │ .   . │ ? │ ? │
  ├───┼───┼   ┼   ┼   ┼───┼───┤
2 │ ? │ . │ .   .   . │ ? │ ? │
  ├───┼   ┼───┼   ┼───┼───┼───┤
3 │ ? │ .   . │ @   K │ ? │ ? │
  ├───┼───┼───┼   ┼   ┼───┼───┤
4 │ ? │ ? │ ? │ .   . │ ? │ ? │
  ├───┼───┼───┼───┼───┼───┼───┤
5 │ ? │ ? │ ? │ ? │ ? │ ? │ ? │
  └───┴───┴───┴───┴───┴───┴───┘
```

实际发送给 LLM 的简化 ASCII 格式（节省 token）：

```
MAP (7x7 around you, row 0-6):
#?#?#.#.#?#?#
? . . . . ? ?
#?# #.# #?#?#
? .   . . ? ?
#?#.# #.#?#?#
? . .   . ? ?
#?# #.# #?#?#
? .   @ K ? ?
#?#.#.# #?#?#
? ? ? .   ? ?
#?#?#?#.#?#?#
? ? ? ? ? ? ?
#?#?#?#?#?#?#
```

**简化方案**（MVP 推荐，大幅节省 token）：

不发送 ASCII 地图，只发送结构化坐标列表。ASCII 地图作为可选增强，通过 Tuning Knob 控制开关。

### Visible Cells List Format

```
VISIBLE CELLS:
(5,3) open:E,S [YOU]
(6,3) open:W,S [KEY:BRASS]
(5,2) open:N,S,E
(6,2) open:S,W
(5,4) open:N,E
(6,4) open:N,W
(4,3) open:E (dead end)
(4,2) open:S,E
(5,1) open:S,E,W
(4,1) open:E,W
(3,1) open:E
```

每行格式：`(x,y) open:{可通行方向列表} [可选标注]`

标注类型：
- `[YOU]` — Agent 当前位置
- `[KEY:BRASS]` / `[KEY:JADE]` / `[KEY:CRYSTAL]` — 该 cell 上有钥匙（仅显示 Agent 当前需要收集的钥匙，已收集的钥匙不再显示）
- `[CHEST]` — 该 cell 上有宝箱（仅在所有钥匙收集完成后显示）
- `(dead end)` — 只有一个开放方向（辅助 LLM 识别死胡同）

### Explored Cells List Format

```
EXPLORED CELLS (walls only, items may have changed):
(2,1) open:E,S
(2,2) open:N,W
(1,2) open:E (dead end)
```

格式与 Visible Cells 相同，但**不包含标记标注**（钥匙/宝箱）。标题行提醒 LLM 这些区域的物品状态可能已变化。

### Visited List Format

```
VISITED (cells you have been to):
(5,5) (5,4) (5,3) (4,3) (4,2) (4,1) (3,1)
```

已访问 cell 按首次访问时间倒序排列（最近首次到达的在前），以空格分隔。这帮助 LLM 识别"我已经走过哪里"，实现避免重复访问的策略。底层数据源 Grid Movement 的 `visited_cells` 按正序存储（旧到新、append-only），本系统在构建 prompt 时反转输出顺序。重复访问同一 cell 不会改变其在列表中的位置——仅首次访问时记录。

### Response Parsing

LLM 响应由本系统解析，结果交给 LLM Agent Integration 消费。

```
# 返回类型：目标坐标 或 单步方向 或 NONE
enum ParseResult:
  TARGET(pos: Vector2i)      # 主格式：目标坐标
  DIRECTION(dir: MoveDirection)  # 降级格式：单步方向
  NONE                       # 解析失败

parse_response(text: String) -> ParseResult:
  # 1. 尝试提取 JSON
  json = extract_json(text)           # 寻找第一个 {...} 块
  if json == null:
    log_warning("No JSON found in LLM response")
    return NONE

  # 2. 优先检查 target 字段
  if json.has("target"):
    var arr = json.get("target")
    if arr is Array and arr.size() == 2:
      var x = int(arr[0])
      var y = int(arr[1])
      return TARGET(Vector2i(x, y))
    log_warning("Invalid target format: " + str(arr))

  # 3. 降级检查 direction 字段
  if json.has("direction"):
    var dir_str = json.get("direction", "").to_upper().strip()
    match dir_str:
      "NORTH", "N", "UP":    return DIRECTION(NORTH)
      "EAST",  "E", "RIGHT": return DIRECTION(EAST)
      "SOUTH", "S", "DOWN":  return DIRECTION(SOUTH)
      "WEST",  "W", "LEFT":  return DIRECTION(WEST)
      _:
        log_warning("Invalid direction: " + dir_str)

  # 4. 两者都无法解析
  return NONE
```

**容错策略**：
- 优先解析 `target`（目标坐标），其次 `direction`（单步方向）
- 接受方向缩写（N/E/S/W）和别名（UP/DOWN/LEFT/RIGHT）
- 忽略 JSON 外的文本（LLM 可能在 JSON 前后添加解释）
- 无法解析时返回 `NONE`（原地不动），不重试、不崩溃
- 目标坐标的验证（范围检查、可见性检查、可达性检查）由 LLM Agent Integration 负责，本系统只做格式解析

### Data Structures

```
LLMInformationFormat:
  # --- 上游数据源引用（只读）---
  maze: MazeData
  fog: FogOfWar
  movement: GridMovementManager
  keys: KeyCollection              # 查询钥匙进度（get_agent_progress）和激活状态（is_key_active）
  win_condition: WinCondition      # 查询宝箱激活状态（is_chest_active）

  # --- 配置 ---
  include_ascii_map: bool          # 是否在 State Message 中包含 ASCII 地图（默认 false）
  include_explored: bool           # 是否包含 Explored cells 列表（默认 true）
  max_visited_count: int           # visited 列表最多显示多少个（默认 20，防止 token 膨胀）
  max_explored_count: int          # Explored cells 列表最多显示多少个（默认 30，按曼哈顿距离排序截断。不使用路径距离，因为 MazeData.get_shortest_path() 在完整迷宫上运行，会泄露 Agent 未知区域的路径信息，违反 FoW 信息边界）

  # --- 构建接口 ---
  build_system_message(player_prompt: String, vision_radius: int) -> String
  build_state_message(agent_id: int) -> String    # tick_count 从 Match State Manager 的 get_tick_count() 内部读取，不作为参数传入

  # --- 解析接口 ---
  parse_response(text: String) -> ParseResult   # 返回 TARGET(pos) / DIRECTION(dir) / NONE

  # --- 调试接口 ---
  get_last_prompt(agent_id: int) -> String    # 返回最后一次为该 Agent 构建的完整 prompt（调试用）
  get_token_estimate(text: String) -> int     # 粗略估算文本的 token 数量
```

### Interactions with Other Systems

| System | Direction | Interface | Data Flow |
|--------|-----------|-----------|-----------|
| **LLM Agent Integration** | Agent → Format | `build_system_message()`, `build_state_message()`, `parse_response()` | Agent Integration 在每个决策点调用构建 prompt，发给 LLM API，再调用解析响应 |
| **Maze Data Model** | Format → Model | `has_wall()`, `get_markers_at()`, `get_cell()` | 读取 Visible/Explored cells 的墙壁结构和标记 |
| **Fog of War** | Format → FoW | `get_visible_cells(agent_id)`, `get_explored_cells(agent_id)`, `get_cell_visibility(agent_id, x, y)` | 决定哪些 cell 的信息可以发送给 LLM |
| **Grid Movement** | Format → Movement | `get_position()`, `get_visited_cells()` | 获取 Agent 当前位置和已访问历史 |
| **Key Collection** | Format → Keys | `get_agent_progress(agent_id)`, `is_key_active()` | 获取 Agent 的钥匙进度（AgentKeyState 枚举），派生当前目标和已收集数量：NEED_BRASS→目标 Brass key/已收集 0，NEED_JADE→目标 Jade key/已收集 1，NEED_CRYSTAL→目标 Crystal key/已收集 2，KEYS_COMPLETE→目标宝箱/已收集 3。**Marker 过滤**：`build_state_message()` 中用 `is_key_active(key_type)` 过滤 Inactive 钥匙，不将其包含在 Visible cells 的 marker 标注中 |
| **Win Condition / Chest** | Format → WinCon | `is_chest_active()` | **Marker 过滤**：`build_state_message()` 中用 `is_chest_active()` 过滤 Inactive 宝箱。FoW 不负责此过滤——本系统是 marker 激活过滤的执行者之一 |
| **Match State Manager** | Format → MSM | `get_tick_count()` | 在 State Message 中包含当前 tick 编号 |

## Formulas

### Token Estimation

```
estimated_tokens = character_count / 4
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| character_count | int | 50 - 5000 | `build_state_message()` 返回的字符串长度 | State Message 的字符数 |
| estimated_tokens | int | 12 - 1250 | 计算结果 | 粗略 token 估算（英文平均 1 token ≈ 4 字符） |

**预期 token 范围**（基于 15x15 迷宫，vision_radius = 3）：
- System Message: ~200 tokens（固定，含玩家 prompt）
- State Message（无 ASCII 地图）: ~100-300 tokens（取决于 visible/explored cell 数量）
- State Message（含 ASCII 地图）: ~200-500 tokens
- LLM Response: ~10-20 tokens

**每场比赛总 token 估算**：
```
total_tokens_per_match = (system_tokens + avg_state_tokens + avg_response_tokens) * api_calls_per_match
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| system_tokens | int | ~200 | System Message | 固定开销（每次 API 调用都包含） |
| avg_state_tokens | int | 100 - 300 | State Message 平均值 | 每次决策点的状态描述 |
| avg_response_tokens | int | ~15 | LLM Response 平均值 | LLM 返回的目标坐标或方向指令 |
| api_calls_per_match | int | 40 - 80 | LLM Agent Integration 估算 | 一场比赛的 API 调用总次数（两个 Agent 合计，基于决策点触发而非每 tick 调用） |

**典型估算**：15x15 迷宫，约 60 次 API 调用（决策点触发），无 ASCII 地图 → (200 + 200 + 15) * 60 ≈ 24,900 tokens/场。对比旧的每 tick 调用方案（166,000 tokens/场），路径队列 + 决策点模式**减少约 85%**。详见 `llm-agent-integration.md` Formulas 部分。

### ASCII Map Dimensions

```
map_width = 2 * vision_radius + 1
map_height = 2 * vision_radius + 1
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| vision_radius | int | 1 - 10 | 配置文件 | Fog of War 的视野半径 |
| map_width, map_height | int | 3 - 21 | 计算结果 | ASCII 地图的 cell 行列数 |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| LLM 返回空字符串或纯空白 | `parse_response()` 返回 `NONE`，Agent 原地不动 | 网络异常或 LLM 拒答都可能导致空响应。不崩溃，消耗一个 tick |
| LLM 返回合法 JSON 但 `target` 和 `direction` 字段均缺失 | `parse_response()` 返回 `NONE` | JSON 结构正确但不包含任何可用指令，等同于无响应 |
| LLM 返回 `{"direction": "NORTHEAST"}` 或其他非法方向 | `parse_response()` 返回 `NONE`，打印警告日志 | 只接受四个基本方向，不支持对角线移动 |
| LLM 在 JSON 前后添加解释文字：`"I'll go north. {"direction": "NORTH"}"` | `parse_response()` 提取第一个 `{...}` 块，正常解析为 `NORTH` | LLM 常常"想出声"，解析器应容错 |
| LLM 返回多个 JSON 对象 | 提取第一个 `{...}` 块，忽略后续内容 | 取第一个决策，简单确定 |
| LLM 返回的方向指向墙壁 | `parse_response()` 正常返回该方向。Grid Movement 的 `can_move()` 负责拒绝并记录撞墙 | 信息格式层不做合法性验证——那是 Grid Movement 的职责。分层清晰 |
| Visible cells 为空（Agent 视野内只有自己脚下的 cell） | `VISIBLE CELLS` 区域只包含 Agent 当前位置一条记录。正常构建 prompt | vision_radius = 0 的极端情况，系统不需要特殊处理 |
| Explored cells 数量巨大（Agent 已探索 50x50 迷宫的大部分） | Explored cells 列表按离 Agent 当前位置的曼哈顿距离排序，截断至 `max_explored_count` 条（默认 30）。提醒 LLM "showing nearest {n} of {total} explored cells" | 防止 token 膨胀超出 LLM 上下文窗口限制。优先显示距离近的（更可能与当前决策相关）。使用曼哈顿距离而非路径距离，因为路径距离需要在完整迷宫上寻路，会间接泄露未知区域信息 |
| Visited cells 数量巨大 | 截断至 `max_visited_count` 条（默认 20），保留最近首次到达的 N 个（首次访问时间倒序）。提醒 LLM "showing last {n} of {total} visited" | 同上，最近首次到达的 cell 对避免重复访问更有价值 |
| 当前目标钥匙在 Explored 区域新出现（Jade Key 出现在 Agent 已经 Explored 但当前不 Visible 的 cell） | Prompt 不包含该钥匙位置信息（FoW 规则：Explored cell 不暴露标记）。Agent 必须重新探索才能发现 | 严格遵循 Fog of War 信息边界，不偷偷泄露 Agent 不应知道的信息 |
| 玩家的 prompt 非常长（数千字符） | System Message 按原样包含玩家 prompt，不截断。如果总 token 超出 LLM 上下文限制，由 LLM Agent Integration 层处理（截断或报错） | 信息格式层不限制创意性输入。token 管理是 API 调用层的职责 |
| 玩家的 prompt 为空 | System Message 的 `PLAYER STRATEGY` 区域为空。LLM 将使用默认行为导航 | 空 prompt 是合法的（Match State Manager GDD 已确认），信息格式层正常处理 |
| 比赛第一个 tick（Agent 刚 Spawn，无移动历史） | `VISITED` 列表只包含 Spawn 位置一个坐标。正常构建 prompt | 初始状态，无特殊处理 |
| Key Collection 系统尚未初始化（比赛还没开始就调用 `build_state_message`） | 钥匙进度显示 `0/3`，目标显示 `Brass key`（默认第一把） | 防御性设计，不崩溃。实际不应发生（只在 PLAYING 状态调用） |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Maze Data Model** | LLMFormat depends on this | 查询 `has_wall()`, `get_markers_at()`, `get_cell()` 读取 Visible/Explored cells 的墙壁结构和标记内容 |
| **Fog of War** | LLMFormat depends on this | 查询 `get_visible_cells(agent_id)`, `get_explored_cells(agent_id)`, `get_cell_visibility(agent_id, x, y)` 确定哪些 cell 的信息可以发送给 LLM |
| **Grid Movement** | LLMFormat depends on this | 查询 `get_position()` 获取 Agent 当前位置，查询 `get_visited_cells()` 获取已访问历史 |
| **Key Collection** | LLMFormat depends on this | 查询 `get_agent_progress(agent_id)` 获取 Agent 的钥匙进度（AgentKeyState 枚举），派生当前目标（NEED_BRASS→Brass key, NEED_JADE→Jade key, NEED_CRYSTAL→Crystal key, KEYS_COMPLETE→宝箱）和已收集数量（0/1/2/3），查询 `is_key_active(key_type)` 过滤 Visible cells 中的 Inactive 钥匙 marker（FoW 不负责此过滤） |
| **Win Condition / Chest** | LLMFormat depends on this | 查询 `is_chest_active()` 过滤 Visible cells 中的 Inactive 宝箱 marker。查询 `get_chest_position()` 在宝箱 Active 且在视野内时序列化宝箱位置。FoW 不负责此过滤——marker 激活状态过滤是本系统和 Match Renderer 的职责 |
| **Match State Manager** | LLMFormat depends on this | 查询 `get_tick_count()` 在 State Message 中包含当前 tick 编号 |
| **LLM Agent Integration** | Agent depends on this | 调用 `build_system_message()`, `build_state_message()` 构建 prompt，调用 `parse_response()` 解析 LLM 返回 |
| **(无下游系统依赖 LLMFormat)** | — | LLM Information Format 是一个纯转换层，不被除 LLM Agent Integration 之外的系统直接引用 |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `include_ascii_map` | false | true / false | 在 State Message 中包含局部 ASCII 地图，给 LLM 空间直觉辅助，但增加 ~100-200 tokens/次调用 | 仅使用坐标列表，token 更紧凑，LLM 需要纯粹依赖坐标推理空间关系 |
| `include_explored` | true | true / false | 包含 Explored cells 的墙壁结构，帮助 LLM 利用已知地形做决策 | 省 token，但 LLM 失去对已探索区域的记忆（每次只看到当前视野） |
| `max_visited_count` | 20 | 5 - 100 | 显示更多已访问历史，帮助 LLM 避免重复路径，但增加 token 消耗 | 减少 token，但 LLM 可能重复访问旧路径 |
| `max_explored_count` | 30 | 10 - 200 | 显示更多已探索 cell 的结构，帮助 LLM 做全局规划（按曼哈顿距离排序截断） | 减少 token，LLM 只能基于当前视野和有限记忆做局部决策 |

**注意事项**：

- `include_ascii_map` 是最影响"LLM 导航质量 vs token 成本"权衡的参数。原型阶段应 A/B 测试有无 ASCII 地图的导航表现差异
- `include_explored = false` 本质上让 LLM 成为"无记忆"Agent，每次决策只靠当前视野做判断。这可能反而适合某些 LLM（减少上下文干扰），需要测试
- `max_visited_count` 和 `max_explored_count` 的最优值取决于迷宫大小和 LLM 的上下文窗口。15x15 迷宫最多 225 个 cell，默认值足够覆盖大部分有意义的历史
- token 成本直接影响 API 费用。基于决策点触发模式，典型场景约 60 次 API 调用 × (200 + 200 + 15) ≈ 24,900 tokens/场。以 GPT-4o 定价估算约 $0.06-0.12/场
- 所有值必须从配置文件读取，禁止硬编码

## Visual/Audio Requirements

LLM Information Format 是纯数据转换系统，不直接产生视觉或音频输出。但以下调试/观战功能由下游系统消费本系统数据来实现：

| Event | Visual Feedback | Audio Feedback | Priority | Responsible System |
|-------|----------------|---------------|----------|--------------------|
| LLM 收到的 prompt（调试模式） | 可选：在 HUD 或独立面板中显示最后一次发送给 LLM 的 State Message | 无 | Full | Match HUD / Debug Panel |
| LLM 的原始响应（调试模式） | 可选：在 HUD 中显示 LLM 的原始返回文本和解析结果 | 无 | Full | Match HUD / Debug Panel |
| 解析失败 | 可选：Agent 头顶显示 "?" 标记，提示本 tick LLM 响应无法解析 | 无 | Full | Match Renderer |

## Acceptance Criteria

### Prompt 构建
- [ ] `build_system_message(player_prompt, vision_radius)` 返回包含游戏规则、坐标系说明、输出格式要求和玩家 prompt 的完整 System Message
- [ ] `build_state_message(agent_id)` 返回包含当前位置、可通行方向、Visible cells、Explored cells、已访问历史和钥匙进度的完整 State Message（tick_count 从 Match State Manager 内部读取）
- [ ] State Message 中的坐标使用 `(x, y)` 格式，X 向右 Y 向下，与 Maze Data Model 一致
- [ ] State Message 中 `Open directions` 仅列出 `MazeData.can_move()` 返回 true 的方向

### 信息边界（Fog of War + Marker 激活状态合规）
- [ ] Visible cells 列表包含墙壁结构和**已激活（Active）**标记信息（钥匙/宝箱）
- [ ] Visible cell 上存在 Inactive marker（如 Jade Key 在 BRASS_ACTIVE 阶段）时，prompt 中不包含该 marker 标注
- [ ] Explored cells 列表仅包含墙壁结构，不包含任何标记信息
- [ ] Unknown cells 完全不出现在 prompt 中的任何列表里
- [ ] 钥匙在 Explored cell 上新出现时，prompt 不包含该钥匙位置
- [ ] 钥匙在 Visible cell 上新出现时，prompt 在当前 tick 即包含该钥匙位置
- [ ] 宝箱在 Inactive 状态时，即使在 Visible cell 上也不包含在 prompt 中
- [ ] 宝箱 Active 且在 Visible cell 上时，prompt 包含 `[CHEST]` 标注

### 响应解析
- [ ] `parse_response('{"target": [8, 5]}')` 返回 `TARGET(Vector2i(8, 5))`
- [ ] `parse_response('{"direction": "NORTH"}')` 返回 `DIRECTION(MoveDirection.NORTH)`
- [ ] `parse_response('{"target": [8, 5], "direction": "NORTH"}')` 优先返回 `TARGET`（target 优先级高于 direction）
- [ ] `parse_response('{"direction": "n"}')` 返回 `DIRECTION(MoveDirection.NORTH)`（大小写不敏感）
- [ ] `parse_response('{"direction": "UP"}')` 返回 `DIRECTION(MoveDirection.NORTH)`（别名支持）
- [ ] `parse_response('I think north. {"target": [3, 2]}')` 正确提取 JSON 并返回 `TARGET`
- [ ] `parse_response('')`（空字符串）返回 `NONE`
- [ ] `parse_response('{"direction": "NORTHEAST"}')` 返回 `NONE`（非法方向）
- [ ] `parse_response('{"foo": "bar"}')` 返回 `NONE`（缺少 target 和 direction 字段）
- [ ] `parse_response('not json at all')` 返回 `NONE`（无 JSON）
- [ ] `parse_response('{"target": "invalid"}')` 返回 `NONE`（target 格式错误），降级检查 direction（若也无则 NONE）

### 截断与 token 控制
- [ ] Visited cells 超过 `max_visited_count` 时，仅显示最近首次到达的 N 个（首次访问时间倒序，与 Grid Movement 的 append-only visited_cells 反转输出一致），并注明 "showing last N of M visited"
- [ ] Explored cells 超过 `max_explored_count` 时，按距 Agent 当前位置的曼哈顿距离排序，仅显示最近的 N 个，并注明 "showing nearest N of M explored"
- [ ] `include_ascii_map = false` 时 State Message 不包含 MAP 区域
- [ ] `include_explored = false` 时 State Message 不包含 EXPLORED CELLS 区域

### 配置
- [ ] 所有参数（`include_ascii_map`, `include_explored`, `max_visited_count`, `max_explored_count`）从外部配置文件读取，禁止硬编码

### 性能
- [ ] 对 50x50 迷宫 + vision_radius = 10，单次 `build_state_message()` 在 5ms 内完成
- [ ] `parse_response()` 在 1ms 内完成

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| ASCII 地图 vs 纯坐标列表：哪种格式的 LLM 导航成功率更高？ | Game Designer | Prototype 阶段 | 需要 A/B 测试。MVP 默认关闭 ASCII 地图（`include_ascii_map = false`），原型阶段用两种配置分别运行 50 场比赛，比较到达率和平均步数 |
| 是否应该在 prompt 中告诉 LLM "你已经在这个位置停留了 N 个 tick"？ | Game Designer | Sprint 1 | 如果 LLM 反复返回无效方向导致原地不动，提醒它"你已经停了 3 个 tick"可能帮助它调整策略。但这也增加了 prompt 复杂度 |
| Explored cells 的排序策略：路径距离 vs 访问时间？ | Technical Director | Sprint 1 | **Resolved 2026-04-04**: 使用曼哈顿距离排序。路径距离（`MazeData.get_shortest_path()`）在完整迷宫上运行，会通过排序结果间接泄露 Agent 未知区域的墙壁信息，违反 FoW 信息边界（Core Rule #4）。曼哈顿距离不需要迷宫结构信息，安全且足够作为"距离近优先"的近似。备选方案（已知图 BFS）需要新增 API 且复杂度过高，不值得 |
| 是否需要支持多种 LLM 的 prompt 格式？不同 LLM（GPT-4, Claude, Gemini）对格式的偏好可能不同 | Technical Director | Sprint 2 | MVP 使用统一格式。如果原型测试显示不同 LLM 表现差异大，考虑添加 format_style 配置（"structured" / "natural_language"） |
| 是否应该在 State Message 中包含"上一个 tick 的结果"（如"你向北移动成功"或"你撞墙了"）？ | Game Designer | Sprint 1 | 这帮助 LLM 理解自己行为的后果，但也增加 token。可以作为可选字段 |
