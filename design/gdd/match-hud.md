# Match HUD

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-02
> **System Index**: #13
> **Layer**: Presentation
> **Implements Pillar**: Simple Rules Deep Play, Information Trade-off

## Overview

Match HUD 是比赛中叠加在游戏画面上方的信息显示层，为观战者提供实时的比赛状态数据。它显示三类核心信息：**双方钥匙进度**（各 3 格进度条，已拾取的亮起对应颜色）、**比赛计时**（已经过的时间和 tick 数）、以及**阶段提示**（如"宝箱已出现"）。HUD 使用 Godot 的 CanvasLayer 渲染，独立于 Match Renderer 的游戏世界坐标系，始终固定在屏幕边缘不随摄像机移动。HUD 是纯消费端——监听 Key Collection、Match State Manager、Win Condition、Grid Movement 的信号和查询接口获取数据，自身不发出信号，不影响任何游戏逻辑。MVP 阶段 HUD 保持极简：顶部左右两侧显示双方进度，顶部中央显示计时，底部显示阶段提示。设计目标是让观战者在任何时刻都能一眼判断"谁领先、差多远、比赛进行了多久"，无需离开游戏画面。

## Player Fantasy

**"比赛的仪表盘"**：你的视线在迷宫画面和 HUD 之间快速切换。左上角三个钥匙槽——蓝色方的第一格亮起金铜色，你的 AI 拿到了 Brass Key。右上角红色方还是三格全灰。你领先了。屏幕顶部中央的计时器显示 "00:42 | Tick 84"——不到一分钟，你的 AI 已经完成了三分之一的目标。这种"一眼读懂局势"的能力让观战变得有节奏感：每次钥匙槽亮起都是一个小高潮，每次看计时器都在评估"这个速度够快吗"。

**"竞争的温度计"**：当双方的进度条同时推进到第二格——Jade Key 都拿了——你知道这场比赛进入了白热化。底部突然弹出一行提示："🏆 宝箱已出现"。Crystal Key 被某方拾取了，终局阶段开始。HUD 不需要告诉你宝箱在哪（那是迷宫画面的事），它只需要告诉你"比赛进入了最后阶段"。这种克制的信息设计让 HUD 成为氛围的推手，而非信息的负担。

**"极简即尊重"**：HUD 只占屏幕边缘很窄的空间，不遮挡迷宫画面。没有花哨的边框、没有不必要的数据、没有干扰视线的动画。它尊重观战者的注意力——你想看的是迷宫里两个 AI 的对决，HUD 只是在你需要的时候给你一个快速参考。

## Detailed Design

### Core Rules

**渲染层级**

1. HUD 使用 Godot CanvasLayer 渲染，`layer` 值高于 Match Renderer 的游戏世界，确保 HUD 始终显示在迷宫画面之上
2. HUD 使用屏幕坐标（像素），不受 Camera2D 缩放和平移影响
3. HUD 元素使用 Godot Control 节点（Label、TextureRect、HBoxContainer 等），通过 anchor/margin 定位到屏幕边缘

**布局**

4. HUD 分为三个区域：
   - **顶部左侧**：Agent A（蓝色）的钥匙进度——标签 "A" + 3 个钥匙槽图标
   - **顶部右侧**：Agent B（红色）的钥匙进度——3 个钥匙槽图标 + 标签 "B"（镜像布局）
   - **顶部中央**：比赛计时器——显示 `MM:SS` 格式的经过时间和当前 tick 数
5. 屏幕底部中央为**阶段提示区**，仅在需要时显示临时文字提示（如"宝箱已出现"），无提示时不占空间

**钥匙进度显示**

6. 每个 Agent 有 3 个钥匙槽，从左到右依次对应 Brass、Jade、Crystal
7. 槽位状态：
   - **未拾取**：灰色/暗色图标
   - **已拾取**：亮起对应颜色（Brass = 金铜色，Jade = 翠绿色，Crystal = 冰蓝色）
8. 状态由 `KeyCollection.get_agent_progress(agent_id)` 推断：如果 Agent 的 progress 已超过某把钥匙的阶段，则该槽位为"已拾取"
9. 槽位亮起时播放短暂的脉冲放大动画（约 0.3 秒），强化拾取反馈

**比赛计时**

10. 显示格式：`MM:SS | Tick NNN`
11. 时间来源：`MatchStateManager.get_elapsed_time()`，每帧更新（`_process`）
12. Tick 数来源：`MatchStateManager.get_tick_count()`，每次 `tick` 信号更新
13. 仅在 PLAYING 状态下计时器运行；COUNTDOWN 显示 "00:00 | Tick 0"；FINISHED 显示最终定格时间

**阶段提示**

14. 临时文字提示，在特定事件发生时从底部弹入，持续数秒后自动淡出：
    - `chest_activated` → "🏆 宝箱已出现"（持续 3 秒）
15. 提示区同一时间只显示一条提示，新提示覆盖旧提示
16. 提示使用较大字号 + 半透明背景条，确保可读性不遮挡太多画面

**生命周期**

17. HUD 监听 Match State Manager 的 `state_changed` 信号：
    - COUNTDOWN：显示 HUD 元素，初始化所有槽位为灰色，计时器归零
    - PLAYING：启用实时更新（计时器、信号响应）
    - FINISHED：停止计时器更新，保持最终状态。可叠加显示"比赛结束"文字
18. HUD 监听 Key Collection 的 `key_collected` 信号更新钥匙槽位
19. HUD 监听 Win Condition 的 `chest_activated` 信号显示阶段提示

### Data Structures

```
# 场景节点结构
MatchHUD (CanvasLayer):
  layer: int                          # CanvasLayer 层级（高于游戏世界）

  # --- 顶部栏 ---
  top_bar: HBoxContainer              # 顶部横条容器
    agent_a_panel: HBoxContainer       # 左侧：Agent A 进度
      agent_a_label: Label             # "A" 标签（蓝色）
      key_slots_a: Array<TextureRect>  # 3 个钥匙槽（Brass, Jade, Crystal）
    timer_panel: VBoxContainer         # 中央：计时器
      time_label: Label                # "MM:SS" 时间显示
      tick_label: Label                # "Tick NNN" tick 数显示
    agent_b_panel: HBoxContainer       # 右侧：Agent B 进度
      key_slots_b: Array<TextureRect>  # 3 个钥匙槽（Brass, Jade, Crystal）
      agent_b_label: Label             # "B" 标签（红色）

  # --- 底部提示区 ---
  toast_container: CenterContainer     # 底部居中容器
    toast_label: Label                 # 阶段提示文字
    toast_bg: Panel                    # 半透明背景条

  # --- 内部状态 ---
  is_playing: bool                     # 当前是否在 PLAYING 状态（控制计时器更新）
  toast_timer: Timer                   # 提示自动淡出计时器

  # --- 信号监听（纯消费端）---
  # 监听 Match State Manager: state_changed, tick
  # 监听 Key Collection: key_collected
  # 监听 Win Condition: chest_activated
```

**设计决策**：

- **CanvasLayer 而非 Control 子节点**：HUD 必须独立于 Camera2D 的变换，CanvasLayer 天然提供这个隔离
- **HBoxContainer 布局**：利用 Godot 的自动布局系统，HUD 自适应不同屏幕分辨率，无需手动计算像素位置
- **TextureRect 钥匙槽**：使用图片而非纯色块，可以复用 Match Renderer 的钥匙 Sprite 资源（灰色版 + 彩色版）
- **toast_timer**：独立 Timer 节点控制提示显示时长，timeout 后触发淡出动画

### States and Transitions

HUD 自身没有独立状态机——行为由 Match State Manager 状态驱动，与 Match Renderer 模式一致。

**HUD 行为随比赛阶段变化**

| Match State | HUD Behavior |
|-------------|-------------|
| **SETUP** | HUD 不可见（`visible = false`） |
| **COUNTDOWN** | HUD 可见。所有钥匙槽灰色，计时器显示 "00:00 \| Tick 0"，无阶段提示 |
| **PLAYING** | 实时更新：计时器每帧刷新，`key_collected` 信号触发槽位亮起，`chest_activated` 触发阶段提示 |
| **FINISHED** | 计时器定格在最终值。钥匙槽保持最终状态。可显示"比赛结束"提示 |

**钥匙槽位状态**

```
LOCKED → COLLECTED
```

| State | Visual | 触发条件 |
|-------|--------|---------|
| **LOCKED** | 灰色钥匙图标 | 初始状态 |
| **COLLECTED** | 对应颜色钥匙图标 + 短暂脉冲放大动画 | 收到 `key_collected(agent_id, key_type)` 信号且 agent_id 匹配 |

**阶段提示状态**

```
HIDDEN → SHOWING → HIDDEN
```

| State | Visual | 触发条件 |
|-------|--------|---------|
| **HIDDEN** | 提示区不可见 | 初始状态 / 淡出完成后 |
| **SHOWING** | 提示文字从底部滑入，半透明背景条可见 | 收到触发信号（如 `chest_activated`） |
| **HIDDEN** | 提示文字淡出消失 | `toast_timer` 超时（默认 3 秒） |

### Interactions with Other Systems

| System | Direction | Interface | Data Flow |
|--------|-----------|-----------|-----------|
| **Key Collection** | HUD depends on this | 监听 `key_collected(agent_id, key_type)` 信号；查询 `get_agent_progress(agent_id)` | `key_collected`：触发对应 Agent 的钥匙槽位亮起动画。`get_agent_progress()`：`initialize` 时恢复已有进度（如中途重连场景） |
| **Match State Manager** | HUD depends on this | 监听 `state_changed`, `tick` 信号；查询 `get_elapsed_time()`, `get_tick_count()` | `state_changed`：驱动 HUD 生命周期（显示/隐藏/定格）。`tick`：更新 tick 数显示。`get_elapsed_time()`：每帧更新时间显示 |
| **Win Condition / Chest** | HUD depends on this | 监听 `chest_activated` 信号；查询 `is_chest_active()` | `chest_activated`：显示"宝箱已出现"阶段提示。`is_chest_active()`：初始化时恢复阶段状态 |
| **Grid Movement** | HUD depends on this | 查询 `get_total_moves(mover_id)` | MVP 不显示（预留）。未来可在 HUD 中显示每个 Agent 的移动步数统计 |
| **Match Renderer** | 并行，无直接依赖 | — | 两者都是 Presentation 层，各自独立渲染。HUD 通过 CanvasLayer 叠加在 Renderer 之上 |
| **(无下游依赖)** | — | — | Match HUD 是数据流终端，不发出信号，不被任何其他系统依赖 |

## Formulas

### Timer Display Format（计时器格式化）

```
minutes = floor(elapsed_time / 60)
seconds = floor(elapsed_time) % 60
display = "%02d:%02d | Tick %d" % [minutes, seconds, tick_count]
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| elapsed_time | float | 0 to max_match_duration | `MatchStateManager.get_elapsed_time()` | 比赛已进行时长（秒） |
| tick_count | int | 0+ | `MatchStateManager.get_tick_count()` | 已经过的 tick 数 |
| display | String | — | 格式化结果 | 显示在 HUD 上的文字 |

### Key Slot State Inference（钥匙槽位推断）

```
is_collected(agent_id, key_type) =
  if key_type == KEY_BRASS:  agent_progress > NEED_BRASS
  if key_type == KEY_JADE:   agent_progress > NEED_JADE
  if key_type == KEY_CRYSTAL: agent_progress > NEED_CRYSTAL
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| agent_progress | AgentKeyState | NEED_BRASS / NEED_JADE / NEED_CRYSTAL / KEYS_COMPLETE | `KeyCollection.get_agent_progress(agent_id)` | 该 Agent 的当前钥匙进度 |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 两个 Agent 同一 tick 拾取同一把钥匙 | 两个 `key_collected` 信号依次到达，两侧对应槽位各自亮起，各播放独立的脉冲动画 | 信号按顺序处理，两侧 HUD 独立更新 |
| 比赛超时（`max_match_duration` 到达） | 计时器定格在最终时间，显示"TIME UP"阶段提示 | 超时由 MSM 的 `match_finished(DRAW)` 触发，HUD 在 FINISHED 状态下显示 |
| 窗口 resize | HUD 通过 anchor/margin 自动适配新分辨率，无需手动调整 | Godot Control 节点的布局系统自动处理 |
| 比赛开始时已有进度（理论上不会发生，但防御性处理） | COUNTDOWN 时 HUD 查询 `get_agent_progress()` 恢复已有进度，槽位直接设为正确状态（无动画） | 防御性初始化，确保 HUD 与逻辑状态一致 |
| `chest_activated` 提示正在显示时收到 `match_finished` | 提示立即被"比赛结束"提示替换（新提示覆盖旧提示） | 比赛结束是更高优先级的信息 |
| `key_collected` 信号在非 PLAYING 状态到达 | 忽略，不更新槽位 | 只在 PLAYING 状态下响应游戏事件 |
| 阶段提示淡出动画进行中收到新提示 | 立即终止淡出，显示新提示，重置 toast_timer | 新信息优先于正在消失的旧信息 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Key Collection** | Match HUD depends on this | 监听 `key_collected(agent_id, key_type)` 触发槽位亮起。查询 `get_agent_progress(agent_id)` 用于初始化恢复 |
| **Match State Manager** | Match HUD depends on this | 监听 `state_changed` 驱动 HUD 生命周期，监听 `tick` 更新 tick 数显示。查询 `get_elapsed_time()` 和 `get_tick_count()` 更新计时器 |
| **Win Condition / Chest** | Match HUD depends on this | 监听 `chest_activated` 显示阶段提示。查询 `is_chest_active()` 用于初始化恢复 |
| **Grid Movement** | Match HUD depends on this（预留） | MVP 不使用。未来可查询 `get_total_moves(mover_id)` 显示移动统计 |
| **(无下游依赖)** | — | Match HUD 是数据流终端，不发出信号，不被任何其他系统依赖 |

## Tuning Knobs

| Knob | Type | Default | Safe Range | Affects |
|------|------|---------|------------|---------|
| `hud_canvas_layer` | int | 10 | 5 - 20 | CanvasLayer 层级。必须高于游戏世界（默认 0）和 Match Renderer |
| `toast_duration` | float | 3.0 | 1.0 - 5.0 | 阶段提示显示时长（秒）。太短看不清，太长遮挡画面 |
| `toast_fade_duration` | float | 0.5 | 0.2 - 1.0 | 提示淡出动画时长（秒） |
| `key_slot_pulse_duration` | float | 0.3 | 0.1 - 0.5 | 钥匙槽位亮起时的脉冲放大动画时长（秒） |
| `key_slot_pulse_scale` | float | 1.3 | 1.1 - 1.5 | 脉冲放大的最大缩放倍数 |
| `timer_font_size` | int | 24 | 16 - 36 | 计时器字体大小 |
| `toast_font_size` | int | 28 | 20 - 40 | 阶段提示字体大小 |
| `hud_margin` | int | 16 | 8 - 32 | HUD 元素与屏幕边缘的间距（像素） |

**设计说明**：

- HUD 的调节参数主要影响视觉呈现，不影响任何游戏逻辑
- `timer_font_size` 和 `toast_font_size` 需要在不同分辨率下测试可读性
- 所有值必须从配置文件读取，禁止硬编码

## Visual/Audio Requirements

### Visual

| Element | Description | Priority |
|---------|-------------|----------|
| **钥匙槽图标（灰色）** | 3 种钥匙的灰色/暗色版本，与 Match Renderer 的钥匙 Sprite 风格一致但更小（HUD 尺寸） | MVP |
| **钥匙槽图标（彩色）** | Brass = 金铜色，Jade = 翠绿色，Crystal = 冰蓝色。亮起状态 | MVP |
| **Agent 标签** | "A" 蓝色文字 + "B" 红色文字，颜色与 Match Renderer 的 Agent 颜色一致 | MVP |
| **计时器文字** | 白色等宽字体（Monospace），确保数字跳动时不抖动 | MVP |
| **阶段提示背景** | 半透明深色背景条（约 50% 透明度），确保白色文字在任何迷宫画面上都可读 | MVP |
| **脉冲动画** | 钥匙槽亮起时的 Tween：scale 1.0→1.3→1.0，ease-out | MVP |
| **提示滑入动画** | 提示从屏幕底部外滑入到可见位置，Tween ease-out | MVP |
| **提示淡出动画** | 提示透明度 1.0→0.0，Tween 线性 | MVP |

### Audio

HUD 本身不播放音效。钥匙拾取音效由 Key Collection 负责，阶段提示无独立音效（宝箱出现的音效由 Win Condition / Match Renderer 负责）。

## Acceptance Criteria

### 钥匙进度

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-1 | COUNTDOWN 时所有 6 个钥匙槽（双方各 3）显示为灰色 | 视觉测试 + 单元测试：断言所有 TextureRect 使用灰色纹理 |
| AC-2 | `key_collected(0, KEY_BRASS)` 信号后，Agent A 的 Brass 槽位亮起金铜色 | 集成测试：模拟信号，断言纹理切换为彩色版且播放脉冲动画 |
| AC-3 | Agent A 拾取钥匙不影响 Agent B 的槽位显示 | 集成测试：A 拾取 Brass 后断言 B 的 Brass 槽仍为灰色 |
| AC-4 | 三把钥匙的槽位颜色与 Match Renderer 中的钥匙颜色一致（Brass=铜，Jade=绿，Crystal=蓝） | 视觉测试 |

### 计时器

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-5 | PLAYING 状态下计时器每帧更新，显示格式为 `MM:SS \| Tick NNN` | 视觉测试 + 单元测试：断言 Label.text 格式正确 |
| AC-6 | FINISHED 状态下计时器定格，不再更新 | 单元测试：FINISHED 后多帧断言 Label.text 不变 |
| AC-7 | 计时器使用等宽字体，数字跳动时不产生水平抖动 | 视觉测试 |

### 阶段提示

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-8 | `chest_activated` 信号后显示"宝箱已出现"提示 | 集成测试：模拟信号，断言 toast_label.text 和 visible 状态 |
| AC-9 | 提示在 `toast_duration` 秒后自动淡出 | 集成测试：等待超时后断言 toast_container.visible == false |
| AC-10 | 新提示覆盖正在显示的旧提示 | 集成测试：连续触发两条提示，断言只显示最新一条 |

### 布局与生命周期

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-11 | HUD 固定在屏幕边缘，不随 Camera2D 移动 | 视觉测试：缩放/平移摄像机后 HUD 位置不变 |
| AC-12 | 窗口 resize 后 HUD 自适应新分辨率 | 集成测试：运行中改变窗口大小，HUD 保持正确布局 |
| AC-13 | SETUP 状态下 HUD 不可见 | 单元测试：断言 CanvasLayer.visible == false |
| AC-14 | COUNTDOWN 状态下 HUD 可见，计时器显示 "00:00 \| Tick 0" | 单元测试 |

### 性能

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-15 | HUD 渲染开销不超过 1ms/帧 | 性能测试：Godot Profiler |
| AC-16 | 所有配置值从外部配置读取，无硬编码 | 代码审查 |

## Open Questions

| # | Question | Impact | Status |
|---|----------|--------|--------|
| OQ-1 | 是否需要在 HUD 中显示移动统计（步数/撞墙次数）？Grid Movement 已提供 `get_total_moves()` 和 `get_blocked_count()` 接口，但可能让 HUD 过于拥挤 | Low | 推迟到 playtest 后决定。MVP 不显示，预留接口 |
| OQ-2 | 是否需要在钥匙槽旁边显示"当前目标"指示（如闪烁高亮下一个需要拾取的钥匙）？可以帮助观战者理解每个 Agent 当前在找什么 | Low | 推迟到 Full 阶段。MVP 的三格进度条已足够清晰 |
| OQ-3 | 阶段提示是否需要更多事件触发？如"Agent A 拾取了 Brass Key"等实时播报。可能增加观战趣味但也增加信息噪音 | Low | 推迟到 playtest 后决定。MVP 仅显示"宝箱已出现"这一个高价值提示 |
