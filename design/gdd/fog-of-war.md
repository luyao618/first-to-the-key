# Fog of War / Vision

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-04
> **Last Reviewed By**: GPT (external review, 2026-04-03)
> **System Index**: #6
> **Layer**: Core
> **Implements Pillar**: Information Trade-off, Fair Racing

## Overview

Fog of War / Vision 是迷宫竞速中的**信息控制系统**，决定每个 Agent 在任何给定时刻能"看到"迷宫的哪些部分。它将迷宫划分为三种可见性状态：**未知（Unknown）**、**已探索（Explored）**、**可见（Visible）**。Agent 当前位置周围一定范围内的 cell 处于 Visible 状态，Agent 离开后这些 cell 退化为 Explored（记住结构但不显示动态内容），从未进入视野的区域保持 Unknown。

**Vision 模型（可配置策略）**：视野计算策略通过 `vision_strategy` 配置项选择。MVP 使用 **`PATH_REACH`（路径可达感知）**：Agent 的"视野"覆盖从当前位置沿可通行路径 BFS 扩展 `vision_radius` 步可达的所有 cell——这意味着 Agent 可以"感知"到拐角后方的区域，只要路径距离在范围内。这对 LLM Agent 是合理的：LLM 的输入是结构化文本而非视觉画面，路径可达感知更适合文本化的信息传递，且与原型验证阶段（`prototypes/llm-maze-nav/`）使用的方案一致。

**人类可玩模式的视野策略**：`PATH_REACH` 不适用于未来的人类可操作模式（Player vs Player / Player vs Agent）——人类玩家会看到拐角后面的区域，产生"隔墙感知"的反直觉体验。因此 FoW 系统将视野计算抽象为可替换策略：
- **`PATH_REACH`**（MVP 默认）：BFS 沿可通行路径扩展，适合 LLM Agent
- **`LINE_OF_SIGHT`**（Core 阶段实现）：基于射线投射的视线计算，适合人类玩家。只有从 Agent 位置有直接视线（不被墙壁遮挡）且在 `vision_radius` 范围内的 cell 才可见
- 策略选择由游戏模式决定：Agent vs Agent → `PATH_REACH`；Player vs Player / Player vs Agent → `LINE_OF_SIGHT`
- 两种策略共享相同的 cell 三态（Unknown/Visible/Explored）、相同的 VisionMap 数据结构、相同的查询接口。差异仅在 `compute_visible_cells()` 的内部算法

该系统是 "Information Trade-off" 设计支柱的核心载体——迷雾迫使 Agent 在不完整信息下做决策，使 prompt 质量成为决定性因素：好的 prompt 教会 Agent 系统性探索，差的 prompt 导致 Agent 在迷雾中盲目徘徊。对于 God View 的人类观察者来说，迷雾不影响其视野——他们看到完整地图，但只能通过消息（带冻结惩罚）向 Agent 传递信息。

Fog of War 不处理渲染（由 Match Renderer 消费可见性数据）、不处理移动（仅在 Agent 移动后更新视野）、不决定 LLM 收到什么文本（由 LLM Information Format 根据可见性数据构建）、**不过滤 marker 激活状态**（由消费方查询 Key Collection / Win Condition 自行过滤）。它只维护一个核心职责：**管理每个 Agent 对迷宫 cell 的可见性状态**。

## Player Fantasy

**对于 prompt 策略师（Agent vs Agent 模式）**：你的 AI 是一个被蒙上眼睛的迷宫跑者——它只能看到脚下几格的范围。你坐在 God View 里看着完整地图，心里清楚地知道钥匙在哪、最短路径是什么，但你无法直接操控它。你唯一能做的，是在赛前通过 prompt 教会它在黑暗中如何做决策。当你的 AI 走到岔路口，果断选择了正确方向——那一刻你知道，是你的 prompt 教会了它"靠墙走"或"优先探索未知方向"。那种成就感不是来自操作，而是来自**教导**。

**对于迷雾中的探索者（Player vs Player / Player vs Agent 模式）**：你身处迷雾中，只能看到视线所及的范围——拐角后面是一片漆黑。每走一步，迷雾退开一点，新的墙壁和通道浮现。你不知道钥匙在哪，不知道对手走到了哪里，但你知道你每一步都在缩小未知的范围。呼叫 LLM Observer 可以获得全局信息，但你会被冻结在原地——对手不会停下。迷雾带来的不是恐惧，而是**探索的刺激和信息的饥渴**。（注：人类可玩模式使用 `LINE_OF_SIGHT` 视野策略，不同于 LLM Agent 的 `PATH_REACH`——人类无法看到拐角后面的区域，这更符合直觉上的"视野"概念。）

**对于系统设计者**：Fog of War 是让整个游戏"有意义"的系统。没有迷雾，迷宫就是一道寻路题，任何 A* 都能秒解。有了迷雾，每一步都是在不完整信息下的决策——这才是 prompt 工程和策略深度的来源。好的迷雾系统应该让人感到"信息是珍贵的"，而不是"视野是烦人的限制"。

## Detailed Design

### Core Rules

1. **每个 Agent 拥有独立的可见性地图（VisionMap）**。两个 Agent 的视野互不影响——Agent A 探索过的区域对 Agent B 仍然是 Unknown
2. **每个 cell 对一个 Agent 有且仅有三种可见性状态**：
   - **Unknown** — 从未进入该 Agent 视野，不知道墙壁结构、不知道有无内容物
   - **Visible** — 当前在该 Agent 视野范围内，可以看到墙壁结构和该 cell 上的所有标记（钥匙、宝箱）
   - **Explored** — 曾经 Visible 但当前不在视野内，记住墙壁结构，但**不显示动态标记**（即看不到钥匙/宝箱是否还在或新出现）
3. **视野范围（策略可配置）**：以 Agent 当前位置为起点，使用 `vision_strategy` 指定的算法计算 Visible cells。**MVP 默认 `PATH_REACH`**：沿可通行路径（不穿墙）BFS 扩展最多 `vision_radius` 步可达的所有 cell 为 Visible。这是路径距离（BFS 步数），Agent 可以"感知"到拐角后方的区域。**Core 阶段 `LINE_OF_SIGHT`**：基于射线投射，仅 Agent 有直接视线的 cell 为 Visible，拐角后方不可见。两种策略共享相同的 cell 三态和 VisionMap 数据结构
4. **视野更新时机**：每当 Agent 移动到新 cell 时触发一次视野重算。Agent 不移动则视野不变。**初始视野刷新**：由 Grid Movement 的 `initialize()` 在 Mover 就位后调用 `FoW.update_vision(agent_id, spawn_pos)` 完成（见 `grid-movement.md`）。FoW 的 `initialize(maze, agent_ids)` 仅创建 VisionMap 并重置为全 UNKNOWN 状态，不自行读取 spawn 位置或刷新初始视野。这保证了初始视野计算在 Mover 已就位后执行，避免 FoW 和 Grid Movement 信号处理顺序不确定导致的竞态
5. **God View 模式**：人类观察者（Agent vs Agent 模式的玩家）看到整个迷宫的完整信息，不受迷雾影响。God View 不是 Fog of War 系统提供的——它是 Match Renderer 直接读取 MazeData 的结果
6. **迷雾不影响通行性**：Agent 可以向 Unknown 方向移动（如果没有墙壁阻挡）。迷雾限制的是**信息**，不是**行动**
7. **Marker 可见性职责分离**：FoW 只管理 cell 的三态可见性，**不负责判断 marker 的激活状态**（如钥匙是否 Active、宝箱是否已出现）。消费方获取 Agent 可见 markers 的标准工作流是：
   1. `FoW.get_visible_cells(agent_id)` → 获取可见 cell 列表
   2. `MazeData.get_markers_at(x, y)` → 获取 cell 上的 markers
   3. `KeyCollection.is_key_active(key_type)` → 过滤 Inactive 钥匙
   4. `WinCondition.is_chest_active()` → 过滤 Inactive 宝箱

   这意味着 MazeData 中从一开始就存在所有 marker（Jade/Crystal/Chest 等），但 Inactive 的 marker 由消费方（LLM Information Format / Match Renderer）在上述第 3-4 步过滤掉，而非由 FoW 过滤。FoW 不查询也不依赖 Key Collection 或 Win Condition 的状态。Visible cell 上的 marker 内容始终从 MazeData 实时读取——如果一个 marker 在已经 Visible 的 cell 上从 Inactive 变为 Active（例如 Agent 拿到 Brass Key 后 Jade Key 激活，而 Jade 恰好在当前视野内），消费方在下一次构建时即可发现，无需等待 `update_vision()`。Explored cell 上的 marker 不对 Agent 暴露（由消费方在第 2 步跳过 Explored cells 的 marker 读取来实现）

### Data Structures

```
# 枚举类型
enum CellVisibility { UNKNOWN, VISIBLE, EXPLORED }

# 单个 Agent 的可见性地图
VisionMap:
  agent_id: int                              # 0 = Agent A, 1 = Agent B
  maze: MazeData                             # 引用，用于 BFS 查询
  visibility: Array<Array<CellVisibility>>   # 二维数组 [y][x]，与 MazeData.cells 对齐
  current_visible: Array<Vector2i>           # 当前 Visible 状态的 cell 列表（缓存，每次 update 重算）

  # --- 查询接口 ---
  get_cell_visibility(x, y) -> CellVisibility    # 返回指定 cell 的可见性状态
  get_visible_cells() -> Array<Vector2i>          # 返回所有当前 Visible 的 cell，按固定顺序排序（行优先：y 升序，y 相同则 x 升序）
  get_explored_cells() -> Array<Vector2i>         # 返回所有 Explored 的 cell，同上排序规则
  get_known_cells() -> Array<Vector2i>            # 返回所有非 Unknown 的 cell（Visible + Explored）
  get_coverage() -> float                         # 返回探索覆盖率（known_count / total_cells）

  # --- 更新接口 ---
  update_vision(new_position: Vector2i)           # 重算视野：BFS 扩展，更新 visibility 数组
  reset()                                         # 所有 cell 重置为 UNKNOWN，清空 current_visible

# 迷雾管理器（管理所有 Agent 的 VisionMap）
FogOfWar:
  vision_maps: Dictionary<int, VisionMap>    # agent_id -> VisionMap
  vision_radius: int                         # 从配置文件读取，所有 Agent 共用
  vision_strategy: VisionStrategy            # 从 MatchConfig 读取（由 game_mode 自动决定）

  # --- 枚举（定义在 MatchConfig，此处引用）---
  # enum VisionStrategy { PATH_REACH, LINE_OF_SIGHT }  — 见 match-state-manager.md MatchConfig

  # --- 对外接口 ---
  initialize(maze: MazeData, agent_ids: Array<int>)   # 创建所有 Agent 的 VisionMap，重置为全 UNKNOWN 状态。初始视野刷新由 Grid Movement 的 initialize() 调用 update_vision() 完成
  update_vision(agent_id: int, new_position: Vector2i) # 委托给对应 VisionMap
  get_cell_visibility(agent_id: int, x: int, y: int) -> CellVisibility
  get_visible_cells(agent_id: int) -> Array<Vector2i>   # 行优先排序（y 升序，x 升序）
  get_explored_cells(agent_id: int) -> Array<Vector2i>  # 行优先排序（y 升序，x 升序）

  # --- 内部方法（不由外部系统直接调用）---
  _reset(agent_id: int)                                # 重置指定 Agent 的视野（由 initialize 内部调用）
  _reset_all()                                         # 重置所有 Agent 的视野（由 initialize 内部调用）
```

**设计决策**：

- **VisionMap 与 MazeData 对齐**：使用相同的 `[y][x]` 二维数组和 `(x, y)` 公开参数顺序，避免坐标系混淆
- **FogOfWar 作为外观（Facade）**：下游系统只与 `FogOfWar` 交互，不直接访问 `VisionMap`，保持接口简洁
- **current_visible 缓存**：每次 `update_vision` 时重算并缓存当前 Visible 列表，避免 `get_visible_cells()` 每次调用都遍历整个数组
- **返回列表排序固定为行优先（row-major）**：`get_visible_cells()` 和 `get_explored_cells()` 按 `(y, x)` 升序排列。固定排序保证：1) LLM Information Format 每次构建的 prompt 内容稳定（相同游戏状态产生相同文本），避免无意义抖动影响 LLM 决策；2) 测试可重现（断言可以比较有序列表）
- **agent_id 使用 int**：与 Match State Manager 的玩家标识保持一致（0 = Agent A, 1 = Agent B），简单够用
- **FoW 只管 cell 可见性，不过滤 marker 激活状态**：FoW 的 API 只返回 cell 坐标和可见性状态，不包含 marker 信息，也不查询 Key Collection / Win Condition 的激活状态。消费方获取 marker 内容的标准工作流见 Core Rules 第 7 条。FoW 不缓存也不过滤任何 marker 数据，从而保持依赖关系的单向性（FoW 仅依赖 MazeData，不依赖 Feature 层系统）
- **生命周期契约——总是 `initialize()`**：
  - **新比赛（新迷宫）或 Rematch（同迷宫）**：统一调用 `initialize(maze, agent_ids)`。`initialize()` 内部会：1) 创建或重建 VisionMap（匹配迷宫尺寸），2) 绑定 MazeData 引用，3) 重置所有 cell 为 UNKNOWN。Rematch 时传入同一 MazeData 即可，`initialize()` 会重置旧状态
  - **初始视野刷新**由 Grid Movement 的 `initialize()` 负责——在 Mover 就位后调用 `FoW.update_vision(agent_id, spawn_pos)`。这保证了初始视野计算在 Mover 位置确定后执行（见 `grid-movement.md` 设计说明）
  - `_reset(agent_id)` 和 `_reset_all()` 是**内部工具方法**，供 `initialize()` 内部调用。外部系统不应直接调用它们——始终通过 `initialize()` 完成生命周期管理
  - **禁止**：仅调用 `_reset_all()` 而不 `initialize()`——会导致 MazeData 引用过期

### States and Transitions

```
Agent 视角下，每个 cell 的状态机：

  ┌──────────┐
  │ Unknown  │ ◄── 初始状态（所有 cell）
  └────┬─────┘
       │ Agent 移动后，该 cell 在 vision_radius 内
       ▼
  ┌──────────┐
  │ Visible  │ ◄──┐
  └────┬─────┘    │ Agent 再次移动到范围内
       │          │
       │ Agent 移动后，该 cell 不再在 vision_radius 内
       ▼          │
  ┌──────────┐    │
  │ Explored │ ───┘
  └──────────┘
```

- **Unknown → Visible**：Agent 移动后，BFS 从 Agent 位置扩展 vision_radius 步，该 cell 可达
- **Visible → Explored**：Agent 移动后，该 cell 不再在 BFS vision_radius 范围内
- **Explored → Visible**：Agent 回到附近，该 cell 重新进入 BFS 范围
- **不存在 Explored → Unknown**：一旦探索过，永远记住墙壁结构（不会"遗忘"）
- **不存在 Visible → Unknown**：同上

### Interactions with Other Systems

| System | Direction | Interface | Data Flow |
|--------|-----------|-----------|-----------|
| **Maze Data Model** | FoW → Model | `get_neighbors(x, y)`, `has_wall(x, y, dir)` | 视野计算时沿可通行路径 BFS 扩展，需查询墙壁和邻居 |
| **Grid Movement** | Movement → FoW（初始化） | `update_vision(agent_id, position)` 直接调用 | Grid Movement 的 `initialize()` 完成 Mover 就位后，为每个 Mover 调用一次，触发初始视野计算。FoW 的 `initialize()` 仅创建 VisionMap 并重置为全 UNKNOWN——不自行刷新初始视野 |
| **Grid Movement** | FoW ← Movement（运行时） | FoW 监听 `mover_moved(mover_id, old_pos, new_pos)` 信号 | FoW 自行监听 `mover_moved`，在 handler 中调用内部 `update_vision(agent_id, new_pos)` 重算视野。Grid Movement 运行时不主动调用 FoW |
| **LLM Information Format** | LLMFormat → FoW | `get_cell_visibility(agent_id, x, y)`, `get_visible_cells(agent_id)`, `get_explored_cells(agent_id)` | LLM 格式化器根据可见性决定向 LLM 发送哪些 cell 的信息 |
| **Match Renderer** | Renderer → FoW | `get_cell_visibility(agent_id, x, y)` | Renderer 根据可见性状态决定每个 cell 的渲染方式（隐藏/半透明/完全显示） |
| **Key Collection** | 无直接依赖 | — | FoW 不查询 Key Collection 的状态。Marker 激活状态过滤由消费方（LLM Information Format / Match Renderer）自行调用 `KeyCollection.is_key_active()` 完成。见 Core Rules 第 7 条 |
| **Win Condition / Chest** | 无直接依赖 | — | FoW 不查询 Win Condition 的状态。宝箱激活状态过滤由消费方自行调用 `WinCondition.is_chest_active()` 完成。见 Core Rules 第 7 条 |
| **Match State Manager** | MSM → FoW | `initialize()` | COUNTDOWN 阶段，FoW 监听 `state_changed` 信号调用 `initialize(maze, agent_ids)`——仅创建 VisionMap 并重置状态，初始视野刷新由 Grid Movement 后续调用 `update_vision()` 完成。FoW 从 MatchConfig 读取 `vision_strategy` |

## Formulas

### Vision BFS（PATH_REACH 策略 — MVP 默认）

```
visible_cells = BFS(maze, agent_position, vision_radius)
```

**注意**：此算法为 `PATH_REACH` 策略的实现。BFS 沿可通行路径扩展，Agent 可以"感知"到拐角后方的 cell，只要路径距离 ≤ vision_radius。`LINE_OF_SIGHT` 策略的算法（射线投射）将在 Core 阶段设计。

算法伪代码：
```
func compute_visible_cells(maze: MazeData, origin: Vector2i, radius: int) -> Array<Vector2i>:
    queue = [(origin, 0)]       # (位置, 距离)
    visited = {origin: 0}
    result = [origin]

    while queue is not empty:
        (pos, dist) = queue.pop_front()
        if dist >= radius:
            continue
        for neighbor in maze.get_neighbors(pos.x, pos.y):
            if neighbor not in visited:
                visited[neighbor] = dist + 1
                result.append(neighbor)
                queue.push_back((neighbor, dist + 1))

    return result
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| maze | MazeData | — | 当前迷宫实例 | 提供 `get_neighbors()` 用于 BFS 扩展 |
| origin | Vector2i | (0,0) to (width-1, height-1) | Agent 当前位置 | BFS 起点 |
| radius | int | 0 to 10 | 配置文件 `vision_radius`（运行时支持 0，配置安全范围 1-10） | 最大 BFS 扩展步数 |
| visible_cells | Array\<Vector2i\> | 1 to min(π·r², w·h) 个元素 | 计算结果 | 所有在视野范围内的 cell 坐标 |

**预期输出范围**：
- `vision_radius = 1`：最少 1 个（死胡同，四面有墙）、最多 5 个（Agent + 4 个邻居全通）
- `vision_radius = 3`：典型迷宫中约 7-15 个 cell
- `vision_radius = 5`：典型迷宫中约 15-40 个 cell

**示例计算**（vision_radius = 3，Agent 在位置 (2,2)）：
```
迷宫局部（. = 通道，| 和 - = 墙）：

  0   1   2   3   4
0 [.] [.]-[.] [.] [.]
     |         |
1 [.] [.] [.] [.]-[.]
              |
2 [.]-[.] [A] [.] [.]
                   |
3 [.] [.] [.]-[.] [.]
          |
4 [.]-[.] [.] [.] [.]

Agent 在 (2,2)，vision_radius = 3

BFS 步骤：
  距离 0: (2,2)                           → 1 cell
  距离 1: (2,1), (3,2)                    → +2 cells（(1,2) 有墙挡住，(2,3) 有墙挡住）
  距离 2: (2,0), (1,1), (3,1), (4,2)     → +4 cells
  距离 3: (1,0), (0,1), (3,0), (4,3)     → +4 cells

可见 cell 总数 = 11
```

### Exploration Coverage（探索覆盖率）

```
coverage = known_count / total_cells
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| known_count | int | 0 to w·h | VisionMap 中非 Unknown 的 cell 数量 | 已知（Visible + Explored）的 cell 总数 |
| total_cells | int | w·h | MazeData | 迷宫总 cell 数 |
| coverage | float | 0.0 to 1.0 | 计算结果 | 探索覆盖率，可用于 HUD 显示或数据分析 |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| Agent 在死胡同（三面有墙），vision_radius = 3 | 视野沿唯一通道向后延伸 3 步。可见 cell 数量远少于开阔区域 | 路径距离 BFS 自然处理，无需特殊逻辑。这也创造了有趣的信息劣势——死胡同不仅浪费移动，还限制视野 |
| Agent 位置就是 Spawn 点（比赛刚开始） | Grid Movement 的 `initialize()` 在 Mover 就位后调用 `FoW.update_vision(agent_id, spawn_pos)`，Spawn 周围 vision_radius 范围内的 cell 变为 Visible，其余保持 Unknown。FoW 的 `initialize()` 本身不执行此操作——它仅创建 VisionMap 并重置为全 UNKNOWN | 比赛开始时 Agent 不应该处于完全黑暗状态——初始位置周围的视野是必要的起步信息。初始视野刷新由 Grid Movement 负责，确保 Mover 已就位后再执行（见 grid-movement.md） |
| vision_radius = 0 | Agent 只能看到自己脚下的 cell（1 个 Visible cell）。合法但游戏性极差 | 运行时合法（BFS 不扩展，仅返回 origin），但配置文件的安全范围限制为 1-10。值 0 仅用于自动化测试 |
| 两个 Agent 在同一个 cell | 各自的 VisionMap 独立计算，互不影响。两个 Agent 都不会因为对方的存在获得额外信息 | Agent 之间不共享视野，保持信息隔离 |
| Agent 移动后又回到原位 | 之前 Explored 的 cell 中在视野范围内的重新变为 Visible，可以看到最新的标记状态（比如新出现的钥匙） | Explored → Visible 转换是核心机制，确保"回头确认"是有效策略 |
| 钥匙在 Explored 区域出现（Agent 拿到 Brass Key 后 Jade Key 显现，但 Jade Key 所在 cell 已经是 Explored） | Agent 看不到 Jade Key 出现。该 cell 显示为 Explored 状态（只有墙壁结构，无标记信息）。Agent 必须重新走到附近让该 cell 变为 Visible 才能发现 | 这是 "Information Trade-off" 支柱的关键体现——你不能假设已探索区域没有变化 |
| 宝箱在 Unknown 区域生成 | Agent 完全不知道宝箱存在或位置。必须探索到宝箱所在 cell 附近才能发现 | 符合设计决策 "Treasure Chest Visibility: Follows Fog-of-War Rules" |
| 迷宫非常小（2x2），vision_radius = 3 | 所有 cell 都在视野范围内，BFS 在 4 个 cell 内完成。整个迷宫始终 Visible，等效于无迷雾 | 小迷宫本身就不适合有意义的迷雾体验，但系统不需要特殊处理 |
| `get_cell_visibility` 查询越界坐标 | 返回 `UNKNOWN`，不崩溃 | 越界坐标视为"迷宫外部"，逻辑上确实是未知的。遵循 MazeData 相同的防御性、不崩溃的设计哲学（MazeData 越界返回 `null`，FoW 越界返回 `UNKNOWN`，行为不同但理念一致） |
| Match 重新开始（rematch，同一迷宫） | 调用 `initialize(same_maze, agent_ids)`，与新比赛流程相同。`initialize()` 内部重置所有 VisionMap 为全 UNKNOWN。初始视野由 Grid Movement 的 `initialize()` 后续调用 `update_vision()` 刷新。外部系统不需要单独调用 `_reset_all()` | 统一生命周期：无论 rematch 还是新迷宫，外部系统只需调用 `initialize()`。简化调用方责任 |
| Match 使用新迷宫开始（new match） | 调用 `initialize(new_maze, agent_ids)`。`initialize()` 会：1) 创建新的 VisionMap（匹配新迷宫尺寸），2) 绑定新 MazeData 引用，3) 重置所有 cell 为 UNKNOWN。初始视野由 Grid Movement 的 `initialize()` 后续调用 `update_vision()` 刷新 | 新迷宫的尺寸、spawn 位置、结构可能与旧迷宫完全不同。`initialize()` 内部处理所有重建逻辑 |
| `get_visible_cells(999)`（无效 agent_id） | 返回空数组 `[]`，打印警告日志 | 不崩溃，与 `get_cell_visibility(999, ...)` 返回 `UNKNOWN` 的防御策略一致 |
| `get_explored_cells(999)`（无效 agent_id） | 返回空数组 `[]`，打印警告日志 | 同上 |
| `update_vision(999, pos)`（无效 agent_id） | 忽略，打印警告日志，不创建新 VisionMap | 只有 `initialize()` 中注册的 agent_id 才有对应 VisionMap。无效 id 不应静默创建新状态 |
| `_reset(999)`（无效 agent_id） | 忽略，打印警告日志 | 同上 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Maze Data Model** | FoW depends on this | 视野 BFS 需要查询 `get_neighbors()` 和 `has_wall()` 来沿可通行路径扩展。没有 MazeData 就无法计算视野 |
| **Grid Movement** | FoW depends on this（信号 + 初始化） | **运行时**：FoW 监听 Grid Movement 的 `mover_moved` 信号，在 handler 中调用 `update_vision()` 重算视野。**初始化时**：Grid Movement 的 `initialize()` 在 Mover 就位后调用 `FoW.update_vision(agent_id, spawn_pos)` 刷新初始视野。FoW 的 `initialize()` 仅创建 VisionMap 并重置为全 UNKNOWN，不自行读取 spawn 位置。依赖方向：FoW 依赖 Grid Movement 的 `mover_moved` 信号驱动运行时视野更新，并依赖 Grid Movement 的 `initialize()` 驱动初始视野刷新 |
| **LLM Information Format** | LLMFormat depends on FoW | 格式化器查询 `get_visible_cells()` 和 `get_explored_cells()` 来决定向 LLM 发送哪些 cell 信息。FoW 提供可见性数据，LLMFormat 决定如何序列化。**Marker 激活状态过滤由 LLMFormat 自行完成**（查询 KeyCollection / WinCondition），FoW 不参与 |
| **Match Renderer** | Renderer depends on FoW | Renderer 查询 `get_cell_visibility()` 决定每个 cell 的渲染方式：Unknown = 隐藏/黑色，Explored = 半透明/灰色，Visible = 完全显示。**Marker 激活状态过滤由 Renderer 自行完成**（查询 KeyCollection / WinCondition），FoW 不参与 |
| **Key Collection** | 无直接依赖 | FoW 不查询 Key Collection 的任何接口——marker 激活过滤是消费方（LLMFormat / Renderer）的职责，不是 FoW 的职责 |
| **Win Condition / Chest** | 无直接依赖 | FoW 不查询 Win Condition 的任何接口——宝箱激活过滤是消费方的职责 |
| **Match State Manager** | MSM triggers FoW | MSM 在 COUNTDOWN 阶段通知 FoW 调用 `initialize(maze, agent_ids)`（创建 VisionMap 并重置为全 UNKNOWN；初始视野刷新由 Grid Movement 后续完成）。FoW 从 MatchConfig 读取 `vision_strategy` |
| **(上游依赖总结)** | — | FoW 依赖 Maze Data Model（BFS 查询）、Grid Movement（`mover_moved` 信号驱动运行时视野更新 + `initialize()` 驱动初始视野刷新）、Match State Manager（MatchConfig 的 `vision_strategy`）。FoW 不依赖 Key Collection、Win Condition 或任何 Feature 层系统的内部状态 |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `vision_radius` | 3 | 1 - 10 | 视野更大，Agent 获取信息更多，导航更容易，prompt 质量的影响减弱。极端情况下（radius ≥ 迷宫对角线）等效于无迷雾 | 视野更小，Agent 近乎"盲走"，导航高度依赖 prompt 中的探索策略。过小会导致游戏体验沮丧，LLM 难以做出有意义的决策 |
| `vision_strategy` | PATH_REACH | PATH_REACH / LINE_OF_SIGHT | — | — |

**`vision_strategy` 说明**：
- **PATH_REACH**（MVP 默认）：BFS 沿可通行路径扩展。Agent 可感知拐角后方区域。适合 LLM Agent——结构化文本不区分"直接可见"与"路径可达"
- **LINE_OF_SIGHT**（Core 阶段）：射线投射视线计算。拐角后方不可见。适合人类可操作模式——符合玩家对"视野"的直觉理解
- **Owner**：`vision_strategy` 的值由 `MatchConfig.game_mode` 自动决定，在 `MatchStateManager.start_setup()` 中设置（见 `match-state-manager.md` MatchConfig 定义）。FoW 从 MatchConfig 中读取该值，不自行决定
- 映射规则：AGENT_VS_AGENT → PATH_REACH；PLAYER_VS_AGENT / PLAYER_VS_PLAYER → LINE_OF_SIGHT
- MVP 阶段只实现 `PATH_REACH`，`LINE_OF_SIGHT` 延迟到 Core 阶段

**注意事项**：

- `vision_radius` 是本系统最关键的运行时调参（`vision_strategy` 由游戏模式自动决定，不是运行时调节项）
- 建议默认值 `3`：在 15x15 迷宫中，BFS 3 步大约能看到 7-15 个 cell，既提供了有用信息又保留了大量未知区域
- `vision_radius = 1` 适合"Hard Mode"——只能看到紧邻的通道，几乎每一步都是盲注
- `vision_radius = 5+` 适合新手或教程——信息充足，降低挫败感
- 该值与迷宫尺寸的比例很重要：小迷宫 + 大视野 = 无挑战，大迷宫 + 小视野 = 极高难度
- 两个 Agent 使用相同的 `vision_radius`（Fair Racing 支柱要求）
- 值必须从配置文件读取，禁止硬编码

## Visual/Audio Requirements

Fog of War 本身是纯数据系统，不直接渲染或播放音效。以下需求由 Match Renderer 消费 FoW 可见性数据来实现：

| Visibility State | Visual Treatment | Priority | Responsible System |
|-----------------|-----------------|----------|--------------------|
| **Unknown** | 完全遮挡——黑色/深色覆盖，不显示墙壁结构和任何内容 | MVP | Match Renderer |
| **Explored** | 半透明灰色覆盖——可以看到墙壁和通道结构，但颜色暗淡。不显示该 cell 上的标记（钥匙/宝箱） | MVP | Match Renderer |
| **Visible** | 完全显示——正常亮度，墙壁、通道、标记（钥匙/宝箱）全部可见 | MVP | Match Renderer |

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|----------------|---------------|----------|
| Cell 从 Unknown → Visible（首次进入视野） | 迷雾消散动画（黑色淡出），cell 内容浮现 | 可选：轻微揭示音效（柔和的"嘶"声） | MVP (视觉) / Full (音效) |
| Cell 从 Explored → Visible（重新进入视野） | 灰色覆盖淡出至完全显示，无特殊动画 | 无 | MVP |
| Cell 从 Visible → Explored（离开视野） | 完全显示渐变为灰色半透明覆盖 | 无 | MVP |
| Agent 发现钥匙（Visible cell 上有当前需要的钥匙） | 钥匙图标出现时有短暂高亮/脉冲动画 | 可选：发现音效（与拾取音效不同） | Full |

**God View 特殊处理**：人类观察者的 God View 不经过 FoW 渲染——所有 cell 始终以完全显示状态渲染，由 Match Renderer 根据观察模式切换渲染路径。

## Acceptance Criteria

### 核心功能
- [ ] `FogOfWar.initialize(maze, [0, 1])` 后，所有 cell 为 `UNKNOWN` 状态（VisionMap 创建但未刷新初始视野）。初始视野刷新由 Grid Movement 的 `initialize()` 调用 `update_vision(agent_id, spawn_pos)` 完成——此后 Spawn 位置及 BFS vision_radius 范围内的 cell 变为 `VISIBLE`
- [ ] `initialize()` 仅创建 VisionMap 并重置状态，不自行从 MazeData 读取 spawn 位置或调用 `update_vision()`——初始视野刷新是 Grid Movement 的职责
- [ ] Agent A 的视野更新不影响 Agent B 的 VisionMap——两个 Agent 的可见性完全独立
- [ ] Agent 移动后，之前 `VISIBLE` 但不在新视野范围内的 cell 转为 `EXPLORED`
- [ ] Agent 回到之前探索过的区域，`EXPLORED` cell 重新变为 `VISIBLE`
- [ ] `EXPLORED` cell 不会退化为 `UNKNOWN`——一旦探索过永远记住墙壁结构

### 视野计算
- [ ] 视野使用路径距离（BFS 步数），不穿墙：隔一面墙的相邻 cell 不可见，即使直线距离为 1
- [ ] `vision_radius = 3` 时，在死胡同中可见 cell 数量明显少于在开阔通道中
- [ ] `vision_radius = 0` 时，Agent 只能看到自己脚下的 1 个 cell

### 信息可见性
- [ ] 消费方可通过 `FoW.get_visible_cells()` + `MazeData.get_markers_at()` + `KeyCollection.is_key_active()` / `WinCondition.is_chest_active()` 获取 Agent 视野内的**已激活**标记信息（marker 激活过滤由消费方完成，FoW 不参与）
- [ ] `EXPLORED` cell 虽可查到坐标，但消费方不应向 Agent 暴露其上的标记内容（由 LLM Information Format / Renderer 执行此过滤）
- [ ] FoW 不查询 KeyCollection 或 WinCondition 的任何接口——FoW 的 API 只涉及 cell 可见性状态
- [ ] 钥匙在 `EXPLORED` 区域新出现时，Agent 必须重新进入视野范围（cell 变为 `VISIBLE`）才能获知
- [ ] 钥匙在已 `VISIBLE` 的 cell 上新出现时，Agent 立即可见（marker 从 MazeData 实时读取，不需要额外 update_vision）
- [ ] 钥匙拾取不依赖可见性——Agent 站在钥匙 cell 上即可拾取（由 Key Collection 负责）

### 边界与防御
- [ ] `get_cell_visibility(agent_id, -1, 0)` 返回 `UNKNOWN`，不崩溃
- [ ] `get_cell_visibility(999, 0, 0)`（无效 agent_id）返回 `UNKNOWN`，打印警告日志
- [ ] `get_visible_cells(999)`（无效 agent_id）返回空数组 `[]`，打印警告日志
- [ ] `get_explored_cells(999)`（无效 agent_id）返回空数组 `[]`，打印警告日志
- [ ] `update_vision(999, pos)`（无效 agent_id）忽略操作，打印警告日志，不创建新 VisionMap
- [ ] `_reset(999)`（无效 agent_id）忽略操作，打印警告日志
- [ ] `_reset(0)` 后 Agent A 的所有 cell 重置为 `UNKNOWN`，Agent B 不受影响

### 生命周期
- [ ] Rematch 时再次调用 `initialize(same_maze, agent_ids)` 等效于对同一迷宫重新开始，VisionMap 重置为全 UNKNOWN，旧状态完全清除。初始视野由 Grid Movement 后续调用 `update_vision()` 刷新
- [ ] 使用新迷宫调用 `initialize(new_maze, agent_ids)` 后，VisionMap 尺寸匹配新迷宫，旧迷宫状态完全清除
- [ ] `_reset(agent_id)` 和 `_reset_all()` 为内部方法，不需要外部系统直接调用
- [ ] `get_visible_cells()` 和 `get_explored_cells()` 返回的列表按行优先排序（y 升序，x 升序），相同游戏状态产生相同顺序

### 性能
- [ ] 对 50x50 迷宫 + vision_radius = 10，单次 `update_vision()` 在 2ms 内完成
- [ ] `get_cell_visibility()` 为 O(1) 查询（直接数组索引访问）
- [ ] `get_visible_cells()` 返回缓存结果，不触发重新计算

### 配置
- [ ] `vision_radius` 从外部配置文件读取，禁止硬编码
- [ ] `vision_strategy` 从 `MatchConfig` 读取（由 `game_mode` 自动决定），MVP 默认 `PATH_REACH`
- [ ] 两个 Agent 使用相同的 `vision_radius` 值和 `vision_strategy`

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Explored 不显示动态标记是否对 LLM 过于严苛？LLM 可能无法推理"之前经过时没钥匙，现在可能有了" | Game Designer | Prototype 阶段 | 需要 playtest 验证。备选方案：Explored cell 也显示标记（降低难度），或在 LLM Information Format 中显式告知"已探索区域可能有新物品" |
| vision_radius 的最佳默认值？文档建议 3，但实际体验取决于迷宫密度和 LLM 导航能力 | Game Designer | Prototype 阶段 | 原型阶段用多个值（2, 3, 5）测试，观察 LLM 导航成功率和比赛时长 |
| 是否需要一个 `recommended_radius(maze_size)` 公式来自动适配不同大小的迷宫？ | Game Designer | Sprint 2 | MVP 使用固定值即可。如果支持多种迷宫尺寸，考虑 `radius = max(1, floor(min(width, height) / 5))` 作为起点 |
| Agent 是否应该能"看到"对方 Agent 的位置（如果在视野范围内）？ | Game Designer | Sprint 1 | 当前设计未涉及。MVP 中两个 Agent 互不可见。未来可作为可选规则添加 |
