## Unit tests for MatchStateManager.
extends GutTest

var msm: Node


func before_each() -> void:
	# Create a fresh instance (not the autoload singleton)
	msm = load("res://src/core/match_state_manager.gd").new()
	add_child_autoqfree(msm)


func test_initial_state_is_setup() -> void:
	assert_eq(msm.current_state, Enums.MatchState.SETUP)


func test_start_setup_sets_config() -> void:
	var config := {
		"game_mode": Enums.GameMode.AGENT_VS_AGENT,
		"prompt_a": "test prompt a",
		"prompt_b": "",
	}
	msm.start_setup(config)
	assert_eq(msm.current_state, Enums.MatchState.SETUP)
	assert_eq(msm.config["prompt_a"], "test prompt a")


func test_start_countdown_requires_finalized_maze() -> void:
	msm.start_setup({})
	# No maze set - should fail
	assert_false(msm.start_countdown())
	assert_eq(msm.current_state, Enums.MatchState.SETUP)


func test_start_countdown_succeeds_with_maze() -> void:
	msm.start_setup({})
	# Create and finalize a mock maze
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	assert_true(msm.start_countdown())
	assert_eq(msm.current_state, Enums.MatchState.COUNTDOWN)


func test_invalid_transition_setup_to_playing() -> void:
	msm.start_setup({})
	msm.start_playing()
	assert_eq(msm.current_state, Enums.MatchState.SETUP, "Should remain SETUP")


func test_finish_match_only_from_playing() -> void:
	msm.start_setup({})
	msm.finish_match(Enums.MatchResult.PLAYER_A_WIN, 0)
	assert_eq(msm.current_state, Enums.MatchState.SETUP, "Should remain SETUP")


func test_reset_from_any_state() -> void:
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	msm.reset()
	assert_eq(msm.current_state, Enums.MatchState.SETUP)
	assert_null(msm.current_maze)
	assert_eq(msm.tick_count, 0)
	assert_eq(msm.result, Enums.MatchResult.NONE)


func test_state_changed_signal_emitted() -> void:
	watch_signals(msm)
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	assert_signal_emitted(msm, "state_changed")


func test_finish_match_records_result() -> void:
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	msm.start_playing()
	msm.finish_match(Enums.MatchResult.PLAYER_A_WIN, 0)
	assert_eq(msm.current_state, Enums.MatchState.FINISHED)
	assert_eq(msm.result, Enums.MatchResult.PLAYER_A_WIN)
	assert_eq(msm.winner_id, 0)


## Helper to create a minimal finalized maze.
func _make_finalized_maze(MazeDataClass) -> RefCounted:
	var maze = MazeDataClass.new(3, 3)
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	maze.set_wall(1, 0, Enums.Direction.EAST, false)
	maze.set_wall(2, 0, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 1, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 2, Enums.Direction.WEST, false)
	maze.set_wall(1, 2, Enums.Direction.WEST, false)
	maze.set_wall(0, 2, Enums.Direction.NORTH, false)
	maze.set_wall(1, 1, Enums.Direction.SOUTH, false)
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(2, 2, Enums.MarkerType.SPAWN_B)
	maze.place_marker(1, 0, Enums.MarkerType.KEY_BRASS)
	maze.place_marker(2, 0, Enums.MarkerType.KEY_JADE)
	maze.place_marker(2, 1, Enums.MarkerType.KEY_CRYSTAL)
	maze.place_marker(1, 2, Enums.MarkerType.CHEST)
	maze.finalize()
	return maze
