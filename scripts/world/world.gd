class_name GameWorld
extends Node3D

const ResourceNodeScript = preload("res://scripts/world/resource_node.gd")
const WORLD_GENERATION_SEED := 0x56494c4c41
const WATER_REGIONS: Array[Rect2] = [
	Rect2(-16.0, -5.0, 1.0, 10.0),
	Rect2(15.0, -5.0, 1.0, 10.0),
]
const WATER_SURFACE_LIFT := 0.035

@onready var terrain: TerrainBuilder = $Terrain
@onready var road: RoadBuilder = $Road
@onready var vegetation: VegetationBuilder = $Vegetation
@onready var resource_nodes: Node3D = $ResourceNodes
@onready var water: Node3D = $Water


func _ready() -> void:
	if not terrain.build():
		push_error("World initialization stopped because terrain failed")
		return
	_build_water_fallback()
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


func get_blocked_regions() -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	for rect in WATER_REGIONS:
		regions.append({
			"state": GridCell.State.WATER,
			"rect": rect,
		})
	return regions


static func generated_resource_definitions(
	seed: int = WORLD_GENERATION_SEED
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{"id": "stone-00", "zone": "common_mine", "type": "stone", "x": -14.2, "z": 8.0},
		{"id": "stone-01", "zone": "common_mine", "type": "stone", "x": -11.2, "z": 9.2},
		{"id": "stone-02", "zone": "common_mine", "type": "stone", "x": -8.4, "z": 10.7},
		{"id": "stone-03", "zone": "common_mine", "type": "stone", "x": -13.2, "z": 5.5},
		{"id": "coal-00", "zone": "common_mine", "type": "coal", "x": -9.2, "z": 6.0},
		{"id": "coal-01", "zone": "common_mine", "type": "coal", "x": -14.5, "z": 11.2},
		{"id": "copper-00", "zone": "common_mine", "type": "copper_ore", "x": -7.4, "z": 7.7},
		{"id": "copper-01", "zone": "common_mine", "type": "copper_ore", "x": -11.8, "z": 11.7},
		{"id": "iron-00", "zone": "common_mine", "type": "iron_ore", "x": -14.1, "z": 3.2},
		{"id": "iron-01", "zone": "common_mine", "type": "iron_ore", "x": -10.5, "z": 3.8},
		{"id": "silver-00", "zone": "rare_mine", "type": "silver_ore", "x": 10.0, "z": 11.5},
		{"id": "gold-00", "zone": "rare_mine", "type": "gold_ore", "x": 12.8, "z": 11.2},
		{"id": "crystal-00", "zone": "rare_mine", "type": "crystal", "x": 15.4, "z": 11.7},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var definitions: Array[Dictionary] = []
	for row in rows:
		var jitter := Vector2(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.18, 0.18))
		definitions.append({
			"resource_id": str(row.id),
			"resource_type": str(row.type),
			"position": Vector3(float(row.x) + jitter.x, 0.0, float(row.z) + jitter.y),
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


func get_gatherable_nodes() -> Array[Node]:
	return _gatherable_nodes()


func validate_resource_dicts(value: Variant, loaded_day: int = -1) -> bool:
	return normalize_resource_dicts(value, loaded_day) is Array


func normalize_resource_dicts(value: Variant, loaded_day: int = -1) -> Variant:
	if not value is Array:
		return null
	var known := {}
	for gatherable in _gatherable_nodes():
		var id := str(gatherable.get("resource_id"))
		if id.is_empty() or known.has(id):
			return null
		known[id] = gatherable
	var normalized_by_id := {}
	for record in value:
		if not record is Dictionary:
			return null
		var id := str(record.get("resource_id", ""))
		if id.is_empty() or normalized_by_id.has(id) or not known.has(id):
			return null
		var gatherable: Variant = known[id]
		if (
			not gatherable.has_method("normalize_state_dict")
			or not gatherable.has_method("default_state_dict")
		):
			return null
		var normalized: Dictionary = gatherable.call(
			"normalize_state_dict", record, loaded_day
		)
		if normalized.is_empty():
			return null
		normalized_by_id[id] = normalized
	var ids: Array = known.keys()
	ids.sort()
	var complete: Array[Dictionary] = []
	for id in ids:
		if normalized_by_id.has(id):
			complete.append(normalized_by_id[id])
		else:
			complete.append(known[id].call("default_state_dict"))
	return complete


func restore_resource_dicts(value: Variant, loaded_day: int = 0) -> bool:
	var normalized_value: Variant = normalize_resource_dicts(value, loaded_day)
	if not normalized_value is Array:
		return false
	var normalized: Array = normalized_value as Array
	var by_id := {}
	for gatherable in _gatherable_nodes():
		by_id[str(gatherable.get("resource_id"))] = gatherable
	var before: Array[Dictionary] = to_resource_dicts()
	for record in normalized:
		if not bool(by_id[str(record.resource_id)].call("from_dict", record)):
			for previous in before:
				by_id[str(previous.resource_id)].call("from_dict", previous)
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
		var is_gatherable := (
			child.has_method("can_gather")
			and child.has_method("to_dict")
			and child.has_method("from_dict")
		)
		if is_gatherable and _has_property(child, "gathering_enabled"):
			is_gatherable = bool(child.get("gathering_enabled"))
		if is_gatherable:
			result.append(child)
		_collect_gatherables(child, result)


func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _build_water_fallback() -> void:
	if water == null or water.get_child_count() > 0:
		return
	for index in range(WATER_REGIONS.size()):
		var rect := WATER_REGIONS[index]
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "WaterRegion%02d" % index
		var plane := PlaneMesh.new()
		plane.size = rect.size
		mesh_instance.mesh = plane
		var center := rect.get_center()
		mesh_instance.position = Vector3(
			center.x,
			terrain.get_height_at(center.x, center.y) + WATER_SURFACE_LIFT,
			center.y
		)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.24, 0.56, 0.68, 0.72)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.35
		material.metallic = 0.05
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		water.add_child(mesh_instance)
