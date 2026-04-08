## Unit tests for ResultScreen.
extends GutTest

const ResultScreenClass := preload("res://src/ui/result_screen.gd")

var rs: Control


func before_each() -> void:
	rs = ResultScreenClass.new()
	add_child_autoqfree(rs)


# --- Result Title ---

func test_get_result_title_player_a_wins() -> void:
	assert_eq(rs.get_result_title(Enums.MatchResult.PLAYER_A_WIN), "Player 1 Wins!")


func test_get_result_title_player_b_wins() -> void:
	assert_eq(rs.get_result_title(Enums.MatchResult.PLAYER_B_WIN), "Player 2 Wins!")


func test_get_result_title_draw() -> void:
	assert_eq(rs.get_result_title(Enums.MatchResult.DRAW), "Draw!")


func test_get_result_title_none() -> void:
	assert_eq(rs.get_result_title(Enums.MatchResult.NONE), "No Result")


# --- Result Color ---

func test_get_result_color_player_a() -> void:
	assert_eq(rs.get_result_color(Enums.MatchResult.PLAYER_A_WIN), rs._winner_color_a)


func test_get_result_color_player_b() -> void:
	assert_eq(rs.get_result_color(Enums.MatchResult.PLAYER_B_WIN), rs._winner_color_b)


func test_get_result_color_draw() -> void:
	assert_eq(rs.get_result_color(Enums.MatchResult.DRAW), rs._draw_color)


# --- Agent Status Text ---

func test_get_agent_status_winner() -> void:
	assert_eq(rs.get_agent_status(0, Enums.MatchResult.PLAYER_A_WIN, 0), "Winner")


func test_get_agent_status_defeated() -> void:
	assert_eq(rs.get_agent_status(1, Enums.MatchResult.PLAYER_A_WIN, 0), "Defeated")


func test_get_agent_status_draw() -> void:
	assert_eq(rs.get_agent_status(0, Enums.MatchResult.DRAW, -1), "Draw")
	assert_eq(rs.get_agent_status(1, Enums.MatchResult.DRAW, -1), "Draw")


# --- Idle Rate ---

func test_calculate_idle_rate_normal() -> void:
	assert_almost_eq(rs.calculate_idle_rate(25, 200), 12.5, 0.01)


func test_calculate_idle_rate_zero_ticks() -> void:
	assert_eq(rs.calculate_idle_rate(10, 0), 0.0)


func test_calculate_idle_rate_zero_idle() -> void:
	assert_eq(rs.calculate_idle_rate(0, 100), 0.0)


func test_calculate_idle_rate_100_percent() -> void:
	assert_almost_eq(rs.calculate_idle_rate(100, 100), 100.0, 0.01)


# --- Time Format ---

func test_format_elapsed_time() -> void:
	assert_eq(rs.format_elapsed_time(95.7), "1:35")


func test_format_elapsed_time_zero() -> void:
	assert_eq(rs.format_elapsed_time(0.0), "0:00")


func test_format_elapsed_time_large() -> void:
	assert_eq(rs.format_elapsed_time(3661.0), "61:01")


# --- Keys Progress ---

func test_get_keys_string_none() -> void:
	assert_eq(rs.get_keys_string(Enums.AgentKeyState.NEED_BRASS), "0/3")


func test_get_keys_string_one() -> void:
	assert_eq(rs.get_keys_string(Enums.AgentKeyState.NEED_JADE), "1/3")


func test_get_keys_string_two() -> void:
	assert_eq(rs.get_keys_string(Enums.AgentKeyState.NEED_CRYSTAL), "2/3")


func test_get_keys_string_all() -> void:
	assert_eq(rs.get_keys_string(Enums.AgentKeyState.KEYS_COMPLETE), "3/3")


# --- Prompt Display ---

func test_get_prompt_display_normal() -> void:
	assert_eq(rs.get_prompt_display("my strategy"), "my strategy")


func test_get_prompt_display_empty() -> void:
	assert_eq(rs.get_prompt_display(""), "(empty)")
