class_name BuildingInstance
extends Node3D

signal interacted(building: BuildingInstance, player: Node)

const GameDataScript = preload("res://scripts/core/game_data.gd")
const COLLISION_LAYERS := 16 | 64
const INTERACTION_LAYERS := 64 | 256
const CAMERA_OCCLUDER_LAYER := 32
const OCCLUDED_OPACITY := 0.3
const CLEAR_OPACITY := 1.0
const FADE_RATE := 10.0

@export var authored_building_id := ""

var data: BuildingData
var grid_x := 0
var grid_z := 0
var occupied_cells: Array[Dictionary] = []
var _preview_mode := false
var _preview_valid := true
var _opacity_target := CLEAR_OPACITY

var building_id: String:
	get:
		return data.building_id if data else authored_building_id

var building_data: BuildingData:
	get:
		return data
	set(value):
		data = value

var gx: int:
	get:
		return grid_x

var gz: int:
	get:
		return grid_z


static func opacity_step(current: float, target: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-FADE_RATE * delta))


static func vertical_scale_for(texture_size: Vector2, target_size: Vector2) -> float:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 or target_size.x <= 0.0:
		return 1.0
	var pixel_size := target_size.x / texture_size.x
	return target_size.y / (texture_size.y * pixel_size)


func _ready() -> void:
	_ensure_nodes()
	if data == null and not authored_building_id.is_empty():
		var game_data = GameDataScript.new()
		configure(BuildingData.from_dictionary(game_data.get_building(authored_building_id)), 0, 0, [])
		game_data.free()


func configure(
	building_data: BuildingData,
	gx: int,
	gz: int,
	cells: Array
) -> void:
	data = building_data
	grid_x = gx
	grid_z = gz
	occupied_cells.clear()
	for cell in cells:
		if cell is Dictionary:
			occupied_cells.append((cell as Dictionary).duplicate(true))
	_ensure_nodes()
	if data == null or not data.is_valid():
		return
	name = data.display_name
	_configure_visuals()
	_configure_physics()
	if not _preview_mode and not is_in_group("building_instance"):
		add_to_group("building_instance")


func set_preview_mode(value: bool) -> void:
	_preview_mode = value
	_ensure_nodes()
	var collision := get_node("Collision") as StaticBody3D
	var interaction_area := get_node("InteractionArea") as Area3D
	var camera_occluder := get_node("CameraOccluder") as Area3D
	collision.collision_layer = 0 if value else COLLISION_LAYERS
	collision.collision_mask = 0
	interaction_area.collision_layer = 0 if value else INTERACTION_LAYERS
	interaction_area.collision_mask = 0
	interaction_area.monitoring = not value
	camera_occluder.collision_layer = 0 if value else CAMERA_OCCLUDER_LAYER
	camera_occluder.collision_mask = 0
	camera_occluder.monitoring = false
	if value:
		remove_from_group("building_instance")
	else:
		add_to_group("building_instance")
	_apply_visual_color()


func deactivate() -> void:
	_ensure_nodes()
	var collision := get_node("Collision") as StaticBody3D
	var interaction_area := get_node("InteractionArea") as Area3D
	var camera_occluder := get_node("CameraOccluder") as Area3D
	collision.collision_layer = 0
	collision.collision_mask = 0
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 0
	interaction_area.monitoring = false
	camera_occluder.collision_layer = 0
	camera_occluder.collision_mask = 0
	camera_occluder.monitoring = false
	remove_from_group("building_instance")
	visible = false
	set_process(false)


func set_preview_valid(value: bool) -> void:
	_preview_valid = value
	_apply_visual_color()


func set_camera_occluded(value: bool) -> void:
	_opacity_target = OCCLUDED_OPACITY if value else CLEAR_OPACITY


func get_target_opacity() -> float:
	return _opacity_target


func get_interaction_area() -> Area3D:
	_ensure_nodes()
	return get_node("InteractionArea") as Area3D


func interact(player: Node) -> void:
	interacted.emit(self, player)


func to_dict() -> Dictionary:
	return {
		"building_id": data.building_id if data else authored_building_id,
		"gx": grid_x,
		"gz": grid_z,
		"occupied_cells": occupied_cells.duplicate(true),
	}


func _process(delta: float) -> void:
	if _preview_mode:
		return
	for geometry in _visual_geometry():
		if geometry is Sprite3D:
			var sprite := geometry as Sprite3D
			var color: Color = sprite.modulate
			color.a = opacity_step(color.a, _opacity_target, delta)
			sprite.modulate = color
		elif geometry is MeshInstance3D:
			var mesh := geometry as MeshInstance3D
			var current_alpha := 1.0 - mesh.transparency
			mesh.transparency = 1.0 - opacity_step(current_alpha, _opacity_target, delta)


func _ensure_nodes() -> void:
	var visual_root := get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		visual_root = Node3D.new()
		visual_root.name = "VisualRoot"
		add_child(visual_root)
	if visual_root.get_node_or_null("BackLayer") == null:
		var back := Sprite3D.new()
		back.name = "BackLayer"
		visual_root.add_child(back)
	if visual_root.get_node_or_null("FrontLayer") == null:
		var front := Sprite3D.new()
		front.name = "FrontLayer"
		visual_root.add_child(front)
	if visual_root.get_node_or_null("FallbackBody") == null:
		var fallback_body := MeshInstance3D.new()
		fallback_body.name = "FallbackBody"
		visual_root.add_child(fallback_body)
	if visual_root.get_node_or_null("FallbackRoof") == null:
		var fallback_roof := MeshInstance3D.new()
		fallback_roof.name = "FallbackRoof"
		visual_root.add_child(fallback_roof)
	_ensure_physics_node("Collision", StaticBody3D)
	_ensure_physics_node("InteractionArea", Area3D)
	_ensure_physics_node("CameraOccluder", Area3D)


func _ensure_physics_node(node_name: String, node_type: Variant) -> void:
	var physics_node := get_node_or_null(node_name) as CollisionObject3D
	if physics_node == null:
		physics_node = node_type.new()
		physics_node.name = node_name
		add_child(physics_node)
	if physics_node.get_node_or_null("CollisionShape3D") == null:
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		physics_node.add_child(collision_shape)


func _configure_visuals() -> void:
	var visual_root := get_node("VisualRoot") as Node3D
	var back := visual_root.get_node("BackLayer") as Sprite3D
	var front := visual_root.get_node("FrontLayer") as Sprite3D
	var base_path := "res://assets/buildings/painted/%s/%s" % [data.building_id, data.building_id]
	var back_texture := _load_texture(base_path + "_back.png")
	var front_texture := _load_texture(base_path + "_front.png")
	var has_painted_layers := back_texture != null and front_texture != null
	back.visible = has_painted_layers
	front.visible = has_painted_layers
	if has_painted_layers:
		_configure_sprite(back, back_texture, Vector3.ZERO, -0.1)
		_configure_sprite(front, front_texture, Vector3(0.025, 0.0, 0.025), 0.1)
	_configure_fallback(not has_painted_layers)
	_apply_visual_color()


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _configure_sprite(
	sprite: Sprite3D,
	texture: Texture2D,
	offset: Vector3,
	sort_offset: float
) -> void:
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.pixel_size = data.visual_size.x / float(texture.get_width())
	sprite.scale = Vector3(
		1.0,
		vertical_scale_for(texture.get_size(), data.visual_size),
		1.0
	)
	sprite.position = Vector3(
		offset.x,
		data.visual_size.y * 0.5 + offset.y,
		offset.z
	)
	sprite.sorting_offset = sort_offset


func _configure_fallback(visible: bool) -> void:
	var body := get_node("VisualRoot/FallbackBody") as MeshInstance3D
	var roof := get_node("VisualRoot/FallbackRoof") as MeshInstance3D
	body.visible = visible
	roof.visible = visible
	if not visible:
		return
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(
		maxf(float(data.footprint.x) * 0.72, 0.45),
		data.visual_size.y * 0.55,
		maxf(float(data.footprint.y) * 0.72, 0.45)
	)
	body.mesh = body_mesh
	body.position.y = body_mesh.size.y * 0.5
	body.material_override = _fallback_material(Color("b97b4c"))
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(
		body_mesh.size.x * 1.12,
		data.visual_size.y * 0.28,
		body_mesh.size.z * 1.12
	)
	roof.mesh = roof_mesh
	roof.position.y = body_mesh.size.y + roof_mesh.size.y * 0.35
	roof.material_override = _fallback_material(Color("5f4336"))


func _fallback_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _configure_physics() -> void:
	var footprint_size := Vector3(
		maxf(float(data.footprint.x) * 0.78, 0.4),
		maxf(data.visual_size.y * 0.58, 0.5),
		maxf(float(data.footprint.y) * 0.78, 0.4)
	)
	_set_box_shape("Collision", footprint_size, footprint_size.y * 0.5)
	_set_box_shape(
		"InteractionArea",
		footprint_size + Vector3(0.55, 0.35, 0.55),
		(footprint_size.y + 0.35) * 0.5
	)
	_set_box_shape(
		"CameraOccluder",
		Vector3(
			maxf(data.visual_size.x * 0.82, 0.5),
			maxf(data.visual_size.y * 0.9, 0.6),
			maxf(float(data.footprint.y) * 0.65, 0.4)
		),
		data.visual_size.y * 0.45
	)
	set_preview_mode(_preview_mode)


func _set_box_shape(node_path: NodePath, size: Vector3, center_y: float) -> void:
	var collision_shape := get_node(NodePath("%s/CollisionShape3D" % node_path)) as CollisionShape3D
	var shape := BoxShape3D.new()
	shape.size = size
	collision_shape.shape = shape
	collision_shape.position.y = center_y


func _apply_visual_color() -> void:
	var tint := Color.WHITE
	if _preview_mode:
		tint = Color(0.48, 1.0, 0.52, 0.68) if _preview_valid else Color(1.0, 0.38, 0.38, 0.68)
	for geometry in _visual_geometry():
		if geometry is Sprite3D:
			(geometry as Sprite3D).modulate = tint
		elif geometry is MeshInstance3D:
			var mesh := geometry as MeshInstance3D
			var material := mesh.material_override as StandardMaterial3D
			if material:
				material.albedo_color = Color(tint.r, tint.g, tint.b, 1.0)
			mesh.transparency = 1.0 - tint.a


func _visual_geometry() -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	var visual_root := get_node_or_null("VisualRoot")
	if visual_root == null:
		return result
	for child in visual_root.get_children():
		if child is GeometryInstance3D:
			result.append(child)
	return result
