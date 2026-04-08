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


func test_set_wall_removes_wall_and_syncs_neighbor() -> void:
	var maze := MazeData.new(3, 3)
	maze.set_wall(1, 1, Enums.Direction.EAST, false)
	assert_false(maze.has_wall(1, 1, Enums.Direction.EAST), "(1,1) EAST should be open")
	assert_false(maze.has_wall(2, 1, Enums.Direction.WEST), "(2,1) WEST should be open (synced)")


func test_set_wall_adds_wall_and_syncs_neighbor() -> void:
	var maze := MazeData.new(3, 3)
	maze.set_wall(1, 1, Enums.Direction.EAST, false)  # Remove first
	maze.set_wall(1, 1, Enums.Direction.EAST, true)   # Add back
	assert_true(maze.has_wall(1, 1, Enums.Direction.EAST))
	assert_true(maze.has_wall(2, 1, Enums.Direction.WEST))


func test_boundary_wall_cannot_be_removed() -> void:
	var maze := MazeData.new(3, 3)
	maze.set_wall(0, 0, Enums.Direction.WEST, false)
	assert_true(maze.has_wall(0, 0, Enums.Direction.WEST), "Left boundary wall must stay")

	maze.set_wall(0, 0, Enums.Direction.NORTH, false)
	assert_true(maze.has_wall(0, 0, Enums.Direction.NORTH), "Top boundary wall must stay")

	maze.set_wall(2, 2, Enums.Direction.EAST, false)
	assert_true(maze.has_wall(2, 2, Enums.Direction.EAST), "Right boundary wall must stay")

	maze.set_wall(2, 2, Enums.Direction.SOUTH, false)
	assert_true(maze.has_wall(2, 2, Enums.Direction.SOUTH), "Bottom boundary wall must stay")


func test_can_move_after_wall_removal() -> void:
	var maze := MazeData.new(3, 3)
	maze.set_wall(1, 1, Enums.Direction.NORTH, false)
	assert_true(maze.can_move(1, 1, Enums.Direction.NORTH))
	assert_true(maze.can_move(1, 0, Enums.Direction.SOUTH))


func test_get_neighbors_after_wall_removal() -> void:
	var maze := MazeData.new(3, 3)
	maze.set_wall(1, 1, Enums.Direction.EAST, false)
	maze.set_wall(1, 1, Enums.Direction.SOUTH, false)
	var neighbors := maze.get_neighbors(1, 1)
	assert_eq(neighbors.size(), 2)
	assert_has(neighbors, Vector2i(2, 1))
	assert_has(neighbors, Vector2i(1, 2))


func test_place_marker_and_query() -> void:
	var maze := MazeData.new(5, 5)
	maze.place_marker(2, 3, Enums.MarkerType.SPAWN_A)
	assert_eq(maze.get_marker_position(Enums.MarkerType.SPAWN_A), Vector2i(2, 3))
	var markers := maze.get_markers_at(2, 3)
	assert_has(markers, Enums.MarkerType.SPAWN_A)


func test_place_marker_uniqueness_relocates() -> void:
	var maze := MazeData.new(5, 5)
	maze.place_marker(1, 1, Enums.MarkerType.SPAWN_A)
	maze.place_marker(3, 3, Enums.MarkerType.SPAWN_A)
	# Old position should no longer have the marker
	assert_eq(maze.get_markers_at(1, 1).size(), 0, "Old position should be empty")
	# New position should have it
	assert_eq(maze.get_marker_position(Enums.MarkerType.SPAWN_A), Vector2i(3, 3))
	assert_has(maze.get_markers_at(3, 3), Enums.MarkerType.SPAWN_A)


func test_remove_marker() -> void:
	var maze := MazeData.new(5, 5)
	maze.place_marker(2, 2, Enums.MarkerType.KEY_BRASS)
	maze.remove_marker(2, 2, Enums.MarkerType.KEY_BRASS)
	assert_eq(maze.get_markers_at(2, 2).size(), 0)
	assert_eq(maze.get_marker_position(Enums.MarkerType.KEY_BRASS), Vector2i(-1, -1))


func test_multiple_markers_on_same_cell() -> void:
	var maze := MazeData.new(5, 5)
	maze.place_marker(2, 2, Enums.MarkerType.KEY_BRASS)
	maze.place_marker(2, 2, Enums.MarkerType.SPAWN_A)
	var markers := maze.get_markers_at(2, 2)
	assert_eq(markers.size(), 2)
	assert_has(markers, Enums.MarkerType.KEY_BRASS)
	assert_has(markers, Enums.MarkerType.SPAWN_A)


func test_unplaced_marker_returns_negative_one() -> void:
	var maze := MazeData.new(5, 5)
	assert_eq(maze.get_marker_position(Enums.MarkerType.CHEST), Vector2i(-1, -1))


## Helper: create a minimal valid 3x3 maze (all connected, all markers placed).
func _make_valid_maze() -> MazeData:
	var maze := MazeData.new(3, 3)
	# Open a path: (0,0)-(1,0)-(2,0)-(2,1)-(2,2)-(1,2)-(0,2)-(0,1)-(1,1)
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	maze.set_wall(1, 0, Enums.Direction.EAST, false)
	maze.set_wall(2, 0, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 1, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 2, Enums.Direction.WEST, false)
	maze.set_wall(1, 2, Enums.Direction.WEST, false)
	maze.set_wall(0, 2, Enums.Direction.NORTH, false)
	maze.set_wall(1, 1, Enums.Direction.SOUTH, false)
	# Place all 6 markers on unique cells
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(2, 2, Enums.MarkerType.SPAWN_B)
	maze.place_marker(1, 0, Enums.MarkerType.KEY_BRASS)
	maze.place_marker(2, 0, Enums.MarkerType.KEY_JADE)
	maze.place_marker(2, 1, Enums.MarkerType.KEY_CRYSTAL)
	maze.place_marker(1, 2, Enums.MarkerType.CHEST)
	return maze


func test_is_valid_with_complete_maze() -> void:
	var maze := _make_valid_maze()
	assert_true(maze.is_valid())


func test_is_valid_fails_missing_marker() -> void:
	var maze := _make_valid_maze()
	maze.remove_marker(1, 2, Enums.MarkerType.CHEST)
	assert_false(maze.is_valid())
	assert_push_error_count(1)


func test_is_valid_fails_duplicate_marker_positions() -> void:
	var maze := MazeData.new(3, 3)
	# Open path
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	maze.set_wall(1, 0, Enums.Direction.EAST, false)
	maze.set_wall(2, 0, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 1, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 2, Enums.Direction.WEST, false)
	maze.set_wall(1, 2, Enums.Direction.WEST, false)
	maze.set_wall(0, 2, Enums.Direction.NORTH, false)
	maze.set_wall(1, 1, Enums.Direction.SOUTH, false)
	# Place two markers on same cell
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(0, 0, Enums.MarkerType.KEY_BRASS)  # Same cell as SPAWN_A!
	maze.place_marker(2, 2, Enums.MarkerType.SPAWN_B)
	maze.place_marker(1, 0, Enums.MarkerType.KEY_JADE)
	maze.place_marker(2, 0, Enums.MarkerType.KEY_CRYSTAL)
	maze.place_marker(2, 1, Enums.MarkerType.CHEST)
	assert_false(maze.is_valid())
	assert_push_error_count(1)


func test_is_valid_fails_disconnected() -> void:
	var maze := MazeData.new(3, 3)
	# No walls removed - all cells isolated
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(2, 2, Enums.MarkerType.SPAWN_B)
	maze.place_marker(1, 0, Enums.MarkerType.KEY_BRASS)
	maze.place_marker(2, 0, Enums.MarkerType.KEY_JADE)
	maze.place_marker(2, 1, Enums.MarkerType.KEY_CRYSTAL)
	maze.place_marker(1, 2, Enums.MarkerType.CHEST)
	assert_false(maze.is_valid())
	assert_push_error_count(1)


func test_finalize_locks_writes() -> void:
	var maze := _make_valid_maze()
	assert_true(maze.finalize())
	# Writes should be rejected after finalize
	maze.set_wall(1, 1, Enums.Direction.NORTH, false)
	assert_true(maze.has_wall(1, 1, Enums.Direction.NORTH), "set_wall should be rejected after finalize")
	maze.place_marker(1, 1, Enums.MarkerType.CHEST)
	assert_eq(maze.get_marker_position(Enums.MarkerType.CHEST), Vector2i(1, 2), "place_marker should be rejected after finalize")
	assert_push_error_count(2)


func test_finalize_fails_on_invalid_maze() -> void:
	var maze := MazeData.new(3, 3)  # No markers
	assert_false(maze.finalize())
	assert_push_error_count(1)


func test_reset_restores_initial_state() -> void:
	var maze := _make_valid_maze()
	maze.finalize()
	maze.reset()
	# All walls should be back
	assert_true(maze.has_wall(0, 0, Enums.Direction.EAST))
	# Markers cleared
	assert_eq(maze.get_marker_position(Enums.MarkerType.SPAWN_A), Vector2i(-1, -1))
	# Write should work again
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	assert_false(maze.has_wall(0, 0, Enums.Direction.EAST))


func test_reset_is_idempotent() -> void:
	var maze := MazeData.new(3, 3)
	maze.reset()  # Should not error on Uninitialized state
	assert_true(maze.has_wall(0, 0, Enums.Direction.NORTH))


func test_reset_then_finalize_works() -> void:
	var maze := _make_valid_maze()
	maze.finalize()
	maze.reset()
	# Rebuild the same valid maze
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
	assert_true(maze.finalize())


func test_shortest_path_adjacent() -> void:
	var maze := MazeData.new(3, 3)
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	var path := maze.get_shortest_path(Vector2i(0, 0), Vector2i(1, 0))
	assert_eq(path.size(), 2, "Path should have 2 nodes (start + end)")
	assert_eq(path[0], Vector2i(0, 0))
	assert_eq(path[1], Vector2i(1, 0))


func test_shortest_path_same_position() -> void:
	var maze := MazeData.new(3, 3)
	var path := maze.get_shortest_path(Vector2i(1, 1), Vector2i(1, 1))
	assert_eq(path.size(), 0, "Same start and goal should return empty path")


func test_shortest_path_no_connection() -> void:
	var maze := MazeData.new(3, 3)  # All walls - no connections
	var path := maze.get_shortest_path(Vector2i(0, 0), Vector2i(2, 2))
	assert_eq(path.size(), 0, "Disconnected cells should return empty path")


func test_shortest_path_linear() -> void:
	var maze := MazeData.new(5, 1)
	# Open a straight line: (0,0)-(1,0)-(2,0)-(3,0)-(4,0)
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	maze.set_wall(1, 0, Enums.Direction.EAST, false)
	maze.set_wall(2, 0, Enums.Direction.EAST, false)
	maze.set_wall(3, 0, Enums.Direction.EAST, false)
	var path := maze.get_shortest_path(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(path.size(), 5, "Path length should be 5 (0->1->2->3->4)")


func test_shortest_path_finds_shorter_route() -> void:
	# Create a maze with two paths: short (2 steps) and long (4 steps)
	var maze := MazeData.new(3, 2)
	# Short path: (0,0) -> (1,0) -> (2,0)
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	maze.set_wall(1, 0, Enums.Direction.EAST, false)
	# Long path: (0,0) -> (0,1) -> (1,1) -> (2,1) -> (2,0)
	maze.set_wall(0, 0, Enums.Direction.SOUTH, false)
	maze.set_wall(0, 1, Enums.Direction.EAST, false)
	maze.set_wall(1, 1, Enums.Direction.EAST, false)
	maze.set_wall(2, 1, Enums.Direction.NORTH, false)
	var path := maze.get_shortest_path(Vector2i(0, 0), Vector2i(2, 0))
	assert_eq(path.size(), 3, "Should find shortest path (3 nodes = 2 steps)")
