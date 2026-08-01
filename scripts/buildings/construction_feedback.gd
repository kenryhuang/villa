class_name ConstructionFeedback
extends Node3D

const HAMMER_TEXTURE_PATH := "res://assets/buildings/construction/construction_hammer_painted.png"
const HAMMER_SHADER_PATH := "res://assets/buildings/construction/construction_hammer.gdshader"
const PROGRESS_SHADER_PATH := "res://assets/buildings/construction/construction_progress.gdshader"
const STRIKE_PERIOD := 0.6
const RAISED_ANGLE := deg_to_rad(25.0)
const IMPACT_ANGLE := deg_to_rad(105.0)
const FOUNDATION_CONTACT_X_RATIO := 0.34
const FOUNDATION_CONTACT_Y_RATIO := 0.10
const HAMMER_HEAD_LEVER_RATIO := 0.72
const PROGRESS_TEXTURE_SIZE := 128

var _phase := 0.0
var _hammer_ready := false
var _progress_ready := false
var _asset_warnings := {}


static func strike_angle_for_phase(phase: float) -> float:
	var normalized := clampf(phase, 0.0, 1.0)
	if normalized <= 0.25:
		return RAISED_ANGLE
	if normalized <= 0.48:
		var fall_t := inverse_lerp(0.25, 0.48, normalized)
		return lerpf(RAISED_ANGLE, IMPACT_ANGLE, fall_t * fall_t * fall_t)
	if normalized <= 0.55:
		return IMPACT_ANGLE
	var rebound_t := inverse_lerp(0.55, 1.0, normalized)
	var eased := 1.0 - pow(1.0 - rebound_t, 3.0)
	return lerpf(IMPACT_ANGLE, RAISED_ANGLE, eased)


static func hammer_screen_offset_for(visual_size: Vector2, hammer_height: float) -> Vector2:
	var lever := hammer_height * HAMMER_HEAD_LEVER_RATIO
	var impact_head_from_pivot := Vector2(
		-sin(IMPACT_ANGLE) * lever,
		cos(IMPACT_ANGLE) * lever
	)
	var target_head := Vector2(
		visual_size.x * FOUNDATION_CONTACT_X_RATIO,
		visual_size.y * FOUNDATION_CONTACT_Y_RATIO
	)
	return target_head - impact_head_from_pivot


func configure(visual_size: Vector2) -> void:
	_ensure_nodes()
	var pivot := get_node("HammerPivot") as Node3D
	var hammer_sprite := pivot.get_node("HammerSprite") as Sprite3D
	var progress_sprite := get_node("Progress") as Sprite3D

	var hammer_height := clampf(
		minf(visual_size.x, visual_size.y) * 0.32,
		0.38,
		0.72
	)
	pivot.position = Vector3.ZERO
	pivot.rotation.z = strike_angle_for_phase(_phase)
	var hammer_texture := _load_texture(HAMMER_TEXTURE_PATH)
	var hammer_shader := _load_shader(HAMMER_SHADER_PATH)
	hammer_sprite.texture = hammer_texture
	_hammer_ready = hammer_texture != null and hammer_shader != null
	if _hammer_ready:
		hammer_sprite.pixel_size = hammer_height / float(hammer_texture.get_height())
		hammer_sprite.position = Vector3.ZERO
		var screen_offset := hammer_screen_offset_for(visual_size, hammer_height)
		hammer_sprite.extra_cull_margin = screen_offset.length() + hammer_height
		var hammer_material := ShaderMaterial.new()
		hammer_material.shader = hammer_shader
		hammer_material.render_priority = 10
		hammer_material.set_shader_parameter("albedo_texture", hammer_texture)
		hammer_material.set_shader_parameter("sprite_height", hammer_height)
		hammer_material.set_shader_parameter("pivot_uv", _painted_hammer_pivot_uv(hammer_texture))
		hammer_material.set_shader_parameter("screen_offset", screen_offset)
		hammer_material.set_shader_parameter("strike_angle", pivot.rotation.z)
		hammer_sprite.material_override = hammer_material
	else:
		if hammer_texture == null:
			_warn_missing(HAMMER_TEXTURE_PATH)
		if hammer_shader == null:
			_warn_missing(HAMMER_SHADER_PATH)

	progress_sprite.position = Vector3(
		visual_size.x * 0.52,
		visual_size.y * 1.03,
		0.18
	)
	var disk_size := clampf(
		minf(visual_size.x, visual_size.y) * 0.22,
		0.28,
		0.48
	)
	progress_sprite.pixel_size = disk_size / float(PROGRESS_TEXTURE_SIZE)
	_configure_progress_material(progress_sprite)
	_apply_child_visibility()


func update_state(
	progress: float,
	preview: bool,
	complete: bool,
	active: bool
) -> void:
	_ensure_nodes()
	var progress_sprite := get_node("Progress") as Sprite3D
	var material := progress_sprite.material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))
	visible = active and not preview and not complete
	_apply_child_visibility()


func advance_animation(delta: float) -> void:
	var pivot := get_node("HammerPivot") as Node3D
	if delta <= 0.0 or not visible or not _hammer_ready or not pivot.visible:
		return
	_phase = fmod(_phase + delta / STRIKE_PERIOD, 1.0)
	pivot.rotation.z = strike_angle_for_phase(_phase)
	var hammer_sprite := pivot.get_node("HammerSprite") as Sprite3D
	var material := hammer_sprite.material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("strike_angle", pivot.rotation.z)


func _ensure_nodes() -> void:
	var pivot := get_node_or_null("HammerPivot") as Node3D
	if pivot == null:
		pivot = Node3D.new()
		pivot.name = "HammerPivot"
		add_child(pivot)
	var hammer_sprite := pivot.get_node_or_null("HammerSprite") as Sprite3D
	if hammer_sprite == null:
		hammer_sprite = Sprite3D.new()
		hammer_sprite.name = "HammerSprite"
		pivot.add_child(hammer_sprite)
		_configure_billboard(hammer_sprite, 0.5)
	var progress_sprite := get_node_or_null("Progress") as Sprite3D
	if progress_sprite == null:
		progress_sprite = Sprite3D.new()
		progress_sprite.name = "Progress"
		add_child(progress_sprite)
		_configure_billboard(progress_sprite, 0.6)


func _configure_billboard(sprite: Sprite3D, sorting_offset: float) -> void:
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.sorting_offset = sorting_offset


func _configure_progress_material(progress_sprite: Sprite3D) -> void:
	var shader := _load_shader(PROGRESS_SHADER_PATH)
	if shader == null:
		_progress_ready = false
		_warn_missing(PROGRESS_SHADER_PATH)
		return
	var image := Image.create(
		PROGRESS_TEXTURE_SIZE,
		PROGRESS_TEXTURE_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color.WHITE)
	progress_sprite.texture = ImageTexture.create_from_image(image)
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("progress", 0.0)
	progress_sprite.material_override = material
	_progress_ready = true


func _apply_child_visibility() -> void:
	var pivot := get_node_or_null("HammerPivot") as Node3D
	if pivot != null:
		pivot.visible = visible and _hammer_ready
	var progress_sprite := get_node_or_null("Progress") as Sprite3D
	if progress_sprite != null:
		progress_sprite.visible = visible and _progress_ready


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _load_shader(path: String) -> Shader:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Shader


func _painted_hammer_pivot_uv(texture: Texture2D) -> Vector2:
	var image := texture.get_image()
	if image == null:
		return Vector2(0.5, 1.0)
	var painted_bounds := image.get_used_rect()
	if painted_bounds.size == Vector2i.ZERO:
		return Vector2(0.5, 1.0)
	var last_painted_row := painted_bounds.end.y - 1
	return Vector2(
		0.5,
		float(last_painted_row) / float(maxi(texture.get_height() - 1, 1))
	)


func _warn_missing(path: String) -> void:
	if _asset_warnings.has(path):
		return
	_asset_warnings[path] = true
	push_warning("Missing construction feedback resource '%s'." % path)
