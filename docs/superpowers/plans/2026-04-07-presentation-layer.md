# Presentation Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the four Presentation-layer systems (Match Renderer, Prompt Input, Match HUD, Result Screen) that depend on Foundation + Core + Feature layers and provide the complete visual game experience.

**Architecture:** Match Renderer is a Node2D rendering the maze via TileMapLayer, marker Sprites, and Agent Sprites with Tween animations, all contained in the Match scene's center column. Prompt Input is a CanvasLayer UI panel managing the SETUP-phase prompt collection with a sequential P1→P2 flow. Match HUD is a set of Control nodes displaying key progress, timer, and toast notifications in the left/right/center columns during PLAYING. Result Screen is an independent scene displaying match results, statistics, and Rematch/Quit buttons. All four systems share a consistent 3-column layout (20/60/20).

**Tech Stack:** Godot 4.6, GDScript, GUT 9.x, Tween animations, Control nodes, TileMapLayer

---

## File Structure

```
src/
  ui/
    match_renderer.gd            # MatchRenderer (Node2D) - maze/marker/agent rendering
    prompt_input.gd              # PromptInput (Control) - SETUP prompt collection
    match_hud.gd                 # MatchHUD (Node) - key progress, timer, toasts
    result_screen.gd             # ResultScreen (Control) - results, stats, rematch

scenes/
  match/
    Match.tscn                   # Update: add 3-column layout, renderer, HUD, prompt input
    match.gd                     # Update: wire signals, orchestrate lifecycle
  result/
    Result.tscn                  # Update: add 3-column layout, stats, buttons
    result.gd                    # Update: read Autoloads, display results

assets/
  data/
    game_config.json             # Add renderer/hud/prompt config sections (modify existing)
    ui_config.json               # UI-specific config (panel_ratio, colors, fonts)

tests/
  unit/
    test_match_renderer.gd       # MatchRenderer unit tests
    test_prompt_input.gd         # PromptInput unit tests
    test_match_hud.gd            # MatchHUD unit tests
    test_result_screen.gd        # ResultScreen unit tests
```

---

### Task 0: UI Config and 3-Column Layout Setup

**Files:**
- Create: `assets/data/ui_config.json`
- Modify: `assets/data/game_config.json`
- Modify: `src/shared/enums.gd`

- [ ] **Step 1: Create UI config file**

Create `assets/data/ui_config.json`:

```json
{
    "layout": {
        "panel_ratio": 0.20
    },
    "renderer": {
        "cell_size": 32,
        "margin_ratio": 0.1,
        "move_anim_ratio": 0.6,
        "bump_anim_duration": 0.2,
        "bump_offset": 4.0,
        "float_anim_amplitude": 3.0,
        "float_anim_period": 2.0,
        "agent_a_color": "#4488FF",
        "agent_b_color": "#FF4444",
        "agent_overlap_offset": 3.0
    },
    "hud": {
        "toast_duration": 3.0,
        "toast_fade_duration": 0.5,
        "key_slot_pulse_duration": 0.3,
        "key_slot_pulse_scale": 1.3,
        "timer_font_size": 24,
        "toast_font_size": 28,
        "hud_margin": 16
    },
    "prompt_input": {
        "placeholder_text": "Explore unvisited directions first. When at a fork, prefer directions you haven't been to. If you see a key, go to it immediately. Avoid revisiting dead ends.",
        "text_edit_min_lines": 8,
        "show_char_count": true
    },
    "result": {
        "result_title_font_size": 48,
        "stat_font_size": 16,
        "prompt_max_visible_lines": 6,
        "winner_color_a": "#4488FF",
        "winner_color_b": "#FF4444",
        "draw_color": "#AAAAAA"
    }
}
```

- [ ] **Step 2: Add Presentation enums to shared enums**

Append to `src/shared/enums.gd` (after existing enums):

```gdscript
enum RenderMode { GOD_VIEW, AGENT_VIEW }

enum AgentKeyState { NEED_BRASS, NEED_JADE, NEED_CRYSTAL, KEYS_COMPLETE }

## Ordered sequence of key MarkerTypes for iteration.
const KEY_SEQUENCE: Array[int] = [MarkerType.KEY_BRASS, MarkerType.KEY_JADE, MarkerType.KEY_CRYSTAL]
```

Note: `AgentKeyState` and `KEY_SEQUENCE` may already be added by the Feature Layer plan (Key Collection). If so, skip duplicates. The `RenderMode` enum is new to this layer.

- [ ] **Step 3: Commit**

```bash
git add assets/data/ui_config.json src/shared/enums.gd
git commit -m "feat: add UI config and RenderMode enum for Presentation Layer"
```

---

### Task 1: Match Scene 3-Column Layout

**Files:**
- Modify: `scenes/match/Match.tscn`
- Modify: `scenes/match/match.gd`

- [ ] **Step 1: Write Match scene with 3-column layout**

Update `scenes/match/match.gd`:

```gdscript
## Match scene root script.
## Manages the match lifecycle: 3-column layout, signal wiring, scene orchestration.
extends Control

@onready var left_panel: PanelContainer = $HBoxContainer/LeftPanel
@onready var center_panel: SubViewportContainer = $HBoxContainer/CenterPanel
@onready var right_panel: PanelContainer = $HBoxContainer/RightPanel

var _panel_ratio: float = 0.20


func _ready() -> void:
	_load_config()
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)


func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/ui_config.json")
	var layout_cfg: Dictionary = cfg.get("layout", {})
	_panel_ratio = ConfigLoader.get_or_default(layout_cfg, "panel_ratio", 0.20)


func _apply_layout() -> void:
	var vp_size := get_viewport_rect().size
	if left_panel and right_panel and center_panel:
		left_panel.custom_minimum_size.x = vp_size.x * _panel_ratio
		right_panel.custom_minimum_size.x = vp_size.x * _panel_ratio
		center_panel.custom_minimum_size.x = vp_size.x * (1.0 - 2.0 * _panel_ratio)
```

- [ ] **Step 2: Update Match.tscn to use Control root with HBoxContainer**

Recreate `scenes/match/Match.tscn`:

```bash
cat > scenes/match/Match.tscn << 'TSCN'
[gd_scene load_steps=2 format=3 uid="uid://match_scene"]

[ext_resource type="Script" path="res://scenes/match/match.gd" id="1"]

[node name="Match" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="HBoxContainer" type="HBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="LeftPanel" type="PanelContainer" parent="HBoxContainer"]
layout_mode = 2
size_flags_horizontal = 3

[node name="CenterPanel" type="SubViewportContainer" parent="HBoxContainer"]
layout_mode = 2
size_flags_horizontal = 3
size_flags_stretch_ratio = 3.0

[node name="SubViewport" type="SubViewport" parent="HBoxContainer/CenterPanel"]
size = Vector2i(768, 720)

[node name="RightPanel" type="PanelContainer" parent="HBoxContainer"]
layout_mode = 2
size_flags_horizontal = 3
TSCN
```

- [ ] **Step 3: Commit**

```bash
git add scenes/match/Match.tscn scenes/match/match.gd
git commit -m "feat: Match scene 3-column layout with configurable panel ratio"
```

---

### Task 2: MatchRenderer - Maze Grid Rendering

**Files:**
- Create: `src/ui/match_renderer.gd`
- Create: `tests/unit/test_match_renderer.gd`

- [ ] **Step 1: Write failing tests for MatchRenderer initialization**

Create `tests/unit/test_match_renderer.gd`:

```gdscript
## Unit tests for MatchRenderer.
extends GutTest

const MatchRendererClass := preload("res://src/ui/match_renderer.gd")
const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")

var renderer: Node2D
var maze: RefCounted


func before_each() -> void:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	maze = gen.generate(5, 5)
	assert_not_null(maze)

	renderer = MatchRendererClass.new()
	add_child_autoqfree(renderer)


func test_initialize_creates_maze_layer() -> void:
	renderer.initialize(maze)
	assert_not_null(renderer._maze_layer, "Maze layer should exist")


func test_initialize_creates_marker_layer() -> void:
	renderer.initialize(maze)
	assert_not_null(renderer._marker_layer, "Marker layer should exist")


func test_initialize_creates_agent_layer() -> void:
	renderer.initialize(maze)
	assert_not_null(renderer._agent_layer, "Agent layer should exist")


func test_grid_to_pixel_conversion() -> void:
	renderer.initialize(maze)
	var pixel := renderer.grid_to_pixel(Vector2i(0, 0))
	var expected := Vector2(renderer._cell_size / 2.0, renderer._cell_size / 2.0)
	assert_eq(pixel, expected)


func test_grid_to_pixel_offset() -> void:
	renderer.initialize(maze)
	var pixel := renderer.grid_to_pixel(Vector2i(2, 3))
	var cs: float = renderer._cell_size
	var expected := Vector2(2 * cs + cs / 2.0, 3 * cs + cs / 2.0)
	assert_eq(pixel, expected)


func test_agent_sprites_created() -> void:
	renderer.initialize(maze)
	assert_eq(renderer._agent_sprites.size(), 2, "Should have 2 agent sprites")


func test_agent_initial_positions() -> void:
	renderer.initialize(maze)
	var spawn_a := maze.get_marker_position(Enums.MarkerType.SPAWN_A)
	var sprite_a: Sprite2D = renderer._agent_sprites[0]
	assert_eq(sprite_a.position, renderer.grid_to_pixel(spawn_a))


func test_key_sprites_created() -> void:
	renderer.initialize(maze)
	assert_eq(renderer._key_sprites.size(), 3, "Should have 3 key sprites")


func test_brass_key_visible_initially() -> void:
	renderer.initialize(maze)
	var brass_sprite: Sprite2D = renderer._key_sprites[Enums.MarkerType.KEY_BRASS]
	assert_true(brass_sprite.visible, "Brass key should be visible initially")


func test_jade_key_hidden_initially() -> void:
	renderer.initialize(maze)
	var jade_sprite: Sprite2D = renderer._key_sprites[Enums.MarkerType.KEY_JADE]
	assert_false(jade_sprite.visible, "Jade key should be hidden initially")


func test_crystal_key_hidden_initially() -> void:
	renderer.initialize(maze)
	var crystal_sprite: Sprite2D = renderer._key_sprites[Enums.MarkerType.KEY_CRYSTAL]
	assert_false(crystal_sprite.visible, "Crystal key should be hidden initially")


func test_chest_sprite_hidden_initially() -> void:
	renderer.initialize(maze)
	if renderer._chest_sprite != null:
		assert_false(renderer._chest_sprite.visible, "Chest should be hidden initially")


func test_cleanup_removes_all() -> void:
	renderer.initialize(maze)
	renderer.cleanup()
	assert_eq(renderer._agent_sprites.size(), 0)
	assert_eq(renderer._key_sprites.size(), 0)
	assert_null(renderer._chest_sprite)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_match_renderer.gd -gexit`

Expected: FAIL - cannot preload `match_renderer.gd`

- [ ] **Step 3: Implement MatchRenderer**

Create `src/ui/match_renderer.gd`:

```gdscript
## Match Renderer - visualizes maze, markers, and agents.
## Instantiated in the Match scene's center column SubViewport.
## See design/gdd/match-renderer.md for full specification.
class_name MatchRenderer
extends Node2D

# --- Configuration ---
var _cell_size: int = 32
var _margin_ratio: float = 0.1
var _move_anim_ratio: float = 0.6
var _bump_anim_duration: float = 0.2
var _bump_offset: float = 4.0
var _float_anim_amplitude: float = 3.0
var _float_anim_period: float = 2.0
var _agent_a_color: Color = Color("#4488FF")
var _agent_b_color: Color = Color("#FF4444")
var _agent_overlap_offset: float = 3.0
var _render_mode: int = Enums.RenderMode.GOD_VIEW

# --- Internal Nodes ---
var _maze_layer: Node2D = null
var _marker_layer: Node2D = null
var _agent_layer: Node2D = null
var _maze: RefCounted = null

# --- Sprite References ---
var _agent_sprites: Dictionary = {}  # agent_id -> Sprite2D
var _key_sprites: Dictionary = {}    # MarkerType -> Sprite2D
var _chest_sprite: Sprite2D = null
var _agent_tweens: Dictionary = {}   # agent_id -> Tween (current movement tween)


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/ui_config.json")
	var rcfg: Dictionary = cfg.get("renderer", {})
	_cell_size = ConfigLoader.get_or_default(rcfg, "cell_size", 32)
	_margin_ratio = ConfigLoader.get_or_default(rcfg, "margin_ratio", 0.1)
	_move_anim_ratio = ConfigLoader.get_or_default(rcfg, "move_anim_ratio", 0.6)
	_bump_anim_duration = ConfigLoader.get_or_default(rcfg, "bump_anim_duration", 0.2)
	_bump_offset = ConfigLoader.get_or_default(rcfg, "bump_offset", 4.0)
	_float_anim_amplitude = ConfigLoader.get_or_default(rcfg, "float_anim_amplitude", 3.0)
	_float_anim_period = ConfigLoader.get_or_default(rcfg, "float_anim_period", 2.0)
	_agent_a_color = Color(ConfigLoader.get_or_default(rcfg, "agent_a_color", "#4488FF"))
	_agent_b_color = Color(ConfigLoader.get_or_default(rcfg, "agent_b_color", "#FF4444"))
	_agent_overlap_offset = ConfigLoader.get_or_default(rcfg, "agent_overlap_offset", 3.0)

	# Also read cell_size from game_config for consistency
	var game_cfg := ConfigLoader.load_json("res://assets/data/game_config.json")
	var maze_cfg: Dictionary = game_cfg.get("maze", {})
	_cell_size = ConfigLoader.get_or_default(maze_cfg, "cell_size", _cell_size)


## Build all render layers from MazeData.
func initialize(maze: RefCounted) -> void:
	cleanup()
	_maze = maze

	# Create layer containers
	_maze_layer = Node2D.new()
	_maze_layer.name = "MazeLayer"
	_maze_layer.z_index = 0
	add_child(_maze_layer)

	_marker_layer = Node2D.new()
	_marker_layer.name = "MarkerLayer"
	_marker_layer.z_index = 1
	add_child(_marker_layer)

	_agent_layer = Node2D.new()
	_agent_layer.name = "AgentLayer"
	_agent_layer.z_index = 2
	add_child(_agent_layer)

	_build_maze_grid()
	_build_markers()
	_build_agents()


## Draw maze walls and floors using simple draw calls.
## MVP: Uses _draw() on child nodes instead of TileMap for simplicity.
func _build_maze_grid() -> void:
	var grid_drawer := _MazeGridDrawer.new()
	grid_drawer.maze = _maze
	grid_drawer.cell_size = _cell_size
	_maze_layer.add_child(grid_drawer)


## Place marker sprites (keys + chest).
func _build_markers() -> void:
	# Keys
	for key_type in Enums.KEY_SEQUENCE:
		var pos: Vector2i = _maze.get_marker_position(key_type)
		if pos == Vector2i(-1, -1):
			push_warning("MatchRenderer: Missing key marker %d" % key_type)
			continue

		var sprite := Sprite2D.new()
		sprite.position = grid_to_pixel(pos)
		sprite.texture = _create_placeholder_texture(_get_key_color(key_type), 16)
		sprite.z_index = 1

		# Hardcoded initial visibility: only Brass visible
		sprite.visible = (key_type == Enums.MarkerType.KEY_BRASS)

		_marker_layer.add_child(sprite)
		_key_sprites[key_type] = sprite

	# Chest
	var chest_pos: Vector2i = _maze.get_marker_position(Enums.MarkerType.CHEST)
	if chest_pos != Vector2i(-1, -1):
		_chest_sprite = Sprite2D.new()
		_chest_sprite.position = grid_to_pixel(chest_pos)
		_chest_sprite.texture = _create_placeholder_texture(Color(0.8, 0.7, 0.2), 24)
		_chest_sprite.visible = false  # Chest starts inactive
		_chest_sprite.z_index = 1
		_marker_layer.add_child(_chest_sprite)


## Place agent sprites at spawn positions.
func _build_agents() -> void:
	for i in range(2):
		var spawn_marker: int = Enums.MarkerType.SPAWN_A if i == 0 else Enums.MarkerType.SPAWN_B
		var spawn_pos: Vector2i = _maze.get_marker_position(spawn_marker)
		var color: Color = _agent_a_color if i == 0 else _agent_b_color

		var sprite := Sprite2D.new()
		sprite.position = grid_to_pixel(spawn_pos)
		sprite.texture = _create_placeholder_texture(color, 24)
		sprite.z_index = 2
		_agent_layer.add_child(sprite)
		_agent_sprites[i] = sprite


# --- Coordinate Conversion ---

func grid_to_pixel(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * _cell_size + _cell_size / 2.0,
		grid_pos.y * _cell_size + _cell_size / 2.0
	)


# --- Animation Handlers ---

## Animate agent movement from old to new grid position.
func animate_move(mover_id: int, old_pos: Vector2i, new_pos: Vector2i, duration: float) -> void:
	if not _agent_sprites.has(mover_id):
		return

	var sprite: Sprite2D = _agent_sprites[mover_id]

	# Kill existing tween
	if _agent_tweens.has(mover_id) and _agent_tweens[mover_id] != null:
		_agent_tweens[mover_id].kill()
		# Snap to target of previous animation
	sprite.position = grid_to_pixel(old_pos)

	var target := grid_to_pixel(new_pos)
	var tween := create_tween()
	tween.tween_property(sprite, "position", target, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_agent_tweens[mover_id] = tween


## Animate agent bump (wall collision).
func animate_bump(mover_id: int, pos: Vector2i, direction: int) -> void:
	if not _agent_sprites.has(mover_id):
		return

	var sprite: Sprite2D = _agent_sprites[mover_id]
	var base := grid_to_pixel(pos)
	sprite.position = base

	var offset := Vector2.ZERO
	match direction:
		Enums.Direction.NORTH: offset = Vector2(0, -_bump_offset)
		Enums.Direction.EAST: offset = Vector2(_bump_offset, 0)
		Enums.Direction.SOUTH: offset = Vector2(0, _bump_offset)
		Enums.Direction.WEST: offset = Vector2(-_bump_offset, 0)

	if _agent_tweens.has(mover_id) and _agent_tweens[mover_id] != null:
		_agent_tweens[mover_id].kill()

	var tween := create_tween()
	tween.tween_property(sprite, "position", base + offset, _bump_anim_duration * 0.4)
	tween.tween_property(sprite, "position", base, _bump_anim_duration * 0.6).set_ease(Tween.EASE_OUT)
	_agent_tweens[mover_id] = tween


## Show a key sprite with fade-in animation.
func show_key(key_type: int) -> void:
	if not _key_sprites.has(key_type):
		return
	var sprite: Sprite2D = _key_sprites[key_type]
	sprite.visible = true
	sprite.modulate.a = 0.0
	sprite.scale = Vector2(0.5, 0.5)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.5)
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.5).set_ease(Tween.EASE_OUT)


## Handle key collected - adjust opacity.
func on_key_collected(key_type: int, both_collected: bool) -> void:
	if not _key_sprites.has(key_type):
		return
	var sprite: Sprite2D = _key_sprites[key_type]
	if both_collected:
		sprite.visible = false
	else:
		sprite.modulate.a = 0.4


## Show chest sprite with fade-in.
func show_chest() -> void:
	if _chest_sprite == null:
		return
	_chest_sprite.visible = true
	_chest_sprite.modulate.a = 0.0
	_chest_sprite.scale = Vector2(0.5, 0.5)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_chest_sprite, "modulate:a", 1.0, 0.5)
	tween.tween_property(_chest_sprite, "scale", Vector2(1.0, 1.0), 0.5).set_ease(Tween.EASE_OUT)


# --- Cleanup ---

func cleanup() -> void:
	for child in get_children():
		child.queue_free()
	_agent_sprites.clear()
	_key_sprites.clear()
	_chest_sprite = null
	_agent_tweens.clear()
	_maze_layer = null
	_marker_layer = null
	_agent_layer = null


# --- Helpers ---

func _get_key_color(key_type: int) -> Color:
	match key_type:
		Enums.MarkerType.KEY_BRASS: return Color(0.8, 0.6, 0.2)   # Copper/brass
		Enums.MarkerType.KEY_JADE: return Color(0.2, 0.8, 0.4)    # Green
		Enums.MarkerType.KEY_CRYSTAL: return Color(0.3, 0.6, 1.0) # Ice blue
	return Color.WHITE


## Create a simple colored square texture as placeholder.
func _create_placeholder_texture(color: Color, size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Internal class to draw the maze grid.
class _MazeGridDrawer extends Node2D:
	var maze: RefCounted
	var cell_size: int = 32

	func _draw() -> void:
		if maze == null:
			return
		var floor_color := Color(0.9, 0.9, 0.85)
		var wall_color := Color(0.2, 0.2, 0.25)
		var wall_width := 2.0

		# Draw floor tiles
		for y in range(maze.height):
			for x in range(maze.width):
				var rect := Rect2(x * cell_size, y * cell_size, cell_size, cell_size)
				draw_rect(rect, floor_color)

		# Draw walls
		for y in range(maze.height):
			for x in range(maze.width):
				var ox: float = x * cell_size
				var oy: float = y * cell_size
				if maze.has_wall(x, y, Enums.Direction.NORTH):
					draw_line(Vector2(ox, oy), Vector2(ox + cell_size, oy), wall_color, wall_width)
				if maze.has_wall(x, y, Enums.Direction.EAST):
					draw_line(Vector2(ox + cell_size, oy), Vector2(ox + cell_size, oy + cell_size), wall_color, wall_width)
				if maze.has_wall(x, y, Enums.Direction.SOUTH):
					draw_line(Vector2(ox, oy + cell_size), Vector2(ox + cell_size, oy + cell_size), wall_color, wall_width)
				if maze.has_wall(x, y, Enums.Direction.WEST):
					draw_line(Vector2(ox, oy), Vector2(ox, oy + cell_size), wall_color, wall_width)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_match_renderer.gd -gexit`

Expected: All 13 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/ui/match_renderer.gd tests/unit/test_match_renderer.gd
git commit -m "feat: MatchRenderer with maze grid, marker sprites, agent sprites, animations"
```

---

### Task 3: PromptInput - SETUP Phase UI

**Files:**
- Create: `src/ui/prompt_input.gd`
- Create: `tests/unit/test_prompt_input.gd`

- [ ] **Step 1: Write failing tests for PromptInput**

Create `tests/unit/test_prompt_input.gd`:

```gdscript
## Unit tests for PromptInput.
extends GutTest

const PromptInputClass := preload("res://src/ui/prompt_input.gd")

var pi: Control


func before_each() -> void:
	pi = PromptInputClass.new()
	add_child_autoqfree(pi)
	pi._initialize_ui()


func test_initial_state_is_player_a_input() -> void:
	assert_eq(pi.get_state(), PromptInputClass.InputState.PLAYER_A_INPUT)


func test_submit_player_a_advances_state() -> void:
	pi.submit_prompt_a("test prompt A")
	assert_eq(pi.get_state(), PromptInputClass.InputState.PLAYER_B_INPUT)


func test_submit_player_a_stores_prompt() -> void:
	pi.submit_prompt_a("my strategy")
	assert_eq(pi.get_prompt_a(), "my strategy")


func test_submit_player_b_advances_to_completed() -> void:
	pi.submit_prompt_a("A")
	pi.submit_prompt_b("B")
	assert_eq(pi.get_state(), PromptInputClass.InputState.COMPLETED)


func test_submit_player_b_stores_prompt() -> void:
	pi.submit_prompt_a("A")
	pi.submit_prompt_b("my B strategy")
	assert_eq(pi.get_prompt_b(), "my B strategy")


func test_empty_prompt_allowed() -> void:
	pi.submit_prompt_a("")
	assert_eq(pi.get_state(), PromptInputClass.InputState.PLAYER_B_INPUT)
	assert_eq(pi.get_prompt_a(), "")


func test_reset_clears_state() -> void:
	pi.submit_prompt_a("A")
	pi.submit_prompt_b("B")
	pi.reset_input()
	assert_eq(pi.get_state(), PromptInputClass.InputState.PLAYER_A_INPUT)
	assert_eq(pi.get_prompt_a(), "")
	assert_eq(pi.get_prompt_b(), "")


func test_submit_b_before_a_ignored() -> void:
	pi.submit_prompt_b("B")
	assert_eq(pi.get_state(), PromptInputClass.InputState.PLAYER_A_INPUT)


func test_completed_signal_emitted() -> void:
	watch_signals(pi)
	pi.submit_prompt_a("A")
	pi.submit_prompt_b("B")
	assert_signal_emitted(pi, "prompts_submitted")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_prompt_input.gd -gexit`

Expected: FAIL - cannot preload `prompt_input.gd`

- [ ] **Step 3: Implement PromptInput**

Create `src/ui/prompt_input.gd`:

```gdscript
## Prompt Input - SETUP phase prompt collection UI.
## Manages sequential P1→P2 prompt entry in the Match scene's left/right columns.
## See design/gdd/prompt-input.md for full specification.
class_name PromptInput
extends Control

enum InputState { PLAYER_A_INPUT, PLAYER_B_INPUT, COMPLETED }

signal prompts_submitted(prompt_a: String, prompt_b: String)

var _state: int = InputState.PLAYER_A_INPUT
var _prompt_a: String = ""
var _prompt_b: String = ""

# --- Config ---
var _placeholder_text: String = "Explore unvisited directions first. When at a fork, prefer directions you haven't been to. If you see a key, go to it immediately. Avoid revisiting dead ends."
var _text_edit_min_lines: int = 8
var _show_char_count: bool = true

# --- UI Nodes (created dynamically) ---
var _left_container: VBoxContainer = null
var _right_container: VBoxContainer = null
var _text_edit: TextEdit = null
var _ready_button: Button = null
var _char_label: Label = null
var _status_label: Label = null


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/ui_config.json")
	var pi_cfg: Dictionary = cfg.get("prompt_input", {})
	_placeholder_text = ConfigLoader.get_or_default(pi_cfg, "placeholder_text", _placeholder_text)
	_text_edit_min_lines = ConfigLoader.get_or_default(pi_cfg, "text_edit_min_lines", 8)
	_show_char_count = ConfigLoader.get_or_default(pi_cfg, "show_char_count", true)


## Initialize UI nodes. Called after adding to scene tree with panel references.
func _initialize_ui() -> void:
	_state = InputState.PLAYER_A_INPUT
	_prompt_a = ""
	_prompt_b = ""


# --- State Machine ---

func get_state() -> int:
	return _state


func get_prompt_a() -> String:
	return _prompt_a


func get_prompt_b() -> String:
	return _prompt_b


func submit_prompt_a(prompt: String) -> void:
	if _state != InputState.PLAYER_A_INPUT:
		return
	_prompt_a = prompt
	_state = InputState.PLAYER_B_INPUT


func submit_prompt_b(prompt: String) -> void:
	if _state != InputState.PLAYER_B_INPUT:
		return
	_prompt_b = prompt
	_state = InputState.COMPLETED
	prompts_submitted.emit(_prompt_a, _prompt_b)


func reset_input() -> void:
	_state = InputState.PLAYER_A_INPUT
	_prompt_a = ""
	_prompt_b = ""


## Build UI for current state into the given left/right panel containers.
func build_ui(left_panel: Control, right_panel: Control) -> void:
	_clear_panels(left_panel, right_panel)

	match _state:
		InputState.PLAYER_A_INPUT:
			_build_input_panel(left_panel, "Player 1", func(text: String): submit_prompt_a(text); build_ui(left_panel, right_panel))
			_build_waiting_panel(right_panel, "Waiting for Player 1...")
		InputState.PLAYER_B_INPUT:
			_build_ready_panel(left_panel, "Player 1 Ready")
			_build_input_panel(right_panel, "Player 2", func(text: String): submit_prompt_b(text))
		InputState.COMPLETED:
			_build_ready_panel(left_panel, "Player 1 Ready")
			_build_ready_panel(right_panel, "Player 2 Ready")


func _build_input_panel(container: Control, title: String, on_submit: Callable) -> void:
	var vbox := VBoxContainer.new()
	container.add_child(vbox)

	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	var text_edit := TextEdit.new()
	text_edit.placeholder_text = _placeholder_text
	text_edit.custom_minimum_size.y = _text_edit_min_lines * 20
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(text_edit)

	if _show_char_count:
		var char_label := Label.new()
		char_label.text = "0 characters"
		char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		text_edit.text_changed.connect(func(): char_label.text = "%d characters" % text_edit.text.length())
		vbox.add_child(char_label)

	var button := Button.new()
	button.text = "Ready"
	button.pressed.connect(func(): on_submit.call(text_edit.text))
	vbox.add_child(button)


func _build_waiting_panel(container: Control, message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(label)


func _build_ready_panel(container: Control, message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(label)


func _clear_panels(left: Control, right: Control) -> void:
	for child in left.get_children():
		child.queue_free()
	for child in right.get_children():
		child.queue_free()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_prompt_input.gd -gexit`

Expected: All 9 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/ui/prompt_input.gd tests/unit/test_prompt_input.gd
git commit -m "feat: PromptInput with sequential P1/P2 prompt collection, state machine"
```

---

### Task 4: MatchHUD - Key Progress, Timer, and Toasts

**Files:**
- Create: `src/ui/match_hud.gd`
- Create: `tests/unit/test_match_hud.gd`

- [ ] **Step 1: Write failing tests for MatchHUD**

Create `tests/unit/test_match_hud.gd`:

```gdscript
## Unit tests for MatchHUD.
extends GutTest

const MatchHUDClass := preload("res://src/ui/match_hud.gd")

var hud: Node


func before_each() -> void:
	hud = MatchHUDClass.new()
	add_child_autoqfree(hud)
	hud._initialize_state()


# --- Key Slot State ---

func test_initial_key_slots_all_locked() -> void:
	for agent_id in [0, 1]:
		for key_idx in range(3):
			assert_false(hud.is_key_slot_collected(agent_id, key_idx),
				"Agent %d slot %d should start locked" % [agent_id, key_idx])


func test_on_key_collected_agent_a_brass() -> void:
	hud.on_key_collected(0, Enums.MarkerType.KEY_BRASS)
	assert_true(hud.is_key_slot_collected(0, 0), "Agent A brass slot should be collected")
	assert_false(hud.is_key_slot_collected(0, 1), "Agent A jade slot still locked")
	assert_false(hud.is_key_slot_collected(0, 2), "Agent A crystal slot still locked")


func test_on_key_collected_agent_b_jade() -> void:
	hud.on_key_collected(1, Enums.MarkerType.KEY_JADE)
	assert_true(hud.is_key_slot_collected(1, 1), "Agent B jade slot should be collected")
	assert_false(hud.is_key_slot_collected(1, 0), "Agent B brass slot still locked")


func test_on_key_collected_all_three() -> void:
	hud.on_key_collected(0, Enums.MarkerType.KEY_BRASS)
	hud.on_key_collected(0, Enums.MarkerType.KEY_JADE)
	hud.on_key_collected(0, Enums.MarkerType.KEY_CRYSTAL)
	assert_true(hud.is_key_slot_collected(0, 0))
	assert_true(hud.is_key_slot_collected(0, 1))
	assert_true(hud.is_key_slot_collected(0, 2))


func test_agent_independence() -> void:
	hud.on_key_collected(0, Enums.MarkerType.KEY_BRASS)
	assert_true(hud.is_key_slot_collected(0, 0))
	assert_false(hud.is_key_slot_collected(1, 0), "Agent B unaffected by Agent A pickup")


# --- Timer ---

func test_format_time_zero() -> void:
	assert_eq(hud.format_time(0.0, 0), "00:00 | Tick 0")


func test_format_time_normal() -> void:
	assert_eq(hud.format_time(95.7, 191), "01:35 | Tick 191")


func test_format_time_large() -> void:
	assert_eq(hud.format_time(3661.0, 7322), "61:01 | Tick 7322")


# --- Toast ---

func test_show_toast_sets_text() -> void:
	hud.show_toast("Test message")
	assert_eq(hud.get_toast_text(), "Test message")
	assert_true(hud.is_toast_visible())


func test_show_toast_overwrites_previous() -> void:
	hud.show_toast("First")
	hud.show_toast("Second")
	assert_eq(hud.get_toast_text(), "Second")


func test_clear_toast() -> void:
	hud.show_toast("Test")
	hud.clear_toast()
	assert_false(hud.is_toast_visible())


# --- Lifecycle ---

func test_set_playing_enables_updates() -> void:
	hud.set_playing(true)
	assert_true(hud._is_playing)


func test_set_playing_false_disables_updates() -> void:
	hud.set_playing(true)
	hud.set_playing(false)
	assert_false(hud._is_playing)


func test_key_collected_ignored_when_not_playing() -> void:
	hud.set_playing(false)
	hud.on_key_collected(0, Enums.MarkerType.KEY_BRASS)
	assert_false(hud.is_key_slot_collected(0, 0),
		"Key collection should be ignored when not playing")


func test_initialize_resets_all() -> void:
	hud.set_playing(true)
	hud.on_key_collected(0, Enums.MarkerType.KEY_BRASS)
	hud.show_toast("test")
	hud._initialize_state()
	assert_false(hud.is_key_slot_collected(0, 0))
	assert_false(hud.is_toast_visible())
	assert_false(hud._is_playing)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_match_hud.gd -gexit`

Expected: FAIL - cannot preload `match_hud.gd`

- [ ] **Step 3: Implement MatchHUD**

Create `src/ui/match_hud.gd`:

```gdscript
## Match HUD - displays key progress, timer, and toast notifications.
## Renders in the Match scene's three-column layout during PLAYING state.
## See design/gdd/match-hud.md for full specification.
class_name MatchHUD
extends Node

# --- Configuration ---
var _toast_duration: float = 3.0
var _toast_fade_duration: float = 0.5
var _key_slot_pulse_duration: float = 0.3
var _key_slot_pulse_scale: float = 1.3
var _timer_font_size: int = 24
var _toast_font_size: int = 28
var _hud_margin: int = 16

# --- Internal State ---
var _is_playing: bool = false
var _key_slots: Dictionary = {}   # {agent_id: {slot_index: bool}}
var _toast_text: String = ""
var _toast_visible: bool = false
var _toast_tween: Tween = null

# --- UI Nodes (set by build_hud) ---
var _key_slot_nodes: Dictionary = {}  # {agent_id: Array[TextureRect]}
var _time_label: Label = null
var _tick_label: Label = null
var _toast_label: Label = null
var _toast_bg: Panel = null

# --- Key Colors ---
const KEY_COLORS: Array[Color] = [
	Color(0.8, 0.6, 0.2),   # Brass = copper
	Color(0.2, 0.8, 0.4),   # Jade = green
	Color(0.3, 0.6, 1.0),   # Crystal = ice blue
]


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/ui_config.json")
	var hud_cfg: Dictionary = cfg.get("hud", {})
	_toast_duration = ConfigLoader.get_or_default(hud_cfg, "toast_duration", 3.0)
	_toast_fade_duration = ConfigLoader.get_or_default(hud_cfg, "toast_fade_duration", 0.5)
	_key_slot_pulse_duration = ConfigLoader.get_or_default(hud_cfg, "key_slot_pulse_duration", 0.3)
	_key_slot_pulse_scale = ConfigLoader.get_or_default(hud_cfg, "key_slot_pulse_scale", 1.3)
	_timer_font_size = ConfigLoader.get_or_default(hud_cfg, "timer_font_size", 24)
	_toast_font_size = ConfigLoader.get_or_default(hud_cfg, "toast_font_size", 28)
	_hud_margin = ConfigLoader.get_or_default(hud_cfg, "hud_margin", 16)


## Initialize internal state to defaults (all locked, no toast, not playing).
func _initialize_state() -> void:
	_is_playing = false
	_toast_text = ""
	_toast_visible = false
	_key_slots.clear()
	for agent_id in [0, 1]:
		_key_slots[agent_id] = {0: false, 1: false, 2: false}


## Enable/disable HUD updates.
func set_playing(playing: bool) -> void:
	_is_playing = playing


# --- Key Slots ---

## Map a MarkerType key to slot index (0=Brass, 1=Jade, 2=Crystal).
func _key_type_to_slot(key_type: int) -> int:
	match key_type:
		Enums.MarkerType.KEY_BRASS: return 0
		Enums.MarkerType.KEY_JADE: return 1
		Enums.MarkerType.KEY_CRYSTAL: return 2
	return -1


## Handle key_collected signal from KeyCollection.
func on_key_collected(agent_id: int, key_type: int) -> void:
	if not _is_playing:
		return
	var slot := _key_type_to_slot(key_type)
	if slot == -1:
		return
	if not _key_slots.has(agent_id):
		return
	_key_slots[agent_id][slot] = true

	# Animate slot if UI nodes exist
	if _key_slot_nodes.has(agent_id):
		var nodes: Array = _key_slot_nodes[agent_id]
		if slot < nodes.size():
			_animate_slot_collected(nodes[slot], slot)


func is_key_slot_collected(agent_id: int, slot_index: int) -> bool:
	if not _key_slots.has(agent_id):
		return false
	return _key_slots[agent_id].get(slot_index, false)


func _animate_slot_collected(slot_node: TextureRect, slot_index: int) -> void:
	# Change texture to colored version
	var color: Color = KEY_COLORS[slot_index] if slot_index < KEY_COLORS.size() else Color.WHITE
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(color)
	slot_node.texture = ImageTexture.create_from_image(img)

	# Pulse animation
	var tween := create_tween()
	tween.tween_property(slot_node, "scale", Vector2(_key_slot_pulse_scale, _key_slot_pulse_scale), _key_slot_pulse_duration * 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot_node, "scale", Vector2(1.0, 1.0), _key_slot_pulse_duration * 0.6).set_ease(Tween.EASE_IN)


# --- Timer ---

## Format elapsed time and tick count for display.
func format_time(elapsed: float, ticks: int) -> String:
	var minutes := int(elapsed) / 60
	var seconds := int(elapsed) % 60
	return "%02d:%02d | Tick %d" % [minutes, seconds, ticks]


## Update timer display (called every frame during PLAYING).
func update_timer(elapsed: float, ticks: int) -> void:
	if _time_label != null:
		_time_label.text = format_time(elapsed, ticks)


# --- Toast ---

func show_toast(message: String) -> void:
	_toast_text = message
	_toast_visible = true

	# Cancel existing fade
	if _toast_tween != null:
		_toast_tween.kill()
		_toast_tween = null

	# Update UI if nodes exist
	if _toast_label != null:
		_toast_label.text = message
		_toast_label.visible = true
		_toast_label.modulate.a = 1.0
	if _toast_bg != null:
		_toast_bg.visible = true
		_toast_bg.modulate.a = 0.5

	# Auto-fade after duration
	_toast_tween = create_tween()
	_toast_tween.tween_interval(_toast_duration)
	_toast_tween.tween_callback(func():
		_fade_toast()
	)


func _fade_toast() -> void:
	if _toast_label != null:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(_toast_label, "modulate:a", 0.0, _toast_fade_duration)
		if _toast_bg != null:
			tween.tween_property(_toast_bg, "modulate:a", 0.0, _toast_fade_duration)
		tween.chain().tween_callback(func():
			_toast_visible = false
			if _toast_label != null:
				_toast_label.visible = false
			if _toast_bg != null:
				_toast_bg.visible = false
		)
	else:
		_toast_visible = false


func clear_toast() -> void:
	_toast_text = ""
	_toast_visible = false
	if _toast_tween != null:
		_toast_tween.kill()
		_toast_tween = null
	if _toast_label != null:
		_toast_label.visible = false
	if _toast_bg != null:
		_toast_bg.visible = false


func get_toast_text() -> String:
	return _toast_text


func is_toast_visible() -> bool:
	return _toast_visible


# --- UI Building ---

## Build HUD UI into the Match scene's three-column layout.
## Called by match.gd after entering PLAYING state.
func build_hud(left_panel: Control, center_panel: Control, right_panel: Control) -> void:
	_build_key_progress_panel(left_panel, 0, "A", Color("#4488FF"))
	_build_key_progress_panel(right_panel, 1, "B", Color("#FF4444"))
	_build_timer_panel(center_panel)
	_build_toast_overlay()


func _build_key_progress_panel(container: Control, agent_id: int, label_text: String, color: Color) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	container.add_child(vbox)

	# Agent label
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	vbox.add_child(label)

	# Key slots
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	var slot_nodes: Array[TextureRect] = []
	for i in range(3):
		var slot := TextureRect.new()
		slot.custom_minimum_size = Vector2(20, 20)
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.pivot_offset = Vector2(10, 10)

		# Gray placeholder texture
		var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.4, 0.4, 0.4))
		slot.texture = ImageTexture.create_from_image(img)

		# If already collected (defensive init), color it
		if _key_slots.has(agent_id) and _key_slots[agent_id].get(i, false):
			var cimg := Image.create(20, 20, false, Image.FORMAT_RGBA8)
			cimg.fill(KEY_COLORS[i])
			slot.texture = ImageTexture.create_from_image(cimg)

		hbox.add_child(slot)
		slot_nodes.append(slot)

	_key_slot_nodes[agent_id] = slot_nodes


func _build_timer_panel(container: Control) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	container.add_child(vbox)

	_time_label = Label.new()
	_time_label.text = "00:00 | Tick 0"
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_time_label)


func _build_toast_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var center := CenterContainer.new()
	center.anchors_preset = Control.PRESET_BOTTOM_WIDE
	center.offset_top = -80
	canvas.add_child(center)

	_toast_bg = Panel.new()
	_toast_bg.custom_minimum_size = Vector2(400, 50)
	_toast_bg.visible = false
	_toast_bg.modulate.a = 0.5
	center.add_child(_toast_bg)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.visible = false
	_toast_bg.add_child(_toast_label)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_match_hud.gd -gexit`

Expected: All 15 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/ui/match_hud.gd tests/unit/test_match_hud.gd
git commit -m "feat: MatchHUD with key progress slots, timer, toast notifications"
```

---

### Task 5: ResultScreen - Match Results and Statistics

**Files:**
- Create: `src/ui/result_screen.gd`
- Create: `tests/unit/test_result_screen.gd`
- Modify: `scenes/result/Result.tscn`
- Modify: `scenes/result/result.gd`

- [ ] **Step 1: Write failing tests for ResultScreen**

Create `tests/unit/test_result_screen.gd`:

```gdscript
## Unit tests for ResultScreen.
extends GutTest

const ResultScreenClass := preload("res://src/ui/result_screen.gd")

var rs: Control


func before_each() -> void:
	rs = ResultScreenClass.new()
	add_child_autoqfree(rs)


# --- Result Title ---

func test_get_result_title_player_a_wins() -> void:
	assert_eq(rs.get_result_title(Enums.MatchResult.PLAYER_A_WIN), "Player 1 Wins!")


func test_get_result_title_player_b_wins() -> void:
	assert_eq(rs.get_result_title(Enums.MatchResult.PLAYER_B_WIN), "Player 2 Wins!")


func test_get_result_title_draw() -> void:
	assert_eq(rs.get_result_title(Enums.MatchResult.DRAW), "Draw!")


func test_get_result_title_none() -> void:
	assert_eq(rs.get_result_title(Enums.MatchResult.NONE), "No Result")


# --- Result Color ---

func test_get_result_color_player_a() -> void:
	assert_eq(rs.get_result_color(Enums.MatchResult.PLAYER_A_WIN), rs._winner_color_a)


func test_get_result_color_player_b() -> void:
	assert_eq(rs.get_result_color(Enums.MatchResult.PLAYER_B_WIN), rs._winner_color_b)


func test_get_result_color_draw() -> void:
	assert_eq(rs.get_result_color(Enums.MatchResult.DRAW), rs._draw_color)


# --- Agent Status Text ---

func test_get_agent_status_winner() -> void:
	assert_eq(rs.get_agent_status(0, Enums.MatchResult.PLAYER_A_WIN, 0), "Winner")


func test_get_agent_status_defeated() -> void:
	assert_eq(rs.get_agent_status(1, Enums.MatchResult.PLAYER_A_WIN, 0), "Defeated")


func test_get_agent_status_draw() -> void:
	assert_eq(rs.get_agent_status(0, Enums.MatchResult.DRAW, -1), "Draw")
	assert_eq(rs.get_agent_status(1, Enums.MatchResult.DRAW, -1), "Draw")


# --- Idle Rate ---

func test_calculate_idle_rate_normal() -> void:
	assert_almost_eq(rs.calculate_idle_rate(25, 200), 12.5, 0.01)


func test_calculate_idle_rate_zero_ticks() -> void:
	assert_eq(rs.calculate_idle_rate(10, 0), 0.0)


func test_calculate_idle_rate_zero_idle() -> void:
	assert_eq(rs.calculate_idle_rate(0, 100), 0.0)


func test_calculate_idle_rate_100_percent() -> void:
	assert_almost_eq(rs.calculate_idle_rate(100, 100), 100.0, 0.01)


# --- Time Format ---

func test_format_elapsed_time() -> void:
	assert_eq(rs.format_elapsed_time(95.7), "1:35")


func test_format_elapsed_time_zero() -> void:
	assert_eq(rs.format_elapsed_time(0.0), "0:00")


func test_format_elapsed_time_large() -> void:
	assert_eq(rs.format_elapsed_time(3661.0), "61:01")


# --- Keys Progress ---

func test_get_keys_string_none() -> void:
	assert_eq(rs.get_keys_string(Enums.AgentKeyState.NEED_BRASS), "0/3")


func test_get_keys_string_one() -> void:
	assert_eq(rs.get_keys_string(Enums.AgentKeyState.NEED_JADE), "1/3")


func test_get_keys_string_two() -> void:
	assert_eq(rs.get_keys_string(Enums.AgentKeyState.NEED_CRYSTAL), "2/3")


func test_get_keys_string_all() -> void:
	assert_eq(rs.get_keys_string(Enums.AgentKeyState.KEYS_COMPLETE), "3/3")


# --- Prompt Display ---

func test_get_prompt_display_normal() -> void:
	assert_eq(rs.get_prompt_display("my strategy"), "my strategy")


func test_get_prompt_display_empty() -> void:
	assert_eq(rs.get_prompt_display(""), "(empty)")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_result_screen.gd -gexit`

Expected: FAIL - cannot preload `result_screen.gd`

- [ ] **Step 3: Implement ResultScreen**

Create `src/ui/result_screen.gd`:

```gdscript
## Result Screen - displays match results, statistics, and prompts.
## Independent scene loaded by SceneManager after FINISHED state.
## See design/gdd/result-screen.md for full specification.
class_name ResultScreen
extends Control

# --- Configuration ---
var _panel_ratio: float = 0.20
var _result_title_font_size: int = 48
var _stat_font_size: int = 16
var _prompt_max_visible_lines: int = 6
var _winner_color_a: Color = Color("#4488FF")
var _winner_color_b: Color = Color("#FF4444")
var _draw_color: Color = Color("#AAAAAA")


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var ui_cfg := ConfigLoader.load_json("res://assets/data/ui_config.json")
	var layout_cfg: Dictionary = ui_cfg.get("layout", {})
	_panel_ratio = ConfigLoader.get_or_default(layout_cfg, "panel_ratio", 0.20)

	var result_cfg: Dictionary = ui_cfg.get("result", {})
	_result_title_font_size = ConfigLoader.get_or_default(result_cfg, "result_title_font_size", 48)
	_stat_font_size = ConfigLoader.get_or_default(result_cfg, "stat_font_size", 16)
	_prompt_max_visible_lines = ConfigLoader.get_or_default(result_cfg, "prompt_max_visible_lines", 6)
	_winner_color_a = Color(ConfigLoader.get_or_default(result_cfg, "winner_color_a", "#4488FF"))
	_winner_color_b = Color(ConfigLoader.get_or_default(result_cfg, "winner_color_b", "#FF4444"))
	_draw_color = Color(ConfigLoader.get_or_default(result_cfg, "draw_color", "#AAAAAA"))


# --- Data Formatting ---

## Get the result title text for a given match result.
func get_result_title(match_result: int) -> String:
	match match_result:
		Enums.MatchResult.PLAYER_A_WIN: return "Player 1 Wins!"
		Enums.MatchResult.PLAYER_B_WIN: return "Player 2 Wins!"
		Enums.MatchResult.DRAW: return "Draw!"
	return "No Result"


## Get the result color for a given match result.
func get_result_color(match_result: int) -> Color:
	match match_result:
		Enums.MatchResult.PLAYER_A_WIN: return _winner_color_a
		Enums.MatchResult.PLAYER_B_WIN: return _winner_color_b
		Enums.MatchResult.DRAW: return _draw_color
	return Color.WHITE


## Get agent status text ("Winner" / "Defeated" / "Draw").
func get_agent_status(agent_id: int, match_result: int, match_winner_id: int) -> String:
	if match_result == Enums.MatchResult.DRAW:
		return "Draw"
	if agent_id == match_winner_id:
		return "Winner"
	return "Defeated"


## Calculate idle rate as percentage. Returns 0.0 if tick_count is 0.
func calculate_idle_rate(idle_ticks: int, tick_count: int) -> float:
	if tick_count == 0:
		return 0.0
	return float(idle_ticks) / float(tick_count) * 100.0


## Format elapsed time as "M:SS".
func format_elapsed_time(elapsed: float) -> String:
	var total_seconds := int(elapsed)
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	return "%d:%02d" % [minutes, seconds]


## Get keys progress string from AgentKeyState.
func get_keys_string(agent_state: int) -> String:
	match agent_state:
		Enums.AgentKeyState.NEED_BRASS: return "0/3"
		Enums.AgentKeyState.NEED_JADE: return "1/3"
		Enums.AgentKeyState.NEED_CRYSTAL: return "2/3"
		Enums.AgentKeyState.KEYS_COMPLETE: return "3/3"
	return "0/3"


## Get prompt display text ("(empty)" if blank).
func get_prompt_display(prompt: String) -> String:
	if prompt.strip_edges().is_empty():
		return "(empty)"
	return prompt


# --- UI Building ---

## Populate the result screen with data from Autoloads.
## Called from result.gd _ready().
func populate_from_autoloads() -> void:
	# Read from MatchStateManager
	var match_result: int = MatchStateManager.result
	var match_winner_id: int = MatchStateManager.winner_id
	var prompt_a: String = MatchStateManager.config.get("prompt_a", "")
	var prompt_b: String = MatchStateManager.config.get("prompt_b", "")
	var tick_count: int = MatchStateManager.tick_count
	var elapsed_time: float = MatchStateManager.get_elapsed_time()

	# Read from LLMAgentManager (defensive: may not exist)
	var api_calls_a: int = 0
	var api_calls_b: int = 0
	var tokens_a: int = 0
	var tokens_b: int = 0
	var idle_a: int = 0
	var idle_b: int = 0

	if LLMAgentManager != null:
		var brain_a = LLMAgentManager.get_brain(0)
		var brain_b = LLMAgentManager.get_brain(1)
		if brain_a != null:
			api_calls_a = brain_a.get("total_api_calls", 0)
			tokens_a = brain_a.get("total_tokens_used", 0)
			idle_a = brain_a.get("total_idle_ticks", 0)
		if brain_b != null:
			api_calls_b = brain_b.get("total_api_calls", 0)
			tokens_b = brain_b.get("total_tokens_used", 0)
			idle_b = brain_b.get("total_idle_ticks", 0)

	# Read from KeyCollection (defensive: may not exist)
	var keys_a: int = Enums.AgentKeyState.NEED_BRASS
	var keys_b: int = Enums.AgentKeyState.NEED_BRASS
	if KeyCollection != null:
		keys_a = KeyCollection.get_agent_progress(0)
		keys_b = KeyCollection.get_agent_progress(1)

	# Build UI
	_build_result_ui(
		match_result, match_winner_id,
		prompt_a, prompt_b,
		tick_count, elapsed_time,
		api_calls_a, tokens_a, idle_a,
		api_calls_b, tokens_b, idle_b,
		keys_a, keys_b
	)


func _build_result_ui(
	match_result: int, match_winner_id: int,
	prompt_a: String, prompt_b: String,
	tick_count: int, elapsed_time: float,
	api_calls_a: int, tokens_a: int, idle_a: int,
	api_calls_b: int, tokens_b: int, idle_b: int,
	keys_a: int, keys_b: int
) -> void:
	# Root HBoxContainer for 3-column layout
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(hbox)

	var vp_width := get_viewport_rect().size.x

	# Left panel - Agent A stats
	var left := PanelContainer.new()
	left.custom_minimum_size.x = vp_width * _panel_ratio
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left)
	_build_agent_panel(left, 0, "Agent A", Color("#4488FF"),
		match_result, match_winner_id,
		api_calls_a, tokens_a, idle_a, tick_count,
		keys_a, prompt_a)

	# Center panel - Result title + buttons
	var center := PanelContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 3.0
	hbox.add_child(center)
	_build_center_panel(center, match_result, elapsed_time, tick_count)

	# Right panel - Agent B stats
	var right := PanelContainer.new()
	right.custom_minimum_size.x = vp_width * _panel_ratio
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	_build_agent_panel(right, 1, "Agent B", Color("#FF4444"),
		match_result, match_winner_id,
		api_calls_b, tokens_b, idle_b, tick_count,
		keys_b, prompt_b)


func _build_center_panel(container: Control, match_result: int, elapsed_time: float, tick_count: int) -> void:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	container.add_child(vbox)

	# Spacer
	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer_top)

	# Result title
	var title := Label.new()
	title.text = get_result_title(match_result)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", get_result_color(match_result))
	vbox.add_child(title)

	# Time UP subtitle for draw
	if match_result == Enums.MatchResult.DRAW:
		var time_up := Label.new()
		time_up.text = "TIME UP"
		time_up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_up.add_theme_color_override("font_color", _draw_color)
		vbox.add_child(time_up)

	# Time and ticks
	var time_label := Label.new()
	time_label.text = "Time: %s" % format_elapsed_time(elapsed_time)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(time_label)

	var tick_label := Label.new()
	tick_label.text = "Ticks: %d" % tick_count
	tick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tick_label)

	# Buttons
	var button_spacer := Control.new()
	button_spacer.custom_minimum_size.y = 20
	vbox.add_child(button_spacer)

	var rematch_btn := Button.new()
	rematch_btn.text = "Rematch"
	rematch_btn.pressed.connect(_on_rematch_pressed)
	vbox.add_child(rematch_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)

	# Spacer bottom
	var spacer_bot := Control.new()
	spacer_bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer_bot)


func _build_agent_panel(container: Control, agent_id: int, agent_name: String, color: Color,
		match_result: int, match_winner_id: int,
		api_calls: int, tokens: int, idle_ticks: int, tick_count: int,
		keys_state: int, prompt: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# Agent title
	var title := Label.new()
	title.text = agent_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", color)
	vbox.add_child(title)

	# Status (Winner / Defeated / Draw)
	var status := Label.new()
	status.text = get_agent_status(agent_id, match_result, match_winner_id)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Stats
	_add_stat_label(vbox, "API Calls: %d" % api_calls)
	_add_stat_label(vbox, "Tokens: %s" % _format_number(tokens))
	var idle_rate := calculate_idle_rate(idle_ticks, tick_count)
	_add_stat_label(vbox, "Idle Ticks: %d (%d%%)" % [idle_ticks, int(idle_rate)])
	_add_stat_label(vbox, "Keys: %s" % get_keys_string(keys_state))

	# Separator
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Prompt section
	var prompt_header := Label.new()
	prompt_header.text = "Prompt"
	prompt_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(prompt_header)

	var prompt_text := TextEdit.new()
	prompt_text.text = get_prompt_display(prompt)
	prompt_text.editable = false
	prompt_text.custom_minimum_size.y = _prompt_max_visible_lines * 20
	vbox.add_child(prompt_text)


func _add_stat_label(container: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	container.add_child(label)


func _format_number(n: int) -> String:
	# Simple number formatting with commas
	var s := str(n)
	if n < 1000:
		return s
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result


# --- Button Handlers ---

func _on_rematch_pressed() -> void:
	MatchStateManager.reset()
	SceneManagerGlobal.go_to("match")


func _on_quit_pressed() -> void:
	get_tree().quit()
```

- [ ] **Step 4: Update Result scene script**

Modify `scenes/result/result.gd`:

```gdscript
## Result scene root script.
## Loads ResultScreen component and populates it from Autoloads.
extends Control

const ResultScreenClass := preload("res://src/ui/result_screen.gd")

var _result_screen: Control = null


func _ready() -> void:
	_result_screen = ResultScreenClass.new()
	add_child(_result_screen)
	_result_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_screen.populate_from_autoloads()
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_result_screen.gd -gexit`

Expected: All 22 tests PASS

- [ ] **Step 6: Commit**

```bash
git add src/ui/result_screen.gd tests/unit/test_result_screen.gd scenes/result/result.gd
git commit -m "feat: ResultScreen with result title, agent stats, prompt display, rematch/quit"
```

---

### Task 6: Match Scene Orchestration - Signal Wiring

**Files:**
- Modify: `scenes/match/match.gd`

- [ ] **Step 1: Implement full Match scene orchestration**

Update `scenes/match/match.gd` with complete signal wiring and lifecycle management:

```gdscript
## Match scene root script.
## Orchestrates all systems: maze generation, movement, keys, win condition,
## renderer, HUD, prompt input, and LLM agents via signal wiring.
extends Control

const MazeGenerator := preload("res://src/core/maze_generator.gd")
const GridMovement := preload("res://src/core/grid_movement.gd")
const FogOfWar := preload("res://src/core/fog_of_war.gd")
const KeyCollectionClass := preload("res://src/gameplay/key_collection.gd")
const WinConditionClass := preload("res://src/gameplay/win_condition.gd")
const MatchRendererClass := preload("res://src/ui/match_renderer.gd")
const PromptInputClass := preload("res://src/ui/prompt_input.gd")
const MatchHUDClass := preload("res://src/ui/match_hud.gd")

# --- Layout Nodes ---
@onready var left_panel: PanelContainer = $HBoxContainer/LeftPanel
@onready var center_panel: SubViewportContainer = $HBoxContainer/CenterPanel
@onready var right_panel: PanelContainer = $HBoxContainer/RightPanel
@onready var sub_viewport: SubViewport = $HBoxContainer/CenterPanel/SubViewport

# --- Scene-local Systems ---
var _maze_gen: Node = null
var _grid_movement: Node = null
var _fog: Node = null
var _win_condition: Node = null
var _renderer: Node2D = null
var _prompt_input: Control = null
var _hud: Node = null

# --- Config ---
var _panel_ratio: float = 0.20
var _maze: RefCounted = null


func _ready() -> void:
	_load_config()
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)

	# Connect to MatchStateManager
	MatchStateManager.state_changed.connect(_on_state_changed)
	MatchStateManager.tick.connect(_on_tick)
	MatchStateManager.setup_failed.connect(_on_setup_failed)

	# Start in SETUP: show prompt input
	_setup_prompt_input()


func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/ui_config.json")
	var layout_cfg: Dictionary = cfg.get("layout", {})
	_panel_ratio = ConfigLoader.get_or_default(layout_cfg, "panel_ratio", 0.20)


func _apply_layout() -> void:
	var vp_size := get_viewport_rect().size
	if left_panel and right_panel and center_panel:
		left_panel.custom_minimum_size.x = vp_size.x * _panel_ratio
		right_panel.custom_minimum_size.x = vp_size.x * _panel_ratio
		center_panel.custom_minimum_size.x = vp_size.x * (1.0 - 2.0 * _panel_ratio)


func _process(_delta: float) -> void:
	# Update HUD timer during PLAYING
	if _hud != null and MatchStateManager.current_state == Enums.MatchState.PLAYING:
		_hud.update_timer(MatchStateManager.get_elapsed_time(), MatchStateManager.tick_count)


# --- SETUP Phase: Prompt Input ---

func _setup_prompt_input() -> void:
	_prompt_input = PromptInputClass.new()
	add_child(_prompt_input)
	_prompt_input._initialize_ui()
	_prompt_input.build_ui(left_panel, right_panel)
	_prompt_input.prompts_submitted.connect(_on_prompts_submitted)


func _on_prompts_submitted(prompt_a: String, prompt_b: String) -> void:
	# Store prompts in MSM config
	MatchStateManager.config["prompt_a"] = prompt_a
	MatchStateManager.config["prompt_b"] = prompt_b

	# Generate maze and initialize all systems BEFORE start_countdown(),
	# because MSM.start_countdown() requires current_maze to be finalized.
	var success := _initialize_match_systems()
	if not success:
		MatchStateManager.setup_failed.emit("Maze generation failed")
		return

	# Now transition to COUNTDOWN (precondition: current_maze finalized)
	MatchStateManager.start_countdown()


## Generate maze and initialize all game systems.
## Must be called before start_countdown() since MSM requires a finalized maze.
## Returns true on success, false on failure.
func _initialize_match_systems() -> bool:
	var game_cfg := ConfigLoader.load_json("res://assets/data/game_config.json")

	# Generate maze
	_maze_gen = MazeGenerator.new()
	add_child(_maze_gen)

	var maze_cfg: Dictionary = game_cfg.get("maze", {})
	var w: int = ConfigLoader.get_or_default(maze_cfg, "width", 15)
	var h: int = ConfigLoader.get_or_default(maze_cfg, "height", 15)
	_maze = _maze_gen.generate(w, h)

	if _maze == null:
		push_error("Match: Maze generation failed!")
		return false

	MatchStateManager.current_maze = _maze

	# Initialize FogOfWar
	_fog = FogOfWar.new()
	add_child(_fog)
	_fog.initialize(_maze, [0, 1])

	# Initialize GridMovement
	_grid_movement = GridMovement.new()
	_grid_movement.maze = _maze
	_grid_movement.fog = _fog
	add_child(_grid_movement)
	_grid_movement.initialize()

	# Initialize KeyCollection (Autoload)
	KeyCollection.initialize(_maze)

	# Initialize WinCondition (scene-local)
	_win_condition = WinConditionClass.new()
	add_child(_win_condition)
	_win_condition.initialize(_maze)

	# Wire KeyCollection -> WinCondition
	KeyCollection.chest_unlocked.connect(_win_condition._on_chest_unlocked)

	# Wire GridMovement -> KeyCollection
	_grid_movement.mover_moved.connect(KeyCollection._on_mover_moved)

	# Wire GridMovement -> WinCondition
	_grid_movement.mover_moved.connect(_win_condition._on_mover_moved)

	# Initialize Renderer
	_renderer = MatchRendererClass.new()
	sub_viewport.add_child(_renderer)
	_renderer.initialize(_maze)

	# Wire GridMovement -> Renderer (animations)
	_grid_movement.mover_moved.connect(func(id: int, old_p: Vector2i, new_p: Vector2i):
		var tick_interval: float = ConfigLoader.get_or_default(
			game_cfg.get("match", {}), "tick_interval", 0.5)
		_renderer.animate_move(id, old_p, new_p, tick_interval * _renderer._move_anim_ratio)
	)
	_grid_movement.mover_blocked.connect(func(id: int, pos: Vector2i, dir: int):
		_renderer.animate_bump(id, pos, dir)
	)

	# Wire KeyCollection -> Renderer (key activation)
	KeyCollection.key_activated.connect(func(key_type: int):
		_renderer.show_key(key_type)
	)

	# Wire WinCondition -> Renderer (chest activation)
	_win_condition.chest_activated.connect(func():
		_renderer.show_chest()
	)

	# Initialize HUD (but don't show yet)
	_hud = MatchHUDClass.new()
	add_child(_hud)
	_hud._initialize_state()

	# Initialize LLMAgentManager (Autoload)
	LLMAgentManager.maze = _maze
	LLMAgentManager.movement = _grid_movement
	LLMAgentManager.fog = _fog
	LLMAgentManager.keys = KeyCollection
	LLMAgentManager.win_condition = _win_condition
	LLMAgentManager.initialize({
		"prompt_a": MatchStateManager.config.get("prompt_a", ""),
		"prompt_b": MatchStateManager.config.get("prompt_b", ""),
	})

	# Wire GridMovement -> LLMAgentManager
	_grid_movement.mover_moved.connect(LLMAgentManager._on_mover_moved)
	_grid_movement.mover_blocked.connect(LLMAgentManager._on_mover_blocked)

	return true


# --- State Machine Handlers ---

func _on_state_changed(old_state: int, new_state: int) -> void:
	match new_state:
		Enums.MatchState.COUNTDOWN:
			_on_enter_countdown()
		Enums.MatchState.PLAYING:
			_on_enter_playing()
		Enums.MatchState.FINISHED:
			_on_enter_finished()


func _on_enter_countdown() -> void:
	# Systems already initialized in _initialize_match_systems().
	# COUNTDOWN phase only handles UI: clear prompt input, show "Ready!" labels.
	_clear_side_panels()

	var countdown_label := Label.new()
	countdown_label.text = "Ready!"
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(countdown_label)

	var countdown_label_r := Label.new()
	countdown_label_r.text = "Ready!"
	countdown_label_r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label_r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label_r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(countdown_label_r)


func _on_enter_playing() -> void:
	# Clear countdown displays
	_clear_side_panels()

	# Show HUD
	if _hud != null:
		_hud.set_playing(true)
		_hud.build_hud(left_panel, center_panel, right_panel)

		# Wire KeyCollection -> HUD
		KeyCollection.key_collected.connect(_hud.on_key_collected)

		# Wire WinCondition -> HUD (toast)
		_win_condition.chest_activated.connect(func():
			_hud.show_toast("Chest appeared!")
		)

	# Activate systems
	KeyCollection.set_active(true)
	_win_condition.set_active(true)
	LLMAgentManager.set_active(true)


func _on_enter_finished() -> void:
	# Deactivate systems
	KeyCollection.set_active(false)
	if _win_condition != null:
		_win_condition.set_active(false)
	LLMAgentManager.set_active(false)
	if _hud != null:
		_hud.set_playing(false)

	# Resolve win condition
	if _win_condition != null:
		var result := _win_condition.resolve_pending()
		match result["type"]:
			"win":
				MatchStateManager.finish_match(
					Enums.MatchResult.PLAYER_A_WIN if result["winner_id"] == 0 else Enums.MatchResult.PLAYER_B_WIN,
					result["winner_id"]
				)
			"draw":
				MatchStateManager.finish_match(Enums.MatchResult.DRAW, -1)

	# Switch to Result scene
	SceneManagerGlobal.go_to("result")


# --- Tick Processing ---

func _on_tick(tick_count: int) -> void:
	if MatchStateManager.current_state != Enums.MatchState.PLAYING:
		return

	# 1. LLM agents decide directions
	LLMAgentManager.on_tick(tick_count)

	# 2. Grid movement executes
	_grid_movement.on_tick(tick_count)

	# 3. Update fog of war for moved agents
	for i in range(2):
		_fog.update_vision(i, _grid_movement.get_position(i))

	# 4. Win condition deferred resolution
	call_deferred("_resolve_win_condition")


func _resolve_win_condition() -> void:
	if _win_condition == null:
		return
	if MatchStateManager.current_state != Enums.MatchState.PLAYING:
		return

	var result := _win_condition.resolve_pending()
	match result["type"]:
		"win":
			var match_result: int
			if result["winner_id"] == 0:
				match_result = Enums.MatchResult.PLAYER_A_WIN
			else:
				match_result = Enums.MatchResult.PLAYER_B_WIN
			MatchStateManager.finish_match(match_result, result["winner_id"])
		"draw":
			MatchStateManager.finish_match(Enums.MatchResult.DRAW, -1)


# --- Helpers ---

func _clear_side_panels() -> void:
	for child in left_panel.get_children():
		child.queue_free()
	for child in right_panel.get_children():
		child.queue_free()


## Handle initialization failure — reset to SETUP and show error to user.
func _on_setup_failed(reason: String) -> void:
	push_warning("Match: Setup failed — %s. Returning to prompt input." % reason)
	_clear_side_panels()
	_setup_prompt_input()
```

- [ ] **Step 2: Commit**

```bash
git add scenes/match/match.gd
git commit -m "feat: Match scene orchestration with full signal wiring and lifecycle"
```

---

### Task 7: Integration - Run All Tests

**Files:** None (verification only)

- [ ] **Step 1: Run all Presentation Layer tests**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_match_renderer.gd,res://tests/unit/test_prompt_input.gd,res://tests/unit/test_match_hud.gd,res://tests/unit/test_result_screen.gd -gexit`

Expected: All tests PASS (~59 tests across 4 test files)

- [ ] **Step 2: Run all project tests**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/unit/ -gexit`

Expected: All tests PASS (~190+ tests across Foundation + Core + Feature + Presentation)

- [ ] **Step 3: Fix any integration issues**

If any failures, fix and commit:
```bash
git add -A
git commit -m "fix: resolve Presentation Layer integration issues"
```

---

## Verification Checklist

After completing all tasks, verify:

- [ ] **MatchRenderer** passes all acceptance criteria from `design/gdd/match-renderer.md`:
  - Maze grid renders with walls and floors using `_draw()`
  - Agent sprites at spawn positions with correct colors (A=blue, B=red)
  - Brass key visible initially; Jade, Crystal, Chest hidden
  - `grid_to_pixel()` converts (x,y) to centered pixel coordinates
  - `animate_move()` tweens agent sprite to new position
  - `animate_bump()` plays bump-and-return animation
  - `show_key()` fades in a key sprite with scale animation
  - `show_chest()` fades in chest sprite
  - `on_key_collected()` dims or hides key sprite
  - `cleanup()` removes all child nodes and clears references
  - All config from `ui_config.json` (cell_size, colors, anim durations)
- [ ] **PromptInput** passes all acceptance criteria from `design/gdd/prompt-input.md`:
  - Initial state: PLAYER_A_INPUT
  - `submit_prompt_a()` advances to PLAYER_B_INPUT and stores prompt
  - `submit_prompt_b()` advances to COMPLETED and stores prompt
  - `prompts_submitted` signal emitted on completion with both prompts
  - Empty prompts allowed
  - `submit_prompt_b()` before `submit_prompt_a()` ignored
  - `reset_input()` clears all state back to PLAYER_A_INPUT
  - UI builds dynamically with TextEdit + Ready button
  - Config from `ui_config.json` (placeholder_text, min_lines, show_char_count)
- [ ] **MatchHUD** passes all acceptance criteria from `design/gdd/match-hud.md`:
  - 6 key slots (3 per agent) start gray/locked
  - `on_key_collected()` updates correct slot for correct agent
  - Agent independence: A's pickup doesn't affect B's slots
  - `format_time()` produces "MM:SS | Tick NNN" format
  - Toast shows text and auto-fades after duration
  - New toast overwrites previous toast
  - `set_playing(false)` prevents key collection updates
  - `_initialize_state()` resets all slots, toast, playing state
  - All config from `ui_config.json` (toast_duration, pulse, font sizes)
- [ ] **ResultScreen** passes all acceptance criteria from `design/gdd/result-screen.md`:
  - `get_result_title()`: correct titles for WIN_A, WIN_B, DRAW
  - `get_result_color()`: correct colors (blue, red, gray)
  - `get_agent_status()`: "Winner" / "Defeated" / "Draw" per agent
  - `calculate_idle_rate()`: correct percentage, handles tick_count=0
  - `format_elapsed_time()`: "M:SS" format
  - `get_keys_string()`: "0/3" to "3/3" from AgentKeyState
  - `get_prompt_display()`: "(empty)" for blank prompts
  - 3-column layout with configurable panel_ratio
  - Rematch button calls `MatchStateManager.reset()` + `SceneManagerGlobal.go_to("match")`
  - Quit button calls `get_tree().quit()`
  - Reads from Autoloads (MSM, LLMAgentManager, KeyCollection) with null checks
  - All config from `ui_config.json` (font sizes, colors, panel ratio)
- [ ] **Match Scene Orchestration** handles full lifecycle:
  - SETUP: PromptInput displayed, prompts collected
  - COUNTDOWN: Maze generated, all systems initialized, signals wired
  - PLAYING: HUD displayed, systems active, tick processing works
  - FINISHED: Systems deactivated, win condition resolved, scene switches to Result
  - Tick ordering: LLM decide → GridMovement execute → FoW update → WinCondition resolve (deferred)
  - Signal chain: GridMovement → KeyCollection → WinCondition → MatchStateManager
  - Signal chain: GridMovement → Renderer (animations)
  - Signal chain: KeyCollection → HUD (slot updates)
  - Signal chain: WinCondition → HUD (toast) + Renderer (chest)
- [ ] All config values from JSON, no hardcoded gameplay values
- [ ] ~190+ tests all passing across Foundation + Core + Feature + Presentation

