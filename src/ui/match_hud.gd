## Match HUD - displays key progress, timer, and toast notifications.
## Renders in the Match scene's three-column layout during PLAYING state.
## See design/gdd/match-hud.md for full specification.
class_name MatchHUD
extends Node

# --- Configuration ---
var _toast_duration: float = 3.0
var _toast_fade_duration: float = 0.5
var _key_slot_pulse_duration: float = 0.3
var _key_slot_pulse_scale: float = 1.3
var _timer_font_size: int = 24
var _toast_font_size: int = 28
var _hud_margin: int = 16

# --- Internal State ---
var _is_playing: bool = false
var _key_slots: Dictionary = {}   # {agent_id: {slot_index: bool}}
var _toast_text: String = ""
var _toast_visible: bool = false
var _toast_tween: Tween = null

# --- UI Nodes (set by build_hud) ---
var _key_slot_nodes: Dictionary = {}  # {agent_id: Array[TextureRect]}
var _time_label: Label = null
var _tick_label: Label = null
var _toast_label: Label = null
var _toast_bg: Panel = null

# --- Key Colors ---
const KEY_COLORS: Array[Color] = [
	Color(0.8, 0.6, 0.2),   # Brass = copper
	Color(0.2, 0.8, 0.4),   # Jade = green
	Color(0.3, 0.6, 1.0),   # Crystal = ice blue
]


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/ui_config.json")
	var hud_cfg: Dictionary = cfg.get("hud", {})
	_toast_duration = ConfigLoader.get_or_default(hud_cfg, "toast_duration", 3.0)
	_toast_fade_duration = ConfigLoader.get_or_default(hud_cfg, "toast_fade_duration", 0.5)
	_key_slot_pulse_duration = ConfigLoader.get_or_default(hud_cfg, "key_slot_pulse_duration", 0.3)
	_key_slot_pulse_scale = ConfigLoader.get_or_default(hud_cfg, "key_slot_pulse_scale", 1.3)
	_timer_font_size = ConfigLoader.get_or_default(hud_cfg, "timer_font_size", 24)
	_toast_font_size = ConfigLoader.get_or_default(hud_cfg, "toast_font_size", 28)
	_hud_margin = ConfigLoader.get_or_default(hud_cfg, "hud_margin", 16)


## Initialize internal state to defaults (all locked, no toast, not playing).
func _initialize_state() -> void:
	_is_playing = false
	_toast_text = ""
	_toast_visible = false
	_key_slots.clear()
	for agent_id in [0, 1]:
		_key_slots[agent_id] = {0: false, 1: false, 2: false}


## Enable/disable HUD updates.
func set_playing(playing: bool) -> void:
	_is_playing = playing


# --- Key Slots ---

## Map a MarkerType key to slot index (0=Brass, 1=Jade, 2=Crystal).
func _key_type_to_slot(key_type: int) -> int:
	match key_type:
		Enums.MarkerType.KEY_BRASS: return 0
		Enums.MarkerType.KEY_JADE: return 1
		Enums.MarkerType.KEY_CRYSTAL: return 2
	return -1


## Handle key_collected signal from KeyCollection.
func on_key_collected(agent_id: int, key_type: int) -> void:
	if not _is_playing:
		return
	var slot := _key_type_to_slot(key_type)
	if slot == -1:
		return
	if not _key_slots.has(agent_id):
		return
	_key_slots[agent_id][slot] = true

	# Animate slot if UI nodes exist
	if _key_slot_nodes.has(agent_id):
		var nodes: Array = _key_slot_nodes[agent_id]
		if slot < nodes.size():
			_animate_slot_collected(nodes[slot], slot)


func is_key_slot_collected(agent_id: int, slot_index: int) -> bool:
	if not _key_slots.has(agent_id):
		return false
	return _key_slots[agent_id].get(slot_index, false)


func _animate_slot_collected(slot_node: TextureRect, slot_index: int) -> void:
	# Change texture to colored version
	var color: Color = KEY_COLORS[slot_index] if slot_index < KEY_COLORS.size() else Color.WHITE
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(color)
	slot_node.texture = ImageTexture.create_from_image(img)

	# Pulse animation
	var tween := create_tween()
	tween.tween_property(slot_node, "scale", Vector2(_key_slot_pulse_scale, _key_slot_pulse_scale), _key_slot_pulse_duration * 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot_node, "scale", Vector2(1.0, 1.0), _key_slot_pulse_duration * 0.6).set_ease(Tween.EASE_IN)


# --- Timer ---

## Format elapsed time and tick count for display.
func format_time(elapsed: float, ticks: int) -> String:
	var minutes := int(elapsed) / 60
	var seconds := int(elapsed) % 60
	return "%02d:%02d | Tick %d" % [minutes, seconds, ticks]


## Update timer display (called every frame during PLAYING).
func update_timer(elapsed: float, ticks: int) -> void:
	if _time_label != null:
		_time_label.text = format_time(elapsed, ticks)


# --- Toast ---

func show_toast(message: String) -> void:
	_toast_text = message
	_toast_visible = true

	# Cancel existing fade
	if _toast_tween != null:
		_toast_tween.kill()
		_toast_tween = null

	# Update UI if nodes exist
	if _toast_label != null:
		_toast_label.text = message
		_toast_label.visible = true
		_toast_label.modulate.a = 1.0
	if _toast_bg != null:
		_toast_bg.visible = true
		_toast_bg.modulate.a = 0.5

	# Auto-fade after duration
	_toast_tween = create_tween()
	_toast_tween.tween_interval(_toast_duration)
	_toast_tween.tween_callback(func() -> void:
		_fade_toast()
	)


func _fade_toast() -> void:
	if _toast_label != null:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(_toast_label, "modulate:a", 0.0, _toast_fade_duration)
		if _toast_bg != null:
			tween.tween_property(_toast_bg, "modulate:a", 0.0, _toast_fade_duration)
		tween.chain().tween_callback(func() -> void:
			_toast_visible = false
			if _toast_label != null:
				_toast_label.visible = false
			if _toast_bg != null:
				_toast_bg.visible = false
		)
	else:
		_toast_visible = false


func clear_toast() -> void:
	_toast_text = ""
	_toast_visible = false
	if _toast_tween != null:
		_toast_tween.kill()
		_toast_tween = null
	if _toast_label != null:
		_toast_label.visible = false
	if _toast_bg != null:
		_toast_bg.visible = false


func get_toast_text() -> String:
	return _toast_text


func is_toast_visible() -> bool:
	return _toast_visible


# --- UI Building ---

## Build HUD UI into the Match scene's three-column layout.
## Called by match.gd after entering PLAYING state.
func build_hud(left_panel: Control, center_panel: Control, right_panel: Control) -> void:
	_build_key_progress_panel(left_panel, 0, "A", Color("#4488FF"))
	_build_key_progress_panel(right_panel, 1, "B", Color("#FF4444"))
	_build_timer_panel(center_panel)
	_build_toast_overlay()


func _build_key_progress_panel(container: Control, agent_id: int, label_text: String, color: Color) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	container.add_child(vbox)

	# Agent label
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	vbox.add_child(label)

	# Key slots
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	var slot_nodes: Array[TextureRect] = []
	for i in range(3):
		var slot := TextureRect.new()
		slot.custom_minimum_size = Vector2(20, 20)
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.pivot_offset = Vector2(10, 10)

		# Gray placeholder texture
		var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.4, 0.4, 0.4))
		slot.texture = ImageTexture.create_from_image(img)

		# If already collected (defensive init), color it
		if _key_slots.has(agent_id) and _key_slots[agent_id].get(i, false):
			var cimg := Image.create(20, 20, false, Image.FORMAT_RGBA8)
			cimg.fill(KEY_COLORS[i])
			slot.texture = ImageTexture.create_from_image(cimg)

		hbox.add_child(slot)
		slot_nodes.append(slot)

	_key_slot_nodes[agent_id] = slot_nodes


func _build_timer_panel(container: Control) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	container.add_child(vbox)

	_time_label = Label.new()
	_time_label.text = "00:00 | Tick 0"
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_time_label)


func _build_toast_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var center := CenterContainer.new()
	center.anchors_preset = Control.PRESET_BOTTOM_WIDE
	center.offset_top = -80
	canvas.add_child(center)

	_toast_bg = Panel.new()
	_toast_bg.custom_minimum_size = Vector2(400, 50)
	_toast_bg.visible = false
	_toast_bg.modulate.a = 0.5
	center.add_child(_toast_bg)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.visible = false
	_toast_bg.add_child(_toast_label)
