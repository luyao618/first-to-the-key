## Scene Manager - manages top-level scene switching.
## Autoload singleton registered as "SceneManagerGlobal".
## See design/gdd/scene-manager.md for full specification.
extends Node

const ConfigLoader = preload("res://src/shared/config_loader.gd")

# --- Signals ---
signal scene_changing(old_name: String, new_name: String)
signal scene_changed(new_name: String)

# --- State ---
var current_scene_name: String = ""
var _switching: bool = false

# --- Internal ---
var _registry: Dictionary = {}  # scene_name -> PackedScene
var _config_path: String = "res://assets/data/scene_registry.json"
var _initial_scene: String = "match"

## Fallback registry used when config file is missing.
const FALLBACK_REGISTRY: Dictionary = {
	"match": "res://scenes/match/Match.tscn",
	"result": "res://scenes/result/Result.tscn",
}


func _ready() -> void:
	_load_game_config()
	_initialize_registry()
	# Note: Do NOT call go_to() here — Godot's main_scene in project.godot
	# already loads the initial scene. SceneManager only handles subsequent
	# scene transitions (e.g. match → result, result → match via Rematch).


func _load_game_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/game_config.json")
	var scene_cfg: Dictionary = cfg.get("scene", {})
	_initial_scene = ConfigLoader.get_or_default(scene_cfg, "initial_scene", "match")
	_config_path = ConfigLoader.get_or_default(scene_cfg, "config_file_path", "res://assets/data/scene_registry.json")


## Load scene registry from config and eager-cache all PackedScenes.
func _initialize_registry() -> void:
	_registry.clear()

	var config := ConfigLoader.load_json(_config_path)
	if config.is_empty():
		push_error("SceneManager: Config file missing or empty, using fallback registry")
		config = FALLBACK_REGISTRY

	for scene_name in config:
		var path: String = config[scene_name]
		if not ResourceLoader.exists(path):
			push_error("SceneManager: Failed to preload scene '%s' at path '%s'" % [scene_name, path])
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("SceneManager: Failed to load PackedScene at '%s'" % path)
			continue
		_registry[scene_name] = packed


## Switch to a named scene.
func go_to(scene_name: String) -> void:
	if _switching:
		push_warning("SceneManager: Scene switch already in progress, ignoring go_to('%s')" % scene_name)
		return

	if not _registry.has(scene_name):
		push_error("SceneManager: Scene not found in registry: '%s'" % scene_name)
		return

	_switching = true
	var old_name := current_scene_name
	scene_changing.emit(old_name, scene_name)

	var packed: PackedScene = _registry[scene_name]
	get_tree().change_scene_to_packed(packed)

	current_scene_name = scene_name
	_switching = false

	# Emit scene_changed after tree settles
	call_deferred("_emit_scene_changed", scene_name)


func _emit_scene_changed(scene_name: String) -> void:
	scene_changed.emit(scene_name)
