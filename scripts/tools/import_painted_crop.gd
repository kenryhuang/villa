@tool
extends EditorScenePostImport

# Shared by all painted crop models in assets/models/crops/.
# Godot may preserve GLB COLOR_0 without enabling its material contribution.
# Bake this into the imported resource so editor and game use the same paint.
func _post_import(scene: Node) -> Object:
	for mesh_node in scene.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(surface) as StandardMaterial3D
			if material != null:
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = false
	return scene
