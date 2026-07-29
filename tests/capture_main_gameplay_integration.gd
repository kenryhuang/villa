extends SceneTree

const OUTPUT_PATH := "/private/tmp/villa-main-gameplay-integration.png"
const CROP_PROGRESS := [0.0, 1.0, 2.0, 3.0]


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1600, 1000)
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		_fail("main scene cannot load")
		return
	var main = main_scene.instantiate()
	main.load_save_on_start = false
	root.add_child(main)
	current_scene = main
	for _frame in 8:
		await process_frame

	var game_data := root.get_node_or_null("GameData")
	var grain: CropData = game_data.get_crop("grain") if game_data else null
	if grain == null or grain.stage_scenes.size() != 4:
		_fail("main game has no four-stage grain crop")
		return
	var crop_cells := _nearest_farm_cells(main, 4)
	if crop_cells.size() != 4:
		_fail("main game cannot provide four visual farm cells")
		return
	for index in range(crop_cells.size()):
		var cell: GridCell = crop_cells[index]
		if not main.grid_system.set_cell_state(
			cell.gx,
			cell.gz,
			GridCell.State.FARMLAND
		):
			_fail("cannot prepare crop cell %d" % index)
			return
		var crop_instance: CropInstance = main.farming_system.plant(cell, grain)
		if crop_instance == null:
			_fail("cannot plant crop stage %d" % index)
			return
		crop_instance.growth_progress = CROP_PROGRESS[index]
	main.farming_system.rebuild_visuals()

	var barn_cell := _nearest_build_cell(main, "barn")
	if barn_cell == null:
		_fail("main game has no valid barn cell")
		return
	var barn: BuildingInstance = main.building_system.place_building(
		"barn",
		barn_cell.gx,
		barn_cell.gz
	)
	if barn == null:
		_fail("cannot place construction-stage barn")
		return

	var well_cell := _nearest_build_cell(main, "well")
	if well_cell == null:
		_fail("main game has no valid well cell")
		return
	var well: BuildingInstance = main.building_system.place_building(
		"well",
		well_cell.gx,
		well_cell.gz
	)
	if well == null:
		_fail("cannot place completed well")
		return
	well.complete_construction()

	if main.farming_system.get_visual_count() < 4:
		_fail("main tree is missing crop visuals")
		return
	if barn.construction_stage != BuildingInstance.ConstructionStage.FOUNDATION:
		_fail("barn does not show foundation stage")
		return
	if not well.is_construction_complete():
		_fail("well does not show completed stage")
		return

	var focus := Marker3D.new()
	focus.name = "GameplayCaptureFocus"
	main.add_child(focus)
	focus.global_position = _focus_position(main, crop_cells, barn, well)
	main.camera_rig.set_target(focus)
	main.camera_rig.orthographic_size = 9.5
	main.camera_rig.yaw = -PI / 4.0
	for _frame in 16:
		await process_frame
		await physics_frame

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		_fail("cannot save capture: %s" % error_string(error))
		return
	print(
		"CAPTURED: %s (%dx%d) crops=%d buildings=%d"
		% [
			OUTPUT_PATH,
			image.get_width(),
			image.get_height(),
			main.farming_system.get_visual_count(),
			main.building_system.get_building_count(),
		]
	)
	quit(0)


func _nearest_farm_cells(main: Node, count: int) -> Array[GridCell]:
	var candidates: Array[GridCell] = []
	for cell in main.grid_system._cells.values():
		if main.grid_system.can_farm_at(cell.gx, cell.gz):
			candidates.append(cell)
	var player_position: Vector3 = main.player.global_position
	candidates.sort_custom(
		func(a: GridCell, b: GridCell) -> bool:
			return a.world_position_3d().distance_squared_to(player_position) \
				< b.world_position_3d().distance_squared_to(player_position)
	)
	return candidates.slice(0, mini(count, candidates.size()))


func _nearest_build_cell(main: Node, building_id: String) -> GridCell:
	var best: GridCell
	var best_distance := INF
	for cell in main.grid_system._cells.values():
		if not main.building_system.can_place(building_id, cell.gx, cell.gz):
			continue
		var distance: float = cell.world_position_3d().distance_squared_to(
			main.player.global_position
		)
		if distance < best_distance:
			best = cell
			best_distance = distance
	return best


func _focus_position(
	main: Node,
	crop_cells: Array[GridCell],
	barn: BuildingInstance,
	well: BuildingInstance
) -> Vector3:
	var total: Vector3 = main.player.global_position
	for cell in crop_cells:
		total += cell.world_position_3d()
	total += barn.global_position
	total += well.global_position
	var focus: Vector3 = total / float(crop_cells.size() + 3)
	focus.y = main.world.get_height_at(focus.x, focus.z)
	return focus


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
