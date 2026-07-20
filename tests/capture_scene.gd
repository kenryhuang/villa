extends SceneTree

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in 8:
		await process_frame
	var terrain_mesh: MeshInstance3D = scene.get_node("World/Terrain/TerrainMesh")
	var road_mesh: MeshInstance3D = scene.get_node("World/Road/RoadMesh")
	var player: Node3D = scene.get_node("Actors/Player")
	var camera: Camera3D = scene.get_node("CameraRig/Camera3D")
	print("TERRAIN surfaces=%d aabb=%s visible=%s" % [terrain_mesh.mesh.get_surface_count(), terrain_mesh.get_aabb(), terrain_mesh.is_visible_in_tree()])
	print("ROAD surfaces=%d aabb=%s visible=%s" % [road_mesh.mesh.get_surface_count(), road_mesh.get_aabb(), road_mesh.is_visible_in_tree()])
	var terrain_arrays := terrain_mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = terrain_arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = terrain_arrays[Mesh.ARRAY_INDEX]
	var edge_ab: Vector3 = vertices[indices[1]] - vertices[indices[0]]
	var edge_ac: Vector3 = vertices[indices[2]] - vertices[indices[0]]
	print("TERRAIN first_indices=%s normal=%s" % [indices.slice(0, 3), edge_ab.cross(edge_ac).normalized()])
	print("PLAYER=%s CAMERA=%s FORWARD=%s" % [player.global_position, camera.global_position, -camera.global_basis.z])
	for npc in scene.get_node("Actors/Npcs").get_children():
		print("NPC %s at %s" % [npc.name, npc.global_position])
	await RenderingServer.frame_post_draw
	var output_path := "/private/tmp/villa-acceptance.png"
	var error := root.get_texture().get_image().save_png(output_path)
	if error != OK:
		push_error("Unable to save acceptance screenshot: %s" % error_string(error))
		quit(1)
		return
	print("CAPTURED: %s" % output_path)
	quit(0)
