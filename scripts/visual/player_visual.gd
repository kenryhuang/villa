class_name PlayerVisual
extends AnimatedSprite3D

const ATLAS_PATH := "res://assets/characters/player/player_farmer_atlas.png"
const SIDE_WALK_PATH := "res://assets/characters/player/player_farmer_side_walk.png"
const DIRECTIONS := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
const ROW_DIRECTIONS := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
const DEFAULT_DIRECTION := "s"
const GRID_SIZE := Vector2i(8, 8)
const IDLE_FRAME_COUNT := 2
const WALK_FRAME_COUNT := 6
const SIDE_WALK_FRAME_COUNT := 9
const IDLE_FPS := 2.0
const WALK_FPS := 6.0
const SIDE_WALK_FPS := 9.0
const RUN_FPS := 9.0
const SIDE_RUN_FPS := 13.5
const MOVEMENT_THRESHOLD_SQUARED := 0.0025
const PIXEL_SIZE := 0.0068

var _configured := false
var _last_direction := DEFAULT_DIRECTION


func _ready() -> void:
	if not _configured:
		configure(load(ATLAS_PATH) as Texture2D)


func configure(atlas: Texture2D) -> bool:
	_configured = false
	visible = false
	if atlas == null:
		push_error("PlayerVisual requires atlas '%s'." % ATLAS_PATH)
		return false
	if atlas.get_width() <= 0 or atlas.get_height() <= 0:
		push_error("PlayerVisual atlas has no usable pixels.")
		return false
	if atlas.get_width() % GRID_SIZE.x != 0 or atlas.get_height() % GRID_SIZE.y != 0:
		push_error(
			"PlayerVisual atlas must divide into an 8x8 grid; got %dx%d."
			% [atlas.get_width(), atlas.get_height()]
		)
		return false

	sprite_frames = SpriteFrames.new()
	if sprite_frames.has_animation(&"default"):
		sprite_frames.remove_animation(&"default")
	var cell_size := Vector2i(
		atlas.get_width() / GRID_SIZE.x,
		atlas.get_height() / GRID_SIZE.y
	)
	var side_walk := load(SIDE_WALK_PATH) as Texture2D
	if side_walk == null or side_walk.get_size() != Vector2(
		SIDE_WALK_FRAME_COUNT * cell_size.x,
		2 * cell_size.y
	):
		push_error("PlayerVisual requires valid nine-frame side walk '%s'." % SIDE_WALK_PATH)
		return false
	for row in ROW_DIRECTIONS.size():
		var direction := str(ROW_DIRECTIONS[row])
		var idle_name := StringName(idle_animation_name(direction))
		var walk_name := StringName(walk_animation_name(direction))
		sprite_frames.add_animation(idle_name)
		sprite_frames.set_animation_loop(idle_name, true)
		sprite_frames.set_animation_speed(idle_name, IDLE_FPS)
		for column in IDLE_FRAME_COUNT:
			sprite_frames.add_frame(idle_name, _atlas_frame(atlas, cell_size, row, column))
		sprite_frames.add_animation(walk_name)
		sprite_frames.set_animation_loop(walk_name, true)
		sprite_frames.set_animation_speed(
			walk_name,
			SIDE_WALK_FPS if direction in ["e", "w"] else WALK_FPS
		)
		var source_frames: Array[AtlasTexture] = []
		for walk_frame in WALK_FRAME_COUNT:
			source_frames.append(_atlas_frame(atlas, cell_size, row, IDLE_FRAME_COUNT + walk_frame))
		if direction in ["e", "w"]:
			for walk_frame in SIDE_WALK_FRAME_COUNT:
				sprite_frames.add_frame(
					walk_name,
					_atlas_frame(
						side_walk,
						cell_size,
						0 if direction == "e" else 1,
						walk_frame
					)
				)
		else:
			for source_frame in source_frames:
				sprite_frames.add_frame(walk_name, source_frame)

	if not _validate_animations():
		sprite_frames = null
		return false
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaded = false
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	pixel_size = PIXEL_SIZE
	centered = true
	_last_direction = DEFAULT_DIRECTION
	_configured = true
	visible = true
	_play_if_needed(StringName(idle_animation_name(_last_direction)), 1.0)
	return true


func sync_motion(planar_velocity: Vector2, sprinting: bool, on_floor: bool) -> void:
	if not _configured:
		return
	var moving := planar_velocity.length_squared() > MOVEMENT_THRESHOLD_SQUARED
	if moving:
		_last_direction = direction_from_velocity(planar_velocity, _last_direction)
	if not on_floor:
		var jump_animation := StringName(walk_animation_name(_last_direction))
		if animation != jump_animation:
			play(jump_animation)
		pause()
		return
	if moving:
		var movement_animation := StringName(walk_animation_name(_last_direction))
		var is_side_direction := _last_direction in ["e", "w"]
		var base_fps := SIDE_WALK_FPS if is_side_direction else WALK_FPS
		var run_fps := SIDE_RUN_FPS if is_side_direction else RUN_FPS
		var movement_speed := run_fps / base_fps if sprinting else 1.0
		_play_if_needed(movement_animation, movement_speed)
		return
	_play_if_needed(StringName(idle_animation_name(_last_direction)), 1.0)


func get_last_direction() -> String:
	return _last_direction


func is_configured() -> bool:
	return _configured


static func idle_animation_name(direction: String) -> String:
	return "idle_%s" % _valid_direction(direction)


static func walk_animation_name(direction: String) -> String:
	return "walk_%s" % _valid_direction(direction)


static func direction_from_velocity(
	planar_velocity: Vector2,
	previous_direction: String = DEFAULT_DIRECTION
) -> String:
	if planar_velocity.length_squared() <= MOVEMENT_THRESHOLD_SQUARED:
		return _valid_direction(previous_direction)
	var angle := atan2(planar_velocity.x, planar_velocity.y)
	var sector := wrapi(roundi(angle / (PI / 4.0)), 0, 8)
	return ["s", "se", "e", "ne", "n", "nw", "w", "sw"][sector]


static func facing_velocity_from_world(
	world_velocity: Vector3,
	camera_forward: Vector3,
	camera_right: Vector3
) -> Vector2:
	return Vector2(
		world_velocity.dot(camera_right),
		-world_velocity.dot(camera_forward)
	)


static func _valid_direction(direction: String) -> String:
	return direction if DIRECTIONS.has(direction) else DEFAULT_DIRECTION


func _atlas_frame(
	atlas: Texture2D,
	cell_size: Vector2i,
	row: int,
	column: int
) -> AtlasTexture:
	var frame := AtlasTexture.new()
	frame.atlas = atlas
	frame.filter_clip = true
	frame.region = Rect2(
		Vector2(column * cell_size.x, row * cell_size.y),
		Vector2(cell_size)
	)
	return frame


func _validate_animations() -> bool:
	for direction in DIRECTIONS:
		var idle_name := StringName(idle_animation_name(direction))
		var walk_name := StringName(walk_animation_name(direction))
		if not sprite_frames.has_animation(idle_name):
			push_error("PlayerVisual is missing animation '%s'." % idle_name)
			return false
		if sprite_frames.get_frame_count(idle_name) != IDLE_FRAME_COUNT:
			push_error("PlayerVisual animation '%s' must contain two frames." % idle_name)
			return false
		if not sprite_frames.has_animation(walk_name):
			push_error("PlayerVisual is missing animation '%s'." % walk_name)
			return false
		var expected_walk_frames := SIDE_WALK_FRAME_COUNT if direction in ["e", "w"] else WALK_FRAME_COUNT
		if sprite_frames.get_frame_count(walk_name) != expected_walk_frames:
			push_error(
				"PlayerVisual animation '%s' must contain %d frames."
				% [walk_name, expected_walk_frames]
			)
			return false
	return true


func _play_if_needed(next_animation: StringName, next_speed_scale: float) -> void:
	speed_scale = next_speed_scale
	if animation == next_animation and is_playing():
		return
	play(next_animation)
