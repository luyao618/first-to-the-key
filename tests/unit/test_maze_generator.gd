## Unit tests for MazeGenerator.
extends GutTest

const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")


## Helper: create a MazeGenerator node and add to scene tree.
func _make_generator() -> Node:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	return gen


func test_generate_returns_finalized_maze() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(5, 5)
	assert_signal_emitted(gen, "maze_generated")
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	assert_not_null(maze, "Should emit a MazeData instance")


func test_generate_all_cells_reachable() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(10, 10)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	# BFS from (0,0) should reach all 100 cells
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [Vector2i(0, 0)]
	visited[Vector2i(0, 0)] = true
	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		for neighbor in maze.get_neighbors(current.x, current.y):
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	assert_eq(visited.size(), 100, "All 100 cells should be reachable")


func test_generate_perfect_maze_edge_count() -> void:
	# A perfect maze has exactly width*height - 1 passages
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(8, 8)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	var passage_count := 0
	for y in range(8):
		for x in range(8):
			# Count EAST passages (to avoid double-counting)
			if x < 7 and maze.can_move(x, y, Enums.Direction.EAST):
				passage_count += 1
			# Count SOUTH passages
			if y < 7 and maze.can_move(x, y, Enums.Direction.SOUTH):
				passage_count += 1
	assert_eq(passage_count, 8 * 8 - 1, "Perfect maze should have w*h-1 passages")


func test_generate_has_all_markers() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(5, 5)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	assert_eq(maze.get_marker_position(Enums.MarkerType.SPAWN_A), Vector2i(0, 0),
		"SPAWN_A should be at (0,0)")
	assert_eq(maze.get_marker_position(Enums.MarkerType.SPAWN_B), Vector2i(4, 4),
		"SPAWN_B should be at (width-1, height-1)")
	assert_ne(maze.get_marker_position(Enums.MarkerType.KEY_BRASS), Vector2i(-1, -1),
		"KEY_BRASS should be placed")
	assert_ne(maze.get_marker_position(Enums.MarkerType.KEY_JADE), Vector2i(-1, -1),
		"KEY_JADE should be placed")
	assert_ne(maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL), Vector2i(-1, -1),
		"KEY_CRYSTAL should be placed")
	assert_ne(maze.get_marker_position(Enums.MarkerType.CHEST), Vector2i(-1, -1),
		"CHEST should be placed")


func test_markers_all_on_unique_cells() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(5, 5)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	var positions: Array[Vector2i] = []
	for marker in [Enums.MarkerType.SPAWN_A, Enums.MarkerType.SPAWN_B,
			Enums.MarkerType.KEY_BRASS, Enums.MarkerType.KEY_JADE,
			Enums.MarkerType.KEY_CRYSTAL, Enums.MarkerType.CHEST]:
		var pos := maze.get_marker_position(marker)
		assert_does_not_have(positions, pos,
			"Marker %d at (%d,%d) already used" % [marker, pos.x, pos.y])
		positions.append(pos)


func test_markers_not_on_spawn_cells() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(5, 5)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	var spawn_a := maze.get_marker_position(Enums.MarkerType.SPAWN_A)
	var spawn_b := maze.get_marker_position(Enums.MarkerType.SPAWN_B)
	for marker in [Enums.MarkerType.KEY_BRASS, Enums.MarkerType.KEY_JADE,
			Enums.MarkerType.KEY_CRYSTAL, Enums.MarkerType.CHEST]:
		var pos := maze.get_marker_position(marker)
		assert_ne(pos, spawn_a, "Marker %d should not be on SPAWN_A" % marker)
		assert_ne(pos, spawn_b, "Marker %d should not be on SPAWN_B" % marker)
