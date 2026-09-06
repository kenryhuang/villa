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
	var result := session.buildings.try_place_building("food_workshop", 32, 31)
	if not result.placed:
		push_error(str(result))
		quit(1)
		return
	var food_workshop: BuildingInstance = result.instance
	food_workshop.complete_construction()
	food_workshop._process(0.0)
	food_workshop.set_process(false)
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.make_current()
	camera.fov = 43
	var target := food_workshop.position + Vector3.UP * 1.5
	for shot in [["front", Vector3(4.5, 1.8, 7.5)], ["rear", Vector3(-4.5, 1.6, -7.5)], ["low", Vector3(2.5, -.6, 8)]]:
		camera.position = target + shot[1]
		camera.look_at(target)
		await _capture(shot[0])
	camera.position = target + Vector3(4.5, 2.3, 8.5)
	camera.look_at(target)
	session.inventory.add_item("flour", 48)
	session.inventory.add_item("egg", 18)
	session.production.start_recipe(food_workshop, "bread", 3, session.inventory)
	session.production.advance_minutes(81)
	session.production.start_recipe(food_workshop, "bread", 3, session.inventory)
	session.production.advance_minutes(12)
	session.production.start_recipe(food_workshop, "bread", 2, session.inventory)
	await _capture("outputs")
	interaction.hud.show()
	interaction.hud.open_windmill(food_workshop)
	interaction.hud.food_workshop_view.controller.select_recipe("bread")
	await _capture("panel")
	root.content_scale_size = Vector2i(900, 720)
	root.size = Vector2i(900, 720)
	await _capture("panel_narrow")
	interaction.hud.food_workshop_view._show_tab(2)
	await _capture("queue_narrow")
	interaction.hud.close_panels()
	farm.queue_free()
	await process_frame
	print("FOOD WORKSHOP CAPTURE: 7 views")
	quit(0)

func _capture(suffix: String) -> void:
	for frame in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png("res://docs/validation/images/food_workshop_3d_" + suffix + ".png") != OK:
		push_error("Food workshop screenshot failed")
		quit(1)
