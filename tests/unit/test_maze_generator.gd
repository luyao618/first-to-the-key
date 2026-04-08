## Unit tests for MazeGenerator.
extends GutTest

const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")


## Helper: create a MazeGenerator node and add to scene tree.
func _make_generator() -> Node:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	gen._max_generation_retries = 200
	gen._config_loaded = true
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
		var pos: Vector2i = maze.get_marker_position(marker)
		assert_does_not_have(positions, pos,
			"Marker %d at (%d,%d) already used" % [marker, pos.x, pos.y])
		positions.append(pos)


func test_markers_not_on_spawn_cells() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(5, 5)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	var spawn_a: Vector2i = maze.get_marker_position(Enums.MarkerType.SPAWN_A)
	var spawn_b: Vector2i = maze.get_marker_position(Enums.MarkerType.SPAWN_B)
	for marker in [Enums.MarkerType.KEY_BRASS, Enums.MarkerType.KEY_JADE,
			Enums.MarkerType.KEY_CRYSTAL, Enums.MarkerType.CHEST]:
		var pos: Vector2i = maze.get_marker_position(marker)
		assert_ne(pos, spawn_a, "Marker %d should not be on SPAWN_A" % marker)
		assert_ne(pos, spawn_b, "Marker %d should not be on SPAWN_B" % marker)


func test_fairness_validation_passes() -> void:
	var gen := _make_generator()
	# Use the default relaxed fairness from _make_generator (delta=100)
	# Just verify the generated maze passes its own fairness check
	watch_signals(gen)
	gen.generate(15, 15)
	assert_signal_emitted(gen, "maze_generated")
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	# Verify fairness manually
	var spawn_a: Vector2i = maze.get_marker_position(Enums.MarkerType.SPAWN_A)
	var spawn_b: Vector2i = maze.get_marker_position(Enums.MarkerType.SPAWN_B)
	for target in [Enums.MarkerType.KEY_BRASS, Enums.MarkerType.KEY_JADE,
			Enums.MarkerType.KEY_CRYSTAL, Enums.MarkerType.CHEST]:
		var target_pos: Vector2i = maze.get_marker_position(target)
		var path_a: Array[Vector2i] = maze.get_shortest_path(spawn_a, target_pos)
		var path_b: Array[Vector2i] = maze.get_shortest_path(spawn_b, target_pos)
		var delta: int = abs((path_a.size() - 1) - (path_b.size() - 1))
		assert_true(delta <= gen._max_fairness_delta,
			"Fairness delta for target %d is %d (max %d)" % [target, delta, gen._max_fairness_delta])


func test_minimum_size_2x3_succeeds() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(2, 3)
	assert_signal_emitted(gen, "maze_generated")


func test_minimum_size_3x2_succeeds() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(3, 2)
	assert_signal_emitted(gen, "maze_generated")


func test_too_small_1x1_fails() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(1, 1)
	assert_signal_emitted(gen, "generation_failed")
	assert_signal_not_emitted(gen, "maze_generated")


func test_too_small_2x2_fails() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(2, 2)
	assert_signal_emitted(gen, "generation_failed")
	assert_signal_not_emitted(gen, "maze_generated")


func test_too_small_1x5_fails() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(1, 5)
	assert_signal_emitted(gen, "generation_failed")
	assert_signal_not_emitted(gen, "maze_generated")


func test_randomness_produces_different_mazes() -> void:
	var gen := _make_generator()
	var wall_hashes: Array[int] = []
	for i in range(10):
		watch_signals(gen)
		gen.generate(10, 10)
		var maze: RefCounted = get_signal_parameters(gen, "maze_generated", i)[0]
		# Hash the wall pattern
		var h := 0
		for y in range(10):
			for x in range(10):
				if maze.can_move(x, y, Enums.Direction.EAST):
					h = h ^ (x * 31 + y * 37)
				if maze.can_move(x, y, Enums.Direction.SOUTH):
					h = h ^ (x * 41 + y * 43)
		wall_hashes.append(h)
	# At least 9 of 10 should be unique
	var unique_count := 0
	var seen: Dictionary = {}
	for h in wall_hashes:
		if not seen.has(h):
			seen[h] = true
			unique_count += 1
	assert_gte(unique_count, 9, "At least 9 of 10 mazes should be unique")


func test_boundary_walls_intact() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(5, 5)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	# Top boundary
	for x in range(5):
		assert_true(maze.has_wall(x, 0, Enums.Direction.NORTH),
			"Top boundary at x=%d should have NORTH wall" % x)
	# Bottom boundary
	for x in range(5):
		assert_true(maze.has_wall(x, 4, Enums.Direction.SOUTH),
			"Bottom boundary at x=%d should have SOUTH wall" % x)
	# Left boundary
	for y in range(5):
		assert_true(maze.has_wall(0, y, Enums.Direction.WEST),
			"Left boundary at y=%d should have WEST wall" % y)
	# Right boundary
	for y in range(5):
		assert_true(maze.has_wall(4, y, Enums.Direction.EAST),
			"Right boundary at y=%d should have EAST wall" % y)


func test_large_maze_50x50_succeeds() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(50, 50)
	assert_signal_emitted(gen, "maze_generated")
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	# Verify connectivity
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [Vector2i(0, 0)]
	visited[Vector2i(0, 0)] = true
	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		for neighbor in maze.get_neighbors(current.x, current.y):
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	assert_eq(visited.size(), 2500, "All 2500 cells should be reachable in 50x50")
