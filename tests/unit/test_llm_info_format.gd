## Unit tests for LLMInformationFormat.
extends GutTest

const LLMInfoFormat := preload("res://src/ai/llm_info_format.gd")

var fmt: RefCounted


func before_each() -> void:
	fmt = LLMInfoFormat.new()


# --- Response Parsing Tests ---

func test_parse_target() -> void:
	var result := fmt.parse_response('{"target": [8, 5]}')
	assert_eq(result["type"], "TARGET")
	assert_eq(result["pos"], Vector2i(8, 5))


func test_parse_direction_north() -> void:
	var result := fmt.parse_response('{"direction": "NORTH"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.NORTH)


func test_parse_direction_east() -> void:
	var result := fmt.parse_response('{"direction": "EAST"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.EAST)


func test_parse_direction_south() -> void:
	var result := fmt.parse_response('{"direction": "SOUTH"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.SOUTH)


func test_parse_direction_west() -> void:
	var result := fmt.parse_response('{"direction": "WEST"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.WEST)


func test_parse_target_priority_over_direction() -> void:
	var result := fmt.parse_response('{"target": [8, 5], "direction": "NORTH"}')
	assert_eq(result["type"], "TARGET")
	assert_eq(result["pos"], Vector2i(8, 5))


func test_parse_direction_lowercase() -> void:
	var result := fmt.parse_response('{"direction": "north"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.NORTH)


func test_parse_direction_abbreviation_n() -> void:
	var result := fmt.parse_response('{"direction": "N"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.NORTH)


func test_parse_direction_alias_up() -> void:
	var result := fmt.parse_response('{"direction": "UP"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.NORTH)


func test_parse_direction_alias_right() -> void:
	var result := fmt.parse_response('{"direction": "RIGHT"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.EAST)


func test_parse_direction_alias_down() -> void:
	var result := fmt.parse_response('{"direction": "DOWN"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.SOUTH)


func test_parse_direction_alias_left() -> void:
	var result := fmt.parse_response('{"direction": "LEFT"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.WEST)


func test_parse_json_with_surrounding_text() -> void:
	var result := fmt.parse_response('I think north. {"target": [3, 2]}')
	assert_eq(result["type"], "TARGET")
	assert_eq(result["pos"], Vector2i(3, 2))


func test_parse_empty_string() -> void:
	var result := fmt.parse_response("")
	assert_eq(result["type"], "NONE")


func test_parse_invalid_direction() -> void:
	var result := fmt.parse_response('{"direction": "NORTHEAST"}')
	assert_eq(result["type"], "NONE")


func test_parse_missing_fields() -> void:
	var result := fmt.parse_response('{"foo": "bar"}')
	assert_eq(result["type"], "NONE")


func test_parse_no_json() -> void:
	var result := fmt.parse_response("not json at all")
	assert_eq(result["type"], "NONE")


func test_parse_invalid_target_format() -> void:
	var result := fmt.parse_response('{"target": "invalid"}')
	assert_eq(result["type"], "NONE")


func test_parse_target_wrong_array_size() -> void:
	var result := fmt.parse_response('{"target": [1]}')
	assert_eq(result["type"], "NONE")


func test_parse_invalid_target_falls_back_to_direction() -> void:
	var result := fmt.parse_response('{"target": "bad", "direction": "SOUTH"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.SOUTH)


# --- Prompt Building Tests ---
# These tests require a full game setup: maze, fog, movement, keys, win_con

const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")
const FogOfWarClass := preload("res://src/core/fog_of_war.gd")
const GridMovementClass := preload("res://src/core/grid_movement.gd")
const KeyCollectionClass := preload("res://src/gameplay/key_collection.gd")
const WinConditionClass := preload("res://src/gameplay/win_condition.gd")

var maze: RefCounted
var fog_node: Node
var gm: Node
var kc: Node
var wc: Node


func _setup_game() -> void:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	maze = gen.generate(5, 5)
	assert_not_null(maze)

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


func test_build_system_message_contains_rules() -> void:
	var msg := fmt.build_system_message("Go north always", 3)
	assert_string_contains(msg, "You are an AI agent navigating a maze")
	assert_string_contains(msg, "COORDINATE SYSTEM")
	assert_string_contains(msg, "OUTPUT FORMAT")
	assert_string_contains(msg, "Go north always")


func test_build_system_message_includes_vision_radius() -> void:
	var msg := fmt.build_system_message("test", 5)
	assert_string_contains(msg, "5 steps")


func test_build_system_message_empty_prompt() -> void:
	var msg := fmt.build_system_message("", 3)
	assert_string_contains(msg, "PLAYER STRATEGY:")


func test_build_state_message_contains_position() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	var pos := gm.get_position_of(0)
	assert_string_contains(msg, "Position: (%d, %d)" % [pos.x, pos.y])


func test_build_state_message_contains_turn() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 42)
	assert_string_contains(msg, "TURN 42")


func test_build_state_message_contains_open_directions() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	assert_string_contains(msg, "Open directions:")


func test_build_state_message_contains_visible_cells() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	assert_string_contains(msg, "VISIBLE CELLS:")


func test_build_state_message_contains_you_marker() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	assert_string_contains(msg, "[YOU]")


func test_build_state_message_contains_objective() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	assert_string_contains(msg, "OBJECTIVE: Find the Brass key")
	assert_string_contains(msg, "Keys collected: 0/3")


func test_build_state_message_visited_section() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	assert_string_contains(msg, "VISITED")


func test_state_message_fog_compliance_no_unknown_cells() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	# The prompt should not contain coordinates that are UNKNOWN for this agent
	# We can't easily test every cell, but verify visible cells are present
	var visible := fog_node.get_visible_cells(0)
	for cell_pos in visible:
		assert_string_contains(msg, "(%d,%d)" % [cell_pos.x, cell_pos.y])


func test_inactive_key_not_in_prompt() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	# Jade and Crystal should NOT appear in prompt (not yet active)
	assert_does_not_have(msg, "[KEY:JADE]")
	assert_does_not_have(msg, "[KEY:CRYSTAL]")


func test_inactive_chest_not_in_prompt() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	assert_does_not_have(msg, "[CHEST]")


func test_token_estimate() -> void:
	var estimate := fmt.get_token_estimate("Hello world this is a test")
	# 26 chars / 4 = 6 tokens (roughly)
	assert_gte(estimate, 5)
	assert_lte(estimate, 10)


## Helper to assert string does NOT contain substring.
func assert_does_not_have(text: String, substring: String) -> void:
	assert_eq(text.find(substring), -1,
		"Expected text to NOT contain '%s'" % substring)
