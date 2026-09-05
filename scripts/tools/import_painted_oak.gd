@tool
extends EditorScenePostImport

## Preserves the authored COLOR_0 bark and foliage brushwork when Godot imports
## the standalone painted oak. glTF carries the colors, but its importer does
## not enable them as the albedo source on StandardMaterial3D by default.
func _post_import(scene: Node) -> Object:
	_apply_vertex_colors(scene)
	return scene

func _apply_vertex_colors(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface in mesh_instance.mesh.get_surface_count():
				var colors := mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR] as PackedColorArray
				var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
				if not colors.is_empty() and material != null:
					material.vertex_color_use_as_albedo = true
					material.vertex_color_is_srgb = false
	for child in node.get_children():
		_apply_vertex_colors(child)
