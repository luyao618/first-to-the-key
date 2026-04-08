## Key Collection - manages key activation phases and per-agent pickup progress.
## Autoload singleton registered as "KeyCollection".
## See design/gdd/key-collection.md for full specification.
class_name KeyCollectionManager
extends Node

# --- Signals ---
signal key_collected(agent_id: int, key_type: int)
signal key_activated(key_type: int)
signal chest_unlocked(agent_id: int)

# --- State ---
var _global_phase: int = Enums.GlobalKeyPhase.BRASS_ACTIVE
var _agent_progress: Dictionary = {}  # agent_id -> AgentKeyState
var _key_positions: Dictionary = {}   # MarkerType -> Vector2i
var _maze: RefCounted = null
var _active: bool = false  # Only process pickups in PLAYING state


## Initialize with a finalized MazeData. Resets all internal state.
func initialize(maze: RefCounted) -> void:
	_maze = maze
	_global_phase = Enums.GlobalKeyPhase.BRASS_ACTIVE
	_agent_progress.clear()
	_key_positions.clear()
	_active = false

	# Cache key positions
	for key_type in Enums.KEY_SEQUENCE:
		var pos: Vector2i = maze.get_marker_position(key_type)
		if pos == Vector2i(-1, -1):
			push_error("KeyCollection: Missing key marker %d in MazeData" % key_type)
		_key_positions[key_type] = pos

	# Initialize agent progress
	for agent_id in [0, 1]:
		_agent_progress[agent_id] = Enums.AgentKeyState.NEED_BRASS


## Reset to default empty state.
func reset() -> void:
	_global_phase = Enums.GlobalKeyPhase.BRASS_ACTIVE
	_agent_progress.clear()
	_key_positions.clear()
	_maze = null
	_active = false


## Enable pickup processing (called when PLAYING state begins).
func set_active(active: bool) -> void:
	_active = active


# --- Query Interface ---

func get_global_phase() -> int:
	return _global_phase


func get_agent_progress(agent_id: int) -> int:
	if not _agent_progress.has(agent_id):
		return Enums.AgentKeyState.NEED_BRASS
	return _agent_progress[agent_id]


func is_key_active(key_type: int) -> bool:
	match _global_phase:
		Enums.GlobalKeyPhase.BRASS_ACTIVE:
			return key_type == Enums.MarkerType.KEY_BRASS
		Enums.GlobalKeyPhase.JADE_ACTIVE:
			return key_type == Enums.MarkerType.KEY_BRASS or key_type == Enums.MarkerType.KEY_JADE
		Enums.GlobalKeyPhase.CRYSTAL_ACTIVE, Enums.GlobalKeyPhase.ALL_COLLECTED:
			return key_type in [Enums.MarkerType.KEY_BRASS, Enums.MarkerType.KEY_JADE, Enums.MarkerType.KEY_CRYSTAL]
	return false


func get_keys_collected_count(agent_id: int) -> int:
	var state := get_agent_progress(agent_id)
	match state:
		Enums.AgentKeyState.NEED_BRASS: return 0
		Enums.AgentKeyState.NEED_JADE: return 1
		Enums.AgentKeyState.NEED_CRYSTAL: return 2
		Enums.AgentKeyState.KEYS_COMPLETE: return 3
	return 0


## Get the next key this agent needs, or -1 if all collected.
func get_next_key(agent_id: int) -> int:
	var state := get_agent_progress(agent_id)
	match state:
		Enums.AgentKeyState.NEED_BRASS: return Enums.MarkerType.KEY_BRASS
		Enums.AgentKeyState.NEED_JADE: return Enums.MarkerType.KEY_JADE
		Enums.AgentKeyState.NEED_CRYSTAL: return Enums.MarkerType.KEY_CRYSTAL
	return -1


# --- Movement Handler ---

## Called when an agent moves to a new cell. Checks for key pickup.
func _on_mover_moved(mover_id: int, _old_pos: Vector2i, new_pos: Vector2i) -> void:
	if not _active:
		return
	if not _agent_progress.has(mover_id):
		return

	var agent_state: int = _agent_progress[mover_id]
	if agent_state == Enums.AgentKeyState.KEYS_COMPLETE:
		return  # Already collected all keys

	# Determine what key this agent needs next
	var next_key: int = get_next_key(mover_id)
	if next_key == -1:
		return

	# Check: is the key active and is the agent on the key's cell?
	if not is_key_active(next_key):
		return
	if not _key_positions.has(next_key):
		return
	if _key_positions[next_key] != new_pos:
		return

	# Pickup!
	_advance_agent(mover_id, next_key)


## Advance agent progress after successful pickup.
func _advance_agent(agent_id: int, picked_key: int) -> void:
	var old_state: int = _agent_progress[agent_id]

	# Advance agent state
	match old_state:
		Enums.AgentKeyState.NEED_BRASS:
			_agent_progress[agent_id] = Enums.AgentKeyState.NEED_JADE
		Enums.AgentKeyState.NEED_JADE:
			_agent_progress[agent_id] = Enums.AgentKeyState.NEED_CRYSTAL
		Enums.AgentKeyState.NEED_CRYSTAL:
			_agent_progress[agent_id] = Enums.AgentKeyState.KEYS_COMPLETE

	key_collected.emit(agent_id, picked_key)

	# Check if this pickup should advance the global phase
	_try_advance_global_phase(picked_key)

	# If agent completed all keys, emit chest_unlocked
	if _agent_progress[agent_id] == Enums.AgentKeyState.KEYS_COMPLETE:
		chest_unlocked.emit(agent_id)


## Try to advance global key activation phase.
func _try_advance_global_phase(picked_key: int) -> void:
	match picked_key:
		Enums.MarkerType.KEY_BRASS:
			if _global_phase == Enums.GlobalKeyPhase.BRASS_ACTIVE:
				_global_phase = Enums.GlobalKeyPhase.JADE_ACTIVE
				key_activated.emit(Enums.MarkerType.KEY_JADE)
		Enums.MarkerType.KEY_JADE:
			if _global_phase == Enums.GlobalKeyPhase.JADE_ACTIVE:
				_global_phase = Enums.GlobalKeyPhase.CRYSTAL_ACTIVE
				key_activated.emit(Enums.MarkerType.KEY_CRYSTAL)
		Enums.MarkerType.KEY_CRYSTAL:
			if _global_phase == Enums.GlobalKeyPhase.CRYSTAL_ACTIVE:
				_global_phase = Enums.GlobalKeyPhase.ALL_COLLECTED
