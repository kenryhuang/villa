extends SceneTree

const OUTPUT_PATH := "/private/tmp/villa-main-pointer-farmland.png"


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1600, 1000)
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("main scene cannot load")
		return
	var main = packed.instantiate()
	main.load_save_on_start = false
	root.add_child(main)
	current_scene = main
	for _frame in 8:
		await process_frame
		await physics_frame

	var cells := _nearest_reachable_farm_cells(main, 4)
	if cells.size() != 4:
		_fail("main scene has fewer than four reachable farm cells")
		return

	main.action_controller.select_slot(0)
	for index in range(3):
		var cell: GridCell = cells[index]
		if not _click_cell(main, cell):
			_fail("pointer failed to hoe cell %d" % index)
			return
		if cell.state != GridCell.State.FARMLAND:
			_fail("cell %d did not become farmland" % index)
			return

	main.action_controller.select_slot(PlayerActionController.SEED_SLOT)
	if not _click_cell(main, cells[0]):
		_fail("pointer failed to plant the first farmland cell")
		return
	if cells[0].state != GridCell.State.PLANTED:
		_fail("first farmland cell did not become planted")
		return

	var focus := Marker3D.new()
	focus.name = "FarmlandCaptureFocus"
	main.add_child(focus)
	focus.global_position = _average_cell_position(cells)
	main.camera_rig.set_target(focus)
	main.camera_rig.orthographic_size = 6.2
	main.camera_rig.yaw = -PI / 4.0
	for _frame in 16:
		await process_frame
		await physics_frame

	main.action_controller.select_slot(0)
	var hover_cell: GridCell = cells[3]
	var camera: Camera3D = root.get_camera_3d()
	var motion := InputEventMouseMotion.new()
	motion.position = camera.unproject_position(hover_cell.world_position_3d())
	motion.global_position = motion.position
	main.action_controller._input(motion)
	main.action_controller._process(0.0)
	await process_frame

	var highlight := main.grid_system.get_node(
		"GridCells/CellHighlight"
	) as MeshInstance3D
	if main.grid_system.get_farmland_visual_count() != 3:
		_fail(
			"expected three farmland visuals, got %d"
			% main.grid_system.get_farmland_visual_count()
		)
		return
	if main.farming_system.get_visual_count() != 1:
		_fail(
			"expected one crop visual, got %d"
			% main.farming_system.get_visual_count()
		)
		return
	if (
		highlight == null
		or not highlight.visible
		or int(highlight.get_meta("gx", -1)) != hover_cell.gx
		or int(highlight.get_meta("gz", -1)) != hover_cell.gz
	):
		_fail("hover highlight is not aligned to the fourth pointer cell")
		return

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		_fail("cannot save capture: %s" % error_string(error))
		return
	print(
		"CAPTURED: %s farmland=%d crops=%d highlight=%s"
		% [
			OUTPUT_PATH,
			main.grid_system.get_farmland_visual_count(),
			main.farming_system.get_visual_count(),
			str(highlight.visible),
		]
	)
	quit(0)


func _click_cell(main: Node, cell: GridCell) -> bool:
	var camera: Camera3D = root.get_camera_3d()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(cell.world_position_3d())
	click.global_position = click.position
	var before_state: int = cell.state
	main.action_controller._input(click)
	main.action_controller._unhandled_input(click)
	return cell.state != before_state


func _nearest_reachable_farm_cells(main: Node, count: int) -> Array[GridCell]:
	var candidates: Array[GridCell] = []
	var player_position: Vector3 = main.player.global_position
	for cell in main.grid_system._cells.values():
		if not main.grid_system.can_farm_at(cell.gx, cell.gz):
			continue
		var point: Vector3 = cell.world_position_3d()
		var distance := Vector2(
			player_position.x - point.x,
			player_position.z - point.z
		).length()
		if distance <= main.player.interaction_range:
			candidates.append(cell)
	candidates.sort_custom(
		func(a: GridCell, b: GridCell) -> bool:
			return a.world_position_3d().distance_squared_to(player_position) \
				< b.world_position_3d().distance_squared_to(player_position)
	)
	return candidates.slice(0, mini(count, candidates.size()))


func _average_cell_position(cells: Array[GridCell]) -> Vector3:
	var result := Vector3.ZERO
	for cell in cells:
		result += cell.world_position_3d()
	return result / float(cells.size())


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
