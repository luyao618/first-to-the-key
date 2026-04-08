## Maze Generator — procedural maze creation using iterative DFS (Recursive Backtracker).
## Creates a fully connected perfect maze, places markers, validates fairness.
## See design/gdd/maze-generator.md for full specification.
class_name MazeGenerator
extends Node

const ConfigLoader = preload("res://src/shared/config_loader.gd")

signal maze_generated(maze_data: RefCounted)
signal generation_failed(retry_count: int, reason: String)

## Config values (loaded from game_config.json).
var _max_fairness_delta: int = 2
var _max_generation_retries: int = 50
var _config_loaded: bool = false


## Generate a maze with the given dimensions.
## Returns the finalized MazeData on success, null on failure.
## Also emits maze_generated / generation_failed signals.
func generate(width: int, height: int) -> RefCounted:
	if not _config_loaded:
		_load_config()

	# Minimum size check: need at least 6 cells for 6 markers, width >= 2, height >= 2
	if width < 2 or height < 2 or width * height < 6:
		generation_failed.emit(0, "Maze too small: %dx%d (need w>=2, h>=2, w*h>=6)" % [width, height])
		return null

	var maze := MazeData.new(width, height)

	for attempt in range(_max_generation_retries):
		if attempt > 0:
			maze.reset()

		# Phase 1: Carve passages with iterative DFS
		_carve_maze(maze, width, height)

		# Phase 2: Place markers
		_place_markers(maze, width, height)

		# Phase 3: Validate fairness
		if not _validate_fairness(maze):
			continue

		# Phase 4: Finalize
		if maze.finalize():
			maze_generated.emit(maze)
			return maze
		# finalize() failed (is_valid() detected issue) — retry

	generation_failed.emit(_max_generation_retries,
		"Failed to generate fair maze after %d retries" % _max_generation_retries)
	return null


## Iterative DFS (Recursive Backtracker) maze carving.
## Uses explicit stack to avoid GDScript stack overflow on large mazes.
func _carve_maze(maze: RefCounted, width: int, height: int) -> void:
	var visited: Dictionary = {}

	# Start from a random cell
	var start := Vector2i(randi() % width, randi() % height)
	var stack: Array[Vector2i] = [start]
	visited[start] = true

	while stack.size() > 0:
		var current: Vector2i = stack.back()

		# Get unvisited neighbors
		var unvisited_neighbors: Array[Dictionary] = []
		for dir in [Enums.Direction.NORTH, Enums.Direction.EAST,
				Enums.Direction.SOUTH, Enums.Direction.WEST]:
			var offset: Vector2i = Enums.DIRECTION_OFFSETS[dir]
			var nx := current.x + offset.x
			var ny := current.y + offset.y
			if nx >= 0 and nx < width and ny >= 0 and ny < height:
				var neighbor := Vector2i(nx, ny)
				if not visited.has(neighbor):
					unvisited_neighbors.append({"pos": neighbor, "dir": dir})

		if unvisited_neighbors.size() > 0:
			# Pick a random unvisited neighbor
			var chosen: Dictionary = unvisited_neighbors[randi() % unvisited_neighbors.size()]
			var next_pos: Vector2i = chosen["pos"]
			var dir: int = chosen["dir"]

			# Remove the wall between current and chosen
			maze.set_wall(current.x, current.y, dir, false)

			visited[next_pos] = true
			stack.append(next_pos)
		else:
			# Backtrack
			stack.pop_back()


## Place spawn points, keys, and chest.
func _place_markers(maze: RefCounted, width: int, height: int) -> void:
	# Fixed spawn positions
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(width - 1, height - 1, Enums.MarkerType.SPAWN_B)

	# Collect available cells (not spawn points, not occupied)
	var occupied: Dictionary = {
		Vector2i(0, 0): true,
		Vector2i(width - 1, height - 1): true,
	}

	var items_to_place := [
		Enums.MarkerType.KEY_BRASS,
		Enums.MarkerType.KEY_JADE,
		Enums.MarkerType.KEY_CRYSTAL,
		Enums.MarkerType.CHEST,
	]

	for marker_type in items_to_place:
		var available: Array[Vector2i] = []
		for y in range(height):
			for x in range(width):
				var pos := Vector2i(x, y)
				if not occupied.has(pos):
					available.append(pos)

		var chosen: Vector2i = available[randi() % available.size()]
		maze.place_marker(chosen.x, chosen.y, marker_type)
		occupied[chosen] = true


## Validate fairness: BFS path delta for all 4 targets must be within threshold.
func _validate_fairness(maze: RefCounted) -> bool:
	var spawn_a: Vector2i = maze.get_marker_position(Enums.MarkerType.SPAWN_A)
	var spawn_b: Vector2i = maze.get_marker_position(Enums.MarkerType.SPAWN_B)

	var targets := [
		Enums.MarkerType.KEY_BRASS,
		Enums.MarkerType.KEY_JADE,
		Enums.MarkerType.KEY_CRYSTAL,
		Enums.MarkerType.CHEST,
	]

	for target_type in targets:
		var target_pos: Vector2i = maze.get_marker_position(target_type)
		var path_a: Array = maze.get_shortest_path(spawn_a, target_pos)
		var path_b: Array = maze.get_shortest_path(spawn_b, target_pos)

		# Path size includes start and end, so steps = size - 1
		# Empty path means same position (0 steps)
		var steps_a: int = max(0, path_a.size() - 1)
		var steps_b: int = max(0, path_b.size() - 1)
		var delta: int = abs(steps_a - steps_b)

		if delta > _max_fairness_delta:
			return false

	return true


## Load config values from game_config.json.
func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/game_config.json")
	var maze_cfg: Dictionary = cfg.get("maze", {})
	var gen_cfg: Dictionary = cfg.get("generator", {})
	_max_fairness_delta = ConfigLoader.get_or_default(maze_cfg, "max_fairness_delta", 2)
	_max_generation_retries = ConfigLoader.get_or_default(gen_cfg, "max_generation_retries", 50)
	_config_loaded = true
