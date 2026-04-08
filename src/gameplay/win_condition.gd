## Win Condition / Chest - manages chest activation and victory resolution.
## Instantiated as a child node in the Match scene.
## See design/gdd/win-condition.md for full specification.
class_name WinConditionManager
extends Node

# --- Signals ---
signal chest_activated
signal chest_opened(agent_id: int)

# --- State ---
var _chest_state: int = Enums.ChestState.INACTIVE
var _chest_position: Vector2i = Vector2i(-1, -1)
var _agent_eligibility: Dictionary = {}  # agent_id -> AgentEligibility
var _pending_openers: Array[int] = []
var _maze: RefCounted = null
var _active: bool = false  # Only process in PLAYING state


## Initialize with a finalized MazeData. Resets all internal state.
func initialize(maze: RefCounted) -> void:
	_maze = maze
	_chest_state = Enums.ChestState.INACTIVE
	_chest_position = maze.get_marker_position(Enums.MarkerType.CHEST)
	_agent_eligibility.clear()
	_pending_openers.clear()
	_active = false

	if _chest_position == Vector2i(-1, -1):
		push_error("WinCondition: Missing CHEST marker in MazeData")

	for agent_id in [0, 1]:
		_agent_eligibility[agent_id] = Enums.AgentEligibility.INELIGIBLE


## Reset to default empty state.
func reset() -> void:
	_chest_state = Enums.ChestState.INACTIVE
	_chest_position = Vector2i(-1, -1)
	_agent_eligibility.clear()
	_pending_openers.clear()
	_maze = null
	_active = false


## Enable/disable victory checking (PLAYING state).
func set_active(active: bool) -> void:
	_active = active


# --- Query Interface ---

func is_chest_active() -> bool:
	return _chest_state == Enums.ChestState.ACTIVE


func get_chest_position() -> Vector2i:
	return _chest_position


func is_agent_eligible(agent_id: int) -> bool:
	if not _agent_eligibility.has(agent_id):
		return false
	return _agent_eligibility[agent_id] == Enums.AgentEligibility.ELIGIBLE


# --- Signal Handlers ---

## Called when KeyCollection emits chest_unlocked(agent_id).
func _on_chest_unlocked(agent_id: int) -> void:
	# Mark agent as eligible
	_agent_eligibility[agent_id] = Enums.AgentEligibility.ELIGIBLE

	# Activate chest on first unlock
	if _chest_state == Enums.ChestState.INACTIVE:
		_chest_state = Enums.ChestState.ACTIVE
		chest_activated.emit()


## Called when GridMovement emits mover_moved.
func _on_mover_moved(mover_id: int, _old_pos: Vector2i, new_pos: Vector2i) -> void:
	if not _active:
		return
	if _chest_state != Enums.ChestState.ACTIVE:
		return
	if not is_agent_eligible(mover_id):
		return
	if new_pos != _chest_position:
		return

	# Agent is eligible and at chest position
	if not _pending_openers.has(mover_id):
		_pending_openers.append(mover_id)


## Resolve pending openers at tick end. Returns result dictionary.
## Called via call_deferred at end of tick.
func resolve_pending() -> Dictionary:
	if _pending_openers.size() == 0:
		_pending_openers.clear()
		return {"type": "none"}

	var result: Dictionary
	if _pending_openers.size() == 1:
		var winner_id: int = _pending_openers[0]
		chest_opened.emit(winner_id)
		result = {"type": "win", "winner_id": winner_id}
	else:
		# Two agents at chest same tick = draw
		result = {"type": "draw"}

	_pending_openers.clear()
	return result
