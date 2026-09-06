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
	var session: Farm3DSession = farm.farm_session
	session.season.set_process(false)
	var golf = session.golf
	var hud = golf.hud
	session.player.set_physics_process(false)
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.far = 400
	camera.fov = 52
	camera.position = Vector3(-106,75,177)
	camera.look_at(Vector3(-118,1,92))
	camera.make_current()
	hud.hide()
	await _capture("course")
	camera.position = Vector3(-123,3.5,68)
	camera.look_at(Vector3(-124,2,62))
	await _capture("entrance")
	hud.show()
	session.player.global_position = golf.Art.ground(golf.Course.ENTRANCE)+Vector3.BACK*2
	golf.start_round()
	session.player.global_position = golf.ball.position+Vector3.RIGHT
	golf.enter_address()
	await _capture("address")
	golf.gesture.begin(Time.get_ticks_usec()/1000000.0)
	golf.gesture.motion(Vector2(0,165),Time.get_ticks_usec()/1000000.0+.01)
	await _capture("backswing")
	golf.begin_swing({"power":.72,"deviation":.035})
	for frame in 32:
		await process_frame
	await _capture("flight")
	golf.release_control()
	golf.set_process(false)
	hud.hide()
	var cup: Vector2 = golf.Course.HOLES[0].cup
	camera.position = golf.Art.ground(cup)+Vector3(1.0,.65,1.6)
	camera.look_at(golf.Art.ground(cup))
	camera.make_current()
	await _capture("cup")
	farm.queue_free()
	await process_frame
	print("GOLF CAPTURE: 6 views")
	quit(0)

func _capture(suffix: String) -> void:
	for frame in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png("res://docs/validation/images/golf_3d_"+suffix+".png") != OK:
		push_error("Golf capture failed")
		quit(1)
