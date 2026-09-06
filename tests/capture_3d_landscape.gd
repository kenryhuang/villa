extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--farm-test" in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(1440,960)
	var farm := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	farm.set_process(false)
	farm.get_node("Player").set_physics_process(false)
	farm.get_node("FarmInteraction").set_process(false)
	farm.get_node("FarmInteraction").hud.hide()
	farm.get_node("FarmSession").season.set_process(false)
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.current = true
	camera.far = 500
	camera.fov = 50
	var shots := [
		["overview",Vector3(125,125,145),Vector3(0,4,-7)],
		["hills",Vector3(-11,13,32),Vector3(-44,5,3)],
		["mountains",Vector3(-9,16,-12),Vector3(-13,14,-59)],
		["canyon",Vector3(54,27,-15),Vector3(34,3,-49)],
		["river",Vector3(56,10,36),Vector3(39,0,16)],
		["farm",Vector3(14,8,19),Vector3(0,1,0)]
	]
	for shot in shots:
		camera.position = shot[1]
		camera.look_at(shot[2])
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png("res://docs/validation/images/landscape_3d_"+shot[0]+".png")
		if error != OK:
			push_error("Landscape screenshot failed: "+shot[0])
			quit(1)
			return
	farm.queue_free()
	await process_frame
	print("LANDSCAPE CAPTURE: 6 views")
	quit(0)
