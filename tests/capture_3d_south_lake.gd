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
	farm.player.set_physics_process(false)
	farm.get_node("FarmInteraction").set_process(false)
	var hud = farm.get_node("FarmInteraction").hud
	hud.hide()
	farm.farm_session.season.set_process(false)
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.current = true
	camera.far = 550
	camera.fov = 50
	var shots := [
		["overview",Vector3(160,180,232),Vector3(0,4,32)],
		["lake",Vector3(38,29,144),Vector3(-6,-.5,105)],
		["transition",Vector3(-28,10,57),Vector3(-5,0,93)],
		["shore",Vector3(-6,3.6,77),Vector3(-6,.2,102)],
	]
	for shot in shots:
		if shot[0] == "shore":
			hud.show()
			farm.player.position = farm.get_node("Landscape/LakeFishingShores/NorthShore").position
			farm.player.rotation.y = 0
		camera.position = shot[1]
		camera.look_at(shot[2])
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://docs/validation/images/south_3d_"+shot[0]+".png"
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("South lake screenshot failed: "+shot[0])
			quit(1)
			return
	farm.queue_free()
	await process_frame
	print("SOUTH LAKE CAPTURE: 4 views")
	quit(0)
