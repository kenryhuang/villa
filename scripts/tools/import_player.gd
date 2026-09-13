@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	# Soft skin response suits the painted farm art. The main scene uses a hard
	# directional shadow map whose tiny facial shadows otherwise look like ink
	# under the eyelids and lips. Retain lighting and the character's cast shadow.
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for index in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(index) as StandardMaterial3D
			if material == null: continue
			if "warm face and skin" in material.resource_name:
				material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
				material.disable_receive_shadows = true
			elif "soft denim" in material.resource_name:
				# Prevent broad self-shadow bands on the smooth skinned trouser
				# surface in Compatibility rendering; keep normal diffuse shading
				# and the character's cast shadow on the ground.
				material.disable_receive_shadows = true
	return scene
