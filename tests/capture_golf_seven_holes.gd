extends SceneTree
func _initialize(): run.call_deferred()
func run():
	if DisplayServer.get_name() == "headless" or "--farm-test" not in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(1440,1100)
	var farm = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.farm_session.season.set_process(false)
	farm.farm_session.player.set_physics_process(false)
	var golf = farm.farm_session.golf
	golf.get_parent().set_process_input(false)
	golf.hud.hide()
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.far = 600
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 215
	camera.position = Vector3(-154,200,100)
	camera.look_at(Vector3(-124,0,30))
	camera.make_current()
	await capture("seven-hole-overview")
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 62
	camera.position = Vector3(-109,21,134)
	camera.look_at(Vector3(-116,0,103))
	await capture("pond-dogleg")
	golf.player.global_position = golf.Art.ground(golf.Course.ENTRANCE)+Vector3.BACK*2
	golf.start_round()
	golf.round_state.hole = 2
	golf.round_state.scores.assign([3,4])
	golf.round_state.ball = golf.Course.HOLES[2].tee
	golf.ball.place(golf.round_state.ball)
	golf.player.global_position = golf.ball.position+Vector3.RIGHT
	golf.enter_address()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	golf.hud.show()
	golf._orbit_distance = 28
	golf._orbit_pitch = .7
	golf._orbit_yaw = .7
	golf.direction = golf.direction.rotated(Vector3.UP,deg_to_rad(-20))
	golf.contact_side = -.6
	golf.gesture.begin(0)
	golf.gesture.motion(Vector2(0,190),.2)
	await capture("forest-curve-setup")
	farm.free()
	print("SEVEN HOLE CAPTURE: PASS")
	quit()
func capture(label: String):
	for frame in 15: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tmp/golf-seven")
	root.get_texture().get_image().save_png("res://tmp/golf-seven/"+label+".png")
