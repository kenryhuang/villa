extends SceneTree

const OUTPUT := "res://docs/validation/images/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(1440, 960)
	var preview := (load("res://scenes/preview/farm_3d_preview.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	var session = preview.get_node("FarmSession")
	session.season.set_process(false)
	var interaction = preview.get_node("FarmInteraction")
	var farmer = preview.get_node("Player")
	farmer.global_position = Vector3(2.0, 0.0, 2.8)
	var cells: Array[GridCell] = []
	for gx in [19, 20]:
		for gz in [14, 15]:
			var cell: GridCell = session.grid.get_cell(gx, gz)
			cells.append(cell)
			if not session.act(cell, "hoe").get("ok", false):
				push_error("Capture could not cultivate its actual demo cell")
				quit(1)
				return
	interaction.select_mode("seed")
	await _settle()
	await _capture("farm_3d_cultivated.png")
	for cell in cells:
		if not session.act(cell, "seed").get("ok", false):
			quit(1)
			return
	interaction.hud.notify_message("播种完成 · 谷物会随着游戏时间自然生长")
	await _capture("farm_3d_seeded.png")
	session.season.advance_game_minutes(54)
	interaction.hud.notify_message("谷物正在生长 · 距成熟还有 54 游戏分钟")
	await _capture("farm_3d_growing.png")
	session.season.advance_game_minutes(54)
	interaction.select_mode("harvest")
	interaction.hud.notify_message("谷物成熟了，可以收获入背包")
	await _capture("farm_3d_mature.png")
	var total := 0
	for cell in cells:
		var result: Dictionary = session.act(cell, "harvest")
		if not result.get("ok", false):
			quit(1)
			return
		total += int(result.items.get("grain", 0))
	interaction.hud.notify_message("收获完成 · 背包增加 %d 份谷物，土地可以再次播种" % total)
	await _capture("farm_3d_harvested.png")
	print("CAPTURED 3D FARM LIFECYCLE: cultivated / seeded / growing / mature / harvested")
	preview.queue_free()
	await process_frame
	quit(0)

func _settle() -> void:
	for frame in 12:
		await physics_frame
	await process_frame

func _capture(filename: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUTPUT + filename)
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Unable to save lifecycle evidence: " + filename)
