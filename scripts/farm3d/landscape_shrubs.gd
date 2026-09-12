extends Node3D
## Low decorative shrubs: deterministic, rooted to slopes, spatially batched.
const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const WIND = preload("res://assets/models/vegetation/tree_pack/tree_wind.gdshader")
const MODELS := [
	[preload("res://assets/models/vegetation/tree_pack/meadow_shrub_lod0.glb"), preload("res://assets/models/vegetation/tree_pack/meadow_shrub_lod2.glb")],
	[preload("res://assets/models/vegetation/tree_pack/sage_shrub_lod0.glb"), preload("res://assets/models/vegetation/tree_pack/sage_shrub_lod2.glb")],
]
const REGIONS := [
	{"id":"hills", "area":Rect2(-71,-34,46,91), "count":64},
	{"id":"mountains", "area":Rect2(-70,-73,93,35), "count":36},
	{"id":"golf", "area":Rect2(-162,-69,76,202), "count":32},
]
var placements: Array[Dictionary] = []
var batch_count := 0

func configure(grid: Farm3DFlatGrid) -> void:
	if not placements.is_empty(): return
	var rng := RandomNumberGenerator.new()
	rng.seed = 780710911
	for region in REGIONS:
		var count := 0
		for attempt in 1800:
			if count >= int(region.count): break
			var area: Rect2 = region.area
			var point := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
			if not suitable(point, str(region.id), grid): continue
			if placements.any(func(p): return point.distance_to(Vector2(p.position.x, p.position.z)) < 2.6): continue
			var size := rng.randf_range(.75, 1.1) * (.65 if region.id == "golf" else 1.0)
			var normal := Vector3(Profile.surface_height(point.x-.5,point.y)-Profile.surface_height(point.x+.5,point.y), 1,
				Profile.surface_height(point.x,point.y-.5)-Profile.surface_height(point.x,point.y+.5)).normalized()
			var up := Vector3.UP.lerp(normal, .65).normalized()
			var basis := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, rng.randf_range(0,TAU))
			placements.append({"region":region.id, "species":rng.randi_range(0,1), "scale":size,
				"position":Vector3(point.x,Profile.surface_height(point.x,point.y)-.10*size,point.y), "basis":basis.scaled(Vector3.ONE*size)})
			count += 1
	_build_batches()

static func suitable(point: Vector2, region: String, grid: Farm3DFlatGrid) -> bool:
	if Profile.is_water(point.x,point.y) or Profile.is_fishing_shore(point.x,point.y): return false
	if Profile.surface_height(point.x,point.y) < .3: return false
	var slope := Profile.slope_at(point.x,point.y)
	if slope > .85: return false
	if region != "golf" and slope < .24: return false
	if region == "golf":
		if Profile.Golf.surface(point) != "rough": return false
		for hole in Profile.Golf.HOLES:
			if Profile.Golf.route_distance(point,hole) < 8 or point.distance_to(hole.tee) < 10 or point.distance_to(hole.cup) < 10: return false
		for pond in Profile.Golf.PONDS:
			if ((point-pond.center)/(pond.radii+Vector2.ONE*3)).length() < 1.5: return false
		if point.distance_to(Profile.Golf.ENTRANCE) < 8: return false
	for tree in Profile.TREES:
		if point.distance_to(tree) < 2.3: return false
	var cell := grid.world_to_grid(point.x,point.y)
	var data := grid.get_cell(cell.x,cell.y)
	if data == null or data.state != GridCell.State.DECORATION: return false
	# Keep clear of any saved planting/buildings beside decorative slope cells.
	for dz in range(-2,3):
		for dx in range(-2,3):
			var neighbor := grid.get_cell(cell.x+dx,cell.y+dz)
			if neighbor != null and neighbor.state in [GridCell.State.FARMLAND,GridCell.State.PLANTED,GridCell.State.BUILDING,GridCell.State.ROAD]: return false
	return true

func _build_batches() -> void:
	var meshes := {}
	var materials := {}
	for species in 2:
		for level in 2:
			var model: Node = MODELS[species][level].instantiate()
			for mesh in model.find_children("*","MeshInstance3D",true,false):
				var part := 1 if str(mesh.name).begins_with("Leaves") else 0
				meshes[Vector3i(species,level,part)] = mesh.mesh
			model.free()
		for part in 2:
			var mat := ShaderMaterial.new()
			mat.shader = WIND
			mat.set_shader_parameter("foliage", part == 1)
			mat.set_shader_parameter("tree_height", 1.25 if species == 0 else 1.05)
			mat.set_shader_parameter("wind_strength", .025 if part == 1 else .008)
			materials[Vector2i(species,part)] = mat
	var buckets := {}
	for placement in placements:
		var point: Vector3 = placement.position
		var key := Vector3i(floori(point.x/40),floori(point.z/40),int(placement.species))
		if not buckets.has(key): buckets[key] = []
		buckets[key].append(placement)
	for key: Vector3i in buckets:
		var center := Vector3(key.x*40+20,0,key.y*40+20)
		for level in 2:
			for part in 2:
				var batch := MultiMeshInstance3D.new()
				batch.name = "Shrubs_%d_%d_%d_LOD%d_%d" % [key.x,key.y,key.z,level,part]
				batch.position = center
				batch.multimesh = MultiMesh.new()
				batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
				batch.multimesh.mesh = meshes[Vector3i(key.z,level,part)]
				batch.multimesh.instance_count = buckets[key].size()
				for index in buckets[key].size():
					var p: Dictionary = buckets[key][index]
					batch.multimesh.set_instance_transform(index,Transform3D(p.basis,p.position-center))
				batch.material_override = materials[Vector2i(key.z,part)]
				batch.visibility_range_begin = 0 if level == 0 else 45
				batch.visibility_range_end = 45 if level == 0 else 110
				if level == 1: batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(batch)
				batch_count += 1
