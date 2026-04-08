## Utility for loading JSON configuration files with fallback defaults.
class_name ConfigLoader
extends RefCounted


## Load a JSON file and return parsed Dictionary.
## Returns empty Dictionary on failure and prints error.
static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ConfigLoader: File not found: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ConfigLoader: Cannot open file: %s" % path)
		return {}

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		push_error("ConfigLoader: JSON parse error in %s at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}

	var result = json.data
	if result is Dictionary:
		return result

	push_error("ConfigLoader: Expected Dictionary at root of %s, got %s" % [path, typeof(result)])
	return {}


## Get a value from a dictionary with a default fallback.
## Prints a warning if the key is missing.
static func get_or_default(config: Dictionary, key: String, default_value: Variant) -> Variant:
	if config.has(key):
		return config[key]
	push_warning("ConfigLoader: Key '%s' missing from config, using default: %s" % [key, str(default_value)])
	return default_value
