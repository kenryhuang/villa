class_name BuildingActivityVisual
extends Sprite3D

const FRAME_COUNT := 4
const FRAME_SIZE := Vector2i(512, 512)
const ATLAS_SIZE := Vector2i(FRAME_SIZE.x * FRAME_COUNT, FRAME_SIZE.y)
const FADE_DURATION := 0.15
const FALLBACK_FPS := 4.0

var _configured := false
var _active := false
var _effective_fps := FALLBACK_FPS
var _frame_accumulator := 0.0
var _target_alpha := 0.0
var _fade_alpha := 0.0
var _external_tint := Color.WHITE
var _warning_keys := {}


func configure(
	activity_texture: Texture2D,
	target_size: Vector2,
	ground_anchor_uv: Vector2,
	frames_per_second: float,
	required_resource_path: String = ""
) -> bool:
	_reset_configuration()
	if activity_texture == null:
		if not required_resource_path.is_empty():
			_warn_once(
				"missing:%s" % required_resource_path,
				"Missing building activity atlas '%s'; activity layer disabled."
				% required_resource_path
			)
		return false
	if Vector2i(activity_texture.get_size()) != ATLAS_SIZE:
		_warn_once(
			"invalid_size:%s" % Vector2i(activity_texture.get_size()),
			"Invalid building activity atlas size %s; expected %s."
			% [Vector2i(activity_texture.get_size()), ATLAS_SIZE]
		)
		return false
	if target_size.x <= 0.0 or target_size.y <= 0.0:
		push_warning("Building activity visual requires a positive target size.")
		return false

	texture = activity_texture
	hframes = FRAME_COUNT
	vframes = 1
	frame = 0
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pixel_size = target_size.x / float(FRAME_SIZE.x)
	scale = Vector3(
		1.0,
		target_size.y / (float(FRAME_SIZE.y) * pixel_size),
		1.0
	)
	position = Vector3(
		(0.5 - clampf(ground_anchor_uv.x, 0.0, 1.0)) * target_size.x,
		(clampf(ground_anchor_uv.y, 0.0, 1.0) - 0.5) * target_size.y,
		0.0
	)
	sorting_offset = 0.0
	if frames_per_second <= 0.0:
		_warn_once(
			"invalid_fps",
			"Invalid building activity FPS %.3f; using %.1f FPS."
			% [frames_per_second, FALLBACK_FPS]
		)
	_effective_fps = frames_per_second if frames_per_second > 0.0 else FALLBACK_FPS
	_configured = true
	return true


func set_active(value: bool) -> void:
	_active = value and _configured
	_target_alpha = 1.0 if _active else 0.0
	if _active:
		visible = true


func set_external_tint(value: Color) -> void:
	_external_tint = value
	_apply_composed_modulate()


func get_external_tint() -> Color:
	return _external_tint


func advance_animation(delta: float) -> void:
	if not _configured or delta <= 0.0:
		return
	_fade_alpha = move_toward(_fade_alpha, _target_alpha, delta / FADE_DURATION)
	_apply_composed_modulate()
	if _active:
		_frame_accumulator += delta
		var frame_duration := 1.0 / _effective_fps
		while _frame_accumulator >= frame_duration:
			_frame_accumulator -= frame_duration
			frame = (frame + 1) % FRAME_COUNT
		return
	if is_zero_approx(_fade_alpha):
		frame = 0
		_frame_accumulator = 0.0
		visible = false


func is_configured() -> bool:
	return _configured


func is_active() -> bool:
	return _active


func get_effective_fps() -> float:
	return _effective_fps


func get_warning_count() -> int:
	return _warning_keys.size()


func _reset_configuration() -> void:
	texture = null
	hframes = 1
	vframes = 1
	frame = 0
	_configured = false
	_active = false
	_effective_fps = FALLBACK_FPS
	_frame_accumulator = 0.0
	_target_alpha = 0.0
	_fade_alpha = 0.0
	_external_tint = Color.WHITE
	_apply_composed_modulate()
	visible = false


func _apply_composed_modulate() -> void:
	modulate = Color(
		_external_tint.r,
		_external_tint.g,
		_external_tint.b,
		_external_tint.a * _fade_alpha
	)


func _warn_once(key: String, message: String) -> void:
	if _warning_keys.has(key):
		return
	_warning_keys[key] = true
	push_warning(message)
