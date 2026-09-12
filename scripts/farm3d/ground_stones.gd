extends Node3D

## Replace only the authored River stone surface; paths and fences retain their meshes.
const MODELS := [
	preload("res://assets/models/environment/scanned_stones/stone_01.glb"),
	preload("res://assets/models/environment/scanned_stones/stone_02.glb"),
	preload("res://assets/models/environment/scanned_stones/stone_03.glb"),
	preload("res://assets/models/environment/scanned_stones/stone_04.glb"),
]
const PLACEMENTS := preload("res://assets/models/environment/scanned_stones/placements.tres")

var rock_count := 0
var pebble_count := 0

func replace_environment_rocks(environment: Node) -> void:
	if get_child_count() > 0: return
	var placements: Array = PLACEMENTS.get_meta("placements")
	var buckets: Array = []
	var meshes: Array[Mesh] = []
	for model in MODELS:
		var sample: Node = model.instantiate()
		var large_mesh: Mesh
		var small_mesh: Mesh
		for mesh_node in sample.find_children("*", "MeshInstance3D", true, false):
			if str(mesh_node.name).begins_with("Rock"): large_mesh = mesh_node.mesh
			if str(mesh_node.name).begins_with("Pebble"): small_mesh = mesh_node.mesh
		assert(large_mesh != null and small_mesh != null, "Missing stone mesh variant")
		meshes.append(large_mesh); meshes.append(small_mesh)
		buckets.append([]); buckets.append([])
		sample.free()
	for placement in placements:
		var point := Vector3(float(placement.position[0]), 0, float(placement.position[2]))
		var large: bool = placement.large
		var seed_value := absi(("farm-stones:%s:%s" % [point.x, point.z]).hash())
		var species := seed_value % MODELS.size()
		# Deliberate silhouettes at the three existing landmarks; small stones mix all four.
		if large: species = 1 if point.x < -10 else (2 if point.x < 0 else 3)
		var size := float(placement.width) / 2.0
		point.y = Farm3DTerrainProfile.surface_height(point.x, point.z) - size * .025
		var basis := Basis(Vector3.UP, float(seed_value % 6283) / 1000.0).scaled(Vector3.ONE * size)
		var transform := Transform3D(basis, point)
		var bucket := species * 2 + (0 if large else 1)
		buckets[bucket].append(transform)
		if large:
			rock_count += 1
			var body := StaticBody3D.new()
			body.name = "RockCollision%d" % rock_count
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta("golf_obstacle", true)
			body.transform = transform
			var shape := CollisionShape3D.new()
			shape.shape = meshes[bucket].create_convex_shape(true, true)
			body.add_child(shape); add_child(body)
		else: pebble_count += 1
	for index in buckets.size():
		if buckets[index].is_empty(): continue
		var batch := MultiMeshInstance3D.new()
		batch.name = "Stone%d%s" % [index / 2 + 1, "Rocks" if index % 2 == 0 else "Pebbles"]
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh = meshes[index]
		batch.multimesh.instance_count = buckets[index].size()
		for instance in buckets[index].size():
			batch.multimesh.set_instance_transform(instance, buckets[index][instance])
		# Small ground details do not need shadow passes or drawing across the whole map.
		if index % 2 == 1:
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			batch.visibility_range_end = 65
			batch.visibility_range_end_margin = 5
		add_child(batch)
	for node in environment.find_children("*", "MeshInstance3D", true, false):
		var cleaned: ArrayMesh = node.mesh.duplicate()
		var changed := false
		for surface in range(cleaned.get_surface_count() - 1, -1, -1):
			var mat := cleaned.surface_get_material(surface)
			if mat != null and mat.resource_name == "River stone":
				cleaned.surface_remove(surface)
				changed = true
		if changed: node.mesh = cleaned
