## Result Screen - displays match results, statistics, and prompts.
## Independent scene loaded by SceneManager after FINISHED state.
## See design/gdd/result-screen.md for full specification.
class_name ResultScreen
extends Control

# --- Configuration ---
var _panel_ratio: float = 0.20
var _result_title_font_size: int = 48
var _stat_font_size: int = 16
var _prompt_max_visible_lines: int = 6
var _winner_color_a: Color = Color("#4488FF")
var _winner_color_b: Color = Color("#FF4444")
var _draw_color: Color = Color("#AAAAAA")


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var ui_cfg := ConfigLoader.load_json("res://assets/data/ui_config.json")
	var layout_cfg: Dictionary = ui_cfg.get("layout", {})
	_panel_ratio = ConfigLoader.get_or_default(layout_cfg, "panel_ratio", 0.20)

	var result_cfg: Dictionary = ui_cfg.get("result", {})
	_result_title_font_size = ConfigLoader.get_or_default(result_cfg, "result_title_font_size", 48)
	_stat_font_size = ConfigLoader.get_or_default(result_cfg, "stat_font_size", 16)
	_prompt_max_visible_lines = ConfigLoader.get_or_default(result_cfg, "prompt_max_visible_lines", 6)
	_winner_color_a = Color(ConfigLoader.get_or_default(result_cfg, "winner_color_a", "#4488FF"))
	_winner_color_b = Color(ConfigLoader.get_or_default(result_cfg, "winner_color_b", "#FF4444"))
	_draw_color = Color(ConfigLoader.get_or_default(result_cfg, "draw_color", "#AAAAAA"))


# --- Data Formatting ---

## Get the result title text for a given match result.
func get_result_title(match_result: int) -> String:
	match match_result:
		Enums.MatchResult.PLAYER_A_WIN: return "Player 1 Wins!"
		Enums.MatchResult.PLAYER_B_WIN: return "Player 2 Wins!"
		Enums.MatchResult.DRAW: return "Draw!"
	return "No Result"


## Get the result color for a given match result.
func get_result_color(match_result: int) -> Color:
	match match_result:
		Enums.MatchResult.PLAYER_A_WIN: return _winner_color_a
		Enums.MatchResult.PLAYER_B_WIN: return _winner_color_b
		Enums.MatchResult.DRAW: return _draw_color
	return Color.WHITE


## Get agent status text ("Winner" / "Defeated" / "Draw").
func get_agent_status(agent_id: int, match_result: int, match_winner_id: int) -> String:
	if match_result == Enums.MatchResult.DRAW:
		return "Draw"
	if agent_id == match_winner_id:
		return "Winner"
	return "Defeated"


## Calculate idle rate as percentage. Returns 0.0 if tick_count is 0.
func calculate_idle_rate(idle_ticks: int, tick_count: int) -> float:
	if tick_count == 0:
		return 0.0
	return float(idle_ticks) / float(tick_count) * 100.0


## Format elapsed time as "M:SS".
func format_elapsed_time(elapsed: float) -> String:
	var total_seconds := int(elapsed)
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	return "%d:%02d" % [minutes, seconds]


## Get keys progress string from AgentKeyState.
func get_keys_string(agent_state: int) -> String:
	match agent_state:
		Enums.AgentKeyState.NEED_BRASS: return "0/3"
		Enums.AgentKeyState.NEED_JADE: return "1/3"
		Enums.AgentKeyState.NEED_CRYSTAL: return "2/3"
		Enums.AgentKeyState.KEYS_COMPLETE: return "3/3"
	return "0/3"


## Get prompt display text ("(empty)" if blank).
func get_prompt_display(prompt: String) -> String:
	if prompt.strip_edges().is_empty():
		return "(empty)"
	return prompt


# --- UI Building ---

## Populate the result screen with data from Autoloads.
## Called from result.gd _ready().
func populate_from_autoloads() -> void:
	# Read from MatchStateManager
	var match_result: int = MatchStateManager.result
	var match_winner_id: int = MatchStateManager.winner_id
	var prompt_a: String = MatchStateManager.config.get("prompt_a", "")
	var prompt_b: String = MatchStateManager.config.get("prompt_b", "")
	var tick_count: int = MatchStateManager.tick_count
	var elapsed_time: float = MatchStateManager.get_elapsed_time()

	# Read from LLMAgentManager (defensive: may not exist)
	var api_calls_a: int = 0
	var api_calls_b: int = 0
	var tokens_a: int = 0
	var tokens_b: int = 0
	var idle_a: int = 0
	var idle_b: int = 0

	if LLMAgentManager != null:
		var brain_a: Variant = LLMAgentManager.get_brain(0)
		var brain_b: Variant = LLMAgentManager.get_brain(1)
		if brain_a != null:
			api_calls_a = brain_a.get("total_api_calls", 0)
			tokens_a = brain_a.get("total_tokens_used", 0)
			idle_a = brain_a.get("total_idle_ticks", 0)
		if brain_b != null:
			api_calls_b = brain_b.get("total_api_calls", 0)
			tokens_b = brain_b.get("total_tokens_used", 0)
			idle_b = brain_b.get("total_idle_ticks", 0)

	# Read from KeyCollection (defensive: may not exist)
	var keys_a: int = Enums.AgentKeyState.NEED_BRASS
	var keys_b: int = Enums.AgentKeyState.NEED_BRASS
	if KeyCollection != null:
		keys_a = KeyCollection.get_agent_progress(0)
		keys_b = KeyCollection.get_agent_progress(1)

	# Build UI
	_build_result_ui(
		match_result, match_winner_id,
		prompt_a, prompt_b,
		tick_count, elapsed_time,
		api_calls_a, tokens_a, idle_a,
		api_calls_b, tokens_b, idle_b,
		keys_a, keys_b
	)


func _build_result_ui(
	match_result: int, match_winner_id: int,
	prompt_a: String, prompt_b: String,
	tick_count: int, elapsed_time: float,
	api_calls_a: int, tokens_a: int, idle_a: int,
	api_calls_b: int, tokens_b: int, idle_b: int,
	keys_a: int, keys_b: int
) -> void:
	# Root HBoxContainer for 3-column layout
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(hbox)

	var vp_width := get_viewport_rect().size.x

	# Left panel - Agent A stats
	var left := PanelContainer.new()
	left.custom_minimum_size.x = vp_width * _panel_ratio
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left)
	_build_agent_panel(left, 0, "Agent A", Color("#4488FF"),
		match_result, match_winner_id,
		api_calls_a, tokens_a, idle_a, tick_count,
		keys_a, prompt_a)

	# Center panel - Result title + buttons
	var center := PanelContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 3.0
	hbox.add_child(center)
	_build_center_panel(center, match_result, elapsed_time, tick_count)

	# Right panel - Agent B stats
	var right := PanelContainer.new()
	right.custom_minimum_size.x = vp_width * _panel_ratio
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	_build_agent_panel(right, 1, "Agent B", Color("#FF4444"),
		match_result, match_winner_id,
		api_calls_b, tokens_b, idle_b, tick_count,
		keys_b, prompt_b)


func _build_center_panel(container: Control, match_result: int, elapsed_time: float, tick_count: int) -> void:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	container.add_child(vbox)

	# Spacer
	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer_top)

	# Result title
	var title := Label.new()
	title.text = get_result_title(match_result)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", get_result_color(match_result))
	vbox.add_child(title)

	# Time UP subtitle for draw
	if match_result == Enums.MatchResult.DRAW:
		var time_up := Label.new()
		time_up.text = "TIME UP"
		time_up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_up.add_theme_color_override("font_color", _draw_color)
		vbox.add_child(time_up)

	# Time and ticks
	var time_label := Label.new()
	time_label.text = "Time: %s" % format_elapsed_time(elapsed_time)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(time_label)

	var tick_label := Label.new()
	tick_label.text = "Ticks: %d" % tick_count
	tick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tick_label)

	# Buttons
	var button_spacer := Control.new()
	button_spacer.custom_minimum_size.y = 20
	vbox.add_child(button_spacer)

	var rematch_btn := Button.new()
	rematch_btn.text = "Rematch"
	rematch_btn.pressed.connect(_on_rematch_pressed)
	vbox.add_child(rematch_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)

	# Spacer bottom
	var spacer_bot := Control.new()
	spacer_bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer_bot)


func _build_agent_panel(container: Control, agent_id: int, agent_name: String, color: Color,
		match_result: int, match_winner_id: int,
		api_calls: int, tokens: int, idle_ticks: int, tick_count: int,
		keys_state: int, prompt: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# Agent title
	var title := Label.new()
	title.text = agent_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", color)
	vbox.add_child(title)

	# Status (Winner / Defeated / Draw)
	var status := Label.new()
	status.text = get_agent_status(agent_id, match_result, match_winner_id)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Stats
	_add_stat_label(vbox, "API Calls: %d" % api_calls)
	_add_stat_label(vbox, "Tokens: %s" % _format_number(tokens))
	var idle_rate := calculate_idle_rate(idle_ticks, tick_count)
	_add_stat_label(vbox, "Idle Ticks: %d (%d%%)" % [idle_ticks, int(idle_rate)])
	_add_stat_label(vbox, "Keys: %s" % get_keys_string(keys_state))

	# Separator
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Prompt section
	var prompt_header := Label.new()
	prompt_header.text = "Prompt"
	prompt_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(prompt_header)

	var prompt_text := TextEdit.new()
	prompt_text.text = get_prompt_display(prompt)
	prompt_text.editable = false
	prompt_text.custom_minimum_size.y = _prompt_max_visible_lines * 20
	vbox.add_child(prompt_text)


func _add_stat_label(container: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	container.add_child(label)


func _format_number(n: int) -> String:
	# Simple number formatting with commas
	var s := str(n)
	if n < 1000:
		return s
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result


# --- Button Handlers ---

func _on_rematch_pressed() -> void:
	MatchStateManager.reset()
	SceneManagerGlobal.go_to("match")


func _on_quit_pressed() -> void:
	get_tree().quit()
