## Unit tests for GridMovement.
extends GutTest

const MazeData := preload("res://src/core/maze_data.gd")
const FogOfWar := preload("res://src/core/fog_of_war.gd")
const GridMovement := preload("res://src/core/grid_movement.gd")


## Helper: create a FogOfWar node.
func _make_fog() -> Node:
	var fog := FogOfWar.new()
	add_child_autoqfree(fog)
	return fog


## Helper: create a finalized 5x5 maze with a snake path and all markers.
func _make_test_maze() -> RefCounted:
	var maze := MazeData.new(5, 5)
	# Open a snake path to ensure full connectivity:
	# Row 0: (0,0)-(1,0)-(2,0)-(3,0)-(4,0) then down at (4,0)
	# Row 1: (4,1)-(3,1)-(2,1)-(1,1)-(0,1) then down at (0,1)
	# Row 2: (0,2)-(1,2)-(2,2)-(3,2)-(4,2) then down at (4,2)
	# Row 3: (4,3)-(3,3)-(2,3)-(1,3)-(0,3) then down at (0,3)
	# Row 4: (0,4)-(1,4)-(2,4)-(3,4)-(4,4)
	for y in range(5):
		for x in range(4):
			maze.set_wall(x, y, Enums.Direction.EAST, false)
		if y < 4:
			if y % 2 == 0:
				maze.set_wall(4, y, Enums.Direction.SOUTH, false)
			else:
				maze.set_wall(0, y, Enums.Direction.SOUTH, false)
	# Place markers
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(4, 4, Enums.MarkerType.SPAWN_B)
	maze.place_marker(2, 0, Enums.MarkerType.KEY_BRASS)
	maze.place_marker(3, 1, Enums.MarkerType.KEY_JADE)
	maze.place_marker(1, 3, Enums.MarkerType.KEY_CRYSTAL)
	maze.place_marker(2, 2, Enums.MarkerType.CHEST)
	maze.finalize()
	return maze


## Helper: create GridMovement node with maze and fog injected.
func _make_gm() -> Node:
	var maze := _make_test_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0, 1])
	var gm: Node = GridMovement.new()
	gm.maze = maze
	gm.fog = fog
	add_child_autoqfree(gm)
	return gm


func test_initialize_sets_mover_positions_from_spawns() -> void:
	var gm := _make_gm()
	gm.initialize()
	assert_eq(gm.get_position_of(0), Vector2i(0, 0), "Mover 0 at SPAWN_A")
	assert_eq(gm.get_position_of(1), Vector2i(4, 4), "Mover 1 at SPAWN_B")


func test_initialize_records_spawn_in_visited() -> void:
	var gm := _make_gm()
	gm.initialize()
	assert_true(gm.has_visited(0, Vector2i(0, 0)), "Mover 0 should have visited spawn")
	assert_true(gm.has_visited(1, Vector2i(4, 4)), "Mover 1 should have visited spawn")


func test_initialize_visited_cells_contains_spawn() -> void:
	var gm := _make_gm()
	gm.initialize()
	var visited := gm.get_visited_cells(0)
	assert_eq(visited.size(), 1)
	assert_has(visited, Vector2i(0, 0))


func test_initialize_stats_are_zero() -> void:
	var gm := _make_gm()
	gm.initialize()
	assert_eq(gm.get_total_moves(0), 0)
	assert_eq(gm.get_blocked_count(0), 0)
	assert_eq(gm.get_total_moves(1), 0)
	assert_eq(gm.get_blocked_count(1), 0)


func test_initialize_triggers_fog_initial_vision() -> void:
	var maze := _make_test_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0, 1])
	var gm: Node = GridMovement.new()
	gm.maze = maze
	gm.fog = fog
	add_child_autoqfree(gm)
	gm.initialize()
	# After initialize, fog should have vision around spawn
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.VISIBLE,
		"SPAWN_A should be VISIBLE after initialize")
	assert_eq(fog.get_cell_visibility(1, 4, 4), Enums.CellVisibility.VISIBLE,
		"SPAWN_B should be VISIBLE after initialize")


func test_reset_clears_all_state() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.reset()
	assert_eq(gm.get_position_of(0), Vector2i(-1, -1), "After reset position should be (-1,-1)")
	assert_eq(gm.get_visited_cells(0).size(), 0)
	assert_eq(gm.get_total_moves(0), 0)
	assert_eq(gm.get_blocked_count(0), 0)


func test_invalid_mover_id_queries() -> void:
	var gm := _make_gm()
	gm.initialize()
	assert_eq(gm.get_position_of(99), Vector2i(-1, -1))
	assert_eq(gm.get_visited_cells(99).size(), 0)
	assert_false(gm.has_visited(99, Vector2i(0, 0)))
	assert_eq(gm.get_total_moves(99), 0)
	assert_eq(gm.get_blocked_count(99), 0)


func test_set_direction_and_move_east() -> void:
	var gm := _make_gm()
	gm.initialize()
	watch_signals(gm)
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.on_tick(1)
	assert_eq(gm.get_position_of(0), Vector2i(1, 0), "Should move east to (1,0)")
	assert_signal_emitted(gm, "mover_moved")
	var params := get_signal_parameters(gm, "mover_moved", 0)
	assert_eq(params[0], 0)  # mover_id
	assert_eq(params[1], Vector2i(0, 0))  # old_pos
	assert_eq(params[2], Vector2i(1, 0))  # new_pos


func test_blocked_movement_stays_in_place() -> void:
	var gm := _make_gm()
	gm.initialize()
	watch_signals(gm)
	# Try to move north from (0,0) — always blocked (boundary wall)
	gm.set_direction(0, Enums.MoveDirection.NORTH)
	gm.on_tick(1)
	assert_eq(gm.get_position_of(0), Vector2i(0, 0), "Should stay at (0,0)")
	assert_signal_emitted(gm, "mover_blocked")
	var params := get_signal_parameters(gm, "mover_blocked", 0)
	assert_eq(params[0], 0)  # mover_id
	assert_eq(params[1], Vector2i(0, 0))  # pos


func test_blocked_increments_blocked_count() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.set_direction(0, Enums.MoveDirection.NORTH)
	gm.on_tick(1)
	assert_eq(gm.get_blocked_count(0), 1)
	gm.set_direction(0, Enums.MoveDirection.NORTH)
	gm.on_tick(2)
	assert_eq(gm.get_blocked_count(0), 2)


func test_no_direction_emits_stayed() -> void:
	var gm := _make_gm()
	gm.initialize()
	watch_signals(gm)
	# No set_direction — pending is NONE
	gm.on_tick(1)
	assert_signal_emitted(gm, "mover_stayed")
	var params := get_signal_parameters(gm, "mover_stayed", 0)
	assert_eq(params[0], 0)  # mover_id
	assert_eq(params[1], Vector2i(0, 0))  # pos


func test_pending_direction_cleared_after_tick() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.on_tick(1)
	# Second tick without set_direction should stay
	watch_signals(gm)
	gm.on_tick(2)
	assert_signal_emitted(gm, "mover_stayed")


func test_total_moves_increments_on_success() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.on_tick(1)
	assert_eq(gm.get_total_moves(0), 1)
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.on_tick(2)
	assert_eq(gm.get_total_moves(0), 2)


func test_visited_cells_no_duplicates() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.on_tick(1)
	gm.set_direction(0, Enums.MoveDirection.WEST)
	gm.on_tick(2)
	# Back at (0,0) — should not duplicate in visited_cells
	var visited := gm.get_visited_cells(0)
	var unique: Dictionary = {}
	for v in visited:
		assert_false(unique.has(v), "Duplicate visited cell: (%d,%d)" % [v.x, v.y])
		unique[v] = true


func test_last_set_direction_wins() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.set_direction(0, Enums.MoveDirection.NORTH)  # Will be overwritten
	gm.set_direction(0, Enums.MoveDirection.EAST)   # Last write wins
	gm.on_tick(1)
	assert_eq(gm.get_position_of(0), Vector2i(1, 0), "Last set_direction should win")


func test_both_movers_process_in_same_tick() -> void:
	var gm := _make_gm()
	gm.initialize()
	watch_signals(gm)
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.set_direction(1, Enums.MoveDirection.WEST)
	gm.on_tick(1)
	# Mover 0 should move east from (0,0) to (1,0)
	assert_eq(gm.get_position_of(0), Vector2i(1, 0), "Mover 0 should move east")
	# Mover 1 at (4,4), west should be open in snake maze
	assert_eq(gm.get_position_of(1), Vector2i(3, 4), "Mover 1 should move west")


func test_invalid_mover_id_set_direction_no_crash() -> void:
	var gm := _make_gm()
	gm.initialize()
	# Should not crash
	gm.set_direction(99, Enums.MoveDirection.EAST)
	gm.on_tick(1)
	# Movers should be unaffected (stayed)
	assert_eq(gm.get_position_of(0), Vector2i(0, 0))


func test_direction_offsets_correct() -> void:
	assert_eq(GridMovement.DIRECTION_OFFSETS[Enums.MoveDirection.NORTH], Vector2i(0, -1))
	assert_eq(GridMovement.DIRECTION_OFFSETS[Enums.MoveDirection.EAST], Vector2i(1, 0))
	assert_eq(GridMovement.DIRECTION_OFFSETS[Enums.MoveDirection.SOUTH], Vector2i(0, 1))
	assert_eq(GridMovement.DIRECTION_OFFSETS[Enums.MoveDirection.WEST], Vector2i(-1, 0))


func test_has_visited_returns_true_for_moved_cells() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.on_tick(1)
	assert_true(gm.has_visited(0, Vector2i(0, 0)), "Should have visited start")
	assert_true(gm.has_visited(0, Vector2i(1, 0)), "Should have visited (1,0)")
	assert_false(gm.has_visited(0, Vector2i(2, 0)), "Should not have visited (2,0)")
