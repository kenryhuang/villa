class_name ResourceNode
extends Node3D

const INTERACTION_LAYER := 64
const OBSTACLE_LAYER := 16

@export var resource_id := ""
@export var required_tool := "pickaxe"
@export var hits_remaining := 3
@export var yield_per_hit: Dictionary = {"stone": 2}
@export var bonus_table: Array[Dictionary] = []
@export var respawn_days := 3

var visual_kind := "rock"
var _max_hits := 3
var _respawn_day := -1
var _last_advanced_day := 0


func _ready() -> void:
	add_to_group("gatherable_resource")
	_set_gather_active(hits_remaining > 0)


func configure_resource(definition: Dictionary) -> bool:
	var next_id := str(definition.get("resource_id", ""))
	var next_tool := str(definition.get("required_tool", ""))
	var next_hits_value: Variant = definition.get("hits", 3)
	var next_respawn_value: Variant = definition.get("respawn_days", 3)
	var next_yield: Variant = definition.get("yield_per_hit", {})
	var next_bonus: Variant = definition.get("bonus_table", [])
	var next_position: Variant = definition.get("position", Vector3.ZERO)
	if (
		next_id.is_empty()
		or next_tool not in ["axe", "pickaxe"]
		or not _is_positive_integer(next_hits_value)
		or not _is_non_negative_integer(next_respawn_value)
		or not _valid_reward(next_yield)
		or not _valid_bonus_table(next_bonus)
		or not next_position is Vector3
		or not _finite_vector3(next_position)
	):
		return false
	resource_id = next_id
	required_tool = next_tool
	_max_hits = int(next_hits_value)
	hits_remaining = _max_hits
	respawn_days = int(next_respawn_value)
	yield_per_hit = _normalized_reward(next_yield)
	bonus_table = _normalized_bonus_table(next_bonus)
	position = next_position
	visual_kind = str(definition.get("visual_kind", "rock"))
	_respawn_day = -1
	_last_advanced_day = 0
	_set_gather_active(true)
	return true


func can_gather(tool_id: String) -> bool:
	return (
		not resource_id.is_empty()
		and tool_id == required_tool
		and hits_remaining > 0
		and not yield_per_hit.is_empty()
	)


func preview_reward(tool_id: String) -> Dictionary:
	if not can_gather(tool_id):
		return {}
	var reward := yield_per_hit.duplicate(true)
	var hit_number := _max_hits - hits_remaining + 1
	for entry in bonus_table:
		var every_hits := int(entry.every_hits)
		var offset := int(entry.offset)
		if (hit_number - 1 - offset) % every_hits != 0:
			continue
		var item_id := str(entry.item_id)
		reward[item_id] = int(reward.get(item_id, 0)) + int(entry.quantity)
	return reward


func commit_gather(tool_id: String, total_day: int = 0) -> Dictionary:
	if total_day < 0:
		return {}
	var reward := preview_reward(tool_id)
	if reward.is_empty():
		return {}
	hits_remaining -= 1
	if hits_remaining == 0:
		_respawn_day = total_day + respawn_days
		_set_gather_active(false)
	return reward


func advance_day(total_day: int) -> bool:
	if total_day < 0 or total_day <= _last_advanced_day:
		return false
	_last_advanced_day = total_day
	if hits_remaining > 0 or _respawn_day < 0 or total_day < _respawn_day:
		return false
	hits_remaining = _max_hits
	_respawn_day = -1
	_set_gather_active(true)
	return true


func initialize_at_day(total_day: int) -> void:
	hits_remaining = _max_hits
	_respawn_day = -1
	_last_advanced_day = maxi(total_day, 0)
	_set_gather_active(true)


func sync_day_cursor(total_day: int) -> bool:
	if total_day < 0:
		return false
	_last_advanced_day = total_day
	return true


func get_respawn_day() -> int:
	return _respawn_day


func to_dict() -> Dictionary:
	return {
		"resource_id": resource_id,
		"position": [position.x, position.y, position.z],
		"hits_remaining": hits_remaining,
		"respawn_day": _respawn_day,
	}


func validate_state_dict(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for field in ["resource_id", "position", "hits_remaining", "respawn_day"]:
		if not data.has(field):
			return false
	if str(data.resource_id) != resource_id or resource_id.is_empty():
		return false
	var saved_position: Variant = data.position
	if not saved_position is Array or saved_position.size() != 3:
		return false
	for coordinate in saved_position:
		if not _is_finite_number(coordinate):
			return false
	if not _is_integer_number(data.hits_remaining):
		return false
	if not _is_integer_number(data.respawn_day):
		return false
	var saved_hits := int(data.hits_remaining)
	var saved_respawn := int(data.respawn_day)
	if saved_hits < 0 or saved_hits > _max_hits or saved_respawn < -1:
		return false
	if saved_hits == 0 and saved_respawn < 0:
		return false
	if saved_hits > 0 and saved_respawn != -1:
		return false
	return true


func from_dict(data: Dictionary) -> bool:
	if not validate_state_dict(data):
		return false
	var saved_position: Array = data.position
	position = Vector3(
		float(saved_position[0]),
		float(saved_position[1]),
		float(saved_position[2])
	)
	hits_remaining = int(data.hits_remaining)
	_respawn_day = int(data.respawn_day)
	_set_gather_active(hits_remaining > 0)
	return true


func build_fallback_visual() -> void:
	if get_node_or_null("Visual") != null or get_node_or_null("Collision") != null:
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	var shape: Shape3D
	match visual_kind:
		"clay":
			var clay_mesh := CylinderMesh.new()
			clay_mesh.top_radius = 0.48
			clay_mesh.bottom_radius = 0.58
			clay_mesh.height = 0.32
			mesh_instance.mesh = clay_mesh
			var cylinder := CylinderShape3D.new()
			cylinder.radius = 0.56
			cylinder.height = 0.32
			shape = cylinder
		"sand":
			var sand_mesh := SphereMesh.new()
			sand_mesh.radius = 0.6
			sand_mesh.height = 0.28
			mesh_instance.mesh = sand_mesh
			var sphere := SphereShape3D.new()
			sphere.radius = 0.55
			shape = sphere
		_:
			var rock_mesh := SphereMesh.new()
			rock_mesh.radius = 0.48
			rock_mesh.height = 0.8
			mesh_instance.mesh = rock_mesh
			var sphere := SphereShape3D.new()
			sphere.radius = 0.48
			shape = sphere
	var material := StandardMaterial3D.new()
	material.roughness = 0.92
	material.albedo_color = _fallback_color()
	mesh_instance.material_override = material
	mesh_instance.position.y = 0.2
	add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = OBSTACLE_LAYER | INTERACTION_LAYER
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	collision.position.y = 0.2
	body.add_child(collision)
	add_child(body)
	_set_gather_active(hits_remaining > 0)


func _set_gather_active(active: bool) -> void:
	visible = active
	var body := get_node_or_null("Collision") as CollisionObject3D
	if body != null:
		body.collision_layer = (OBSTACLE_LAYER | INTERACTION_LAYER) if active else 0


func _fallback_color() -> Color:
	match visual_kind:
		"clay":
			return Color(0.52, 0.29, 0.18)
		"sand":
			return Color(0.82, 0.70, 0.45)
		_:
			return Color(0.38, 0.40, 0.43)


func _valid_reward(value: Variant) -> bool:
	if not value is Dictionary or value.is_empty():
		return false
	for item_id in value:
		if str(item_id).is_empty() or not _is_positive_integer(value[item_id]):
			return false
	return true


func _normalized_reward(value: Dictionary) -> Dictionary:
	var result := {}
	for item_id in value:
		result[str(item_id)] = int(value[item_id])
	return result


func _valid_bonus_table(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry in value:
		if not entry is Dictionary:
			return false
		for field in ["item_id", "quantity", "every_hits"]:
			if not entry.has(field):
				return false
		if (
			str(entry.item_id).is_empty()
			or not _is_positive_integer(entry.quantity)
			or not _is_positive_integer(entry.every_hits)
			or not _is_non_negative_integer(entry.get("offset", 0))
			or int(entry.get("offset", 0)) >= int(entry.every_hits)
		):
			return false
	return true


func _normalized_bonus_table(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in value:
		result.append({
			"item_id": str(entry.item_id),
			"quantity": int(entry.quantity),
			"every_hits": int(entry.every_hits),
			"offset": int(entry.get("offset", 0)),
		})
	return result


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
