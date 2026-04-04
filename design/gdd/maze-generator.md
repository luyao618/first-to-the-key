# Maze Generator

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-04
> **System Index**: #4
> **Layer**: Core
> **Implements Pillar**: Fair Racing, Simple Rules Deep Play

## Overview

Maze Generator 是在每场比赛开始前自动运行的程序化迷宫生成系统。它接收迷宫尺寸参数，使用 Recursive Backtracker（深度优先搜索）算法在 Maze Data Model 的全墙网格上"打通"墙壁，生成一个完全连通的迷宫。生成迷宫结构后，系统将两个玩家的 Spawn 点放置在固定对角位置（左上角 `(0,0)` / 右下角 `(width-1, height-1)`），再将三把钥匙（Brass、Jade、Crystal）和一个宝箱随机散布在迷宫中。最后执行公平性后验证：使用 BFS 计算双方到每个目标的最短路径，确认路径差异在允许阈值内（默认 ≤ 2 步）。如果验证失败，系统重新生成整个迷宫，直到通过或达到最大重试次数。Maze Generator 不参与比赛进行中的任何逻辑——它在 Match State Manager 的 SETUP 阶段一次性生成迷宫，调用 `MazeData.finalize()` 锁定数据，然后退出。玩家不直接操作这个系统，但每场比赛的地图体验完全由它决定。

## Player Fantasy

Maze Generator 是完全隐形的系统——玩家永远不会意识到它的存在，但每一秒的游戏体验都建立在它的输出上。它塑造的是两种感受：

**"这张地图很有趣"**：好的迷宫让人想探索。Recursive Backtracker 生成的长蜿蜒走廊创造出"拐角背后有什么"的好奇心，岔路口迫使 Agent（和写 prompt 的你）做出方向选择。死胡同不是浪费——它们惩罚盲目探索，奖励系统化搜索策略。当你看到自己的 AI 在死胡同里掉头，你就知道下一局该怎么改 prompt 了。

**"比赛是公平的"**：你输了比赛，但不是因为对手的起点离钥匙更近。公平性验证确保每张地图在结构上给双方大致相等的机会。胜负归结于 prompt 质量和 Agent 决策，而非地图运气。这是 Fair Racing pillar 的基石：*"Victory is determined by decision quality, not luck or information asymmetry."*

## Detailed Design

### Core Rules

1. Maze Generator 在 Match State Manager 的 **SETUP** 阶段运行，由 `state_changed` 信号触发
2. 生成是**同步阻塞**操作——SETUP 阶段不会结束直到迷宫生成完成（或达到最大重试次数失败）
3. Generator 是一次性执行系统：生成完成后调用 `MazeData.finalize()`，此后不再参与比赛的任何逻辑
4. 由 Generator 自行创建 `MazeData` 实例（`MazeData.new(width, height)`），初始化为全墙网格。生成完成后通过 `maze_generated` 信号将实例传递给其他系统
5. 使用 **Recursive Backtracker（DFS + 随机邻居选择）** 算法打通墙壁：
   - 从随机起始 cell 开始
   - 随机选择一个未访问的相邻 cell
   - 移除两者之间的墙壁（调用 `MazeData.set_wall()`）
   - 推进到新 cell
   - 无未访问邻居时回溯
   - 所有 cell 被访问后结束
   - **实现要求**：使用迭代 + 显式栈实现（非递归），避免大迷宫（50×50 = 2500 cells）触发 GDScript 栈溢出
6. 算法保证生成完全连通的完美迷宫（Perfect Maze：任意两点之间恰好存在一条路径，无环路）
7. Spawn 点固定在对角：`SPAWN_A` 放置在 `(0, 0)`，`SPAWN_B` 放置在 `(width - 1, height - 1)`
8. 三把钥匙（`KEY_BRASS`、`KEY_JADE`、`KEY_CRYSTAL`）和一个 `CHEST` 随机放置，约束：
   - 不可放置在 Spawn 点所在的 cell
   - 不可放置在已有其他 marker 的 cell（每个 marker 独占一个 cell）
   - 从所有满足约束的空 cell 中均匀随机选取
9. 放置顺序：Spawn → Keys → Chest
10. 公平性验证：对每个目标分别计算双方最短路径差：
    - `|path(SPAWN_A → target) - path(SPAWN_B → target)| <= max_fairness_delta`
    - 目标包括：`KEY_BRASS`、`KEY_JADE`、`KEY_CRYSTAL`、`CHEST`（共 4 项）
    - 所有 4 项必须全部通过，任一失败则整体失败
    - `max_fairness_delta` 默认值 `2`
    - **MVP 局限性**：此验证是逐目标独立检查，不考虑钥匙收集的顺序路径（Brass → Jade → Crystal → Chest）。单点 delta 公平不等于全程 race route 公平。见 Open Questions 中的详细讨论
11. 验证失败时，调用 `MazeData.reset()` 将同一实例恢复为全墙并清除 markers，从头执行完整生成流程
12. 最大重试次数 `max_generation_retries` 默认 `50`；达到上限仍未通过则发出 `generation_failed` 信号，不降级
13. 验证通过后调用 `MazeData.finalize()` 锁定数据。若 `finalize()` 返回 `false`（`is_valid()` 检测到异常），视为生成失败，执行重试。若重试耗尽则发出 `generation_failed` 信号
14. 生成完成且 `finalize()` 成功后，发出 `maze_generated` 信号

### States and Transitions

```
  ┌──────────┐   state_changed(SETUP)   ┌────────────┐
  │   IDLE   │ ─────────────────────────► │ GENERATING │
  └──────────┘                            └─────┬──────┘
                                                │ DFS 完成
                                                ▼
                                          ┌────────────┐
                                          │  PLACING   │
                                          └─────┬──────┘
                                                │ markers 放置完成
                                                ▼
                                          ┌────────────┐
                                          │ VALIDATING │──── 失败且未达重试上限 ──► GENERATING
                                          └─────┬──────┘
                                            通过 │        失败且达到上限
                                                ▼              ▼
                                          ┌──────────┐   ┌──────────┐
                                          │   DONE   │   │  FAILED  │
                                          └──────────┘   └──────────┘
```

| State | 行为 | 退出条件 |
|-------|------|---------|
| **IDLE** | 等待触发，不占用资源 | 收到 SETUP 信号 |
| **GENERATING** | 执行 Recursive Backtracker，打通墙壁 | DFS 遍历完所有 cell |
| **PLACING** | 放置 Spawn 点、钥匙、宝箱 | 所有 markers 放置完成 |
| **VALIDATING** | BFS 公平性验证 4 个目标 | 全部通过 → DONE；任一失败 → 重试或 FAILED |
| **DONE** | 调用 `finalize()`，发出 `maze_generated` | 终态 |
| **FAILED** | 发出 `generation_failed` | 终态 |

> **实现说明**：整个流程是同步阻塞的，这些"状态"是函数内的执行步骤，不需要用正式的状态机实现。描述为状态是为了文档清晰度。

### Interactions with Other Systems

| System | Direction | Interface | Data Flow |
|--------|-----------|-----------|-----------|
| **Match State Manager** | Manager → Generator | 监听 `state_changed` 信号 | SETUP 阶段触发生成流程 |
| **Maze Data Model** | Generator → Model | `set_wall()`, `place_marker()`, `finalize()`, `get_shortest_path()` | 写入墙壁和 markers，验证公平性，最终锁定数据 |
| **Match State Manager** | Generator → Manager | `maze_generated` / `generation_failed` 信号 | 通知生成结果，Manager 据此决定是否进入 COUNTDOWN 或显示错误 |
| **Grid Movement** | 无直接交互 | — | Grid Movement 读取的是 finalized 后的 MazeData，不经过 Generator |
| **Fog of War** | 无直接交互 | — | 同上 |
| **Match Renderer** | 无直接交互 | — | 同上 |

**关键点**：Maze Generator 只与两个系统直接交互——Match State Manager（触发和结果通知）和 Maze Data Model（数据写入和验证）。生成完成后，Generator 通过 `maze_generated` 信号将 finalized 的 MazeData 实例传递给 Match State Manager，MSM 将其存储在 `current_maze` 字段中。所有其他系统通过 MSM 的 `get_maze()` 或 `state_changed` 信号间接获取迷宫引用。

**信号定义**：

```
signal maze_generated(maze_data: MazeData)    # 生成成功，携带 finalized 的迷宫实例
signal generation_failed(retry_count: int, reason: String)  # 生成失败，携带已重试次数和失败原因
```

## Formulas

### Fairness Validation

```
path_length(A, B) = MazeData.get_shortest_path(A, B).size() - 1
fairness_delta(target) = abs(path_length(SPAWN_A, target) - path_length(SPAWN_B, target))
is_fair(target) = fairness_delta(target) <= max_fairness_delta
is_maze_fair = is_fair(KEY_BRASS) AND is_fair(KEY_JADE) AND is_fair(KEY_CRYSTAL) AND is_fair(CHEST)
```

> **API 转换说明**：`MazeData.get_shortest_path()` 返回 `Array<Vector2i>`（路径坐标数组），步数 = 数组长度 - 1（起点不算步数）。

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| target | Vector2i | 迷宫内任意坐标 | marker 位置 | 验证目标（钥匙或宝箱的坐标） |
| path_length(A, B) | int | 1 to width×height−1 | `MazeData.get_shortest_path().size() - 1` | 两点间 BFS 最短路径步数 |
| fairness_delta | int | 0+ | 计算结果 | 双方到同一目标的路径差 |
| max_fairness_delta | int | 0 to 5 | 配置文件 | 允许的最大路径差异，默认 `2` |
| is_maze_fair | bool | — | 计算结果 | 迷宫是否通过公平性验证 |

**预期值**：15×15 Perfect Maze 中，对角 spawn 到中心区域的最短路径约 15-40 步。delta 通常 0-5，`max_fairness_delta = 2` 下通过率约 60-80%（即平均 1-2 次重试）。

### Algorithm Complexity

```
DFS 时间复杂度 = O(width × height)
BFS 验证复杂度 = O(width × height) × 8 queries (2 spawns × 4 targets) = O(8 × width × height)
单次生成总复杂度 = O(width × height)
最坏情况总复杂度 = O(max_generation_retries × width × height)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| width × height | int | 4 to 2500 | 配置文件 | 迷宫总 cell 数 |
| max_generation_retries | int | 1 to 200 | 配置文件 | 最大重试次数，默认 `50` |

**性能预期**：15×15 迷宫（225 cells），单次生成 + 验证 < 1ms。50 次重试 < 50ms。对玩家完全无感知。

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 迷宫尺寸太小（如 2×2，只有 4 个 cell）：需要放 6 个 marker（2 spawn + 3 keys + 1 chest） | `generation_failed`——可用 cell 不足以放置所有 marker | 最小可用尺寸要求 `width * height >= 6` 且 `width >= 2` 且 `height >= 2`（如 2×3、3×2、3×3 均可） |
| `max_fairness_delta = 0`：要求双方路径完全等长 | 正常执行，但通过率极低，大概率触发最大重试次数后失败 | 合法配置但实际不可用，文档在 Tuning Knobs 中警告 |
| DFS 起始 cell 恰好是 spawn 点 | 无影响——DFS 起始位置不影响生成结果的公平性，只影响迷宫的随机形态 | Recursive Backtracker 从任意 cell 开始都生成完全连通的迷宫 |
| 所有空 cell 的公平性都不达标（极端不对称迷宫） | 重试 50 次后 `generation_failed` | Perfect Maze 的拓扑由随机种子决定，极端不对称概率很低但理论上存在 |
| 重试过程中内存：反复创建/丢弃 MazeData | 每次重试调用 `MazeData.reset()` 将同一实例恢复为全墙、清除 markers、回退为 Uninitialized 状态，不创建新对象 | 避免 50 次重试产生 50 个临时对象的 GC 压力。`reset()` 接口已在 Maze Data Model GDD 中定义 |
| 随机种子：两局生成了相同的迷宫 | 允许——使用引擎默认随机数，不做去重检查 | 15×15 迷宫的可能排列数天文级别，重复概率可忽略 |
| 配置文件缺失 `max_fairness_delta` 或 `max_generation_retries` | 使用代码内文档化的默认值（`2` 和 `50`），打印警告日志 | 配置缺失不应阻止游戏运行，但需提醒开发者补充配置 |
| `finalize()` 在公平性验证通过后返回 `false` | 视为生成失败，执行重试（与公平性验证失败相同流程） | `is_valid()` 可能检测到 Generator 未覆盖的异常（如边界墙被意外移除），应作为安全网 |

> **跨系统注意**：Maze Data Model 定义的最小尺寸为 2×2，但 Maze Generator 要求 `width * height >= 6` 才能放下全部 6 个 marker（2×3、3×2 是最小可用尺寸）。Generator 应在开始前检查尺寸，不满足时立即 `generation_failed`。

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Maze Data Model** | Generator depends on this | 核心依赖——使用全部写入接口（`set_wall()`, `place_marker()`）、验证接口（`get_shortest_path()`）和生命周期接口（`finalize()`） |
| **Match State Manager** | Generator depends on this | 监听 `state_changed` 信号获取 SETUP 触发；生成完成/失败后通过信号通知 Manager |
| **Grid Movement** | Movement 间接依赖 Generator 的输出 | 无直接交互——Movement 读取 finalized MazeData，Generator 是该数据的生产者 |
| **Fog of War** | FoW 间接依赖 Generator 的输出 | 同上 |
| **Key Collection** | Keys 间接依赖 Generator 的输出 | 同上——钥匙位置由 Generator 放置 |
| **Win Condition / Chest** | WinCon 间接依赖 Generator 的输出 | 同上——宝箱位置由 Generator 放置 |
| **LLM Information Format** | LLMFormat 间接依赖 Generator 的输出 | 同上 |
| **Match Renderer** | Renderer 间接依赖 Generator 的输出 | 同上 |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `max_fairness_delta` | 2 | 0 - 5 | 生成更快（通过率更高），但双方起始公平性降低 | 更严格的公平性，但生成需要更多重试；`0` 时几乎必定失败 |
| `max_generation_retries` | 50 | 10 - 200 | 更大的搜索空间，极端配置下更可能找到公平迷宫 | 更快放弃，不公平配置下更容易触发 `generation_failed` |

**注意事项**：

- `max_fairness_delta` 和 `max_generation_retries` 是配对调优的——收紧 delta 时应增大 retries
- `max_fairness_delta = 0` 要求完全等长路径，15×15 迷宫下通过率极低，不建议使用
- 大迷宫（30×30+）路径更长，`max_fairness_delta = 2` 可能导致大量重试，建议按迷宫尺寸比例调整（如 `max(2, (width + height) / 15)`）
- 迷宫尺寸（`width`, `height`）由 Maze Data Model 管理，不在此重复定义
- 所有值必须从配置文件读取；代码中定义有文档化的默认值作为 fallback，配置缺失时使用默认值并打印警告日志

## Visual/Audio Requirements

Maze Generator 是纯逻辑系统，不直接产生任何视觉或音频输出。但它的执行过程可能需要间接的反馈：

| Event | Visual Feedback | Audio Feedback | Priority | Responsible System |
|-------|----------------|---------------|----------|--------------------|
| 迷宫生成中（SETUP 阶段） | 加载画面或"Generating maze..."提示文字 | 无 | MVP | Scene Manager / UI |
| 迷宫生成完成 | 提示消失，进入 Countdown | 无 | MVP | Match State Manager |
| 迷宫生成失败 | 错误提示："Failed to generate a fair maze. Please adjust settings." | 可选：错误音效 | MVP | UI |

> **注意**：迷宫生成在 15×15 规模下 < 50ms，玩家几乎不会看到加载提示。但为了处理极端配置（大迷宫 + 严格公平性）导致的长时间生成，UI 层应预留加载状态。

## Acceptance Criteria

- [ ] 对 15×15 迷宫调用 Generator，生成后所有 225 个 cell 均可从 `(0,0)` 到达（BFS 验证连通性）
- [ ] 生成的迷宫是 Perfect Maze：迷宫图包含恰好 `width × height - 1` 条通道（相邻 cell 间无墙的连接）
- [ ] `SPAWN_A` 位于 `(0, 0)`，`SPAWN_B` 位于 `(width-1, height-1)`
- [ ] 三把钥匙和宝箱各占一个独立 cell，不与 spawn 点或彼此重叠
- [ ] 公平性验证：4 个目标的 `fairness_delta` 均 ≤ `max_fairness_delta`
- [ ] 验证失败时整体重新生成（墙壁 + markers 全部重置），而非仅重新放置 markers
- [ ] 重试次数达到 `max_generation_retries` 后发出 `generation_failed` 信号，不降级
- [ ] 验证通过后调用 `MazeData.finalize()` 成功（返回 `true`）
- [ ] 生成完成后发出 `maze_generated` 信号
- [ ] 迷宫尺寸不满足 `width * height >= 6` 或 `width < 2` 或 `height < 2` 时立即 `generation_failed`
- [ ] 多次生成产生不同的迷宫结构（随机性验证：连续 10 次生成，至少 9 次结构不同）
- [ ] Performance：15×15 迷宫单次生成（含验证）< 5ms
- [ ] Performance：15×15 迷宫 50 次重试总耗时 < 100ms
- [ ] 所有配置值（`max_fairness_delta`, `max_generation_retries`）从外部配置读取；配置缺失时使用代码内默认值并打印警告日志

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Perfect Maze（无环路）是否太线性？是否需要后处理移除额外墙壁来创建环路，增加路径多样性？ | Game Designer | 原型阶段 | MVP 使用 Perfect Maze。原型验证后根据 LLM 导航表现决定是否需要环路 |
| 公平性验证是否需要考虑钥匙的收集顺序（Brass → Jade → Crystal → Chest 的累计路径）而非逐个独立验证？ | Game Designer | Sprint 1 | **MVP 使用单目标独立验证作为近似方案**。当前验证检查 SPAWN → KEY_BRASS / KEY_JADE / KEY_CRYSTAL / CHEST 四个独立 delta，但实际比赛是 Brass → Jade → Crystal → Chest 的顺序推进式 race route。单点距离公平不能完全推出整条顺序路径公平——例如两方到 Brass 等距，但 Brass → Jade 的路径可能严重不对称。累计路径验证（计算 `SPAWN→Brass→Jade→Crystal→Chest` 全程步数 delta）更精确但实现复杂（需排列所有中间段路径），待原型数据验证 MVP 方案的实际公平性后决定是否升级 |
| 是否需要暴露随机种子让玩家复现同一张地图（用于训练或分享）？ | Game Designer | Sprint 2 | MVP 不支持。后续可添加种子输入功能 |
| MazeData 是否需要新增 `reset()` 方法（将 finalized 状态回退为 uninitialized 并清空所有数据）以支持重试？ | Technical Director | Sprint 1 | **Resolved 2026-04-04**: 已在 Maze Data Model GDD 中添加 `reset()` 接口。`reset()` 将 Finalized 或 Uninitialized 状态回退为 Uninitialized（全墙、无 markers、写入接口解锁）。Generator 重试时调用 `maze.reset()` 复用同一实例。MazeData 生命周期已从两态（Uninitialized → Finalized）扩展为可回退的双向流转 |
