## Unit tests for SceneManager.
extends GutTest

var sm: Node


func before_each() -> void:
	sm = load("res://src/core/scene_manager.gd").new()
	add_child_autoqfree(sm)
	# Manually call initialization since we're not using autoload
	sm._initialize_registry()


func test_registry_loaded_from_config() -> void:
	assert_true(sm._registry.has("match"), "Registry should have 'match'")
	assert_true(sm._registry.has("result"), "Registry should have 'result'")


func test_go_to_nonexistent_scene_stays() -> void:
	sm.go_to("nonexistent")
	# Should log error but not crash
	assert_eq(sm.current_scene_name, "", "Should remain empty")
	assert_push_error_count(1)


func test_scene_changing_signal_emitted() -> void:
	watch_signals(sm)
	sm.go_to("match")
	# In test environment without SceneTree, we check signal emission
	assert_signal_emitted(sm, "scene_changing")


func test_switching_state_blocks_reentrant_calls() -> void:
	sm._switching = true
	watch_signals(sm)
	sm.go_to("match")
	assert_signal_not_emitted(sm, "scene_changing")


func test_fallback_registry_when_config_missing() -> void:
	# Create a fresh instance with no file
	var sm2: Node = load("res://src/core/scene_manager.gd").new()
	add_child_autoqfree(sm2)
	sm2._config_path = "res://nonexistent_path.json"
	sm2._initialize_registry()
	# Should have fallback entries
	assert_true(sm2._registry.has("match"))
	assert_true(sm2._registry.has("result"))
	assert_push_error_count(2)  # File not found + fallback warning
