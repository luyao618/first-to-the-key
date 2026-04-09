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

## Dev mode: skip prompt input and auto-start with default prompts.
## Change to false for normal gameplay with prompt input.
const DEV_SKIP_PROMPTS: bool = true


func _ready() -> void:
	_load_config()
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)

	# Connect to MatchStateManager
	MatchStateManager.state_changed.connect(_on_state_changed)
	MatchStateManager.tick.connect(_on_tick)
	MatchStateManager.setup_failed.connect(_on_setup_failed)

	if DEV_SKIP_PROMPTS:
		# Skip prompt input, use default prompts, go straight to match
		call_deferred("_on_prompts_submitted", "Explore the maze efficiently", "Find keys quickly")
	else:
		# Normal flow: show prompt input
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
	_maze_gen.generation_failed.connect(func(retries: int, reason: String) -> void:
		push_error("Match: MazeGenerator failed after %d retries: %s" % [retries, reason])
	)
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
	_grid_movement.mover_moved.connect(func(id: int, old_p: Vector2i, new_p: Vector2i) -> void:
		var tick_interval: float = ConfigLoader.get_or_default(
			game_cfg.get("match", {}), "tick_interval", 0.5)
		_renderer.animate_move(id, old_p, new_p, tick_interval * _renderer._move_anim_ratio)
	)
	_grid_movement.mover_blocked.connect(func(id: int, pos: Vector2i, dir: int) -> void:
		_renderer.animate_bump(id, pos, dir)
	)

	# Wire KeyCollection -> Renderer (key activation)
	KeyCollection.key_activated.connect(func(key_type: int) -> void:
		_renderer.show_key(key_type)
	)

	# Wire WinCondition -> Renderer (chest activation)
	_win_condition.chest_activated.connect(func() -> void:
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

func _on_state_changed(_old_state: int, new_state: int) -> void:
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
		_win_condition.chest_activated.connect(func() -> void:
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

	# Result and winner_id are already set by finish_match() which triggered
	# this state change. No need to resolve_pending() again.

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
		_fog.update_vision(i, _grid_movement.get_position_of(i))

	# 4. Win condition deferred resolution
	call_deferred("_resolve_win_condition")


func _resolve_win_condition() -> void:
	if _win_condition == null:
		return
	if MatchStateManager.current_state != Enums.MatchState.PLAYING:
		return

	var win_result: Dictionary = _win_condition.resolve_pending()
	match win_result["type"]:
		"win":
			var match_result: int
			if win_result["winner_id"] == 0:
				match_result = Enums.MatchResult.PLAYER_A_WIN
			else:
				match_result = Enums.MatchResult.PLAYER_B_WIN
			MatchStateManager.finish_match(match_result, win_result["winner_id"])
		"draw":
			MatchStateManager.finish_match(Enums.MatchResult.DRAW, -1)


# --- Helpers ---

func _clear_side_panels() -> void:
	for child in left_panel.get_children():
		child.queue_free()
	for child in right_panel.get_children():
		child.queue_free()


## Handle initialization failure - reset to SETUP and show error to user.
func _on_setup_failed(reason: String) -> void:
	push_warning("Match: Setup failed - %s. Returning to prompt input." % reason)
	_clear_side_panels()
	_setup_prompt_input()
