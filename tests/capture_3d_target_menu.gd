extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(1440, 960)
	var preview := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	var interaction = preview.get_node("FarmInteraction")
	var session = preview.get_node("FarmSession")
	session.season.set_process(false)
	preview.get_node("Player").global_position = Vector3(2, 0, 2.8)
	interaction.select_target("farmland", "paddy")
	var cell: GridCell = session.grid.get_cell(19, 15)
	session.apply_target(cell, "farmland", "paddy")
	interaction._front_target = true
	interaction.select_category("farmland")
	await _capture("farm_3d_menu_farmland.png")
	interaction.select_category("seed")
	await _capture("farm_3d_menu_seeds.png")
	interaction.select_category("building")
	await _capture("farm_3d_menu_buildings.png")
	interaction.cancel_selection()
	session.inventory.add_item("grain", 8)
	session.inventory.add_item("carrot", 3)
	interaction.hud.notify_message("已收获谷物 ×8、胡萝卜 ×3，物品已放入背包")
	interaction.hud.toggle_inventory()
	await _capture("farm_3d_menu_inventory.png")
	preview.queue_free()
	await process_frame
	quit(0)

func _capture(filename: String) -> void:
	for i in 12:
		await physics_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://docs/validation/images/" + filename)
	var result := root.get_texture().get_image().save_png(path)
	if result != OK:
		push_error("Capture failed: " + path)
		quit(1)
