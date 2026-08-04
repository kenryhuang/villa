class_name TreeInstance
extends ResourceNode

const TreeFellingCatalogScript = preload("res://scripts/world/tree_felling_catalog.gd")
const TREE_TRUNK_LAYER := 16
const CAMERA_OCCLUDER_LAYER := 32
const OCCLUDED_OPACITY := 0.30
const CLEAR_OPACITY := 1.0
const FADE_RATE := 10.0
const FRAME_FADE_DURATION := 0.20
const FIRST_FRAME_CENTER := 1.0 / 3.0
const SECOND_FRAME_CENTER := 2.0 / 3.0

var occlusion_target := CLEAR_OPACITY
var sprite: Sprite3D
var stump_visual: Sprite3D
var felling_blend_visual: Sprite3D
var _full_sprite_scale := Vector3.ONE
var _full_sprite_position := Vector3.ZERO
var variant := ""
var felling_atlas: Texture2D
var _felling_active := false
var _felling_frame := -1

static func trunk_radius_for(clearance: float) -> float:
	return clampf(clearance * 0.36, 0.24, 0.46)

static func trunk_height_for(tree_height: float) -> float:
	return clampf(tree_height * 0.42, 0.65, 1.10)

static func occluder_dimensions(tree_size: Vector2) -> Vector2:
	var radius := tree_size.x * 0.46
	return Vector2(radius, maxf(tree_size.y * 0.90, radius * 2.0))

static func opacity_step(current: float, target: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-FADE_RATE * delta))

static func vertical_scale_for(texture_size: Vector2, target_size: Vector2) -> float:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 or target_size.x <= 0.0:
		return 1.0
	var pixel_size := target_size.x / texture_size.x
	return target_size.y / (texture_size.y * pixel_size)


static func felling_frame_used_rect(texture: Texture2D, frame: int = 0) -> Rect2i:
	if not TreeFellingCatalogScript.is_valid_atlas(texture) or frame < 0 or frame > 3:
		return Rect2i()
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2i()
	var cell_width := image.get_width() / 4
	return image.get_region(Rect2i(cell_width * frame, 0, cell_width, image.get_height())).get_used_rect()

func configure(
	tree_data: Dictionary,
	texture: Texture2D,
	terrain_height: float,
	loaded_felling_atlas: Texture2D = null
) -> void:
	var tree_width := float(tree_data.width)
	var tree_height := float(tree_data.height)
	variant = str(tree_data.get("variant", ""))
	felling_atlas = loaded_felling_atlas if TreeFellingCatalogScript.is_valid_atlas(loaded_felling_atlas) else null
	interaction_radius = trunk_radius_for(float(tree_data.clearance))
	configure_resource({
		"resource_id": str(tree_data.get(
			"id",
			"tree@%.3f,%.3f" % [float(tree_data.x), float(tree_data.z)]
		)),
		"resource_type": "tree",
		"position": Vector3(float(tree_data.x), terrain_height, float(tree_data.z)),
		"gatherable": (
			TreeFellingCatalogScript.is_variant_choppable(variant)
			and felling_atlas != null
		),
	})
	add_to_group("tree_instance")

	sprite = Sprite3D.new()
	sprite.name = "Sprite3D"
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.pixel_size = tree_width / float(texture.get_width())
	sprite.scale = Vector3(1.0, vertical_scale_for(texture.get_size(), Vector2(tree_width, tree_height)), 1.0)
	_full_sprite_scale = sprite.scale
	sprite.position = Vector3(0.0, tree_height * 0.5, 0.0)
	_full_sprite_position = sprite.position
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)

	stump_visual = Sprite3D.new()
	stump_visual.name = "StumpVisual"
	stump_visual.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stump_visual.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	stump_visual.no_depth_test = false
	if felling_atlas != null:
		var cell_size := Vector2(float(felling_atlas.get_width()) / 4.0, float(felling_atlas.get_height()))
		var standing_bounds := felling_frame_used_rect(felling_atlas)
		var painted_width := maxf(float(standing_bounds.size.x), 1.0)
		var painted_height := maxf(float(standing_bounds.size.y), 1.0)
		stump_visual.pixel_size = tree_width / painted_width
		stump_visual.scale = Vector3(
			1.0,
			tree_height / (painted_height * stump_visual.pixel_size),
			1.0
		)
		stump_visual.position.y = (
			(float(standing_bounds.end.y) - cell_size.y * 0.5)
			* stump_visual.pixel_size
			* stump_visual.scale.y
		)
	stump_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stump_visual.visible = false
	add_child(stump_visual)

	felling_blend_visual = Sprite3D.new()
	felling_blend_visual.name = "FellingBlendVisual"
	felling_blend_visual.billboard = stump_visual.billboard
	felling_blend_visual.alpha_cut = stump_visual.alpha_cut
	felling_blend_visual.no_depth_test = stump_visual.no_depth_test
	felling_blend_visual.pixel_size = stump_visual.pixel_size
	felling_blend_visual.scale = stump_visual.scale
	felling_blend_visual.position = stump_visual.position
	felling_blend_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	felling_blend_visual.render_priority = 1
	felling_blend_visual.visible = false
	add_child(felling_blend_visual)

	var trunk_height := trunk_height_for(tree_height)
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = trunk_radius_for(float(tree_data.clearance))
	trunk_shape.height = trunk_height
	var trunk_body := StaticBody3D.new()
	trunk_body.name = "TrunkBody"
	trunk_body.collision_layer = TREE_TRUNK_LAYER
	trunk_body.collision_mask = 0
	var trunk_collision := CollisionShape3D.new()
	trunk_collision.name = "CollisionShape3D"
	trunk_collision.shape = trunk_shape
	trunk_collision.position.y = trunk_height * 0.5
	trunk_body.add_child(trunk_collision)
	add_child(trunk_body)

	var gather_area := Area3D.new()
	gather_area.name = "GatherArea"
	gather_area.collision_layer = INTERACTION_LAYER
	gather_area.collision_mask = 0
	var gather_collision := CollisionShape3D.new()
	gather_collision.name = "CollisionShape3D"
	gather_collision.shape = trunk_shape
	gather_collision.position.y = trunk_height * 0.5
	gather_area.add_child(gather_collision)
	add_child(gather_area)

	var occluder_size := occluder_dimensions(Vector2(tree_width, tree_height))
	var occluder_shape := CapsuleShape3D.new()
	occluder_shape.radius = occluder_size.x
	occluder_shape.height = occluder_size.y
	var camera_occluder := Area3D.new()
	camera_occluder.name = "CameraOccluder"
	camera_occluder.collision_layer = CAMERA_OCCLUDER_LAYER
	camera_occluder.collision_mask = 0
	camera_occluder.monitoring = false
	var occluder_collision := CollisionShape3D.new()
	occluder_collision.name = "CollisionShape3D"
	occluder_collision.shape = occluder_shape
	occluder_collision.position.y = tree_height * 0.5
	camera_occluder.add_child(occluder_collision)
	add_child(camera_occluder)
	_set_gather_active(gathering_enabled and remaining_units > 0)
	_apply_visual_stage()


func is_chop_eligible() -> bool:
	return (
		gathering_enabled
		and remaining_units > 0
		and TreeFellingCatalogScript.is_variant_choppable(variant)
		and felling_atlas != null
	)


func get_gather_duration() -> float:
	return TreeFellingCatalogScript.GATHER_DURATION


func preview_reward(tool_id: String) -> Dictionary:
	return {item_id: remaining_units} if can_gather(tool_id) else {}


func commit_gather(tool_id: String, total_day: int = 0) -> Dictionary:
	if total_day < 0:
		return {}
	var reward := preview_reward(tool_id)
	if reward.is_empty():
		return {}
	remaining_units = 0
	_respawn_day = total_day + respawn_days
	_update_visual_stage()
	_set_gather_active(false)
	return reward


func begin_felling(_fall_direction: int) -> bool:
	if not is_chop_eligible() or remaining_units <= 0:
		return false
	_felling_active = true
	stump_visual.flip_h = false
	felling_blend_visual.flip_h = false
	set_felling_progress(0.0)
	return true


func set_felling_progress(progress: float) -> void:
	if not _felling_active:
		return
	var value := clampf(progress, 0.0, 1.0)
	var fade_half_progress := FRAME_FADE_DURATION / TreeFellingCatalogScript.GATHER_DURATION * 0.5
	if absf(value - FIRST_FRAME_CENTER) <= fade_half_progress:
		_show_felling_blend(
			0,
			1,
			inverse_lerp(
				FIRST_FRAME_CENTER - fade_half_progress,
				FIRST_FRAME_CENTER + fade_half_progress,
				value
			)
		)
	elif absf(value - SECOND_FRAME_CENTER) <= fade_half_progress:
		_show_felling_blend(
			1,
			2,
			inverse_lerp(
				SECOND_FRAME_CENTER - fade_half_progress,
				SECOND_FRAME_CENTER + fade_half_progress,
				value
			)
		)
	else:
		_show_felling_frame(0 if value < FIRST_FRAME_CENTER else (1 if value < SECOND_FRAME_CENTER else 2))


func cancel_felling() -> void:
	_felling_active = false
	_felling_frame = -1
	if stump_visual != null:
		stump_visual.visible = false
		stump_visual.flip_h = false
		_set_sprite_alpha(stump_visual, 1.0)
	if felling_blend_visual != null:
		felling_blend_visual.visible = false
		felling_blend_visual.flip_h = false
		_set_sprite_alpha(felling_blend_visual, 0.0)
	if sprite != null:
		sprite.visible = remaining_units > 0
		_sprite_reset()


func get_felling_frame() -> int:
	return _felling_frame


func _show_felling_frame(frame: int) -> void:
	if stump_visual == null or felling_atlas == null or frame < 0 or frame > 3:
		return
	_set_felling_texture(stump_visual, frame)
	_set_sprite_alpha(stump_visual, 1.0)
	if felling_blend_visual != null:
		felling_blend_visual.visible = false
		_set_sprite_alpha(felling_blend_visual, 0.0)
	stump_visual.visible = true
	_felling_frame = frame
	if sprite != null:
		sprite.visible = false


func _show_felling_blend(from_frame: int, to_frame: int, weight: float) -> void:
	if stump_visual == null or felling_blend_visual == null or felling_atlas == null:
		return
	var blend := clampf(weight, 0.0, 1.0)
	_set_felling_texture(stump_visual, from_frame)
	_set_felling_texture(felling_blend_visual, to_frame)
	_set_sprite_alpha(stump_visual, 1.0 - blend)
	_set_sprite_alpha(felling_blend_visual, blend)
	stump_visual.visible = true
	felling_blend_visual.visible = true
	_felling_frame = to_frame if blend >= 0.5 else from_frame
	if sprite != null:
		sprite.visible = false


func _set_felling_texture(target_sprite: Sprite3D, frame: int) -> void:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = felling_atlas
	var cell_width := float(felling_atlas.get_width()) / 4.0
	atlas_texture.region = Rect2(cell_width * float(frame), 0.0, cell_width, felling_atlas.get_height())
	target_sprite.texture = atlas_texture


func _set_sprite_alpha(target_sprite: Sprite3D, alpha: float) -> void:
	var color := target_sprite.modulate
	color.a = clampf(alpha, 0.0, 1.0)
	target_sprite.modulate = color


func _sprite_reset() -> void:
	if sprite == null:
		return
	sprite.scale = _full_sprite_scale
	sprite.position = _full_sprite_position
	var color := sprite.modulate
	color.r = 1.0
	color.g = 1.0
	sprite.modulate = color


func _set_gather_active(active: bool) -> void:
	super(active)
	if sprite != null:
		sprite.visible = true
	var trunk_body := get_node_or_null("TrunkBody") as CollisionObject3D
	if trunk_body != null:
		trunk_body.collision_layer = TREE_TRUNK_LAYER if (not gathering_enabled or active) else 0
	var gather_area := get_node_or_null("GatherArea") as CollisionObject3D
	if gather_area != null:
		gather_area.collision_layer = INTERACTION_LAYER if remaining_units > 0 else 0
	_apply_visual_stage()


func _update_visual_stage() -> void:
	visual_stage = _stage_for_units(remaining_units)
	_apply_visual_stage()


func _stage_for_units(units: int) -> int:
	if units <= 0:
		return 3
	if units >= 4:
		return 0
	return 1 if units >= 2 else 2


func _apply_visual_stage() -> void:
	if visual_stage == 3:
		_felling_active = false
		_show_felling_frame(3)
		return
	if not _felling_active:
		_felling_frame = -1
		if stump_visual != null:
			stump_visual.visible = false
		if sprite != null:
			sprite.visible = true
			_sprite_reset()

func set_camera_occluded(value: bool) -> void:
	occlusion_target = OCCLUDED_OPACITY if value else CLEAR_OPACITY

func _process(delta: float) -> void:
	if sprite == null:
		return
	var color := sprite.modulate
	color.a = opacity_step(color.a, occlusion_target, delta)
	sprite.modulate = color
