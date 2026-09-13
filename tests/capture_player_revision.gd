extends SceneTree

var views: Array[SubViewport] = []
var animators: Array[AnimationPlayer] = []
var models: Array[Node3D] = []
var cameras: Array[Camera3D] = []

func _initialize() -> void:
	run.call_deferred()

func add_view(rect: Rect2i, yaw: float, clip: String, time: float, title: String, model_path := "res://assets/models/farm3d/player_farmer.glb") -> void:
	var container := SubViewportContainer.new()
	container.position = rect.position
	container.size = rect.size
	root.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = rect.size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	views.append(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("e5e2d9")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("e4e9f0")
	environment.environment.ambient_light_energy = .25
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	light.light_energy = .55
	light.shadow_enabled = true
	viewport.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(20,20)
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color("d9d5ca")
	floor_mesh.material_override = ground
	viewport.add_child(floor_mesh)
	var model := load(model_path).instantiate() as Node3D
	viewport.add_child(model)
	models.append(model)
	model.rotation.y = yaw
	var animator: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	animators.append(animator)
	for name in animator.get_animation_list():
		if String(name).get_file().to_lower() == clip.to_lower():
			animator.play(name)
			animator.seek(time,true)
			animator.pause()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.22
	camera.position = Vector3(0,1.12,5)
	viewport.add_child(camera)
	camera.look_at(Vector3(0,1.02,0))
	camera.make_current()
	cameras.append(camera)
	var label := Label.new()
	label.text = title
	label.position = Vector2(12,rect.size.y-36)
	label.add_theme_color_override("font_color",Color("354033"))
	label.add_theme_font_size_override("font_size",22)
	viewport.add_child(label)

func save_image(path: String) -> void:
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func clear_views() -> void:
	for child in root.get_children(): child.queue_free()
	views.clear()
	animators.clear()
	models.clear()
	cameras.clear()
	await process_frame

func capture_motion(clip: String, duration: float, speed: float, reference: float) -> void:
	await clear_views()
	root.size=Vector2i(960,640)
	for index in 2:
		add_view(Rect2i(index*480,0,480,640),PI/2 if index==0 else .5,clip,0,
			"%s · %.1f m/s" % [clip.to_upper(),speed])
		# Static ground marks make a sliding planted foot immediately visible.
		for line_index in range(-18,19):
			var line := MeshInstance3D.new()
			line.mesh=BoxMesh.new()
			line.mesh.size=Vector3(.012,.002,18)
			line.position=Vector3(line_index*.65,.001,0)
			var mat := StandardMaterial3D.new()
			mat.albedo_color=Color("9caa94")
			line.material_override=mat
			views[index].add_child(line)
	var period := 2*duration/(speed/reference)
	var frames := roundi(period/.02)
	var directory := "res://tmp/player-upright-motion/"+clip.to_lower()
	DirAccess.make_dir_recursive_absolute(directory)
	for frame in frames:
		var seconds := period*frame/frames
		for index in 2:
			animators[index].seek(fposmod(seconds*speed/reference,duration),true)
			models[index].position=models[index].basis.z*speed*seconds
			cameras[index].position=models[index].position+Vector3(0,1.12,5)
			cameras[index].look_at(models[index].position+Vector3(0,1.02,0))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/%03d.png"%frame)
	var manifest := FileAccess.open(directory+"/capture.json",FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"frames":frames,"duration":period,"speed":speed,"reference_speed":reference}))
	print("Captured %s: %d frames at 50 fps"%[clip,frames])

func run() -> void:
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size=Vector2i.ZERO
	root.size = Vector2i(1600,1040)
	DirAccess.make_dir_recursive_absolute("res://art/concepts/player")
	for index in 8:
		add_view(Rect2i(index%4*400,index/4*520,400,520), PI/2, "Walk",index*1.2/8.0,
			"WALK %02d / 8" % (index+1))
	await save_image("res://art/concepts/player/player-walk-frames.png")
	await clear_views()
	for index in 8:
		add_view(Rect2i(index%4*400,index/4*520,400,520), PI/2, "Run",index*.1,
			"RUN %02d / 8" % (index+1))
	await save_image("res://art/concepts/player/player-run-frames.png")
	await clear_views()
	root.size=Vector2i(1600,900)
	for index in 4:
		add_view(Rect2i(index*400,0,400,900),[0.0,.55,PI/2,PI][index],"Idle",0,
			["FRONT","THREE QUARTER","SIDE","BACK"][index])
	await save_image("res://art/concepts/player/player-turnaround.png")
	if "--motion" in OS.get_cmdline_user_args():
		await capture_motion("Walk",1.2,3.0,Farm3DPlayer.WALK_REFERENCE_SPEED)
		await capture_motion("Run",.8,6.0,Farm3DPlayer.RUN_REFERENCE_SPEED)
	print("Saved player turnaround and eight-frame walk/run sheets")
	quit()
