class_name ResourceNode
extends Node3D

signal gathering_active_changed(resource_id: String, active: bool)

const ResourceCatalogScript = preload("res://scripts/world/resource_catalog.gd")
const INTERACTION_LAYER := 64
const OBSTACLE_LAYER := 16
const STATE_VERSION := 2

@export var resource_id := ""
@export var resource_type := "stone"
@export var item_id := "stone"
@export var required_tool := "pickaxe"
@export var max_units := 4
@export var remaining_units := 4
@export var respawn_days := 3
@export var visual_stage := 0
@export var gathering_enabled := true
@export var interaction_radius := 0.52

# Compatibility surfaces for old scenes and callers. Runtime rewards are always one unit.
var hits_remaining: int:
	get:
		return remaining_units
	set(value):
		remaining_units = value
		_update_visual_stage()
var yield_per_hit: Dictionary:
	get:
		return {item_id: 1} if not item_id.is_empty() else {}
	set(value):
		if value is Dictionary and not value.is_empty():
			item_id = str(value.keys()[0])
var bonus_table: Array[Dictionary] = []
var visual_kind := "stone"

var _respawn_day := 0
var _last_advanced_day := 0
var _legacy_max_hits := 3
var _gather_active := false


func _ready() -> void:
	if gathering_enabled:
		add_to_group("gatherable_resource")
	else:
		remove_from_group("gatherable_resource")
	_set_gather_active(gathering_enabled and remaining_units > 0)
	_apply_visual_stage()


func configure_resource(definition: Dictionary) -> bool:
	var next_id := str(definition.get("resource_id", ""))
	var next_position: Variant = definition.get("position", Vector3.ZERO)
	if next_id.is_empty() or not next_position is Vector3 or not _finite_vector3(next_position):
		return false

	var next_type := str(definition.get("resource_type", ""))
	if next_type.is_empty():
		next_type = _infer_resource_type(definition)
	var catalog := ResourceCatalogScript.definition(next_type)
	var next_item := str(definition.get("item_id", catalog.get("item_id", "")))
	if next_item.is_empty():
		var legacy_reward: Variant = definition.get("yield_per_hit", {})
		if legacy_reward is Dictionary and not legacy_reward.is_empty():
			next_item = str(legacy_reward.keys()[0])
	var next_tool := str(definition.get("required_tool", catalog.get("required_tool", "")))
	var next_max_value: Variant = definition.get(
		"max_units",
		definition.get("hits", catalog.get("max_units", 0))
	)
	var next_respawn_value: Variant = definition.get(
		"respawn_days",
		catalog.get("respawn_days", 0)
	)
	if (
		next_type.is_empty()
		or next_item.is_empty()
		or next_tool not in ["axe", "pickaxe"]
		or not _is_positive_integer(next_max_value)
		or not _is_non_negative_integer(next_respawn_value)
	):
		return false

	resource_id = next_id
	resource_type = next_type
	item_id = next_item
	required_tool = next_tool
	max_units = int(next_max_value)
	remaining_units = max_units
	_legacy_max_hits = int(definition.get("hits", max_units))
	respawn_days = int(next_respawn_value)
	position = next_position
	visual_kind = str(definition.get("visual_kind", catalog.get("visual_kind", next_type)))
	gathering_enabled = bool(definition.get("gatherable", true))
	bonus_table.clear()
	_respawn_day = 0
	_last_advanced_day = 0
	_update_visual_stage()
	if is_inside_tree():
		if gathering_enabled:
			add_to_group("gatherable_resource")
		else:
			remove_from_group("gatherable_resource")
	_set_gather_active(gathering_enabled and remaining_units > 0)
	return true


func can_gather(tool_id: String) -> bool:
	return (
		gathering_enabled
		and not resource_id.is_empty()
		and tool_id == required_tool
		and remaining_units > 0
		and not item_id.is_empty()
	)


func preview_reward(tool_id: String) -> Dictionary:
	return {item_id: 1} if can_gather(tool_id) else {}


func commit_gather(tool_id: String, total_day: int = 0) -> Dictionary:
	if total_day < 0:
		return {}
	var reward := preview_reward(tool_id)
	if reward.is_empty():
		return {}
	remaining_units -= 1
	if remaining_units == 0:
		_respawn_day = total_day + respawn_days
	_update_visual_stage()
	_set_gather_active(gathering_enabled and remaining_units > 0)
	return reward


func advance_day(total_day: int) -> bool:
	if total_day < 0 or total_day <= _last_advanced_day:
		return false
	_last_advanced_day = total_day
	if remaining_units > 0 or _respawn_day <= 0 or total_day < _respawn_day:
		return false
	remaining_units = max_units
	_respawn_day = 0
	_update_visual_stage()
	_set_gather_active(gathering_enabled)
	return true


func initialize_at_day(total_day: int) -> void:
	remaining_units = max_units
	_respawn_day = 0
	_last_advanced_day = maxi(total_day, 0)
	_update_visual_stage()
	_set_gather_active(gathering_enabled)


func sync_day_cursor(total_day: int) -> bool:
	if total_day < 0:
		return false
	_last_advanced_day = total_day
	return true


func get_respawn_day() -> int:
	return _respawn_day


func get_display_name() -> String:
	return str(ResourceCatalogScript.definition(resource_type).get("display_name", resource_type))


func get_interaction_radius() -> float:
	return maxf(0.0, interaction_radius)


func to_dict() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"resource_id": resource_id,
		"resource_type": resource_type,
		"item_id": item_id,
		"required_tool": required_tool,
		"max_units": max_units,
		"remaining_units": remaining_units,
		"respawn_days": respawn_days,
		"respawn_day": _respawn_day,
		"position": [position.x, position.y, position.z],
		"visual_stage": visual_stage,
	}


func validate_state_dict(data: Variant, loaded_day: int = -1) -> bool:
	return not _normalized_state(data, loaded_day).is_empty()


func from_dict(data: Dictionary) -> bool:
	var normalized := _normalized_state(data)
	if normalized.is_empty():
		return false
	var saved_position: Array = normalized.position
	position = Vector3(float(saved_position[0]), float(saved_position[1]), float(saved_position[2]))
	remaining_units = int(normalized.remaining_units)
	_respawn_day = int(normalized.respawn_day)
	_update_visual_stage()
	_set_gather_active(gathering_enabled and remaining_units > 0)
	return true


func build_fallback_visual() -> void:
	if get_node_or_null("Visual") != null or get_node_or_null("Collision") != null:
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.52
	rock_mesh.height = 0.82
	mesh_instance.mesh = rock_mesh
	var material := StandardMaterial3D.new()
	material.roughness = 0.92
	material.albedo_color = _fallback_color()
	mesh_instance.material_override = material
	mesh_instance.position.y = 0.2
	add_child(mesh_instance)
	var crack_mark := MeshInstance3D.new()
	crack_mark.name = "CrackMark"
	var crack_quad := QuadMesh.new()
	crack_quad.size = Vector2(0.42, 0.30)
	crack_mark.mesh = crack_quad
	var crack_material := StandardMaterial3D.new()
	crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crack_material.albedo_color = Color(0.12, 0.09, 0.07, 0.78)
	crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crack_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	crack_mark.material_override = crack_material
	crack_mark.position = Vector3(0.0, 0.34, 0.46)
	crack_mark.visible = false
	add_child(crack_mark)

	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = OBSTACLE_LAYER | INTERACTION_LAYER
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.52
	collision.shape = sphere
	collision.position.y = 0.2
	body.add_child(collision)
	add_child(body)
	_apply_visual_stage()
	_set_gather_active(gathering_enabled and remaining_units > 0)


func _set_gather_active(active: bool) -> void:
	visible = true
	var body := get_node_or_null("Collision") as CollisionObject3D
	if body != null:
		body.collision_layer = (OBSTACLE_LAYER | INTERACTION_LAYER) if active else 0
	if active != _gather_active:
		_gather_active = active
		gathering_active_changed.emit(resource_id, active)


func _update_visual_stage() -> void:
	if remaining_units <= 0:
		visual_stage = 3
	elif remaining_units >= max_units:
		visual_stage = 0
	elif remaining_units * 3 > max_units:
		visual_stage = 1
	else:
		visual_stage = 2
	_apply_visual_stage()


func _apply_visual_stage() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null:
		return
	match visual_stage:
		0:
			visual.scale = Vector3.ONE
		1:
			visual.scale = Vector3(0.82, 0.82, 0.82)
		2:
			visual.scale = Vector3(0.62, 0.62, 0.62)
		_:
			visual.scale = Vector3(0.42, 0.18, 0.42)
	var crack_mark := get_node_or_null("CrackMark") as MeshInstance3D
	if crack_mark != null:
		crack_mark.visible = visual_stage in [1, 2]


func _fallback_color() -> Color:
	return Color(ResourceCatalogScript.definition(resource_type).get("color", Color("62666a")))


func _normalized_state(data: Variant, loaded_day: int = -1) -> Dictionary:
	if not data is Dictionary:
		return {}
	if int(data.get("state_version", 1)) == STATE_VERSION:
		return _normalized_v2_state(data, loaded_day)
	return _normalized_legacy_state(data, loaded_day)


func _normalized_v2_state(data: Dictionary, loaded_day: int) -> Dictionary:
	for field in [
		"resource_id", "resource_type", "item_id", "required_tool", "max_units",
		"remaining_units", "respawn_days", "respawn_day", "position", "visual_stage",
	]:
		if not data.has(field):
			return {}
	if (
		str(data.resource_id) != resource_id
		or str(data.resource_type) != resource_type
		or str(data.item_id) != item_id
		or str(data.required_tool) != required_tool
		or not _is_integer_number(data.max_units)
		or int(data.max_units) != max_units
		or not _is_integer_number(data.remaining_units)
		or not _is_integer_number(data.respawn_days)
		or int(data.respawn_days) != respawn_days
		or not _is_integer_number(data.respawn_day)
		or not _is_integer_number(data.visual_stage)
	):
		return {}
	return _validated_normalized_state(data, loaded_day)


func _normalized_legacy_state(data: Dictionary, loaded_day: int) -> Dictionary:
	for field in ["resource_id", "position", "hits_remaining", "respawn_day"]:
		if not data.has(field):
			return {}
	if str(data.resource_id) != resource_id or not _is_integer_number(data.hits_remaining):
		return {}
	var old_hits := int(data.hits_remaining)
	if old_hits < 0 or old_hits > _legacy_max_hits:
		return {}
	var migrated_units := 0
	if old_hits > 0:
		migrated_units = ceili(float(old_hits) / float(_legacy_max_hits) * float(max_units))
	return _validated_normalized_state({
		"state_version": STATE_VERSION,
		"resource_id": resource_id,
		"resource_type": resource_type,
		"item_id": item_id,
		"required_tool": required_tool,
		"max_units": max_units,
		"remaining_units": migrated_units,
		"respawn_days": respawn_days,
		"respawn_day": data.respawn_day,
		"position": data.position,
		"visual_stage": _stage_for_units(migrated_units),
	}, loaded_day)


func _validated_normalized_state(data: Dictionary, loaded_day: int) -> Dictionary:
	var saved_position: Variant = data.position
	if not saved_position is Array or saved_position.size() != 3:
		return {}
	for coordinate in saved_position:
		if not _is_finite_number(coordinate):
			return {}
	var saved_units := int(data.remaining_units)
	var saved_respawn := int(data.respawn_day)
	if saved_units < 0 or saved_units > max_units or saved_respawn < 0:
		return {}
	if saved_units == 0 and saved_respawn <= 0:
		return {}
	if saved_units > 0 and saved_respawn != 0:
		return {}
	if loaded_day >= 0 and saved_units == 0 and (
		saved_respawn <= loaded_day or saved_respawn > loaded_day + respawn_days
	):
		return {}
	var expected_stage := _stage_for_units(saved_units)
	if int(data.visual_stage) != expected_stage:
		return {}
	return data.duplicate(true)


func _stage_for_units(units: int) -> int:
	if units <= 0:
		return 3
	if units >= max_units:
		return 0
	return 1 if units * 3 > max_units else 2


func _infer_resource_type(definition: Dictionary) -> String:
	var reward: Variant = definition.get("yield_per_hit", {})
	if not reward is Dictionary or reward.is_empty():
		return ""
	var inferred_item := str(reward.keys()[0])
	if inferred_item == "wood":
		return "tree"
	return inferred_item


func _is_positive_integer(value: Variant) -> bool:
	return _is_integer_number(value) and int(value) > 0


func _is_non_negative_integer(value: Variant) -> bool:
	return _is_integer_number(value) and int(value) >= 0


func _is_integer_number(value: Variant) -> bool:
	return _is_finite_number(value) and floorf(float(value)) == float(value)


func _is_finite_number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
	)


func _finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
