# Key Collection

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-04
> **System Index**: #7
> **Layer**: Feature
> **Implements Pillar**: Simple Rules Deep Play, Information Trade-off

## Overview

Key Collection 是管理钥匙拾取进度和钥匙显现节奏的游戏规则系统。游戏中有三把钥匙（Brass、Jade、Crystal），它们**逐个显现**：开局只有 Brass Key 存在于迷宫中，当任意一方 Agent 拾取 Brass 后 Jade Key 才出现，任意一方拾取 Jade 后 Crystal Key 才出现，任意一方拾取 Crystal 后宝箱才出现。钥匙的出现是全局事件——对双方 Agent 都可见（受 Fog of War 限制）。但每个 Agent 拥有独立的拾取进度，必须按 Brass → Jade → Crystal 的固定顺序拾取：没拿到 Brass 就无法拾取 Jade，即使 Jade 已经存在于迷宫中。钥匙是"检查点"而非"消耗品"：A 拾取后钥匙仍保留在原位，B 到达同一位置也可以拾取。拾取判定纯粹基于位置——Agent 移动到钥匙所在 cell 时自动拾取当前进度对应的钥匙，无需额外操作，也不依赖 Fog of War 可见性（看不到也能捡）。当某个 Agent 集齐三把钥匙后，宝箱出现在迷宫中，Agent 需找到宝箱打开它获取金蛋才能赢得比赛（宝箱和金蛋的逻辑由 Win Condition / Chest 系统负责）。Key Collection 监听 Grid Movement 的 `mover_moved` 信号触发判定，从 MazeData 读取钥匙位置，是连接移动系统与胜利条件的桥梁。

## Player Fantasy

**"钥匙是里程碑"**：每拿到一把钥匙，你都离胜利更近了一步。三把钥匙把一场迷宫竞赛切分成三个清晰的子目标——先找 Brass，再找 Jade，最后 Crystal。每一把钥匙的拾取都是一个小高潮：你的 AI 在迷宫中摸索了 30 秒，终于踩到了钥匙所在的格子，"叮"的一声，进度条推进了一格。而第一个拾取某把钥匙的 Agent 还会触发下一把钥匙的出现——这意味着领先者在推进比赛节奏，落后者则在已有的路标中追赶。第三把钥匙拾取的瞬间更是关键——宝箱在迷宫某处浮现，金蛋就在里面，但你的 AI 还得找到它。这种节奏感让观战不无聊——你不是在等一个遥远的终点，而是在追踪一连串即时的里程碑。

**"公平的赛跑"**：你和对手在找同一把钥匙，钥匙在同一个位置。你的 AI 先到了 Brass Key——钥匙不会消失，对手到了一样拿得到。而你的领先直接触发了 Jade Key 的出现，对手此时可能连 Brass 都还没找到。胜负不取决于"谁先抢到钥匙"，而是谁的整体路径效率更高、谁的 prompt 教会了 AI 更系统化的搜索策略。

## Detailed Design

### Core Rules

**钥匙显现机制**

1. 三把钥匙的位置在 Maze Generator 生成时全部确定（`KEY_BRASS`、`KEY_JADE`、`KEY_CRYSTAL` markers 已放置在 MazeData 中），但只有当前阶段的钥匙处于 **Active（活跃）** 状态
2. 开局只有 `KEY_BRASS` 为 Active，`KEY_JADE` 和 `KEY_CRYSTAL` 为 Inactive
3. Inactive 的钥匙对所有系统不可见——Fog of War 不暴露、Renderer 不渲染、拾取判定跳过
4. 当任意一方 Agent 拾取当前 Active 的钥匙后，下一把钥匙变为 Active：
   - 任意方拾取 Brass → Jade 变为 Active
   - 任意方拾取 Jade → Crystal 变为 Active
   - 任意方拾取 Crystal → 全局阶段推进到 ALL_COLLECTED，该 Agent 发出 `chest_unlocked(agent_id)` 信号，通知 Win Condition / Chest 系统该 Agent 有资格开宝箱。后续其他 Agent 拾取 Crystal 时，全局阶段不再推进，但同样发出 `chest_unlocked(agent_id)` 信号
5. 钥匙的激活是**全局事件**：A 拾取 Brass 触发 Jade 出现后，Jade 对 A 和 B 都存在（受 Fog of War 可见性限制）

**拾取规则**

6. Key Collection 监听 Grid Movement 的 `mover_moved` 信号，每次 Agent 移动后检查新位置
7. 拾取条件（全部满足才拾取）：
   - 该 cell 上有一把钥匙 marker
   - 该钥匙当前为 Active 状态
   - 该钥匙是这个 Agent 的 `next_key`（当前进度的下一把）
8. 拾取效果：
   - 该 Agent 的 `next_key` 推进到下一阶段（Brass → Jade → Crystal → Done）
   - 发出 `key_collected(agent_id, key_type)` 信号
   - 如果这把钥匙是全局首次被拾取（触发下一把显现），发出 `key_activated(next_key_type)` 信号
9. 钥匙是检查点：拾取后钥匙 marker **保留在原位**，不从 MazeData 中移除。另一个 Agent 到达同一位置仍可拾取
10. 拾取不依赖 Fog of War 可见性：Agent 看不到钥匙也能拾取（站在 cell 上即触发）

**每个 Agent 的独立进度**

11. 每个 Agent 维护自己的 `next_key` 状态：初始为 `KEY_BRASS`，拾取后依次推进
12. Agent A 拾取 Brass 后 `next_key` 变为 `KEY_JADE`，但 Agent B 的 `next_key` 仍为 `KEY_BRASS`（B 需要自己去拾取 Brass）
13. 当某个 Agent 的 `next_key` 为 Done（三把钥匙全部拾取），该 Agent 进入"寻找宝箱"阶段，后续逻辑由 Win Condition / Chest 系统接管

### Data Structures

```
# 枚举类型
enum KeyType { KEY_BRASS, KEY_JADE, KEY_CRYSTAL }
enum GlobalKeyPhase { BRASS_ACTIVE, JADE_ACTIVE, CRYSTAL_ACTIVE, ALL_COLLECTED }
enum AgentKeyState { NEED_BRASS, NEED_JADE, NEED_CRYSTAL, KEYS_COMPLETE }

# 单个 Agent 的钥匙进度
AgentKeyProgress:
  agent_id: int                    # 0 = Agent A, 1 = Agent B
  state: AgentKeyState             # 当前进度状态
  next_key: KeyType or null        # 下一把需要拾取的钥匙（KEYS_COMPLETE 时为 null）

# 钥匙收集管理器
KeyCollectionManager:
  global_phase: GlobalKeyPhase     # 当前全局钥匙激活阶段
  agent_progress: Dictionary<int, AgentKeyProgress>  # agent_id -> 进度
  key_positions: Dictionary<KeyType, Vector2i>       # 缓存的钥匙位置（initialize 时从 MazeData 读取）
  maze: MazeData                   # 迷宫数据引用（只读）

  # --- 信号 ---
  signal key_collected(agent_id: int, key_type: KeyType)   # 某 Agent 成功拾取某把钥匙
  signal key_activated(key_type: KeyType)                   # 某把钥匙变为 Active（全局首次）
  signal chest_unlocked(agent_id: int)                      # 某 Agent 集齐三把钥匙

  # --- 查询接口 ---
  is_key_active(key_type: KeyType) -> bool          # 该钥匙当前是否为 Active
  get_global_phase() -> GlobalKeyPhase              # 当前全局阶段
  get_agent_progress(agent_id: int) -> AgentKeyState  # 某 Agent 的钥匙进度

  # --- 生命周期 ---
  initialize(maze: MazeData)       # 读取钥匙位置，重置并初始化所有状态（COUNTDOWN 时调用——包括 Rematch 后的新一局）
  reset()                          # 清空所有状态到默认值（仅在不经过 initialize 的异常退出场景使用）
```

**设计决策**：

- **缓存钥匙位置**：`initialize()` 时一次性从 MazeData 读取 3 个钥匙位置到 `key_positions`，避免每次 `mover_moved` 都查询 MazeData
- **信号分离**：`key_collected`（每次拾取都发）、`key_activated`（仅全局首次）、`chest_unlocked`（每个完成的 Agent 各发一次）三个信号职责清晰，下游系统按需监听
- **AgentKeyProgress 与 GlobalKeyPhase 分离**：全局阶段决定哪些钥匙存在，Agent 进度决定谁能捡什么，两者独立变化

### States and Transitions

两个层面的状态：全局钥匙激活状态 + 每个 Agent 的拾取进度。

**全局钥匙激活状态**

```
BRASS_ACTIVE → JADE_ACTIVE → CRYSTAL_ACTIVE → ALL_COLLECTED
```

| State | Active Keys | 触发条件 | 退出条件 |
|-------|------------|---------|---------|
| **BRASS_ACTIVE** | Brass | 比赛开始（PLAYING） | 任意方拾取 Brass |
| **JADE_ACTIVE** | Brass + Jade | 任意方拾取 Brass | 任意方拾取 Jade |
| **CRYSTAL_ACTIVE** | Brass + Jade + Crystal | 任意方拾取 Jade | 任意方拾取 Crystal |
| **ALL_COLLECTED** | Brass + Jade + Crystal | 任意方拾取 Crystal | 终态（宝箱出现） |

> **注意**：激活是累加的——Jade 激活后 Brass 仍然 Active（因为 B 可能还没捡 Brass）。

**每个 Agent 的拾取进度**

```
NEED_BRASS → NEED_JADE → NEED_CRYSTAL → KEYS_COMPLETE
```

| State | next_key | 触发条件 | 退出条件 |
|-------|----------|---------|---------|
| **NEED_BRASS** | KEY_BRASS | 初始状态 | 该 Agent 站在 Brass cell 上且 Brass 为 Active |
| **NEED_JADE** | KEY_JADE | 拾取 Brass | 该 Agent 站在 Jade cell 上且 Jade 为 Active |
| **NEED_CRYSTAL** | KEY_CRYSTAL | 拾取 Jade | 该 Agent 站在 Crystal cell 上且 Crystal 为 Active |
| **KEYS_COMPLETE** | — | 拾取 Crystal | 终态，等待 Win Condition / Chest 接管 |

### Interactions with Other Systems

| System | Direction | Interface | Data Flow |
|--------|-----------|-----------|-----------|
| **Grid Movement** | Movement → Keys | 监听 `mover_moved` 信号 | 每次 Agent 移动后检查新位置是否可拾取钥匙 |
| **Maze Data Model** | Keys → Model | `get_marker_position(key_type)`, `get_markers_at(x, y)` | 查询钥匙位置，判断 Agent 所在 cell 是否有钥匙 |
| **Fog of War** | 无直接交互 | — | FoW 不查询 Key Collection。Marker 激活过滤由 LLM Information Format 和 Match Renderer 直接查询 `is_key_active()` 完成 |
| **Win Condition / Chest** | Keys → WinCon | `chest_unlocked(agent_id)` 信号 | 某 Agent 集齐三把钥匙后通知宝箱出现 |
| **Match Renderer** | Renderer → Keys | `is_key_active(key_type)`, `get_agent_progress(agent_id)` | 渲染钥匙图标（仅 Active 的钥匙），渲染 Agent 的钥匙进度 |
| **Match HUD** | HUD → Keys | `get_agent_progress(agent_id)` | 显示双方钥匙拾取进度（如 3 格进度条） |
| **LLM Information Format** | LLMFormat → Keys | `is_key_active(key_type)`, `get_agent_progress(agent_id)` | 将钥匙激活状态和 Agent 进度序列化给 LLM。LLMFormat 从 `get_agent_progress()` 推导 OBJECTIVE 文本（钥匙名或 "treasure chest"）和 keys_collected 数值 |
| **Match State Manager** | Keys → MSM | 监听 `state_changed` 信号 | Key Collection 监听 MSM 的 `state_changed`：COUNTDOWN 时调用 `initialize(maze)` 读取钥匙位置并**重置所有内部状态**（global_phase 回到 BRASS_ACTIVE，所有 Agent 进度回到 NEED_BRASS），PLAYING 时启用拾取判定，FINISHED 时停止处理并**保持最终状态**（下游系统如 Result Screen、Match HUD、Match Renderer 在 FINISHED 后仍需读取钥匙进度）。Rematch 流程：`MatchStateManager.reset()` → `state_changed(_, SETUP)` → Maze Generator 生成新迷宫 → `state_changed(_, COUNTDOWN)` → Key Collection 的 `initialize()` 自动用新 MazeData 重置一切。不需要额外的显式 `reset()` 调用 |

## Formulas

### Key Progression

```
next_key(agent) =
  if collected_count(agent) == 0: KEY_BRASS
  if collected_count(agent) == 1: KEY_JADE
  if collected_count(agent) == 2: KEY_CRYSTAL
  if collected_count(agent) == 3: DONE
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| collected_count | int | 0 to 3 | Agent 内部状态 | 该 Agent 已拾取的钥匙数量 |
| next_key | MarkerType or DONE | KEY_BRASS / KEY_JADE / KEY_CRYSTAL / DONE | 计算结果 | 该 Agent 下一把需要拾取的钥匙 |

### Pickup Check（每次 mover_moved 触发）

```
can_pickup(agent, cell) =
  cell 上存在 marker M
  AND M 是钥匙类型（KEY_BRASS / KEY_JADE / KEY_CRYSTAL）
  AND is_key_active(M) == true
  AND next_key(agent) == M
```

### Global Activation State

```
global_phase =
  if 无人拾取过任何钥匙: BRASS_ACTIVE
  if 有人拾取过 Brass 但无人拾取过 Jade: JADE_ACTIVE
  if 有人拾取过 Jade 但无人拾取过 Crystal: CRYSTAL_ACTIVE
  if 有人拾取过 Crystal: ALL_COLLECTED
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| global_phase | enum | BRASS_ACTIVE / JADE_ACTIVE / CRYSTAL_ACTIVE / ALL_COLLECTED | 内部状态 | 当前全局钥匙激活阶段 |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 两个 Agent 同一 tick 到达同一把钥匙所在的 cell | 两个 Agent 都成功拾取。如果这把钥匙是全局首次被拾取，只发出一次 `key_activated` 信号（第一个处理的 Agent 触发激活，第二个处理时发现已激活，跳过） | Tick 原子性：Grid Movement 在同一 tick 内按 mover_id 顺序逐个发出 `mover_moved`，Key Collection 按信号接收顺序处理。两个 Agent 独立进度互不影响 |
| Agent 站在 Jade Key cell 上但 `next_key` 仍为 `KEY_BRASS`（尚未拾取 Brass） | 不拾取。Agent 的 `next_key` 不匹配 Jade，判定条件不满足 | 强制顺序拾取是核心规则。即使 Jade 已 Active 且 Agent 就在上面，也必须先拿 Brass |
| Agent 站在 Jade Key cell 上且 `next_key` 为 `KEY_JADE`，但 Jade 尚未被激活（仍在 BRASS_ACTIVE 阶段） | 不拾取。钥匙未 Active，判定条件不满足 | **注意：此状态在正常游戏流中不可达**——Agent 的 `next_key` 变为 `KEY_JADE` 的唯一途径是拾取 Brass，而拾取 Brass 会立即将全局阶段推进到 JADE_ACTIVE。此边界条件仅作为防御性编程参考（如状态被外部工具手动修改的调试场景），实现和测试中不应为此构造专门的 production 代码路径 |
| Agent 移动到一个 cell 上有 Brass Key，但该 Agent 已经拾取过 Brass（`next_key` = `KEY_JADE`） | 不拾取（`next_key` 不匹配）。无事件发出 | 钥匙是检查点，不可重复拾取。已拾取的钥匙不再与 Agent 交互 |
| Agent A 拾取 Crystal（全局首次），同一 tick Agent B 也拾取 Crystal | A 的拾取将全局阶段推进到 ALL_COLLECTED 并发出 `chest_unlocked(A)`。B 的拾取发现全局阶段已为 ALL_COLLECTED，不重复推进，但 B 自己也进入 KEYS_COMPLETE 状态，同样发出 `chest_unlocked(B)`。两个 Agent 的 `key_collected(agent_id, KEY_CRYSTAL)` 信号均正常发出 | 全局阶段推进是幂等的——只推进一次。但 `chest_unlocked` 对每个完成所有钥匙的 Agent 都发出，因为 Win Condition 需要知道哪些 Agent 有资格开宝箱 |
| 比赛开始时 MazeData 中缺少某个钥匙 marker（如 `KEY_JADE` 位置未设置） | `initialize()` 时检测到缺失，打印错误日志。该钥匙的位置为 `(-1, -1)`，任何 Agent 永远无法到达该坐标，游戏卡在该阶段无法推进 | 不崩溃，但游戏无法正常完成。这是 Maze Generator 的 bug——`MazeData.is_valid()` 应拦截此情况 |
| `mover_moved` 信号在非 PLAYING 状态下到达 Key Collection | 忽略，不处理拾取判定 | 只在 PLAYING 状态下处理游戏逻辑，与 Grid Movement 的设计保持一致 |
| Agent 被 `initialize()` 放置在 Spawn 点，而 Spawn 点恰好就是 Brass Key 所在 cell | **无效地图——Maze Generator bug**。Generator 明确禁止将 marker 放在 Spawn 点所在 cell（Maze Generator 规则 #8.1）。若此情况出现，应视为上游生成错误。防御性处理：不自动拾取（拾取仅由 `mover_moved` 信号触发，`initialize()` 不触发 `mover_moved`）。注意：`MazeData.is_valid()` 不检查此约束（它只验证边界封闭、必要标记存在、连通性），拦截责任在 Generator 的放置规则 | 拾取判定严格绑定移动事件，初始放置不算移动。上游 Generator 约束应确保此场景不发生 |
| 所有钥匙放置在同一个 cell 上 | **无效地图——Maze Generator bug**。Generator 明确禁止将 marker 放在已有其他 marker 的 cell 上（Maze Generator 规则 #8.2，每个 marker 独占一个 cell）。MazeData 数据模型本身允许同一 cell 持有多个不同类型的 marker（Maze Data Model 规则 #5），拦截责任在 Generator 而非数据模型。防御性处理：Agent 到达该 cell 时仅拾取 `next_key` 匹配的那把，行为与正常拾取一致 | 上游 Generator 约束保证钥匙分散放置，Key Collection 不需要为此场景做特殊处理。保留描述仅作为防御性编程参考 |
| `key_activated` 信号发出时，另一个 Agent 恰好已经站在新激活钥匙的 cell 上 | 不自动拾取。必须等该 Agent 下次 `mover_moved` 才会重新检查。但如果 Agent 原地不动（撞墙或不移动），不会触发 `mover_moved`，需要移开再回来 | 与上一条一致——拾取判定只在移动成功时触发。这创造了一个微妙的策略空间：如果 AI 停在一个位置等待，可能错过"恰好出现在脚下"的钥匙 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Maze Data Model** | Key Collection depends on this | 查询 `get_marker_position(KEY_BRASS/KEY_JADE/KEY_CRYSTAL)` 获取钥匙位置，查询 `get_markers_at(x, y)` 判断 Agent 所在 cell 是否有钥匙 marker |
| **Grid Movement** | Key Collection depends on this | 监听 `mover_moved(mover_id, old_pos, new_pos)` 信号触发拾取判定 |
| **Match State Manager** | Key Collection depends on this | 监听 `state_changed` 信号管理生命周期——COUNTDOWN 时 `initialize(maze)` 重置所有内部状态并读取新 MazeData 的钥匙位置，PLAYING 时启用拾取判定，FINISHED 时停止处理并保持最终状态。Rematch 后 COUNTDOWN 再次触发 `initialize()`，完成隐式重置 |
| **Fog of War / Vision** | 无直接依赖 | FoW 不查询 Key Collection 的状态。之前描述的 "FoW 查询 `is_key_active()`" 已修正——marker 激活过滤由消费方（LLM Information Format / Match Renderer）直接查询 `is_key_active()` 完成，FoW 仅管理 cell 可见性三态 |
| **Win Condition / Chest** | WinCon depends on this | 监听 `chest_unlocked(agent_id)` 信号（某 Agent 集齐三把钥匙时发出），触发宝箱出现逻辑 |
| **Match Renderer** | Renderer depends on this | 查询 `is_key_active(key_type)` 决定是否渲染钥匙图标，查询 `get_agent_progress(agent_id)` 渲染 Agent 的钥匙收集状态 |
| **Match HUD** | HUD depends on this | 查询 `get_agent_progress(agent_id)` 显示双方钥匙拾取进度（如 3 格进度条） |
| **LLM Information Format** | LLMFormat depends on this | 查询 `is_key_active(key_type)` 和 `get_agent_progress(agent_id)` 将钥匙状态序列化给 LLM |

## Tuning Knobs

Key Collection 是一个规则驱动的系统，可调参数非常少——大部分行为由固定规则定义（3 把钥匙、固定顺序、检查点语义）。可调参数主要来自 Maze Generator 的钥匙放置策略，而非 Key Collection 本身。

| Knob | Type | Default | Safe Range | Affects | Owned By |
|------|------|---------|------------|---------|----------|
| `key_count` | int | 3 | 3（当前固定） | 比赛节奏、子目标数量 | Key Collection |
| `key_sequence` | Array | [BRASS, JADE, CRYSTAL] | 固定顺序（当前不可配置） | 拾取顺序 | Key Collection |
| `key_placement_min_distance` | int | — | 由 Maze Generator 定义 | 钥匙之间的最小路径距离，影响比赛时长和搜索难度 | Maze Generator |
| `key_spawn_distance_ratio` | float | — | 由 Maze Generator 定义 | 钥匙到双方 Spawn 点的路径距离比率（越接近 1.0 越公平） | Maze Generator |

**设计说明**：

- `key_count` 和 `key_sequence` 当前为硬编码常量，不作为运行时配置暴露。如果未来需要支持不同钥匙数量的变体模式，可以将其提升为配置项
- 实际影响比赛节奏的调节主要在 Maze Generator 端：钥匙的放置位置决定了搜索距离和公平性。Key Collection 只负责"拾取规则"，不负责"放在哪里"
- 没有"拾取延迟"或"拾取冷却"等调节项——拾取是即时的，与 Grid Movement 的 tick 粒度对齐

## Visual/Audio Requirements

### Visual

| Element | Description | Priority |
|---------|-------------|----------|
| **钥匙图标（Active）** | 三种颜色的钥匙图标：Brass（金铜色）、Jade（翠绿色）、Crystal（冰蓝色）。Active 时在迷宫 cell 中显示，带轻微上下浮动动画 | MVP |
| **钥匙图标（Inactive）** | 不渲染。Inactive 钥匙对渲染系统完全不可见 | MVP |
| **拾取反馈** | Agent 踩到钥匙时的视觉反馈：钥匙图标闪烁后消融到 Agent 身上（或简单的缩放 + 透明度渐变），持续约 0.3-0.5 秒 | MVP |
| **钥匙激活动画** | 新钥匙变为 Active 时的出现动画：从无到有的淡入 + 轻微光晕扩散，持续约 0.5 秒 | MVP |
| **进度指示器** | HUD 上每个 Agent 的钥匙进度：3 个钥匙槽位，已拾取的亮起对应颜色，未拾取的灰暗 | MVP |

### Audio

| Element | Description | Priority |
|---------|-------------|----------|
| **钥匙拾取音效** | 清脆的"叮"声，三把钥匙音高递进（Brass 最低、Crystal 最高），强化进度感 | MVP |
| **钥匙激活音效** | 新钥匙出现时的环境音效：柔和的魔法闪现声，提示双方"新目标出现了" | MVP |
| **全部集齐音效** | 第三把钥匙拾取时的特殊音效：比单把钥匙更隆重的乐句，标志进入最终阶段 | MVP |

**设计说明**：

- 拾取反馈是纯视觉/音效层面的——钥匙 marker 在数据层保留原位（检查点语义），但渲染层可以对"已被该 Agent 拾取"做视觉区分（如半透明显示）
- 音效设计强调节奏感——三把钥匙的音高递进让观战者能通过声音判断比赛进度

## Acceptance Criteria

### 全局钥匙激活

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-1 | 比赛开始（PLAYING）时，只有 Brass Key 为 Active，Jade 和 Crystal 为 Inactive | 单元测试：`initialize()` 后断言 `is_key_active(KEY_BRASS) == true`，`is_key_active(KEY_JADE) == false`，`is_key_active(KEY_CRYSTAL) == false` |
| AC-2 | 任意 Agent 拾取 Brass 后，Jade 变为 Active | 单元测试：模拟 Agent 移动到 Brass cell，断言 `key_activated` 信号发出且参数为 `KEY_JADE`，之后 `is_key_active(KEY_JADE) == true` |
| AC-3 | 任意 Agent 拾取 Jade 后，Crystal 变为 Active | 同 AC-2 模式 |
| AC-4 | 任意 Agent 拾取 Crystal 后，`chest_unlocked` 信号发出 | 单元测试：模拟完整的 3 把钥匙拾取流程，断言 `chest_unlocked(agent_id)` 信号在第三把拾取后发出 |
| AC-5 | 激活是累加的——Jade 激活后 Brass 仍为 Active | 单元测试：拾取 Brass 后断言 `is_key_active(KEY_BRASS) == true` 且 `is_key_active(KEY_JADE) == true` |

### 独立拾取进度

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-6 | 每个 Agent 初始 `next_key` 为 `KEY_BRASS` | 单元测试：`initialize()` 后断言两个 Agent 的 `get_agent_progress()` 均为 `NEED_BRASS` |
| AC-7 | Agent A 拾取 Brass 不影响 Agent B 的进度 | 单元测试：A 拾取 Brass 后，断言 A 的 `next_key` 为 `KEY_JADE`，B 的 `next_key` 仍为 `KEY_BRASS` |
| AC-8 | Agent 必须按 Brass → Jade → Crystal 顺序拾取 | 单元测试：Agent 的 `next_key` 为 `KEY_BRASS` 时站在 Jade cell 上，断言不触发 `key_collected` 信号 |

### 拾取判定

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-9 | Agent 移动到有 Active 钥匙且 `next_key` 匹配的 cell 时，自动拾取 | 集成测试：模拟 `mover_moved` 信号，断言 `key_collected(agent_id, key_type)` 信号发出 |
| AC-10 | 钥匙拾取后 marker 保留在原位，另一个 Agent 到达同一位置可拾取 | 集成测试：A 拾取 Brass 后，B 移动到同一 cell，断言 B 也成功拾取 |
| AC-11 | Agent 的 `next_key` 不匹配 Active 钥匙时不拾取 | 单元测试：Agent（`next_key` 为 `KEY_BRASS`）站在 Active 的 Jade cell 上（全局阶段已推进到 JADE_ACTIVE），断言不触发拾取。验证 `next_key` 匹配检查独立于钥匙激活状态 |
| AC-12 | 拾取不依赖 Fog of War 可见性 | 集成测试：Agent 视野范围外的钥匙 cell，Agent 移动到该 cell 后仍成功拾取 |

### 信号正确性

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-13 | `key_collected(agent_id, key_type)` 在每次成功拾取时发出 | 信号监听测试：完整 3 把钥匙流程中收到恰好 3 次 `key_collected` 信号 |
| AC-14 | `key_activated(next_key_type)` 仅在全局首次拾取该阶段钥匙时发出 | 信号监听测试：A 拾取 Brass 触发 `key_activated(KEY_JADE)`，随后 B 拾取 Brass 不再触发 `key_activated` |
| AC-15 | 非 PLAYING 状态下 `mover_moved` 不触发拾取判定 | 单元测试：在 COUNTDOWN 状态下发送 `mover_moved`，断言无 `key_collected` 信号 |

### 生命周期

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-16 | `initialize(maze)` 正确读取 MazeData 中的 3 个钥匙位置，并将所有内部状态重置为初始值 | 单元测试：完成一局比赛后（global_phase = ALL_COLLECTED），用新 MazeData 再次调用 `initialize()`，断言 global_phase 回到 BRASS_ACTIVE、所有 Agent 进度回到 NEED_BRASS、钥匙位置更新为新 MazeData 的值 |
| AC-17 | `initialize()` 是 Rematch 后的隐式重置机制——不需要额外调用 `reset()` | 集成测试：模拟完整 Rematch 流程（FINISHED → reset() → SETUP → COUNTDOWN 触发 initialize()），断言 Key Collection 状态完全干净 |
| AC-18 | MazeData 中缺少钥匙 marker 时 `initialize()` 不崩溃，打印错误日志 | 单元测试：构造缺少 `KEY_JADE` 的 MazeData，`initialize()` 后断言无异常且错误日志被记录 |

## Open Questions

| # | Question | Impact | Status |
|---|----------|--------|--------|
| OQ-1 | 钥匙激活时是否需要通知 LLM？当前设计中 LLM 通过 LLM Information Format 在每个 tick 获取完整状态快照，所以不需要单独推送"新钥匙出现了"的事件。但如果 LLM 没有被明确告知阶段变化，可能导致 prompt 策略难以写"当 Jade 出现时切换目标" | Medium | Resolved — LLM Agent Integration 已显式监听 `key_activated(key_type)` 和 `chest_unlocked(agent_id)` 作为决策点触发源（LLM Agent Integration GDD 决策点定义 "新目标可见" 条件）。钥匙激活不需要额外通知机制，现有信号链路已覆盖 |
| OQ-2 | `chest_unlocked` 信号是否应携带宝箱位置？当前设计只传 `agent_id`，宝箱位置由 Win Condition / Chest 系统从 MazeData 读取。但如果宝箱位置是在 `chest_unlocked` 时才动态生成的（而非 Maze Generator 预设），则需要不同的数据流 | Medium | Resolved — 宝箱位置由 Maze Generator 预设在 MazeData 中，Win Condition 的 `initialize()` 从 `get_marker_position(CHEST)` 读取并缓存，`chest_unlocked` 信号不需要携带位置 |
| OQ-3 | 是否需要"钥匙拾取历史"供 Result Screen 展示？如"Agent A 在第 15 tick 拾取了 Brass Key"这样的时间线数据 | Low | 推迟到 Match HUD / Result Screen 设计时决定 |
