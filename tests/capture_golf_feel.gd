extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or "--farm-test" not in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(1440,960)
	var farm = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.farm_session.season.set_process(false)
	farm.farm_session.player.set_physics_process(false)
	var golf = farm.farm_session.golf
	golf.player.global_position = golf.Art.ground(golf.Course.ENTRANCE)+Vector3.BACK*2
	golf.start_round()
	golf.player.global_position = golf.ball.position+Vector3.RIGHT
	golf.enter_address()
	golf.get_parent().set_process_input(false)
	golf.get_parent().set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	golf.gesture.begin(0)
	golf.gesture.motion(Vector2(7,132),.2)
	await capture("golf-feel-backswing")
	golf.gesture.cancel()
	golf.club = 2
	golf.contact_height = 0
	golf.gesture.begin(0)
	golf.gesture.motion(Vector2(4,68),.2,true)
	await capture("golf-feel-putt")
	root.size = Vector2i(900,720)
	root.content_scale_size = Vector2i(900,720)
	await capture("golf-feel-compact")
	farm.free()
	print("GOLF FEEL CAPTURE: PASS")
	quit(0)

func capture(label: String) -> void:
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tmp/golf-feel")
	root.get_texture().get_image().save_png("res://tmp/golf-feel/"+label+".png")
