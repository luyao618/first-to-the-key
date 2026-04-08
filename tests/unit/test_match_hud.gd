## Unit tests for MatchHUD.
extends GutTest

const MatchHUDClass := preload("res://src/ui/match_hud.gd")

var hud: Node


func before_each() -> void:
	hud = MatchHUDClass.new()
	add_child_autoqfree(hud)
	hud._initialize_state()


# --- Key Slot State ---

func test_initial_key_slots_all_locked() -> void:
	for agent_id in [0, 1]:
		for key_idx in range(3):
			assert_false(hud.is_key_slot_collected(agent_id, key_idx),
				"Agent %d slot %d should start locked" % [agent_id, key_idx])


func test_on_key_collected_agent_a_brass() -> void:
	hud.set_playing(true)
	hud.on_key_collected(0, Enums.MarkerType.KEY_BRASS)
	assert_true(hud.is_key_slot_collected(0, 0), "Agent A brass slot should be collected")
	assert_false(hud.is_key_slot_collected(0, 1), "Agent A jade slot still locked")
	assert_false(hud.is_key_slot_collected(0, 2), "Agent A crystal slot still locked")


func test_on_key_collected_agent_b_jade() -> void:
	hud.set_playing(true)
	hud.on_key_collected(1, Enums.MarkerType.KEY_JADE)
	assert_true(hud.is_key_slot_collected(1, 1), "Agent B jade slot should be collected")
	assert_false(hud.is_key_slot_collected(1, 0), "Agent B brass slot still locked")


func test_on_key_collected_all_three() -> void:
	hud.set_playing(true)
	hud.on_key_collected(0, Enums.MarkerType.KEY_BRASS)
	hud.on_key_collected(0, Enums.MarkerType.KEY_JADE)
	hud.on_key_collected(0, Enums.MarkerType.KEY_CRYSTAL)
	assert_true(hud.is_key_slot_collected(0, 0))
	assert_true(hud.is_key_slot_collected(0, 1))
	assert_true(hud.is_key_slot_collected(0, 2))


func test_agent_independence() -> void:
	hud.set_playing(true)
	hud.on_key_collected(0, Enums.MarkerType.KEY_BRASS)
	assert_true(hud.is_key_slot_collected(0, 0))
	assert_false(hud.is_key_slot_collected(1, 0), "Agent B unaffected by Agent A pickup")


# --- Timer ---

func test_format_time_zero() -> void:
	assert_eq(hud.format_time(0.0, 0), "00:00 | Tick 0")


func test_format_time_normal() -> void:
	assert_eq(hud.format_time(95.7, 191), "01:35 | Tick 191")


func test_format_time_large() -> void:
	assert_eq(hud.format_time(3661.0, 7322), "61:01 | Tick 7322")


# --- Toast ---

func test_show_toast_sets_text() -> void:
	hud.show_toast("Test message")
	assert_eq(hud.get_toast_text(), "Test message")
	assert_true(hud.is_toast_visible())


func test_show_toast_overwrites_previous() -> void:
	hud.show_toast("First")
	hud.show_toast("Second")
	assert_eq(hud.get_toast_text(), "Second")


func test_clear_toast() -> void:
	hud.show_toast("Test")
	hud.clear_toast()
	assert_false(hud.is_toast_visible())


# --- Lifecycle ---

func test_set_playing_enables_updates() -> void:
	hud.set_playing(true)
	assert_true(hud._is_playing)


func test_set_playing_false_disables_updates() -> void:
	hud.set_playing(true)
	hud.set_playing(false)
	assert_false(hud._is_playing)


func test_key_collected_ignored_when_not_playing() -> void:
	hud.set_playing(false)
	hud.on_key_collected(0, Enums.MarkerType.KEY_BRASS)
	assert_false(hud.is_key_slot_collected(0, 0),
		"Key collection should be ignored when not playing")


func test_initialize_resets_all() -> void:
	hud.set_playing(true)
	hud.on_key_collected(0, Enums.MarkerType.KEY_BRASS)
	hud.show_toast("test")
	hud._initialize_state()
	assert_false(hud.is_key_slot_collected(0, 0))
	assert_false(hud.is_toast_visible())
	assert_false(hud._is_playing)
