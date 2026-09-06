extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--farm-test" in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(1440, 960)
	var farm := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var session: Farm3DSession = farm.get_node("FarmSession")
	session.season.set_process(false)
	session.player.set_physics_process(false)
	session.player.hide()
	var interaction = farm.get_node("FarmInteraction")
	interaction.set_process(false)
	interaction.hud.hide()
	session.player.position = session.grid.get_cell(32, 31).world_position_3d() + Vector3.LEFT * 1.2
	var result := session.buildings.try_place_building("windmill", 32, 31)
	if not result.placed:
		push_error(str(result))
		quit(1)
		return
	var windmill: BuildingInstance = result.instance
	windmill.complete_construction()
	windmill.set_process(false)
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.make_current()
	camera.fov = 43
	var target := windmill.position + Vector3.UP * 1.7
	for shot in [["front", Vector3(4.5, 1.8, 7.5)], ["rear", Vector3(-4.5, 1.6, -7.5)], ["low", Vector3(2.5, -.6, 8)]]:
		camera.position = target + shot[1]
		camera.look_at(target)
		await _capture(shot[0])
	camera.position = target + Vector3(4.5, 2.3, 8.5)
	camera.look_at(target)
	session.inventory.add_item("grain", 48)
	session.inventory.add_item("sunflower", 18)
	session.production.start_recipe(windmill, "flour", 3, session.inventory)
	session.production.advance_minutes(81)
	session.production.start_recipe(windmill, "flour", 3, session.inventory)
	session.production.advance_minutes(12)
	session.production.start_recipe(windmill, "animal_feed", 2, session.inventory)
	await _capture("outputs")
	interaction.hud.show()
	interaction.hud.open_windmill(windmill)
	await _capture("panel")
	root.content_scale_size = Vector2i(900, 720)
	root.size = Vector2i(900, 720)
	await _capture("panel_narrow")
	interaction.hud.windmill_view._show_tab(2)
	await _capture("queue_narrow")
	interaction.hud.close_panels()
	farm.queue_free()
	await process_frame
	print("WINDMILL CAPTURE: 7 views")
	quit(0)

func _capture(suffix: String) -> void:
	for frame in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png("res://docs/validation/images/windmill_3d_" + suffix + ".png") != OK:
		push_error("Windmill screenshot failed")
		quit(1)
