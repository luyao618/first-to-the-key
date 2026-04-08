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
