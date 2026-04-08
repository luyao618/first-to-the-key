## Unit tests for MazeData class.
extends GutTest

const MazeData := preload("res://src/core/maze_data.gd")


func test_constructor_creates_grid_with_correct_dimensions() -> void:
	var maze := MazeData.new(5, 4)
	assert_eq(maze.width, 5, "Width should be 5")
	assert_eq(maze.height, 4, "Height should be 4")


func test_all_cells_start_with_four_walls() -> void:
	var maze := MazeData.new(3, 3)
	for y in range(3):
		for x in range(3):
			assert_true(maze.has_wall(x, y, Enums.Direction.NORTH), "(%d,%d) NORTH wall" % [x, y])
			assert_true(maze.has_wall(x, y, Enums.Direction.EAST), "(%d,%d) EAST wall" % [x, y])
			assert_true(maze.has_wall(x, y, Enums.Direction.SOUTH), "(%d,%d) SOUTH wall" % [x, y])
			assert_true(maze.has_wall(x, y, Enums.Direction.WEST), "(%d,%d) WEST wall" % [x, y])


func test_all_cells_start_with_no_markers() -> void:
	var maze := MazeData.new(3, 3)
	for y in range(3):
		for x in range(3):
			assert_eq(maze.get_markers_at(x, y).size(), 0, "(%d,%d) should have no markers" % [x, y])


func test_can_move_returns_false_when_all_walls() -> void:
	var maze := MazeData.new(3, 3)
	assert_false(maze.can_move(1, 1, Enums.Direction.NORTH))
	assert_false(maze.can_move(1, 1, Enums.Direction.EAST))
	assert_false(maze.can_move(1, 1, Enums.Direction.SOUTH))
	assert_false(maze.can_move(1, 1, Enums.Direction.WEST))


func test_get_neighbors_returns_empty_when_all_walls() -> void:
	var maze := MazeData.new(3, 3)
	assert_eq(maze.get_neighbors(1, 1).size(), 0)


func test_out_of_bounds_get_cell_returns_null() -> void:
	var maze := MazeData.new(3, 3)
	assert_null(maze.get_cell(-1, 0))
	assert_null(maze.get_cell(3, 0))
	assert_null(maze.get_cell(0, -1))
	assert_null(maze.get_cell(0, 3))
