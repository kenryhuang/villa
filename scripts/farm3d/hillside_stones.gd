extends Node3D
## A small deterministic scatter of the existing scanned stone meshes.
const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const Shrubs = preload("res://scripts/farm3d/landscape_shrubs.gd")
const Stones = preload("res://scripts/farm3d/ground_stones.gd")
const REGIONS := [
	{"id":"hills", "area":Rect2(-68,-32,40,86), "count":24},
	{"id":"mountains", "area":Rect2(-68,-70,88,30), "count":12},
]
var placements: Array[Dictionary] = []
var _meshes: Array[Mesh] = []
var _bases: Array[PackedVector3Array] = []

func configure(grid: Farm3DFlatGrid, shrubs: Node3D) -> void:
	if not _meshes.is_empty(): return
	for model in Stones.MODELS:
		var sample: Node = model.instantiate()
		for part in sample.find_children("*", "MeshInstance3D", true, false):
			if not str(part.name).begins_with("Rock"): continue
			_meshes.append(part.mesh)
			var base := PackedVector3Array()
			for surface in part.mesh.get_surface_count():
				for vertex: Vector3 in part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					if vertex.y < .012: base.append(vertex)
			assert(not base.is_empty(), "Scanned stone needs its closed flat base")
			_bases.append(base)
		sample.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 886620913
	for region in REGIONS:
		var count := 0
		for attempt in 2400:
			if count >= int(region.count): break
			var area: Rect2 = region.area
			var point := Vector2(rng.randf_range(area.position.x,area.end.x),rng.randf_range(area.position.y,area.end.y))
			if not Shrubs.suitable(point,region.id,grid): continue
			if placements.any(func(p): return point.distance_to(Vector2(p.position.x,p.position.z)) < 3.2): continue
			if shrubs.placements.any(func(p): return point.distance_to(Vector2(p.position.x,p.position.z)) < 1.4): continue
			var species := rng.randi_range(0,3)
			# Imported meshes have a two-metre horizontal extent: 0.4–0.95 m here.
			var size := rng.randf_range(.20,.475)
			var basis := (Basis(Quaternion(Vector3.UP,Profile.surface_normal(point.x,point.y))) * Basis(Vector3.UP,rng.randf_range(0,TAU))).scaled(Vector3.ONE*size)
			# Fit every bottom vertex beneath the actual triangulated terrain,
			# including where the footprint crosses terrain triangle boundaries.
			var height := INF
			for vertex in _bases[species]:
				var offset := basis * vertex
				height = minf(height,Profile.surface_height(point.x+offset.x,point.y+offset.z)-offset.y)
			placements.append({"region":region.id,"species":species,"basis":basis,"position":Vector3(point.x,height-.02,point.y)})
			count += 1
	_build_batches()

func _build_batches() -> void:
	var buckets := {}
	for p in placements:
		var key := Vector3i(floori(p.position.x/32),floori(p.position.z/32),p.species)
		if not buckets.has(key): buckets[key] = []
		buckets[key].append(p)
	for key: Vector3i in buckets:
		var batch := MultiMeshInstance3D.new()
		batch.name = "SlopeStones_%d_%d_%d" % [key.x,key.y,key.z]
		batch.position = Vector3(key.x*32+16,0,key.y*32+16)
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh = _meshes[key.z]
		batch.multimesh.instance_count = buckets[key].size()
		for i in buckets[key].size():
			var p: Dictionary = buckets[key][i]
			batch.multimesh.set_instance_transform(i,Transform3D(p.basis,p.position-batch.position))
		batch.visibility_range_end = 100
		batch.visibility_range_end_margin = 5
		add_child(batch)
