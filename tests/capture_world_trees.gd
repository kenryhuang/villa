extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--farm-test" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1440, 960)
	var farm: Node3D = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.set_process(false)
	farm.farm_session.season.set_process(false)
	farm.farm_session.living_world.set_process(false)
	farm.farm_session.player.set_physics_process(false)
	farm.get_node("FarmInteraction").set_process(false)
	farm.get_node("FarmInteraction").hud.hide()
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.current = true
	camera.far = 500
	camera.fov = 55
	for shot in [
		["world_farm", Vector3(21, 14, 25), Vector3(0, 2, -4)],
		["world_grove", Vector3(-20, 14, 42), Vector3(-44, 4, 14)],
		["world_golf", Vector3(-100, 18, 82), Vector3(-121, 8, 66)],
	]:
		camera.position = shot[1]
		camera.look_at(shot[2])
		for tree in get_nodes_in_group("farm_world_trees"):
			tree.update_lod(camera.global_position.distance_to(tree.global_position))
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://docs/validation/diverse-trees/" + shot[0] + ".png"
		if root.get_texture().get_image().save_png(path) != OK: quit(1); return
		print("WORLD TREE CAPTURE ", path)
	var detail_tree: Node3D = get_nodes_in_group("farm_world_trees").filter(func(t): return t.species == "warm_oak")[0]
	detail_tree.forced_lod = 0; detail_tree.update_lod(0)
	var slope_tree: Node3D = get_nodes_in_group("farm_world_trees").filter(func(t): return is_equal_approx(t.global_position.x,-120))[0]
	slope_tree.forced_lod = 0; slope_tree.update_lod(0)
	for shot in [
		["leaf_detail",detail_tree.global_position+Vector3(3,4.5,4.8),detail_tree.global_position+Vector3(.8,4.0,.6)],
		["slope_roots",slope_tree.global_position+Vector3(2.7,1.4,3.2),slope_tree.global_position+Vector3(0,.3,0)],
	]:
		camera.position = shot[1]
		camera.position.y = maxf(camera.position.y,Farm3DTerrainProfile.surface_height(camera.position.x,camera.position.z)+.9)
		camera.look_at(shot[2])
		for frame in 18: await process_frame
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png("res://docs/validation/diverse-trees/%s.png" % shot[0]) != OK: quit(1); return
	for region in ["hills", "mountains", "golf"]:
		var shrubs: Node = farm.get_node("LandscapeShrubs")
		var placement: Dictionary = shrubs.placements.filter(func(p): return p.region == region)[0]
		var target: Vector3 = placement.position + Vector3.UP*.6
		camera.position = target + Vector3(5,3.6,6)
		camera.look_at(target)
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png("res://docs/validation/diverse-trees/shrubs_%s.png" % region) != OK: quit(1); return
	farm.queue_free(); await process_frame; await process_frame
	quit(0)
