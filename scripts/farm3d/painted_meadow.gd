class_name PaintedMeadow
extends Node3D

## Lightweight painted grass for the 3D farm.  The grass is deliberately
## owned by the simulation grid: cultivated cells are masked here while soil
## and crop visuals remain authoritative in their own runtime systems.

const GRID_MIN_X := -18.0
const GRID_MAX_X := 18.0
const GRID_MIN_Z := -14.0
const GRID_MAX_Z := 14.0
const VISUAL_HALF_EXTENT := 22.0
const FARMLAND_STATE := 1
const PLANTED_STATE := 2
const TREE_TRUNKS := [
	Vector2(-8, -5), Vector2(-10, 2), Vector2(12, -9),
	Vector2(10, 5), Vector2(-5, -12), Vector2(5, -14),
]
const BOULDERS := [Vector2(-6, 6), Vector2(11, 1), Vector2(-11, -8)]
const GRASS_TEXTURE := preload("res://assets/terrain/grass-seamless-blended.png")

var _grid: GridSystem
var _instances: Array[Dictionary] = []
var _by_cell := {}
var _grass_meshes: Array[ArrayMesh] = []
var _grass_multimeshes: Array[MultiMesh] = []
var _grass_nodes: Array[MultiMeshInstance3D] = []
var _flower_mesh: ArrayMesh
var _flower_multimesh: MultiMesh
var _flower_node: MultiMeshInstance3D
var _flower_indices := {}


func configure(grid: GridSystem) -> void:
	_grid = grid
	if _grass_multimeshes.is_empty():
		_build_meadow()
	_refresh_all_cells()


func refresh_cell(gx: int, gz: int) -> void:
	if _grid == null:
		return
	var key := Vector2i(gx, gz)
	if not _by_cell.has(key):
		return
	var cell = _grid.get_cell(gx, gz)
	var hidden := cell != null and (int(cell.state) == FARMLAND_STATE or int(cell.state) == PLANTED_STATE)
	for record_index in _by_cell[key]:
		var index := int(record_index)
		var record: Dictionary = _instances[index]
		record.hidden = hidden
		_instances[index] = record
		_set_record_visible(record, not hidden)


func apply_ground_material(environment_model: Node) -> void:
	# The GLB keeps path, soil and rocks in separate material surfaces.  Replace
	# only its named meadow surfaces so the original hand-painted texture remains
	# crisp and tiled across the walkable, flat ground.
	if environment_model == null:
		return
	var grass_material := StandardMaterial3D.new()
	grass_material.resource_name = "Painted meadow ground"
	grass_material.albedo_texture = GRASS_TEXTURE
	grass_material.roughness = 1.0
	grass_material.uv1_scale = Vector3(12.0, 12.0, 12.0)
	for node in _find_meshes(environment_model):
		for surface in node.mesh.get_surface_count():
			var source = node.get_active_material(surface)
			if source != null and "meadow" in source.resource_name.to_lower():
				node.set_surface_override_material(surface, grass_material)


func _build_meadow() -> void:
	for child in get_children():
		child.queue_free()
	_instances.clear()
	_by_cell.clear()
	_flower_indices.clear()
	_grass_meshes.clear()
	_grass_multimeshes.clear()
	_grass_nodes.clear()
	for variant in 3:
		_grass_meshes.append(_make_grass_clump(variant))
	for variant in 3:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = false
		multi.mesh = _grass_meshes[variant]
		_grass_multimeshes.append(multi)
		var node := MultiMeshInstance3D.new()
		node.name = "GrassClumps%02d" % variant
		node.multimesh = multi
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_grass_nodes.append(node)
	_flower_mesh = _make_flower()
	_flower_multimesh = MultiMesh.new()
	_flower_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_flower_multimesh.mesh = _flower_mesh
	_flower_node = MultiMeshInstance3D.new()
	_flower_node.name = "SparseWildflowers"
	_flower_node.multimesh = _flower_multimesh
	_flower_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flower_node)

	var rng := RandomNumberGenerator.new()
	rng.seed = 9253
	var positions: Array[Vector2] = []
	# A jittered lattice reads as a lush meadow while retaining the inexpensive
	# shared meshes and giving each one-meter farm cell a stable set of blades.
	for z in range(-21, 22):
		for x in range(-21, 22):
			for sample in 2:
				var point := Vector2(x + rng.randf_range(-.42, .42), z + rng.randf_range(-.42, .42))
				if _can_grow_at(point):
					positions.append(point)
	for index in positions.size():
		var point := positions[index]
		var variant := index % 3
		var transform := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), Vector3(point.x, 0.012, point.y))
		# Scale only the clump geometry. Transform3D.scaled() would also move its
		# origin and desynchronise this exact point from its owning grid cell.
		transform.basis = transform.basis.scaled(Vector3.ONE * rng.randf_range(.78, 1.24))
		var record := {"variant": variant, "index": _instances.size(), "transform": transform, "flower": -1, "hidden": false}
		_instances.append(record)
		var key: Variant = _grid_key(point)
		if key != null:
			if not _by_cell.has(key):
				_by_cell[key] = []
			_by_cell[key].append(_instances.size() - 1)
		if index % 31 == 7:
			record.flower = _flower_indices.size()
			_flower_indices[_instances.size() - 1] = record.flower
	for variant in 3:
		var count := 0
		for record in _instances:
			if record.variant == variant:
				count += 1
		_grass_multimeshes[variant].instance_count = count
	var cursors := [0, 0, 0]
	for record_index in _instances.size():
		var record: Dictionary = _instances[record_index]
		var variant: int = record.variant
		record.multi_index = cursors[variant]
		cursors[variant] += 1
		_grass_multimeshes[variant].set_instance_transform(record.multi_index, record.transform)
		_instances[record_index] = record
	_flower_multimesh.instance_count = _flower_indices.size()
	for record_index in _flower_indices:
		var record: Dictionary = _instances[record_index]
		_flower_multimesh.set_instance_transform(record.flower, record.transform)


func _refresh_all_cells() -> void:
	for gz in range(28):
		for gx in range(36):
			refresh_cell(gx, gz)


func _set_record_visible(record: Dictionary, visible: bool) -> void:
	var transform: Transform3D = record.transform
	if not visible:
		# A valid transform moved below the foundation is more reliable than a
		# singular MultiMesh basis, which the renderer normalizes to identity.
		transform.origin = Vector3(transform.origin.x, -100.0, transform.origin.z)
	_grass_multimeshes[int(record.variant)].set_instance_transform(int(record.multi_index), transform)
	if int(record.flower) >= 0:
		_flower_multimesh.set_instance_transform(int(record.flower), transform)


func _grid_key(point: Vector2):
	if point.x < GRID_MIN_X or point.x >= GRID_MAX_X or point.y < GRID_MIN_Z or point.y >= GRID_MAX_Z:
		return null
	return Vector2i(floori(point.x - GRID_MIN_X), floori(point.y - GRID_MIN_Z))


func _can_grow_at(point: Vector2) -> bool:
	var path_x := -2.8 + sin(point.y * .14) * 1.3
	if absf(point.x - path_x) < 1.32:
		return false
	for trunk in TREE_TRUNKS:
		if point.distance_to(trunk) < 1.05:
			return false
	for boulder in BOULDERS:
		if point.distance_to(boulder) < 1.2:
			return false
	# The north fence is intentionally left readable through its base.
	return not (point.x > .35 and point.x < 10.35 and absf(point.y + 9.66) < .38)


func _make_grass_clump(variant: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 411 + variant * 907
	var palette := [Color("#668b37"), Color("#7fa54b"), Color("#9cbd5e"), Color("#5f8136")]
	for blade_index in 9 + variant:
		var angle := rng.randf_range(0.0, TAU)
		var direction := Vector2(cos(angle), sin(angle))
		var side := Vector2(-direction.y, direction.x)
		var base := direction * rng.randf_range(0.0, .095)
		var height := rng.randf_range(.12, .25) * (1.0 + variant * .08)
		var width := rng.randf_range(.016, .029)
		var start := vertices.size()
		for segment in 5:
			var t := float(segment) / 4.0
			var bend := direction * (t * t * rng.randf_range(.08, .17))
			var center := Vector3(base.x + bend.x, height * sin(t * PI * .54), base.y + bend.y)
			var half_width := width * sin(t * PI) * .75
			vertices.append(center + Vector3(side.x * half_width, 0, side.y * half_width))
			vertices.append(center - Vector3(side.x * half_width, 0, side.y * half_width))
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)
			colors.append(palette[(blade_index + variant) % palette.size()])
			colors.append(palette[(blade_index + variant) % palette.size()])
			uvs.append(Vector2(0, t))
			uvs.append(Vector2(1, t))
			if segment > 0:
				var previous := start + (segment - 1) * 2
				var current := start + segment * 2
				indices.append_array([previous, current, current + 1, previous, current + 1, previous + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _grass_material())
	return mesh


func _make_flower() -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, .24, 0), Vector3(-.05, .22, 0), Vector3(.05, .22, 0), Vector3(0, .22, -.05), Vector3(0, .22, .05)])
	var indices := PackedInt32Array([0, 1, 2, 0, 3, 1, 1, 4, 3, 1, 2, 5])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#f2d36c")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


func _grass_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;
void vertex() {
	float breeze = sin(TIME * 1.35 + float(INSTANCE_ID) * .37 + VERTEX.y * 6.0) * VERTEX.y * .11;
	VERTEX.x += breeze;
	VERTEX.z += cos(TIME * 1.05 + float(INSTANCE_ID) * .21) * VERTEX.y * .055;
}
void fragment() { ALBEDO = COLOR.rgb; ROUGHNESS = .96; EMISSION = COLOR.rgb * .05; }
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		meshes.append_array(_find_meshes(child))
	return meshes
