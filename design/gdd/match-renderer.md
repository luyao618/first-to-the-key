# Match Renderer

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-02
> **System Index**: #11
> **Layer**: Presentation
> **Implements Pillar**: Simple Rules Deep Play, Information Trade-off

## Overview

Match Renderer 是将比赛状态可视化的 Presentation 层系统。它从 Maze Data Model 读取迷宫结构，从 Grid Movement 获取 Agent 位置和移动事件，从 Fog of War 查询可见性状态，从 Key Collection 和 Win Condition 获取钥匙/宝箱的激活与拾取状态，将所有信息组合渲染到屏幕上。MVP 阶段仅支持 Agent vs Agent 模式的 **God View**——人类观察者看到完整迷宫，两个 Agent 的实时位置和所有标记物（钥匙、宝箱）均可见，不受 Fog of War 限制。渲染架构分为三层：底层用 Godot TileMap 绘制墙壁和通道的静态网格，中间层用 Sprite 节点渲染钥匙、宝箱等可交互标记物（带浮动/激活/拾取动画），顶层用 Sprite 节点渲染两个 Agent（带移动补间和撞墙抖动动画）。逻辑与渲染解耦——游戏逻辑层（Grid Movement 等）立即更新坐标，Match Renderer 异步播放补间动画追赶逻辑位置，确保视觉流畅而不阻塞 tick 节奏。摄像机固定，自动缩放适配迷宫到屏幕可视区域。未来 Player vs Player 模式需要的 Agent FoW 视图（分屏/画中画）不在 MVP 范围内，但渲染架构应预留扩展空间。

## Player Fantasy

**"棋盘上的对弈"**：你坐在 God View 前，俯瞰整个迷宫。两个小色块——一蓝一红——在迷宫中穿行。你看到蓝色 Agent（你的 AI）在一个岔路口犹豫了一下，然后选了左边——正是通往 Brass Key 的方向。你紧握拳头。红色 Agent 在右边撞了墙，抖了一下，浪费了一个 tick。你露出微笑。这种"旁观者清"的快感来自于：你看得到全局，你知道最优路径，而你的 AI 在有限视野中做出的每一个决策，都在验证你 prompt 的质量。

**"比赛的节奏感"**：钥匙在迷宫中轻轻浮动，等待被发现。当你的 AI 踩上 Brass Key——"叮"一声，钥匙闪烁消融到 Agent 身上，HUD 上第一格亮起。随即 Jade Key 在迷宫另一侧淡入浮现，带着柔和的光晕。三把钥匙的逐步收集给比赛创造了清晰的节奏：搜索 → 发现 → 拾取 → 下一目标。最后宝箱出现时的光柱效果和开启时的金蛋动画，是整场比赛的高潮。好的渲染不只是"让东西看得见"，而是通过视觉节奏让观战变得引人入胜。

**"清晰即公平"**：两个 Agent 用不同颜色（蓝/红）清晰区分，钥匙用三种颜色（铜/翠绿/冰蓝）标识进度，迷宫的墙壁和通道一目了然。没有视觉混淆，没有遮挡，没有需要猜测的元素。你能在任何时刻准确判断：谁在哪里，谁更接近目标，谁的 prompt 更好。这种信息透明度让观战的策略分析成为可能——你不是在"看热闹"，而是在"复盘 prompt 的效果"。

## Detailed Design

### Core Rules

**渲染模式**

1. MVP 阶段仅支持 **God View** 渲染模式：整个迷宫完全可见，不应用 Fog of War 遮挡，所有 Active 标记物（钥匙、宝箱）和 Agent 位置实时显示
2. 未来 Player vs Player/Agent 模式需要 **Agent View** 渲染模式（应用 FoW 三态渲染），MVP 不实现但架构预留：渲染管线通过 `render_mode` 参数决定是否查询 FoW 数据

**渲染层级**

3. 渲染分为三层，按 Z-order 从底到顶：
   - **Layer 0 — Maze Layer**：TileMap 绘制墙壁和通道的静态网格。比赛开始后不变（迷宫结构不可变）
   - **Layer 1 — Marker Layer**：Sprite 节点渲染钥匙和宝箱。随游戏进度动态变化（激活/拾取/出现/开启）
   - **Layer 2 — Agent Layer**：Sprite 节点渲染两个 Agent。每 tick 更新位置，播放移动/撞墙动画
4. 每层使用独立的 Godot Node2D 容器，通过 `z_index` 控制叠加顺序

**迷宫渲染（Layer 0）**

5. 使用 Godot TileMap 节点渲染迷宫网格。每个 cell 映射到一个 tile，tile 类型由墙壁组合决定（4 面墙壁共 16 种组合）
6. TileMap 在 `initialize()` 时一次性构建，遍历 MazeData 所有 cell，根据 `has_wall(x, y, dir)` 选择对应 tile
7. 地板用浅色，墙壁用深色，形成清晰的通道/障碍对比
8. Spawn 点用淡色标记（蓝/红圆环）标注初始位置，比赛全程可见

**标记物渲染（Layer 1）**

9. 每个标记物（钥匙/宝箱）是一个独立的 Sprite 节点，挂载在 Marker Layer 容器下
10. 标记物的可见性由对应系统的状态决定：
    - 钥匙：`KeyCollection.is_key_active(key_type)` 为 true 时可见
    - 宝箱：`WinCondition.is_chest_active()` 为 true 时可见
11. 标记物位置固定（从 MazeData marker 位置转换为像素坐标），不移动
12. Active 标记物播放轻微上下浮动的循环动画（Tween 或 AnimationPlayer）

**Agent 渲染（Layer 2）**

13. 每个 Agent 是一个 Sprite 节点，用颜色区分：Agent A = 蓝色，Agent B = 红色
14. Agent 渲染位置与逻辑位置**解耦**：逻辑层（Grid Movement）立即更新坐标，渲染层通过 Tween 播放从旧位置到新位置的滑动动画
15. 移动动画时长应短于 `tick_interval`，确保动画在下一 tick 前完成。建议 `move_anim_duration = tick_interval * 0.6`
16. 撞墙动画：Agent Sprite 向撞墙方向短距离偏移后弹回（约 3-5 像素），持续约 0.2 秒
17. 原地不动（`mover_stayed`）：无动画，Agent 保持静止

**摄像机**

18. 使用 Godot Camera2D，固定位置，居中于迷宫中心
19. 自动缩放：根据迷宫像素尺寸和屏幕分辨率计算 zoom 值，确保整个迷宫适配屏幕可视区域（留 margin）
20. `zoom = min(screen_width / maze_pixel_width, screen_height / maze_pixel_height) * (1.0 - margin_ratio)`

**生命周期**

21. Match Renderer 监听 Match State Manager 的 `state_changed` 信号管理生命周期：
    - SETUP → COUNTDOWN：`initialize(maze)` 构建 TileMap，放置 Marker Sprites，放置 Agent Sprites 到 Spawn 点，设置摄像机
    - COUNTDOWN → PLAYING：显示倒计时动画（3-2-1-GO），倒计时结束后动画消失
    - PLAYING：持续响应移动/拾取/激活/开启事件播放对应动画
    - PLAYING → FINISHED：播放胜利/平局动画（宝箱开启 + 胜利者高亮 + 失败者灰显）

### Data Structures

```
# 枚举类型
enum RenderMode { GOD_VIEW, AGENT_VIEW }

# 渲染配置
RenderConfig:
  cell_size: int                    # 每个 cell 的像素边长（从 MazeData 配置读取）
  margin_ratio: float               # 摄像机留白比例（0.0-0.2）
  move_anim_ratio: float              # 移动动画时长占 tick_interval 的比例（0.4-0.8）
  bump_anim_duration: float          # 撞墙抖动动画时长（秒）
  bump_offset: float                 # 撞墙抖动偏移像素数
  float_anim_amplitude: float        # 标记物浮动动画振幅（像素）
  float_anim_period: float           # 标记物浮动动画周期（秒）
  agent_a_color: Color               # Agent A 颜色（蓝色）
  agent_b_color: Color               # Agent B 颜色（红色）

# 场景节点结构
MatchRenderer (Node2D):
  render_mode: RenderMode            # 当前渲染模式（MVP 固定 GOD_VIEW）
  config: RenderConfig               # 渲染配置

  # --- 子节点层级 ---
  maze_layer: TileMapLayer           # Layer 0: 墙壁和通道
  marker_layer: Node2D               # Layer 1: 钥匙和宝箱容器
    key_sprites: Dictionary<KeyType, Sprite2D>    # 钥匙精灵（3 个）
    chest_sprite: Sprite2D                         # 宝箱精灵（1 个）
  agent_layer: Node2D                # Layer 2: Agent 容器
    agent_sprites: Dictionary<int, Sprite2D>       # Agent 精灵（agent_id -> Sprite）
  camera: Camera2D                   # 固定摄像机
  countdown_label: Label             # 倒计时文字（3-2-1-GO）

  # --- 信号监听（不发出信号，纯消费端）---
  # 监听 Match State Manager: state_changed
  # 监听 Grid Movement: mover_moved, mover_blocked, mover_stayed
  # 监听 Key Collection: key_collected, key_activated
  # 监听 Win Condition: chest_activated, chest_opened

  # --- 生命周期 ---
  initialize(maze: MazeData)         # 构建 TileMap，放置标记物和 Agent，设置摄像机
  cleanup()                          # 清理所有渲染节点
```

**设计决策**：

- **纯消费端，不发出信号**：Match Renderer 只监听其他系统的信号驱动渲染更新，不向外发出信号。它是数据流的终端
- **Sprite 节点 vs 自定义 _draw()**：选择 Sprite 节点方案——每个可移动/可动画的元素是独立节点，可以直接使用 Godot 的 Tween 和 AnimationPlayer，实现简单且调试方便
- **TileMapLayer 而非 TileMap**：Godot 4.x 推荐使用 TileMapLayer 替代旧版 TileMap 节点，每个 layer 是独立节点
- **Dictionary 索引**：`key_sprites` 按 KeyType 索引，`agent_sprites` 按 agent_id 索引，方便在信号回调中快速定位目标节点

### States and Transitions

Match Renderer 自身没有独立状态机——它的行为完全由 Match State Manager 的状态驱动。

**渲染行为随比赛阶段变化**

| Match State | Renderer Behavior |
|-------------|-------------------|
| **SETUP** | 无渲染。等待 `state_changed` 信号 |
| **COUNTDOWN** | `initialize(maze)` 构建完整渲染场景。显示倒计时动画（3-2-1-GO）。Agent 和标记物可见但静止 |
| **PLAYING** | 活跃渲染：响应 `mover_moved`/`mover_blocked` 播放 Agent 动画，响应 `key_activated`/`key_collected` 播放钥匙动画，响应 `chest_activated`/`chest_opened` 播放宝箱动画 |
| **FINISHED** | 播放终局动画。胜利者 Agent 高亮放大，失败者灰显半透明。宝箱开启动画（如果是正常胜利）或 "TIME UP" 文字（如果是超时平局）。之后保持静态画面直到 `reset()` |

**标记物渲染状态**

每个标记物 Sprite 有三种渲染状态：

```
HIDDEN → APPEARING → IDLE → (钥匙: COLLECTED / 宝箱: OPENED)
```

| State | Visual | 触发条件 |
|-------|--------|---------|
| **HIDDEN** | `visible = false`，不渲染 | 初始状态（Inactive 标记物） |
| **APPEARING** | 淡入 + 光晕动画（0.5 秒） | 收到 `key_activated` 或 `chest_activated` 信号 |
| **IDLE** | 浮动循环动画 | APPEARING 动画完成后自动进入 |
| **COLLECTED** | 闪烁消融到 Agent 身上（0.3-0.5 秒），之后 `visible = false`（仅 God View 下；Agent View 下钥匙作为检查点保留可见） | 收到 `key_collected(agent_id, key_type)` 信号。注意：God View 下钥匙是检查点语义，被 A 拾取后 B 仍可拾取。设计选择：God View 下钥匙被拾取后**不隐藏**，改为半透明显示表示"已被至少一方拾取"，当双方都拾取后再完全隐藏。**推断逻辑**：Renderer 收到 `key_collected(agent_id, key_type)` 后，查询双方 `KeyCollection.get_agent_progress(0)` 和 `get_agent_progress(1)`——如果某 Agent 的 progress 已超过该钥匙阶段（如 progress 为 `NEED_JADE` 则 Brass 已拾取），即视为该 Agent 已拾取。一方拾取 → `modulate.a = 0.4`；双方拾取 → `visible = false` |
| **OPENED** | 宝箱盖弹开 + 金蛋升起 + 光芒（1.0-1.5 秒） | 收到 `chest_opened(agent_id)` 信号 |

**Agent 渲染状态**

```
IDLE → MOVING → IDLE
IDLE → BUMPING → IDLE
```

| State | Visual | 触发条件 |
|-------|--------|---------|
| **IDLE** | 静止在当前逻辑位置的像素坐标上 | 初始状态 / 动画完成后 |
| **MOVING** | Tween 从旧像素位置滑动到新像素位置 | 收到 `mover_moved` 信号 |
| **BUMPING** | 向撞墙方向短距离偏移后弹回 | 收到 `mover_blocked` 信号 |

### Interactions with Other Systems

| System | Direction | Interface | Data Flow |
|--------|-----------|-----------|-----------|
| **Maze Data Model** | Renderer depends on this | `get_cell()`, `has_wall()`, `get_marker_position()` | `initialize()` 时遍历所有 cell 构建 TileMap，读取标记位置放置 Sprite 节点 |
| **Grid Movement** | Renderer depends on this | 监听 `mover_moved`, `mover_blocked`, `mover_stayed` 信号；查询 `get_position()` | 移动事件驱动 Agent 动画；查询当前位置用于 Sprite 初始定位 |
| **Fog of War / Vision** | Renderer depends on this | `get_cell_visibility(agent_id, x, y)` | MVP（God View）不使用。未来 Agent View 模式下查询可见性状态决定 cell 渲染方式（Unknown/Explored/Visible） |
| **Key Collection** | Renderer depends on this | 监听 `key_activated`, `key_collected` 信号；查询 `is_key_active()`, `get_agent_progress()` | `key_activated`：触发钥匙出现动画。`key_collected`：触发钥匙拾取动画 + 半透明化。`is_key_active()`：`initialize()` 时判断哪些钥匙应初始可见（Brass 在比赛开始时已 Active） |
| **Win Condition / Chest** | Renderer depends on this | 监听 `chest_activated`, `chest_opened` 信号；查询 `is_chest_active()` | `chest_activated`：触发宝箱出现动画（淡入 + 光柱）。`chest_opened`：触发宝箱开启动画（盖弹开 + 金蛋） |
| **Match State Manager** | Renderer depends on this | 监听 `state_changed`, `match_finished` 信号；查询 `get_tick_count()`, `get_elapsed_time()` | `state_changed`：驱动渲染生命周期（初始化/倒计时/活跃/终局）。`match_finished`：读取比赛结果决定胜利/平局动画 |
| **Match HUD** | HUD 与 Renderer 并行 | 无直接依赖 | 两者都是 Presentation 层，各自独立监听游戏系统信号。HUD 渲染叠加在 Renderer 之上（UI Canvas Layer） |

## Formulas

### Grid-to-Pixel Conversion（坐标转换）

```
pixel_pos = grid_pos * cell_size + cell_size / 2
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| grid_pos | Vector2i | (0,0) to (width-1, height-1) | MazeData / Grid Movement | 网格坐标 |
| cell_size | int | 16 to 128 | RenderConfig | 每个 cell 的像素边长 |
| pixel_pos | Vector2 | (cell_size/2, cell_size/2) to (...) | 计算结果 | Sprite 在场景中的像素位置（cell 中心点） |

### Camera Zoom（摄像机缩放）

```
maze_pixel_width = maze_width * cell_size
maze_pixel_height = maze_height * cell_size
fit_zoom = min(screen_width / maze_pixel_width, screen_height / maze_pixel_height)
zoom = fit_zoom * (1.0 - margin_ratio)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| maze_width, maze_height | int | 2 to 50 | MazeData | 迷宫网格尺寸 |
| cell_size | int | 16 to 128 | RenderConfig | 每个 cell 的像素边长 |
| screen_width, screen_height | int | — | Viewport | 屏幕分辨率 |
| margin_ratio | float | 0.0 to 0.2 | RenderConfig | 边缘留白比例 |
| zoom | float | 0.1+ | 计算结果 | Camera2D 的 zoom 值 |

**示例计算**（15x15 迷宫，cell_size = 32，屏幕 1920x1080，margin = 0.1）：
```
maze_pixel_width = 15 * 32 = 480
maze_pixel_height = 15 * 32 = 480
fit_zoom = min(1920/480, 1080/480) = min(4.0, 2.25) = 2.25
zoom = 2.25 * 0.9 = 2.025
```

### Move Animation Duration（移动动画时长）

```
move_anim_duration = tick_interval * move_anim_ratio
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| tick_interval | float | 0.1 to 5.0 | Match State Manager 配置 | 两次 tick 之间的间隔 |
| move_anim_ratio | float | 0.4 to 0.8 | RenderConfig | 动画时长占 tick 间隔的比例 |
| move_anim_duration | float | 0.04 to 4.0 | 计算结果 | Tween 动画时长（秒） |

**约束**：`move_anim_duration < tick_interval`，确保动画在下一 tick 前完成。建议 `move_anim_ratio = 0.6`。

### Float Animation（标记物浮动）

```
y_offset = sin(time * 2π / float_anim_period) * float_anim_amplitude
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| time | float | 0+ | 引擎 `_process(delta)` 累计 | 当前时间 |
| float_anim_period | float | 1.0 to 3.0 | RenderConfig | 浮动周期（秒） |
| float_anim_amplitude | float | 2.0 to 6.0 | RenderConfig | 浮动振幅（像素） |
| y_offset | float | -amplitude to +amplitude | 计算结果 | Sprite 的 Y 轴偏移 |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 移动动画未播完时下一个 `mover_moved` 到达 | 立即终止当前 Tween，将 Sprite 瞬移到上一次的逻辑目标位置，然后启动新的 Tween 到本次目标位置 | 逻辑位置始终正确（Grid Movement 保证），渲染追赶逻辑。如果 `tick_interval` 非常短而动画较慢，会看到"跳跃"效果——这是 `move_anim_ratio` 过高的信号，应调低 |
| 两个 Agent 在同一 cell 上重叠 | 两个 Sprite 都渲染在该 cell 中心点。为避免完全遮挡，使用轻微偏移：Agent A 偏移 (-3, -3) 像素，Agent B 偏移 (+3, +3) 像素 | 两个 Agent 占同一 cell 是合法的（Grid Movement 允许），渲染层需要让双方都可见 |
| 迷宫非常大（50x50），摄像机缩放后 cell 很小 | 正常缩放，每个 cell 可能只有几像素。Agent Sprite 和标记物 Sprite 会随缩放变小但仍可见 | 大迷宫的可读性由 cell_size 和屏幕分辨率共同决定。如果太小以至于不可辨认，应调大 cell_size 或限制迷宫尺寸。Renderer 不负责这个决策 |
| 迷宫非常小（2x2），摄像机缩放后 cell 很大 | 正常缩放，每个 cell 占据屏幕大块面积。pixel art 在放大后可能出现模糊——使用 Godot 的 nearest-neighbor filtering 保持像素清晰 | 小迷宫的极端放大是合法的。设置 `texture_filter = TEXTURE_FILTER_NEAREST` 避免模糊 |
| `key_collected` 信号到达但对应的 key_sprite 已经处于 HIDDEN 状态 | 忽略，不播放动画。打印调试日志 | 不应发生（钥匙必须 Active 才能被拾取），但防御性处理 |
| `chest_opened` 信号到达但 chest_sprite 处于 HIDDEN 状态 | 忽略，不播放动画。打印调试日志 | 同上——宝箱必须 Active 才能被开启 |
| 比赛超时平局（`match_finished(DRAW, -1)`）而非宝箱开启胜利 | 不播放宝箱开启动画。显示 "TIME UP" 文字叠加。两个 Agent 都灰显（无胜利者） | 超时平局没有宝箱开启事件，Renderer 根据 `match_finished` 的 result 参数决定播放哪种终局动画 |
| `initialize()` 时 MazeData 中某个标记缺失（如无 CHEST） | 对应 Sprite 不创建。其他标记正常渲染。打印警告日志 | 不崩溃，缺失的标记不影响其他元素的渲染。这是 Maze Generator 的 bug，Renderer 做防御性处理 |
| 窗口大小改变（resize） | 重新计算 camera zoom 以适配新分辨率 | 连接 Viewport 的 `size_changed` 信号，动态调整 zoom |
| 钥匙被 Agent A 拾取后 Agent B 到达同一位置再次拾取 | Agent A 拾取时钥匙 Sprite 变为半透明。Agent B 拾取时钥匙 Sprite 完全隐藏（双方都已拾取）。两次拾取各播放独立的拾取反馈动画（闪烁 + 粒子效果跟随对应 Agent） | God View 下钥匙是检查点语义，需要视觉区分"被一方拾取"和"被双方拾取" |
| `state_changed` 信号到达但 Renderer 尚未完成上一个状态的动画（如倒计时动画还没播完就收到 PLAYING） | 立即终止当前动画，进入新状态的渲染行为 | 状态切换由逻辑层驱动，渲染层必须跟上。未播完的动画不应阻塞游戏进度 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Maze Data Model** | Match Renderer depends on this | `initialize()` 时遍历所有 cell 调用 `has_wall(x, y, dir)` 构建 TileMap，调用 `get_marker_position()` 获取标记物像素位置。运行时不再查询（迷宫结构不可变） |
| **Grid Movement** | Match Renderer depends on this | 监听 `mover_moved(mover_id, old_pos, new_pos)` 播放移动补间动画，监听 `mover_blocked(mover_id, pos, dir)` 播放撞墙抖动，监听 `mover_stayed(mover_id, pos)` 确认无动画。查询 `get_position(mover_id)` 用于初始定位 |
| **Fog of War / Vision** | Match Renderer depends on this | MVP 不使用（God View 不经过 FoW）。未来 Agent View 模式下查询 `get_cell_visibility(agent_id, x, y)` 决定 cell 渲染方式（Unknown = 黑色遮挡，Explored = 半透明灰色，Visible = 完全显示） |
| **Key Collection** | Match Renderer depends on this | 监听 `key_activated(key_type)` 触发钥匙出现动画，监听 `key_collected(agent_id, key_type)` 触发拾取动画。查询 `is_key_active(key_type)` 用于初始化时判断哪些钥匙可见，查询 `get_agent_progress(agent_id)` 判断钥匙半透明状态 |
| **Win Condition / Chest** | Match Renderer depends on this | 监听 `chest_activated` 触发宝箱出现动画（淡入 + 光柱），监听 `chest_opened(agent_id)` 触发开启动画（盖弹开 + 金蛋）。查询 `is_chest_active()` 用于初始化时判断宝箱是否可见 |
| **Match State Manager** | Match Renderer depends on this | 监听 `state_changed(old, new)` 驱动渲染生命周期（COUNTDOWN 初始化、PLAYING 活跃渲染、FINISHED 终局动画），监听 `match_finished(result)` 决定胜利/平局动画类型。读取 `tick_interval` 配置计算 `move_anim_duration` |
| **(无下游依赖)** | — | Match Renderer 是数据流终端，不发出信号，不被任何其他系统依赖 |

## Tuning Knobs

| Knob | Type | Default | Safe Range | Affects |
|------|------|---------|------------|---------|
| `cell_size` | int | 32 | 16 - 128 | 每个 cell 的像素边长。影响迷宫在屏幕上的大小、资源清晰度、摄像机缩放。大值 = 更清晰但大迷宫可能超出屏幕；小值 = 更多内容但细节不清 |
| `margin_ratio` | float | 0.1 | 0.0 - 0.2 | 摄像机留白比例。0.0 = 迷宫撑满屏幕；0.2 = 四周留 20% 空白给 HUD 和呼吸空间 |
| `move_anim_ratio` | float | 0.6 | 0.4 - 0.8 | 移动动画时长占 tick_interval 的比例。低值 = 快速跳跃感；高值 = 流畅滑动感。超过 0.8 有动画未完成被打断的风险 |
| `bump_anim_duration` | float | 0.2 | 0.1 - 0.4 | 撞墙抖动动画时长（秒）。太短 = 看不清；太长 = 感觉迟钝 |
| `bump_offset` | float | 4.0 | 2.0 - 8.0 | 撞墙抖动偏移像素数。影响"撞墙"的视觉力度 |
| `float_anim_amplitude` | float | 3.0 | 2.0 - 6.0 | 标记物浮动振幅（像素）。低值 = 微妙；高值 = 显眼 |
| `float_anim_period` | float | 2.0 | 1.0 - 3.0 | 标记物浮动周期（秒）。低值 = 快速弹跳；高值 = 缓慢漂浮 |
| `agent_a_color` | Color | `#4488FF`（蓝） | 任意高对比度颜色 | Agent A 的颜色标识 |
| `agent_b_color` | Color | `#FF4444`（红） | 任意高对比度颜色 | Agent B 的颜色标识，需与 Agent A 颜色有足够区分度 |
| `agent_overlap_offset` | float | 3.0 | 2.0 - 6.0 | 两个 Agent 在同一 cell 时的像素偏移量，防止完全重叠 |

**设计说明**：

- `cell_size` 同时影响 Maze Data Model 的坐标转换和 Renderer 的像素布局，修改时需两端同步
- `move_anim_ratio` 是最影响"游戏节奏感"的渲染参数——0.6 左右给人"有节奏的滑动"感；低于 0.4 像是"瞬移"；高于 0.8 看起来"拖泥带水"
- 颜色选择需考虑色盲友好——蓝/红组合对大多数色觉类型可区分，但未来可考虑加形状区分
- 所有值必须从配置文件读取，禁止硬编码

## Visual/Audio Requirements

### Visual

**美术资源清单**

| Asset | Description | Spec | Priority |
|-------|-------------|------|----------|
| **Maze Tileset** | 16 种 tile 变体（4 面墙壁的所有组合），地板浅色 + 墙壁深色。pixel art 风格 | `cell_size x cell_size` 像素（默认 32x32） | MVP |
| **Agent Sprite A** | 蓝色角色精灵。简约设计——圆形或方形色块即可，带轻微内部细节（如眼睛/方向指示）区分朝向 | 24x24 像素（留 cell 边距） | MVP |
| **Agent Sprite B** | 红色角色精灵。与 Agent A 形状相同，颜色不同 | 24x24 像素 | MVP |
| **Brass Key** | 金铜色钥匙图标 | 16x16 像素 | MVP |
| **Jade Key** | 翠绿色钥匙图标 | 16x16 像素 | MVP |
| **Crystal Key** | 冰蓝色钥匙图标 | 16x16 像素 | MVP |
| **Chest (closed)** | 木质/金色宝箱图标（关闭状态） | 24x24 像素 | MVP |
| **Chest (open)** | 宝箱打开状态 | 24x24 像素 | MVP |
| **Golden Egg** | 金色发光球体 | 16x16 像素 | MVP |
| **Spawn Marker A** | 蓝色圆环，标注 Agent A 起始位置 | 28x28 像素，半透明 | MVP |
| **Spawn Marker B** | 红色圆环，标注 Agent B 起始位置 | 28x28 像素，半透明 | MVP |

**动画需求**

| Animation | Description | Duration | Trigger | Priority |
|-----------|-------------|----------|---------|----------|
| **Agent 移动** | Sprite 从旧 cell 中心滑动到新 cell 中心（Tween，ease-out） | `tick_interval * 0.6` | `mover_moved` 信号 | MVP |
| **Agent 撞墙** | Sprite 向撞墙方向偏移 4px 后弹回（Tween，ease-in-out） | 0.2 秒 | `mover_blocked` 信号 | MVP |
| **标记物浮动** | Sprite Y 轴正弦往复运动 | 循环（周期 2 秒） | 标记物进入 IDLE 状态 | MVP |
| **标记物出现** | 透明度 0→1 淡入 + 轻微缩放 0.5→1.0 | 0.5 秒 | `key_activated` / `chest_activated` | MVP |
| **钥匙拾取** | 闪烁 2-3 次后缩放至 0 + 透明度渐变。拾取粒子效果飞向对应 Agent | 0.3-0.5 秒 | `key_collected` | MVP |
| **宝箱出现** | 透明度淡入 + 光柱效果（比钥匙出现更隆重） | 0.5-0.8 秒 | `chest_activated` | MVP |
| **宝箱开启** | 盖弹开帧动画 → 金蛋升起 → 径向光芒扩散 | 1.0-1.5 秒 | `chest_opened` | MVP |
| **倒计时** | 屏幕中央 "3" → "2" → "1" → "GO!" 文字缩放弹入弹出 | 每数字 1 秒，GO 持续 0.5 秒 | COUNTDOWN 状态 | MVP |
| **胜利者高亮** | 胜利 Agent 持续脉冲放大/发光；失败 Agent modulate 灰色 + 半透明 | 持续直到 reset | `match_finished` | MVP |

### Audio

Match Renderer 本身不直接管理音效播放（建议由独立的 AudioManager 或各系统的 Visual/Audio Requirements 中定义的音效负责）。但 Renderer 的动画事件可以作为音效触发点：

| Trigger Point | Suggested Audio | Responsible |
|---------------|----------------|-------------|
| 钥匙出现动画开始 | 魔法闪现声 | Key Collection (audio) |
| 钥匙拾取动画开始 | 清脆"叮"声，三把钥匙音高递进 | Key Collection (audio) |
| 宝箱出现动画开始 | 深沉魔法浮现声 | Win Condition (audio) |
| 宝箱开启动画开始 | 木箱"咔嗒" + 华丽乐句 | Win Condition (audio) |
| 倒计时每秒 | 节拍音效，GO 时更强 | Match State Manager (audio) |
| 胜利判定 | 欢快旋律 | Result Screen (audio) |

**设计说明**：

- MVP 美术风格为简约 pixel art，优先功能清晰度而非美学精致度
- 所有 Sprite 使用 `TEXTURE_FILTER_NEAREST` 保持像素清晰
- 动画全部使用 Godot Tween 实现（代码驱动），不使用 AnimationPlayer（减少外部资源依赖）
- 音效职责不在 Renderer——Renderer 触发视觉动画，音效由对应系统的 audio 层负责。实现时可通过信号解耦

## Acceptance Criteria

### 迷宫渲染

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-1 | `initialize(maze)` 后 TileMap 正确渲染所有 cell 的墙壁和通道 | 视觉测试：对比 MazeData 的 `has_wall()` 输出与渲染结果，每个方向的墙壁状态一致 |
| AC-2 | Spawn 标记在正确位置渲染，颜色与对应 Agent 一致（蓝/红） | 视觉测试：Spawn 标记位置与 `get_marker_position(SPAWN_A/B)` 一致 |
| AC-3 | TileMap 在 `initialize()` 后不再变化（迷宫结构不可变） | 代码审查：确认无运行时修改 TileMap 的逻辑 |

### Agent 渲染

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-4 | Agent Sprite 初始位置与 Grid Movement 的 `get_position()` 对应的像素坐标一致 | 单元测试：`initialize()` 后断言 Sprite.position == `grid_to_pixel(get_position(mover_id))` |
| AC-5 | `mover_moved` 信号触发 Tween 动画，Sprite 从旧像素位置滑动到新像素位置 | 视觉测试：Agent 移动时无跳跃，平滑滑动 |
| AC-6 | 移动动画时长 = `tick_interval * move_anim_ratio`，在下一 tick 前完成 | 单元测试：断言 Tween duration 值正确且 < tick_interval |
| AC-7 | `mover_blocked` 信号触发撞墙抖动动画，方向与撞墙方向一致 | 视觉测试：向北撞墙时 Sprite 向上偏移后弹回 |
| AC-8 | 移动动画未完成时收到新 `mover_moved`，旧 Tween 立即终止，Sprite 瞬移到上一逻辑目标 | 集成测试：快速连续两次移动，Sprite 最终到达正确位置 |
| AC-9 | 两个 Agent 在同一 cell 时有像素偏移，双方均可见 | 视觉测试：两个 Agent 重叠时不完全遮挡 |

### 标记物渲染

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-10 | 比赛开始时仅 Brass Key 可见（Active），Jade、Crystal、Chest 不可见（Inactive） | 视觉测试 + 单元测试：断言 Brass key_sprite.visible == true，其余 == false |
| AC-11 | `key_activated` 信号触发对应钥匙的出现动画（淡入 + 缩放） | 视觉测试：新钥匙从透明渐变到完全可见 |
| AC-12 | `key_collected` 信号触发拾取动画，之后钥匙 Sprite 变为半透明（一方拾取）或完全隐藏（双方拾取） | 视觉测试 + 单元测试：断言 modulate.a 值正确 |
| AC-13 | `chest_activated` 信号触发宝箱出现动画（淡入 + 光柱），比钥匙出现更隆重 | 视觉测试 |
| AC-14 | `chest_opened` 信号触发宝箱开启动画（盖弹开 + 金蛋 + 光芒） | 视觉测试 |
| AC-15 | Active 标记物播放浮动循环动画 | 视觉测试：标记物 Y 轴有周期性微动 |

### 摄像机

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-16 | 摄像机自动缩放使整个迷宫适配屏幕可视区域（留 margin） | 视觉测试：任意迷宫尺寸（2x2 到 50x50）均可完整显示 |
| AC-17 | 窗口 resize 后摄像机 zoom 重新计算 | 集成测试：运行中拖拽窗口大小，迷宫保持适配 |

### 生命周期

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-18 | COUNTDOWN 状态显示倒计时动画（3-2-1-GO） | 视觉测试 |
| AC-19 | FINISHED 状态正确显示胜利/平局动画（胜利者高亮或 TIME UP 文字） | 视觉测试：正常胜利和超时平局两种场景 |
| AC-20 | `cleanup()` 正确移除所有渲染节点，不留残余 | 单元测试：cleanup 后 maze_layer、marker_layer、agent_layer 子节点数为 0 |

### 性能

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-21 | 50x50 迷宫 + 2 Agent + 所有标记物的单帧渲染在 16.6ms 内完成（60fps） | 性能测试：Godot Profiler 测量渲染帧时间 |
| AC-22 | 所有配置值从外部配置读取，无硬编码 | 代码审查 |

## Open Questions

| # | Question | Impact | Status |
|---|----------|--------|--------|
| OQ-1 | TileMap tile 设计：是用 16 种独立 tile 图片还是用 Godot TileMap 的 terrain/autotile 功能自动匹配墙壁？Autotile 更灵活但配置复杂；独立 tile 简单直接但美术资源量更大 | Medium | 推迟到实现阶段决定。MVP 建议先用 16 种独立 tile，后续可迁移到 autotile |
| OQ-2 | 宝箱开启动画与 `finish_match()` 的时序（来自 Win Condition OQ-1）：Renderer 是在 `chest_opened` 信号后播放动画再等 `finish_match`，还是 `finish_match` 已经触发了 FINISHED 状态后在 FINISHED 状态下播放？后者更简单——Renderer 在收到 `match_finished` 时检查 result，如果是 WIN 则播放宝箱开启 + 胜利动画序列 | Medium | 建议采用后者：`finish_match` 立即触发，Renderer 在 FINISHED 状态下播放终局动画序列。这样逻辑层不需要等渲染 |
| OQ-3 | Agent View 渲染模式的架构预留：是用同一 TileMap 加 FoW 遮罩覆盖层，还是使用 Godot 的 SubViewport 做分屏？SubViewport 更干净但性能开销更大 | Low | 推迟到 Core 阶段（Player vs Player 模式）设计时决定 |
| OQ-4 | 是否需要"Agent 路径轨迹"可视化？在 God View 下用淡色线条显示每个 Agent 的历史移动路径，帮助观战者分析 prompt 效果 | Low | 推迟到 Full 阶段。MVP 不显示路径轨迹，但 Grid Movement 的 `visited_cells` 数据已可用 |
| OQ-5 | Grid Movement 的 OQ-2 现在可以回答：移动动画与逻辑解耦——逻辑层立即更新坐标，渲染层异步播放补间动画追赶逻辑位置 | — | Resolved |
