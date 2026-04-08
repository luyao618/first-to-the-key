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
	gen._config_loaded = true
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
			var neighbors: Array[Vector2i] = maze.get_neighbors(x, y)
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
			var neighbors: Array[Vector2i] = maze.get_neighbors(x, y)
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
				var last_move: int = _dir_to_move_dir(open_dirs[0])
				var reverse: int = Enums.OPPOSITE_MOVE_DIRECTION[last_move]
				# If the other open direction is the reverse, it's a corridor
				var other_move: int = _dir_to_move_dir(open_dirs[1])
				if other_move == reverse:
					# Coming from open_dirs[0], only exit is open_dirs[1] (reverse = last_dir's opposite)
					# Actually this is straight: exclude last_dir's reverse, 1 forward option
					assert_false(mgr._is_decision_point(Vector2i(x, y), last_move),
						"Straight corridor should not be a decision point")
					return
	pass_test("No straight corridor found")


# --- Auto-Advance ---

func test_get_auto_direction_straight() -> void:
	# Find a cell that is a straight corridor (2 open dirs that are opposites)
	# and verify auto-advance continues forward
	for y in range(maze.height):
		for x in range(maze.width):
			var open_dirs: Array[int] = []
			for dir in [Enums.Direction.NORTH, Enums.Direction.EAST, Enums.Direction.SOUTH, Enums.Direction.WEST]:
				if maze.can_move(x, y, dir):
					open_dirs.append(dir)
			if open_dirs.size() == 2:
				# Use one open dir as last_dir: "I was moving in this direction"
				var last_move: int = _dir_to_move_dir(open_dirs[0])
				var reverse_of_last: int = Enums.OPPOSITE_MOVE_DIRECTION[last_move]
				# Forward = open dirs minus reverse of last_move
				var forward_dirs: Array[int] = []
				for od in open_dirs:
					var md: int = _dir_to_move_dir(od)
					if md != reverse_of_last:
						forward_dirs.append(md)
				var result: int = mgr._get_auto_direction(Vector2i(x, y), last_move)
				if forward_dirs.size() == 1:
					assert_eq(result, forward_dirs[0],
						"Straight corridor should auto-advance forward")
				else:
					assert_eq(result, Enums.MoveDirection.NONE)
				return
	pass_test("No straight corridor found")


func test_get_auto_direction_none_at_decision_point() -> void:
	# At a decision point, auto direction should be NONE
	for y in range(maze.height):
		for x in range(maze.width):
			var neighbors: Array[Vector2i] = maze.get_neighbors(x, y)
			if neighbors.size() >= 3:
				var result: int = mgr._get_auto_direction(Vector2i(x, y), Enums.MoveDirection.NORTH)
				assert_eq(result, Enums.MoveDirection.NONE)
				return
	pass_test("No intersection found")


# --- Path Queue ---

func test_replace_queue_generates_directions() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	var pos: Vector2i = gm.get_position_of(0)
	# Find a reachable target
	var target := _find_reachable_target(pos)
	if target == Vector2i(-1, -1):
		pass_test("No reachable target found")
		return
	mgr._replace_queue(brain, target)
	assert_gt(brain["path_queue"].size(), 0, "Queue should have directions")


func test_replace_queue_same_position_clears() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	var pos: Vector2i = gm.get_position_of(0)
	mgr._replace_queue(brain, pos)
	assert_eq(brain["path_queue"].size(), 0, "Same position should clear queue")


func test_replace_queue_truncates_at_max() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	brain["max_queue_length"] = 3
	var pos: Vector2i = gm.get_position_of(0)
	# Find a distant target
	var target := _find_distant_target(pos, 5)
	if target == Vector2i(-1, -1):
		pass_test("No distant target found")
		return
	mgr._replace_queue(brain, target)
	assert_lte(brain["path_queue"].size(), 3, "Queue should be truncated to max_queue_length")


func test_consume_queue_pops_front() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	brain["path_queue"] = [Enums.MoveDirection.NORTH, Enums.MoveDirection.EAST] as Array[int]
	var dir: int = mgr._consume_queue(brain)
	assert_eq(dir, Enums.MoveDirection.NORTH)
	assert_eq(brain["path_queue"].size(), 1)


func test_consume_empty_queue_returns_none() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	brain["path_queue"].clear()
	var dir: int = mgr._consume_queue(brain)
	assert_eq(dir, Enums.MoveDirection.NONE)


# --- Brain State ---

func test_initial_brain_state() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	assert_eq(brain["agent_id"], 0)
	assert_eq(brain["path_queue"].size(), 0)
	assert_eq(brain["last_move_direction"], Enums.MoveDirection.NONE)
	assert_eq(brain["request_state"], Enums.RequestState.IDLE)
	assert_eq(brain["total_api_calls"], 0)
	assert_eq(brain["total_idle_ticks"], 0)


func test_get_brain_invalid_id() -> void:
	var brain: Variant = mgr.get_brain(99)
	assert_null(brain)


func test_reset_clears_brains() -> void:
	mgr.reset()
	assert_eq(mgr._brains.size(), 0)


# --- API Response Handling ---

func test_handle_target_response_generates_queue() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	var pos: Vector2i = gm.get_position_of(0)
	var target := _find_reachable_target(pos)
	if target == Vector2i(-1, -1):
		pass_test("No reachable target")
		return
	# Make target visible/explored
	fog_node.update_vision(0, pos)
	var vis: int = fog_node.get_cell_visibility(0, target.x, target.y)
	if vis == Enums.CellVisibility.UNKNOWN:
		# Move closer so target is visible
		pass_test("Target not visible - skip")
		return

	brain["pending_response"] = '{"target": [%d, %d]}' % [target.x, target.y]
	mgr._handle_api_response(brain, brain["pending_response"])
	assert_gt(brain["path_queue"].size(), 0, "Should generate path queue")


func test_handle_direction_response_single_step() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	brain["pending_response"] = '{"direction": "EAST"}'
	mgr._handle_api_response(brain, brain["pending_response"])
	assert_eq(brain["path_queue"].size(), 1)
	assert_eq(brain["path_queue"][0], Enums.MoveDirection.EAST)


func test_handle_none_response_no_queue_change() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	brain["path_queue"] = [Enums.MoveDirection.NORTH] as Array[int]
	mgr._handle_api_response(brain, "invalid response")
	assert_eq(brain["path_queue"].size(), 1, "NONE should not clear existing queue")


# --- Target Validation ---

func test_validate_target_out_of_bounds() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	assert_false(mgr._validate_target(brain, Vector2i(-1, 0)))
	assert_false(mgr._validate_target(brain, Vector2i(maze.width, 0)))
	assert_false(mgr._validate_target(brain, Vector2i(0, maze.height)))


func test_validate_target_unknown_cell() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	# Find a cell that's UNKNOWN for agent 0
	for y in range(maze.height):
		for x in range(maze.width):
			if fog_node.get_cell_visibility(0, x, y) == Enums.CellVisibility.UNKNOWN:
				assert_false(mgr._validate_target(brain, Vector2i(x, y)),
					"Unknown cell should be rejected")
				return
	pass_test("All cells visible (small maze)")


func test_validate_target_current_position() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	var pos: Vector2i = gm.get_position_of(0)
	assert_false(mgr._validate_target(brain, pos), "Current position should be rejected")


func test_validate_target_visible_cell_accepted() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	var pos: Vector2i = gm.get_position_of(0)
	var visible: Array[Vector2i] = fog_node.get_visible_cells(0)
	for v in visible:
		if v != pos:
			assert_true(mgr._validate_target(brain, v),
				"Visible cell should be accepted")
			return
	pass_test("No visible cell other than current position")


# --- Tick Processing ---

func test_first_tick_idle_no_api_key() -> void:
	# Without API key, first tick should still track idle
	var brain: Dictionary = mgr.get_brain(0)
	mgr._active = true
	mgr._process_brain_tick(brain, 1)
	assert_eq(brain["total_idle_ticks"], 1)


func test_tick_consumes_queue() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	brain["last_move_direction"] = Enums.MoveDirection.EAST  # Not first tick
	var pos: Vector2i = gm.get_position_of(0)
	# Find a valid direction
	var valid_dir := Enums.MoveDirection.NONE
	for dir in [Enums.MoveDirection.EAST, Enums.MoveDirection.SOUTH]:
		var maze_dir: int
		match dir:
			Enums.MoveDirection.EAST: maze_dir = Enums.Direction.EAST
			Enums.MoveDirection.SOUTH: maze_dir = Enums.Direction.SOUTH
		if maze.can_move(pos.x, pos.y, maze_dir):
			valid_dir = dir
			break
	if valid_dir == Enums.MoveDirection.NONE:
		pass_test("No valid direction from spawn")
		return

	brain["path_queue"] = [valid_dir] as Array[int]
	mgr._active = true
	mgr._process_brain_tick(brain, 1)
	assert_eq(brain["path_queue"].size(), 0, "Queue should be consumed")


# --- Statistics ---

func test_statistics_reset() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	brain["total_api_calls"] = 5
	brain["total_tokens_used"] = 1000
	brain["total_idle_ticks"] = 10
	mgr.reset()
	mgr.initialize()
	brain = mgr.get_brain(0)
	assert_eq(brain["total_api_calls"], 0)
	assert_eq(brain["total_tokens_used"], 0)
	assert_eq(brain["total_idle_ticks"], 0)


func test_get_api_call_count() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	brain["total_api_calls"] = 42
	assert_eq(mgr.get_api_call_count(0), 42)


func test_get_idle_tick_count() -> void:
	var brain: Dictionary = mgr.get_brain(0)
	brain["total_idle_ticks"] = 7
	assert_eq(mgr.get_idle_tick_count(0), 7)


func test_get_api_call_count_invalid_id() -> void:
	assert_eq(mgr.get_api_call_count(99), 0)


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
				var path: Array[Vector2i] = maze.get_shortest_path(from, target)
				if path.size() >= 2:
					return target
	return Vector2i(-1, -1)


func _find_distant_target(from: Vector2i, min_dist: int) -> Vector2i:
	for y in range(maze.height):
		for x in range(maze.width):
			var target := Vector2i(x, y)
			if target != from:
				var path: Array[Vector2i] = maze.get_shortest_path(from, target)
				if path.size() > min_dist:
					return target
	return Vector2i(-1, -1)
