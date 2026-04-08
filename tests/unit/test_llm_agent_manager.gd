## Unit tests for LLMAgentManager.
## Tests focus on path queue, auto-advance, and decision point detection.
## API integration tests are separate (they mock HTTP responses).
extends GutTest

const LLMAgentClass := preload("res://src/ai/llm_agent_manager.gd")
const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")
const FogOfWarClass := preload("res://src/core/fog_of_war.gd")
const GridMovementClass := preload("res://src/core/grid_movement.gd")
const KeyCollectionClass := preload("res://src/gameplay/key_collection.gd")
const WinConditionClass := preload("res://src/gameplay/win_condition.gd")
const LLMInfoFormat := preload("res://src/ai/llm_info_format.gd")

var mgr: Node
var maze: RefCounted
var fog_node: Node
var gm: Node
var kc: Node
var wc: Node


func before_each() -> void:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	maze = gen.generate(5, 5)
	assert_not_null(maze, "Test maze should generate")

	fog_node = FogOfWarClass.new()
	add_child_autoqfree(fog_node)
	fog_node.initialize(maze, [0, 1])

	gm = GridMovementClass.new()
	gm.maze = maze
	gm.fog = fog_node
	add_child_autoqfree(gm)
	gm.initialize()

	kc = KeyCollectionClass.new()
	add_child_autoqfree(kc)
	kc.initialize(maze)
	kc.set_active(true)

	wc = WinConditionClass.new()
	add_child_autoqfree(wc)
	wc.initialize(maze)

	mgr = LLMAgentClass.new()
	add_child_autoqfree(mgr)
	mgr.maze = maze
	mgr.movement = gm
	mgr.fog = fog_node
	mgr.keys = kc
	mgr.win_condition = wc
	mgr.initialize()


# --- Decision Point Detection ---

func test_is_decision_point_intersection() -> void:
	# Find an intersection in the maze (cell with 3+ open directions)
	var found := false
	for y in range(maze.height):
		for x in range(maze.width):
			var neighbors := maze.get_neighbors(x, y)
			if neighbors.size() >= 3:
				# It's an intersection regardless of last_dir
				assert_true(mgr._is_decision_point(Vector2i(x, y), Enums.MoveDirection.NORTH))
				found = true
				break
		if found:
			break
	if not found:
		pass_test("No intersection found in 5x5 maze (possible for perfect maze)")


func test_is_decision_point_dead_end() -> void:
	# Find a dead end (cell with only 1 open direction)
	for y in range(maze.height):
		for x in range(maze.width):
			var neighbors := maze.get_neighbors(x, y)
			if neighbors.size() == 1:
				assert_true(mgr._is_decision_point(Vector2i(x, y), Enums.MoveDirection.NORTH))
				return
	pass_test("No dead end found in maze")


func test_is_not_decision_point_straight() -> void:
	# Find a straight corridor (cell with exactly 2 open directions that are opposite)
	for y in range(maze.height):
		for x in range(maze.width):
			var open_dirs: Array[int] = []
			for dir in [Enums.Direction.NORTH, Enums.Direction.EAST, Enums.Direction.SOUTH, Enums.Direction.WEST]:
				if maze.can_move(x, y, dir):
					open_dirs.append(dir)
			if open_dirs.size() == 2:
				# Use one direction as last_dir, the other should be auto-advance
				var last_move := _dir_to_move_dir(open_dirs[0])
				var reverse := Enums.OPPOSITE_MOVE_DIRECTION[last_move]
				# If the other open direction is the reverse, it's a corridor
				var other_move := _dir_to_move_dir(open_dirs[1])
				if other_move == reverse:
					# Coming from open_dirs[0], only exit is open_dirs[1] (reverse = last_dir's opposite)
					# Actually this is straight: exclude last_dir's reverse, 1 forward option
					assert_false(mgr._is_decision_point(Vector2i(x, y), last_move),
						"Straight corridor should not be a decision point")
					return
	pass_test("No straight corridor found")


# --- Auto-Advance ---

func test_get_auto_direction_straight() -> void:
	# Find a cell that is a straight corridor
	for y in range(maze.height):
		for x in range(maze.width):
			var open_dirs: Array[int] = []
			for dir in [Enums.Direction.NORTH, Enums.Direction.EAST, Enums.Direction.SOUTH, Enums.Direction.WEST]:
				if maze.can_move(x, y, dir):
					open_dirs.append(dir)
			if open_dirs.size() == 2:
				var move_dir_0 := _dir_to_move_dir(open_dirs[0])
				var move_dir_1 := _dir_to_move_dir(open_dirs[1])
				# If coming from direction 0, auto should go direction 1
				var result := mgr._get_auto_direction(Vector2i(x, y), move_dir_0)
				# The auto direction should be the other open direction (not the reverse of last_dir)
				var reverse_of_0 := Enums.OPPOSITE_MOVE_DIRECTION[move_dir_0]
				if move_dir_1 != reverse_of_0:
					assert_eq(result, move_dir_1)
				else:
					# move_dir_1 IS the reverse, meaning there's no forward direction
					assert_eq(result, Enums.MoveDirection.NONE)
				return
	pass_test("No straight corridor found")


func test_get_auto_direction_none_at_decision_point() -> void:
	# At a decision point, auto direction should be NONE
	for y in range(maze.height):
		for x in range(maze.width):
			var neighbors := maze.get_neighbors(x, y)
			if neighbors.size() >= 3:
				var result := mgr._get_auto_direction(Vector2i(x, y), Enums.MoveDirection.NORTH)
				assert_eq(result, Enums.MoveDirection.NONE)
				return
	pass_test("No intersection found")


# --- Path Queue ---

func test_replace_queue_generates_directions() -> void:
	var brain := mgr.get_brain(0)
	var pos := gm.get_position_of(0)
	# Find a reachable target
	var target := _find_reachable_target(pos)
	if target == Vector2i(-1, -1):
		pass_test("No reachable target found")
		return
	mgr._replace_queue(brain, target)
	assert_gt(brain["path_queue"].size(), 0, "Queue should have directions")


func test_replace_queue_same_position_clears() -> void:
	var brain := mgr.get_brain(0)
	var pos := gm.get_position_of(0)
	mgr._replace_queue(brain, pos)
	assert_eq(brain["path_queue"].size(), 0, "Same position should clear queue")


func test_replace_queue_truncates_at_max() -> void:
	var brain := mgr.get_brain(0)
	brain["max_queue_length"] = 3
	var pos := gm.get_position_of(0)
	# Find a distant target
	var target := _find_distant_target(pos, 5)
	if target == Vector2i(-1, -1):
		pass_test("No distant target found")
		return
	mgr._replace_queue(brain, target)
	assert_lte(brain["path_queue"].size(), 3, "Queue should be truncated to max_queue_length")


func test_consume_queue_pops_front() -> void:
	var brain := mgr.get_brain(0)
	brain["path_queue"] = [Enums.MoveDirection.NORTH, Enums.MoveDirection.EAST] as Array[int]
	var dir := mgr._consume_queue(brain)
	assert_eq(dir, Enums.MoveDirection.NORTH)
	assert_eq(brain["path_queue"].size(), 1)


func test_consume_empty_queue_returns_none() -> void:
	var brain := mgr.get_brain(0)
	brain["path_queue"].clear()
	var dir := mgr._consume_queue(brain)
	assert_eq(dir, Enums.MoveDirection.NONE)


# --- Brain State ---

func test_initial_brain_state() -> void:
	var brain := mgr.get_brain(0)
	assert_eq(brain["agent_id"], 0)
	assert_eq(brain["path_queue"].size(), 0)
	assert_eq(brain["last_move_direction"], Enums.MoveDirection.NONE)
	assert_eq(brain["request_state"], Enums.RequestState.IDLE)
	assert_eq(brain["total_api_calls"], 0)
	assert_eq(brain["total_idle_ticks"], 0)


func test_get_brain_invalid_id() -> void:
	var brain := mgr.get_brain(99)
	assert_null(brain)


func test_reset_clears_brains() -> void:
	mgr.reset()
	assert_eq(mgr._brains.size(), 0)


# --- Helpers ---

func _dir_to_move_dir(dir: int) -> int:
	match dir:
		Enums.Direction.NORTH: return Enums.MoveDirection.NORTH
		Enums.Direction.EAST: return Enums.MoveDirection.EAST
		Enums.Direction.SOUTH: return Enums.MoveDirection.SOUTH
		Enums.Direction.WEST: return Enums.MoveDirection.WEST
	return Enums.MoveDirection.NONE


func _find_reachable_target(from: Vector2i) -> Vector2i:
	# Find any cell reachable from 'from' that isn't 'from'
	for y in range(maze.height):
		for x in range(maze.width):
			var target := Vector2i(x, y)
			if target != from:
				var path := maze.get_shortest_path(from, target)
				if path.size() >= 2:
					return target
	return Vector2i(-1, -1)


func _find_distant_target(from: Vector2i, min_dist: int) -> Vector2i:
	for y in range(maze.height):
		for x in range(maze.width):
			var target := Vector2i(x, y)
			if target != from:
				var path := maze.get_shortest_path(from, target)
				if path.size() > min_dist:
					return target
	return Vector2i(-1, -1)
