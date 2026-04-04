# Match HUD

> **Status**: Approved
> **Author**: design-system agent
> **Last Updated**: 2026-04-02
> **System Index**: #13
> **Layer**: Presentation
> **Implements Pillar**: Simple Rules Deep Play, Information Trade-off

## Overview

Match HUD 是比赛中显示实时状态数据的信息层，为观战者提供三类核心信息：**双方钥匙进度**（各 3 格进度条，已拾取的亮起对应颜色）、**比赛计时**（已经过的时间和 tick 数）、以及**阶段提示**（如"宝箱已出现"）。HUD 的内容在 PLAYING 阶段显示在 Match 场景固定三栏布局的**左右栏**中（Agent A 进度在左栏，Agent B 进度在右栏），计时器显示在中栏顶部。三栏布局由 Match 场景根节点定义，全程不变（见 prompt-input.md 三栏布局规范）。HUD 是纯消费端——监听 Key Collection、Match State Manager、Win Condition、Grid Movement 的信号和查询接口获取数据，自身不发出信号，不影响任何游戏逻辑。MVP 阶段 HUD 保持极简：左右栏显示双方钥匙进度，中栏顶部显示计时，底部显示阶段提示。设计目标是让观战者在任何时刻都能一眼判断"谁领先、差多远、比赛进行了多久"，无需离开游戏画面。

## Player Fantasy

**"比赛的仪表盘"**：你的视线在迷宫画面和 HUD 之间快速切换。左上角三个钥匙槽——蓝色方的第一格亮起金铜色，你的 AI 拿到了 Brass Key。右上角红色方还是三格全灰。你领先了。屏幕顶部中央的计时器显示 "00:42 | Tick 84"——不到一分钟，你的 AI 已经完成了三分之一的目标。这种"一眼读懂局势"的能力让观战变得有节奏感：每次钥匙槽亮起都是一个小高潮，每次看计时器都在评估"这个速度够快吗"。

**"竞争的温度计"**：当双方的进度条同时推进到第二格——Jade Key 都拿了——你知道这场比赛进入了白热化。底部突然弹出一行提示："🏆 宝箱已出现"。Crystal Key 被某方拾取了，终局阶段开始。HUD 不需要告诉你宝箱在哪（那是迷宫画面的事），它只需要告诉你"比赛进入了最后阶段"。这种克制的信息设计让 HUD 成为氛围的推手，而非信息的负担。

**"极简即尊重"**：HUD 只占屏幕边缘很窄的空间，不遮挡迷宫画面。没有花哨的边框、没有不必要的数据、没有干扰视线的动画。它尊重观战者的注意力——你想看的是迷宫里两个 AI 的对决，HUD 只是在你需要的时候给你一个快速参考。

## Detailed Design

### Core Rules

**渲染层级**

1. HUD 内容在 PLAYING 阶段显示在 Match 场景的三栏布局中：钥匙进度放在左右栏（Agent A 左栏、Agent B 右栏），计时器放在中栏顶部区域
2. 阶段提示（toast）使用 CanvasLayer 渲染，覆盖在中栏底部，不受 Camera2D 影响
3. HUD 元素使用 Godot Control 节点（Label、TextureRect、HBoxContainer 等），通过三栏容器的子节点结构定位

**布局**

4. HUD 分为三个区域：
   - **左栏**：Agent A（蓝色）的钥匙进度——标签 "A" + 3 个钥匙槽图标
   - **右栏**：Agent B（红色）的钥匙进度——3 个钥匙槽图标 + 标签 "B"（镜像布局）
   - **中栏顶部**：比赛计时器——显示 `MM:SS` 格式的经过时间和当前 tick 数
5. 中栏底部为**阶段提示区**，仅在需要时显示临时文字提示（如"宝箱已出现"），无提示时不占空间

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
13. 仅在 PLAYING 状态下计时器运行并显示。COUNTDOWN 阶段计时器不显示（HUD 内容不可见）。FINISHED 阶段不在 Match 场景停留（立即切 Result），计时器无需定格

**阶段提示**

14. 临时文字提示，在特定事件发生时从底部弹入，持续数秒后自动淡出：
    - `chest_activated` → "🏆 宝箱已出现"（持续 3 秒）
15. 提示区同一时间只显示一条提示，新提示覆盖旧提示
16. 提示使用较大字号 + 半透明背景条，确保可读性不遮挡太多画面

**生命周期**

17. HUD 监听 Match State Manager 的 `state_changed` 信号：
    - COUNTDOWN：HUD 内容不显示（左右栏由 Prompt Input 显示 "Ready!" 文字）。HUD 在此阶段仅初始化内部状态（槽位全灰、计时器归零），但不渲染到屏幕
    - PLAYING：HUD 内容显示，启用实时更新（计时器、信号响应）。左右栏从 Prompt Input 的 "Ready!" 切换为 HUD 的钥匙进度
    - FINISHED：不做额外显示。Match 根脚本收到 `match_finished` 后立即切换到 Result 场景，HUD 随 Match 场景销毁。终局表现由 Result Screen 负责
18. HUD 监听 Key Collection 的 `key_collected` 信号更新钥匙槽位
19. HUD 监听 Win Condition 的 `chest_activated` 信号显示阶段提示

### Data Structures

```
# 场景节点结构
MatchHUD (Node):
  # HUD 内容分布在 Match 场景的三栏布局中

  # --- 左栏（Agent A 进度）---
  agent_a_panel: VBoxContainer        # 左栏：Agent A 进度
    agent_a_label: Label              # "A" 标签（蓝色）
    key_slots_a: Array<TextureRect>   # 3 个钥匙槽（Brass, Jade, Crystal）

  # --- 中栏顶部（计时器）---
  timer_panel: VBoxContainer          # 中栏顶部：计时器
    time_label: Label                 # "MM:SS" 时间显示
    tick_label: Label                 # "Tick NNN" tick 数显示

  # --- 右栏（Agent B 进度）---
  agent_b_panel: VBoxContainer        # 右栏：Agent B 进度
    key_slots_b: Array<TextureRect>   # 3 个钥匙槽（Brass, Jade, Crystal）
    agent_b_label: Label              # "B" 标签（红色）

  # --- 阶段提示区（CanvasLayer，覆盖中栏底部）---
  toast_layer: CanvasLayer            # 提示覆盖层
    toast_container: CenterContainer  # 底部居中容器
      toast_label: Label              # 阶段提示文字
      toast_bg: Panel                 # 半透明背景条

  # --- 内部状态 ---
  is_playing: bool                    # 当前是否在 PLAYING 状态（控制计时器更新）
  toast_timer: Timer                  # 提示自动淡出计时器

  # --- 信号监听（纯消费端）---
  # 监听 Match State Manager: state_changed, tick
  # 监听 Key Collection: key_collected
  # 监听 Win Condition: chest_activated
```

**设计决策**：

- **三栏布局集成**：HUD 的钥匙进度和计时器直接嵌入 Match 场景的三栏布局（左右栏 + 中栏顶部），与 Prompt Input 共享同一套栏位容器。阶段提示（toast）仍使用 CanvasLayer 覆盖在中栏底部，确保不被迷宫渲染遮挡
- **VBoxContainer 布局**：左右栏内使用 VBoxContainer 纵向排列钥匙进度，利用 Godot 的自动布局系统自适应
- **TextureRect 钥匙槽**：使用图片而非纯色块，可以复用 Match Renderer 的钥匙 Sprite 资源（灰色版 + 彩色版）
- **toast_timer**：独立 Timer 节点控制提示显示时长，timeout 后触发淡出动画

### States and Transitions

HUD 自身没有独立状态机——行为由 Match State Manager 状态驱动，与 Match Renderer 模式一致。

**HUD 行为随比赛阶段变化**

| Match State | HUD Behavior |
|-------------|-------------|
| **SETUP** | HUD 不可见（`visible = false`） |
| **COUNTDOWN** | HUD 内容不显示（左右栏由 Prompt Input 管理 "Ready!" 文字）。内部状态初始化：所有钥匙槽灰色，计时器归零，但不渲染到屏幕 |
| **PLAYING** | HUD 内容显示。左右栏切换为钥匙进度，中栏顶部显示计时器。实时更新：计时器每帧刷新，`key_collected` 信号触发槽位亮起，`chest_activated` 触发阶段提示 |
| **FINISHED** | 不做额外显示。Match 根脚本收到 `match_finished` 后立即切换到 Result 场景，HUD 随 Match 场景销毁 |

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
| **Match State Manager** | HUD depends on this | 监听 `state_changed`, `tick` 信号；查询 `get_elapsed_time()`, `get_tick_count()` | `state_changed`：驱动 HUD 生命周期（COUNTDOWN 内部初始化、PLAYING 显示并实时更新、FINISHED 随场景销毁）。`tick`：更新 tick 数显示。`get_elapsed_time()`：PLAYING 阶段每帧更新时间显示 |
| **Win Condition / Chest** | HUD depends on this | 监听 `chest_activated` 信号；查询 `is_chest_active()` | `chest_activated`：显示"宝箱已出现"阶段提示。`is_chest_active()`：初始化时恢复阶段状态 |
| **Grid Movement** | HUD depends on this | 查询 `get_total_moves(mover_id)` | MVP 不显示（预留）。未来可在 HUD 中显示每个 Agent 的移动步数统计 |
| **Match Renderer** | 共享三栏布局 | — | 两者都是 Presentation 层。HUD 的钥匙进度放在三栏的左右栏中，Match Renderer 的 God View 渲染在中栏。两者通过 Match 场景的三栏容器结构共存 |
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
| 比赛超时（`max_match_duration` 到达） | 不做特殊处理。超时触发 `match_finished(DRAW)`，Match 根脚本立即切换到 Result 场景，HUD 随场景销毁。"TIME UP" 展示由 Result Screen 负责 | FINISHED 状态不在 Match 场景停留 |
| 窗口 resize | HUD 通过 anchor/margin 自动适配新分辨率，无需手动调整 | Godot Control 节点的布局系统自动处理 |
| 比赛开始时已有进度（理论上不会发生，但防御性处理） | COUNTDOWN 时 HUD 内部初始化阶段查询 `get_agent_progress()` 恢复已有进度，槽位内部状态设为正确值（不渲染到屏幕）。PLAYING 开始时直接显示正确状态 | 防御性初始化，确保 HUD 内部状态与逻辑状态一致 |
| `chest_activated` 提示正在显示时收到 `match_finished` | 不做特殊处理。Match 根脚本立即切换到 Result 场景，HUD 随 Match 场景销毁 | FINISHED 状态不在 Match 场景停留，HUD 无需覆盖提示 |
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
| `toast_canvas_layer` | int | 10 | 5 - 20 | 阶段提示覆盖层的 CanvasLayer 层级。必须高于游戏世界（默认 0）和 Match Renderer |
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
| AC-1 | PLAYING 开始时所有 6 个钥匙槽（双方各 3）初始显示为灰色 | 视觉测试 + 单元测试：PLAYING 阶段开始后断言所有 TextureRect 使用灰色纹理 |
| AC-2 | `key_collected(0, KEY_BRASS)` 信号后，Agent A 的 Brass 槽位亮起金铜色 | 集成测试：模拟信号，断言纹理切换为彩色版且播放脉冲动画 |
| AC-3 | Agent A 拾取钥匙不影响 Agent B 的槽位显示 | 集成测试：A 拾取 Brass 后断言 B 的 Brass 槽仍为灰色 |
| AC-4 | 三把钥匙的槽位颜色与 Match Renderer 中的钥匙颜色一致（Brass=铜，Jade=绿，Crystal=蓝） | 视觉测试 |

### 计时器

| # | Criterion | Verification |
|---|-----------|-------------|
| AC-5 | PLAYING 状态下计时器每帧更新，显示格式为 `MM:SS \| Tick NNN` | 视觉测试 + 单元测试：断言 Label.text 格式正确 |
| AC-6 | FINISHED 状态下 HUD 不做额外显示，Match 根脚本立即切换到 Result 场景 | 集成测试：`match_finished` 信号发出后确认场景切换被触发 |
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
| AC-11 | HUD 钥匙进度在三栏布局的左右栏中显示，计时器在中栏顶部，不随 Camera2D 移动 | 视觉测试：缩放/平移摄像机后 HUD 位置不变 |
| AC-12 | 窗口 resize 后 HUD 自适应新分辨率 | 集成测试：运行中改变窗口大小，HUD 保持正确布局 |
| AC-13 | SETUP 状态下 HUD 内容不可见（左右栏由 Prompt Input 管理） | 单元测试：断言 HUD 钥匙进度和计时器元素 visible == false |
| AC-14 | COUNTDOWN 状态下 HUD 内容不显示（左右栏由 Prompt Input 显示 "Ready!"），内部状态已初始化（槽位灰色、计时器归零） | 单元测试：断言 HUD 元素 visible == false，内部 is_playing == false |

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
