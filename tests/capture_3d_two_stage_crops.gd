extends SceneTree

const OUTPUT := "res://docs/validation/images/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--farm-test" in OS.get_cmdline_user_args():
		push_error("Crop screenshots require a GPU and --farm-test")
		quit(1)
		return
	root.size = Vector2i(1440, 960)
	var farm := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	farm.set_process(false)
	farm.get_node("Player").hide()
	farm.get_node("Player").set_physics_process(false)
	farm.get_node("FarmInteraction").set_process(false)
	farm.get_node("FarmInteraction").hud.hide()
	var session: Farm3DSession = farm.get_node("FarmSession")
	session.season.set_process(false)
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.current = true
	camera.fov = 43
	var cells: Array[GridCell] = []
	for index in 3:
		var crop_id: String = ["potato", "tomato", "lavender"][index]
		session.season.current_season = SeasonSystem.Season.SUMMER if crop_id == "lavender" else SeasonSystem.Season.SPRING
		for stage in 2:
			var cell: GridCell = session.grid.get_cell(19 + index * 2, 18 + stage * 2)
			session.grid.set_cell_state(cell.gx, cell.gz, GridCell.State.FARMLAND)
			var seed_id := crop_id + "_seed"
			var crop: CropInstance = session.farming.commit_plant(cell, seed_id, session.farming.preview_plant(cell, seed_id))
			crop.set_growth_state(4.0 if stage else 0.0, CropInstance.LifecycleState.MATURE if stage else CropInstance.LifecycleState.GROWING)
			session.visuals.sync_cell(cell)
			cells.append(cell)
		var target := cells[-1].world_position_3d() + Vector3.UP * (.48 if index == 1 else .39)
		camera.position = target + Vector3(.90, .40, 2.05)
		camera.look_at(target)
		await _capture(crop_id + "_3d_mature.png")
		camera.position = target + Vector3(-1.85, .02, -.85)
		camera.look_at(target)
		await _capture(crop_id + "_3d_back_low.png")
		var seed_target := cells[-2].world_position_3d() + Vector3.UP * .045
		camera.position = seed_target + Vector3(.12, .09, .78)
		camera.look_at(seed_target)
		await _capture(crop_id + "_3d_seed.png")
	var center := cells[3].world_position_3d() + Vector3(0, .20, -1)
	camera.position = center + Vector3(.6, 3.1, 6.3)
	camera.look_at(center)
	await _capture("two_stage_crops_3d.png")
	farm.queue_free()
	await process_frame
	print("TWO STAGE CROP CAPTURE: mature, low rear, seed and overview")
	quit(0)

func _capture(filename: String) -> void:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + filename)) != OK:
		push_error("Screenshot failed: " + filename)
		quit(1)
