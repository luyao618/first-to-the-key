## Match scene root script.
## Manages the match lifecycle: 3-column layout, signal wiring, scene orchestration.
extends Control

@onready var left_panel: PanelContainer = $HBoxContainer/LeftPanel
@onready var center_panel: SubViewportContainer = $HBoxContainer/CenterPanel
@onready var right_panel: PanelContainer = $HBoxContainer/RightPanel

var _panel_ratio: float = 0.20


func _ready() -> void:
	_load_config()
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)


func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/ui_config.json")
	var layout_cfg: Dictionary = cfg.get("layout", {})
	_panel_ratio = ConfigLoader.get_or_default(layout_cfg, "panel_ratio", 0.20)


func _apply_layout() -> void:
	var vp_size := get_viewport_rect().size
	if left_panel and right_panel and center_panel:
		left_panel.custom_minimum_size.x = vp_size.x * _panel_ratio
		right_panel.custom_minimum_size.x = vp_size.x * _panel_ratio
		center_panel.custom_minimum_size.x = vp_size.x * (1.0 - 2.0 * _panel_ratio)
