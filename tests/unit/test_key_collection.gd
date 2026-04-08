## Unit tests for KeyCollection.
extends GutTest

const KeyCollectionClass := preload("res://src/gameplay/key_collection.gd")
const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")

var kc: Node
var maze: RefCounted


func before_each() -> void:
	# Generate a valid maze
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	maze = gen.generate(5, 5)
	assert_not_null(maze, "Test maze should generate")

	kc = KeyCollectionClass.new()
	add_child_autoqfree(kc)
	kc.initialize(maze)
	kc.set_active(true)


func test_initial_global_phase_is_brass_active() -> void:
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.BRASS_ACTIVE)


func test_initial_agent_progress_is_need_brass() -> void:
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_BRASS)
	assert_eq(kc.get_agent_progress(1), Enums.AgentKeyState.NEED_BRASS)


func test_brass_is_active_initially() -> void:
	assert_true(kc.is_key_active(Enums.MarkerType.KEY_BRASS))
	assert_false(kc.is_key_active(Enums.MarkerType.KEY_JADE))
	assert_false(kc.is_key_active(Enums.MarkerType.KEY_CRYSTAL))


func test_pickup_brass_advances_agent_progress() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_JADE)
	assert_signal_emitted(kc, "key_collected")


func test_pickup_brass_activates_jade() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	assert_true(kc.is_key_active(Enums.MarkerType.KEY_JADE))
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.JADE_ACTIVE)
	assert_signal_emitted(kc, "key_activated")


func test_agent_independence() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	# Agent 0 advanced, Agent 1 still needs brass
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_JADE)
	assert_eq(kc.get_agent_progress(1), Enums.AgentKeyState.NEED_BRASS)


func test_agent_cannot_skip_keys() -> void:
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	# Brass picked up by agent 0 to activate Jade globally
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	# Agent 1 goes to Jade without picking Brass first
	watch_signals(kc)
	kc._on_mover_moved(1, Vector2i(-1, -1), jade_pos)
	assert_signal_not_emitted(kc, "key_collected")
	assert_eq(kc.get_agent_progress(1), Enums.AgentKeyState.NEED_BRASS)


func test_checkpoint_semantics_both_agents_pickup() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	# Agent 1 can also pick up brass (checkpoint, not consumed)
	watch_signals(kc)
	kc._on_mover_moved(1, Vector2i(-1, -1), brass_pos)
	assert_eq(kc.get_agent_progress(1), Enums.AgentKeyState.NEED_JADE)
	assert_signal_emitted(kc, "key_collected")


func test_key_activated_only_on_first_pickup() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	var activated_count_1 := get_signal_emit_count(kc, "key_activated")
	kc._on_mover_moved(1, Vector2i(-1, -1), brass_pos)
	var activated_count_2 := get_signal_emit_count(kc, "key_activated")
	# key_activated should only fire once (first pickup triggers Jade activation)
	assert_eq(activated_count_1, 1)
	assert_eq(activated_count_2, 1, "Second brass pickup should NOT emit key_activated again")


func test_activation_is_cumulative() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	# Brass should still be active after Jade activates
	assert_true(kc.is_key_active(Enums.MarkerType.KEY_BRASS))
	assert_true(kc.is_key_active(Enums.MarkerType.KEY_JADE))


func test_full_pipeline_agent_collects_all_three() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos := maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)

	watch_signals(kc)

	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_JADE)
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.JADE_ACTIVE)

	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_CRYSTAL)
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.CRYSTAL_ACTIVE)

	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.KEYS_COMPLETE)
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.ALL_COLLECTED)

	assert_eq(get_signal_emit_count(kc, "key_collected"), 3)
	assert_eq(get_signal_emit_count(kc, "key_activated"), 2)
	assert_signal_emitted(kc, "chest_unlocked")


func test_chest_unlocked_emitted_per_agent() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos := maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)

	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)

	kc._on_mover_moved(1, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(1, Vector2i(-1, -1), jade_pos)
	watch_signals(kc)
	kc._on_mover_moved(1, Vector2i(-1, -1), crystal_pos)

	assert_signal_emitted(kc, "chest_unlocked")
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.ALL_COLLECTED)


func test_same_tick_both_pickup_brass() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(1, Vector2i(-1, -1), brass_pos)
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_JADE)
	assert_eq(kc.get_agent_progress(1), Enums.AgentKeyState.NEED_JADE)
	assert_eq(get_signal_emit_count(kc, "key_activated"), 1)
	assert_eq(get_signal_emit_count(kc, "key_collected"), 2)


func test_moving_to_non_key_cell_no_pickup() -> void:
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), Vector2i(0, 0))
	assert_signal_not_emitted(kc, "key_collected")


func test_agent_on_inactive_key_no_pickup() -> void:
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	assert_signal_not_emitted(kc, "key_collected")


func test_already_collected_key_no_repeat() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	assert_signal_not_emitted(kc, "key_collected")


func test_get_keys_collected_count() -> void:
	assert_eq(kc.get_keys_collected_count(0), 0)
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	assert_eq(kc.get_keys_collected_count(0), 1)


func test_get_next_key() -> void:
	assert_eq(kc.get_next_key(0), Enums.MarkerType.KEY_BRASS)
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	assert_eq(kc.get_next_key(0), Enums.MarkerType.KEY_JADE)


func test_initialize_resets_after_complete_game() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos := maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)

	kc.initialize(maze)
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.BRASS_ACTIVE)
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_BRASS)
	assert_eq(kc.get_agent_progress(1), Enums.AgentKeyState.NEED_BRASS)
	assert_true(kc.is_key_active(Enums.MarkerType.KEY_BRASS))
	assert_false(kc.is_key_active(Enums.MarkerType.KEY_JADE))


func test_invalid_agent_id_returns_default() -> void:
	assert_eq(kc.get_agent_progress(99), Enums.AgentKeyState.NEED_BRASS)
	assert_eq(kc.get_keys_collected_count(99), 0)
	assert_eq(kc.get_next_key(99), Enums.MarkerType.KEY_BRASS)


func test_missing_key_marker_no_crash() -> void:
	var small_maze := MazeData.new(3, 3)
	small_maze.set_wall(0, 0, Enums.Direction.EAST, false)
	small_maze.set_wall(1, 0, Enums.Direction.EAST, false)
	small_maze.set_wall(2, 0, Enums.Direction.SOUTH, false)
	small_maze.set_wall(2, 1, Enums.Direction.SOUTH, false)
	small_maze.set_wall(2, 2, Enums.Direction.WEST, false)
	small_maze.set_wall(1, 2, Enums.Direction.WEST, false)
	small_maze.set_wall(0, 2, Enums.Direction.NORTH, false)
	small_maze.set_wall(1, 1, Enums.Direction.SOUTH, false)
	small_maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	small_maze.place_marker(2, 2, Enums.MarkerType.SPAWN_B)
	small_maze.place_marker(1, 0, Enums.MarkerType.KEY_BRASS)
	small_maze.place_marker(2, 1, Enums.MarkerType.KEY_CRYSTAL)
	small_maze.place_marker(1, 2, Enums.MarkerType.CHEST)
	var kc2 := KeyCollectionClass.new()
	add_child_autoqfree(kc2)
	kc2.initialize(small_maze)
	assert_eq(kc2._key_positions.get(Enums.MarkerType.KEY_JADE, Vector2i(-1, -1)), Vector2i(-1, -1))
