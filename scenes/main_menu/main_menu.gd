## Main Menu scene root script.
## Loads MainMenuScreen component for title screen display.
extends Control

const MainMenuScreenClass := preload("res://src/ui/main_menu_screen.gd")

var _screen: Control = null


func _ready() -> void:
	_screen = MainMenuScreenClass.new()
	add_child(_screen)
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
