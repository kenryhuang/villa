extends Node3D
## Three trial replacements use existing tree positions and navigation reserves.
const MODEL = preload("res://assets/models/vegetation/mawais_tree/tree.glb")
const WIND = preload("res://assets/models/vegetation/mawais_tree/tree_wind.gdshader")
static var _materials: Dictionary = {}

func _ready() -> void:
	add_to_group("farm_world_trees")
	add_to_group("mawais_trial_trees")
	var model := MODEL.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 150.0
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if not _materials.has(source.resource_name):
				var material := ShaderMaterial.new()
				material.shader = WIND
				material.set_shader_parameter("tint", source.albedo_color)
				material.set_shader_parameter("foliage", source.resource_name == "Leaves")
				material.set_shader_parameter("textured", source.albedo_texture != null)
				if source.albedo_texture != null:
					material.set_shader_parameter("albedo_map", source.albedo_texture)
				_materials[source.resource_name] = material
			mesh.set_surface_override_material(surface, _materials[source.resource_name])
	# Preserve the previous trunk collision envelope and its matching grid reserve.
	var trunk := CylinderShape3D.new()
	trunk.radius = .5
	trunk.height = 3.0
	_add_body("TrunkCollision", trunk, Vector3(0,1.5,0), 1)
	var crown := SphereShape3D.new()
	crown.radius = 1.45
	_add_body("CanopyCollision", crown, Vector3(0,4.25,0), 4)
	for position in [Vector3(-1.7,3.6,0),Vector3(1.7,3.6,0),Vector3(0,3.6,-1.8),Vector3(0,3.6,1.8)]:
		var collider := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 1.15
		collider.shape = shape
		collider.position = position
		get_node("CanopyCollision").add_child(collider)

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
