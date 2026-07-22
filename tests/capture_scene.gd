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
	var trees := get_nodes_in_group("tree_instance")
	print("TREES runtime=%d" % trees.size())
	if trees.size() != 28:
		push_error("Expected 28 runtime trees, got %d" % trees.size())
		quit(1)
		return
	var acceptance_tree: Node3D = trees[0]
	var original_tree_position := acceptance_tree.global_position
	var camera_direction := Vector2(
		camera.global_position.x - player.global_position.x,
		camera.global_position.z - player.global_position.z
	).normalized()
	acceptance_tree.global_position = Vector3(
		player.global_position.x + camera_direction.x * 0.8,
		original_tree_position.y,
		player.global_position.z + camera_direction.y * 0.8
	)
	for _frame in 12:
		await physics_frame
		await process_frame
	if not is_equal_approx(float(acceptance_tree.occlusion_target), 0.3):
		push_error("Camera ray did not mark aligned tree as occluded")
		quit(1)
		return
	print("OCCLUSION target=%.2f opacity=%.2f" % [acceptance_tree.occlusion_target, acceptance_tree.sprite.modulate.a])
	var player_shape: CollisionShape3D = player.get_node("CollisionShape3D")
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = player_shape.shape
	shape_query.transform = Transform3D(player.global_basis, Vector3(
		acceptance_tree.global_position.x,
		player.global_position.y,
		acceptance_tree.global_position.z
	))
	shape_query.collision_mask = 16
	shape_query.collide_with_areas = false
	shape_query.collide_with_bodies = true
	var trunk_hits: Array[Dictionary] = scene.get_world_3d().direct_space_state.intersect_shape(shape_query)
	if trunk_hits.is_empty():
		push_error("Player collision shape did not detect aligned tree trunk")
		quit(1)
		return
	print("COLLISION trunk_hits=%d" % trunk_hits.size())
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
	acceptance_tree.global_position = original_tree_position
	for _frame in 2:
		await physics_frame
		await process_frame
	if not is_equal_approx(float(acceptance_tree.occlusion_target), 1.0):
		push_error("Tree opacity target did not restore after clearing camera ray")
		quit(1)
		return
	print("OCCLUSION restored=%.2f" % acceptance_tree.occlusion_target)
	quit(0)
