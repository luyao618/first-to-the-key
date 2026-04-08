## Unit tests for PromptInput.
extends GutTest

const PromptInputClass := preload("res://src/ui/prompt_input.gd")

var pi: Control


func before_each() -> void:
	pi = PromptInputClass.new()
	add_child_autoqfree(pi)
	pi._initialize_ui()


func test_initial_state_is_player_a_input() -> void:
	assert_eq(pi.get_state(), PromptInputClass.InputState.PLAYER_A_INPUT)


func test_submit_player_a_advances_state() -> void:
	pi.submit_prompt_a("test prompt A")
	assert_eq(pi.get_state(), PromptInputClass.InputState.PLAYER_B_INPUT)


func test_submit_player_a_stores_prompt() -> void:
	pi.submit_prompt_a("my strategy")
	assert_eq(pi.get_prompt_a(), "my strategy")


func test_submit_player_b_advances_to_completed() -> void:
	pi.submit_prompt_a("A")
	pi.submit_prompt_b("B")
	assert_eq(pi.get_state(), PromptInputClass.InputState.COMPLETED)


func test_submit_player_b_stores_prompt() -> void:
	pi.submit_prompt_a("A")
	pi.submit_prompt_b("my B strategy")
	assert_eq(pi.get_prompt_b(), "my B strategy")


func test_empty_prompt_allowed() -> void:
	pi.submit_prompt_a("")
	assert_eq(pi.get_state(), PromptInputClass.InputState.PLAYER_B_INPUT)
	assert_eq(pi.get_prompt_a(), "")


func test_reset_clears_state() -> void:
	pi.submit_prompt_a("A")
	pi.submit_prompt_b("B")
	pi.reset_input()
	assert_eq(pi.get_state(), PromptInputClass.InputState.PLAYER_A_INPUT)
	assert_eq(pi.get_prompt_a(), "")
	assert_eq(pi.get_prompt_b(), "")


func test_submit_b_before_a_ignored() -> void:
	pi.submit_prompt_b("B")
	assert_eq(pi.get_state(), PromptInputClass.InputState.PLAYER_A_INPUT)


func test_completed_signal_emitted() -> void:
	watch_signals(pi)
	pi.submit_prompt_a("A")
	pi.submit_prompt_b("B")
	assert_signal_emitted(pi, "prompts_submitted")
