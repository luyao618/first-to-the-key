## Main Menu Screen - title screen with Play and Quit buttons.
## Builds UI dynamically from config, following ResultScreen pattern.
## See design/gdd/scene-manager.md for scene flow specification.
class_name MainMenuScreen
extends Control

# --- Configuration ---
var _title_text: String = "First to the Key"
var _play_button_text: String = "Play"
var _quit_button_text: String = "Quit"


func _ready() -> void:
	_load_config()
	_build_ui()


func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/ui_config.json")
	var menu_cfg: Dictionary = cfg.get("mainMenu", {})
	_title_text = ConfigLoader.get_or_default(menu_cfg, "titleText", _title_text)
	_play_button_text = ConfigLoader.get_or_default(menu_cfg, "playButtonText", _play_button_text)
	_quit_button_text = ConfigLoader.get_or_default(menu_cfg, "quitButtonText", _quit_button_text)


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	vbox.custom_minimum_size = Vector2(300, 0)
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = _title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "Prompt Engineering Arena"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(subtitle)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 40
	vbox.add_child(spacer)

	# Play button
	var play_btn := Button.new()
	play_btn.text = _play_button_text
	play_btn.custom_minimum_size = Vector2(200, 50)
	play_btn.pressed.connect(_on_play_pressed)
	vbox.add_child(play_btn)

	# Quit button
	var quit_btn := Button.new()
	quit_btn.text = _quit_button_text
	quit_btn.custom_minimum_size = Vector2(200, 40)
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)


# --- Button Handlers ---

func _on_play_pressed() -> void:
	SceneManagerGlobal.go_to("match")


func _on_quit_pressed() -> void:
	get_tree().quit()
