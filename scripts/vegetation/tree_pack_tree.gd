extends Node3D
## Reusable tree sample. Layer 1 blocks actors, layer 4 is canopy/camera/golf.
## Map placement must also register a blocker in the farm's grid navigation.

const WIND = preload("res://assets/models/vegetation/tree_pack/tree_wind.gdshader")
const ASSET_ROOT := "res://assets/models/vegetation/tree_pack/"
const SPECIES := ["golden_broadleaf", "green_columnar", "open_green"]
const HEIGHTS := [6.0, 6.4, 6.2]
static var _models: Dictionary = {}

@export_enum("auto", "golden_broadleaf", "green_columnar", "open_green") var species := "auto"
@export_range(-1, 2) var forced_lod := -1
@export var wind_enabled := true
@export var terrain_roots := false
var current_lod := -1
var lod_nodes: Array[Node3D] = []
var wind_materials: Array[ShaderMaterial] = []
var _elapsed := 0.0
var species_index := 0
var _root_plane := Vector3.ZERO

static func species_for_position(point: Vector3) -> int:
	return ("tree-pack-world-v1:%d:%d" % [roundi(point.x * 100), roundi(point.z * 100)]).hash() % SPECIES.size()

func _species_catalog() -> Array:
	return SPECIES

func _choose_species(point: Vector3) -> int:
	return species_for_position(point)

func _tree_height() -> float:
	return HEIGHTS[species_index]

func _model_path(level: int) -> String:
	return ASSET_ROOT + species + "_lod%d.glb" % level

func _ready() -> void:
	if species == "auto": species = _species_catalog()[_choose_species(global_position)]
	species_index = _species_catalog().find(species)
	assert(species_index >= 0)
	add_to_group("farm_world_trees")
	var height := _tree_height()
	if terrain_roots:
		var profile = preload("res://scripts/farm3d/terrain_profile.gd")
		var p := global_position
		var radius := global_basis.get_scale().abs().x
		var slope_x: float = (profile.surface_height(p.x+radius,p.z)-profile.surface_height(p.x-radius,p.z))/(2*radius)
		var slope_z: float = (profile.surface_height(p.x,p.z+radius)-profile.surface_height(p.x,p.z-radius))/(2*radius)
		var local_gradient := global_basis.transposed()*Vector3(slope_x,0,slope_z)/global_basis.get_scale().y
		_root_plane = Vector3(local_gradient.x,(profile.surface_height(p.x,p.z)-p.y)/global_basis.get_scale().y-.09,local_gradient.z)
	for part in ["Trunk", "Leaves"]:
		var material := ShaderMaterial.new()
		material.shader = WIND
		material.set_shader_parameter("tree_height", height)
		material.set_shader_parameter("foliage", part == "Leaves")
		wind_materials.append(material)
	lod_nodes.resize(3)
	set_wind_enabled(wind_enabled)
	_build_collisions()
	_elapsed = float(species_index) * .08
	var camera := get_viewport().get_camera_3d()
	update_lod(camera.global_position.distance_to(global_position) if camera != null else 100.0)

func _build_collisions() -> void:
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.5
	trunk.height = 3.0
	_add_body("TrunkCollision", trunk, Vector3(0, 1.5, 0), 1)
	var canopy := SphereShape3D.new()
	canopy.radius = 1.4
	_add_body("CanopyCollision", canopy, Vector3(0,4.1,0), 4)
	for offset in [Vector3(-1.1,4.2,0),Vector3(1.1,4.2,0),Vector3(0,4.3,-1.3),Vector3(0,4.3,1.3),Vector3(0,4.9,0)]:
		var volume := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 1.25 if offset.y<4.9 else .85
		volume.shape = shape
		volume.position = offset
		get_node("CanopyCollision").add_child(volume)

func _add_body(body_name: String, shape: Shape3D, offset: Vector3, layer: int) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	body.set_meta("golf_obstacle", true)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = offset
	body.add_child(collider)
	add_child(body)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0.0
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		update_lod(camera.global_position.distance_to(global_position))

func update_lod(camera_distance: float) -> void:
	camera_distance /= maxf(.1, global_basis.get_scale().abs().x)
	var level := forced_lod
	if level < 0:
		# Two metres of hysteresis avoids flickering near a transition.
		level = maxi(current_lod, 0)
		if camera_distance > 47.0:
			level = 2
		elif camera_distance < 18.0:
			level = 0
		elif level == 0 and camera_distance > 22.0:
			level = 1
		elif level == 2 and camera_distance < 43.0:
			level = 1
	level = clampi(level, 0, 2)
	if current_lod == level:
		return
	if lod_nodes[level] == null:
		var path := _model_path(level)
		if not _models.has(path): _models[path] = load(path) as PackedScene
		var model := (_models[path] as PackedScene).instantiate() as Node3D
		model.name = "LOD%d" % level
		add_child(model)
		lod_nodes[level] = model
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			# Preserve authored trunk textures when replacing the static material with wind.
			if str(mesh.name).begins_with("Trunk"):
				var source := mesh.get_active_material(0) as BaseMaterial3D
				if source != null and source.albedo_texture != null and source.normal_texture != null:
					wind_materials[0].set_shader_parameter("textured_bark", true)
					wind_materials[0].set_shader_parameter("bark_albedo", source.albedo_texture)
					wind_materials[0].set_shader_parameter("bark_normal", source.normal_texture)
			mesh.material_override = wind_materials[1 if str(mesh.name).begins_with("Leaves") else 0]
			if terrain_roots and str(mesh.name).begins_with("Trunk"): _fit_roots(mesh)
	current_lod = level
	for index in range(lod_nodes.size()):
		if lod_nodes[index] != null: lod_nodes[index].visible = index == current_lod

func _fit_roots(instance: MeshInstance3D) -> void:
	# Only the lower trunk is unique per placement. Leaves and model resources
	# remain shared; fitting is performed once per loaded LOD, never each frame.
	var fitted := ArrayMesh.new()
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		for i in vertices.size():
			var vertex := vertices[i]
			var weight := 1.0-smoothstep(0,.85,vertex.y)
			vertex.y += (_root_plane.y+_root_plane.x*vertex.x+_root_plane.z*vertex.z)*weight
			vertices[i] = vertex
		arrays[Mesh.ARRAY_VERTEX] = vertices
		fitted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		fitted.surface_set_material(surface,instance.mesh.surface_get_material(surface))
	instance.mesh = fitted

func set_wind_enabled(enabled: bool) -> void:
	wind_enabled = enabled
	for index in range(wind_materials.size()):
		wind_materials[index].set_shader_parameter("wind_strength", (0.04 if index == 1 else 0.018) if enabled else 0.0)
