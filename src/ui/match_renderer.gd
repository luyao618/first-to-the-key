## Match Renderer - visualizes maze, markers, and agents.
## Instantiated in the Match scene's center column SubViewport.
## See design/gdd/match-renderer.md for full specification.
class_name MatchRenderer
extends Node2D

# --- Configuration ---
var _cell_size: int = 32
var _margin_ratio: float = 0.1
var _move_anim_ratio: float = 0.6
var _bump_anim_duration: float = 0.2
var _bump_offset: float = 4.0
var _float_anim_amplitude: float = 3.0
var _float_anim_period: float = 2.0
var _agent_a_color: Color = Color("#4488FF")
var _agent_b_color: Color = Color("#FF4444")
var _agent_overlap_offset: float = 3.0
var _render_mode: int = Enums.RenderMode.GOD_VIEW

# --- Internal Nodes ---
var _maze_layer: Node2D = null
var _marker_layer: Node2D = null
var _agent_layer: Node2D = null
var _maze: RefCounted = null

# --- Sprite References ---
var _agent_sprites: Dictionary = {}  # agent_id -> Sprite2D
var _key_sprites: Dictionary = {}    # MarkerType -> Sprite2D
var _chest_sprite: Sprite2D = null
var _agent_tweens: Dictionary = {}   # agent_id -> Tween (current movement tween)

# --- Art Asset Textures ---
var _tex_agent_a: Texture2D = null
var _tex_agent_b: Texture2D = null
var _tex_key_brass: Texture2D = null
var _tex_key_jade: Texture2D = null
var _tex_key_crystal: Texture2D = null
var _tex_chest: Texture2D = null
var _tex_floor: Texture2D = null
var _tex_wall: Texture2D = null


func _ready() -> void:
	_load_config()
	_load_art_assets()


func _load_config() -> void:
	var cfg := ConfigLoader.load_json("res://assets/data/ui_config.json")
	var rcfg: Dictionary = cfg.get("renderer", {})
	_cell_size = ConfigLoader.get_or_default(rcfg, "cell_size", 32)
	_margin_ratio = ConfigLoader.get_or_default(rcfg, "margin_ratio", 0.1)
	_move_anim_ratio = ConfigLoader.get_or_default(rcfg, "move_anim_ratio", 0.6)
	_bump_anim_duration = ConfigLoader.get_or_default(rcfg, "bump_anim_duration", 0.2)
	_bump_offset = ConfigLoader.get_or_default(rcfg, "bump_offset", 4.0)
	_float_anim_amplitude = ConfigLoader.get_or_default(rcfg, "float_anim_amplitude", 3.0)
	_float_anim_period = ConfigLoader.get_or_default(rcfg, "float_anim_period", 2.0)
	_agent_a_color = Color(ConfigLoader.get_or_default(rcfg, "agent_a_color", "#4488FF"))
	_agent_b_color = Color(ConfigLoader.get_or_default(rcfg, "agent_b_color", "#FF4444"))
	_agent_overlap_offset = ConfigLoader.get_or_default(rcfg, "agent_overlap_offset", 3.0)

	# Also read cell_size from game_config for consistency
	var game_cfg := ConfigLoader.load_json("res://assets/data/game_config.json")
	var maze_cfg: Dictionary = game_cfg.get("maze", {})
	_cell_size = ConfigLoader.get_or_default(maze_cfg, "cell_size", _cell_size)


## Load art asset textures from disk. Falls back to placeholder if missing.
func _load_art_assets() -> void:
	_tex_agent_a = _try_load_texture("res://assets/art/sprites/agent_a.png")
	_tex_agent_b = _try_load_texture("res://assets/art/sprites/agent_b.png")
	_tex_key_brass = _try_load_texture("res://assets/art/sprites/items/key_brass.png")
	_tex_key_jade = _try_load_texture("res://assets/art/sprites/items/key_jade.png")
	_tex_key_crystal = _try_load_texture("res://assets/art/sprites/items/key_crystal.png")
	_tex_chest = _try_load_texture("res://assets/art/sprites/items/chest.png")
	_tex_floor = _try_load_texture("res://assets/art/tiles/floor.png")
	_tex_wall = _try_load_texture("res://assets/art/tiles/wall.png")


## Try to load a texture from the given path. Returns null if not found.
func _try_load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("MatchRenderer: Art asset not found: %s — using placeholder" % path)
		return null
	return load(path) as Texture2D


## Build all render layers from MazeData.
func initialize(maze: RefCounted) -> void:
	cleanup()
	_maze = maze

	# Dynamically compute cell_size so the maze fills the viewport
	_compute_cell_size()

	# Create layer containers
	_maze_layer = Node2D.new()
	_maze_layer.name = "MazeLayer"
	_maze_layer.z_index = 0
	add_child(_maze_layer)

	_marker_layer = Node2D.new()
	_marker_layer.name = "MarkerLayer"
	_marker_layer.z_index = 1
	add_child(_marker_layer)

	_agent_layer = Node2D.new()
	_agent_layer.name = "AgentLayer"
	_agent_layer.z_index = 2
	add_child(_agent_layer)

	_build_maze_grid()
	_build_markers()
	_build_agents()


## Compute cell_size so the maze fills the SubViewport with a small margin.
func _compute_cell_size() -> void:
	if _maze == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size: Vector2i = vp.size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return
	# Leave a margin around the edges
	var usable_w: float = vp_size.x * (1.0 - _margin_ratio * 2.0)
	var usable_h: float = vp_size.y * (1.0 - _margin_ratio * 2.0)
	var cell_w := int(usable_w / _maze.width)
	var cell_h := int(usable_h / _maze.height)
	_cell_size = mini(cell_w, cell_h)
	if _cell_size < 8:
		_cell_size = 8  # Floor to avoid degenerate rendering

	# Center the maze in the viewport
	var maze_w: float = _maze.width * _cell_size
	var maze_h: float = _maze.height * _cell_size
	position = Vector2(
		(vp_size.x - maze_w) / 2.0,
		(vp_size.y - maze_h) / 2.0
	)


## Draw maze walls and floors using simple draw calls.
## MVP: Uses _draw() on child nodes instead of TileMap for simplicity.
func _build_maze_grid() -> void:
	var grid_drawer := _MazeGridDrawer.new()
	grid_drawer.maze = _maze
	grid_drawer.cell_size = _cell_size
	grid_drawer.floor_texture = _tex_floor
	grid_drawer.wall_texture = _tex_wall
	_maze_layer.add_child(grid_drawer)


## Place marker sprites (keys + chest).
func _build_markers() -> void:
	# Keys
	for key_type in Enums.KEY_SEQUENCE:
		var pos: Vector2i = _maze.get_marker_position(key_type)
		if pos == Vector2i(-1, -1):
			push_warning("MatchRenderer: Missing key marker %d" % key_type)
			continue

		var sprite := Sprite2D.new()
		sprite.position = grid_to_pixel(pos)

		var art_tex: Texture2D = _get_key_texture(key_type)
		if art_tex != null:
			sprite.texture = art_tex
			_fit_sprite_to_cell(sprite, _cell_size * 0.7)
		else:
			sprite.texture = _create_placeholder_texture(_get_key_color(key_type), 16)
		sprite.z_index = 1

		# Hardcoded initial visibility: only Brass visible
		sprite.visible = (key_type == Enums.MarkerType.KEY_BRASS)

		_marker_layer.add_child(sprite)
		_key_sprites[key_type] = sprite

	# Chest
	var chest_pos: Vector2i = _maze.get_marker_position(Enums.MarkerType.CHEST)
	if chest_pos != Vector2i(-1, -1):
		_chest_sprite = Sprite2D.new()
		_chest_sprite.position = grid_to_pixel(chest_pos)

		if _tex_chest != null:
			_chest_sprite.texture = _tex_chest
			_fit_sprite_to_cell(_chest_sprite, _cell_size * 0.85)
		else:
			_chest_sprite.texture = _create_placeholder_texture(Color(0.8, 0.7, 0.2), 24)
		_chest_sprite.visible = false  # Chest starts inactive
		_chest_sprite.z_index = 1
		_marker_layer.add_child(_chest_sprite)


## Place agent sprites at spawn positions.
func _build_agents() -> void:
	for i in range(2):
		var spawn_marker: int = Enums.MarkerType.SPAWN_A if i == 0 else Enums.MarkerType.SPAWN_B
		var spawn_pos: Vector2i = _maze.get_marker_position(spawn_marker)
		var color: Color = _agent_a_color if i == 0 else _agent_b_color

		var sprite := Sprite2D.new()
		sprite.position = grid_to_pixel(spawn_pos)

		var art_tex: Texture2D = _tex_agent_a if i == 0 else _tex_agent_b
		if art_tex != null:
			sprite.texture = art_tex
			_fit_sprite_to_cell(sprite, _cell_size * 0.9)
		else:
			sprite.texture = _create_placeholder_texture(color, 24)
		sprite.z_index = 2
		_agent_layer.add_child(sprite)
		_agent_sprites[i] = sprite


# --- Coordinate Conversion ---

func grid_to_pixel(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * _cell_size + _cell_size / 2.0,
		grid_pos.y * _cell_size + _cell_size / 2.0
	)


# --- Animation Handlers ---

## Animate agent movement from old to new grid position.
func animate_move(mover_id: int, old_pos: Vector2i, new_pos: Vector2i, duration: float) -> void:
	if not _agent_sprites.has(mover_id):
		return

	var sprite: Sprite2D = _agent_sprites[mover_id]

	# Kill existing tween
	if _agent_tweens.has(mover_id) and _agent_tweens[mover_id] != null:
		_agent_tweens[mover_id].kill()
	# Snap to target of previous animation
	sprite.position = grid_to_pixel(old_pos)

	var target := grid_to_pixel(new_pos)
	var tween := create_tween()
	tween.tween_property(sprite, "position", target, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_agent_tweens[mover_id] = tween


## Animate agent bump (wall collision).
func animate_bump(mover_id: int, pos: Vector2i, direction: int) -> void:
	if not _agent_sprites.has(mover_id):
		return

	var sprite: Sprite2D = _agent_sprites[mover_id]
	var base := grid_to_pixel(pos)
	sprite.position = base

	var offset := Vector2.ZERO
	match direction:
		Enums.Direction.NORTH: offset = Vector2(0, -_bump_offset)
		Enums.Direction.EAST: offset = Vector2(_bump_offset, 0)
		Enums.Direction.SOUTH: offset = Vector2(0, _bump_offset)
		Enums.Direction.WEST: offset = Vector2(-_bump_offset, 0)

	if _agent_tweens.has(mover_id) and _agent_tweens[mover_id] != null:
		_agent_tweens[mover_id].kill()

	var tween := create_tween()
	tween.tween_property(sprite, "position", base + offset, _bump_anim_duration * 0.4)
	tween.tween_property(sprite, "position", base, _bump_anim_duration * 0.6).set_ease(Tween.EASE_OUT)
	_agent_tweens[mover_id] = tween


## Show a key sprite with fade-in animation.
func show_key(key_type: int) -> void:
	if not _key_sprites.has(key_type):
		return
	var sprite: Sprite2D = _key_sprites[key_type]
	sprite.visible = true
	sprite.modulate.a = 0.0
	# Remember the fitted scale so we animate TO it, not to (1,1)
	var target_scale: Vector2 = sprite.scale
	sprite.scale = target_scale * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.5)
	tween.tween_property(sprite, "scale", target_scale, 0.5).set_ease(Tween.EASE_OUT)


## Handle key collected - adjust opacity.
func on_key_collected(key_type: int, both_collected: bool) -> void:
	if not _key_sprites.has(key_type):
		return
	var sprite: Sprite2D = _key_sprites[key_type]
	if both_collected:
		sprite.visible = false
	else:
		sprite.modulate.a = 0.4


## Show chest sprite with fade-in.
func show_chest() -> void:
	if _chest_sprite == null:
		return
	_chest_sprite.visible = true
	_chest_sprite.modulate.a = 0.0
	# Remember the fitted scale so we animate TO it, not to (1,1)
	var target_scale: Vector2 = _chest_sprite.scale
	_chest_sprite.scale = target_scale * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_chest_sprite, "modulate:a", 1.0, 0.5)
	tween.tween_property(_chest_sprite, "scale", target_scale, 0.5).set_ease(Tween.EASE_OUT)


# --- Cleanup ---

func cleanup() -> void:
	for child in get_children():
		child.queue_free()
	_agent_sprites.clear()
	_key_sprites.clear()
	_chest_sprite = null
	_agent_tweens.clear()
	_maze_layer = null
	_marker_layer = null
	_agent_layer = null


# --- Helpers ---

func _get_key_color(key_type: int) -> Color:
	match key_type:
		Enums.MarkerType.KEY_BRASS: return Color(0.8, 0.6, 0.2)   # Copper/brass
		Enums.MarkerType.KEY_JADE: return Color(0.2, 0.8, 0.4)    # Green
		Enums.MarkerType.KEY_CRYSTAL: return Color(0.3, 0.6, 1.0) # Ice blue
	return Color.WHITE


## Get the art texture for a key type. Returns null if not loaded.
func _get_key_texture(key_type: int) -> Texture2D:
	match key_type:
		Enums.MarkerType.KEY_BRASS: return _tex_key_brass
		Enums.MarkerType.KEY_JADE: return _tex_key_jade
		Enums.MarkerType.KEY_CRYSTAL: return _tex_key_crystal
	return null


## Scale a sprite uniformly so its longest side fits target_size pixels.
func _fit_sprite_to_cell(sprite: Sprite2D, target_size: float) -> void:
	if sprite.texture == null:
		return
	var tex_size := sprite.texture.get_size()
	var max_dim := maxf(tex_size.x, tex_size.y)
	if max_dim <= 0.0:
		return
	var s := target_size / max_dim
	sprite.scale = Vector2(s, s)


## Create a simple colored square texture as placeholder.
func _create_placeholder_texture(color: Color, size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Internal class to draw the maze grid.
class _MazeGridDrawer extends Node2D:
	var maze: RefCounted
	var cell_size: int = 32
	var floor_texture: Texture2D = null
	var wall_texture: Texture2D = null

	func _draw() -> void:
		if maze == null:
			return
		var floor_color := Color(0.9, 0.9, 0.85)
		var wall_color := Color(0.2, 0.2, 0.25)
		var wall_width := 2.0

		# Draw floor tiles
		for y in range(maze.height):
			for x in range(maze.width):
				var rect := Rect2(x * cell_size, y * cell_size, cell_size, cell_size)
				if floor_texture != null:
					draw_texture_rect(floor_texture, rect, false)
				else:
					draw_rect(rect, floor_color)

		# Draw walls
		for y in range(maze.height):
			for x in range(maze.width):
				var ox: float = x * cell_size
				var oy: float = y * cell_size

				if maze.has_wall(x, y, Enums.Direction.NORTH):
					if wall_texture != null:
						_draw_wall_segment(ox, oy, ox + cell_size, oy, wall_width)
					else:
						draw_line(Vector2(ox, oy), Vector2(ox + cell_size, oy), wall_color, wall_width)
				if maze.has_wall(x, y, Enums.Direction.EAST):
					if wall_texture != null:
						_draw_wall_segment(ox + cell_size, oy, ox + cell_size, oy + cell_size, wall_width)
					else:
						draw_line(Vector2(ox + cell_size, oy), Vector2(ox + cell_size, oy + cell_size), wall_color, wall_width)
				if maze.has_wall(x, y, Enums.Direction.SOUTH):
					if wall_texture != null:
						_draw_wall_segment(ox, oy + cell_size, ox + cell_size, oy + cell_size, wall_width)
					else:
						draw_line(Vector2(ox, oy + cell_size), Vector2(ox + cell_size, oy + cell_size), wall_color, wall_width)
				if maze.has_wall(x, y, Enums.Direction.WEST):
					if wall_texture != null:
						_draw_wall_segment(ox, oy, ox, oy + cell_size, wall_width)
					else:
						draw_line(Vector2(ox, oy), Vector2(ox, oy + cell_size), wall_color, wall_width)


	## Draw a wall segment as a thin textured rect along a line.
	func _draw_wall_segment(x0: float, y0: float, x1: float, y1: float, thickness: float) -> void:
		var wall_thick := thickness * 2.0
		if absf(y0 - y1) < 0.01:
			# Horizontal wall
			var rect := Rect2(x0, y0 - wall_thick / 2.0, x1 - x0, wall_thick)
			draw_texture_rect(wall_texture, rect, false)
		else:
			# Vertical wall
			var rect := Rect2(x0 - wall_thick / 2.0, y0, wall_thick, y1 - y0)
			draw_texture_rect(wall_texture, rect, false)
