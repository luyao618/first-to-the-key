# Maze Data Model

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-03-31
> **System Index**: #1
> **Layer**: Foundation
> **Implements Pillar**: Fair Racing, Simple Rules Deep Play

## Overview

Maze Data Model 是整个游戏的空间数据基础，定义了迷宫在内存中的表示方式。它将迷宫建模为一个二维网格（grid），每个单元格（cell）拥有四面墙壁状态和可选的内容物（钥匙、宝箱、玩家起始点）。该系统本身不生成迷宫、不渲染画面、不处理移动逻辑 -- 它仅提供数据结构和查询接口，供 Maze Generator 写入数据、Grid Movement 查询通行性、Fog of War 计算可见区域、Match Renderer 绘制地图、LLM Information Format 序列化迷宫状态。作为被 10+ 系统依赖的 Foundation 层组件，其 API 的稳定性和清晰度直接决定了后续所有系统的开发效率。

## Player Fantasy

Maze Data Model 是一个纯数据层系统，玩家不会直接"感受"到它的存在。但它支撑着玩家体验的根基：

**对于 prompt 策略师（Agent vs Agent 模式）**：你在 God View 中看到的每一面墙壁、每一条通道、每一把钥匙的位置，都是这个数据模型在驱动。它的精确性保证了你看到的地图就是 AI 正在导航的地图 -- 没有隐藏的不一致，没有视觉欺骗。当你的 AI 在岔路口做出正确选择，那是因为它收到了准确的空间数据。

**对于公平竞赛（Fair Racing pillar）**：数据模型的对称性查询能力让 Maze Generator 可以验证两侧路径长度，确保没有先天优势。每场比赛的公平感，始于数据层的诚实。

**对于系统设计者**：这是一个"隐形但不可或缺"的系统。设计目标是让所有下游系统都能用最少的代码、最直观的 API 获取迷宫信息。好的数据模型让人忘记它的存在。

## Detailed Design

### Core Rules

1. 迷宫是一个 `width x height` 的二维矩形网格，每个位置用坐标 `(x, y)` 标识，其中 `(0, 0)` 是左上角
2. 每个 cell 拥有 4 面墙壁（North, East, South, West），每面墙壁是 `bool`（true = 有墙，false = 通道）
3. 相邻 cell 之间的墙壁是**共享的**：cell `(x, y)` 的 East 墙 == cell `(x+1, y)` 的 West 墙。修改一面必须同步修改另一面
4. 网格边界的 cell 外侧墙壁**始终为 true**（不可移除），确保迷宫封闭
5. 每个 cell 可以持有零或多个**标记（markers）**，类型包括：
   - `SPAWN_A` / `SPAWN_B` -- 玩家 A / B 的起始位置（整个迷宫各恰好 1 个）
   - `KEY_BRASS` / `KEY_JADE` / `KEY_CRYSTAL` -- 钥匙位置（各恰好 1 个）
   - `CHEST` -- 宝箱位置（恰好 1 个）
6. Markers 不影响通行性 -- 它们是逻辑标记，不是物理障碍
7. Maze Data Model 是**只读共享数据**：Match 开始后迷宫结构（墙壁）不会改变。Markers 的可见性由 Fog of War 控制，但位置数据始终存在于模型中
8. 坐标系统：X 轴向右递增，Y 轴向下递增（与 Godot 2D 坐标系和 TileMap 一致）

### Data Structures

```
# 枚举类型
enum Direction { NORTH, EAST, SOUTH, WEST }
enum MarkerType { SPAWN_A, SPAWN_B, KEY_BRASS, KEY_JADE, KEY_CRYSTAL, CHEST }

# 单元格数据
Cell:
  position: Vector2i          # (x, y) 坐标
  walls: Dictionary<Direction, bool>  # 四面墙壁状态
  markers: Array<MarkerType>  # 该 cell 上的标记（通常 0-1 个）

# 迷宫数据
MazeData:
  width: int                  # 网格宽度（列数）
  height: int                 # 网格高度（行数）
  cells: Array<Array<Cell>>   # 二维数组 [y][x]，即 cells[y][x]

  # --- 查询接口 ---
  get_cell(x, y) -> Cell
  has_wall(x, y, direction) -> bool
  can_move(x, y, direction) -> bool        # 反向查询：该方向是否可通行
  get_neighbors(x, y) -> Array<Vector2i>   # 返回所有可通行的相邻 cell 坐标
  get_marker_position(type) -> Vector2i    # 返回指定标记的坐标
  get_markers_at(x, y) -> Array<MarkerType>

  # --- 写入接口（仅 Maze Generator 调用）---
  set_wall(x, y, direction, value)         # 自动同步相邻 cell 的对应墙壁
  place_marker(x, y, type)
  remove_marker(x, y, type)

  # --- 生命周期接口 ---
  finalize() -> bool                       # 调用 is_valid()，若通过则锁定写入接口，返回 true；否则返回 false

  # --- 验证接口 ---
  is_valid() -> bool                       # 检查迷宫完整性（边界封闭、必要标记存在）
  get_shortest_path(from, to) -> Array<Vector2i>  # BFS 最短路径（用于公平性验证）
```

**设计决策**：

- **墙壁共享同步**：避免 cell A 认为"可通行"但 cell B 认为"有墙"的不一致 bug
- **Markers 统一管理**：比单独跟踪 `key_brass_pos`, `chest_pos` 更灵活，方便 Fog of War 统一查询"这个 cell 有什么"
- **`get_shortest_path` 在数据模型中**：BFS 仅需墙壁数据，是纯数据操作，且被多个系统需要（公平性验证、距离信息）
- **`cells[y][x]` 存储顺序**：行优先（先选行 y 再选列 x），但公开 API 统一用 `(x, y)` 参数顺序

### States and Transitions

Maze Data Model 本身是静态数据，但它有两个生命周期阶段：

| State | Entry Condition | Exit Condition | Behavior |
|-------|----------------|----------------|----------|
| **Uninitialized** | `MazeData` 对象刚创建 | Maze Generator 调用 `finalize()` | 所有 cell 初始化为四面有墙、无标记。写入接口可用，查询接口可用但返回的是"全墙"状态 |
| **Finalized** | `finalize()` 调用成功（`is_valid()` 通过） | Match 结束，对象释放 | 写入接口被锁定（调用会产生错误日志但不崩溃）。所有查询接口正常工作。迷宫结构不可变 |

### Interactions with Other Systems

| System | Direction | Interface | Data Flow |
|--------|-----------|-----------|-----------|
| **Maze Generator** | Generator -> Model | `set_wall()`, `place_marker()`, `finalize()` | Generator 写入墙壁和标记，完成后调用 `finalize()` 锁定数据 |
| **Grid Movement** | Movement -> Model | `can_move(x, y, dir)` | Movement 查询某方向是否可通行，决定是否执行移动 |
| **Fog of War** | FoW -> Model | `get_neighbors()`, `has_wall()` | FoW 从 agent 位置出发，沿可通行路径计算可见范围 |
| **Key Collection** | Keys -> Model | `get_marker_position()`, `get_markers_at()` | 查询钥匙位置，判断 agent 是否站在钥匙 cell 上 |
| **Win Condition / Chest** | WinCon -> Model | `get_marker_position(CHEST)` | 查询宝箱位置，判断 agent 是否到达 |
| **LLM Information Format** | LLMFormat -> Model | `get_cell()`, `has_wall()`, `get_markers_at()` | 将 agent 视野范围内的迷宫数据序列化为文本 |
| **Match Renderer** | Renderer -> Model | `get_cell()`, 遍历所有 cells | 读取完整迷宫数据进行渲染 |
| **Maze Generator (公平性)** | Generator -> Model | `get_shortest_path()` | 验证两个 spawn 点到各钥匙的路径长度差异 |

## Formulas

### BFS Shortest Path

```
path_length = BFS(maze, start, goal)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| maze | MazeData | -- | 当前迷宫实例 | 提供 `get_neighbors()` 用于图遍历 |
| start | Vector2i | (0,0) to (width-1, height-1) | 调用方指定 | 起始坐标 |
| goal | Vector2i | (0,0) to (width-1, height-1) | 调用方指定 | 目标坐标 |
| path_length | int | 1 to width*height-1 | 计算结果 | 最短路径的步数（cell 数量 - 1） |

**预期输出范围**：对于 `w x h` 的迷宫，最短路径长度范围为 `1`（相邻）到 `w * h - 1`（遍历整个迷宫的蛇形路径）。典型迷宫中，对角线距离约为 `w + h` 量级。

**Edge case**：若 `start == goal`，返回空路径（长度 0）。若路径不存在（迷宫未连通），返回空数组。

### Coordinate Conversion

```
# Grid 坐标 -> 像素坐标（供 Renderer 使用）
pixel_x = grid_x * cell_size
pixel_y = grid_y * cell_size

# 像素坐标 -> Grid 坐标（供输入系统使用）
grid_x = floor(pixel_x / cell_size)
grid_y = floor(pixel_y / cell_size)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| grid_x, grid_y | int | 0 to width-1, 0 to height-1 | 迷宫坐标 | 网格坐标 |
| pixel_x, pixel_y | float | 0 to width*cell_size, 0 to height*cell_size | 屏幕坐标 | 像素坐标 |
| cell_size | int | 16 to 128 | 配置文件 | 每个 cell 的像素边长 |

### Fairness Delta

```
fairness_delta = abs(path_A - path_B)
is_fair = fairness_delta <= max_fairness_delta
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| path_A | int | 1+ | `get_shortest_path(SPAWN_A, target)` | 玩家 A 到目标的最短路径 |
| path_B | int | 1+ | `get_shortest_path(SPAWN_B, target)` | 玩家 B 到目标的最短路径 |
| fairness_delta | int | 0+ | 计算结果 | 路径长度差异 |
| max_fairness_delta | int | 0 to 5 | 配置文件 | 允许的最大路径差异 |

**预期输出**：`fairness_delta` 越小越公平。建议默认 `max_fairness_delta = 2`，即两侧路径差最多 2 步。

**验证策略**：Maze Generator 应对每个目标分别验证公平性（SPAWN→KEY_BRASS、SPAWN→KEY_JADE、SPAWN→KEY_CRYSTAL、SPAWN→CHEST），所有目标均需通过。具体验证流程由 Maze Generator GDD 定义。

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 坐标越界：查询 `get_cell(-1, 0)` 或 `get_cell(width, 0)` | 返回 `null` 并打印警告日志，不崩溃 | 防御性编程，下游系统可能有 off-by-one 错误 |
| 重复放置同类型标记：对第二个 cell 调用 `place_marker(x2, y2, SPAWN_A)` | 先移除旧位置的 `SPAWN_A`，再在新位置放置。保证全迷宫该标记唯一 | SPAWN 和 KEY 类标记有唯一性约束 |
| 同一 cell 放置多个标记：`place_marker(3, 3, KEY_BRASS)` + `place_marker(3, 3, SPAWN_A)` | 允许。一个 cell 可以同时持有多个不同类型的标记 | 虽然 Maze Generator 通常不会这么做，但数据模型不应限制这种可能性 |
| Finalized 后调用写入接口：`set_wall()` / `place_marker()` | 操作被忽略，打印错误日志 `"MazeData is finalized, write operation rejected"` | 保护运行时数据完整性，不使用 assert 以避免生产环境崩溃 |
| 迷宫不连通：`is_valid()` 检测到某些 cell 无法从 SPAWN_A 到达 | `is_valid()` 返回 `false`，附带错误信息 `"Unreachable cells detected"` | Maze Generator 必须保证连通性，验证接口帮助捕获生成 bug |
| `get_shortest_path()` 起点或终点不存在标记 | 正常执行 BFS（参数是坐标不是标记类型），如果坐标合法就搜索 | 路径查询不依赖标记，只依赖墙壁拓扑 |
| 迷宫尺寸为最小值 `2x2` | 正常工作。4 个 cell，最少移除 3 面墙壁即可形成连通迷宫 | 支持小迷宫用于测试和教程 |
| 迷宫尺寸为 `1x1` | `is_valid()` 返回 `false`（无法放置 2 个不同位置的 spawn 点） | 单 cell 迷宫没有游戏意义 |
| `get_shortest_path()` 在未连通的迷宫上调用 | 返回空数组 `[]`，表示无路径 | 调用方应检查返回值是否为空 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Maze Generator** | Generator depends on this | 调用写入接口构建迷宫结构，调用验证接口确认完整性 |
| **Grid Movement** | Movement depends on this | 查询 `can_move()` 判断移动方向是否可通行 |
| **Fog of War / Vision** | FoW depends on this | 查询 `get_neighbors()` / `has_wall()` 计算视野可达范围 |
| **Key Collection** | Keys depends on this | 查询 `get_marker_position()` / `get_markers_at()` 定位钥匙和判断拾取 |
| **Win Condition / Chest** | WinCon depends on this | 查询 `get_marker_position(CHEST)` 定位宝箱 |
| **LLM Information Format** | LLMFormat depends on this | 读取视野范围内的 cell 数据序列化为 LLM 可理解的文本 |
| **LLM Agent Integration** | 间接依赖（通过 LLM Information Format） | 不直接调用，但数据模型的结构决定了 LLM 收到的信息质量 |
| **Match Renderer** | Renderer depends on this | 遍历所有 cell 数据绘制迷宫视图 |
| **Match HUD** | 间接依赖（通过 Key Collection） | 不直接调用，但钥匙进度数据源自此模型 |
| **(无上游依赖)** | -- | Maze Data Model 是 Foundation 层，不依赖任何其他游戏系统。仅依赖 Godot 引擎基础类型（`Vector2i`, `Array`, `Dictionary`） |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `width` | 15 | 2 - 50 | 迷宫更宽，比赛时间更长，路径选择更多，LLM 导航难度增加 | 迷宫更窄，比赛更短更简单，适合教程或快速测试 |
| `height` | 15 | 2 - 50 | 同 width | 同 width |
| `cell_size` | 32 | 16 - 128 | 每个 cell 占更多像素，迷宫在屏幕上显示更大（可能需要滚动/缩放） | 每个 cell 更小，更多迷宫内容可见但细节更难辨认 |
| `max_fairness_delta` | 2 | 0 - 5 | 允许更大的路径不对称，生成更快但公平性降低 | 要求更严格的对称性，生成可能需要更多重试但竞赛更公平 |

**注意事项**：

- `width` 和 `height` 不需要相等，支持长方形迷宫
- `cell_size` 影响渲染而非游戏逻辑，但坐标转换公式依赖此值
- `max_fairness_delta = 0` 意味着两侧路径必须完全等长，对生成算法压力很大，建议不低于 1
- 所有值必须从配置文件（Resource/JSON）读取，禁止硬编码

## Visual/Audio Requirements

Maze Data Model 是纯数据系统，不直接产生视觉或音频输出。以下需求由下游系统消费本模型数据来实现：

| Event | Visual Feedback | Audio Feedback | Priority | Responsible System |
|-------|----------------|---------------|----------|--------------------|
| 迷宫生成完成 | 完整迷宫在 God View 中渲染 | 无 | MVP | Match Renderer |
| Cell 进入视野 | 迷雾消散，cell 及其内容物显现 | 可选：轻微揭示音效 | MVP | Fog of War + Match Renderer |
| 标记物可见 | 钥匙/宝箱图标在对应 cell 渲染 | 无（拾取音效由 Key Collection 负责） | MVP | Match Renderer |

## Acceptance Criteria

- [ ] `MazeData.new(width, height)` 创建的迷宫中，所有 cell 初始化为四面有墙、无标记
- [ ] `set_wall(x, y, EAST, false)` 同时移除 `(x, y)` 的 East 墙和 `(x+1, y)` 的 West 墙
- [ ] 边界墙壁不可移除：`set_wall(0, 0, WEST, false)` 后，`has_wall(0, 0, WEST)` 仍返回 `true`
- [ ] `can_move(x, y, dir)` 在墙壁存在时返回 `false`，墙壁移除后返回 `true`
- [ ] `get_neighbors()` 只返回可通行方向的相邻坐标，不包含有墙壁阻隔的方向
- [ ] `place_marker(x, y, SPAWN_A)` 重复调用时，旧位置标记被自动移除，全迷宫该类型标记始终唯一
- [ ] `get_marker_position(KEY_BRASS)` 返回正确坐标；未放置时返回 `Vector2i(-1, -1)`
- [ ] `is_valid()` 在以下情况返回 `false`：缺少 SPAWN_A/B、缺少任意钥匙、缺少 CHEST、迷宫不连通
- [ ] `is_valid()` 在所有标记齐全且迷宫完全连通时返回 `true`
- [ ] Finalized 后调用 `set_wall()` / `place_marker()` 不修改数据，并打印错误日志
- [ ] `get_shortest_path(start, goal)` 在连通迷宫中返回正确的 BFS 最短路径
- [ ] `get_shortest_path(start, start)` 返回空路径
- [ ] `get_shortest_path()` 在不连通的迷宫中返回空数组
- [ ] 坐标越界查询（`get_cell(-1, 0)`）返回 `null`，不崩溃
- [ ] Performance: 对 50x50 迷宫，`get_shortest_path()` 在 10ms 内完成
- [ ] 所有配置值（width, height, cell_size, max_fairness_delta）从外部配置读取，无硬编码

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| cell_size 是否应该属于 Maze Data Model，还是纯粹由 Renderer 管理？ | Technical Director | Sprint 1 | 待定 -- 目前放在 Model 中供坐标转换使用，但可能更适合放在 Renderer 配置中 |
| 是否需要支持非矩形迷宫（如 L 型、环形）？ | Game Designer | Sprint 1 | MVP 仅支持矩形。数据结构可扩展但不预先设计 |
| Marker 系统是否需要支持自定义扩展类型（为未来 Item 系统预留）？ | Game Designer | Pre-Production 结束前 | 待定 -- 当前 enum 够用，扩展可后续添加 |
