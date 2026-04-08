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
