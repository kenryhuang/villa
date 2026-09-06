extends SceneTree

const CROPS := ["carrot", "strawberry", "blueberry", "watermelon", "sunflower", "pumpkin", "apple", "peach", "grape", "lemon"]
const HEIGHTS := [0.22, 0.18, 0.43, 0.15, 0.63, 0.15, 0.88, 0.88, 0.55, 0.88]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--farm-test" in OS.get_cmdline_user_args():
		push_error("Screenshots require GPU and --farm-test")
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
	var cell: GridCell = session.grid.get_cell(20, 18)
	session.grid.set_cell_state(cell.gx,cell.gz,GridCell.State.FARMLAND)
	for index in CROPS.size():
		var crop_id: String = CROPS[index]
		var definition: CropData
		for candidate in CropCatalog.default_crop_definitions():
			if candidate.crop_id == crop_id:
				definition = candidate
		session.season.current_season = definition.seasons[0] if not definition.seasons.is_empty() else SeasonSystem.Season.SPRING
		session.farming.set_greenhouse_cells([Vector2i(cell.gx,cell.gz)] if crop_id == "lemon" else [])
		cell.crop_instance = null
		cell.state = GridCell.State.FARMLAND
		var crop: CropInstance = session.farming.commit_plant(cell,definition.plant_item_id,session.farming.preview_plant(cell,definition.plant_item_id))
		session.visuals.sync_cell(cell)
		var target := cell.world_position_3d() + Vector3.UP * .12
		camera.position = target + Vector3(.30,.15,1.0)
		camera.look_at(target)
		await _capture(crop_id+"_3d_seed.png")
		crop.set_growth_state(definition.growth_days,CropInstance.LifecycleState.MATURE)
		session.visuals.sync_cell(cell)
		target = cell.world_position_3d() + Vector3.UP * HEIGHTS[index]
		var distance := maxf(1.5,HEIGHTS[index]*3.8)
		var holder: Node3D = session.visuals._visuals[GridSystem.cell_key(cell.gx,cell.gz)]
		var plant: Node3D = holder.get_node("Crop_"+crop_id)
		camera.position = target + plant.basis * Vector3(distance*.3,distance*.23,distance)
		camera.look_at(target)
		await _capture(crop_id+"_3d_mature.png")
		camera.position = target + plant.basis * Vector3(-distance*.95,.015,-distance*.55)
		camera.look_at(target)
		await _capture(crop_id+"_3d_back_low.png")
	farm.queue_free()
	await process_frame
	print("REMAINING CROPS CAPTURE: 10 crops, seed/mature/rear views")
	quit(0)

func _capture(filename: String) -> void:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/validation/images/"+filename)) != OK:
		push_error("Screenshot failed: "+filename)
		quit(1)
