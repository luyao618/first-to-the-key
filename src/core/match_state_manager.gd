## Match State Manager - FSM driving the match lifecycle.
## Autoload singleton registered as "MatchStateManager".
## See design/gdd/match-state-manager.md for full specification.
extends Node

const ConfigLoader = preload("res://src/shared/config_loader.gd")

# --- Signals ---
signal state_changed(old_state: int, new_state: int)
signal tick(tick_count: int)
signal match_finished(result: int)
signal maze_ready
signal setup_failed(reason: String)

# --- State ---
var current_state: int = Enums.MatchState.SETUP
var config: Dictionary = {}
var current_maze: RefCounted = null  # MazeData instance
var result: int = Enums.MatchResult.NONE
var winner_id: int = -1
var tick_count: int = 0
var elapsed_time: float = 0.0

# --- Internal ---
var _tick_timer: Timer = null
var _countdown_timer: Timer = null
var _playing_start_time: float = 0.0
var _tick_interval: float = 0.5
var _countdown_duration: float = 3.0
var _max_match_duration: float = 300.0


func _ready() -> void:
	_load_config()
	_setup_timers()


func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/game_config.json")
	var match_cfg: Dictionary = cfg.get("match", {})
	_tick_interval = ConfigLoader.get_or_default(match_cfg, "tick_interval", 0.5)
	_countdown_duration = ConfigLoader.get_or_default(match_cfg, "countdown_duration", 3.0)
	_max_match_duration = ConfigLoader.get_or_default(match_cfg, "max_match_duration", 300.0)


func _setup_timers() -> void:
	_tick_timer = Timer.new()
	_tick_timer.wait_time = _tick_interval
	_tick_timer.one_shot = false
	_tick_timer.autostart = false
	_tick_timer.timeout.connect(_on_tick_timeout)
	add_child(_tick_timer)

	_countdown_timer = Timer.new()
	_countdown_timer.wait_time = _countdown_duration
	_countdown_timer.one_shot = true
	_countdown_timer.autostart = false
	_countdown_timer.timeout.connect(_on_countdown_finished)
	add_child(_countdown_timer)


func _process(delta: float) -> void:
	if current_state == Enums.MatchState.PLAYING:
		elapsed_time = (Time.get_ticks_msec() / 1000.0) - _playing_start_time
		if elapsed_time >= _max_match_duration:
			finish_match(Enums.MatchResult.DRAW, -1)


## Transition to SETUP and load config.
func start_setup(match_config: Dictionary) -> void:
	config = match_config
	_change_state(Enums.MatchState.SETUP)


## Transition from SETUP to COUNTDOWN. Returns false if preconditions not met.
func start_countdown() -> bool:
	if current_state != Enums.MatchState.SETUP:
		push_warning("Invalid transition: %d -> COUNTDOWN" % current_state)
		return false

	if current_maze == null or not current_maze._finalized:
		push_warning("Cannot start countdown: MazeData not finalized")
		return false

	_change_state(Enums.MatchState.COUNTDOWN)
	_countdown_timer.start()
	return true


## Transition from COUNTDOWN to PLAYING.
func start_playing() -> void:
	if current_state != Enums.MatchState.COUNTDOWN:
		push_warning("Invalid transition: %d -> PLAYING" % current_state)
		return

	_playing_start_time = Time.get_ticks_msec() / 1000.0
	elapsed_time = 0.0
	_change_state(Enums.MatchState.PLAYING)
	_tick_timer.start()


## Transition from PLAYING to FINISHED.
func finish_match(match_result: int, match_winner_id: int) -> void:
	if current_state != Enums.MatchState.PLAYING:
		push_warning("Invalid transition: %d -> FINISHED" % current_state)
		return

	result = match_result
	winner_id = match_winner_id
	_tick_timer.stop()
	_change_state(Enums.MatchState.FINISHED)
	match_finished.emit(result)


## Reset all state back to SETUP.
func reset() -> void:
	_tick_timer.stop()
	_countdown_timer.stop()
	current_maze = null
	result = Enums.MatchResult.NONE
	winner_id = -1
	tick_count = 0
	elapsed_time = 0.0
	config = {}
	_change_state(Enums.MatchState.SETUP)


# --- Queries ---

func get_state() -> int:
	return current_state

func get_config() -> Dictionary:
	return config

func get_maze() -> RefCounted:
	return current_maze

func get_tick_count() -> int:
	return tick_count

func get_elapsed_time() -> float:
	return elapsed_time

func is_playing() -> bool:
	return current_state == Enums.MatchState.PLAYING


# --- Internal ---

func _change_state(new_state: int) -> void:
	var old := current_state
	current_state = new_state
	state_changed.emit(old, new_state)


func _on_tick_timeout() -> void:
	if current_state != Enums.MatchState.PLAYING:
		return
	tick_count += 1
	tick.emit(tick_count)


func _on_countdown_finished() -> void:
	start_playing()
