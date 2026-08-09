class_name BuildingProductionYard
extends Node3D

const ATLAS_FRAME_SIZE := Vector2(256.0, 192.0)
const VALID_STYLES := ["timber", "masonry", "industrial"]
const PHYSICAL_COLLISION_LAYER := 16
const TEXTURES := {
	"timber": "res://assets/buildings/yards/timber_yard_fence.svg",
	"masonry": "res://assets/buildings/yards/masonry_yard_fence.svg",
	"industrial": "res://assets/buildings/yards/industrial_yard_fence.svg",
}

var _yard_size := Vector2i.ZERO
var _style := ""
var _structure_offset := Vector3.ZERO
var _construction_stage := 3
var _preview_active := false
var _preview_valid := true
var _maintenance_state := "normal"
var _collisions_enabled := false
var _segments: Array[Sprite3D] = []
var _output_slots: Array[Vector3] = []
var _collision_body: StaticBody3D


func configure(size: Vector2i, style: String, structure_offset: Vector3) -> bool:
	if size.x not in [3, 4] or size.y != size.x or style not in VALID_STYLES:
		return false
	clear_immediately()
	_yard_size = size
	_style = style
	_structure_offset = structure_offset
	_ensure_layers()
	_build_fence_segments()
	_build_perimeter_collision()
	_output_slots = _slots_for_size(size)
	_apply_visual_state()
	_apply_collision_state()
	return true


func set_preview_state(active: bool, valid: bool) -> void:
	_preview_active = active
	_preview_valid = valid
	_apply_visual_state()


func set_construction_stage(stage: int) -> void:
	_construction_stage = clampi(stage, 0, 3)
	_apply_visual_state()


func get_construction_stage() -> int:
	return _construction_stage


func set_maintenance_state(state: String) -> void:
	_maintenance_state = state
	_apply_visual_state()


func set_interaction_enabled(enabled: bool) -> void:
	_collisions_enabled = enabled
	_apply_collision_state()


func get_output_slots() -> Array[Vector3]:
	return _output_slots.duplicate()


func get_fence_segment_count() -> int:
	return _segments.size()


func get_style() -> String:
	return _style


func get_visual_tint() -> Color:
	if _preview_active:
		return Color(0.48, 1.0, 0.52, 0.68) if _preview_valid else Color(1.0, 0.38, 0.38, 0.68)
	if _maintenance_state == "warning":
		return Color(0.92, 0.89, 0.78, 1.0)
	if _maintenance_state in ["overdue", "repairing"]:
		return Color(0.76, 0.72, 0.66, 1.0)
	return Color.WHITE


func all_output_slots_inside_bounds() -> bool:
	var half_x := float(_yard_size.x) * 0.5
	var half_z := float(_yard_size.y) * 0.5
	for slot in _output_slots:
		if absf(slot.x) >= half_x or absf(slot.z) >= half_z:
			return false
	return true


func has_enabled_collisions() -> bool:
	return _collision_body != null and _collision_body.collision_layer != 0


func get_collision_layers() -> Array[int]:
	var result: Array[int] = []
	if _collision_body != null and _collision_body.collision_layer != 0:
		result.append(_collision_body.collision_layer)
	return result


func clear_immediately() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_segments.clear()
	_output_slots.clear()
	_collision_body = null


func _ensure_layers() -> void:
	for layer_name in ["BackFenceLayer", "SideFenceLayer", "FrontFenceLayer"]:
		var layer := Node3D.new()
		layer.name = layer_name
		add_child(layer)
	_collision_body = StaticBody3D.new()
	_collision_body.name = "FenceCollisions"
	_collision_body.collision_mask = 0
	add_child(_collision_body)


func _build_fence_segments() -> void:
	var half_x := float(_yard_size.x) * 0.5
	var half_z := float(_yard_size.y) * 0.5
	for index in _yard_size.x:
		var x := -half_x + 0.5 + float(index)
		_add_segment(Vector3(x, 0.0, -half_z), 0, get_node("BackFenceLayer"), -0.35)
		_add_segment(Vector3(x, 0.0, half_z), 0, get_node("FrontFenceLayer"), 0.45)
	for index in _yard_size.y:
		var z := -half_z + 0.5 + float(index)
		_add_segment(Vector3(-half_x, 0.0, z), 1, get_node("SideFenceLayer"), 0.05)
		_add_segment(Vector3(half_x, 0.0, z), 1, get_node("SideFenceLayer"), 0.05)


func _add_segment(position_value: Vector3, orientation: int, parent: Node, sorting: float) -> void:
	var sprite := Sprite3D.new()
	sprite.texture = load(TEXTURES[_style]) as Texture2D
	sprite.region_enabled = true
	sprite.pixel_size = 0.004
	sprite.position = position_value + Vector3(0.0, 0.36, 0.0)
	sprite.sorting_offset = sorting
	sprite.set_meta("orientation", orientation)
	parent.add_child(sprite)
	_segments.append(sprite)


func _build_perimeter_collision() -> void:
	var half_x := float(_yard_size.x) * 0.5
	var half_z := float(_yard_size.y) * 0.5
	_add_box_collision(Vector3(float(_yard_size.x), 0.8, 0.12), Vector3(0.0, 0.4, -half_z))
	_add_box_collision(Vector3(float(_yard_size.x), 0.8, 0.12), Vector3(0.0, 0.4, half_z))
	_add_box_collision(Vector3(0.12, 0.8, float(_yard_size.y)), Vector3(-half_x, 0.4, 0.0))
	_add_box_collision(Vector3(0.12, 0.8, float(_yard_size.y)), Vector3(half_x, 0.4, 0.0))


func _add_box_collision(size: Vector3, position_value: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = position_value
	_collision_body.add_child(collision)


func _slots_for_size(size: Vector2i) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var columns := 3 if size.x == 3 else 4
	var spacing := 0.78
	var start_x := -float(columns - 1) * spacing * 0.5
	var first_z := float(size.y) * 0.5 - 0.76
	for row in 2:
		for column in columns:
			result.append(Vector3(start_x + float(column) * spacing, 0.0, first_z - float(row) * 0.54))
	return result


func _apply_visual_state() -> void:
	var tint := get_visual_tint()
	for sprite in _segments:
		var orientation := int(sprite.get_meta("orientation", 0))
		sprite.region_rect = Rect2(
			float(orientation) * ATLAS_FRAME_SIZE.x,
			float(_construction_stage) * ATLAS_FRAME_SIZE.y,
			ATLAS_FRAME_SIZE.x,
			ATLAS_FRAME_SIZE.y
		)
		sprite.modulate = tint


func _apply_collision_state() -> void:
	if _collision_body != null:
		_collision_body.collision_layer = PHYSICAL_COLLISION_LAYER if _collisions_enabled else 0
