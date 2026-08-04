class_name TreeInstance
extends ResourceNode

const TreeFellingCatalogScript = preload("res://scripts/world/tree_felling_catalog.gd")
const TREE_TRUNK_LAYER := 16
const CAMERA_OCCLUDER_LAYER := 32
const OCCLUDED_OPACITY := 0.30
const CLEAR_OPACITY := 1.0
const FADE_RATE := 10.0

var occlusion_target := CLEAR_OPACITY
var sprite: Sprite3D
var stump_visual: Sprite3D
var _full_sprite_scale := Vector3.ONE
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
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)

	stump_visual = Sprite3D.new()
	stump_visual.name = "StumpVisual"
	stump_visual.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stump_visual.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	stump_visual.no_depth_test = false
	if felling_atlas != null:
		var cell_size := Vector2(float(felling_atlas.get_width()) / 4.0, float(felling_atlas.get_height()))
		stump_visual.pixel_size = tree_width / cell_size.x
		stump_visual.scale = Vector3(
			1.0,
			vertical_scale_for(cell_size, Vector2(tree_width, tree_height)),
			1.0
		)
	stump_visual.position.y = tree_height * 0.5
	stump_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stump_visual.visible = false
	add_child(stump_visual)

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


func begin_felling(fall_direction: int) -> bool:
	if not is_chop_eligible() or remaining_units <= 0:
		return false
	_felling_active = true
	stump_visual.flip_h = fall_direction < 0
	set_felling_progress(0.0)
	return true


func set_felling_progress(progress: float) -> void:
	if not _felling_active:
		return
	var value := clampf(progress, 0.0, 1.0)
	var next_frame := 0 if value < 0.325 else (1 if value < 0.675 else 2)
	_show_felling_frame(next_frame)


func cancel_felling() -> void:
	_felling_active = false
	_felling_frame = -1
	if stump_visual != null:
		stump_visual.visible = false
		stump_visual.flip_h = false
	if sprite != null:
		sprite.visible = remaining_units > 0
		_sprite_reset()


func get_felling_frame() -> int:
	return _felling_frame


func _show_felling_frame(frame: int) -> void:
	if stump_visual == null or felling_atlas == null or frame < 0 or frame > 3:
		return
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = felling_atlas
	var cell_width := float(felling_atlas.get_width()) / 4.0
	atlas_texture.region = Rect2(cell_width * float(frame), 0.0, cell_width, felling_atlas.get_height())
	stump_visual.texture = atlas_texture
	stump_visual.visible = true
	_felling_frame = frame
	if sprite != null:
		sprite.visible = false


func _sprite_reset() -> void:
	if sprite == null:
		return
	sprite.scale = _full_sprite_scale
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
