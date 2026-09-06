extends SceneTree

const OUTPUT := "res://docs/validation/images/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--farm-test" in OS.get_cmdline_user_args():
		push_error("Rose screenshots require a GPU and --farm-test to isolate player saves")
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
	var session = farm.get_node("FarmSession")
	session.season.set_process(false)
	var cells: Array[GridCell] = []
	for index in 5:
		var cell: GridCell = session.grid.get_cell(19 + index, 18)
		session.grid.set_cell_state(cell.gx, cell.gz, GridCell.State.FARMLAND)
		var crop: CropInstance = session.farming.commit_plant(cell, "rose_seed", session.farming.preview_plant(cell, "rose_seed"))
		crop.set_growth_state([0.0, 1.5, 3.0, 4.0, 4.0][index], CropInstance.LifecycleState.WITHERED if index == 4 else (CropInstance.LifecycleState.MATURE if index == 3 else CropInstance.LifecycleState.GROWING))
		session.visuals.sync_cell(cell)
		cells.append(cell)
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.current = true
	camera.fov = 43
	var center := cells[2].world_position_3d() + Vector3.UP * .3
	camera.position = center + Vector3(.7, 2.1, 6.6)
	camera.look_at(center)
	await _capture("rose_3d_stages.png")
	var seed_target := cells[0].world_position_3d() + Vector3.UP * .055
	camera.position = seed_target + Vector3(.12, .07, .75)
	camera.look_at(seed_target)
	await _capture("rose_3d_seed_low.png")
	var target := cells[3].world_position_3d() + Vector3.UP * .39
	camera.position = target + Vector3(.40, .12, 1.9)
	camera.look_at(target)
	await _capture("rose_3d_low.png")
	# Same soil, root offset and camera as the previous image: isolate old sprite behavior.
	var holder: Node3D = session.visuals._visuals[GridSystem.cell_key(cells[3].gx, cells[3].gz)]
	var modeled: Node3D = holder.get_node("Crop_rose")
	modeled.hide()
	var old: Node3D = load("res://assets/crops/rose/rose_stage_3_mature.tscn").instantiate()
	holder.add_child(old)
	old.position.y = .06
	await _capture("rose_25d_before.png")
	old.queue_free()
	modeled.show()
	camera.position = target + Vector3(1.85,.40,-.45)
	camera.look_at(target)
	await _capture("rose_3d_side.png")
	camera.position = target + Vector3(-.65,.65,-1.8)
	camera.look_at(target)
	await _capture("rose_3d_back.png")
	farm.queue_free()
	await process_frame
	print("ROSE CAPTURE: five stages, low view, side, back, old sprite comparison")
	quit(0)

func _capture(filename: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + filename))
	if error != OK:
		push_error("Screenshot failed: " + filename)
		quit(1)
