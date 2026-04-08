## Unit tests for FogOfWar and VisionMap.
extends GutTest

const MazeData := preload("res://src/core/maze_data.gd")
const FogOfWar := preload("res://src/core/fog_of_war.gd")


## Helper: create a FogOfWar node and add to scene tree.
func _make_fog() -> Node:
	var fog := FogOfWar.new()
	add_child_autoqfree(fog)
	return fog


## Helper: create a small connected maze for vision tests.
## All internal walls removed (open grid).
func _make_open_maze(w: int = 3, h: int = 3) -> RefCounted:
	var maze := MazeData.new(w, h)
	for y in range(h):
		for x in range(w):
			if x < w - 1:
				maze.set_wall(x, y, Enums.Direction.EAST, false)
			if y < h - 1:
				maze.set_wall(x, y, Enums.Direction.SOUTH, false)
	return maze


func test_initialize_creates_vision_maps_for_all_agents() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0, 1])
	# All cells should be UNKNOWN after initialize (no initial vision)
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.UNKNOWN)
	assert_eq(fog.get_cell_visibility(1, 0, 0), Enums.CellVisibility.UNKNOWN)


func test_initialize_all_cells_unknown() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0, 1])
	for y in range(3):
		for x in range(3):
			assert_eq(fog.get_cell_visibility(0, x, y), Enums.CellVisibility.UNKNOWN,
				"Agent 0 cell (%d,%d) should be UNKNOWN" % [x, y])
			assert_eq(fog.get_cell_visibility(1, x, y), Enums.CellVisibility.UNKNOWN,
				"Agent 1 cell (%d,%d) should be UNKNOWN" % [x, y])


func test_get_visible_cells_empty_before_update() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	assert_eq(fog.get_visible_cells(0).size(), 0)


func test_get_explored_cells_empty_before_update() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	assert_eq(fog.get_explored_cells(0).size(), 0)


func test_invalid_agent_id_returns_unknown() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	assert_eq(fog.get_cell_visibility(999, 0, 0), Enums.CellVisibility.UNKNOWN)


func test_invalid_agent_id_visible_cells_returns_empty() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	assert_eq(fog.get_visible_cells(999).size(), 0)


func test_invalid_agent_id_explored_cells_returns_empty() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	assert_eq(fog.get_explored_cells(999).size(), 0)


func test_out_of_bounds_returns_unknown() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	assert_eq(fog.get_cell_visibility(0, -1, 0), Enums.CellVisibility.UNKNOWN)
	assert_eq(fog.get_cell_visibility(0, 0, -1), Enums.CellVisibility.UNKNOWN)
	assert_eq(fog.get_cell_visibility(0, 99, 0), Enums.CellVisibility.UNKNOWN)


func test_update_vision_marks_cells_visible() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 1  # Override for deterministic test
	fog.update_vision(0, Vector2i(1, 1))
	# Center cell and its passable neighbors should be VISIBLE
	assert_eq(fog.get_cell_visibility(0, 1, 1), Enums.CellVisibility.VISIBLE,
		"Center should be VISIBLE")
	assert_eq(fog.get_cell_visibility(0, 1, 0), Enums.CellVisibility.VISIBLE,
		"(1,0) should be VISIBLE")
	assert_eq(fog.get_cell_visibility(0, 2, 1), Enums.CellVisibility.VISIBLE,
		"(2,1) should be VISIBLE")
	assert_eq(fog.get_cell_visibility(0, 1, 2), Enums.CellVisibility.VISIBLE,
		"(1,2) should be VISIBLE")
	assert_eq(fog.get_cell_visibility(0, 0, 1), Enums.CellVisibility.VISIBLE,
		"(0,1) should be VISIBLE")


func test_update_vision_radius_1_does_not_reach_corners() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 1
	fog.update_vision(0, Vector2i(1, 1))
	# Corners are 2 steps away, should still be UNKNOWN
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.UNKNOWN,
		"(0,0) corner should be UNKNOWN at radius 1")
	assert_eq(fog.get_cell_visibility(0, 2, 2), Enums.CellVisibility.UNKNOWN,
		"(2,2) corner should be UNKNOWN at radius 1")


func test_visible_to_explored_transition() -> void:
	var maze := _make_open_maze(5, 1)
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 1
	# Move to (0,0) — sees (0,0) and (1,0)
	fog.update_vision(0, Vector2i(0, 0))
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.VISIBLE)
	assert_eq(fog.get_cell_visibility(0, 1, 0), Enums.CellVisibility.VISIBLE)
	# Move to (3,0) — old cells become EXPLORED
	fog.update_vision(0, Vector2i(3, 0))
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.EXPLORED,
		"(0,0) should become EXPLORED")
	assert_eq(fog.get_cell_visibility(0, 1, 0), Enums.CellVisibility.EXPLORED,
		"(1,0) should become EXPLORED")
	assert_eq(fog.get_cell_visibility(0, 3, 0), Enums.CellVisibility.VISIBLE,
		"(3,0) should be VISIBLE")


func test_explored_to_visible_transition() -> void:
	var maze := _make_open_maze(5, 1)
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 1
	fog.update_vision(0, Vector2i(0, 0))
	fog.update_vision(0, Vector2i(3, 0))
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.EXPLORED)
	# Move back near (0,0)
	fog.update_vision(0, Vector2i(0, 0))
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.VISIBLE,
		"(0,0) should return to VISIBLE when back in range")


func test_explored_never_becomes_unknown() -> void:
	var maze := _make_open_maze(5, 1)
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 1
	fog.update_vision(0, Vector2i(0, 0))
	fog.update_vision(0, Vector2i(4, 0))
	# (0,0) should be EXPLORED, not UNKNOWN
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.EXPLORED,
		"Once explored, never back to UNKNOWN")


func test_agents_have_independent_vision() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0, 1])
	fog._vision_radius = 1
	fog.update_vision(0, Vector2i(0, 0))
	# Agent 0 sees (0,0), Agent 1 does not
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.VISIBLE)
	assert_eq(fog.get_cell_visibility(1, 0, 0), Enums.CellVisibility.UNKNOWN,
		"Agent 1 should not see Agent 0's vision")


func test_vision_blocked_by_walls() -> void:
	# 3x1 maze, only (0,0)-(1,0) open, (1,0)-(2,0) walled
	var maze := MazeData.new(3, 1)
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	# (1,0)-(2,0) wall stays closed
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 3
	fog.update_vision(0, Vector2i(0, 0))
	# Can see (0,0) and (1,0) but NOT (2,0) — wall blocks BFS
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.VISIBLE)
	assert_eq(fog.get_cell_visibility(0, 1, 0), Enums.CellVisibility.VISIBLE)
	assert_eq(fog.get_cell_visibility(0, 2, 0), Enums.CellVisibility.UNKNOWN,
		"Wall should block BFS path")


func test_vision_radius_zero_sees_only_self() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 0
	fog.update_vision(0, Vector2i(1, 1))
	assert_eq(fog.get_cell_visibility(0, 1, 1), Enums.CellVisibility.VISIBLE)
	assert_eq(fog.get_visible_cells(0).size(), 1)
	# Neighbors should be UNKNOWN
	assert_eq(fog.get_cell_visibility(0, 1, 0), Enums.CellVisibility.UNKNOWN)


func test_get_visible_cells_sorted_row_major() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 10  # See everything in 3x3
	fog.update_vision(0, Vector2i(1, 1))
	var visible := fog.get_visible_cells(0)
	# Should be sorted: (0,0),(1,0),(2,0),(0,1),(1,1),(2,1),(0,2),(1,2),(2,2)
	assert_eq(visible.size(), 9)
	assert_eq(visible[0], Vector2i(0, 0))
	assert_eq(visible[1], Vector2i(1, 0))
	assert_eq(visible[2], Vector2i(2, 0))
	assert_eq(visible[3], Vector2i(0, 1))
	assert_eq(visible[8], Vector2i(2, 2))


func test_get_explored_cells_sorted_row_major() -> void:
	var maze := _make_open_maze(5, 1)
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 1
	fog.update_vision(0, Vector2i(0, 0))  # Sees (0,0), (1,0)
	fog.update_vision(0, Vector2i(4, 0))  # (0,0),(1,0) -> EXPLORED; sees (3,0),(4,0)
	var explored := fog.get_explored_cells(0)
	assert_eq(explored.size(), 2)
	assert_eq(explored[0], Vector2i(0, 0))
	assert_eq(explored[1], Vector2i(1, 0))


func test_update_vision_invalid_agent_ignored() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	# Should not crash, should not create new vision map
	fog.update_vision(999, Vector2i(0, 0))
	assert_eq(fog.get_visible_cells(999).size(), 0)


func test_reinitialize_same_maze_resets_vision() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog.update_vision(0, Vector2i(1, 1))
	assert_gt(fog.get_visible_cells(0).size(), 0, "Should have visible cells")
	# Reinitialize with same maze
	fog.initialize(maze, [0])
	assert_eq(fog.get_visible_cells(0).size(), 0, "Should be reset after reinitialize")
	assert_eq(fog.get_cell_visibility(0, 1, 1), Enums.CellVisibility.UNKNOWN)


func test_reinitialize_new_maze_different_size() -> void:
	var maze_small := _make_open_maze(3, 3)
	var fog := _make_fog()
	fog.initialize(maze_small, [0, 1])
	fog.update_vision(0, Vector2i(0, 0))

	# Reinitialize with larger maze
	var maze_large := _make_open_maze(5, 5)
	fog.initialize(maze_large, [0, 1])
	# Should handle new dimensions
	assert_eq(fog.get_cell_visibility(0, 4, 4), Enums.CellVisibility.UNKNOWN)
	assert_eq(fog.get_visible_cells(0).size(), 0)


func test_reinitialize_different_agent_ids() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0, 1])
	fog.update_vision(0, Vector2i(0, 0))
	# Reinitialize with different agents
	fog.initialize(maze, [2, 3])
	# Old agent 0 should no longer exist
	assert_eq(fog.get_visible_cells(0).size(), 0)
	# New agent 2 should start UNKNOWN
	assert_eq(fog.get_cell_visibility(2, 0, 0), Enums.CellVisibility.UNKNOWN)
