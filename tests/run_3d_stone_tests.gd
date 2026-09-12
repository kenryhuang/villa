extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func run() -> void:
	if "--farm-test" not in OS.get_cmdline_user_args(): quit(2); return
	var farm: Node3D = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	var stones: Node3D = farm.get_node("GroundStones")
	check(stones.rock_count == 3 and stones.pebble_count == 55, "All original 58 ground rocks replaced")
	var total := 0
	var batches := 0
	var colliders := 0
	for child in stones.get_children():
		if child is MultiMeshInstance3D:
			batches += 1
			total += child.multimesh.instance_count
			var mesh: Mesh = child.multimesh.mesh
			check(mesh.get_surface_count() == 1, "Each stone uses one baked PBR material")
			var mat: StandardMaterial3D = mesh.surface_get_material(0)
			check(mat.albedo_texture != null and mat.normal_enabled, "Albedo and baked normals imported")
		if child is StaticBody3D: colliders += 1
	check(total == 58 and batches <= 8 and colliders == 3, "Batch budget and large-rock collisions")
	var materials: Array[String] = []
	for node in farm.get_node("EnvironmentModel").find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			materials.append(node.mesh.surface_get_material(surface).resource_name)
	check("River stone" not in materials, "Original merged rock surface removed")
	check(materials.any(func(n): return "Footpath" in n) and materials.any(func(n): return "Fence" in n), "Path and fence preserved")
	await physics_frame; await physics_frame
	for point in [Vector3(-6,0,6), Vector3(11,0,1), Vector3(-11,0,-8)]:
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP*4, point + Vector3.UP*.05, 1)
		var hit := farm.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and hit.collider.get_parent() == stones, "Large stone blocks physics at %s" % point)
	var old_children := stones.get_child_count()
	stones.replace_environment_rocks(farm.get_node("EnvironmentModel"))
	check(stones.get_child_count() == old_children, "Repeated setup does not duplicate stones")
	if "--capture-stones" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440,960)
		farm.set_process(false)
		farm.farm_session.season.set_process(false)
		farm.farm_session.living_world.set_process(false)
		farm.player.set_physics_process(false)
		farm.get_node("FarmInteraction").hud.hide()
		var camera := Camera3D.new(); farm.add_child(camera); camera.current = true; camera.fov = 48
		for shot in [["world_rock", Vector3(-3,2.6,9.5), Vector3(-6,.35,6)],
			["world_stones", Vector3(20,13,22), Vector3(0,1,-3)],
			["world_light_stone", Vector3(14,2.1,4), Vector3(11,.2,1)]]:
			camera.position = shot[1]; camera.look_at(shot[2])
			for frame in 12: await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://docs/validation/stone-pack-previews/%s.png" % shot[0]) == OK, "Capture %s" % shot[0])
	farm.queue_free(); await process_frame; await process_frame
	print("3D STONES: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
