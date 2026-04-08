## Unit tests for ConfigLoader utility.
extends GutTest


func test_load_json_valid_file() -> void:
	var data := ConfigLoader.load_json("res://assets/data/game_config.json")
	assert_true(data.has("maze"), "Should have 'maze' key")
	assert_true(data.has("match"), "Should have 'match' key")


func test_load_json_missing_file_returns_empty() -> void:
	var data := ConfigLoader.load_json("res://nonexistent.json")
	assert_eq(data.size(), 0, "Missing file should return empty dict")


func test_get_or_default_existing_key() -> void:
	var config := {"width": 15}
	var value = ConfigLoader.get_or_default(config, "width", 10)
	assert_eq(value, 15)


func test_get_or_default_missing_key() -> void:
	var config := {}
	var value = ConfigLoader.get_or_default(config, "width", 10)
	assert_eq(value, 10)


func test_game_config_has_expected_values() -> void:
	var data := ConfigLoader.load_json("res://assets/data/game_config.json")
	assert_eq(data["maze"]["width"], 15)
	assert_eq(data["maze"]["height"], 15)
	assert_eq(data["match"]["tick_interval"], 0.5)
	assert_eq(data["match"]["countdown_duration"], 3.0)
