# Feature Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the four Feature-layer systems (Key Collection, Win Condition, LLM Information Format, LLM Agent Integration) that depend on Foundation + Core layers and enable the complete game loop.

**Architecture:** KeyCollection is an Autoload (Node) managing global key activation phases and per-agent pickup progress, triggered by GridMovement's mover_moved signal. WinConditionManager is a scene-local Node managing chest activation and deferred tick-end victory resolution. LLMInformationFormat is a RefCounted stateless transformer that builds prompts and parses LLM responses. LLMAgentManager is an Autoload (Node) managing per-agent AgentBrain decision loops with path queues, HTTPRequest API calls, and decision point detection.

**Tech Stack:** Godot 4.6, GDScript, GUT 9.x, JSON config, OpenAI-compatible Chat Completions API

---

## File Structure

```
src/
  gameplay/
    key_collection.gd           # KeyCollection (Node, Autoload) - key activation + pickup
    win_condition.gd             # WinConditionManager (Node) - chest activation + victory
  ai/
    llm_info_format.gd          # LLMInformationFormat (RefCounted) - prompt builder + response parser
    llm_agent_manager.gd        # LLMAgentManager (Node, Autoload) - decision engine + API

src/shared/
    enums.gd                     # Add GlobalKeyPhase, AgentKeyState, ChestState, AgentEligibility, RequestState enums (modify existing)

assets/data/
    game_config.json             # Add llm_format section (modify existing)

tests/
  unit/
    test_key_collection.gd       # KeyCollection unit tests
    test_win_condition.gd        # WinConditionManager unit tests
    test_llm_info_format.gd      # LLMInformationFormat unit tests
    test_llm_agent_manager.gd    # LLMAgentManager unit tests
```

---

### Task 0: Add Feature Layer Enums and Update Config

**Files:**
- Modify: `src/shared/enums.gd`
- Modify: `assets/data/game_config.json`
- Modify: `project.godot`

- [ ] **Step 1: Add Feature Layer enums to shared enums**

Append the following to `src/shared/enums.gd` (after `CellVisibility` enum added by Core Layer):

```gdscript
enum GlobalKeyPhase { BRASS_ACTIVE, JADE_ACTIVE, CRYSTAL_ACTIVE, ALL_COLLECTED }

enum AgentKeyState { NEED_BRASS, NEED_JADE, NEED_CRYSTAL, KEYS_COMPLETE }

enum ChestState { INACTIVE, ACTIVE }

enum AgentEligibility { INELIGIBLE, ELIGIBLE }

enum RequestState { IDLE, IN_FLIGHT }

## Key sequence: the fixed order of key collection.
const KEY_SEQUENCE: Array = [
	MarkerType.KEY_BRASS,
	MarkerType.KEY_JADE,
	MarkerType.KEY_CRYSTAL,
]

## MoveDirection -> opposite mapping.
const OPPOSITE_MOVE_DIRECTION: Dictionary = {
	MoveDirection.NORTH: MoveDirection.SOUTH,
	MoveDirection.SOUTH: MoveDirection.NORTH,
	MoveDirection.EAST: MoveDirection.WEST,
	MoveDirection.WEST: MoveDirection.EAST,
}
```

- [ ] **Step 2: Add LLM format config to game_config.json**

The `llm_format` section already exists in `game_config.json` from Foundation Layer. Verify it contains:

```json
{
    "llm_format": {
        "include_ascii_map": false,
        "include_explored": true,
        "max_visited_count": 20,
        "max_explored_count": 30
    }
}
```

If missing, add it.

- [ ] **Step 3: Register KeyCollection and LLMAgentManager Autoloads in project.godot**

Add to the `[autoload]` section of `project.godot`:

```ini
KeyCollection="*res://src/gameplay/key_collection.gd"
LLMAgentManager="*res://src/ai/llm_agent_manager.gd"
```

Note: These files don't exist yet — they will be created in later tasks. Godot will show warnings but won't crash. Alternatively, defer this step until the files exist.

- [ ] **Step 4: Create directory structure**

```bash
mkdir -p src/gameplay src/ai
```

- [ ] **Step 5: Commit**

```bash
git add src/shared/enums.gd assets/data/game_config.json project.godot
git commit -m "feat: add Feature Layer enums (GlobalKeyPhase, AgentKeyState, ChestState, etc.)"
```

---

### Task 1: KeyCollection - Core Pickup Logic

**Files:**
- Create: `src/gameplay/key_collection.gd`
- Create: `tests/unit/test_key_collection.gd`

- [ ] **Step 1: Write failing tests for KeyCollection initialization and pickup**

Create `tests/unit/test_key_collection.gd`:

```gdscript
## Unit tests for KeyCollection.
extends GutTest

const KeyCollectionClass := preload("res://src/gameplay/key_collection.gd")
const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")

var kc: Node
var maze: RefCounted


func before_each() -> void:
	# Generate a valid maze
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	maze = gen.generate(5, 5)
	assert_not_null(maze, "Test maze should generate")

	kc = KeyCollectionClass.new()
	add_child_autoqfree(kc)
	kc.initialize(maze)
	kc.set_active(true)


func test_initial_global_phase_is_brass_active() -> void:
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.BRASS_ACTIVE)


func test_initial_agent_progress_is_need_brass() -> void:
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_BRASS)
	assert_eq(kc.get_agent_progress(1), Enums.AgentKeyState.NEED_BRASS)


func test_brass_is_active_initially() -> void:
	assert_true(kc.is_key_active(Enums.MarkerType.KEY_BRASS))
	assert_false(kc.is_key_active(Enums.MarkerType.KEY_JADE))
	assert_false(kc.is_key_active(Enums.MarkerType.KEY_CRYSTAL))


func test_pickup_brass_advances_agent_progress() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_JADE)
	assert_signal_emitted(kc, "key_collected")


func test_pickup_brass_activates_jade() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	assert_true(kc.is_key_active(Enums.MarkerType.KEY_JADE))
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.JADE_ACTIVE)
	assert_signal_emitted(kc, "key_activated")


func test_agent_independence() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	# Agent 0 advanced, Agent 1 still needs brass
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_JADE)
	assert_eq(kc.get_agent_progress(1), Enums.AgentKeyState.NEED_BRASS)


func test_agent_cannot_skip_keys() -> void:
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	# Brass picked up by agent 0 to activate Jade globally
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	# Agent 1 goes to Jade without picking Brass first
	watch_signals(kc)
	kc._on_mover_moved(1, Vector2i(-1, -1), jade_pos)
	assert_signal_not_emitted(kc, "key_collected")
	assert_eq(kc.get_agent_progress(1), Enums.AgentKeyState.NEED_BRASS)


func test_checkpoint_semantics_both_agents_pickup() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	# Agent 1 can also pick up brass (checkpoint, not consumed)
	watch_signals(kc)
	kc._on_mover_moved(1, Vector2i(-1, -1), brass_pos)
	assert_eq(kc.get_agent_progress(1), Enums.AgentKeyState.NEED_JADE)
	assert_signal_emitted(kc, "key_collected")


func test_key_activated_only_on_first_pickup() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	var activated_count_1 := get_signal_emit_count(kc, "key_activated")
	kc._on_mover_moved(1, Vector2i(-1, -1), brass_pos)
	var activated_count_2 := get_signal_emit_count(kc, "key_activated")
	# key_activated should only fire once (first pickup triggers Jade activation)
	assert_eq(activated_count_1, 1)
	assert_eq(activated_count_2, 1, "Second brass pickup should NOT emit key_activated again")


func test_activation_is_cumulative() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	# Brass should still be active after Jade activates
	assert_true(kc.is_key_active(Enums.MarkerType.KEY_BRASS))
	assert_true(kc.is_key_active(Enums.MarkerType.KEY_JADE))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_key_collection.gd -gexit`

Expected: FAIL - cannot preload `key_collection.gd`

- [ ] **Step 3: Implement KeyCollection**

Create `src/gameplay/key_collection.gd`:

```gdscript
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_key_collection.gd -gexit`

Expected: All 10 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/gameplay/key_collection.gd tests/unit/test_key_collection.gd
git commit -m "feat: KeyCollection with global activation phases and per-agent pickup (TDD)"
```

---

### Task 2: KeyCollection - Full Pipeline and Lifecycle Tests

**Files:**
- Modify: `tests/unit/test_key_collection.gd`

- [ ] **Step 1: Write tests for full 3-key pipeline, lifecycle, and edge cases**

Append to `tests/unit/test_key_collection.gd`:

```gdscript
func test_full_pipeline_agent_collects_all_three() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos := maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)

	watch_signals(kc)

	# Pick up Brass
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_JADE)
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.JADE_ACTIVE)

	# Pick up Jade
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_CRYSTAL)
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.CRYSTAL_ACTIVE)

	# Pick up Crystal
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.KEYS_COMPLETE)
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.ALL_COLLECTED)

	assert_eq(get_signal_emit_count(kc, "key_collected"), 3)
	assert_eq(get_signal_emit_count(kc, "key_activated"), 2)  # Jade + Crystal activation
	assert_signal_emitted(kc, "chest_unlocked")


func test_chest_unlocked_emitted_per_agent() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos := maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)

	# Agent 0 collects all
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)

	# Agent 1 also collects all
	kc._on_mover_moved(1, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(1, Vector2i(-1, -1), jade_pos)
	watch_signals(kc)
	kc._on_mover_moved(1, Vector2i(-1, -1), crystal_pos)

	assert_signal_emitted(kc, "chest_unlocked")
	# Global phase should still be ALL_COLLECTED (idempotent)
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.ALL_COLLECTED)


func test_same_tick_both_pickup_brass() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(1, Vector2i(-1, -1), brass_pos)
	# Both should advance
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_JADE)
	assert_eq(kc.get_agent_progress(1), Enums.AgentKeyState.NEED_JADE)
	# key_activated should fire only once
	assert_eq(get_signal_emit_count(kc, "key_activated"), 1)
	# key_collected should fire twice
	assert_eq(get_signal_emit_count(kc, "key_collected"), 2)


func test_moving_to_non_key_cell_no_pickup() -> void:
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), Vector2i(0, 0))
	assert_signal_not_emitted(kc, "key_collected")


func test_agent_on_inactive_key_no_pickup() -> void:
	# Jade is not yet active
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	assert_signal_not_emitted(kc, "key_collected")


func test_already_collected_key_no_repeat() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	# Move back to brass
	watch_signals(kc)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	assert_signal_not_emitted(kc, "key_collected")


func test_get_keys_collected_count() -> void:
	assert_eq(kc.get_keys_collected_count(0), 0)
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	assert_eq(kc.get_keys_collected_count(0), 1)


func test_get_next_key() -> void:
	assert_eq(kc.get_next_key(0), Enums.MarkerType.KEY_BRASS)
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	assert_eq(kc.get_next_key(0), Enums.MarkerType.KEY_JADE)


func test_initialize_resets_after_complete_game() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos := maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)

	# Re-initialize (simulates Rematch)
	kc.initialize(maze)
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.BRASS_ACTIVE)
	assert_eq(kc.get_agent_progress(0), Enums.AgentKeyState.NEED_BRASS)
	assert_eq(kc.get_agent_progress(1), Enums.AgentKeyState.NEED_BRASS)
	assert_true(kc.is_key_active(Enums.MarkerType.KEY_BRASS))
	assert_false(kc.is_key_active(Enums.MarkerType.KEY_JADE))


func test_invalid_agent_id_returns_default() -> void:
	assert_eq(kc.get_agent_progress(99), Enums.AgentKeyState.NEED_BRASS)
	assert_eq(kc.get_keys_collected_count(99), 0)
	assert_eq(kc.get_next_key(99), Enums.MarkerType.KEY_BRASS)


func test_missing_key_marker_no_crash() -> void:
	# Create a maze missing KEY_JADE
	var small_maze := MazeData.new(3, 3)
	small_maze.set_wall(0, 0, Enums.Direction.EAST, false)
	small_maze.set_wall(1, 0, Enums.Direction.EAST, false)
	small_maze.set_wall(2, 0, Enums.Direction.SOUTH, false)
	small_maze.set_wall(2, 1, Enums.Direction.SOUTH, false)
	small_maze.set_wall(2, 2, Enums.Direction.WEST, false)
	small_maze.set_wall(1, 2, Enums.Direction.WEST, false)
	small_maze.set_wall(0, 2, Enums.Direction.NORTH, false)
	small_maze.set_wall(1, 1, Enums.Direction.SOUTH, false)
	small_maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	small_maze.place_marker(2, 2, Enums.MarkerType.SPAWN_B)
	small_maze.place_marker(1, 0, Enums.MarkerType.KEY_BRASS)
	# KEY_JADE intentionally missing
	small_maze.place_marker(2, 1, Enums.MarkerType.KEY_CRYSTAL)
	small_maze.place_marker(1, 2, Enums.MarkerType.CHEST)
	# Don't finalize (missing marker), just test initialize doesn't crash
	var kc2 := KeyCollectionClass.new()
	add_child_autoqfree(kc2)
	kc2.initialize(small_maze)
	# KEY_JADE position should be (-1, -1), unreachable
	assert_eq(kc2._key_positions.get(Enums.MarkerType.KEY_JADE, Vector2i(-1, -1)), Vector2i(-1, -1))
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_key_collection.gd -gexit`

Expected: All 22 tests PASS

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_key_collection.gd
git commit -m "test: KeyCollection full pipeline, lifecycle, checkpoint semantics, edge cases"
```

---

### Task 3: WinConditionManager - Chest Activation and Victory

**Files:**
- Create: `src/gameplay/win_condition.gd`
- Create: `tests/unit/test_win_condition.gd`

- [ ] **Step 1: Write failing tests for WinConditionManager**

Create `tests/unit/test_win_condition.gd`:

```gdscript
## Unit tests for WinConditionManager.
extends GutTest

const WinConditionClass := preload("res://src/gameplay/win_condition.gd")
const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")

var wc: Node
var maze: RefCounted


func before_each() -> void:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	maze = gen.generate(5, 5)
	assert_not_null(maze, "Test maze should generate")

	wc = WinConditionClass.new()
	add_child_autoqfree(wc)
	wc.initialize(maze)


func test_initial_chest_inactive() -> void:
	assert_false(wc.is_chest_active())


func test_initial_agents_ineligible() -> void:
	assert_false(wc.is_agent_eligible(0))
	assert_false(wc.is_agent_eligible(1))


func test_chest_position_cached() -> void:
	var expected := maze.get_marker_position(Enums.MarkerType.CHEST)
	assert_eq(wc.get_chest_position(), expected)


func test_chest_unlocked_activates_chest() -> void:
	watch_signals(wc)
	wc._on_chest_unlocked(0)
	assert_true(wc.is_chest_active())
	assert_signal_emitted(wc, "chest_activated")


func test_chest_unlocked_marks_agent_eligible() -> void:
	wc._on_chest_unlocked(0)
	assert_true(wc.is_agent_eligible(0))
	assert_false(wc.is_agent_eligible(1))


func test_second_chest_unlocked_no_double_activate() -> void:
	watch_signals(wc)
	wc._on_chest_unlocked(0)
	wc._on_chest_unlocked(1)
	assert_eq(get_signal_emit_count(wc, "chest_activated"), 1)
	assert_true(wc.is_agent_eligible(1))


func test_eligible_agent_at_chest_triggers_pending() -> void:
	wc._on_chest_unlocked(0)
	wc.set_active(true)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	assert_eq(wc._pending_openers.size(), 1)
	assert_has(wc._pending_openers, 0)


func test_ineligible_agent_at_chest_no_trigger() -> void:
	wc._on_chest_unlocked(0)  # Only agent 0 is eligible
	wc.set_active(true)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(1, Vector2i(-1, -1), chest_pos)
	assert_eq(wc._pending_openers.size(), 0)


func test_inactive_chest_no_trigger() -> void:
	# Don't activate chest
	wc.set_active(true)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	assert_eq(wc._pending_openers.size(), 0)


func test_resolve_single_winner() -> void:
	wc._on_chest_unlocked(0)
	wc.set_active(true)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	watch_signals(wc)
	var result := wc.resolve_pending()
	assert_eq(result["type"], "win")
	assert_eq(result["winner_id"], 0)
	assert_signal_emitted(wc, "chest_opened")


func test_resolve_draw() -> void:
	wc._on_chest_unlocked(0)
	wc._on_chest_unlocked(1)
	wc.set_active(true)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	wc._on_mover_moved(1, Vector2i(-1, -1), chest_pos)
	var result := wc.resolve_pending()
	assert_eq(result["type"], "draw")


func test_resolve_empty_no_action() -> void:
	var result := wc.resolve_pending()
	assert_eq(result["type"], "none")


func test_pending_cleared_after_resolve() -> void:
	wc._on_chest_unlocked(0)
	wc.set_active(true)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	wc.resolve_pending()
	assert_eq(wc._pending_openers.size(), 0)


func test_not_active_ignores_mover_moved() -> void:
	wc._on_chest_unlocked(0)
	# set_active not called (default false)
	var chest_pos := wc.get_chest_position()
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	assert_eq(wc._pending_openers.size(), 0)


func test_reset_clears_all() -> void:
	wc._on_chest_unlocked(0)
	wc.set_active(true)
	wc.reset()
	assert_false(wc.is_chest_active())
	assert_false(wc.is_agent_eligible(0))
	assert_eq(wc._pending_openers.size(), 0)


func test_initialize_resets_state() -> void:
	wc._on_chest_unlocked(0)
	wc.initialize(maze)
	assert_false(wc.is_chest_active())
	assert_false(wc.is_agent_eligible(0))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_win_condition.gd -gexit`

Expected: FAIL - cannot preload `win_condition.gd`

- [ ] **Step 3: Implement WinConditionManager**

Create `src/gameplay/win_condition.gd`:

```gdscript
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_win_condition.gd -gexit`

Expected: All 17 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/gameplay/win_condition.gd tests/unit/test_win_condition.gd
git commit -m "feat: WinConditionManager with chest activation, eligibility, deferred resolution"
```

---

### Task 4: LLMInformationFormat - Response Parsing

**Files:**
- Create: `src/ai/llm_info_format.gd`
- Create: `tests/unit/test_llm_info_format.gd`

- [ ] **Step 1: Write failing tests for response parsing**

Create `tests/unit/test_llm_info_format.gd`:

```gdscript
## Unit tests for LLMInformationFormat.
extends GutTest

const LLMInfoFormat := preload("res://src/ai/llm_info_format.gd")

var fmt: RefCounted


func before_each() -> void:
	fmt = LLMInfoFormat.new()


# --- Response Parsing Tests ---

func test_parse_target() -> void:
	var result := fmt.parse_response('{"target": [8, 5]}')
	assert_eq(result["type"], "TARGET")
	assert_eq(result["pos"], Vector2i(8, 5))


func test_parse_direction_north() -> void:
	var result := fmt.parse_response('{"direction": "NORTH"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.NORTH)


func test_parse_direction_east() -> void:
	var result := fmt.parse_response('{"direction": "EAST"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.EAST)


func test_parse_direction_south() -> void:
	var result := fmt.parse_response('{"direction": "SOUTH"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.SOUTH)


func test_parse_direction_west() -> void:
	var result := fmt.parse_response('{"direction": "WEST"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.WEST)


func test_parse_target_priority_over_direction() -> void:
	var result := fmt.parse_response('{"target": [8, 5], "direction": "NORTH"}')
	assert_eq(result["type"], "TARGET")
	assert_eq(result["pos"], Vector2i(8, 5))


func test_parse_direction_lowercase() -> void:
	var result := fmt.parse_response('{"direction": "north"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.NORTH)


func test_parse_direction_abbreviation_n() -> void:
	var result := fmt.parse_response('{"direction": "N"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.NORTH)


func test_parse_direction_alias_up() -> void:
	var result := fmt.parse_response('{"direction": "UP"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.NORTH)


func test_parse_direction_alias_right() -> void:
	var result := fmt.parse_response('{"direction": "RIGHT"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.EAST)


func test_parse_direction_alias_down() -> void:
	var result := fmt.parse_response('{"direction": "DOWN"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.SOUTH)


func test_parse_direction_alias_left() -> void:
	var result := fmt.parse_response('{"direction": "LEFT"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.WEST)


func test_parse_json_with_surrounding_text() -> void:
	var result := fmt.parse_response('I think north. {"target": [3, 2]}')
	assert_eq(result["type"], "TARGET")
	assert_eq(result["pos"], Vector2i(3, 2))


func test_parse_empty_string() -> void:
	var result := fmt.parse_response("")
	assert_eq(result["type"], "NONE")


func test_parse_invalid_direction() -> void:
	var result := fmt.parse_response('{"direction": "NORTHEAST"}')
	assert_eq(result["type"], "NONE")


func test_parse_missing_fields() -> void:
	var result := fmt.parse_response('{"foo": "bar"}')
	assert_eq(result["type"], "NONE")


func test_parse_no_json() -> void:
	var result := fmt.parse_response("not json at all")
	assert_eq(result["type"], "NONE")


func test_parse_invalid_target_format() -> void:
	var result := fmt.parse_response('{"target": "invalid"}')
	assert_eq(result["type"], "NONE")


func test_parse_target_wrong_array_size() -> void:
	var result := fmt.parse_response('{"target": [1]}')
	assert_eq(result["type"], "NONE")


func test_parse_invalid_target_falls_back_to_direction() -> void:
	var result := fmt.parse_response('{"target": "bad", "direction": "SOUTH"}')
	assert_eq(result["type"], "DIRECTION")
	assert_eq(result["dir"], Enums.MoveDirection.SOUTH)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_llm_info_format.gd -gexit`

Expected: FAIL - cannot preload `llm_info_format.gd`

- [ ] **Step 3: Implement LLMInformationFormat with response parsing**

Create `src/ai/llm_info_format.gd`:

```gdscript
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_llm_info_format.gd -gexit`

Expected: All 21 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/ai/llm_info_format.gd tests/unit/test_llm_info_format.gd
git commit -m "feat: LLMInformationFormat with response parsing and prompt builder (TDD)"
```

---

### Task 5: LLMInformationFormat - Prompt Building Tests

**Files:**
- Modify: `tests/unit/test_llm_info_format.gd`

- [ ] **Step 1: Write tests for prompt building**

Append to `tests/unit/test_llm_info_format.gd`:

```gdscript
# --- Prompt Building Tests ---
# These tests require a full game setup: maze, fog, movement, keys, win_con

const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")
const FogOfWar := preload("res://src/core/fog_of_war.gd")
const GridMovement := preload("res://src/core/grid_movement.gd")
const KeyCollectionClass := preload("res://src/gameplay/key_collection.gd")
const WinConditionClass := preload("res://src/gameplay/win_condition.gd")

var maze: RefCounted
var fog_node: Node
var gm: Node
var kc: Node
var wc: Node


func _setup_game() -> void:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	maze = gen.generate(5, 5)
	assert_not_null(maze)

	fog_node = FogOfWar.new()
	add_child_autoqfree(fog_node)
	fog_node.initialize(maze, [0, 1])

	gm = GridMovement.new()
	gm.maze = maze
	gm.fog = fog_node
	add_child_autoqfree(gm)
	gm.initialize()

	kc = KeyCollectionClass.new()
	add_child_autoqfree(kc)
	kc.initialize(maze)
	kc.set_active(true)

	wc = WinConditionClass.new()
	add_child_autoqfree(wc)
	wc.initialize(maze)


func test_build_system_message_contains_rules() -> void:
	var msg := fmt.build_system_message("Go north always", 3)
	assert_string_contains(msg, "You are an AI agent navigating a maze")
	assert_string_contains(msg, "COORDINATE SYSTEM")
	assert_string_contains(msg, "OUTPUT FORMAT")
	assert_string_contains(msg, "Go north always")


func test_build_system_message_includes_vision_radius() -> void:
	var msg := fmt.build_system_message("test", 5)
	assert_string_contains(msg, "5 steps")


func test_build_system_message_empty_prompt() -> void:
	var msg := fmt.build_system_message("", 3)
	assert_string_contains(msg, "PLAYER STRATEGY:")


func test_build_state_message_contains_position() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	var pos := gm.get_position(0)
	assert_string_contains(msg, "Position: (%d, %d)" % [pos.x, pos.y])


func test_build_state_message_contains_turn() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 42)
	assert_string_contains(msg, "TURN 42")


func test_build_state_message_contains_open_directions() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	assert_string_contains(msg, "Open directions:")


func test_build_state_message_contains_visible_cells() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	assert_string_contains(msg, "VISIBLE CELLS:")


func test_build_state_message_contains_you_marker() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	assert_string_contains(msg, "[YOU]")


func test_build_state_message_contains_objective() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	assert_string_contains(msg, "OBJECTIVE: Find the Brass key")
	assert_string_contains(msg, "Keys collected: 0/3")


func test_build_state_message_visited_section() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	assert_string_contains(msg, "VISITED")


func test_state_message_fog_compliance_no_unknown_cells() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	# The prompt should not contain coordinates that are UNKNOWN for this agent
	# We can't easily test every cell, but verify visible cells are present
	var visible := fog_node.get_visible_cells(0)
	for cell_pos in visible:
		assert_string_contains(msg, "(%d,%d)" % [cell_pos.x, cell_pos.y])


func test_inactive_key_not_in_prompt() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	# Jade and Crystal should NOT appear in prompt (not yet active)
	assert_does_not_have(msg, "[KEY:JADE]")
	assert_does_not_have(msg, "[KEY:CRYSTAL]")


func test_inactive_chest_not_in_prompt() -> void:
	_setup_game()
	var msg := fmt.build_state_message(0, maze, fog_node, gm, kc, wc, 1)
	assert_does_not_have(msg, "[CHEST]")


func test_token_estimate() -> void:
	var estimate := fmt.get_token_estimate("Hello world this is a test")
	# 26 chars / 4 = 6 tokens (roughly)
	assert_gte(estimate, 5)
	assert_lte(estimate, 10)


## Helper to assert string does NOT contain substring.
func assert_does_not_have(text: String, substring: String) -> void:
	assert_eq(text.find(substring), -1,
		"Expected text to NOT contain '%s'" % substring)
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_llm_info_format.gd -gexit`

Expected: All 35 tests PASS (21 parsing + 14 building)

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_llm_info_format.gd
git commit -m "test: LLMInformationFormat prompt building, FoW compliance, objective text"
```

---

### Task 6: LLMAgentManager - Path Queue, Auto-Advance, Decision Points

**Files:**
- Create: `src/ai/llm_agent_manager.gd`
- Create: `tests/unit/test_llm_agent_manager.gd`

- [ ] **Step 1: Write failing tests for path queue and decision point logic**

Create `tests/unit/test_llm_agent_manager.gd`:

```gdscript
## Unit tests for LLMAgentManager.
## Tests focus on path queue, auto-advance, and decision point detection.
## API integration tests are separate (they mock HTTP responses).
extends GutTest

const LLMAgentClass := preload("res://src/ai/llm_agent_manager.gd")
const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")
const FogOfWar := preload("res://src/core/fog_of_war.gd")
const GridMovement := preload("res://src/core/grid_movement.gd")
const KeyCollectionClass := preload("res://src/gameplay/key_collection.gd")
const WinConditionClass := preload("res://src/gameplay/win_condition.gd")
const LLMInfoFormat := preload("res://src/ai/llm_info_format.gd")

var mgr: Node
var maze: RefCounted
var fog_node: Node
var gm: Node
var kc: Node
var wc: Node


func before_each() -> void:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	maze = gen.generate(5, 5)
	assert_not_null(maze, "Test maze should generate")

	fog_node = FogOfWar.new()
	add_child_autoqfree(fog_node)
	fog_node.initialize(maze, [0, 1])

	gm = GridMovement.new()
	gm.maze = maze
	gm.fog = fog_node
	add_child_autoqfree(gm)
	gm.initialize()

	kc = KeyCollectionClass.new()
	add_child_autoqfree(kc)
	kc.initialize(maze)
	kc.set_active(true)

	wc = WinConditionClass.new()
	add_child_autoqfree(wc)
	wc.initialize(maze)

	mgr = LLMAgentClass.new()
	add_child_autoqfree(mgr)
	mgr.maze = maze
	mgr.movement = gm
	mgr.fog = fog_node
	mgr.keys = kc
	mgr.win_condition = wc
	mgr.initialize()


# --- Decision Point Detection ---

func test_is_decision_point_intersection() -> void:
	# Find an intersection in the maze (cell with 3+ open directions)
	var found := false
	for y in range(maze.height):
		for x in range(maze.width):
			var neighbors := maze.get_neighbors(x, y)
			if neighbors.size() >= 3:
				# It's an intersection regardless of last_dir
				assert_true(mgr._is_decision_point(Vector2i(x, y), Enums.MoveDirection.NORTH))
				found = true
				break
		if found:
			break
	if not found:
		pass_test("No intersection found in 5x5 maze (possible for perfect maze)")


func test_is_decision_point_dead_end() -> void:
	# Find a dead end (cell with only 1 open direction)
	for y in range(maze.height):
		for x in range(maze.width):
			var neighbors := maze.get_neighbors(x, y)
			if neighbors.size() == 1:
				assert_true(mgr._is_decision_point(Vector2i(x, y), Enums.MoveDirection.NORTH))
				return
	pass_test("No dead end found in maze")


func test_is_not_decision_point_straight() -> void:
	# Find a straight corridor (cell with exactly 2 open directions that are opposite)
	for y in range(maze.height):
		for x in range(maze.width):
			var open_dirs: Array[int] = []
			for dir in [Enums.Direction.NORTH, Enums.Direction.EAST, Enums.Direction.SOUTH, Enums.Direction.WEST]:
				if maze.can_move(x, y, dir):
					open_dirs.append(dir)
			if open_dirs.size() == 2:
				# Use one direction as last_dir, the other should be auto-advance
				var last_move := _dir_to_move_dir(open_dirs[0])
				var reverse := Enums.OPPOSITE_MOVE_DIRECTION[last_move]
				# If the other open direction is the reverse, it's a corridor
				var other_move := _dir_to_move_dir(open_dirs[1])
				if other_move == reverse:
					# Coming from open_dirs[0], only exit is open_dirs[1] (reverse = last_dir's opposite)
					# Actually this is straight: exclude last_dir's reverse, 1 forward option
					assert_false(mgr._is_decision_point(Vector2i(x, y), last_move),
						"Straight corridor should not be a decision point")
					return
	pass_test("No straight corridor found")


# --- Auto-Advance ---

func test_get_auto_direction_straight() -> void:
	# Find a cell that is a straight corridor
	for y in range(maze.height):
		for x in range(maze.width):
			var open_dirs: Array[int] = []
			for dir in [Enums.Direction.NORTH, Enums.Direction.EAST, Enums.Direction.SOUTH, Enums.Direction.WEST]:
				if maze.can_move(x, y, dir):
					open_dirs.append(dir)
			if open_dirs.size() == 2:
				var move_dir_0 := _dir_to_move_dir(open_dirs[0])
				var move_dir_1 := _dir_to_move_dir(open_dirs[1])
				# If coming from direction 0, auto should go direction 1
				var result := mgr._get_auto_direction(Vector2i(x, y), move_dir_0)
				# The auto direction should be the other open direction (not the reverse of last_dir)
				var reverse_of_0 := Enums.OPPOSITE_MOVE_DIRECTION[move_dir_0]
				if move_dir_1 != reverse_of_0:
					assert_eq(result, move_dir_1)
				else:
					# move_dir_1 IS the reverse, meaning there's no forward direction
					assert_eq(result, Enums.MoveDirection.NONE)
				return
	pass_test("No straight corridor found")


func test_get_auto_direction_none_at_decision_point() -> void:
	# At a decision point, auto direction should be NONE
	for y in range(maze.height):
		for x in range(maze.width):
			var neighbors := maze.get_neighbors(x, y)
			if neighbors.size() >= 3:
				var result := mgr._get_auto_direction(Vector2i(x, y), Enums.MoveDirection.NORTH)
				assert_eq(result, Enums.MoveDirection.NONE)
				return
	pass_test("No intersection found")


# --- Path Queue ---

func test_replace_queue_generates_directions() -> void:
	var brain := mgr.get_brain(0)
	var pos := gm.get_position(0)
	# Find a reachable target
	var target := _find_reachable_target(pos)
	if target == Vector2i(-1, -1):
		pass_test("No reachable target found")
		return
	mgr._replace_queue(brain, target)
	assert_gt(brain["path_queue"].size(), 0, "Queue should have directions")


func test_replace_queue_same_position_clears() -> void:
	var brain := mgr.get_brain(0)
	var pos := gm.get_position(0)
	mgr._replace_queue(brain, pos)
	assert_eq(brain["path_queue"].size(), 0, "Same position should clear queue")


func test_replace_queue_truncates_at_max() -> void:
	var brain := mgr.get_brain(0)
	brain["max_queue_length"] = 3
	var pos := gm.get_position(0)
	# Find a distant target
	var target := _find_distant_target(pos, 5)
	if target == Vector2i(-1, -1):
		pass_test("No distant target found")
		return
	mgr._replace_queue(brain, target)
	assert_lte(brain["path_queue"].size(), 3, "Queue should be truncated to max_queue_length")


func test_consume_queue_pops_front() -> void:
	var brain := mgr.get_brain(0)
	brain["path_queue"] = [Enums.MoveDirection.NORTH, Enums.MoveDirection.EAST] as Array[int]
	var dir := mgr._consume_queue(brain)
	assert_eq(dir, Enums.MoveDirection.NORTH)
	assert_eq(brain["path_queue"].size(), 1)


func test_consume_empty_queue_returns_none() -> void:
	var brain := mgr.get_brain(0)
	brain["path_queue"].clear()
	var dir := mgr._consume_queue(brain)
	assert_eq(dir, Enums.MoveDirection.NONE)


# --- Brain State ---

func test_initial_brain_state() -> void:
	var brain := mgr.get_brain(0)
	assert_eq(brain["agent_id"], 0)
	assert_eq(brain["path_queue"].size(), 0)
	assert_eq(brain["last_move_direction"], Enums.MoveDirection.NONE)
	assert_eq(brain["request_state"], Enums.RequestState.IDLE)
	assert_eq(brain["total_api_calls"], 0)
	assert_eq(brain["total_idle_ticks"], 0)


func test_get_brain_invalid_id() -> void:
	var brain := mgr.get_brain(99)
	assert_null(brain)


func test_reset_clears_brains() -> void:
	mgr.reset()
	assert_eq(mgr._brains.size(), 0)


# --- Helpers ---

func _dir_to_move_dir(dir: int) -> int:
	match dir:
		Enums.Direction.NORTH: return Enums.MoveDirection.NORTH
		Enums.Direction.EAST: return Enums.MoveDirection.EAST
		Enums.Direction.SOUTH: return Enums.MoveDirection.SOUTH
		Enums.Direction.WEST: return Enums.MoveDirection.WEST
	return Enums.MoveDirection.NONE


func _find_reachable_target(from: Vector2i) -> Vector2i:
	# Find any cell reachable from 'from' that isn't 'from'
	for y in range(maze.height):
		for x in range(maze.width):
			var target := Vector2i(x, y)
			if target != from:
				var path := maze.get_shortest_path(from, target)
				if path.size() >= 2:
					return target
	return Vector2i(-1, -1)


func _find_distant_target(from: Vector2i, min_dist: int) -> Vector2i:
	for y in range(maze.height):
		for x in range(maze.width):
			var target := Vector2i(x, y)
			if target != from:
				var path := maze.get_shortest_path(from, target)
				if path.size() > min_dist:
					return target
	return Vector2i(-1, -1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_llm_agent_manager.gd -gexit`

Expected: FAIL - cannot preload `llm_agent_manager.gd`

- [ ] **Step 3: Implement LLMAgentManager core (no HTTP yet)**

Create `src/ai/llm_agent_manager.gd`:

```gdscript
## LLM Agent Manager - decision engine managing per-agent AI brains.
## Autoload singleton registered as "LLMAgentManager".
## See design/gdd/llm-agent-integration.md for full specification.
class_name LLMAgentManager
extends Node

# --- Signals ---
signal api_request_sent(agent_id: int)
signal api_response_received(agent_id: int)
signal api_error(agent_id: int, error_type: String)
signal decision_made(agent_id: int, target_pos: Vector2i)
signal auto_advance(agent_id: int, direction: int)

# --- Dependencies (injected) ---
var maze: RefCounted = null
var movement: Node = null  # GridMovementManager
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

## Replace path queue with A* path from current position to target.
func _replace_queue(brain: Dictionary, target: Vector2i) -> void:
	var current_pos: Vector2i = movement.get_position(brain["agent_id"])
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
	var pos: Vector2i = movement.get_position(agent_id)

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
	var state_msg := _info_format.build_state_message(
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
	var parse_result := _info_format.parse_response(response_text)
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
	var current := movement.get_position(agent_id)
	if target == current:
		push_warning("LLMAgent: Target is current position: %s" % str(target))
		return false

	# Must be reachable
	var path := maze.get_shortest_path(current, target)
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_llm_agent_manager.gd -gexit`

Expected: All 13 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/ai/llm_agent_manager.gd tests/unit/test_llm_agent_manager.gd
git commit -m "feat: LLMAgentManager with path queue, auto-advance, decision point detection"
```

---

### Task 7: LLMAgentManager - API Response Handling and Validation Tests

**Files:**
- Modify: `tests/unit/test_llm_agent_manager.gd`

- [ ] **Step 1: Write tests for API response handling and target validation**

Append to `tests/unit/test_llm_agent_manager.gd`:

```gdscript
# --- API Response Handling ---

func test_handle_target_response_generates_queue() -> void:
	var brain := mgr.get_brain(0)
	var pos := gm.get_position(0)
	var target := _find_reachable_target(pos)
	if target == Vector2i(-1, -1):
		pass_test("No reachable target")
		return
	# Make target visible/explored
	fog_node.update_vision(0, pos)
	var vis := fog_node.get_cell_visibility(0, target.x, target.y)
	if vis == Enums.CellVisibility.UNKNOWN:
		# Move closer so target is visible
		pass_test("Target not visible - skip")
		return

	brain["pending_response"] = '{"target": [%d, %d]}' % [target.x, target.y]
	mgr._handle_api_response(brain, brain["pending_response"])
	assert_gt(brain["path_queue"].size(), 0, "Should generate path queue")


func test_handle_direction_response_single_step() -> void:
	var brain := mgr.get_brain(0)
	brain["pending_response"] = '{"direction": "EAST"}'
	mgr._handle_api_response(brain, brain["pending_response"])
	assert_eq(brain["path_queue"].size(), 1)
	assert_eq(brain["path_queue"][0], Enums.MoveDirection.EAST)


func test_handle_none_response_no_queue_change() -> void:
	var brain := mgr.get_brain(0)
	brain["path_queue"] = [Enums.MoveDirection.NORTH] as Array[int]
	mgr._handle_api_response(brain, "invalid response")
	assert_eq(brain["path_queue"].size(), 1, "NONE should not clear existing queue")


# --- Target Validation ---

func test_validate_target_out_of_bounds() -> void:
	var brain := mgr.get_brain(0)
	assert_false(mgr._validate_target(brain, Vector2i(-1, 0)))
	assert_false(mgr._validate_target(brain, Vector2i(maze.width, 0)))
	assert_false(mgr._validate_target(brain, Vector2i(0, maze.height)))


func test_validate_target_unknown_cell() -> void:
	var brain := mgr.get_brain(0)
	# Find a cell that's UNKNOWN for agent 0
	for y in range(maze.height):
		for x in range(maze.width):
			if fog_node.get_cell_visibility(0, x, y) == Enums.CellVisibility.UNKNOWN:
				assert_false(mgr._validate_target(brain, Vector2i(x, y)),
					"Unknown cell should be rejected")
				return
	pass_test("All cells visible (small maze)")


func test_validate_target_current_position() -> void:
	var brain := mgr.get_brain(0)
	var pos := gm.get_position(0)
	assert_false(mgr._validate_target(brain, pos), "Current position should be rejected")


func test_validate_target_visible_cell_accepted() -> void:
	var brain := mgr.get_brain(0)
	var pos := gm.get_position(0)
	var visible := fog_node.get_visible_cells(0)
	for v in visible:
		if v != pos:
			assert_true(mgr._validate_target(brain, v),
				"Visible cell should be accepted")
			return
	pass_test("No visible cell other than current position")


# --- Tick Processing ---

func test_first_tick_idle_no_api_key() -> void:
	# Without API key, first tick should still track idle
	var brain := mgr.get_brain(0)
	mgr._active = true
	mgr._process_brain_tick(brain, 1)
	assert_eq(brain["total_idle_ticks"], 1)


func test_tick_consumes_queue() -> void:
	var brain := mgr.get_brain(0)
	brain["last_move_direction"] = Enums.MoveDirection.EAST  # Not first tick
	var pos := gm.get_position(0)
	# Find a valid direction
	var valid_dir := Enums.MoveDirection.NONE
	for dir in [Enums.MoveDirection.EAST, Enums.MoveDirection.SOUTH]:
		var maze_dir: int
		match dir:
			Enums.MoveDirection.EAST: maze_dir = Enums.Direction.EAST
			Enums.MoveDirection.SOUTH: maze_dir = Enums.Direction.SOUTH
		if maze.can_move(pos.x, pos.y, maze_dir):
			valid_dir = dir
			break
	if valid_dir == Enums.MoveDirection.NONE:
		pass_test("No valid direction from spawn")
		return

	brain["path_queue"] = [valid_dir] as Array[int]
	mgr._active = true
	mgr._process_brain_tick(brain, 1)
	assert_eq(brain["path_queue"].size(), 0, "Queue should be consumed")


# --- Statistics ---

func test_statistics_reset() -> void:
	var brain := mgr.get_brain(0)
	brain["total_api_calls"] = 5
	brain["total_tokens_used"] = 1000
	brain["total_idle_ticks"] = 10
	mgr.reset()
	mgr.initialize()
	brain = mgr.get_brain(0)
	assert_eq(brain["total_api_calls"], 0)
	assert_eq(brain["total_tokens_used"], 0)
	assert_eq(brain["total_idle_ticks"], 0)


func test_get_api_call_count() -> void:
	var brain := mgr.get_brain(0)
	brain["total_api_calls"] = 42
	assert_eq(mgr.get_api_call_count(0), 42)


func test_get_idle_tick_count() -> void:
	var brain := mgr.get_brain(0)
	brain["total_idle_ticks"] = 7
	assert_eq(mgr.get_idle_tick_count(0), 7)


func test_get_api_call_count_invalid_id() -> void:
	assert_eq(mgr.get_api_call_count(99), 0)
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_llm_agent_manager.gd -gexit`

Expected: All 26 tests PASS

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_llm_agent_manager.gd
git commit -m "test: LLMAgentManager API response handling, target validation, tick processing"
```

---

### Task 8: Integration - KeyCollection + WinCondition + GridMovement

**Files:**
- Create: `tests/unit/test_feature_integration.gd`

- [ ] **Step 1: Write integration tests for the full Feature Layer pipeline**

Create `tests/unit/test_feature_integration.gd`:

```gdscript
## Integration tests for Feature Layer systems working together.
extends GutTest

const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")
const FogOfWar := preload("res://src/core/fog_of_war.gd")
const GridMovement := preload("res://src/core/grid_movement.gd")
const KeyCollectionClass := preload("res://src/gameplay/key_collection.gd")
const WinConditionClass := preload("res://src/gameplay/win_condition.gd")

var maze: RefCounted
var fog: Node
var gm: Node
var kc: Node
var wc: Node


func before_each() -> void:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	maze = gen.generate(5, 5)
	assert_not_null(maze)

	fog = FogOfWar.new()
	add_child_autoqfree(fog)
	fog.initialize(maze, [0, 1])

	gm = GridMovement.new()
	gm.maze = maze
	gm.fog = fog
	add_child_autoqfree(gm)
	gm.initialize()

	kc = KeyCollectionClass.new()
	add_child_autoqfree(kc)
	kc.initialize(maze)
	kc.set_active(true)

	wc = WinConditionClass.new()
	add_child_autoqfree(wc)
	wc.initialize(maze)

	# Wire signals
	kc.chest_unlocked.connect(wc._on_chest_unlocked)


func test_key_collection_to_win_condition_signal_chain() -> void:
	# Collect all three keys for agent 0
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos := maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)

	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)

	# Win condition should now have chest active and agent 0 eligible
	assert_true(wc.is_chest_active(), "Chest should be active after all keys collected")
	assert_true(wc.is_agent_eligible(0), "Agent 0 should be eligible")
	assert_false(wc.is_agent_eligible(1), "Agent 1 should not be eligible")


func test_agent_reaches_chest_triggers_win() -> void:
	# Collect all keys
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos := maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)
	var chest_pos := maze.get_marker_position(Enums.MarkerType.CHEST)

	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)

	# Move agent to chest
	wc.set_active(true)
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)

	# Resolve
	watch_signals(wc)
	var result := wc.resolve_pending()
	assert_eq(result["type"], "win")
	assert_eq(result["winner_id"], 0)
	assert_signal_emitted(wc, "chest_opened")


func test_ineligible_agent_at_chest_no_win() -> void:
	# Agent 0 collects all keys
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos := maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)
	var chest_pos := maze.get_marker_position(Enums.MarkerType.CHEST)

	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)

	# Agent 1 (no keys) reaches chest
	wc.set_active(true)
	wc._on_mover_moved(1, Vector2i(-1, -1), chest_pos)
	var result := wc.resolve_pending()
	assert_eq(result["type"], "none", "Ineligible agent should not trigger win")


func test_both_agents_complete_same_tick_draw() -> void:
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	var jade_pos := maze.get_marker_position(Enums.MarkerType.KEY_JADE)
	var crystal_pos := maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL)
	var chest_pos := maze.get_marker_position(Enums.MarkerType.CHEST)

	# Both agents collect all keys
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(1, Vector2i(-1, -1), brass_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(1, Vector2i(-1, -1), jade_pos)
	kc._on_mover_moved(0, Vector2i(-1, -1), crystal_pos)
	kc._on_mover_moved(1, Vector2i(-1, -1), crystal_pos)

	# Both reach chest same tick
	wc.set_active(true)
	wc._on_mover_moved(0, Vector2i(-1, -1), chest_pos)
	wc._on_mover_moved(1, Vector2i(-1, -1), chest_pos)
	var result := wc.resolve_pending()
	assert_eq(result["type"], "draw")


func test_reinitialize_full_pipeline() -> void:
	# Complete a game
	var brass_pos := maze.get_marker_position(Enums.MarkerType.KEY_BRASS)
	kc._on_mover_moved(0, Vector2i(-1, -1), brass_pos)

	# Re-initialize everything (simulates Rematch)
	kc.initialize(maze)
	wc.initialize(maze)

	# All state should be reset
	assert_eq(kc.get_global_phase(), Enums.GlobalKeyPhase.BRASS_ACTIVE)
	assert_false(wc.is_chest_active())
	assert_false(wc.is_agent_eligible(0))
```

- [ ] **Step 2: Run integration tests**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_feature_integration.gd -gexit`

Expected: All 5 tests PASS

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_feature_integration.gd
git commit -m "test: Feature Layer integration - KeyCollection + WinCondition signal chain"
```

---

### Task 9: Integration - Run All Tests

**Files:** None (verification only)

- [ ] **Step 1: Run all tests**

Run: `godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/unit/ -gexit`

Expected: All tests PASS (~130+ tests across Foundation + Core + Feature)

- [ ] **Step 2: Fix any integration issues**

If any failures, fix and commit:
```bash
git add -A
git commit -m "fix: resolve Feature Layer integration issues"
```

---

## Verification Checklist

After completing all tasks, verify:

- [ ] **Enums** updated with GlobalKeyPhase, AgentKeyState, ChestState, AgentEligibility, RequestState, KEY_SEQUENCE, OPPOSITE_MOVE_DIRECTION
- [ ] **KeyCollection** passes all acceptance criteria from `design/gdd/key-collection.md`:
  - Initial state: BRASS_ACTIVE, all agents NEED_BRASS
  - Brass active initially; Jade and Crystal inactive
  - Pickup advances agent progress (NEED_BRASS → NEED_JADE → NEED_CRYSTAL → KEYS_COMPLETE)
  - Pickup advances global phase (BRASS_ACTIVE → JADE_ACTIVE → CRYSTAL_ACTIVE → ALL_COLLECTED)
  - Agent independence: A's pickup doesn't affect B's progress
  - Sequential enforcement: can't skip keys
  - Checkpoint semantics: both agents can pick up same key
  - key_activated fires only on first global activation
  - Activation is cumulative (Jade active doesn't deactivate Brass)
  - chest_unlocked emitted per agent when KEYS_COMPLETE
  - initialize() resets all state for Rematch
  - Missing key marker doesn't crash
- [ ] **WinConditionManager** passes all acceptance criteria from `design/gdd/win-condition.md`:
  - Initial: chest INACTIVE, all agents INELIGIBLE
  - chest_unlocked activates chest and marks agent eligible
  - Second chest_unlocked doesn't double-activate
  - Eligible agent at chest adds to pending_openers
  - Ineligible agent at chest ignored
  - Inactive chest ignored
  - resolve_pending: single opener = win, two openers = draw
  - pending_openers cleared after resolve
  - Not active = ignores mover_moved
  - reset() and initialize() clear all state
- [ ] **LLMInformationFormat** passes all acceptance criteria from `design/gdd/llm-information-format.md`:
  - Response parsing: target, direction, priority, aliases, empty, invalid
  - System message includes rules, coordinate system, format, player prompt
  - State message includes position, open directions, visible cells, visited, objective
  - FoW compliance: no unknown cells, no inactive markers in prompt
  - Explored cells sorted by Manhattan distance, truncated at max_explored_count
  - Visited cells reversed (most recent first), truncated at max_visited_count
  - Config from JSON (include_ascii_map, include_explored, max counts)
- [ ] **LLMAgentManager** passes all acceptance criteria from `design/gdd/llm-agent-integration.md`:
  - Decision point detection: intersection, dead end, auto-advance straight
  - Path queue: generate from A*, consume front, truncate at max
  - Auto-advance on straight corridors
  - First tick: always request API, idle
  - Target validation: bounds, visibility, not current pos, reachable
  - API response handling: target→queue, direction→single step, none→no change
  - Statistics tracking: api_calls, tokens_used, idle_ticks
  - Reset clears all state
- [ ] All config values from JSON, no hardcoded gameplay values
- [ ] ~130+ tests all passing across Foundation + Core + Feature
