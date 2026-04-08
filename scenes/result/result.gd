## Result scene root script.
## Loads ResultScreen component and populates it from Autoloads.
extends Control

const ResultScreenClass := preload("res://src/ui/result_screen.gd")

var _result_screen: Control = null


func _ready() -> void:
	_result_screen = ResultScreenClass.new()
	add_child(_result_screen)
	_result_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_screen.populate_from_autoloads()
