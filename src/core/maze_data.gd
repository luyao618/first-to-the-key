## Maze Data Model - spatial data foundation for the entire game.
## Represents a 2D grid maze with walls, markers, and pathfinding.
## See design/gdd/maze-data-model.md for full specification.
class_name MazeData
extends RefCounted

## Grid dimensions.
var width: int
var height: int

## Internal cell storage. Access as _cells[y][x].
## Each cell is a Dictionary: { "walls": {dir: bool}, "markers": Array[Enums.MarkerType] }
var _cells: Array[Array] = []

## Whether the maze is finalized (write-locked).
var _finalized: bool = false

## Marker position cache: MarkerType -> Vector2i.
var _marker_positions: Dictionary = {}


func _init(w: int, h: int) -> void:
	width = w
	height = h
	_init_cells()


## Initialize all cells with four walls and no markers.
func _init_cells() -> void:
	_cells.clear()
	_marker_positions.clear()
	for y in range(height):
		var row: Array[Dictionary] = []
		for x in range(width):
			row.append({
				"walls": {
					Enums.Direction.NORTH: true,
					Enums.Direction.EAST: true,
					Enums.Direction.SOUTH: true,
					Enums.Direction.WEST: true,
				},
				"markers": [] as Array[int],
			})
		_cells.append(row)


## Returns the cell dictionary at (x, y), or null if out of bounds.
func get_cell(x: int, y: int) -> Variant:
	if x < 0 or x >= width or y < 0 or y >= height:
		push_warning("MazeData: get_cell(%d, %d) out of bounds (size %dx%d)" % [x, y, width, height])
		return null
	return _cells[y][x]


## Returns true if the specified wall exists.
func has_wall(x: int, y: int, direction: int) -> bool:
	var cell = get_cell(x, y)
	if cell == null:
		return true  # Out of bounds treated as walled
	return cell["walls"][direction]


## Returns true if movement in the given direction is possible (no wall).
func can_move(x: int, y: int, direction: int) -> bool:
	return not has_wall(x, y, direction)


## Returns coordinates of all passable neighbors.
func get_neighbors(x: int, y: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in [Enums.Direction.NORTH, Enums.Direction.EAST, Enums.Direction.SOUTH, Enums.Direction.WEST]:
		if can_move(x, y, dir):
			var offset: Vector2i = Enums.DIRECTION_OFFSETS[dir]
			result.append(Vector2i(x + offset.x, y + offset.y))
	return result


## Returns all markers at the given position.
func get_markers_at(x: int, y: int) -> Array:
	var cell = get_cell(x, y)
	if cell == null:
		return []
	return cell["markers"].duplicate()


## Returns the position of a marker type, or Vector2i(-1, -1) if not placed.
func get_marker_position(marker_type: int) -> Vector2i:
	if _marker_positions.has(marker_type):
		return _marker_positions[marker_type]
	return Vector2i(-1, -1)


## Check if a wall is on the maze boundary.
func _is_boundary_wall(x: int, y: int, direction: int) -> bool:
	match direction:
		Enums.Direction.NORTH: return y == 0
		Enums.Direction.SOUTH: return y == height - 1
		Enums.Direction.WEST: return x == 0
		Enums.Direction.EAST: return x == width - 1
	return false


## Set wall state, syncing the shared wall on the neighbor cell.
## Boundary walls cannot be removed (silently enforced).
func set_wall(x: int, y: int, direction: int, value: bool) -> void:
	if _finalized:
		push_error("MazeData is finalized, write operation rejected")
		return

	var cell = get_cell(x, y)
	if cell == null:
		return

	# Boundary walls are always true - ignore attempts to remove them
	if not value and _is_boundary_wall(x, y, direction):
		return

	cell["walls"][direction] = value

	# Sync the neighbor's corresponding wall
	var offset: Vector2i = Enums.DIRECTION_OFFSETS[direction]
	var nx := x + offset.x
	var ny := y + offset.y
	var neighbor = get_cell(nx, ny)
	if neighbor != null:
		var opposite_dir: int = Enums.OPPOSITE_DIRECTION[direction]
		neighbor["walls"][opposite_dir] = value
