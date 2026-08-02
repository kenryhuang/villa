class_name GameWorld
extends Node3D

const ResourceNodeScript = preload("res://scripts/world/resource_node.gd")
const WORLD_GENERATION_SEED := 0x56494c4c41

@onready var terrain: TerrainBuilder = $Terrain
@onready var road: RoadBuilder = $Road
@onready var vegetation: VegetationBuilder = $Vegetation
@onready var resource_nodes: Node3D = $ResourceNodes


func _ready() -> void:
	if not terrain.build():
		push_error("World initialization stopped because terrain failed")
		return
	road.build(terrain)
	var route: Array[Dictionary] = []
	for point in RoadBuilder.MAIN_ROUTE:
		route.append(point.duplicate())
	vegetation.build(terrain, route)
	generate_resource_nodes(terrain)


func get_height_at(world_x: float, world_z: float) -> float:
	return terrain.get_height_at(world_x, world_z)


func get_bounds() -> Rect2:
	return Rect2(-17.2, -13.2, 34.4, 26.4)


static func generated_resource_definitions(
	seed: int = WORLD_GENERATION_SEED
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{"id": "rock-coal-00", "zone": "wasteland", "kind": "rock", "x": -12.4, "z": -8.1, "yield": {"stone": 2}, "bonus": [{"item_id": "coal", "quantity": 1, "every_hits": 3, "offset": 2}]},
		{"id": "rock-coal-01", "zone": "wasteland", "kind": "rock", "x": 10.8, "z": 8.6, "yield": {"stone": 2}, "bonus": [{"item_id": "coal", "quantity": 1, "every_hits": 3, "offset": 2}]},
		{"id": "rock-copper-00", "zone": "wasteland", "kind": "rock", "x": -10.6, "z": 7.7, "yield": {"stone": 2}, "bonus": [{"item_id": "copper_ore", "quantity": 1, "every_hits": 2, "offset": 1}]},
		{"id": "rock-copper-01", "zone": "wasteland", "kind": "rock", "x": 12.3, "z": -7.5, "yield": {"stone": 2}, "bonus": [{"item_id": "copper_ore", "quantity": 1, "every_hits": 2, "offset": 1}]},
		{"id": "rock-iron-00", "zone": "wasteland", "kind": "rock", "x": -14.0, "z": 2.6, "yield": {"stone": 2}, "bonus": [{"item_id": "iron_ore", "quantity": 1, "every_hits": 3, "offset": 2}]},
		{"id": "rock-iron-01", "zone": "wasteland", "kind": "rock", "x": 14.2, "z": 3.3, "yield": {"stone": 2}, "bonus": [{"item_id": "iron_ore", "quantity": 1, "every_hits": 3, "offset": 2}]},
		{"id": "river-clay-00", "zone": "riverbank", "kind": "clay", "x": -15.1, "z": -1.8, "yield": {"clay": 2}, "bonus": []},
		{"id": "river-clay-01", "zone": "riverbank", "kind": "clay", "x": -15.0, "z": 2.0, "yield": {"clay": 2}, "bonus": []},
		{"id": "river-sand-00", "zone": "riverbank", "kind": "sand", "x": 15.0, "z": -2.2, "yield": {"sand": 2}, "bonus": []},
		{"id": "river-sand-01", "zone": "riverbank", "kind": "sand", "x": 15.1, "z": 1.7, "yield": {"sand": 2}, "bonus": []},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var definitions: Array[Dictionary] = []
	for row in rows:
		var jitter := Vector2(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.18, 0.18))
		definitions.append({
			"resource_id": str(row.id),
			"required_tool": "pickaxe",
			"hits": 3,
			"yield_per_hit": row.yield.duplicate(true),
			"bonus_table": row.bonus.duplicate(true),
			"respawn_days": 3,
			"position": Vector3(float(row.x) + jitter.x, 0.0, float(row.z) + jitter.y),
			"visual_kind": str(row.kind),
			"zone": str(row.zone),
		})
	return definitions


func generate_resource_nodes(terrain_source: Variant = null) -> int:
	var container := _resource_container()
	if container == null:
		return 0
	for definition in generated_resource_definitions():
		var resource_id := str(definition.resource_id)
		if container.get_node_or_null(NodePath(resource_id)) != null:
			continue
		var configured := definition.duplicate(true)
		var point: Vector3 = configured.position
		if terrain_source != null and terrain_source.has_method("get_height_at"):
			point.y = float(terrain_source.call("get_height_at", point.x, point.z))
		configured["position"] = point
		var resource = ResourceNodeScript.new()
		resource.name = resource_id
		if not resource.configure_resource(configured):
			resource.free()
			continue
		resource.build_fallback_visual()
		container.add_child(resource)
	return container.get_child_count()


func to_resource_dicts() -> Array[Dictionary]:
	var gatherables := _gatherable_nodes()
	gatherables.sort_custom(func(left: Node, right: Node) -> bool:
		return str(left.get("resource_id")) < str(right.get("resource_id"))
	)
	var records: Array[Dictionary] = []
	for gatherable in gatherables:
		records.append(gatherable.call("to_dict"))
	return records


func validate_resource_dicts(value: Variant) -> bool:
	if not value is Array:
		return false
	var known := {}
	for gatherable in _gatherable_nodes():
		var id := str(gatherable.get("resource_id"))
		if id.is_empty() or known.has(id):
			return false
		known[id] = gatherable
	if value.size() != known.size():
		return false
	var seen := {}
	for record in value:
		if not record is Dictionary:
			return false
		var id := str(record.get("resource_id", ""))
		if id.is_empty() or seen.has(id) or not known.has(id):
			return false
		var gatherable: Variant = known[id]
		if (
			not gatherable.has_method("validate_state_dict")
			or not bool(gatherable.call("validate_state_dict", record))
		):
			return false
		seen[id] = true
	return true


func restore_resource_dicts(value: Variant, loaded_day: int = 0) -> bool:
	if not validate_resource_dicts(value):
		return false
	var by_id := {}
	for gatherable in _gatherable_nodes():
		by_id[str(gatherable.get("resource_id"))] = gatherable
	for record in value:
		if not bool(by_id[str(record.resource_id)].call("from_dict", record)):
			return false
	for gatherable in by_id.values():
		gatherable.call("sync_day_cursor", loaded_day)
	return true


func initialize_resources_at_day(total_day: int) -> void:
	generate_resource_nodes(terrain if is_instance_valid(terrain) else null)
	for gatherable in _gatherable_nodes():
		gatherable.call("initialize_at_day", total_day)


func advance_resource_day(total_day: int) -> int:
	var respawned := 0
	for gatherable in _gatherable_nodes():
		if bool(gatherable.call("advance_day", total_day)):
			respawned += 1
	return respawned


func _resource_container() -> Node3D:
	var container := get_node_or_null("ResourceNodes") as Node3D
	if container != null:
		return container
	container = Node3D.new()
	container.name = "ResourceNodes"
	add_child(container)
	return container


func _gatherable_nodes() -> Array[Node]:
	var result: Array[Node] = []
	_collect_gatherables(self, result)
	return result


func _collect_gatherables(parent: Node, result: Array[Node]) -> void:
	for child in parent.get_children():
		if (
			child.has_method("can_gather")
			and child.has_method("to_dict")
			and child.has_method("from_dict")
		):
			result.append(child)
		_collect_gatherables(child, result)
