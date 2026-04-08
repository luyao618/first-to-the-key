## LLM Agent Manager - decision engine managing per-agent AI brains.
## Autoload singleton registered as "LLMAgentManager".
## See design/gdd/llm-agent-integration.md for full specification.
extends Node

const ConfigLoader = preload("res://src/shared/config_loader.gd")

# --- Signals ---
signal api_request_sent(agent_id: int)
signal api_response_received(agent_id: int)
signal api_error(agent_id: int, error_type: String)
signal decision_made(agent_id: int, target_pos: Vector2i)
signal auto_advance(agent_id: int, direction: int)

# --- Dependencies (injected) ---
var maze: RefCounted = null
var movement: Node = null  # GridMovement
var fog: Node = null  # FogOfWar
var keys: Node = null  # KeyCollection
var win_condition: Node = null  # WinConditionManager

# --- Internal ---
var _brains: Array[Dictionary] = []
var _info_format: RefCounted = null  # LLMInformationFormat
var _active: bool = false

# --- Config defaults ---
var _default_api_endpoint: String = "https://api.openai.com/v1/chat/completions"
var _default_model: String = "gpt-4o"
var _default_api_timeout: float = 10.0
var _default_temperature: float = 0.3
var _default_max_tokens: int = 50
var _default_max_queue_length: int = 20


func _ready() -> void:
	_info_format = preload("res://src/ai/llm_info_format.gd").new()


## Initialize brains for both agents. Config is a Dictionary with optional
## llm_config_a / llm_config_b sub-dictionaries and prompt_a / prompt_b strings.
func initialize(config: Dictionary = {}) -> void:
	_brains.clear()
	for i in range(2):
		var suffix := "a" if i == 0 else "b"
		var llm_cfg: Dictionary = config.get("llm_config_%s" % suffix, {})
		var prompt: String = config.get("prompt_%s" % suffix, "")
		_brains.append(_create_brain(i, llm_cfg, prompt))


## Create a brain dictionary for an agent with config.
func _create_brain(agent_id: int, llm_cfg: Dictionary = {}, player_prompt: String = "") -> Dictionary:
	var vision_radius: int = 3
	var cfg := ConfigLoader.load_json("res://assets/data/game_config.json")
	var vision_cfg: Dictionary = cfg.get("vision", {})
	vision_radius = ConfigLoader.get_or_default(vision_cfg, "vision_radius", 3)

	var brain := {
		"agent_id": agent_id,
		"path_queue": [] as Array[int],
		"last_move_direction": Enums.MoveDirection.NONE,
		"request_state": Enums.RequestState.IDLE,
		"pending_response": "",
		"api_endpoint": llm_cfg.get("api_endpoint", _default_api_endpoint),
		"api_key": llm_cfg.get("api_key", ""),
		"model": llm_cfg.get("model", _default_model),
		"api_timeout": llm_cfg.get("api_timeout", _default_api_timeout),
		"temperature": llm_cfg.get("temperature", _default_temperature),
		"max_tokens": llm_cfg.get("max_tokens", _default_max_tokens),
		"max_queue_length": llm_cfg.get("max_queue_length", _default_max_queue_length),
		"system_message": _info_format.build_system_message(player_prompt, vision_radius),
		"total_api_calls": 0,
		"total_tokens_used": 0,
		"total_idle_ticks": 0,
		"http_request": null,
	}
	return brain


## Set active state.
func set_active(active: bool) -> void:
	_active = active


## Reset all state.
func reset() -> void:
	# Cancel any in-flight requests
	for brain in _brains:
		_cancel_request(brain)
	_brains.clear()
	_active = false


# --- Query Interface ---

func get_brain(agent_id: int) -> Variant:
	if agent_id < 0 or agent_id >= _brains.size():
		return null
	return _brains[agent_id]


func get_api_call_count(agent_id: int) -> int:
	var brain = get_brain(agent_id)
	if brain == null:
		return 0
	return brain["total_api_calls"]


func get_idle_tick_count(agent_id: int) -> int:
	var brain = get_brain(agent_id)
	if brain == null:
		return 0
	return brain["total_idle_ticks"]


# --- Decision Point Detection ---

## Check if a position is a decision point given the last move direction.
func _is_decision_point(pos: Vector2i, last_dir: int) -> bool:
	if maze == null:
		return false

	var open_dirs: Array[int] = _get_open_move_dirs(pos)

	# Dead end: only 1 open direction
	if open_dirs.size() <= 1:
		return true

	# Exclude reverse of last_dir to get forward options
	if last_dir != Enums.MoveDirection.NONE:
		var reverse: int = Enums.OPPOSITE_MOVE_DIRECTION[last_dir]
		var forward_dirs: Array[int] = []
		for d in open_dirs:
			if d != reverse:
				forward_dirs.append(d)

		# Intersection: 2+ forward options
		if forward_dirs.size() >= 2:
			return true
		# Straight: exactly 1 forward option
		if forward_dirs.size() == 1:
			return false
		# No forward (dead end facing wall)
		return true
	else:
		# No last direction (first tick) - always decision
		return true


## Get auto-advance direction (straight corridor).
func _get_auto_direction(pos: Vector2i, last_dir: int) -> int:
	if last_dir == Enums.MoveDirection.NONE:
		return Enums.MoveDirection.NONE

	var open_dirs: Array[int] = _get_open_move_dirs(pos)
	var reverse: int = Enums.OPPOSITE_MOVE_DIRECTION[last_dir]
	var forward_dirs: Array[int] = []
	for d in open_dirs:
		if d != reverse:
			forward_dirs.append(d)

	if forward_dirs.size() == 1:
		return forward_dirs[0]
	return Enums.MoveDirection.NONE


## Get all open MoveDirections from a position.
func _get_open_move_dirs(pos: Vector2i) -> Array[int]:
	var result: Array[int] = []
	if maze.can_move(pos.x, pos.y, Enums.Direction.NORTH):
		result.append(Enums.MoveDirection.NORTH)
	if maze.can_move(pos.x, pos.y, Enums.Direction.EAST):
		result.append(Enums.MoveDirection.EAST)
	if maze.can_move(pos.x, pos.y, Enums.Direction.SOUTH):
		result.append(Enums.MoveDirection.SOUTH)
	if maze.can_move(pos.x, pos.y, Enums.Direction.WEST):
		result.append(Enums.MoveDirection.WEST)
	return result


# --- Path Queue ---

## Replace path queue with BFS path from current position to target.
func _replace_queue(brain: Dictionary, target: Vector2i) -> void:
	var current_pos: Vector2i = movement.get_position_of(brain["agent_id"])
	var path: Array[Vector2i] = maze.get_shortest_path(current_pos, target)

	brain["path_queue"].clear()
	if path.size() < 2:
		return  # Same position or unreachable

	# Convert path to direction sequence
	for i in range(path.size() - 1):
		var offset: Vector2i = path[i + 1] - path[i]
		var dir := _offset_to_move_dir(offset)
		if dir != Enums.MoveDirection.NONE:
			brain["path_queue"].append(dir)

	# Truncate to max queue length
	var max_len: int = brain["max_queue_length"]
	if brain["path_queue"].size() > max_len:
		brain["path_queue"] = brain["path_queue"].slice(0, max_len)


## Consume the front of the path queue. Returns MoveDirection.NONE if empty.
func _consume_queue(brain: Dictionary) -> int:
	if brain["path_queue"].size() == 0:
		return Enums.MoveDirection.NONE
	return brain["path_queue"].pop_front()


## Convert a Vector2i offset to MoveDirection.
func _offset_to_move_dir(offset: Vector2i) -> int:
	if offset == Vector2i(0, -1): return Enums.MoveDirection.NORTH
	if offset == Vector2i(1, 0): return Enums.MoveDirection.EAST
	if offset == Vector2i(0, 1): return Enums.MoveDirection.SOUTH
	if offset == Vector2i(-1, 0): return Enums.MoveDirection.WEST
	return Enums.MoveDirection.NONE


# --- Tick Processing ---

## Process one tick for all agents. Called by MSM tick signal.
func on_tick(tick_count: int) -> void:
	if not _active:
		return

	for brain in _brains:
		_process_brain_tick(brain, tick_count)


func _process_brain_tick(brain: Dictionary, tick_count: int) -> void:
	var agent_id: int = brain["agent_id"]
	var pos: Vector2i = movement.get_position_of(agent_id)

	# Check for pending API response
	if brain["pending_response"] != "":
		_handle_api_response(brain, brain["pending_response"])
		brain["pending_response"] = ""

	# First tick: always request API
	if brain["last_move_direction"] == Enums.MoveDirection.NONE:
		if brain["request_state"] == Enums.RequestState.IDLE:
			_send_api_request(brain, tick_count)
		brain["total_idle_ticks"] += 1
		# Don't set any direction (stay in place)
		return

	# Try consuming from path queue
	var dir := _consume_queue(brain)
	if dir != Enums.MoveDirection.NONE:
		movement.set_direction(agent_id, dir)
		return

	# Queue empty - try auto-advance
	var auto_dir := _get_auto_direction(pos, brain["last_move_direction"])
	if auto_dir != Enums.MoveDirection.NONE:
		movement.set_direction(agent_id, auto_dir)
		auto_advance.emit(agent_id, auto_dir)
		return

	# Decision point or stuck - request API if idle
	if brain["request_state"] == Enums.RequestState.IDLE:
		_send_api_request(brain, tick_count)
	brain["total_idle_ticks"] += 1


# --- Movement Callbacks ---

## Called after mover_moved - update last direction and check decision points.
func _on_mover_moved(mover_id: int, old_pos: Vector2i, new_pos: Vector2i) -> void:
	if mover_id < 0 or mover_id >= _brains.size():
		return
	var brain: Dictionary = _brains[mover_id]
	var offset := new_pos - old_pos
	brain["last_move_direction"] = _offset_to_move_dir(offset)

	# Check if new position is a decision point for pre-fire
	if _is_decision_point(new_pos, brain["last_move_direction"]):
		if brain["request_state"] == Enums.RequestState.IDLE:
			# Pre-fire API request (don't clear queue)
			_send_api_request_deferred(brain)


## Called after mover_blocked - clear queue and request new decision.
func _on_mover_blocked(mover_id: int, _pos: Vector2i, _direction: int) -> void:
	if mover_id < 0 or mover_id >= _brains.size():
		return
	var brain: Dictionary = _brains[mover_id]
	brain["path_queue"].clear()
	if brain["request_state"] == Enums.RequestState.IDLE:
		_send_api_request_deferred(brain)


# --- API Integration ---

## Send API request (or simulate for offline/test mode).
func _send_api_request(brain: Dictionary, _tick_count: int) -> void:
	if brain["api_key"].is_empty():
		# No API key - can't make real requests
		# Mark as idle so tests can inject responses
		return

	brain["request_state"] = Enums.RequestState.IN_FLIGHT
	brain["total_api_calls"] += 1
	api_request_sent.emit(brain["agent_id"])

	# Build request
	var state_msg: String = _info_format.build_state_message(
		brain["agent_id"], maze, fog, movement, keys, win_condition,
		MatchStateManager.get_tick_count() if MatchStateManager != null else 0
	)

	var body := {
		"model": brain["model"],
		"messages": [
			{"role": "system", "content": brain["system_message"]},
			{"role": "user", "content": state_msg},
		],
		"temperature": brain["temperature"],
		"max_tokens": brain["max_tokens"],
	}

	# Create HTTPRequest if needed
	if brain["http_request"] == null:
		var http := HTTPRequest.new()
		http.timeout = brain["api_timeout"]
		add_child(http)
		http.request_completed.connect(_on_http_completed.bind(brain["agent_id"]))
		brain["http_request"] = http

	var http: HTTPRequest = brain["http_request"]
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % brain["api_key"],
	]
	var json_body := JSON.stringify(body)
	var err := http.request(brain["api_endpoint"], headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		push_error("LLMAgent: HTTP request failed for agent %d: %s" % [brain["agent_id"], str(err)])
		brain["request_state"] = Enums.RequestState.IDLE
		api_error.emit(brain["agent_id"], "request_failed")


func _send_api_request_deferred(brain: Dictionary) -> void:
	call_deferred("_send_api_request", brain, 0)


## Handle HTTP response.
func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, agent_id: int) -> void:
	if agent_id < 0 or agent_id >= _brains.size():
		return
	var brain: Dictionary = _brains[agent_id]
	brain["request_state"] = Enums.RequestState.IDLE

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("LLMAgent: API error for agent %d: result=%d code=%d" % [agent_id, result, response_code])
		api_error.emit(agent_id, "http_error_%d" % response_code)
		return

	# Parse response
	var text := body.get_string_from_utf8()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_warning("LLMAgent: Failed to parse API response JSON for agent %d" % agent_id)
		api_error.emit(agent_id, "json_parse_error")
		return

	var data = json.data
	if data is Dictionary and data.has("choices"):
		var choices: Array = data["choices"]
		if choices.size() > 0:
			var content: String = choices[0].get("message", {}).get("content", "")
			brain["pending_response"] = content

			# Track token usage
			if data.has("usage"):
				var usage: Dictionary = data["usage"]
				brain["total_tokens_used"] += int(usage.get("total_tokens", 0))

	api_response_received.emit(agent_id)


## Handle pending API response text.
func _handle_api_response(brain: Dictionary, response_text: String) -> void:
	var parse_result: Dictionary = _info_format.parse_response(response_text)
	var agent_id: int = brain["agent_id"]

	match parse_result["type"]:
		"TARGET":
			var target: Vector2i = parse_result["pos"]
			# Validate target
			if _validate_target(brain, target):
				_replace_queue(brain, target)
				decision_made.emit(agent_id, target)
			# else: invalid target, treat as NONE (don't update queue)
		"DIRECTION":
			var dir: int = parse_result["dir"]
			brain["path_queue"] = [dir] as Array[int]
			decision_made.emit(agent_id, Vector2i(-1, -1))
		"NONE":
			pass  # Don't update queue


## Validate a target coordinate from LLM response.
func _validate_target(brain: Dictionary, target: Vector2i) -> bool:
	var agent_id: int = brain["agent_id"]

	# Range check
	if target.x < 0 or target.x >= maze.width or target.y < 0 or target.y >= maze.height:
		push_warning("LLMAgent: Target out of bounds: %s" % str(target))
		return false

	# Must be in visible or explored area
	var vis: int = fog.get_cell_visibility(agent_id, target.x, target.y)
	if vis == Enums.CellVisibility.UNKNOWN:
		push_warning("LLMAgent: Target in unknown area: %s" % str(target))
		return false

	# Must not be current position
	var current: Vector2i = movement.get_position_of(agent_id)
	if target == current:
		push_warning("LLMAgent: Target is current position: %s" % str(target))
		return false

	# Must be reachable
	var path: Array[Vector2i] = maze.get_shortest_path(current, target)
	if path.size() < 2:
		push_warning("LLMAgent: Target unreachable: %s" % str(target))
		return false

	return true


## Cancel any in-flight HTTP request.
func _cancel_request(brain: Dictionary) -> void:
	if brain.has("http_request") and brain["http_request"] != null:
		brain["http_request"].cancel_request()
	brain["request_state"] = Enums.RequestState.IDLE
	brain["pending_response"] = ""
