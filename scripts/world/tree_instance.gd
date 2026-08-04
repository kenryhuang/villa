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
var stump_visual: MeshInstance3D
var axe_mark: Label3D
var _full_sprite_scale := Vector3.ONE
var variant := ""

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

func configure(tree_data: Dictionary, texture: Texture2D, terrain_height: float) -> void:
	var tree_width := float(tree_data.width)
	var tree_height := float(tree_data.height)
	variant = str(tree_data.get("variant", ""))
	interaction_radius = trunk_radius_for(float(tree_data.clearance))
	configure_resource({
		"resource_id": str(tree_data.get(
			"id",
			"tree@%.3f,%.3f" % [float(tree_data.x), float(tree_data.z)]
		)),
		"resource_type": "tree",
		"position": Vector3(float(tree_data.x), terrain_height, float(tree_data.z)),
		"gatherable": TreeFellingCatalogScript.is_variant_choppable(variant),
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

	stump_visual = MeshInstance3D.new()
	stump_visual.name = "StumpVisual"
	var stump_mesh := CylinderMesh.new()
	stump_mesh.top_radius = trunk_radius_for(float(tree_data.clearance)) * 0.82
	stump_mesh.bottom_radius = trunk_radius_for(float(tree_data.clearance))
	stump_mesh.height = 0.24
	stump_visual.mesh = stump_mesh
	var stump_material := StandardMaterial3D.new()
	stump_material.roughness = 0.95
	stump_material.albedo_color = Color("765034")
	stump_visual.material_override = stump_material
	stump_visual.position.y = 0.12
	stump_visual.visible = false
	add_child(stump_visual)

	axe_mark = Label3D.new()
	axe_mark.name = "AxeMark"
	axe_mark.text = "╳"
	axe_mark.font_size = 28
	axe_mark.outline_size = 6
	axe_mark.modulate = Color("6f3f27")
	axe_mark.outline_modulate = Color(0.95, 0.76, 0.49, 0.84)
	axe_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	axe_mark.no_depth_test = true
	axe_mark.position = Vector3(0.0, 0.48, 0.0)
	axe_mark.visible = false
	add_child(axe_mark)

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
	return TreeFellingCatalogScript.is_variant_choppable(variant)


func _set_gather_active(active: bool) -> void:
	super(active)
	if sprite != null:
		sprite.visible = true
	var trunk_body := get_node_or_null("TrunkBody") as CollisionObject3D
	if trunk_body != null:
		trunk_body.collision_layer = TREE_TRUNK_LAYER if (not gathering_enabled or active) else 0
	var gather_area := get_node_or_null("GatherArea") as CollisionObject3D
	if gather_area != null:
		gather_area.collision_layer = INTERACTION_LAYER if active else 0
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
	if sprite != null:
		sprite.visible = visual_stage < 3
		var damage_scale: float = [1.0, 0.96, 0.90, 0.0][visual_stage]
		sprite.scale = _full_sprite_scale * damage_scale
		var color := sprite.modulate
		color.r = 1.0 if visual_stage == 0 else 0.88
		color.g = 1.0 if visual_stage == 0 else 0.82
		sprite.modulate = color
	if stump_visual != null:
		stump_visual.visible = visual_stage == 3
	if axe_mark != null:
		axe_mark.visible = visual_stage in [1, 2]

func set_camera_occluded(value: bool) -> void:
	occlusion_target = OCCLUDED_OPACITY if value else CLEAR_OPACITY

func _process(delta: float) -> void:
	if sprite == null:
		return
	var color := sprite.modulate
	color.a = opacity_step(color.a, occlusion_target, delta)
	sprite.modulate = color
