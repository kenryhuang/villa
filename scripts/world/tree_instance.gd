class_name TreeInstance
extends ResourceNode

const TREE_TRUNK_LAYER := 16
const CAMERA_OCCLUDER_LAYER := 32
const OCCLUDED_OPACITY := 0.30
const CLEAR_OPACITY := 1.0
const FADE_RATE := 10.0

var occlusion_target := CLEAR_OPACITY
var sprite: Sprite3D

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
	interaction_radius = trunk_radius_for(float(tree_data.clearance))
	configure_resource({
		"resource_id": str(tree_data.get(
			"id",
			"tree@%.3f,%.3f" % [float(tree_data.x), float(tree_data.z)]
		)),
		"resource_type": "tree",
		"position": Vector3(float(tree_data.x), terrain_height, float(tree_data.z)),
		"gatherable": bool(tree_data.get("gatherable", false)),
	})
	add_to_group("tree_instance")

	sprite = Sprite3D.new()
	sprite.name = "Sprite3D"
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.pixel_size = tree_width / float(texture.get_width())
	sprite.scale = Vector3(1.0, vertical_scale_for(texture.get_size(), Vector2(tree_width, tree_height)), 1.0)
	sprite.position = Vector3(0.0, tree_height * 0.5, 0.0)
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)

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

func set_camera_occluded(value: bool) -> void:
	occlusion_target = OCCLUDED_OPACITY if value else CLEAR_OPACITY

func _process(delta: float) -> void:
	if sprite == null:
		return
	var color := sprite.modulate
	color.a = opacity_step(color.a, occlusion_target, delta)
	sprite.modulate = color
