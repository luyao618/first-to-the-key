## Integration tests for Feature Layer systems working together.
extends GutTest

const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")
const FogOfWarClass := preload("res://src/core/fog_of_war.gd")
const GridMovementClass := preload("res://src/core/grid_movement.gd")
const KeyCollectionClass := preload("res://src/gameplay/key_collection.gd")
const WinConditionClass := preload("res://src/gameplay/win_condition.gd")

var maze: RefCounted
var fog: Node
var gm: Node
var kc: Node
var wc: Node


func before_each() -> void:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	gen._config_loaded = true
	maze = gen.generate(5, 5)
	assert_not_null(maze)

	fog = FogOfWarClass.new()
	add_child_autoqfree(fog)
	fog.initialize(maze, [0, 1])

	gm = GridMovementClass.new()
	gm.maze = maze
	gm.fog = fog
	add_child_autoqfree(gm)
	gm.initialize()

	kc = KeyCollectionClass.new()
	add_child_autoqfree(kc)
	kc.initialize(maze)
	kc.set_active(true)

	wc = WinConditionClass.new()
	add_child_autoqfree(wc)
	wc.initialize(maze)

	# Wire signals
	kc.chest_unlocked.connect(wc._on_chest_unlocked)


func test_key_collection_to_win_condition_signal_chain() -> void:
	# Collect all three keys for agent 0
	var brass_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)

	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)

	# Win condition should now have chest active and agent 0 eligible
	assert_true(wc.is_chest_active(), "Chest should be active after all keys collected")
	assert_true(wc.is_agent_eligible(0), "Agent 0 should be eligible")
	assert_false(wc.is_agent_eligible(1), "Agent 1 should not be eligible")


func test_agent_reaches_chest_triggers_win() -> void:
	# Collect all keys
	var brass_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)
	var chest_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.CHEST)

	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)

	# Move agent to chest
	wc.set_active(true)
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)

	# Resolve
	watch_signals(wc)
	var result: Dictionary = wc.resolve_pending()
	assert_eq(result["type"], "win")
	assert_eq(result["winner_id"], 0)
	assert_signal_emitted(wc, "chest_opened")


func test_ineligible_agent_at_chest_no_win() -> void:
	# Agent 0 collects all keys
	var brass_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)
	var chest_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.CHEST)

	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)

	# Agent 1 (no keys) reaches chest
	wc.set_active(true)
	wc._on_mover_moved(1, Vector2i(-1, -1), chest_pos)
	var result: Dictionary = wc.resolve_pending()
	assert_eq(result["type"], "none", "Ineligible agent should not trigger win")


func test_both_agents_complete_same_tick_draw() -> void:
	var brass_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)
	var chest_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.CHEST)

	# Both agents collect all keys
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(1, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(1, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)
	kc._on_mover_moved(1, Vector2i(-1, -1), crystal_pos)

	# Both reach chest same tick
	wc.set_active(true)
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	wc._on_mover_moved(1, Vector2i(-1, -1), chest_pos)
	var result: Dictionary = wc.resolve_pending()
	assert_eq(result["type"], "draw")


func test_reinitialize_full_pipeline() -> void:
	# Complete a game
	var brass_pos: Vector2i = maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)

	# Re-initialize everything (simulates Rematch)
	kc.initialize(maze)
	wc.initialize(maze)

	# All state should be reset
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.BRASS_ACTIVE)
	assert_false(wc.is_chest_active())
	assert_false(wc.is_agent_eligible(0))
