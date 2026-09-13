extends Node3D
## Two reversible visual patches. Ground collision and grid state remain authoritative.
const ROOT := "res://assets/models/vegetation/photoreal_grass/"
const WIND = preload("res://assets/models/vegetation/photoreal_grass/grass_wind.gdshader")
const PATCHES := [
	{"center": Vector2(-7.0,3.5), "radii": Vector2(2.7,2.0)},
	{"center": Vector2(11.0,-4.5), "radii": Vector2(2.4,2.2)},
]
var placements: Array[Dictionary] = []
var _grid: Farm3DFlatGrid
var _meshes: Dictionary = {}
var _material: ShaderMaterial
var _pending := false

func configure(grid: Farm3DFlatGrid) -> void:
	_grid = grid
	_material = ShaderMaterial.new()
	_material.shader = WIND
	for variant in 3:
		for lod in 2:
			var model := (load(ROOT + "tuft_%d_lod%d.glb" % [variant,lod]) as PackedScene).instantiate()
			var mesh: MeshInstance3D = model.find_children("*","MeshInstance3D",true,false)[0]
			_meshes[Vector2i(variant,lod)] = mesh.mesh
			model.free()
	_rebuild()
	EventBus.cell_state_changed.connect(_on_cell_state_changed)

func suitable(point: Vector2) -> bool:
	if Farm3DTerrainProfile.slope_at(point.x,point.y) > .18: return false
	# A tuft can overhang its origin; clear its full footprint around tilled ground.
	for offset in [Vector2.ZERO,Vector2(-.34,0),Vector2(.34,0),Vector2(0,-.34),Vector2(0,.34),Vector2(-.25,-.25),Vector2(.25,.25),Vector2(.25,-.25),Vector2(-.25,.25)]:
		var p: Vector2 = point + offset
		var cell := _grid.world_to_grid(p.x,p.y)
		var data := _grid.get_cell(cell.x,cell.y)
		if data == null or data.state != GridCell.State.WASTELAND: return false
		if not _grid.is_navigation_cell_walkable(cell): return false
	return true

func _on_cell_state_changed(gx: int, gz: int, _new_state: int) -> void:
	var point := _grid.grid_to_world(gx,gz)
	for patch in PATCHES:
		if ((point-patch.center)/(patch.radii+Vector2.ONE)).length() < 1.0:
			if not _pending:
				_pending = true
				_rebuild.call_deferred()
			return

func _rebuild() -> void:
	_pending = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	placements.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 698680913
	var buckets := {}
	for patch_index in PATCHES.size():
		var patch: Dictionary = PATCHES[patch_index]
		for zi in range(-12,13):
			for xi in range(-13,14):
				var offset := Vector2(xi*.23+rng.randf_range(-.10,.10),zi*.23+rng.randf_range(-.10,.10))
				var point: Vector2 = patch.center + offset
				var radial: float = (offset/patch.radii).length()
				var probability := .70 * (1.0-smoothstep(.65,1.0,radial))
				var keep := rng.randf() < probability
				var yaw := rng.randf_range(0,TAU)
				var size := rng.randf_range(.78,1.15)
				var variant := rng.randi_range(0,2)
				if not keep or not suitable(point): continue
				var y := Farm3DTerrainProfile.surface_height(point.x,point.y)-.012
				var normal := Vector3(Farm3DTerrainProfile.surface_height(point.x-.3,point.y)-Farm3DTerrainProfile.surface_height(point.x+.3,point.y),.6,
					Farm3DTerrainProfile.surface_height(point.x,point.y-.3)-Farm3DTerrainProfile.surface_height(point.x,point.y+.3)).normalized()
				var basis := (Basis(Quaternion(Vector3.UP,normal))*Basis(Vector3.UP,yaw)).scaled(Vector3.ONE*size)
				var placement := {"position": Vector3(point.x,y,point.y), "basis":basis, "patch":patch_index, "variant":variant}
				placements.append(placement)
				var key := Vector2i(patch_index,variant)
				if not buckets.has(key): buckets[key] = []
				buckets[key].append(placement)
	for key: Vector2i in buckets:
		var center: Vector2 = PATCHES[key.x].center
		for lod in 2:
			var batch := MultiMeshInstance3D.new()
			batch.name = "Patch%d_Variant%d_LOD%d" % [key.x,key.y,lod]
			batch.position = Vector3(center.x,0,center.y)
			batch.multimesh = MultiMesh.new()
			batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			batch.multimesh.mesh = _meshes[Vector2i(key.y,lod)]
			batch.multimesh.instance_count = buckets[key].size()
			for i in buckets[key].size():
				var p: Dictionary = buckets[key][i]
				batch.multimesh.set_instance_transform(i,Transform3D(p.basis,p.position-batch.position))
			batch.material_override = _material
			batch.visibility_range_begin = 0 if lod==0 else 18
			batch.visibility_range_end = 18 if lod==0 else 46
			if lod==1: batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(batch)
