## Unit tests for MatchRenderer.
extends GutTest

const MatchRendererClass := preload("res://src/ui/match_renderer.gd")
const MazeData := preload("res://src/core/maze_data.gd")
const MazeGenerator := preload("res://src/core/maze_generator.gd")

var renderer: Node2D
var maze: RefCounted


func before_each() -> void:
	var gen := MazeGenerator.new()
	add_child_autoqfree(gen)
	gen._max_fairness_delta = 100
	gen._max_generation_retries = 200
	gen._config_loaded = true
	maze = gen.generate(5, 5)
	assert_not_null(maze)

	renderer = MatchRendererClass.new()
	add_child_autoqfree(renderer)


func test_initialize_creates_maze_layer() -> void:
	renderer.initialize(maze)
	assert_not_null(renderer._maze_layer, "Maze layer should exist")


func test_initialize_creates_marker_layer() -> void:
	renderer.initialize(maze)
	assert_not_null(renderer._marker_layer, "Marker layer should exist")


func test_initialize_creates_agent_layer() -> void:
	renderer.initialize(maze)
	assert_not_null(renderer._agent_layer, "Agent layer should exist")


func test_grid_to_pixel_conversion() -> void:
	renderer.initialize(maze)
	var pixel: Vector2 = renderer.grid_to_pixel(Vector2i(0, 0))
	var expected := Vector2(renderer._cell_size / 2.0, renderer._cell_size / 2.0)
	assert_eq(pixel, expected)


func test_grid_to_pixel_offset() -> void:
	renderer.initialize(maze)
	var pixel: Vector2 = renderer.grid_to_pixel(Vector2i(2, 3))
	var cs: float = renderer._cell_size
	var expected := Vector2(2 * cs + cs / 2.0, 3 * cs + cs / 2.0)
	assert_eq(pixel, expected)


func test_agent_sprites_created() -> void:
	renderer.initialize(maze)
	assert_eq(renderer._agent_sprites.size(), 2, "Should have 2 agent sprites")


func test_agent_initial_positions() -> void:
	renderer.initialize(maze)
	var spawn_a: Vector2i = maze.get_marker_position(Enums.MarkerType.SPAWN_A)
	var sprite_a: Sprite2D = renderer._agent_sprites[0]
	var expected_pos: Vector2 = renderer.grid_to_pixel(spawn_a)
	assert_eq(sprite_a.position, expected_pos)


func test_key_sprites_created() -> void:
	renderer.initialize(maze)
	assert_eq(renderer._key_sprites.size(), 3, "Should have 3 key sprites")


func test_brass_key_visible_initially() -> void:
	renderer.initialize(maze)
	var brass_sprite: Sprite2D = renderer._key_sprites[Enums.MarkerType.KEY_BRASS]
	assert_true(brass_sprite.visible, "Brass key should be visible initially")


func test_jade_key_hidden_initially() -> void:
	renderer.initialize(maze)
	var jade_sprite: Sprite2D = renderer._key_sprites[Enums.MarkerType.KEY_JADE]
	assert_false(jade_sprite.visible, "Jade key should be hidden initially")


func test_crystal_key_hidden_initially() -> void:
	renderer.initialize(maze)
	var crystal_sprite: Sprite2D = renderer._key_sprites[Enums.MarkerType.KEY_CRYSTAL]
	assert_false(crystal_sprite.visible, "Crystal key should be hidden initially")


func test_chest_sprite_hidden_initially() -> void:
	renderer.initialize(maze)
	if renderer._chest_sprite != null:
		assert_false(renderer._chest_sprite.visible, "Chest should be hidden initially")


func test_cleanup_removes_all() -> void:
	renderer.initialize(maze)
	renderer.cleanup()
	assert_eq(renderer._agent_sprites.size(), 0)
	assert_eq(renderer._key_sprites.size(), 0)
	assert_null(renderer._chest_sprite)
