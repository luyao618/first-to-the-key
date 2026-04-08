# Core Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the three Core-layer systems (Maze Generator, Grid Movement, Fog of War) that transform the Foundation-layer data structures into playable game mechanics.

**Architecture:** MazeGenerator is a Node that creates and populates MazeData instances using iterative DFS with explicit stack, returning the result and emitting signals. GridMovement is a Node managing Mover dictionaries and processing tick-based movement with batch signal emission. FogOfWar is a Node managing per-agent VisionMaps using BFS PATH_REACH vision. All three are scene-local Nodes (not Autoloads), instantiated within the Match scene. They depend on Foundation-layer classes (MazeData, MatchStateManager, Enums) and read config from game_config.json via ConfigLoader.

**Tech Stack:** Godot 4.6, GDScript, GUT 9.x (Godot Unit Test), JSON config files

---

## Prerequisites

This plan depends on **Plan 1: Foundation Layer** being fully implemented:
- `src/core/maze_data.gd` (MazeData class — RefCounted, grid/walls/markers/BFS)
- `src/core/match_state_manager.gd` (MatchStateManager — Autoload, FSM/tick/countdown)
- `src/shared/enums.gd` (shared enums — Autoload "Enums")
- `src/shared/config_loader.gd` (ConfigLoader — JSON loader utility)
- `assets/data/game_config.json` (gameplay config)

## File Structure

```
src/
  core/
    maze_generator.gd         # MazeGenerator (Node) — iterative DFS, marker placement, fairness validation
    grid_movement.gd          # GridMovement (Node) — tick-based movement, Mover management
    fog_of_war.gd             # FogOfWar (Node) — manages per-agent VisionMaps

tests/
  unit/
    test_maze_generator.gd    # MazeGenerator unit tests
    test_grid_movement.gd     # GridMovement unit tests
    test_fog_of_war.gd        # FogOfWar unit tests
```

---

### Task 0: Add CellVisibility Enum

**Files:**
- Modify: `src/shared/enums.gd`

- [ ] **Step 1: Add CellVisibility enum to shared enums**

Append to `src/shared/enums.gd` (after existing enums):

```gdscript
enum CellVisibility { UNKNOWN, VISIBLE, EXPLORED }
```

- [ ] **Step 2: Commit**

```bash
git add src/shared/enums.gd
git commit -m "feat: add CellVisibility enum for Fog of War system"
```

---

### Task 1: FogOfWar — VisionMap Data Structure and Basic Queries

FogOfWar is implemented first because GridMovement.initialize() calls fog.update_vision().

**Files:**
- Create: `src/core/fog_of_war.gd`
- Create: `tests/unit/test_fog_of_war.gd`

- [ ] **Step 1: Write failing tests for FogOfWar construction and cell queries**

Create `tests/unit/test_fog_of_war.gd`:

```gdscript
## Unit tests for FogOfWar and VisionMap.
extends GutTest

const MazeData := preload("res://src/core/maze_data.gd")
const FogOfWar := preload("res://src/core/fog_of_war.gd")


## Helper: create a FogOfWar node and add to scene tree.
func _make_fog() -> Node:
	var fog := FogOfWar.new()
	add_child_autoqfree(fog)
	return fog


## Helper: create a small connected maze for vision tests.
## All internal walls removed (open grid).
func _make_open_maze(w: int = 3, h: int = 3) -> RefCounted:
	var maze := MazeData.new(w, h)
	for y in range(h):
		for x in range(w):
			if x < w - 1:
				maze.set_wall(x, y, Enums.Direction.EAST, false)
			if y < h - 1:
				maze.set_wall(x, y, Enums.Direction.SOUTH, false)
	return maze


func test_initialize_creates_vision_maps_for_all_agents() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0, 1])
	# All cells should be UNKNOWN after initialize (no initial vision)
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.UNKNOWN)
	assert_eq(fog.get_cell_visibility(1, 0, 0), Enums.CellVisibility.UNKNOWN)


func test_initialize_all_cells_unknown() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0, 1])
	for y in range(3):
		for x in range(3):
			assert_eq(fog.get_cell_visibility(0, x, y), Enums.CellVisibility.UNKNOWN,
				"Agent 0 cell (%d,%d) should be UNKNOWN" % [x, y])
			assert_eq(fog.get_cell_visibility(1, x, y), Enums.CellVisibility.UNKNOWN,
				"Agent 1 cell (%d,%d) should be UNKNOWN" % [x, y])


func test_get_visible_cells_empty_before_update() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	assert_eq(fog.get_visible_cells(0).size(), 0)


func test_get_explored_cells_empty_before_update() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	assert_eq(fog.get_explored_cells(0).size(), 0)


func test_invalid_agent_id_returns_unknown() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	assert_eq(fog.get_cell_visibility(999, 0, 0), Enums.CellVisibility.UNKNOWN)


func test_invalid_agent_id_visible_cells_returns_empty() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	assert_eq(fog.get_visible_cells(999).size(), 0)


func test_invalid_agent_id_explored_cells_returns_empty() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	assert_eq(fog.get_explored_cells(999).size(), 0)


func test_out_of_bounds_returns_unknown() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	assert_eq(fog.get_cell_visibility(0, -1, 0), Enums.CellVisibility.UNKNOWN)
	assert_eq(fog.get_cell_visibility(0, 0, -1), Enums.CellVisibility.UNKNOWN)
	assert_eq(fog.get_cell_visibility(0, 99, 0), Enums.CellVisibility.UNKNOWN)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_fog_of_war.gd -gexit`

Expected: FAIL — cannot preload `fog_of_war.gd` (file does not exist)

- [ ] **Step 3: Implement FogOfWar with VisionMap, initialize, and basic queries**

Create `src/core/fog_of_war.gd`:

```gdscript
## Fog of War facade — manages per-agent visibility of maze cells.
## Each agent has an independent VisionMap tracking three-state cell visibility.
## See design/gdd/fog-of-war.md for full specification.
class_name FogOfWar
extends Node

## Note: CellVisibility enum is defined in Enums autoload (src/shared/enums.gd).
## Use Enums.CellVisibility.UNKNOWN / VISIBLE / EXPLORED.

## Per-agent vision maps. Keys are agent_id (int).
## Values are Dictionaries: { "grid": Array[Array[int]], "current_visible": Array[Vector2i] }
var _vision_maps: Dictionary = {}

## Shared vision radius (from config).
var _vision_radius: int = 3

## Reference to the maze (for BFS neighbor queries).
var _maze: RefCounted = null


## Create VisionMaps for all agents, reset to all UNKNOWN.
## Initial vision is NOT computed here — Grid Movement calls update_vision() after Movers are placed.
func initialize(maze: RefCounted, agent_ids: Array) -> void:
	_maze = maze
	_vision_maps.clear()

	# Load config
	var cfg := ConfigLoader.load_json("res://assets/data/game_config.json")
	var vision_cfg: Dictionary = cfg.get("vision", {})
	_vision_radius = ConfigLoader.get_or_default(vision_cfg, "vision_radius", 3)

	for agent_id in agent_ids:
		_vision_maps[agent_id] = _create_vision_map()


## Update vision for an agent at a new position.
## BFS from position up to vision_radius steps along passable paths.
func update_vision(agent_id: int, position: Vector2i) -> void:
	if not _vision_maps.has(agent_id):
		push_warning("FogOfWar: Invalid agent_id %d in update_vision" % agent_id)
		return

	var vmap: Dictionary = _vision_maps[agent_id]
	var old_visible: Array = vmap["current_visible"]

	# Demote old VISIBLE cells to EXPLORED
	for cell_pos in old_visible:
		var cx: int = cell_pos.x
		var cy: int = cell_pos.y
		if _is_in_bounds(cx, cy):
			vmap["grid"][cy][cx] = Enums.CellVisibility.EXPLORED

	# Compute new visible cells via BFS
	var new_visible: Array[Vector2i] = _compute_visible_cells(position, _vision_radius)

	# Set new visible cells
	for cell_pos in new_visible:
		vmap["grid"][cell_pos.y][cell_pos.x] = Enums.CellVisibility.VISIBLE

	# Cache the new visible list
	vmap["current_visible"] = new_visible


## Get visibility state of a single cell for an agent.
func get_cell_visibility(agent_id: int, x: int, y: int) -> int:
	if not _vision_maps.has(agent_id):
		push_warning("FogOfWar: Invalid agent_id %d in get_cell_visibility" % agent_id)
		return Enums.CellVisibility.UNKNOWN
	if not _is_in_bounds(x, y):
		return Enums.CellVisibility.UNKNOWN
	return _vision_maps[agent_id]["grid"][y][x]


## Get all currently VISIBLE cells for an agent, sorted row-major (y asc, x asc).
func get_visible_cells(agent_id: int) -> Array[Vector2i]:
	if not _vision_maps.has(agent_id):
		push_warning("FogOfWar: Invalid agent_id %d in get_visible_cells" % agent_id)
		return [] as Array[Vector2i]
	var result: Array[Vector2i] = []
	result.assign(_vision_maps[agent_id]["current_visible"])
	result.sort_custom(_sort_row_major)
	return result


## Get all EXPLORED cells for an agent, sorted row-major (y asc, x asc).
func get_explored_cells(agent_id: int) -> Array[Vector2i]:
	if not _vision_maps.has(agent_id):
		push_warning("FogOfWar: Invalid agent_id %d in get_explored_cells" % agent_id)
		return [] as Array[Vector2i]

	var vmap: Dictionary = _vision_maps[agent_id]
	var result: Array[Vector2i] = []
	for y in range(_maze.height):
		for x in range(_maze.width):
			if vmap["grid"][y][x] == Enums.CellVisibility.EXPLORED:
				result.append(Vector2i(x, y))
	return result


# --- Internal ---


## Create a blank vision map (all UNKNOWN).
func _create_vision_map() -> Dictionary:
	var grid: Array = []
	for y in range(_maze.height):
		var row: Array[int] = []
		for x in range(_maze.width):
			row.append(Enums.CellVisibility.UNKNOWN)
		grid.append(row)
	return {
		"grid": grid,
		"current_visible": [] as Array[Vector2i],
	}


## BFS along passable paths from origin up to max_dist steps.
func _compute_visible_cells(origin: Vector2i, max_dist: int) -> Array[Vector2i]:
	if _maze == null:
		return [] as Array[Vector2i]

	var result: Array[Vector2i] = [origin]
	var visited: Dictionary = {origin: 0}
	var queue: Array = [{"pos": origin, "dist": 0}]

	while queue.size() > 0:
		var entry: Dictionary = queue.pop_front()
		var pos: Vector2i = entry["pos"]
		var dist: int = entry["dist"]

		if dist >= max_dist:
			continue

		var neighbors: Array[Vector2i] = _maze.get_neighbors(pos.x, pos.y)
		for neighbor in neighbors:
			if not visited.has(neighbor):
				visited[neighbor] = dist + 1
				result.append(neighbor)
				queue.append({"pos": neighbor, "dist": dist + 1})

	return result


## Check if coordinates are within maze bounds.
func _is_in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < _maze.width and y >= 0 and y < _maze.height


## Sort comparator for row-major order (y ascending, then x ascending).
static func _sort_row_major(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_fog_of_war.gd -gexit`

Expected: All 9 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/fog_of_war.gd tests/unit/test_fog_of_war.gd
git commit -m "feat: FogOfWar with VisionMap data structure, initialize, and boundary defense"
```

---

### Task 2: FogOfWar — Vision Update and State Transitions

**Files:**
- Modify: `tests/unit/test_fog_of_war.gd`

- [ ] **Step 1: Write tests for vision update and three-state transitions**

Append to `tests/unit/test_fog_of_war.gd`:

```gdscript
func test_update_vision_marks_cells_visible() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 1  # Override for deterministic test
	fog.update_vision(0, Vector2i(1, 1))
	# Center cell and its passable neighbors should be VISIBLE
	assert_eq(fog.get_cell_visibility(0, 1, 1), Enums.CellVisibility.VISIBLE,
		"Center should be VISIBLE")
	assert_eq(fog.get_cell_visibility(0, 1, 0), Enums.CellVisibility.VISIBLE,
		"(1,0) should be VISIBLE")
	assert_eq(fog.get_cell_visibility(0, 2, 1), Enums.CellVisibility.VISIBLE,
		"(2,1) should be VISIBLE")
	assert_eq(fog.get_cell_visibility(0, 1, 2), Enums.CellVisibility.VISIBLE,
		"(1,2) should be VISIBLE")
	assert_eq(fog.get_cell_visibility(0, 0, 1), Enums.CellVisibility.VISIBLE,
		"(0,1) should be VISIBLE")


func test_update_vision_radius_1_does_not_reach_corners() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 1
	fog.update_vision(0, Vector2i(1, 1))
	# Corners are 2 steps away, should still be UNKNOWN
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.UNKNOWN,
		"(0,0) corner should be UNKNOWN at radius 1")
	assert_eq(fog.get_cell_visibility(0, 2, 2), Enums.CellVisibility.UNKNOWN,
		"(2,2) corner should be UNKNOWN at radius 1")


func test_visible_to_explored_transition() -> void:
	var maze := _make_open_maze(5, 1)
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 1
	# Move to (0,0) — sees (0,0) and (1,0)
	fog.update_vision(0, Vector2i(0, 0))
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.VISIBLE)
	assert_eq(fog.get_cell_visibility(0, 1, 0), Enums.CellVisibility.VISIBLE)
	# Move to (3,0) — old cells become EXPLORED
	fog.update_vision(0, Vector2i(3, 0))
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.EXPLORED,
		"(0,0) should become EXPLORED")
	assert_eq(fog.get_cell_visibility(0, 1, 0), Enums.CellVisibility.EXPLORED,
		"(1,0) should become EXPLORED")
	assert_eq(fog.get_cell_visibility(0, 3, 0), Enums.CellVisibility.VISIBLE,
		"(3,0) should be VISIBLE")


func test_explored_to_visible_transition() -> void:
	var maze := _make_open_maze(5, 1)
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 1
	fog.update_vision(0, Vector2i(0, 0))
	fog.update_vision(0, Vector2i(3, 0))
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.EXPLORED)
	# Move back near (0,0)
	fog.update_vision(0, Vector2i(0, 0))
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.VISIBLE,
		"(0,0) should return to VISIBLE when back in range")


func test_explored_never_becomes_unknown() -> void:
	var maze := _make_open_maze(5, 1)
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 1
	fog.update_vision(0, Vector2i(0, 0))
	fog.update_vision(0, Vector2i(4, 0))
	# (0,0) should be EXPLORED, not UNKNOWN
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.EXPLORED,
		"Once explored, never back to UNKNOWN")


func test_agents_have_independent_vision() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0, 1])
	fog._vision_radius = 1
	fog.update_vision(0, Vector2i(0, 0))
	# Agent 0 sees (0,0), Agent 1 does not
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.VISIBLE)
	assert_eq(fog.get_cell_visibility(1, 0, 0), Enums.CellVisibility.UNKNOWN,
		"Agent 1 should not see Agent 0's vision")


func test_vision_blocked_by_walls() -> void:
	# 3x1 maze, only (0,0)-(1,0) open, (1,0)-(2,0) walled
	var maze := MazeData.new(3, 1)
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	# (1,0)-(2,0) wall stays closed
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 3
	fog.update_vision(0, Vector2i(0, 0))
	# Can see (0,0) and (1,0) but NOT (2,0) — wall blocks BFS
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.VISIBLE)
	assert_eq(fog.get_cell_visibility(0, 1, 0), Enums.CellVisibility.VISIBLE)
	assert_eq(fog.get_cell_visibility(0, 2, 0), Enums.CellVisibility.UNKNOWN,
		"Wall should block BFS path")


func test_vision_radius_zero_sees_only_self() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 0
	fog.update_vision(0, Vector2i(1, 1))
	assert_eq(fog.get_cell_visibility(0, 1, 1), Enums.CellVisibility.VISIBLE)
	assert_eq(fog.get_visible_cells(0).size(), 1)
	# Neighbors should be UNKNOWN
	assert_eq(fog.get_cell_visibility(0, 1, 0), Enums.CellVisibility.UNKNOWN)


func test_get_visible_cells_sorted_row_major() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 10  # See everything in 3x3
	fog.update_vision(0, Vector2i(1, 1))
	var visible := fog.get_visible_cells(0)
	# Should be sorted: (0,0),(1,0),(2,0),(0,1),(1,1),(2,1),(0,2),(1,2),(2,2)
	assert_eq(visible.size(), 9)
	assert_eq(visible[0], Vector2i(0, 0))
	assert_eq(visible[1], Vector2i(1, 0))
	assert_eq(visible[2], Vector2i(2, 0))
	assert_eq(visible[3], Vector2i(0, 1))
	assert_eq(visible[8], Vector2i(2, 2))


func test_get_explored_cells_sorted_row_major() -> void:
	var maze := _make_open_maze(5, 1)
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog._vision_radius = 1
	fog.update_vision(0, Vector2i(0, 0))  # Sees (0,0), (1,0)
	fog.update_vision(0, Vector2i(4, 0))  # (0,0),(1,0) -> EXPLORED; sees (3,0),(4,0)
	var explored := fog.get_explored_cells(0)
	assert_eq(explored.size(), 2)
	assert_eq(explored[0], Vector2i(0, 0))
	assert_eq(explored[1], Vector2i(1, 0))


func test_update_vision_invalid_agent_ignored() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	# Should not crash, should not create new vision map
	fog.update_vision(999, Vector2i(0, 0))
	assert_eq(fog.get_visible_cells(999).size(), 0)
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_fog_of_war.gd -gexit`

Expected: All 21 tests PASS

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_fog_of_war.gd
git commit -m "test: FogOfWar vision update, state transitions, wall blocking, sorting"
```

---

### Task 3: FogOfWar — Reinitialize Lifecycle

**Files:**
- Modify: `tests/unit/test_fog_of_war.gd`

- [ ] **Step 1: Write tests for reinitialize lifecycle**

Append to `tests/unit/test_fog_of_war.gd`:

```gdscript
func test_reinitialize_same_maze_resets_vision() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0])
	fog.update_vision(0, Vector2i(1, 1))
	assert_gt(fog.get_visible_cells(0).size(), 0, "Should have visible cells")
	# Reinitialize with same maze
	fog.initialize(maze, [0])
	assert_eq(fog.get_visible_cells(0).size(), 0, "Should be reset after reinitialize")
	assert_eq(fog.get_cell_visibility(0, 1, 1), Enums.CellVisibility.UNKNOWN)


func test_reinitialize_new_maze_different_size() -> void:
	var maze_small := _make_open_maze(3, 3)
	var fog := _make_fog()
	fog.initialize(maze_small, [0, 1])
	fog.update_vision(0, Vector2i(0, 0))

	# Reinitialize with larger maze
	var maze_large := _make_open_maze(5, 5)
	fog.initialize(maze_large, [0, 1])
	# Should handle new dimensions
	assert_eq(fog.get_cell_visibility(0, 4, 4), Enums.CellVisibility.UNKNOWN)
	assert_eq(fog.get_visible_cells(0).size(), 0)


func test_reinitialize_different_agent_ids() -> void:
	var maze := _make_open_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0, 1])
	fog.update_vision(0, Vector2i(0, 0))
	# Reinitialize with different agents
	fog.initialize(maze, [2, 3])
	# Old agent 0 should no longer exist
	assert_eq(fog.get_visible_cells(0).size(), 0)
	# New agent 2 should start UNKNOWN
	assert_eq(fog.get_cell_visibility(2, 0, 0), Enums.CellVisibility.UNKNOWN)
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_fog_of_war.gd -gexit`

Expected: All 24 tests PASS

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_fog_of_war.gd
git commit -m "test: FogOfWar reinitialize lifecycle for rematch and new maze"
```

---

### Task 4: MazeGenerator — DFS Maze Carving

**Files:**
- Create: `src/core/maze_generator.gd`
- Create: `tests/unit/test_maze_generator.gd`

- [ ] **Step 1: Write failing tests for DFS maze generation**

Create `tests/unit/test_maze_generator.gd`:

```gdscript
## Unit tests for MazeGenerator.
extends GutTest

const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")


## Helper: create a MazeGenerator node and add to scene tree.
func _make_generator() -> Node:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	return gen


func test_generate_returns_finalized_maze() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(5, 5)
	assert_signal_emitted(gen, "maze_generated")
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	assert_not_null(maze, "Should emit a MazeData instance")


func test_generate_all_cells_reachable() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(10, 10)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	# BFS from (0,0) should reach all 100 cells
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [Vector2i(0, 0)]
	visited[Vector2i(0, 0)] = true
	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		for neighbor in maze.get_neighbors(current.x, current.y):
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	assert_eq(visited.size(), 100, "All 100 cells should be reachable")


func test_generate_perfect_maze_edge_count() -> void:
	# A perfect maze has exactly width*height - 1 passages
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(8, 8)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	var passage_count := 0
	for y in range(8):
		for x in range(8):
			# Count EAST passages (to avoid double-counting)
			if x < 7 and maze.can_move(x, y, Enums.Direction.EAST):
				passage_count += 1
			# Count SOUTH passages
			if y < 7 and maze.can_move(x, y, Enums.Direction.SOUTH):
				passage_count += 1
	assert_eq(passage_count, 8 * 8 - 1, "Perfect maze should have w*h-1 passages")


func test_generate_has_all_markers() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(5, 5)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	assert_eq(maze.get_marker_position(Enums.MarkerType.SPAWN_A), Vector2i(0, 0),
		"SPAWN_A should be at (0,0)")
	assert_eq(maze.get_marker_position(Enums.MarkerType.SPAWN_B), Vector2i(4, 4),
		"SPAWN_B should be at (width-1, height-1)")
	assert_ne(maze.get_marker_position(Enums.MarkerType.KEY_BRASS), Vector2i(-1, -1),
		"KEY_BRASS should be placed")
	assert_ne(maze.get_marker_position(Enums.MarkerType.KEY_JADE), Vector2i(-1, -1),
		"KEY_JADE should be placed")
	assert_ne(maze.get_marker_position(Enums.MarkerType.KEY_CRYSTAL), Vector2i(-1, -1),
		"KEY_CRYSTAL should be placed")
	assert_ne(maze.get_marker_position(Enums.MarkerType.CHEST), Vector2i(-1, -1),
		"CHEST should be placed")


func test_markers_all_on_unique_cells() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(5, 5)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	var positions: Array[Vector2i] = []
	for marker in [Enums.MarkerType.SPAWN_A, Enums.MarkerType.SPAWN_B,
			Enums.MarkerType.KEY_BRASS, Enums.MarkerType.KEY_JADE,
			Enums.MarkerType.KEY_CRYSTAL, Enums.MarkerType.CHEST]:
		var pos := maze.get_marker_position(marker)
		assert_does_not_have(positions, pos,
			"Marker %d at (%d,%d) already used" % [marker, pos.x, pos.y])
		positions.append(pos)


func test_markers_not_on_spawn_cells() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(5, 5)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	var spawn_a := maze.get_marker_position(Enums.MarkerType.SPAWN_A)
	var spawn_b := maze.get_marker_position(Enums.MarkerType.SPAWN_B)
	for marker in [Enums.MarkerType.KEY_BRASS, Enums.MarkerType.KEY_JADE,
			Enums.MarkerType.KEY_CRYSTAL, Enums.MarkerType.CHEST]:
		var pos := maze.get_marker_position(marker)
		assert_ne(pos, spawn_a, "Marker %d should not be on SPAWN_A" % marker)
		assert_ne(pos, spawn_b, "Marker %d should not be on SPAWN_B" % marker)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_generator.gd -gexit`

Expected: FAIL — cannot preload `maze_generator.gd` (file does not exist)

- [ ] **Step 3: Implement MazeGenerator with iterative DFS, marker placement, and fairness validation**

Create `src/core/maze_generator.gd`:

```gdscript
## Maze Generator — procedural maze creation using iterative DFS (Recursive Backtracker).
## Creates a fully connected perfect maze, places markers, validates fairness.
## See design/gdd/maze-generator.md for full specification.
class_name MazeGenerator
extends Node

signal maze_generated(maze_data: RefCounted)
signal generation_failed(retry_count: int, reason: String)

## Config values (loaded from game_config.json).
var _max_fairness_delta: int = 2
var _max_generation_retries: int = 50


## Generate a maze with the given dimensions.
## Returns the finalized MazeData on success, null on failure.
## Also emits maze_generated / generation_failed signals.
func generate(width: int, height: int) -> RefCounted:
	_load_config()

	# Minimum size check: need at least 6 cells for 6 markers, width >= 2, height >= 2
	if width < 2 or height < 2 or width * height < 6:
		generation_failed.emit(0, "Maze too small: %dx%d (need w>=2, h>=2, w*h>=6)" % [width, height])
		return null

	var maze := MazeData.new(width, height)

	for attempt in range(_max_generation_retries):
		if attempt > 0:
			maze.reset()

		# Phase 1: Carve passages with iterative DFS
		_carve_maze(maze, width, height)

		# Phase 2: Place markers
		_place_markers(maze, width, height)

		# Phase 3: Validate fairness
		if not _validate_fairness(maze):
			continue

		# Phase 4: Finalize
		if maze.finalize():
			maze_generated.emit(maze)
			return maze
		# finalize() failed (is_valid() detected issue) — retry

	generation_failed.emit(_max_generation_retries,
		"Failed to generate fair maze after %d retries" % _max_generation_retries)
	return null


## Iterative DFS (Recursive Backtracker) maze carving.
## Uses explicit stack to avoid GDScript stack overflow on large mazes.
func _carve_maze(maze: RefCounted, width: int, height: int) -> void:
	var visited: Dictionary = {}

	# Start from a random cell
	var start := Vector2i(randi() % width, randi() % height)
	var stack: Array[Vector2i] = [start]
	visited[start] = true

	while stack.size() > 0:
		var current: Vector2i = stack.back()

		# Get unvisited neighbors
		var unvisited_neighbors: Array[Dictionary] = []
		for dir in [Enums.Direction.NORTH, Enums.Direction.EAST,
				Enums.Direction.SOUTH, Enums.Direction.WEST]:
			var offset: Vector2i = Enums.DIRECTION_OFFSETS[dir]
			var nx := current.x + offset.x
			var ny := current.y + offset.y
			if nx >= 0 and nx < width and ny >= 0 and ny < height:
				var neighbor := Vector2i(nx, ny)
				if not visited.has(neighbor):
					unvisited_neighbors.append({"pos": neighbor, "dir": dir})

		if unvisited_neighbors.size() > 0:
			# Pick a random unvisited neighbor
			var chosen: Dictionary = unvisited_neighbors[randi() % unvisited_neighbors.size()]
			var next_pos: Vector2i = chosen["pos"]
			var dir: int = chosen["dir"]

			# Remove the wall between current and chosen
			maze.set_wall(current.x, current.y, dir, false)

			visited[next_pos] = true
			stack.append(next_pos)
		else:
			# Backtrack
			stack.pop_back()


## Place spawn points, keys, and chest.
func _place_markers(maze: RefCounted, width: int, height: int) -> void:
	# Fixed spawn positions
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(width - 1, height - 1, Enums.MarkerType.SPAWN_B)

	# Collect available cells (not spawn points, not occupied)
	var occupied: Dictionary = {
		Vector2i(0, 0): true,
		Vector2i(width - 1, height - 1): true,
	}

	var items_to_place := [
		Enums.MarkerType.KEY_BRASS,
		Enums.MarkerType.KEY_JADE,
		Enums.MarkerType.KEY_CRYSTAL,
		Enums.MarkerType.CHEST,
	]

	for marker_type in items_to_place:
		var available: Array[Vector2i] = []
		for y in range(height):
			for x in range(width):
				var pos := Vector2i(x, y)
				if not occupied.has(pos):
					available.append(pos)

		var chosen: Vector2i = available[randi() % available.size()]
		maze.place_marker(chosen.x, chosen.y, marker_type)
		occupied[chosen] = true


## Validate fairness: BFS path delta for all 4 targets must be within threshold.
func _validate_fairness(maze: RefCounted) -> bool:
	var spawn_a: Vector2i = maze.get_marker_position(Enums.MarkerType.SPAWN_A)
	var spawn_b: Vector2i = maze.get_marker_position(Enums.MarkerType.SPAWN_B)

	var targets := [
		Enums.MarkerType.KEY_BRASS,
		Enums.MarkerType.KEY_JADE,
		Enums.MarkerType.KEY_CRYSTAL,
		Enums.MarkerType.CHEST,
	]

	for target_type in targets:
		var target_pos: Vector2i = maze.get_marker_position(target_type)
		var path_a: Array = maze.get_shortest_path(spawn_a, target_pos)
		var path_b: Array = maze.get_shortest_path(spawn_b, target_pos)

		# Path size includes start and end, so steps = size - 1
		# Empty path means same position (0 steps)
		var steps_a: int = max(0, path_a.size() - 1)
		var steps_b: int = max(0, path_b.size() - 1)
		var delta: int = abs(steps_a - steps_b)

		if delta > _max_fairness_delta:
			return false

	return true


## Load config values from game_config.json.
func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/game_config.json")
	var maze_cfg: Dictionary = cfg.get("maze", {})
	var gen_cfg: Dictionary = cfg.get("generator", {})
	_max_fairness_delta = ConfigLoader.get_or_default(maze_cfg, "max_fairness_delta", 2)
	_max_generation_retries = ConfigLoader.get_or_default(gen_cfg, "max_generation_retries", 50)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_generator.gd -gexit`

Expected: All 6 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/maze_generator.gd tests/unit/test_maze_generator.gd
git commit -m "feat: MazeGenerator with iterative DFS, marker placement, fairness validation"
```

---

### Task 5: MazeGenerator — Fairness Validation and Edge Cases

**Files:**
- Modify: `tests/unit/test_maze_generator.gd`

- [ ] **Step 1: Write tests for fairness validation and edge cases**

Append to `tests/unit/test_maze_generator.gd`:

```gdscript
func test_fairness_validation_passes() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(15, 15)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	# Verify fairness manually
	var spawn_a := maze.get_marker_position(Enums.MarkerType.SPAWN_A)
	var spawn_b := maze.get_marker_position(Enums.MarkerType.SPAWN_B)
	for target in [Enums.MarkerType.KEY_BRASS, Enums.MarkerType.KEY_JADE,
			Enums.MarkerType.KEY_CRYSTAL, Enums.MarkerType.CHEST]:
		var target_pos := maze.get_marker_position(target)
		var path_a := maze.get_shortest_path(spawn_a, target_pos)
		var path_b := maze.get_shortest_path(spawn_b, target_pos)
		var delta: int = abs((path_a.size() - 1) - (path_b.size() - 1))
		assert_true(delta <= 2, "Fairness delta for target %d is %d (max 2)" % [target, delta])


func test_minimum_size_2x3_succeeds() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(2, 3)
	assert_signal_emitted(gen, "maze_generated")


func test_minimum_size_3x2_succeeds() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(3, 2)
	assert_signal_emitted(gen, "maze_generated")


func test_too_small_1x1_fails() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(1, 1)
	assert_signal_emitted(gen, "generation_failed")
	assert_signal_not_emitted(gen, "maze_generated")


func test_too_small_2x2_fails() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(2, 2)
	assert_signal_emitted(gen, "generation_failed")
	assert_signal_not_emitted(gen, "maze_generated")


func test_too_small_1x5_fails() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(1, 5)
	assert_signal_emitted(gen, "generation_failed")
	assert_signal_not_emitted(gen, "maze_generated")


func test_randomness_produces_different_mazes() -> void:
	var gen := _make_generator()
	var wall_hashes: Array[int] = []
	for i in range(10):
		watch_signals(gen)
		gen.generate(10, 10)
		var maze: RefCounted = get_signal_parameters(gen, "maze_generated", i)[0]
		# Hash the wall pattern
		var h := 0
		for y in range(10):
			for x in range(10):
				if maze.can_move(x, y, Enums.Direction.EAST):
					h = h ^ (x * 31 + y * 37)
				if maze.can_move(x, y, Enums.Direction.SOUTH):
					h = h ^ (x * 41 + y * 43)
		wall_hashes.append(h)
	# At least 9 of 10 should be unique
	var unique_count := 0
	var seen: Dictionary = {}
	for h in wall_hashes:
		if not seen.has(h):
			seen[h] = true
			unique_count += 1
	assert_gte(unique_count, 9, "At least 9 of 10 mazes should be unique")


func test_boundary_walls_intact() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(5, 5)
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	# Top boundary
	for x in range(5):
		assert_true(maze.has_wall(x, 0, Enums.Direction.NORTH),
			"Top boundary at x=%d should have NORTH wall" % x)
	# Bottom boundary
	for x in range(5):
		assert_true(maze.has_wall(x, 4, Enums.Direction.SOUTH),
			"Bottom boundary at x=%d should have SOUTH wall" % x)
	# Left boundary
	for y in range(5):
		assert_true(maze.has_wall(0, y, Enums.Direction.WEST),
			"Left boundary at y=%d should have WEST wall" % y)
	# Right boundary
	for y in range(5):
		assert_true(maze.has_wall(4, y, Enums.Direction.EAST),
			"Right boundary at y=%d should have EAST wall" % y)


func test_large_maze_50x50_succeeds() -> void:
	var gen := _make_generator()
	watch_signals(gen)
	gen.generate(50, 50)
	assert_signal_emitted(gen, "maze_generated")
	var maze: RefCounted = get_signal_parameters(gen, "maze_generated", 0)[0]
	# Verify connectivity
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [Vector2i(0, 0)]
	visited[Vector2i(0, 0)] = true
	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		for neighbor in maze.get_neighbors(current.x, current.y):
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	assert_eq(visited.size(), 2500, "All 2500 cells should be reachable in 50x50")
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_generator.gd -gexit`

Expected: All 15 tests PASS

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_maze_generator.gd
git commit -m "test: MazeGenerator fairness, edge cases, randomness, boundary walls, 50x50"
```

---

### Task 6: GridMovement — Mover Data Structure and Initialization

**Files:**
- Create: `src/core/grid_movement.gd`
- Create: `tests/unit/test_grid_movement.gd`

- [ ] **Step 1: Write failing tests for GridMovement initialization**

Create `tests/unit/test_grid_movement.gd`:

```gdscript
## Unit tests for GridMovement.
extends GutTest

const MazeData := preload("res://src/core/maze_data.gd")
const FogOfWar := preload("res://src/core/fog_of_war.gd")
const GridMovement := preload("res://src/core/grid_movement.gd")


## Helper: create a finalized 5x5 maze with a snake path and all markers.
func _make_test_maze() -> RefCounted:
	var maze := MazeData.new(5, 5)
	# Open a snake path to ensure full connectivity:
	# Row 0: (0,0)-(1,0)-(2,0)-(3,0)-(4,0) then down at (4,0)
	# Row 1: (4,1)-(3,1)-(2,1)-(1,1)-(0,1) then down at (0,1)
	# Row 2: (0,2)-(1,2)-(2,2)-(3,2)-(4,2) then down at (4,2)
	# Row 3: (4,3)-(3,3)-(2,3)-(1,3)-(0,3) then down at (0,3)
	# Row 4: (0,4)-(1,4)-(2,4)-(3,4)-(4,4)
	for y in range(5):
		for x in range(4):
			maze.set_wall(x, y, Enums.Direction.EAST, false)
		if y < 4:
			if y % 2 == 0:
				maze.set_wall(4, y, Enums.Direction.SOUTH, false)
			else:
				maze.set_wall(0, y, Enums.Direction.SOUTH, false)
	# Place markers
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(4, 4, Enums.MarkerType.SPAWN_B)
	maze.place_marker(2, 0, Enums.MarkerType.KEY_BRASS)
	maze.place_marker(3, 1, Enums.MarkerType.KEY_JADE)
	maze.place_marker(1, 3, Enums.MarkerType.KEY_CRYSTAL)
	maze.place_marker(2, 2, Enums.MarkerType.CHEST)
	maze.finalize()
	return maze


## Helper: create GridMovement node with maze and fog injected.
func _make_gm() -> Node:
	var maze := _make_test_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0, 1])
	var gm: Node = GridMovement.new()
	gm.maze = maze
	gm.fog = fog
	add_child_autoqfree(gm)
	return gm


func test_initialize_sets_mover_positions_from_spawns() -> void:
	var gm := _make_gm()
	gm.initialize()
	assert_eq(gm.get_position_of(0), Vector2i(0, 0), "Mover 0 at SPAWN_A")
	assert_eq(gm.get_position_of(1), Vector2i(4, 4), "Mover 1 at SPAWN_B")


func test_initialize_records_spawn_in_visited() -> void:
	var gm := _make_gm()
	gm.initialize()
	assert_true(gm.has_visited(0, Vector2i(0, 0)), "Mover 0 should have visited spawn")
	assert_true(gm.has_visited(1, Vector2i(4, 4)), "Mover 1 should have visited spawn")


func test_initialize_visited_cells_contains_spawn() -> void:
	var gm := _make_gm()
	gm.initialize()
	var visited := gm.get_visited_cells(0)
	assert_eq(visited.size(), 1)
	assert_has(visited, Vector2i(0, 0))


func test_initialize_stats_are_zero() -> void:
	var gm := _make_gm()
	gm.initialize()
	assert_eq(gm.get_total_moves(0), 0)
	assert_eq(gm.get_blocked_count(0), 0)
	assert_eq(gm.get_total_moves(1), 0)
	assert_eq(gm.get_blocked_count(1), 0)


func test_initialize_triggers_fog_initial_vision() -> void:
	var maze := _make_test_maze()
	var fog := _make_fog()
	fog.initialize(maze, [0, 1])
	var gm: Node = GridMovement.new()
	gm.maze = maze
	gm.fog = fog
	add_child_autoqfree(gm)
	gm.initialize()
	# After initialize, fog should have vision around spawn
	assert_eq(fog.get_cell_visibility(0, 0, 0), Enums.CellVisibility.VISIBLE,
		"SPAWN_A should be VISIBLE after initialize")
	assert_eq(fog.get_cell_visibility(1, 4, 4), Enums.CellVisibility.VISIBLE,
		"SPAWN_B should be VISIBLE after initialize")


func test_reset_clears_all_state() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.reset()
	assert_eq(gm.get_position_of(0), Vector2i(-1, -1), "After reset position should be (-1,-1)")
	assert_eq(gm.get_visited_cells(0).size(), 0)
	assert_eq(gm.get_total_moves(0), 0)
	assert_eq(gm.get_blocked_count(0), 0)


func test_invalid_mover_id_queries() -> void:
	var gm := _make_gm()
	gm.initialize()
	assert_eq(gm.get_position_of(99), Vector2i(-1, -1))
	assert_eq(gm.get_visited_cells(99).size(), 0)
	assert_false(gm.has_visited(99, Vector2i(0, 0)))
	assert_eq(gm.get_total_moves(99), 0)
	assert_eq(gm.get_blocked_count(99), 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_grid_movement.gd -gexit`

Expected: FAIL — cannot preload `grid_movement.gd` (file does not exist)

- [ ] **Step 3: Implement GridMovement with Mover management, initialize, reset, queries**

Create `src/core/grid_movement.gd`:

```gdscript
## Grid Movement — tick-based movement manager for maze agents.
## Manages Mover state, validates movement against MazeData, emits movement signals.
## See design/gdd/grid-movement.md for full specification.
class_name GridMovement
extends Node

# --- Signals ---
signal mover_moved(mover_id: int, old_pos: Vector2i, new_pos: Vector2i)
signal mover_blocked(mover_id: int, pos: Vector2i, direction: int)
signal mover_stayed(mover_id: int, pos: Vector2i)

# --- Dependencies (injected before initialize) ---
## MazeData reference (read-only after finalize).
var maze: RefCounted = null
## FogOfWar reference (only used in initialize for initial vision).
var fog: RefCounted = null

# --- Internal State ---
## Array of Mover dictionaries.
var _movers: Array[Dictionary] = []

## Direction offset mapping for MoveDirection.
const DIRECTION_OFFSETS: Dictionary = {
	Enums.MoveDirection.NORTH: Vector2i(0, -1),
	Enums.MoveDirection.EAST: Vector2i(1, 0),
	Enums.MoveDirection.SOUTH: Vector2i(0, 1),
	Enums.MoveDirection.WEST: Vector2i(-1, 0),
}

## MoveDirection -> Direction mapping for can_move() calls.
const MOVE_TO_DIR: Dictionary = {
	Enums.MoveDirection.NORTH: Enums.Direction.NORTH,
	Enums.MoveDirection.EAST: Enums.Direction.EAST,
	Enums.MoveDirection.SOUTH: Enums.Direction.SOUTH,
	Enums.MoveDirection.WEST: Enums.Direction.WEST,
}


## Initialize movers at spawn positions from MazeData.
## Triggers initial fog vision for each mover.
func initialize() -> void:
	_movers.clear()

	for i in range(2):
		var spawn_marker: int = Enums.MarkerType.SPAWN_A if i == 0 else Enums.MarkerType.SPAWN_B
		var spawn_pos: Vector2i = Vector2i(-1, -1)
		if maze != null:
			spawn_pos = maze.get_marker_position(spawn_marker)

		if spawn_pos == Vector2i(-1, -1):
			push_error("GridMovement: Missing spawn marker %d for mover %d" % [spawn_marker, i])

		var visited_dict: Dictionary = {}
		var visited_list: Array[Vector2i] = []
		if spawn_pos != Vector2i(-1, -1):
			visited_dict[spawn_pos] = true
			visited_list.append(spawn_pos)

		_movers.append({
			"id": i,
			"position": spawn_pos,
			"pending_direction": Enums.MoveDirection.NONE,
			"visited_cells_dict": visited_dict,
			"visited_cells_list": visited_list,
			"total_moves": 0,
			"blocked_count": 0,
		})

	# Trigger initial vision for all movers
	if fog != null:
		for mover in _movers:
			if mover["position"] != Vector2i(-1, -1):
				fog.update_vision(mover["id"], mover["position"])


## Reset all mover state.
func reset() -> void:
	_movers.clear()


## Set the pending direction for a mover. Consumed in next on_tick().
func set_direction(mover_id: int, direction: int) -> void:
	if mover_id < 0 or mover_id >= _movers.size():
		push_warning("GridMovement: Invalid mover_id %d in set_direction" % mover_id)
		return
	_movers[mover_id]["pending_direction"] = direction


## Process one tick: read pending directions, validate, update positions, batch emit signals.
func on_tick(_tick_count: int) -> void:
	var results: Array[Dictionary] = []

	# Phase 1: Process all movers, collect results
	for mover in _movers:
		var dir: int = mover["pending_direction"]
		mover["pending_direction"] = Enums.MoveDirection.NONE

		if dir == Enums.MoveDirection.NONE:
			results.append({"type": "stayed", "id": mover["id"], "pos": mover["position"]})
			continue

		var maze_dir: int = MOVE_TO_DIR[dir]
		var pos: Vector2i = mover["position"]

		if maze != null and maze.can_move(pos.x, pos.y, maze_dir):
			var old_pos: Vector2i = pos
			var offset: Vector2i = DIRECTION_OFFSETS[dir]
			var new_pos: Vector2i = old_pos + offset
			mover["position"] = new_pos
			mover["total_moves"] += 1

			if not mover["visited_cells_dict"].has(new_pos):
				mover["visited_cells_dict"][new_pos] = true
				mover["visited_cells_list"].append(new_pos)

			results.append({"type": "moved", "id": mover["id"],
				"old_pos": old_pos, "new_pos": new_pos})
		else:
			mover["blocked_count"] += 1
			results.append({"type": "blocked", "id": mover["id"],
				"pos": pos, "dir": maze_dir})

	# Phase 2: Batch emit signals after all movers processed
	for result in results:
		match result["type"]:
			"stayed":
				mover_stayed.emit(result["id"], result["pos"])
			"moved":
				mover_moved.emit(result["id"], result["old_pos"], result["new_pos"])
			"blocked":
				mover_blocked.emit(result["id"], result["pos"], result["dir"])


# --- Query Interface ---


## Get current position of a mover.
func get_position_of(mover_id: int) -> Vector2i:
	if mover_id < 0 or mover_id >= _movers.size():
		push_warning("GridMovement: Invalid mover_id %d in get_position_of" % mover_id)
		return Vector2i(-1, -1)
	return _movers[mover_id]["position"]


## Get visited cells as an Array (exposed as ordered list).
func get_visited_cells(mover_id: int) -> Array[Vector2i]:
	if mover_id < 0 or mover_id >= _movers.size():
		return [] as Array[Vector2i]
	var result: Array[Vector2i] = []
	result.assign(_movers[mover_id]["visited_cells_list"])
	return result


## Check if a mover has visited a specific cell.
func has_visited(mover_id: int, pos: Vector2i) -> bool:
	if mover_id < 0 or mover_id >= _movers.size():
		return false
	return _movers[mover_id]["visited_cells_dict"].has(pos)


## Get total successful moves for a mover.
func get_total_moves(mover_id: int) -> int:
	if mover_id < 0 or mover_id >= _movers.size():
		return 0
	return _movers[mover_id]["total_moves"]


## Get total blocked (wall-hit) count for a mover.
func get_blocked_count(mover_id: int) -> int:
	if mover_id < 0 or mover_id >= _movers.size():
		return 0
	return _movers[mover_id]["blocked_count"]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_grid_movement.gd -gexit`

Expected: All 8 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/grid_movement.gd tests/unit/test_grid_movement.gd
git commit -m "feat: GridMovement with Mover management, initialize, reset, queries"
```

---

### Task 7: GridMovement — Tick Processing and Movement Signals

**Files:**
- Modify: `tests/unit/test_grid_movement.gd`

- [ ] **Step 1: Write tests for tick-based movement and signal emission**

Append to `tests/unit/test_grid_movement.gd`:

```gdscript
func test_set_direction_and_move_east() -> void:
	var gm := _make_gm()
	gm.initialize()
	watch_signals(gm)
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.on_tick(1)
	assert_eq(gm.get_position_of(0), Vector2i(1, 0), "Should move east to (1,0)")
	assert_signal_emitted(gm, "mover_moved")
	var params := get_signal_parameters(gm, "mover_moved", 0)
	assert_eq(params[0], 0)  # mover_id
	assert_eq(params[1], Vector2i(0, 0))  # old_pos
	assert_eq(params[2], Vector2i(1, 0))  # new_pos


func test_blocked_movement_stays_in_place() -> void:
	var gm := _make_gm()
	gm.initialize()
	watch_signals(gm)
	# Try to move north from (0,0) — always blocked (boundary wall)
	gm.set_direction(0, Enums.MoveDirection.NORTH)
	gm.on_tick(1)
	assert_eq(gm.get_position_of(0), Vector2i(0, 0), "Should stay at (0,0)")
	assert_signal_emitted(gm, "mover_blocked")
	var params := get_signal_parameters(gm, "mover_blocked", 0)
	assert_eq(params[0], 0)  # mover_id
	assert_eq(params[1], Vector2i(0, 0))  # pos


func test_blocked_increments_blocked_count() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.set_direction(0, Enums.MoveDirection.NORTH)
	gm.on_tick(1)
	assert_eq(gm.get_blocked_count(0), 1)
	gm.set_direction(0, Enums.MoveDirection.NORTH)
	gm.on_tick(2)
	assert_eq(gm.get_blocked_count(0), 2)


func test_no_direction_emits_stayed() -> void:
	var gm := _make_gm()
	gm.initialize()
	watch_signals(gm)
	# No set_direction — pending is NONE
	gm.on_tick(1)
	assert_signal_emitted(gm, "mover_stayed")
	var params := get_signal_parameters(gm, "mover_stayed", 0)
	assert_eq(params[0], 0)  # mover_id
	assert_eq(params[1], Vector2i(0, 0))  # pos


func test_pending_direction_cleared_after_tick() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.on_tick(1)
	# Second tick without set_direction should stay
	watch_signals(gm)
	gm.on_tick(2)
	assert_signal_emitted(gm, "mover_stayed")


func test_total_moves_increments_on_success() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.on_tick(1)
	assert_eq(gm.get_total_moves(0), 1)
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.on_tick(2)
	assert_eq(gm.get_total_moves(0), 2)


func test_visited_cells_no_duplicates() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.on_tick(1)
	gm.set_direction(0, Enums.MoveDirection.WEST)
	gm.on_tick(2)
	# Back at (0,0) — should not duplicate in visited_cells
	var visited := gm.get_visited_cells(0)
	var unique: Dictionary = {}
	for v in visited:
		assert_false(unique.has(v), "Duplicate visited cell: (%d,%d)" % [v.x, v.y])
		unique[v] = true


func test_last_set_direction_wins() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.set_direction(0, Enums.MoveDirection.NORTH)  # Will be overwritten
	gm.set_direction(0, Enums.MoveDirection.EAST)   # Last write wins
	gm.on_tick(1)
	assert_eq(gm.get_position_of(0), Vector2i(1, 0), "Last set_direction should win")


func test_both_movers_process_in_same_tick() -> void:
	var gm := _make_gm()
	gm.initialize()
	watch_signals(gm)
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.set_direction(1, Enums.MoveDirection.WEST)
	gm.on_tick(1)
	# Mover 0 should move east from (0,0) to (1,0)
	assert_eq(gm.get_position_of(0), Vector2i(1, 0), "Mover 0 should move east")
	# Mover 1 at (4,4), west should be open in snake maze
	assert_eq(gm.get_position_of(1), Vector2i(3, 4), "Mover 1 should move west")


func test_invalid_mover_id_set_direction_no_crash() -> void:
	var gm := _make_gm()
	gm.initialize()
	# Should not crash
	gm.set_direction(99, Enums.MoveDirection.EAST)
	gm.on_tick(1)
	# Movers should be unaffected (stayed)
	assert_eq(gm.get_position_of(0), Vector2i(0, 0))


func test_direction_offsets_correct() -> void:
	assert_eq(GridMovement.DIRECTION_OFFSETS[Enums.MoveDirection.NORTH], Vector2i(0, -1))
	assert_eq(GridMovement.DIRECTION_OFFSETS[Enums.MoveDirection.EAST], Vector2i(1, 0))
	assert_eq(GridMovement.DIRECTION_OFFSETS[Enums.MoveDirection.SOUTH], Vector2i(0, 1))
	assert_eq(GridMovement.DIRECTION_OFFSETS[Enums.MoveDirection.WEST], Vector2i(-1, 0))


func test_has_visited_returns_true_for_moved_cells() -> void:
	var gm := _make_gm()
	gm.initialize()
	gm.set_direction(0, Enums.MoveDirection.EAST)
	gm.on_tick(1)
	assert_true(gm.has_visited(0, Vector2i(0, 0)), "Should have visited start")
	assert_true(gm.has_visited(0, Vector2i(1, 0)), "Should have visited (1,0)")
	assert_false(gm.has_visited(0, Vector2i(2, 0)), "Should not have visited (2,0)")
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_grid_movement.gd -gexit`

Expected: All 20 tests PASS

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_grid_movement.gd
git commit -m "test: GridMovement tick processing, movement, blocking, signals, edge cases"
```

---

### Task 8: Integration — Run All Core Layer Tests

**Files:** None (verification only)

- [ ] **Step 1: Run all Core Layer tests**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_fog_of_war.gd -gtest=res://tests/unit/test_maze_generator.gd -gtest=res://tests/unit/test_grid_movement.gd -gexit`

Expected: All tests PASS (approximately 59 tests across 3 test files)

- [ ] **Step 2: Run ALL project tests (Foundation + Core)**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/unit/ -gexit`

Expected: All tests PASS (approximately 109+ tests across all test files)

- [ ] **Step 3: Final commit if any fixes needed**

Only if fixes were required:
```bash
git add -A
git commit -m "fix: resolve integration issues from full Core Layer test run"
```

---

## Verification Checklist

After completing all tasks, verify:

### Fog of War
- [ ] `FogOfWar.initialize(maze, [0, 1])` creates VisionMaps with all cells UNKNOWN
- [ ] `initialize()` does NOT compute initial vision — Grid Movement does that
- [ ] Agent A vision update does not affect Agent B
- [ ] VISIBLE cells become EXPLORED when agent moves away
- [ ] EXPLORED cells return to VISIBLE when agent returns
- [ ] EXPLORED never degrades to UNKNOWN
- [ ] BFS vision does not cross walls (PATH_REACH strategy)
- [ ] `vision_radius = 0` sees only the agent's own cell
- [ ] `get_visible_cells()` returns row-major sorted results (y asc, x asc)
- [ ] `get_explored_cells()` returns row-major sorted results (y asc, x asc)
- [ ] Invalid agent_id returns UNKNOWN / empty arrays, does not crash
- [ ] Out-of-bounds coordinates return UNKNOWN
- [ ] Reinitialize (same or new maze) resets all state to UNKNOWN
- [ ] `vision_radius` read from `game_config.json`, not hardcoded

### Maze Generator
- [ ] Generated maze is fully connected (BFS from any cell reaches all cells)
- [ ] Generated maze is a perfect maze (exactly w*h-1 passages)
- [ ] SPAWN_A at (0,0), SPAWN_B at (width-1, height-1)
- [ ] All 6 markers on unique cells, keys/chest not on spawn cells
- [ ] Fairness validation: all 4 targets have path delta <= max_fairness_delta
- [ ] Minimum size check: w*h >= 6 AND w >= 2 AND h >= 2; fails otherwise
- [ ] Different random seeds produce different mazes (>= 9/10 unique)
- [ ] Boundary walls remain intact after generation
- [ ] 50x50 maze generates successfully without stack overflow
- [ ] `maze_generated` signal emitted on success, `generation_failed` on failure
- [ ] Config values from `game_config.json` (max_fairness_delta, max_generation_retries)

### Grid Movement
- [ ] `initialize()` places movers at SPAWN_A / SPAWN_B positions
- [ ] `initialize()` records spawn in visited_cells
- [ ] `initialize()` triggers `fog.update_vision()` for each mover
- [ ] `set_direction()` + `on_tick()` moves mover to adjacent cell (if passable)
- [ ] Blocked movement: position unchanged, blocked_count increments, `mover_blocked` emitted
- [ ] No direction (NONE): `mover_stayed` emitted
- [ ] `pending_direction` cleared after each tick
- [ ] Last `set_direction()` call wins (overwrite semantics)
- [ ] `visited_cells` has no duplicates
- [ ] Both movers process in same tick, signals batch-emitted after all processing
- [ ] `reset()` clears all state
- [ ] Invalid mover_id does not crash
- [ ] Direction offsets: NORTH=(0,-1), EAST=(1,0), SOUTH=(0,1), WEST=(-1,0)
- [ ] All tests pass (~109+ across Foundation + Core)
