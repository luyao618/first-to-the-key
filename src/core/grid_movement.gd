## Grid Movement — tick-based movement manager for maze agents.
## Manages Mover state, validates movement against MazeData, emits movement signals.
## See design/gdd/grid-movement.md for full specification.
class_name GridMovement
extends Node

# --- Signals ---
signal mover_moved(mover_id: int, old_pos: Vector2i, new_pos: Vector2i)
signal mover_blocked(mover_id: int, pos: Vector2i, direction: int)
signal mover_stayed(mover_id: int, pos: Vector2i)

# --- Dependencies (injected before initialize) ---
## MazeData reference (read-only after finalize).
var maze: RefCounted = null
## FogOfWar reference (only used in initialize for initial vision).
var fog: Node = null

# --- Internal State ---
## Array of Mover dictionaries.
var _movers: Array[Dictionary] = []

## Direction offset mapping for MoveDirection.
const DIRECTION_OFFSETS: Dictionary = {
	Enums.MoveDirection.NORTH: Vector2i(0, -1),
	Enums.MoveDirection.EAST: Vector2i(1, 0),
	Enums.MoveDirection.SOUTH: Vector2i(0, 1),
	Enums.MoveDirection.WEST: Vector2i(-1, 0),
}

## MoveDirection -> Direction mapping for can_move() calls.
const MOVE_TO_DIR: Dictionary = {
	Enums.MoveDirection.NORTH: Enums.Direction.NORTH,
	Enums.MoveDirection.EAST: Enums.Direction.EAST,
	Enums.MoveDirection.SOUTH: Enums.Direction.SOUTH,
	Enums.MoveDirection.WEST: Enums.Direction.WEST,
}


## Initialize movers at spawn positions from MazeData.
## Triggers initial fog vision for each mover.
func initialize() -> void:
	_movers.clear()

	for i in range(2):
		var spawn_marker: int = Enums.MarkerType.SPAWN_A if i == 0 else Enums.MarkerType.SPAWN_B
		var spawn_pos: Vector2i = Vector2i(-1, -1)
		if maze != null:
			spawn_pos = maze.get_marker_position(spawn_marker)

		if spawn_pos == Vector2i(-1, -1):
			push_error("GridMovement: Missing spawn marker %d for mover %d" % [spawn_marker, i])

		var visited_dict: Dictionary = {}
		var visited_list: Array[Vector2i] = []
		if spawn_pos != Vector2i(-1, -1):
			visited_dict[spawn_pos] = true
			visited_list.append(spawn_pos)

		_movers.append({
			"id": i,
			"position": spawn_pos,
			"pending_direction": Enums.MoveDirection.NONE,
			"visited_cells_dict": visited_dict,
			"visited_cells_list": visited_list,
			"total_moves": 0,
			"blocked_count": 0,
		})

	# Trigger initial vision for all movers
	if fog != null:
		for mover in _movers:
			if mover["position"] != Vector2i(-1, -1):
				fog.update_vision(mover["id"], mover["position"])


## Reset all mover state.
func reset() -> void:
	_movers.clear()


## Set the pending direction for a mover. Consumed in next on_tick().
func set_direction(mover_id: int, direction: int) -> void:
	if mover_id < 0 or mover_id >= _movers.size():
		push_warning("GridMovement: Invalid mover_id %d in set_direction" % mover_id)
		return
	_movers[mover_id]["pending_direction"] = direction


## Process one tick: read pending directions, validate, update positions, batch emit signals.
func on_tick(_tick_count: int) -> void:
	var results: Array[Dictionary] = []

	# Phase 1: Process all movers, collect results
	for mover in _movers:
		var dir: int = mover["pending_direction"]
		mover["pending_direction"] = Enums.MoveDirection.NONE

		if dir == Enums.MoveDirection.NONE:
			results.append({"type": "stayed", "id": mover["id"], "pos": mover["position"]})
			continue

		var maze_dir: int = MOVE_TO_DIR[dir]
		var pos: Vector2i = mover["position"]

		if maze != null and maze.can_move(pos.x, pos.y, maze_dir):
			var old_pos: Vector2i = pos
			var offset: Vector2i = DIRECTION_OFFSETS[dir]
			var new_pos: Vector2i = old_pos + offset
			mover["position"] = new_pos
			mover["total_moves"] += 1

			if not mover["visited_cells_dict"].has(new_pos):
				mover["visited_cells_dict"][new_pos] = true
				mover["visited_cells_list"].append(new_pos)

			results.append({"type": "moved", "id": mover["id"],
				"old_pos": old_pos, "new_pos": new_pos})
		else:
			mover["blocked_count"] += 1
			results.append({"type": "blocked", "id": mover["id"],
				"pos": pos, "dir": maze_dir})

	# Phase 2: Batch emit signals after all movers processed
	for result in results:
		match result["type"]:
			"stayed":
				mover_stayed.emit(result["id"], result["pos"])
			"moved":
				mover_moved.emit(result["id"], result["old_pos"], result["new_pos"])
			"blocked":
				mover_blocked.emit(result["id"], result["pos"], result["dir"])


# --- Query Interface ---


## Get current position of a mover.
func get_position_of(mover_id: int) -> Vector2i:
	if mover_id < 0 or mover_id >= _movers.size():
		push_warning("GridMovement: Invalid mover_id %d in get_position_of" % mover_id)
		return Vector2i(-1, -1)
	return _movers[mover_id]["position"]


## Get visited cells as an Array (exposed as ordered list).
func get_visited_cells(mover_id: int) -> Array[Vector2i]:
	if mover_id < 0 or mover_id >= _movers.size():
		return [] as Array[Vector2i]
	var result: Array[Vector2i] = []
	result.assign(_movers[mover_id]["visited_cells_list"])
	return result


## Check if a mover has visited a specific cell.
func has_visited(mover_id: int, pos: Vector2i) -> bool:
	if mover_id < 0 or mover_id >= _movers.size():
		return false
	return _movers[mover_id]["visited_cells_dict"].has(pos)


## Get total successful moves for a mover.
func get_total_moves(mover_id: int) -> int:
	if mover_id < 0 or mover_id >= _movers.size():
		return 0
	return _movers[mover_id]["total_moves"]


## Get total blocked (wall-hit) count for a mover.
func get_blocked_count(mover_id: int) -> int:
	if mover_id < 0 or mover_id >= _movers.size():
		return 0
	return _movers[mover_id]["blocked_count"]
