extends SceneTree

const Fishing = preload("res://scripts/farm3d/farm_fishing.gd")
var farm: Node3D
var fishing: Node3D
var hud: CanvasLayer
var camera: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--farm-test" in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(1440,960)
	farm = (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	farm.set_process(false)
	farm.farm_session.season.set_process(false)
	farm.get_node("FarmInteraction").set_process(false)
	fishing = farm.get_node("FarmInteraction/Fishing")
	fishing.set_process(false)
	hud = farm.get_node("FarmInteraction").hud
	farm.player.position = Vector3(-6,Farm3DTerrainProfile.surface_height(-6,84)+.2,84)
	for i in 35:
		await physics_frame
	farm.player.set_physics_process(false)
	camera = Camera3D.new()
	farm.add_child(camera)
	camera.current = true
	camera.position = Vector3(.5,3.5,80.5)
	camera.look_at(Vector3(-6,1,87))
	camera.fov = 50
	if not fishing.equip():
		push_error("Fishing capture could not equip at lake shore")
		quit(1)
		return
	fishing.rng.seed = 128
	await _shot("ready",0)
	fishing.act()
	await _shot("backswing",.30)
	await _shot("cast",.75)
	fishing.advance(Fishing.CAST_TIME)
	await _shot("waiting",1.0)
	farm.follow_camera.current = true
	farm.set_process(true)
	await _shot("gameplay",1.0)
	farm.set_process(false)
	camera.current = true
	for i in 30:
		fishing.advance(fishing.duration)
		if fishing.state == Fishing.State.BITE:
			break
		fishing.advance(.8)
		fishing.act()
		fishing.advance(Fishing.CAST_TIME)
	if fishing.state != Fishing.State.BITE:
		push_error("Fishing capture did not get a bite")
		quit(1)
		return
	await _shot("bite",.35)
	fishing.act()
	await _shot("reel",.55)
	fishing.advance(Fishing.REEL_TIME)
	await _shot("landing",.5)
	fishing.advance(Fishing.LAND_TIME)
	hud.toggle_inventory()
	await _shot("backpack",0)
	hud.close_panels()
	farm.player.set_physics_process(true)
	farm.player.position = Vector3(28,Farm3DTerrainProfile.surface_height(28,0)+.2,0)
	for i in 35:
		await physics_frame
	farm.player.set_physics_process(false)
	if not fishing.equip():
		push_error("Fishing capture could not equip at river bank")
		quit(1)
		return
	camera.position = Vector3(22,6,6)
	camera.look_at(Vector3(31,-.3,0))
	fishing.act()
	fishing.advance(Fishing.CAST_TIME)
	await _shot("river",1)
	farm.follow_camera.current = true
	farm.set_process(true)
	await _shot("river_gameplay",1)
	farm.queue_free()
	await process_frame
	print("3D FISHING CAPTURE: 11 views")
	quit(0)

func _shot(title: String, seconds: float) -> void:
	if fishing.is_equipped():
		fishing.visual.update_pose(Fishing.State.keys()[fishing.state],seconds,fishing.duration,fishing.location.water,fishing.catch_id)
	fishing._update_hud()
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://docs/validation/images/fishing_3d_%s.png" % title
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Failed to capture "+title)
		quit(1)
