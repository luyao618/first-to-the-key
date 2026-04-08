## LLM Information Format - prompt builder and response parser.
## Stateless transformer: reads from upstream systems, no cached state.
## See design/gdd/llm-information-format.md for full specification.
class_name LLMInformationFormat
extends RefCounted

# --- Configuration ---
var include_ascii_map: bool = false
var include_explored: bool = true
var max_visited_count: int = 20
var max_explored_count: int = 30

# --- Debug ---
var _last_prompts: Dictionary = {}  # agent_id -> last built prompt


func _init() -> void:
	_load_config()


func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/game_config.json")
	var fmt_cfg: Dictionary = cfg.get("llm_format", {})
	include_ascii_map = ConfigLoader.get_or_default(fmt_cfg, "include_ascii_map", false)
	include_explored = ConfigLoader.get_or_default(fmt_cfg, "include_explored", true)
	max_visited_count = ConfigLoader.get_or_default(fmt_cfg, "max_visited_count", 20)
	max_explored_count = ConfigLoader.get_or_default(fmt_cfg, "max_explored_count", 30)


# --- Response Parsing ---

## Parse LLM response text into a result dictionary.
## Returns: {"type": "TARGET", "pos": Vector2i} or
##          {"type": "DIRECTION", "dir": MoveDirection} or
##          {"type": "NONE"}
func parse_response(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return {"type": "NONE"}

	# Extract first JSON block
	var json_str := _extract_json(text)
	if json_str.is_empty():
		push_warning("LLMInfoFormat: No JSON found in response")
		return {"type": "NONE"}

	# Parse JSON
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		push_warning("LLMInfoFormat: JSON parse error: %s" % json.get_error_message())
		return {"type": "NONE"}

	var data = json.data
	if not data is Dictionary:
		return {"type": "NONE"}

	# Priority 1: target
	if data.has("target"):
		var arr = data["target"]
		if arr is Array and arr.size() == 2:
			var x = int(arr[0])
			var y = int(arr[1])
			return {"type": "TARGET", "pos": Vector2i(x, y)}
		push_warning("LLMInfoFormat: Invalid target format: %s" % str(arr))

	# Priority 2: direction
	if data.has("direction"):
		var dir_str: String = str(data["direction"]).to_upper().strip_edges()
		var dir := _parse_direction_string(dir_str)
		if dir != -1:
			return {"type": "DIRECTION", "dir": dir}
		push_warning("LLMInfoFormat: Invalid direction: %s" % dir_str)

	return {"type": "NONE"}


## Extract the first {...} block from text.
func _extract_json(text: String) -> String:
	var start := text.find("{")
	if start == -1:
		return ""

	var depth := 0
	for i in range(start, text.length()):
		if text[i] == "{":
			depth += 1
		elif text[i] == "}":
			depth -= 1
			if depth == 0:
				return text.substr(start, i - start + 1)
	return ""


## Parse a direction string to MoveDirection enum value. Returns -1 on failure.
func _parse_direction_string(dir_str: String) -> int:
	match dir_str:
		"NORTH", "N", "UP":
			return Enums.MoveDirection.NORTH
		"EAST", "E", "RIGHT":
			return Enums.MoveDirection.EAST
		"SOUTH", "S", "DOWN":
			return Enums.MoveDirection.SOUTH
		"WEST", "W", "LEFT":
			return Enums.MoveDirection.WEST
	return -1


# --- Prompt Building ---

## Build the system message (fixed for the entire match).
func build_system_message(player_prompt: String, vision_radius: int) -> String:
	var msg := ""
	msg += "You are an AI agent navigating a maze. Your goal is to collect three keys in order (Brass -> Jade -> Crystal) and then reach the treasure chest to win.\n\n"
	msg += "RULES:\n"
	msg += "- You move one cell per turn in a cardinal direction: NORTH, EAST, SOUTH, or WEST.\n"
	msg += "- You can only move in directions without walls. Moving into a wall wastes your turn.\n"
	msg += "- You have limited vision: you can see cells within %d steps along open paths from your position.\n" % vision_radius
	msg += "- \"Visible\" cells show walls AND items (keys, chest). \"Explored\" cells show walls only (you saw them before but can't currently see items there).\n"
	msg += "- Keys must be collected in order. You can only pick up the key matching your current progress.\n"
	msg += "- You share the maze with an opponent agent. First to open the chest wins.\n\n"
	msg += "COORDINATE SYSTEM:\n"
	msg += "- (x, y) where x increases rightward, y increases downward.\n"
	msg += "- (0, 0) is the top-left corner.\n"
	msg += "- NORTH = y-1, SOUTH = y+1, EAST = x+1, WEST = x-1.\n\n"
	msg += "OUTPUT FORMAT:\n"
	msg += "- Respond with ONLY a JSON object.\n"
	msg += "- Preferred: {\"target\": [x, y]} -- specify a visible or explored cell to navigate to. The system will auto-pathfind.\n"
	msg += "- Fallback: {\"direction\": \"NORTH|EAST|SOUTH|WEST\"} -- move one step in a cardinal direction.\n"
	msg += "- Do NOT include any explanation, reasoning, or extra text.\n\n"
	msg += "PLAYER STRATEGY:\n"
	msg += player_prompt
	return msg


## Build the state message for a specific agent at the current tick.
## All data is read live from upstream systems.
func build_state_message(agent_id: int, maze: RefCounted, fog: Node, movement: Node, keys: Node, win_con: Node, tick_count: int) -> String:
	var pos: Vector2i = movement.get_position(agent_id)
	var msg := ""

	# Header
	msg += "TURN %d\n" % tick_count
	msg += "Position: (%d, %d)\n" % [pos.x, pos.y]

	# Open directions
	var open_dirs: Array[String] = []
	for dir in [Enums.Direction.NORTH, Enums.Direction.EAST, Enums.Direction.SOUTH, Enums.Direction.WEST]:
		if maze.can_move(pos.x, pos.y, dir):
			open_dirs.append(_direction_name(dir))
	msg += "Open directions: %s\n" % ", ".join(open_dirs)

	# Visible cells
	msg += "\nVISIBLE CELLS:\n"
	var visible_cells: Array[Vector2i] = fog.get_visible_cells(agent_id)
	for cell_pos in visible_cells:
		msg += _format_cell_line(cell_pos, maze, keys, win_con, agent_id, pos, true)

	# Explored cells (optional)
	if include_explored:
		var explored_cells: Array[Vector2i] = fog.get_explored_cells(agent_id)
		if explored_cells.size() > 0:
			# Sort by Manhattan distance from agent
			explored_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				var da := absi(a.x - pos.x) + absi(a.y - pos.y)
				var db := absi(b.x - pos.x) + absi(b.y - pos.y)
				return da < db
			)
			var total_explored := explored_cells.size()
			if total_explored > max_explored_count:
				explored_cells = explored_cells.slice(0, max_explored_count)
			msg += "\nEXPLORED CELLS (walls only, items may have changed):\n"
			if total_explored > max_explored_count:
				msg += "(showing nearest %d of %d explored)\n" % [max_explored_count, total_explored]
			for cell_pos in explored_cells:
				msg += _format_cell_line(cell_pos, maze, keys, win_con, agent_id, pos, false)

	# Visited cells
	var visited: Array[Vector2i] = movement.get_visited_cells(agent_id)
	if visited.size() > 0:
		# Reverse for most-recent-first
		var reversed: Array[Vector2i] = []
		for i in range(visited.size() - 1, -1, -1):
			reversed.append(visited[i])
		var total_visited := reversed.size()
		if total_visited > max_visited_count:
			reversed = reversed.slice(0, max_visited_count)
		msg += "\nVISITED (cells you have been to):\n"
		if total_visited > max_visited_count:
			msg += "(showing last %d of %d visited)\n" % [max_visited_count, total_visited]
		var coords: Array[String] = []
		for v in reversed:
			coords.append("(%d,%d)" % [v.x, v.y])
		msg += " ".join(coords) + "\n"

	# Objective
	var agent_state: int = keys.get_agent_progress(agent_id)
	var objective := _get_objective_text(agent_state)
	var keys_count := keys.get_keys_collected_count(agent_id)
	msg += "\nOBJECTIVE: %s\n" % objective
	msg += "Keys collected: %d/3\n" % keys_count

	_last_prompts[agent_id] = msg
	return msg


## Format a single cell line for Visible or Explored sections.
func _format_cell_line(cell_pos: Vector2i, maze: RefCounted, keys: Node, win_con: Node, agent_id: int, agent_pos: Vector2i, include_markers: bool) -> String:
	var line := "(%d,%d) open:" % [cell_pos.x, cell_pos.y]

	# Collect open directions
	var dirs: Array[String] = []
	var open_count := 0
	for dir in [Enums.Direction.NORTH, Enums.Direction.EAST, Enums.Direction.SOUTH, Enums.Direction.WEST]:
		if maze.can_move(cell_pos.x, cell_pos.y, dir):
			dirs.append(_direction_abbrev(dir))
			open_count += 1
	line += ",".join(dirs)

	# Annotations
	var annotations: Array[String] = []
	if cell_pos == agent_pos:
		annotations.append("[YOU]")

	if include_markers:
		# Key markers (only active and matching agent's next key for display)
		var markers: Array = maze.get_markers_at(cell_pos.x, cell_pos.y)
		for marker in markers:
			if marker == Enums.MarkerType.KEY_BRASS and keys.is_key_active(Enums.MarkerType.KEY_BRASS):
				annotations.append("[KEY:BRASS]")
			elif marker == Enums.MarkerType.KEY_JADE and keys.is_key_active(Enums.MarkerType.KEY_JADE):
				annotations.append("[KEY:JADE]")
			elif marker == Enums.MarkerType.KEY_CRYSTAL and keys.is_key_active(Enums.MarkerType.KEY_CRYSTAL):
				annotations.append("[KEY:CRYSTAL]")
			elif marker == Enums.MarkerType.CHEST and win_con.is_chest_active():
				annotations.append("[CHEST]")

	if open_count == 1:
		annotations.append("(dead end)")

	if annotations.size() > 0:
		line += " " + " ".join(annotations)

	line += "\n"
	return line


func _direction_name(dir: int) -> String:
	match dir:
		Enums.Direction.NORTH: return "NORTH"
		Enums.Direction.EAST: return "EAST"
		Enums.Direction.SOUTH: return "SOUTH"
		Enums.Direction.WEST: return "WEST"
	return "UNKNOWN"


func _direction_abbrev(dir: int) -> String:
	match dir:
		Enums.Direction.NORTH: return "N"
		Enums.Direction.EAST: return "E"
		Enums.Direction.SOUTH: return "S"
		Enums.Direction.WEST: return "W"
	return "?"


func _get_objective_text(agent_state: int) -> String:
	match agent_state:
		Enums.AgentKeyState.NEED_BRASS: return "Find the Brass key"
		Enums.AgentKeyState.NEED_JADE: return "Find the Jade key"
		Enums.AgentKeyState.NEED_CRYSTAL: return "Find the Crystal key"
		Enums.AgentKeyState.KEYS_COMPLETE: return "Find the treasure chest"
	return "Unknown"


## Get the last prompt built for an agent (debug).
func get_last_prompt(agent_id: int) -> String:
	if _last_prompts.has(agent_id):
		return _last_prompts[agent_id]
	return ""


## Rough token estimation (1 token ~ 4 chars).
func get_token_estimate(text: String) -> int:
	return text.length() / 4
