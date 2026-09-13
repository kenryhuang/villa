@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	for mesh: MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material != null and material.resource_name == "T1 Needle Leaves":
				# Explicitly use COLOR_0 with the active renderer's colour encoding.
				var needles := ShaderMaterial.new()
				needles.shader = preload("res://assets/models/vegetation/t1_tree/needle_preview.gdshader")
				needles.resource_name = "T1 Needle Leaves"
				mesh.set_surface_override_material(surface,needles)
	return scene
