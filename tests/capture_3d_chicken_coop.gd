extends SceneTree

func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or "--farm-test" not in OS.get_cmdline_user_args(): quit(2); return
	run.call_deferred()

func capture(path: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(path) != OK: quit(1)
	print("COOP_CAPTURE ",path)

func run() -> void:
	root.size = Vector2i(1440,960)
	var folder := "res://docs/validation/chicken-coop"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var farm: Node3D = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var session: Farm3DSession = farm.farm_session
	session.season.set_process(false)
	session.living_world.set_process(false)
	session.player.set_physics_process(false)
	var interaction = farm.get_node("FarmInteraction")
	interaction.set_process(false)
	var hud = interaction.hud
	session.player.position = session.grid.get_cell(32,31).world_position_3d()+Vector3.LEFT*1.2
	var result := session.buildings.try_place_building("chicken_coop",32,31)
	if not result.placed: push_error("Capture could not place coop"); quit(1); return
	var coop: BuildingInstance = result.instance
	coop.complete_construction()
	session.inventory.add_item("animal_feed",5)
	session.production.add_input(coop,"animal_feed",5,session.inventory)
	for day in 3: session.rest()
	session.player.position = coop.position+Vector3(-2.1,0,1.6)
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.current = true
	camera.fov = 42
	hud.hide()
	for shot in [
		["front",Vector3(3.8,2.8,5.3),Vector3(0,.9,0)],
		["window",Vector3(-3.6,2.6,4.3),Vector3(0,.95,0)],
		["hens",Vector3(1.5,1.0,3.0),Vector3(0,.42,.8)],
	]:
		session.player.visible = shot[0] == "front"
		camera.position = coop.position+shot[1]
		camera.look_at(coop.position+shot[2])
		await capture(folder+"/"+shot[0]+".png")
	camera.position = coop.position+Vector3(4.8,3.4,6.6)
	camera.look_at(coop.position+Vector3.UP)
	session.player.position = coop.position+Vector3.BACK*2.7
	session.player.show()
	hud.show()
	interaction.open_windmill(coop)
	await capture(folder+"/panel.png")
	hud.close_panels()
	farm.queue_free()
	await process_frame
	await process_frame
	quit()
