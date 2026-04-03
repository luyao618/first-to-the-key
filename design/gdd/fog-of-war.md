# Fog of War / Vision

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-01
> **System Index**: #6
> **Layer**: Core
> **Implements Pillar**: Information Trade-off, Fair Racing

## Overview

Fog of War / Vision 是迷宫竞速中的**信息控制系统**，决定每个 Agent 在任何给定时刻能"看到"迷宫的哪些部分。它将迷宫划分为三种可见性状态：**未知（Unknown）**、**已探索（Explored）**、**可见（Visible）**。Agent 当前位置周围一定范围内的 cell 处于 Visible 状态，Agent 离开后这些 cell 退化为 Explored（记住结构但不显示动态内容），从未进入视野的区域保持 Unknown。

该系统是 "Information Trade-off" 设计支柱的核心载体——迷雾迫使 Agent 在不完整信息下做决策，使 prompt 质量成为决定性因素：好的 prompt 教会 Agent 系统性探索，差的 prompt 导致 Agent 在迷雾中盲目徘徊。对于 God View 的人类观察者来说，迷雾不影响其视野——他们看到完整地图，但只能通过消息（带冻结惩罚）向 Agent 传递信息。

Fog of War 不处理渲染（由 Match Renderer 消费可见性数据）、不处理移动（仅在 Agent 移动后更新视野）、不决定 LLM 收到什么文本（由 LLM Information Format 根据可见性数据构建）。它只维护一个核心职责：**管理每个 Agent 对迷宫的可见性状态**。

## Player Fantasy

**对于 prompt 策略师（Agent vs Agent 模式）**：你的 AI 是一个被蒙上眼睛的迷宫跑者——它只能看到脚下几格的范围。你坐在 God View 里看着完整地图，心里清楚地知道钥匙在哪、最短路径是什么，但你无法直接操控它。你唯一能做的，是在赛前通过 prompt 教会它在黑暗中如何做决策。当你的 AI 走到岔路口，果断选择了正确方向——那一刻你知道，是你的 prompt 教会了它"靠墙走"或"优先探索未知方向"。那种成就感不是来自操作，而是来自**教导**。

**对于迷雾中的探索者（Player vs Player / Player vs Agent 模式）**：你身处迷雾中，视野只有周围几格。每走一步，迷雾退开一点，新的墙壁和通道浮现。你不知道钥匙在哪，不知道对手走到了哪里，但你知道你每一步都在缩小未知的范围。呼叫 LLM Observer 可以获得全局信息，但你会被冻结在原地——对手不会停下。迷雾带来的不是恐惧，而是**探索的刺激和信息的饥渴**。

**对于系统设计者**：Fog of War 是让整个游戏"有意义"的系统。没有迷雾，迷宫就是一道寻路题，任何 A* 都能秒解。有了迷雾，每一步都是在不完整信息下的决策——这才是 prompt 工程和策略深度的来源。好的迷雾系统应该让人感到"信息是珍贵的"，而不是"视野是烦人的限制"。

## Detailed Design

### Core Rules

1. **每个 Agent 拥有独立的可见性地图（VisionMap）**。两个 Agent 的视野互不影响——Agent A 探索过的区域对 Agent B 仍然是 Unknown
2. **每个 cell 对一个 Agent 有且仅有三种可见性状态**：
   - **Unknown** — 从未进入该 Agent 视野，不知道墙壁结构、不知道有无内容物
   - **Visible** — 当前在该 Agent 视野范围内，可以看到墙壁结构和该 cell 上的所有标记（钥匙、宝箱）
   - **Explored** — 曾经 Visible 但当前不在视野内，记住墙壁结构，但**不显示动态标记**（即看不到钥匙/宝箱是否还在或新出现）
3. **视野范围**：以 Agent 当前位置为起点，沿**可通行路径**（不穿墙）扩展最多 `vision_radius` 步可达的所有 cell 为 Visible。这是**路径距离**（BFS 步数），不是欧几里得距离
4. **视野更新时机**：每当 Agent 移动到新 cell 时触发一次视野重算。Agent 不移动则视野不变
5. **God View 模式**：人类观察者（Agent vs Agent 模式的玩家）看到整个迷宫的完整信息，不受迷雾影响。God View 不是 Fog of War 系统提供的——它是 Match Renderer 直接读取 MazeData 的结果
6. **迷雾不影响通行性**：Agent 可以向 Unknown 方向移动（如果没有墙壁阻挡）。迷雾限制的是**信息**，不是**行动**
7. **Marker 实时读取**：FoW 不缓存 marker 信息。Visible cell 上的 marker 始终从 MazeData 实时读取。如果一个新 marker（如下一把钥匙）出现在已经 Visible 的 cell 上，Agent 立即可见，无需等待移动触发 `update_vision()`。Explored cell 上的 marker 不对 Agent 暴露，无论 marker 何时出现

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
  get_visible_cells() -> Array<Vector2i>          # 返回所有当前 Visible 的 cell
  get_explored_cells() -> Array<Vector2i>         # 返回所有 Explored 的 cell
  get_known_cells() -> Array<Vector2i>            # 返回所有非 Unknown 的 cell（Visible + Explored）
  get_coverage() -> float                         # 返回探索覆盖率（known_count / total_cells）

  # --- 更新接口 ---
  update_vision(new_position: Vector2i)           # 重算视野：BFS 扩展，更新 visibility 数组
  reset()                                         # 所有 cell 重置为 UNKNOWN，清空 current_visible

# 迷雾管理器（管理所有 Agent 的 VisionMap）
FogOfWar:
  vision_maps: Dictionary<int, VisionMap>    # agent_id -> VisionMap
  vision_radius: int                         # 从配置文件读取，所有 Agent 共用

  # --- 对外接口 ---
  initialize(maze: MazeData, agent_ids: Array<int>)   # 创建所有 Agent 的 VisionMap
  update_vision(agent_id: int, new_position: Vector2i) # 委托给对应 VisionMap
  get_cell_visibility(agent_id: int, x: int, y: int) -> CellVisibility
  get_visible_cells(agent_id: int) -> Array<Vector2i>
  get_explored_cells(agent_id: int) -> Array<Vector2i>
  reset(agent_id: int)                                 # 重置指定 Agent 的视野
  reset_all()                                          # 重置所有 Agent 的视野
```

**设计决策**：

- **VisionMap 与 MazeData 对齐**：使用相同的 `[y][x]` 二维数组和 `(x, y)` 公开参数顺序，避免坐标系混淆
- **FogOfWar 作为外观（Facade）**：下游系统只与 `FogOfWar` 交互，不直接访问 `VisionMap`，保持接口简洁
- **current_visible 缓存**：每次 `update_vision` 时重算并缓存当前 Visible 列表，避免 `get_visible_cells()` 每次调用都遍历整个数组
- **agent_id 使用 int**：与 Match State Manager 的玩家标识保持一致（0 = Agent A, 1 = Agent B），简单够用
- **FoW 只管 cell 可见性，不缓存 marker**：FoW 的 API 只返回 cell 坐标和可见性状态，不包含 marker 信息。消费方获取 marker 内容的标准工作流是：`FoW.get_visible_cells(agent_id)` → 遍历结果 → `MazeData.get_markers_at(x, y)`。这意味着 Visible cell 上的 marker 内容始终从 MazeData 实时读取——如果一个 marker 在已经 Visible 的 cell 上新出现（例如 Agent 拿到 Brass Key 后 Jade Key 在当前视野内显现），Agent 立即可见，无需等待下次 `update_vision()`

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
| **Grid Movement** | Movement → FoW（初始化） | `update_vision(agent_id, position)` 直接调用 | Grid Movement 的 `initialize()` 完成 Mover 就位后，为每个 Mover 调用一次，触发初始视野计算 |
| **Grid Movement** | FoW ← Movement（运行时） | FoW 监听 `mover_moved(mover_id, old_pos, new_pos)` 信号 | FoW 自行监听 `mover_moved`，在 handler 中调用内部 `update_vision(agent_id, new_pos)` 重算视野。Grid Movement 运行时不主动调用 FoW |
| **LLM Information Format** | LLMFormat → FoW | `get_cell_visibility(agent_id, x, y)`, `get_visible_cells(agent_id)`, `get_explored_cells(agent_id)` | LLM 格式化器根据可见性决定向 LLM 发送哪些 cell 的信息 |
| **Match Renderer** | Renderer → FoW | `get_cell_visibility(agent_id, x, y)` | Renderer 根据可见性状态决定每个 cell 的渲染方式（隐藏/半透明/完全显示） |
| **Key Collection** | Keys → FoW | `get_cell_visibility(agent_id, x, y)` | 判断 Agent 是否能"看到"某个钥匙（Visible 状态下才显示钥匙图标） |
| **Match State Manager** | MSM → FoW | `reset(agent_id)` | Match 开始时初始化/重置所有 cell 为 Unknown，Match 结束时清理 |

## Formulas

### Vision BFS（视野计算）

```
visible_cells = BFS(maze, agent_position, vision_radius)
```

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
| Agent 位置就是 Spawn 点（比赛刚开始） | 第一次 `update_vision` 在 Agent 放置到 Spawn 位置时触发，Spawn 周围 vision_radius 范围内的 cell 变为 Visible，其余保持 Unknown | 比赛开始时 Agent 不应该处于完全黑暗状态——初始位置周围的视野是必要的起步信息 |
| vision_radius = 0 | Agent 只能看到自己脚下的 cell（1 个 Visible cell）。合法但游戏性极差 | 运行时合法（BFS 不扩展，仅返回 origin），但配置文件的安全范围限制为 1-10。值 0 仅用于自动化测试 |
| 两个 Agent 在同一个 cell | 各自的 VisionMap 独立计算，互不影响。两个 Agent 都不会因为对方的存在获得额外信息 | Agent 之间不共享视野，保持信息隔离 |
| Agent 移动后又回到原位 | 之前 Explored 的 cell 中在视野范围内的重新变为 Visible，可以看到最新的标记状态（比如新出现的钥匙） | Explored → Visible 转换是核心机制，确保"回头确认"是有效策略 |
| 钥匙在 Explored 区域出现（Agent 拿到 Brass Key 后 Jade Key 显现，但 Jade Key 所在 cell 已经是 Explored） | Agent 看不到 Jade Key 出现。该 cell 显示为 Explored 状态（只有墙壁结构，无标记信息）。Agent 必须重新走到附近让该 cell 变为 Visible 才能发现 | 这是 "Information Trade-off" 支柱的关键体现——你不能假设已探索区域没有变化 |
| 宝箱在 Unknown 区域生成 | Agent 完全不知道宝箱存在或位置。必须探索到宝箱所在 cell 附近才能发现 | 符合设计决策 "Treasure Chest Visibility: Follows Fog-of-War Rules" |
| 迷宫非常小（2x2），vision_radius = 3 | 所有 cell 都在视野范围内，BFS 在 4 个 cell 内完成。整个迷宫始终 Visible，等效于无迷雾 | 小迷宫本身就不适合有意义的迷雾体验，但系统不需要特殊处理 |
| `get_cell_visibility` 查询越界坐标 | 返回 `UNKNOWN`，不崩溃 | 越界坐标视为"迷宫外部"，逻辑上确实是未知的。遵循 MazeData 相同的防御性、不崩溃的设计哲学（MazeData 越界返回 `null`，FoW 越界返回 `UNKNOWN`，行为不同但理念一致） |
| Match 重新开始（rematch） | 调用 `reset(agent_id)` 将该 Agent 的所有 cell 重置为 Unknown | 每场比赛的迷雾状态必须是全新的，不能继承上局记忆 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Maze Data Model** | FoW depends on this | 视野 BFS 需要查询 `get_neighbors()` 和 `has_wall()` 来沿可通行路径扩展。没有 MazeData 就无法计算视野 |
| **Grid Movement** | FoW depends on this（信号 + 初始化调用） | **运行时**：FoW 监听 Grid Movement 的 `mover_moved` 信号，在 handler 中调用 `update_vision()` 重算视野。**初始化时**：Grid Movement 的 `initialize()` 完成 Mover 就位后，主动调用 `FoW.update_vision()` 触发初始视野计算。依赖方向：FoW 依赖 Grid Movement 的信号和初始化调用来驱动视野更新 |
| **LLM Information Format** | LLMFormat depends on FoW | 格式化器查询 `get_visible_cells()` 和 `get_explored_cells()` 来决定向 LLM 发送哪些 cell 信息。FoW 提供可见性数据，LLMFormat 决定如何序列化 |
| **Match Renderer** | Renderer depends on FoW | Renderer 查询 `get_cell_visibility()` 决定每个 cell 的渲染方式：Unknown = 隐藏/黑色，Explored = 半透明/灰色，Visible = 完全显示 |
| **Key Collection** | Keys → FoW（信息层面） | FoW 决定 Agent 是否**知道**某把钥匙的存在（仅 Visible cell 上的标记对 Agent 信息可见）。注意：钥匙**拾取判定**不依赖可见性——Agent 站在钥匙 cell 上即可拾取，无论该 cell 之前是否在视野中。FoW 影响的是 LLM 是否收到钥匙位置信息，而非拾取逻辑 |
| **Win Condition / Chest** | WinCon → FoW（信息层面） | FoW 查询 `is_chest_active()` 判断宝箱是否已出现。Inactive 的宝箱不向 Agent 暴露 marker 信息，Active 的宝箱遵循正常视野规则——Agent 视野范围内才可见。与 Key Collection 的可见性逻辑一致 |
| **Match State Manager** | MSM triggers FoW | Match 开始时通知 FoW 初始化 VisionMap，Match 结束时通知 FoW 清理资源 |
| **(上游依赖总结)** | — | Fog of War 依赖 Maze Data Model（BFS 查询）和 Grid Movement（`mover_moved` 信号驱动视野更新 + `initialize()` 时直接调用）。这两个依赖都是单向的——FoW 消费它们的数据/信号，它们不依赖 FoW 的内部状态 |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `vision_radius` | 3 | 1 - 10 | 视野更大，Agent 获取信息更多，导航更容易，prompt 质量的影响减弱。极端情况下（radius ≥ 迷宫对角线）等效于无迷雾 | 视野更小，Agent 近乎"盲走"，导航高度依赖 prompt 中的探索策略。过小会导致游戏体验沮丧，LLM 难以做出有意义的决策 |

**注意事项**：

- `vision_radius` 是本系统唯一的核心调参。系统设计刻意保持简洁——只有一个旋钮
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
- [ ] `FogOfWar.initialize(maze, [0, 1])` 后，所有 cell 对两个 Agent 均为 `UNKNOWN`
- [ ] `update_vision(0, spawn_a_pos)` 后，Agent A 的 Spawn 位置及 BFS vision_radius 范围内的 cell 变为 `VISIBLE`，范围外保持 `UNKNOWN`
- [ ] Agent A 的视野更新不影响 Agent B 的 VisionMap——两个 Agent 的可见性完全独立
- [ ] Agent 移动后，之前 `VISIBLE` 但不在新视野范围内的 cell 转为 `EXPLORED`
- [ ] Agent 回到之前探索过的区域，`EXPLORED` cell 重新变为 `VISIBLE`
- [ ] `EXPLORED` cell 不会退化为 `UNKNOWN`——一旦探索过永远记住墙壁结构

### 视野计算
- [ ] 视野使用路径距离（BFS 步数），不穿墙：隔一面墙的相邻 cell 不可见，即使直线距离为 1
- [ ] `vision_radius = 3` 时，在死胡同中可见 cell 数量明显少于在开阔通道中
- [ ] `vision_radius = 0` 时，Agent 只能看到自己脚下的 1 个 cell

### 信息可见性
- [ ] 消费方可通过 `FoW.get_visible_cells()` + `MazeData.get_markers_at()` 获取 Agent 视野内的标记信息
- [ ] `EXPLORED` cell 虽可查到坐标，但消费方不应向 Agent 暴露其上的标记内容（由 LLM Information Format / Renderer 执行此过滤）
- [ ] 钥匙在 `EXPLORED` 区域新出现时，Agent 必须重新进入视野范围（cell 变为 `VISIBLE`）才能获知
- [ ] 钥匙在已 `VISIBLE` 的 cell 上新出现时，Agent 立即可见（marker 从 MazeData 实时读取，不需要额外 update_vision）
- [ ] 钥匙拾取不依赖可见性——Agent 站在钥匙 cell 上即可拾取（由 Key Collection 负责）

### 边界与防御
- [ ] `get_cell_visibility(agent_id, -1, 0)` 返回 `UNKNOWN`，不崩溃
- [ ] `get_cell_visibility(999, 0, 0)`（无效 agent_id）返回 `UNKNOWN`，打印警告日志
- [ ] `reset(0)` 后 Agent A 的所有 cell 重置为 `UNKNOWN`，Agent B 不受影响

### 性能
- [ ] 对 50x50 迷宫 + vision_radius = 10，单次 `update_vision()` 在 2ms 内完成
- [ ] `get_cell_visibility()` 为 O(1) 查询（直接数组索引访问）
- [ ] `get_visible_cells()` 返回缓存结果，不触发重新计算

### 配置
- [ ] `vision_radius` 从外部配置文件读取，禁止硬编码
- [ ] 两个 Agent 使用相同的 `vision_radius` 值

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Explored 不显示动态标记是否对 LLM 过于严苛？LLM 可能无法推理"之前经过时没钥匙，现在可能有了" | Game Designer | Prototype 阶段 | 需要 playtest 验证。备选方案：Explored cell 也显示标记（降低难度），或在 LLM Information Format 中显式告知"已探索区域可能有新物品" |
| vision_radius 的最佳默认值？文档建议 3，但实际体验取决于迷宫密度和 LLM 导航能力 | Game Designer | Prototype 阶段 | 原型阶段用多个值（2, 3, 5）测试，观察 LLM 导航成功率和比赛时长 |
| 是否需要一个 `recommended_radius(maze_size)` 公式来自动适配不同大小的迷宫？ | Game Designer | Sprint 2 | MVP 使用固定值即可。如果支持多种迷宫尺寸，考虑 `radius = max(1, floor(min(width, height) / 5))` 作为起点 |
| Agent 是否应该能"看到"对方 Agent 的位置（如果在视野范围内）？ | Game Designer | Sprint 1 | 当前设计未涉及。MVP 中两个 Agent 互不可见。未来可作为可选规则添加 |
