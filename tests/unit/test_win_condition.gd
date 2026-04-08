## Unit tests for WinConditionManager.
extends GutTest

const WinConditionClass := preload("res://src/gameplay/win_condition.gd")
const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")

var wc: Node
var maze: RefCounted


func before_each() -> void:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	maze = gen.generate(5, 5)
	assert_not_null(maze, "Test maze should generate")

	wc = WinConditionClass.new()
	add_child_autoqfree(wc)
	wc.initialize(maze)


func test_initial_chest_inactive() -> void:
	assert_false(wc.is_chest_active())


func test_initial_agents_ineligible() -> void:
	assert_false(wc.is_agent_eligible(0))
	assert_false(wc.is_agent_eligible(1))


func test_chest_position_cached() -> void:
	var expected := maze.get_marker_position(Enums.MarkerType.CHEST)
	assert_eq(wc.get_chest_position(), expected)


func test_chest_unlocked_activates_chest() -> void:
	watch_signals(wc)
	wc._on_chest_unlocked(0)
	assert_true(wc.is_chest_active())
	assert_signal_emitted(wc, "chest_activated")


func test_chest_unlocked_marks_agent_eligible() -> void:
	wc._on_chest_unlocked(0)
	assert_true(wc.is_agent_eligible(0))
	assert_false(wc.is_agent_eligible(1))


func test_second_chest_unlocked_no_double_activate() -> void:
	watch_signals(wc)
	wc._on_chest_unlocked(0)
	wc._on_chest_unlocked(1)
	assert_eq(get_signal_emit_count(wc, "chest_activated"), 1)
	assert_true(wc.is_agent_eligible(1))


func test_eligible_agent_at_chest_triggers_pending() -> void:
	wc._on_chest_unlocked(0)
	wc.set_active(true)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	assert_eq(wc._pending_openers.size(), 1)
	assert_has(wc._pending_openers, 0)


func test_ineligible_agent_at_chest_no_trigger() -> void:
	wc._on_chest_unlocked(0)  # Only agent 0 is eligible
	wc.set_active(true)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(1, Vector2i(-1, -1), chest_pos)
	assert_eq(wc._pending_openers.size(), 0)


func test_inactive_chest_no_trigger() -> void:
	# Don't activate chest
	wc.set_active(true)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	assert_eq(wc._pending_openers.size(), 0)


func test_resolve_single_winner() -> void:
	wc._on_chest_unlocked(0)
	wc.set_active(true)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	watch_signals(wc)
	var result := wc.resolve_pending()
	assert_eq(result["type"], "win")
	assert_eq(result["winner_id"], 0)
	assert_signal_emitted(wc, "chest_opened")


func test_resolve_draw() -> void:
	wc._on_chest_unlocked(0)
	wc._on_chest_unlocked(1)
	wc.set_active(true)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	wc._on_mover_moved(1, Vector2i(-1, -1), chest_pos)
	var result := wc.resolve_pending()
	assert_eq(result["type"], "draw")


func test_resolve_empty_no_action() -> void:
	var result := wc.resolve_pending()
	assert_eq(result["type"], "none")


func test_pending_cleared_after_resolve() -> void:
	wc._on_chest_unlocked(0)
	wc.set_active(true)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	wc.resolve_pending()
	assert_eq(wc._pending_openers.size(), 0)


func test_not_active_ignores_mover_moved() -> void:
	wc._on_chest_unlocked(0)
	# set_active not called (default false)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	assert_eq(wc._pending_openers.size(), 0)


func test_reset_clears_all() -> void:
	wc._on_chest_unlocked(0)
	wc.set_active(true)
	wc.reset()
	assert_false(wc.is_chest_active())
	assert_false(wc.is_agent_eligible(0))
	assert_eq(wc._pending_openers.size(), 0)


func test_initialize_resets_state() -> void:
	wc._on_chest_unlocked(0)
	wc.initialize(maze)
	assert_false(wc.is_chest_active())
	assert_false(wc.is_agent_eligible(0))
