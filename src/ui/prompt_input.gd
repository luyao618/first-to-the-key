## Prompt Input - SETUP phase prompt collection UI.
## Manages sequential P1->P2 prompt entry in the Match scene's left/right columns.
## See design/gdd/prompt-input.md for full specification.
class_name PromptInput
extends Control

enum InputState { PLAYER_A_INPUT, PLAYER_B_INPUT, COMPLETED }

signal prompts_submitted(prompt_a: String, prompt_b: String)

var _state: int = InputState.PLAYER_A_INPUT
var _prompt_a: String = ""
var _prompt_b: String = ""

# --- Config ---
var _placeholder_text: String = "Explore unvisited directions first. When at a fork, prefer directions you haven't been to. If you see a key, go to it immediately. Avoid revisiting dead ends."
var _text_edit_min_lines: int = 8
var _show_char_count: bool = true

# --- UI Nodes (created dynamically) ---
var _left_container: VBoxContainer = null
var _right_container: VBoxContainer = null
var _text_edit: TextEdit = null
var _ready_button: Button = null
var _char_label: Label = null
var _status_label: Label = null


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/ui_config.json")
	var pi_cfg: Dictionary = cfg.get("prompt_input", {})
	_placeholder_text = ConfigLoader.get_or_default(pi_cfg, "placeholder_text", _placeholder_text)
	_text_edit_min_lines = ConfigLoader.get_or_default(pi_cfg, "text_edit_min_lines", 8)
	_show_char_count = ConfigLoader.get_or_default(pi_cfg, "show_char_count", true)


## Initialize UI nodes. Called after adding to scene tree with panel references.
func _initialize_ui() -> void:
	_state = InputState.PLAYER_A_INPUT
	_prompt_a = ""
	_prompt_b = ""


# --- State Machine ---

func get_state() -> int:
	return _state


func get_prompt_a() -> String:
	return _prompt_a


func get_prompt_b() -> String:
	return _prompt_b


func submit_prompt_a(prompt: String) -> void:
	if _state != InputState.PLAYER_A_INPUT:
		return
	_prompt_a = prompt
	_state = InputState.PLAYER_B_INPUT


func submit_prompt_b(prompt: String) -> void:
	if _state != InputState.PLAYER_B_INPUT:
		return
	_prompt_b = prompt
	_state = InputState.COMPLETED
	prompts_submitted.emit(_prompt_a, _prompt_b)


func reset_input() -> void:
	_state = InputState.PLAYER_A_INPUT
	_prompt_a = ""
	_prompt_b = ""


## Build UI for current state into the given left/right panel containers.
func build_ui(left_panel: Control, right_panel: Control) -> void:
	_clear_panels(left_panel, right_panel)

	match _state:
		InputState.PLAYER_A_INPUT:
			_build_input_panel(left_panel, "Player 1", func(text: String) -> void: submit_prompt_a(text); build_ui(left_panel, right_panel))
			_build_waiting_panel(right_panel, "Waiting for Player 1...")
		InputState.PLAYER_B_INPUT:
			_build_ready_panel(left_panel, "Player 1 Ready")
			_build_input_panel(right_panel, "Player 2", func(text: String) -> void: submit_prompt_b(text))
		InputState.COMPLETED:
			_build_ready_panel(left_panel, "Player 1 Ready")
			_build_ready_panel(right_panel, "Player 2 Ready")


func _build_input_panel(container: Control, title: String, on_submit: Callable) -> void:
	var vbox := VBoxContainer.new()
	container.add_child(vbox)

	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	var text_edit := TextEdit.new()
	text_edit.placeholder_text = _placeholder_text
	text_edit.custom_minimum_size.y = _text_edit_min_lines * 20
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(text_edit)

	if _show_char_count:
		var char_label := Label.new()
		char_label.text = "0 characters"
		char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		text_edit.text_changed.connect(func() -> void: char_label.text = "%d characters" % text_edit.text.length())
		vbox.add_child(char_label)

	var button := Button.new()
	button.text = "Ready"
	button.pressed.connect(func() -> void: on_submit.call(text_edit.text))
	vbox.add_child(button)


func _build_waiting_panel(container: Control, message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(label)


func _build_ready_panel(container: Control, message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(label)


func _clear_panels(left: Control, right: Control) -> void:
	for child in left.get_children():
		child.queue_free()
	for child in right.get_children():
		child.queue_free()
