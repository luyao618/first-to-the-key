## Fog of War facade — manages per-agent visibility of maze cells.
## Each agent has an independent VisionMap tracking three-state cell visibility.
## See design/gdd/fog-of-war.md for full specification.
class_name FogOfWar
extends Node

## Note: CellVisibility enum is defined in Enums autoload (src/shared/enums.gd).
## Use Enums.CellVisibility.UNKNOWN / VISIBLE / EXPLORED.

## Per-agent vision maps. Keys are agent_id (int).
## Values are Dictionaries: { "grid": Array[Array[int]], "current_visible": Array[Vector2i] }
var _vision_maps: Dictionary = {}

## Shared vision radius (from config).
var _vision_radius: int = 3

## Reference to the maze (for BFS neighbor queries).
var _maze: RefCounted = null


## Create VisionMaps for all agents, reset to all UNKNOWN.
## Initial vision is NOT computed here — Grid Movement calls update_vision() after Movers are placed.
func initialize(maze: RefCounted, agent_ids: Array) -> void:
	_maze = maze
	_vision_maps.clear()

	# Load config
	var cfg := ConfigLoader.load_json("res://assets/data/game_config.json")
	var vision_cfg: Dictionary = cfg.get("vision", {})
	_vision_radius = ConfigLoader.get_or_default(vision_cfg, "vision_radius", 3)

	for agent_id in agent_ids:
		_vision_maps[agent_id] = _create_vision_map()


## Update vision for an agent at a new position.
## BFS from position up to vision_radius steps along passable paths.
func update_vision(agent_id: int, position: Vector2i) -> void:
	if not _vision_maps.has(agent_id):
		push_warning("FogOfWar: Invalid agent_id %d in update_vision" % agent_id)
		return

	var vmap: Dictionary = _vision_maps[agent_id]
	var old_visible: Array = vmap["current_visible"]

	# Demote old VISIBLE cells to EXPLORED
	for cell_pos in old_visible:
		var cx: int = cell_pos.x
		var cy: int = cell_pos.y
		if _is_in_bounds(cx, cy):
			vmap["grid"][cy][cx] = Enums.CellVisibility.EXPLORED

	# Compute new visible cells via BFS
	var new_visible: Array[Vector2i] = _compute_visible_cells(position, _vision_radius)

	# Set new visible cells
	for cell_pos in new_visible:
		vmap["grid"][cell_pos.y][cell_pos.x] = Enums.CellVisibility.VISIBLE

	# Cache the new visible list
	vmap["current_visible"] = new_visible


## Get visibility state of a single cell for an agent.
func get_cell_visibility(agent_id: int, x: int, y: int) -> int:
	if not _vision_maps.has(agent_id):
		push_warning("FogOfWar: Invalid agent_id %d in get_cell_visibility" % agent_id)
		return Enums.CellVisibility.UNKNOWN
	if not _is_in_bounds(x, y):
		return Enums.CellVisibility.UNKNOWN
	return _vision_maps[agent_id]["grid"][y][x]


## Get all currently VISIBLE cells for an agent, sorted row-major (y asc, x asc).
func get_visible_cells(agent_id: int) -> Array[Vector2i]:
	if not _vision_maps.has(agent_id):
		push_warning("FogOfWar: Invalid agent_id %d in get_visible_cells" % agent_id)
		return [] as Array[Vector2i]
	var result: Array[Vector2i] = []
	result.assign(_vision_maps[agent_id]["current_visible"])
	result.sort_custom(_sort_row_major)
	return result


## Get all EXPLORED cells for an agent, sorted row-major (y asc, x asc).
func get_explored_cells(agent_id: int) -> Array[Vector2i]:
	if not _vision_maps.has(agent_id):
		push_warning("FogOfWar: Invalid agent_id %d in get_explored_cells" % agent_id)
		return [] as Array[Vector2i]

	var vmap: Dictionary = _vision_maps[agent_id]
	var result: Array[Vector2i] = []
	for y in range(_maze.height):
		for x in range(_maze.width):
			if vmap["grid"][y][x] == Enums.CellVisibility.EXPLORED:
				result.append(Vector2i(x, y))
	return result


# --- Internal ---


## Create a blank vision map (all UNKNOWN).
func _create_vision_map() -> Dictionary:
	var grid: Array = []
	for y in range(_maze.height):
		var row: Array[int] = []
		for x in range(_maze.width):
			row.append(Enums.CellVisibility.UNKNOWN)
		grid.append(row)
	return {
		"grid": grid,
		"current_visible": [] as Array[Vector2i],
	}


## BFS along passable paths from origin up to max_dist steps.
func _compute_visible_cells(origin: Vector2i, max_dist: int) -> Array[Vector2i]:
	if _maze == null:
		return [] as Array[Vector2i]

	var result: Array[Vector2i] = [origin]
	var visited: Dictionary = {origin: 0}
	var queue: Array = [{"pos": origin, "dist": 0}]

	while queue.size() > 0:
		var entry: Dictionary = queue.pop_front()
		var pos: Vector2i = entry["pos"]
		var dist: int = entry["dist"]

		if dist >= max_dist:
			continue

		var neighbors: Array[Vector2i] = _maze.get_neighbors(pos.x, pos.y)
		for neighbor in neighbors:
			if not visited.has(neighbor):
				visited[neighbor] = dist + 1
				result.append(neighbor)
				queue.append({"pos": neighbor, "dist": dist + 1})

	return result


## Check if coordinates are within maze bounds.
func _is_in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < _maze.width and y >= 0 and y < _maze.height


## Sort comparator for row-major order (y ascending, then x ascending).
static func _sort_row_major(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
