# Foundation Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the three Foundation-layer systems (Maze Data Model, Match State Manager, Scene Manager) that all other game systems depend on, plus project scaffolding (Godot project, GUT test framework, directory structure, configuration files).

**Architecture:** Pure GDScript classes and Autoloads. MazeData is a RefCounted resource (no scene needed). MatchStateManager and SceneManager are Autoload singletons registered in project.godot. All gameplay values read from JSON config files with hardcoded fallbacks. GUT addon for unit testing.

**Tech Stack:** Godot 4.6, GDScript, GUT 9.x (Godot Unit Test), JSON config files

---

## File Structure

```
src/
  core/
    maze_data.gd              # MazeData class (RefCounted) - grid, walls, markers, BFS
    match_state_manager.gd    # MatchStateManager (Node, Autoload) - FSM, tick timer, config
    scene_manager.gd           # SceneManager (Node, Autoload) - scene registry, switching
  shared/
    enums.gd                   # Shared enums (Direction, MarkerType, MatchState, etc.)
    config_loader.gd           # JSON config loader utility

assets/
  data/
    game_config.json           # Gameplay config (maze size, tick interval, vision radius, etc.)
    scene_registry.json        # Scene name -> .tscn path mapping

scenes/
  match/
    Match.tscn                 # Match scene (placeholder - just root Node2D)
    match.gd                   # Match scene script (listens to MSM signals)
  result/
    Result.tscn                # Result scene (placeholder - just root Control)
    result.gd                  # Result scene script (placeholder)

tests/
  unit/
    test_maze_data.gd          # MazeData unit tests
    test_match_state_manager.gd # MatchStateManager unit tests
    test_scene_manager.gd      # SceneManager unit tests
    test_config_loader.gd      # ConfigLoader unit tests

project.godot                  # Godot project file with Autoload registration
```

---

### Task 0: Project Scaffolding & GUT Setup

**Files:**
- Create: `project.godot`
- Create: `src/shared/enums.gd`
- Create: `src/shared/config_loader.gd`
- Create: `assets/data/game_config.json`
- Create: `assets/data/scene_registry.json`
- Create: `scenes/match/Match.tscn`
- Create: `scenes/match/match.gd`
- Create: `scenes/result/Result.tscn`
- Create: `scenes/result/result.gd`
- Create: `tests/unit/.gitkeep`

- [ ] **Step 1: Install GUT addon**

Run:
```bash
cd /Users/yao/.superset/worktrees/first-to-the-key/session18
mkdir -p addons
git clone --depth 1 --branch v9.3.0 https://github.com/bitwes/Gut.git addons/gut
rm -rf addons/gut/.git
```

If the exact tag doesn't exist, use the latest stable:
```bash
git clone --depth 1 https://github.com/bitwes/Gut.git addons/gut
rm -rf addons/gut/.git
```

Expected: `addons/gut/` directory exists with `plugin.cfg`

- [ ] **Step 2: Create project.godot**

Create `project.godot`:

```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; but it can also be manually edited.

config_version=5

[application]

config/name="First to the Key"
config/description="A 2D maze racing game where LLM agents compete"
run/main_scene="res://scenes/match/Match.tscn"
config/features=PackedStringArray("4.6")

[autoload]

Enums="*res://src/shared/enums.gd"
MatchStateManager="*res://src/core/match_state_manager.gd"
SceneManagerGlobal="*res://src/core/scene_manager.gd"

[display]

window/size/viewport_width=1280
window/size/viewport_height=720

[editor_plugins]

enabled=PackedStringArray("res://addons/gut/plugin.cfg")

[gut]

directory="res://tests"
prefix="test_"
suffix=".gd"
```

Note: SceneManager autoload is named `SceneManagerGlobal` to avoid conflict with Godot's internal SceneManager class.

- [ ] **Step 3: Create shared enums**

Create `src/shared/enums.gd`:

```gdscript
## Shared enums used across all game systems.
## Registered as Autoload "Enums" for global access.
extends Node

enum Direction { NORTH, EAST, SOUTH, WEST }

enum MarkerType { SPAWN_A, SPAWN_B, KEY_BRASS, KEY_JADE, KEY_CRYSTAL, CHEST }

enum MatchState { SETUP, COUNTDOWN, PLAYING, FINISHED }

enum GameMode { AGENT_VS_AGENT, PLAYER_VS_AGENT, PLAYER_VS_PLAYER }

enum MatchResult { NONE, PLAYER_A_WIN, PLAYER_B_WIN, DRAW }

enum VisionStrategy { PATH_REACH, LINE_OF_SIGHT }

enum MoveDirection { NORTH, EAST, SOUTH, WEST, NONE }


## Direction -> Vector2i offset mapping.
const DIRECTION_OFFSETS: Dictionary = {
	Direction.NORTH: Vector2i(0, -1),
	Direction.EAST: Vector2i(1, 0),
	Direction.SOUTH: Vector2i(0, 1),
	Direction.WEST: Vector2i(-1, 0),
}

## Direction -> opposite direction mapping.
const OPPOSITE_DIRECTION: Dictionary = {
	Direction.NORTH: Direction.SOUTH,
	Direction.SOUTH: Direction.NORTH,
	Direction.EAST: Direction.WEST,
	Direction.WEST: Direction.EAST,
}
```

- [ ] **Step 4: Create config loader utility**

Create `src/shared/config_loader.gd`:

```gdscript
## Utility for loading JSON configuration files with fallback defaults.
class_name ConfigLoader
extends RefCounted


## Load a JSON file and return parsed Dictionary.
## Returns empty Dictionary on failure and prints error.
static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ConfigLoader: File not found: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ConfigLoader: Cannot open file: %s" % path)
		return {}

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		push_error("ConfigLoader: JSON parse error in %s at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}

	var result = json.data
	if result is Dictionary:
		return result

	push_error("ConfigLoader: Expected Dictionary at root of %s, got %s" % [path, typeof(result)])
	return {}


## Get a value from a dictionary with a default fallback.
## Prints a warning if the key is missing.
static func get_or_default(config: Dictionary, key: String, default_value: Variant) -> Variant:
	if config.has(key):
		return config[key]
	push_warning("ConfigLoader: Key '%s' missing from config, using default: %s" % [key, str(default_value)])
	return default_value
```

- [ ] **Step 5: Create game config JSON**

Create `assets/data/game_config.json`:

```json
{
	"maze": {
		"width": 15,
		"height": 15,
		"cell_size": 32,
		"max_fairness_delta": 2
	},
	"match": {
		"tick_interval": 0.5,
		"countdown_duration": 3.0,
		"max_match_duration": 300.0
	},
	"vision": {
		"vision_radius": 3,
		"vision_strategy": "PATH_REACH"
	},
	"generator": {
		"max_generation_retries": 50
	},
	"llm_format": {
		"include_ascii_map": false,
		"include_explored": true,
		"max_visited_count": 20,
		"max_explored_count": 30
	},
	"scene": {
		"initial_scene": "match",
		"config_file_path": "res://assets/data/scene_registry.json"
	}
}
```

- [ ] **Step 6: Create scene registry JSON**

Create `assets/data/scene_registry.json`:

```json
{
	"match": "res://scenes/match/Match.tscn",
	"result": "res://scenes/result/Result.tscn"
}
```

- [ ] **Step 7: Create placeholder Match scene**

Create `scenes/match/match.gd`:

```gdscript
## Match scene root script.
## Manages the match lifecycle by listening to MatchStateManager signals.
extends Node2D
```

Create `scenes/match/Match.tscn` via script:

```bash
cat > scenes/match/Match.tscn << 'TSCN'
[gd_scene load_steps=2 format=3 uid="uid://match_scene"]

[ext_resource type="Script" path="res://scenes/match/match.gd" id="1"]

[node name="Match" type="Node2D"]
script = ExtResource("1")
TSCN
```

- [ ] **Step 8: Create placeholder Result scene**

Create `scenes/result/result.gd`:

```gdscript
## Result scene root script.
## Displays match results and provides Rematch/Quit buttons.
extends Control
```

Create `scenes/result/Result.tscn` via script:

```bash
cat > scenes/result/Result.tscn << 'TSCN'
[gd_scene load_steps=2 format=3 uid="uid://result_scene"]

[ext_resource type="Script" path="res://scenes/result/result.gd" id="1"]

[node name="Result" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")
TSCN
```

- [ ] **Step 9: Create test directory structure**

```bash
mkdir -p tests/unit
touch tests/unit/.gitkeep
```

- [ ] **Step 10: Verify project structure**

Run:
```bash
find . -name "*.gd" -o -name "*.tscn" -o -name "*.json" -o -name "project.godot" | grep -v addons | grep -v .git | grep -v prototypes | sort
```

Expected output should include:
```
./assets/data/game_config.json
./assets/data/scene_registry.json
./project.godot
./scenes/match/Match.tscn
./scenes/match/match.gd
./scenes/result/Result.tscn
./scenes/result/result.gd
./src/shared/config_loader.gd
./src/shared/enums.gd
```

- [ ] **Step 11: Commit scaffolding**

```bash
git add project.godot src/shared/ assets/data/ scenes/ tests/ addons/gut/
git commit -m "feat: project scaffolding with GUT, shared enums, config loader, placeholder scenes

- Godot 4.6 project with autoload registration
- GUT test framework addon installed
- Shared enums (Direction, MarkerType, MatchState, GameMode, etc.)
- ConfigLoader utility for JSON config with fallback defaults
- game_config.json with maze/match/vision/generator settings
- scene_registry.json mapping scene names to .tscn paths
- Placeholder Match and Result scenes"
```

---

### Task 1: MazeData - Cell Structure and Basic Queries

**Files:**
- Create: `src/core/maze_data.gd`
- Create: `tests/unit/test_maze_data.gd`

- [ ] **Step 1: Write the failing test for MazeData construction and initial state**

Create `tests/unit/test_maze_data.gd`:

```gdscript
## Unit tests for MazeData class.
extends GutTest

const MazeData := preload("res://src/core/maze_data.gd")


func test_constructor_creates_grid_with_correct_dimensions() -> void:
	var maze := MazeData.new(5, 4)
	assert_eq(maze.width, 5, "Width should be 5")
	assert_eq(maze.height, 4, "Height should be 4")


func test_all_cells_start_with_four_walls() -> void:
	var maze := MazeData.new(3, 3)
	for y in range(3):
		for x in range(3):
			assert_true(maze.has_wall(x, y, Enums.Direction.NORTH), "(%d,%d) NORTH wall" % [x, y])
			assert_true(maze.has_wall(x, y, Enums.Direction.EAST), "(%d,%d) EAST wall" % [x, y])
			assert_true(maze.has_wall(x, y, Enums.Direction.SOUTH), "(%d,%d) SOUTH wall" % [x, y])
			assert_true(maze.has_wall(x, y, Enums.Direction.WEST), "(%d,%d) WEST wall" % [x, y])


func test_all_cells_start_with_no_markers() -> void:
	var maze := MazeData.new(3, 3)
	for y in range(3):
		for x in range(3):
			assert_eq(maze.get_markers_at(x, y).size(), 0, "(%d,%d) should have no markers" % [x, y])


func test_can_move_returns_false_when_all_walls() -> void:
	var maze := MazeData.new(3, 3)
	assert_false(maze.can_move(1, 1, Enums.Direction.NORTH))
	assert_false(maze.can_move(1, 1, Enums.Direction.EAST))
	assert_false(maze.can_move(1, 1, Enums.Direction.SOUTH))
	assert_false(maze.can_move(1, 1, Enums.Direction.WEST))


func test_get_neighbors_returns_empty_when_all_walls() -> void:
	var maze := MazeData.new(3, 3)
	assert_eq(maze.get_neighbors(1, 1).size(), 0)


func test_out_of_bounds_get_cell_returns_null() -> void:
	var maze := MazeData.new(3, 3)
	assert_null(maze.get_cell(-1, 0))
	assert_null(maze.get_cell(3, 0))
	assert_null(maze.get_cell(0, -1))
	assert_null(maze.get_cell(0, 3))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_data.gd -gexit`

Expected: FAIL - cannot preload `maze_data.gd` (file doesn't exist)

- [ ] **Step 3: Write MazeData with construction and basic queries**

Create `src/core/maze_data.gd`:

```gdscript
## Maze Data Model - spatial data foundation for the entire game.
## Represents a 2D grid maze with walls, markers, and pathfinding.
## See design/gdd/maze-data-model.md for full specification.
class_name MazeData
extends RefCounted

## Grid dimensions.
var width: int
var height: int

## Internal cell storage. Access as _cells[y][x].
## Each cell is a Dictionary: { "walls": {dir: bool}, "markers": Array[Enums.MarkerType] }
var _cells: Array[Array] = []

## Whether the maze is finalized (write-locked).
var _finalized: bool = false

## Marker position cache: MarkerType -> Vector2i.
var _marker_positions: Dictionary = {}


func _init(w: int, h: int) -> void:
	width = w
	height = h
	_init_cells()


## Initialize all cells with four walls and no markers.
func _init_cells() -> void:
	_cells.clear()
	_marker_positions.clear()
	for y in range(height):
		var row: Array[Dictionary] = []
		for x in range(width):
			row.append({
				"walls": {
					Enums.Direction.NORTH: true,
					Enums.Direction.EAST: true,
					Enums.Direction.SOUTH: true,
					Enums.Direction.WEST: true,
				},
				"markers": [] as Array[int],
			})
		_cells.append(row)


## Returns the cell dictionary at (x, y), or null if out of bounds.
func get_cell(x: int, y: int) -> Variant:
	if x < 0 or x >= width or y < 0 or y >= height:
		push_warning("MazeData: get_cell(%d, %d) out of bounds (size %dx%d)" % [x, y, width, height])
		return null
	return _cells[y][x]


## Returns true if the specified wall exists.
func has_wall(x: int, y: int, direction: int) -> bool:
	var cell = get_cell(x, y)
	if cell == null:
		return true  # Out of bounds treated as walled
	return cell["walls"][direction]


## Returns true if movement in the given direction is possible (no wall).
func can_move(x: int, y: int, direction: int) -> bool:
	return not has_wall(x, y, direction)


## Returns coordinates of all passable neighbors.
func get_neighbors(x: int, y: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in [Enums.Direction.NORTH, Enums.Direction.EAST, Enums.Direction.SOUTH, Enums.Direction.WEST]:
		if can_move(x, y, dir):
			var offset: Vector2i = Enums.DIRECTION_OFFSETS[dir]
			result.append(Vector2i(x + offset.x, y + offset.y))
	return result


## Returns all markers at the given position.
func get_markers_at(x: int, y: int) -> Array:
	var cell = get_cell(x, y)
	if cell == null:
		return []
	return cell["markers"].duplicate()


## Returns the position of a marker type, or Vector2i(-1, -1) if not placed.
func get_marker_position(marker_type: int) -> Vector2i:
	if _marker_positions.has(marker_type):
		return _marker_positions[marker_type]
	return Vector2i(-1, -1)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_data.gd -gexit`

Expected: All 6 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/maze_data.gd tests/unit/test_maze_data.gd
git commit -m "feat: MazeData construction, walls, and basic queries (TDD)"
```

---

### Task 2: MazeData - Wall Modification with Shared Sync

**Files:**
- Modify: `src/core/maze_data.gd`
- Modify: `tests/unit/test_maze_data.gd`

- [ ] **Step 1: Write the failing tests for wall modification**

Append to `tests/unit/test_maze_data.gd`:

```gdscript
func test_set_wall_removes_wall_and_syncs_neighbor() -> void:
	var maze := MazeData.new(3, 3)
	maze.set_wall(1, 1, Enums.Direction.EAST, false)
	assert_false(maze.has_wall(1, 1, Enums.Direction.EAST), "(1,1) EAST should be open")
	assert_false(maze.has_wall(2, 1, Enums.Direction.WEST), "(2,1) WEST should be open (synced)")


func test_set_wall_adds_wall_and_syncs_neighbor() -> void:
	var maze := MazeData.new(3, 3)
	maze.set_wall(1, 1, Enums.Direction.EAST, false)  # Remove first
	maze.set_wall(1, 1, Enums.Direction.EAST, true)   # Add back
	assert_true(maze.has_wall(1, 1, Enums.Direction.EAST))
	assert_true(maze.has_wall(2, 1, Enums.Direction.WEST))


func test_boundary_wall_cannot_be_removed() -> void:
	var maze := MazeData.new(3, 3)
	maze.set_wall(0, 0, Enums.Direction.WEST, false)
	assert_true(maze.has_wall(0, 0, Enums.Direction.WEST), "Left boundary wall must stay")

	maze.set_wall(0, 0, Enums.Direction.NORTH, false)
	assert_true(maze.has_wall(0, 0, Enums.Direction.NORTH), "Top boundary wall must stay")

	maze.set_wall(2, 2, Enums.Direction.EAST, false)
	assert_true(maze.has_wall(2, 2, Enums.Direction.EAST), "Right boundary wall must stay")

	maze.set_wall(2, 2, Enums.Direction.SOUTH, false)
	assert_true(maze.has_wall(2, 2, Enums.Direction.SOUTH), "Bottom boundary wall must stay")


func test_can_move_after_wall_removal() -> void:
	var maze := MazeData.new(3, 3)
	maze.set_wall(1, 1, Enums.Direction.NORTH, false)
	assert_true(maze.can_move(1, 1, Enums.Direction.NORTH))
	assert_true(maze.can_move(1, 0, Enums.Direction.SOUTH))


func test_get_neighbors_after_wall_removal() -> void:
	var maze := MazeData.new(3, 3)
	maze.set_wall(1, 1, Enums.Direction.EAST, false)
	maze.set_wall(1, 1, Enums.Direction.SOUTH, false)
	var neighbors := maze.get_neighbors(1, 1)
	assert_eq(neighbors.size(), 2)
	assert_has(neighbors, Vector2i(2, 1))
	assert_has(neighbors, Vector2i(1, 2))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_data.gd -gexit`

Expected: FAIL - `set_wall` method doesn't exist

- [ ] **Step 3: Implement set_wall with boundary protection and neighbor sync**

Add to `src/core/maze_data.gd` (after `get_marker_position`):

```gdscript
## Check if a wall is on the maze boundary.
func _is_boundary_wall(x: int, y: int, direction: int) -> bool:
	match direction:
		Enums.Direction.NORTH: return y == 0
		Enums.Direction.SOUTH: return y == height - 1
		Enums.Direction.WEST: return x == 0
		Enums.Direction.EAST: return x == width - 1
	return false


## Set wall state, syncing the shared wall on the neighbor cell.
## Boundary walls cannot be removed (silently enforced).
func set_wall(x: int, y: int, direction: int, value: bool) -> void:
	if _finalized:
		push_error("MazeData is finalized, write operation rejected")
		return

	var cell = get_cell(x, y)
	if cell == null:
		return

	# Boundary walls are always true - ignore attempts to remove them
	if not value and _is_boundary_wall(x, y, direction):
		return

	cell["walls"][direction] = value

	# Sync the neighbor's corresponding wall
	var offset: Vector2i = Enums.DIRECTION_OFFSETS[direction]
	var nx := x + offset.x
	var ny := y + offset.y
	var neighbor = get_cell(nx, ny)
	if neighbor != null:
		var opposite_dir: int = Enums.OPPOSITE_DIRECTION[direction]
		neighbor["walls"][opposite_dir] = value
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_data.gd -gexit`

Expected: All 11 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/maze_data.gd tests/unit/test_maze_data.gd
git commit -m "feat: MazeData wall modification with boundary protection and neighbor sync"
```

---

### Task 3: MazeData - Marker Placement

**Files:**
- Modify: `src/core/maze_data.gd`
- Modify: `tests/unit/test_maze_data.gd`

- [ ] **Step 1: Write the failing tests for marker placement**

Append to `tests/unit/test_maze_data.gd`:

```gdscript
func test_place_marker_and_query() -> void:
	var maze := MazeData.new(5, 5)
	maze.place_marker(2, 3, Enums.MarkerType.SPAWN_A)
	assert_eq(maze.get_marker_position(Enums.MarkerType.SPAWN_A), Vector2i(2, 3))
	var markers := maze.get_markers_at(2, 3)
	assert_has(markers, Enums.MarkerType.SPAWN_A)


func test_place_marker_uniqueness_relocates() -> void:
	var maze := MazeData.new(5, 5)
	maze.place_marker(1, 1, Enums.MarkerType.SPAWN_A)
	maze.place_marker(3, 3, Enums.MarkerType.SPAWN_A)
	# Old position should no longer have the marker
	assert_eq(maze.get_markers_at(1, 1).size(), 0, "Old position should be empty")
	# New position should have it
	assert_eq(maze.get_marker_position(Enums.MarkerType.SPAWN_A), Vector2i(3, 3))
	assert_has(maze.get_markers_at(3, 3), Enums.MarkerType.SPAWN_A)


func test_remove_marker() -> void:
	var maze := MazeData.new(5, 5)
	maze.place_marker(2, 2, Enums.MarkerType.KEY_BRASS)
	maze.remove_marker(2, 2, Enums.MarkerType.KEY_BRASS)
	assert_eq(maze.get_markers_at(2, 2).size(), 0)
	assert_eq(maze.get_marker_position(Enums.MarkerType.KEY_BRASS), Vector2i(-1, -1))


func test_multiple_markers_on_same_cell() -> void:
	var maze := MazeData.new(5, 5)
	maze.place_marker(2, 2, Enums.MarkerType.KEY_BRASS)
	maze.place_marker(2, 2, Enums.MarkerType.SPAWN_A)
	var markers := maze.get_markers_at(2, 2)
	assert_eq(markers.size(), 2)
	assert_has(markers, Enums.MarkerType.KEY_BRASS)
	assert_has(markers, Enums.MarkerType.SPAWN_A)


func test_unplaced_marker_returns_negative_one() -> void:
	var maze := MazeData.new(5, 5)
	assert_eq(maze.get_marker_position(Enums.MarkerType.CHEST), Vector2i(-1, -1))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_data.gd -gexit`

Expected: FAIL - `place_marker` method doesn't exist

- [ ] **Step 3: Implement marker placement with uniqueness enforcement**

Add to `src/core/maze_data.gd`:

```gdscript
## Place a marker at (x, y). Unique marker types (SPAWN, KEY, CHEST)
## are auto-relocated: old position is cleared first.
func place_marker(x: int, y: int, marker_type: int) -> void:
	if _finalized:
		push_error("MazeData is finalized, write operation rejected")
		return

	var cell = get_cell(x, y)
	if cell == null:
		return

	# Remove from old position if this marker type already exists
	if _marker_positions.has(marker_type):
		var old_pos: Vector2i = _marker_positions[marker_type]
		var old_cell = get_cell(old_pos.x, old_pos.y)
		if old_cell != null:
			old_cell["markers"].erase(marker_type)

	cell["markers"].append(marker_type)
	_marker_positions[marker_type] = Vector2i(x, y)


## Remove a specific marker from (x, y).
func remove_marker(x: int, y: int, marker_type: int) -> void:
	if _finalized:
		push_error("MazeData is finalized, write operation rejected")
		return

	var cell = get_cell(x, y)
	if cell == null:
		return

	cell["markers"].erase(marker_type)

	if _marker_positions.has(marker_type) and _marker_positions[marker_type] == Vector2i(x, y):
		_marker_positions.erase(marker_type)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_data.gd -gexit`

Expected: All 16 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/maze_data.gd tests/unit/test_maze_data.gd
git commit -m "feat: MazeData marker placement with uniqueness enforcement"
```

---

### Task 4: MazeData - Validation, Finalize, Reset

**Files:**
- Modify: `src/core/maze_data.gd`
- Modify: `tests/unit/test_maze_data.gd`

- [ ] **Step 1: Write the failing tests for validation and lifecycle**

Append to `tests/unit/test_maze_data.gd`:

```gdscript
## Helper: create a minimal valid 3x3 maze (all connected, all markers placed).
func _make_valid_maze() -> MazeData:
	var maze := MazeData.new(3, 3)
	# Open a path: (0,0)-(1,0)-(2,0)-(2,1)-(2,2)-(1,2)-(0,2)-(0,1)-(1,1)
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	maze.set_wall(1, 0, Enums.Direction.EAST, false)
	maze.set_wall(2, 0, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 1, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 2, Enums.Direction.WEST, false)
	maze.set_wall(1, 2, Enums.Direction.WEST, false)
	maze.set_wall(0, 2, Enums.Direction.NORTH, false)
	maze.set_wall(1, 1, Enums.Direction.SOUTH, false)
	# Place all 6 markers on unique cells
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(2, 2, Enums.MarkerType.SPAWN_B)
	maze.place_marker(1, 0, Enums.MarkerType.KEY_BRASS)
	maze.place_marker(2, 0, Enums.MarkerType.KEY_JADE)
	maze.place_marker(2, 1, Enums.MarkerType.KEY_CRYSTAL)
	maze.place_marker(1, 2, Enums.MarkerType.CHEST)
	return maze


func test_is_valid_with_complete_maze() -> void:
	var maze := _make_valid_maze()
	assert_true(maze.is_valid())


func test_is_valid_fails_missing_marker() -> void:
	var maze := _make_valid_maze()
	maze.remove_marker(1, 2, Enums.MarkerType.CHEST)
	assert_false(maze.is_valid())


func test_is_valid_fails_duplicate_marker_positions() -> void:
	var maze := MazeData.new(3, 3)
	# Open path
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	maze.set_wall(1, 0, Enums.Direction.EAST, false)
	maze.set_wall(2, 0, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 1, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 2, Enums.Direction.WEST, false)
	maze.set_wall(1, 2, Enums.Direction.WEST, false)
	maze.set_wall(0, 2, Enums.Direction.NORTH, false)
	maze.set_wall(1, 1, Enums.Direction.SOUTH, false)
	# Place two markers on same cell
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(0, 0, Enums.MarkerType.KEY_BRASS)  # Same cell as SPAWN_A!
	maze.place_marker(2, 2, Enums.MarkerType.SPAWN_B)
	maze.place_marker(1, 0, Enums.MarkerType.KEY_JADE)
	maze.place_marker(2, 0, Enums.MarkerType.KEY_CRYSTAL)
	maze.place_marker(2, 1, Enums.MarkerType.CHEST)
	assert_false(maze.is_valid())


func test_is_valid_fails_disconnected() -> void:
	var maze := MazeData.new(3, 3)
	# No walls removed - all cells isolated
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(2, 2, Enums.MarkerType.SPAWN_B)
	maze.place_marker(1, 0, Enums.MarkerType.KEY_BRASS)
	maze.place_marker(2, 0, Enums.MarkerType.KEY_JADE)
	maze.place_marker(2, 1, Enums.MarkerType.KEY_CRYSTAL)
	maze.place_marker(1, 2, Enums.MarkerType.CHEST)
	assert_false(maze.is_valid())


func test_finalize_locks_writes() -> void:
	var maze := _make_valid_maze()
	assert_true(maze.finalize())
	# Writes should be rejected after finalize
	maze.set_wall(1, 1, Enums.Direction.NORTH, false)
	assert_true(maze.has_wall(1, 1, Enums.Direction.NORTH), "set_wall should be rejected after finalize")
	maze.place_marker(1, 1, Enums.MarkerType.CHEST)
	assert_eq(maze.get_marker_position(Enums.MarkerType.CHEST), Vector2i(1, 2), "place_marker should be rejected after finalize")


func test_finalize_fails_on_invalid_maze() -> void:
	var maze := MazeData.new(3, 3)  # No markers
	assert_false(maze.finalize())


func test_reset_restores_initial_state() -> void:
	var maze := _make_valid_maze()
	maze.finalize()
	maze.reset()
	# All walls should be back
	assert_true(maze.has_wall(0, 0, Enums.Direction.EAST))
	# Markers cleared
	assert_eq(maze.get_marker_position(Enums.MarkerType.SPAWN_A), Vector2i(-1, -1))
	# Write should work again
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	assert_false(maze.has_wall(0, 0, Enums.Direction.EAST))


func test_reset_is_idempotent() -> void:
	var maze := MazeData.new(3, 3)
	maze.reset()  # Should not error on Uninitialized state
	assert_true(maze.has_wall(0, 0, Enums.Direction.NORTH))


func test_reset_then_finalize_works() -> void:
	var maze := _make_valid_maze()
	maze.finalize()
	maze.reset()
	# Rebuild the same valid maze
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	maze.set_wall(1, 0, Enums.Direction.EAST, false)
	maze.set_wall(2, 0, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 1, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 2, Enums.Direction.WEST, false)
	maze.set_wall(1, 2, Enums.Direction.WEST, false)
	maze.set_wall(0, 2, Enums.Direction.NORTH, false)
	maze.set_wall(1, 1, Enums.Direction.SOUTH, false)
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(2, 2, Enums.MarkerType.SPAWN_B)
	maze.place_marker(1, 0, Enums.MarkerType.KEY_BRASS)
	maze.place_marker(2, 0, Enums.MarkerType.KEY_JADE)
	maze.place_marker(2, 1, Enums.MarkerType.KEY_CRYSTAL)
	maze.place_marker(1, 2, Enums.MarkerType.CHEST)
	assert_true(maze.finalize())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_data.gd -gexit`

Expected: FAIL - `is_valid`, `finalize`, `reset` methods don't exist

- [ ] **Step 3: Implement is_valid, finalize, and reset**

Add to `src/core/maze_data.gd`:

```gdscript
## Validate maze integrity:
## - All 6 required markers (SPAWN_A/B, KEY_BRASS/JADE/CRYSTAL, CHEST) exist
## - All 6 marker positions are unique (no two markers on same cell)
## - Maze is fully connected (BFS from SPAWN_A reaches all cells)
func is_valid() -> bool:
	var required_markers := [
		Enums.MarkerType.SPAWN_A,
		Enums.MarkerType.SPAWN_B,
		Enums.MarkerType.KEY_BRASS,
		Enums.MarkerType.KEY_JADE,
		Enums.MarkerType.KEY_CRYSTAL,
		Enums.MarkerType.CHEST,
	]

	# Check all required markers exist
	for marker in required_markers:
		if not _marker_positions.has(marker):
			push_error("MazeData: Missing required marker: %d" % marker)
			return false

	# Check all marker positions are unique
	var positions: Array[Vector2i] = []
	for marker in required_markers:
		var pos: Vector2i = _marker_positions[marker]
		if pos in positions:
			push_error("MazeData: Duplicate marker position at (%d, %d)" % [pos.x, pos.y])
			return false
		positions.append(pos)

	# Check full connectivity via BFS from SPAWN_A
	var start: Vector2i = _marker_positions[Enums.MarkerType.SPAWN_A]
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true

	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		for neighbor in get_neighbors(current.x, current.y):
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)

	if visited.size() != width * height:
		push_error("MazeData: Unreachable cells detected (%d reachable of %d total)" % [visited.size(), width * height])
		return false

	return true


## Validate and lock the maze for reading. Returns true if valid.
func finalize() -> bool:
	if not is_valid():
		return false
	_finalized = true
	return true


## Reset to uninitialized state: all walls up, all markers cleared, writes unlocked.
func reset() -> void:
	_finalized = false
	_init_cells()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_data.gd -gexit`

Expected: All 25 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/maze_data.gd tests/unit/test_maze_data.gd
git commit -m "feat: MazeData validation, finalize, and reset lifecycle"
```

---

### Task 5: MazeData - BFS Shortest Path

**Files:**
- Modify: `src/core/maze_data.gd`
- Modify: `tests/unit/test_maze_data.gd`

- [ ] **Step 1: Write the failing tests for BFS shortest path**

Append to `tests/unit/test_maze_data.gd`:

```gdscript
func test_shortest_path_adjacent() -> void:
	var maze := MazeData.new(3, 3)
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	var path := maze.get_shortest_path(Vector2i(0, 0), Vector2i(1, 0))
	assert_eq(path.size(), 2, "Path should have 2 nodes (start + end)")
	assert_eq(path[0], Vector2i(0, 0))
	assert_eq(path[1], Vector2i(1, 0))


func test_shortest_path_same_position() -> void:
	var maze := MazeData.new(3, 3)
	var path := maze.get_shortest_path(Vector2i(1, 1), Vector2i(1, 1))
	assert_eq(path.size(), 0, "Same start and goal should return empty path")


func test_shortest_path_no_connection() -> void:
	var maze := MazeData.new(3, 3)  # All walls - no connections
	var path := maze.get_shortest_path(Vector2i(0, 0), Vector2i(2, 2))
	assert_eq(path.size(), 0, "Disconnected cells should return empty path")


func test_shortest_path_linear() -> void:
	var maze := MazeData.new(5, 1)
	# Open a straight line: (0,0)-(1,0)-(2,0)-(3,0)-(4,0)
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	maze.set_wall(1, 0, Enums.Direction.EAST, false)
	maze.set_wall(2, 0, Enums.Direction.EAST, false)
	maze.set_wall(3, 0, Enums.Direction.EAST, false)
	var path := maze.get_shortest_path(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(path.size(), 5, "Path length should be 5 (0->1->2->3->4)")


func test_shortest_path_finds_shorter_route() -> void:
	# Create a maze with two paths: short (2 steps) and long (4 steps)
	var maze := MazeData.new(3, 2)
	# Short path: (0,0) -> (1,0) -> (2,0)
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	maze.set_wall(1, 0, Enums.Direction.EAST, false)
	# Long path: (0,0) -> (0,1) -> (1,1) -> (2,1) -> (2,0)
	maze.set_wall(0, 0, Enums.Direction.SOUTH, false)
	maze.set_wall(0, 1, Enums.Direction.EAST, false)
	maze.set_wall(1, 1, Enums.Direction.EAST, false)
	maze.set_wall(2, 1, Enums.Direction.NORTH, false)
	var path := maze.get_shortest_path(Vector2i(0, 0), Vector2i(2, 0))
	assert_eq(path.size(), 3, "Should find shortest path (3 nodes = 2 steps)")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_data.gd -gexit`

Expected: FAIL - `get_shortest_path` method doesn't exist

- [ ] **Step 3: Implement BFS shortest path**

Add to `src/core/maze_data.gd`:

```gdscript
## BFS shortest path from start to goal. Returns array of Vector2i coordinates
## including start and goal. Returns empty array if start == goal or unreachable.
func get_shortest_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if start == goal:
		return [] as Array[Vector2i]

	# BFS
	var queue: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	came_from[start] = null

	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		if current == goal:
			# Reconstruct path
			var path: Array[Vector2i] = []
			var node: Variant = goal
			while node != null:
				path.append(node)
				node = came_from[node]
			path.reverse()
			return path

		for neighbor in get_neighbors(current.x, current.y):
			if not came_from.has(neighbor):
				came_from[neighbor] = current
				queue.append(neighbor)

	# No path found
	return [] as Array[Vector2i]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_maze_data.gd -gexit`

Expected: All 30 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/maze_data.gd tests/unit/test_maze_data.gd
git commit -m "feat: MazeData BFS shortest path algorithm"
```

---

### Task 6: MatchStateManager - FSM Core and State Transitions

**Files:**
- Create: `src/core/match_state_manager.gd`
- Create: `tests/unit/test_match_state_manager.gd`

- [ ] **Step 1: Write the failing tests for FSM transitions**

Create `tests/unit/test_match_state_manager.gd`:

```gdscript
## Unit tests for MatchStateManager.
extends GutTest

var msm: Node


func before_each() -> void:
	# Create a fresh instance (not the autoload singleton)
	msm = load("res://src/core/match_state_manager.gd").new()
	add_child_autoqfree(msm)


func test_initial_state_is_setup() -> void:
	assert_eq(msm.current_state, Enums.MatchState.SETUP)


func test_start_setup_sets_config() -> void:
	var config := {
		"game_mode": Enums.GameMode.AGENT_VS_AGENT,
		"prompt_a": "test prompt a",
		"prompt_b": "",
	}
	msm.start_setup(config)
	assert_eq(msm.current_state, Enums.MatchState.SETUP)
	assert_eq(msm.config["prompt_a"], "test prompt a")


func test_start_countdown_requires_finalized_maze() -> void:
	msm.start_setup({})
	# No maze set - should fail
	assert_false(msm.start_countdown())
	assert_eq(msm.current_state, Enums.MatchState.SETUP)


func test_start_countdown_succeeds_with_maze() -> void:
	msm.start_setup({})
	# Create and finalize a mock maze
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	assert_true(msm.start_countdown())
	assert_eq(msm.current_state, Enums.MatchState.COUNTDOWN)


func test_invalid_transition_setup_to_playing() -> void:
	msm.start_setup({})
	msm.start_playing()
	assert_eq(msm.current_state, Enums.MatchState.SETUP, "Should remain SETUP")


func test_finish_match_only_from_playing() -> void:
	msm.start_setup({})
	msm.finish_match(Enums.MatchResult.PLAYER_A_WIN, 0)
	assert_eq(msm.current_state, Enums.MatchState.SETUP, "Should remain SETUP")


func test_reset_from_any_state() -> void:
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	msm.reset()
	assert_eq(msm.current_state, Enums.MatchState.SETUP)
	assert_null(msm.current_maze)
	assert_eq(msm.tick_count, 0)
	assert_eq(msm.result, Enums.MatchResult.NONE)


func test_state_changed_signal_emitted() -> void:
	watch_signals(msm)
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	assert_signal_emitted(msm, "state_changed")


func test_finish_match_records_result() -> void:
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	msm.start_playing()
	msm.finish_match(Enums.MatchResult.PLAYER_A_WIN, 0)
	assert_eq(msm.current_state, Enums.MatchState.FINISHED)
	assert_eq(msm.result, Enums.MatchResult.PLAYER_A_WIN)
	assert_eq(msm.winner_id, 0)


## Helper to create a minimal finalized maze.
func _make_finalized_maze(MazeDataClass) -> RefCounted:
	var maze = MazeDataClass.new(3, 3)
	maze.set_wall(0, 0, Enums.Direction.EAST, false)
	maze.set_wall(1, 0, Enums.Direction.EAST, false)
	maze.set_wall(2, 0, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 1, Enums.Direction.SOUTH, false)
	maze.set_wall(2, 2, Enums.Direction.WEST, false)
	maze.set_wall(1, 2, Enums.Direction.WEST, false)
	maze.set_wall(0, 2, Enums.Direction.NORTH, false)
	maze.set_wall(1, 1, Enums.Direction.SOUTH, false)
	maze.place_marker(0, 0, Enums.MarkerType.SPAWN_A)
	maze.place_marker(2, 2, Enums.MarkerType.SPAWN_B)
	maze.place_marker(1, 0, Enums.MarkerType.KEY_BRASS)
	maze.place_marker(2, 0, Enums.MarkerType.KEY_JADE)
	maze.place_marker(2, 1, Enums.MarkerType.KEY_CRYSTAL)
	maze.place_marker(1, 2, Enums.MarkerType.CHEST)
	maze.finalize()
	return maze
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_match_state_manager.gd -gexit`

Expected: FAIL - file doesn't exist

- [ ] **Step 3: Implement MatchStateManager FSM core**

Create `src/core/match_state_manager.gd`:

```gdscript
## Match State Manager - FSM driving the match lifecycle.
## Autoload singleton registered as "MatchStateManager".
## See design/gdd/match-state-manager.md for full specification.
extends Node

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_match_state_manager.gd -gexit`

Expected: All 10 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/match_state_manager.gd tests/unit/test_match_state_manager.gd
git commit -m "feat: MatchStateManager FSM with state transitions, tick timer, countdown"
```

---

### Task 7: MatchStateManager - Tick and Timing Tests

**Files:**
- Modify: `tests/unit/test_match_state_manager.gd`

- [ ] **Step 1: Write tests for tick emission and timing**

Append to `tests/unit/test_match_state_manager.gd`:

```gdscript
func test_tick_increments_in_playing_state() -> void:
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	msm.start_playing()
	assert_eq(msm.tick_count, 0)
	# Simulate tick
	msm._on_tick_timeout()
	assert_eq(msm.tick_count, 1)
	msm._on_tick_timeout()
	assert_eq(msm.tick_count, 2)


func test_tick_signal_emitted() -> void:
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	msm.start_playing()
	watch_signals(msm)
	msm._on_tick_timeout()
	assert_signal_emitted_with_parameters(msm, "tick", [1])


func test_tick_not_emitted_in_setup() -> void:
	watch_signals(msm)
	msm._on_tick_timeout()
	assert_signal_not_emitted(msm, "tick")


func test_finish_match_stops_ticks() -> void:
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	msm.start_playing()
	msm.finish_match(Enums.MatchResult.PLAYER_B_WIN, 1)
	watch_signals(msm)
	msm._on_tick_timeout()
	assert_signal_not_emitted(msm, "tick")


func test_match_finished_signal() -> void:
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	msm.start_playing()
	watch_signals(msm)
	msm.finish_match(Enums.MatchResult.DRAW, -1)
	assert_signal_emitted_with_parameters(msm, "match_finished", [Enums.MatchResult.DRAW])


func test_double_finish_match_second_ignored() -> void:
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	msm.start_playing()
	msm.finish_match(Enums.MatchResult.PLAYER_A_WIN, 0)
	# Second call should be ignored (already FINISHED)
	msm.finish_match(Enums.MatchResult.PLAYER_B_WIN, 1)
	assert_eq(msm.result, Enums.MatchResult.PLAYER_A_WIN, "First result should stick")
	assert_eq(msm.winner_id, 0, "First winner should stick")


func test_countdown_auto_triggers_playing() -> void:
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	assert_eq(msm.current_state, Enums.MatchState.COUNTDOWN)
	# Simulate countdown finishing
	msm._on_countdown_finished()
	assert_eq(msm.current_state, Enums.MatchState.PLAYING)


func test_is_playing_query() -> void:
	assert_false(msm.is_playing())
	msm.start_setup({})
	var MazeDataClass := preload("res://src/core/maze_data.gd")
	var maze := _make_finalized_maze(MazeDataClass)
	msm.current_maze = maze
	msm.start_countdown()
	assert_false(msm.is_playing())
	msm.start_playing()
	assert_true(msm.is_playing())
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_match_state_manager.gd -gexit`

Expected: All 18 tests PASS

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_match_state_manager.gd
git commit -m "test: MatchStateManager tick, timing, and signal tests"
```

---

### Task 8: SceneManager - Registry and Scene Switching

**Files:**
- Create: `src/core/scene_manager.gd`
- Create: `tests/unit/test_scene_manager.gd`

- [ ] **Step 1: Write the failing tests for SceneManager**

Create `tests/unit/test_scene_manager.gd`:

```gdscript
## Unit tests for SceneManager.
extends GutTest

var sm: Node


func before_each() -> void:
	sm = load("res://src/core/scene_manager.gd").new()
	add_child_autoqfree(sm)
	# Manually call initialization since we're not using autoload
	sm._initialize_registry()


func test_registry_loaded_from_config() -> void:
	assert_true(sm._registry.has("match"), "Registry should have 'match'")
	assert_true(sm._registry.has("result"), "Registry should have 'result'")


func test_go_to_nonexistent_scene_stays() -> void:
	sm.go_to("nonexistent")
	# Should log error but not crash
	assert_eq(sm.current_scene_name, "", "Should remain empty")


func test_scene_changing_signal_emitted() -> void:
	watch_signals(sm)
	sm.go_to("match")
	# In test environment without SceneTree, we check signal emission
	assert_signal_emitted(sm, "scene_changing")


func test_switching_state_blocks_reentrant_calls() -> void:
	sm._switching = true
	watch_signals(sm)
	sm.go_to("match")
	assert_signal_not_emitted(sm, "scene_changing")


func test_fallback_registry_when_config_missing() -> void:
	# Create a fresh instance with no file
	var sm2 := load("res://src/core/scene_manager.gd").new()
	add_child_autoqfree(sm2)
	sm2._config_path = "res://nonexistent_path.json"
	sm2._initialize_registry()
	# Should have fallback entries
	assert_true(sm2._registry.has("match"))
	assert_true(sm2._registry.has("result"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_scene_manager.gd -gexit`

Expected: FAIL - file doesn't exist

- [ ] **Step 3: Implement SceneManager**

Create `src/core/scene_manager.gd`:

```gdscript
## Scene Manager - manages top-level scene switching.
## Autoload singleton registered as "SceneManagerGlobal".
## See design/gdd/scene-manager.md for full specification.
extends Node

# --- Signals ---
signal scene_changing(old_name: String, new_name: String)
signal scene_changed(new_name: String)

# --- State ---
var current_scene_name: String = ""
var _switching: bool = false

# --- Internal ---
var _registry: Dictionary = {}  # scene_name -> PackedScene
var _config_path: String = "res://assets/data/scene_registry.json"
var _initial_scene: String = "match"

## Fallback registry used when config file is missing.
const FALLBACK_REGISTRY: Dictionary = {
	"match": "res://scenes/match/Match.tscn",
	"result": "res://scenes/result/Result.tscn",
}


func _ready() -> void:
	_load_game_config()
	_initialize_registry()
	# Note: Do NOT call go_to() here — Godot's main_scene in project.godot
	# already loads the initial scene. SceneManager only handles subsequent
	# scene transitions (e.g. match → result, result → match via Rematch).


func _load_game_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/game_config.json")
	var scene_cfg: Dictionary = cfg.get("scene", {})
	_initial_scene = ConfigLoader.get_or_default(scene_cfg, "initial_scene", "match")
	_config_path = ConfigLoader.get_or_default(scene_cfg, "config_file_path", "res://assets/data/scene_registry.json")


## Load scene registry from config and eager-cache all PackedScenes.
func _initialize_registry() -> void:
	_registry.clear()

	var config := ConfigLoader.load_json(_config_path)
	if config.is_empty():
		push_error("SceneManager: Config file missing or empty, using fallback registry")
		config = FALLBACK_REGISTRY

	for scene_name in config:
		var path: String = config[scene_name]
		if not ResourceLoader.exists(path):
			push_error("SceneManager: Failed to preload scene '%s' at path '%s'" % [scene_name, path])
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("SceneManager: Failed to load PackedScene at '%s'" % path)
			continue
		_registry[scene_name] = packed


## Switch to a named scene.
func go_to(scene_name: String) -> void:
	if _switching:
		push_warning("SceneManager: Scene switch already in progress, ignoring go_to('%s')" % scene_name)
		return

	if not _registry.has(scene_name):
		push_error("SceneManager: Scene not found in registry: '%s'" % scene_name)
		return

	_switching = true
	var old_name := current_scene_name
	scene_changing.emit(old_name, scene_name)

	var packed: PackedScene = _registry[scene_name]
	get_tree().change_scene_to_packed(packed)

	current_scene_name = scene_name
	_switching = false

	# Emit scene_changed after tree settles
	call_deferred("_emit_scene_changed", scene_name)


func _emit_scene_changed(scene_name: String) -> void:
	scene_changed.emit(scene_name)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_scene_manager.gd -gexit`

Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/core/scene_manager.gd tests/unit/test_scene_manager.gd
git commit -m "feat: SceneManager with eager cache, registry, scene switching, fallback"
```

---

### Task 9: ConfigLoader Tests

**Files:**
- Create: `tests/unit/test_config_loader.gd`

- [ ] **Step 1: Write tests for ConfigLoader**

Create `tests/unit/test_config_loader.gd`:

```gdscript
## Unit tests for ConfigLoader utility.
extends GutTest


func test_load_json_valid_file() -> void:
	var data := ConfigLoader.load_json("res://assets/data/game_config.json")
	assert_true(data.has("maze"), "Should have 'maze' key")
	assert_true(data.has("match"), "Should have 'match' key")


func test_load_json_missing_file_returns_empty() -> void:
	var data := ConfigLoader.load_json("res://nonexistent.json")
	assert_eq(data.size(), 0, "Missing file should return empty dict")


func test_get_or_default_existing_key() -> void:
	var config := {"width": 15}
	var value = ConfigLoader.get_or_default(config, "width", 10)
	assert_eq(value, 15)


func test_get_or_default_missing_key() -> void:
	var config := {}
	var value = ConfigLoader.get_or_default(config, "width", 10)
	assert_eq(value, 10)


func test_game_config_has_expected_values() -> void:
	var data := ConfigLoader.load_json("res://assets/data/game_config.json")
	assert_eq(data["maze"]["width"], 15)
	assert_eq(data["maze"]["height"], 15)
	assert_eq(data["match"]["tick_interval"], 0.5)
	assert_eq(data["match"]["countdown_duration"], 3.0)
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_config_loader.gd -gexit`

Expected: All 5 tests PASS

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_config_loader.gd
git commit -m "test: ConfigLoader unit tests for JSON loading and defaults"
```

---

### Task 10: Integration Verification - Run All Tests

**Files:** None (verification only)

- [ ] **Step 1: Run all tests**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/unit/ -gexit`

Expected: All tests PASS (approximately 50+ tests across 4 test files)

- [ ] **Step 2: Verify project launches**

Run: `cd /Users/yao/.superset/worktrees/first-to-the-key/session18 && timeout 10 godot --headless 2>&1 || true`

Expected: No crash errors related to Autoloads or scene loading

- [ ] **Step 3: Final commit with all tests passing**

Only if any fixes were needed:
```bash
git add -A
git commit -m "fix: resolve integration issues from full test run"
```

---

## Verification Checklist

After completing all tasks, verify:

- [ ] `project.godot` exists with 3 Autoloads registered (Enums, MatchStateManager, SceneManagerGlobal)
- [ ] GUT addon installed in `addons/gut/`
- [ ] `MazeData` passes all acceptance criteria from `design/gdd/maze-data-model.md`:
  - Construction with all walls, no markers
  - Wall sync between neighbors
  - Boundary wall protection
  - Marker placement with uniqueness
  - `is_valid()` checks markers, uniqueness, connectivity
  - `finalize()` locks writes
  - `reset()` restores initial state
  - `get_shortest_path()` BFS
- [ ] `MatchStateManager` passes all acceptance criteria from `design/gdd/match-state-manager.md`:
  - FSM transitions: SETUP -> COUNTDOWN -> PLAYING -> FINISHED
  - Invalid transitions rejected
  - Tick emission only in PLAYING
  - `finish_match()` stops ticks, records result
  - `reset()` clears everything
  - Countdown auto-triggers PLAYING
- [ ] `SceneManager` passes all acceptance criteria from `design/gdd/scene-manager.md`:
  - Eager cache from JSON registry
  - Fallback registry on missing config
  - `go_to()` with reentry protection
  - Signals emitted correctly
- [ ] All config values from JSON, no hardcoded gameplay values
- [ ] ~50+ unit tests all passing
