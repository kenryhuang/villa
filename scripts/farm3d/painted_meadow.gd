class_name PaintedMeadow
extends Node3D

## Keep the original painted grass texture without decorative 3D weeds.
const GRASS_TEXTURE := preload("res://assets/terrain/grass-seamless-blended.png")


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



func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		meshes.append_array(_find_meshes(child))
	return meshes
