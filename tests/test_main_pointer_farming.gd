extends RefCounted


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main = packed.instantiate()
	main.load_save_on_start = false
	tree.root.add_child(main)
	for _frame in 4:
		await tree.process_frame
		await tree.physics_frame

	var cell := _nearest_reachable_farm_cell(main)
	assertions.truthy(cell != null, "main has farmland reachable by pointer interaction")
	if cell == null:
		main.free()
		return

	var camera: Camera3D = tree.root.get_camera_3d()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(cell.world_position_3d())
	click.global_position = click.position

	main.action_controller.select_slot(0)
	var motion := InputEventMouseMotion.new()
	motion.position = click.position
	motion.global_position = motion.position
	var has_pointer_input: bool = main.action_controller.has_method("_input")
	assertions.truthy(
		has_pointer_input,
		"action controller records real mouse motion events"
	)
	if not has_pointer_input:
		main.free()
		return
	main.action_controller.call("_input", motion)
	main.action_controller._process(0.0)
	var highlight := main.grid_system.get_node(
		"GridCells/CellHighlight"
	) as MeshInstance3D
	assertions.truthy(
		highlight.visible,
		"slot one shows a hover grid at the mouse event position"
	)
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	main.action_controller._unhandled_input(cancel)
	main.action_controller._process(0.0)
	assertions.equal(
		main.action_controller.get_selected_slot(),
		-1,
		"escape clears the active tool"
	)
	assertions.truthy(not highlight.visible, "escape immediately hides the hover grid")
	main.action_controller.select_slot(0)
	main.action_controller._process(0.0)
	assertions.truthy(highlight.visible, "selecting a tool restores the hover grid")

	main.action_controller._unhandled_input(click)
	assertions.equal(
		cell.state,
		GridCell.State.FARMLAND,
		"left click event position hoes its projected grid cell"
	)
	main.action_controller._process(0.0)
	var invalid_material := highlight.material_override as StandardMaterial3D
	assertions.truthy(
		invalid_material != null
		and invalid_material.albedo_color.r > invalid_material.albedo_color.g,
		"cultivated cell changes the hoe hover grid to invalid red"
	)

	var seeds_before: int = main.inventory_system.get_item_count("grain_seed")
	main.action_controller.select_slot(PlayerActionController.SEED_SLOT)
	main.action_controller._unhandled_input(click)
	assertions.equal(
		cell.state,
		GridCell.State.PLANTED,
		"left click event position plants grain on prepared soil"
	)
	assertions.equal(
		main.inventory_system.get_item_count("grain_seed"),
		seeds_before - 1,
		"pointer planting consumes one grain seed"
	)

	# The formal starter economy cannot afford a barn; fund this pointer-only fixture explicitly.
	main.inventory_system.add_item("wood", 170)
	main.inventory_system.add_item("stone", 80)
	var build_cell := _nearest_build_origin(main, "barn")
	assertions.truthy(build_cell != null, "main has a pointer-visible barn origin")
	if build_cell:
		var build_point: Vector3 = build_cell.world_position_3d()
		var build_motion := InputEventMouseMotion.new()
		build_motion.position = camera.unproject_position(build_point)
		build_motion.global_position = build_motion.position
		var build_click := InputEventMouseButton.new()
		build_click.button_index = MOUSE_BUTTON_LEFT
		build_click.pressed = true
		build_click.position = build_motion.position
		build_click.global_position = build_click.position

		assertions.truthy(
			main.action_controller.switch_mode(
				PlayerActionController.ActionMode.BUILDING
			),
			"B enters building mode"
		)
		main.action_controller._input(build_motion)
		main.action_controller._process(0.0)
		assertions.truthy(
			main.building_system.is_in_build_mode(),
			"building mode owns the pointer preview"
		)
		assertions.equal(
			main.building_system.get_preview_marker_count(),
			4,
			"barn pointer preview shows its 2x2 footprint"
		)

		var original_state: int = build_cell.state
		var building_count_before: int = main.building_system.get_building_count()
		var wood_before: int = main.inventory_system.get_item_count("wood")
		var stone_before: int = main.inventory_system.get_item_count("stone")
		main.grid_system.set_cell_state(
			build_cell.gx,
			build_cell.gz,
			GridCell.State.BUILDING
		)
		main.action_controller._process(0.0)
		assertions.truthy(
			not main.building_system.get_preview_can_place(),
			"blocked footprint turns the pointer preview invalid"
		)
		main.action_controller._unhandled_input(build_click)
		assertions.equal(
			main.building_system.get_building_count(),
			building_count_before,
			"invalid pointer click creates no building"
		)
		assertions.equal(
			main.inventory_system.get_item_count("wood"),
			wood_before,
			"invalid pointer click spends no wood"
		)
		assertions.equal(
			main.inventory_system.get_item_count("stone"),
			stone_before,
			"invalid pointer click spends no stone"
		)

		main.grid_system.set_cell_state(build_cell.gx, build_cell.gz, original_state)
		main.action_controller._process(0.0)
		assertions.truthy(
			main.building_system.get_preview_can_place(),
			"restored footprint turns the pointer preview valid"
		)
		main.action_controller._unhandled_input(build_click)
		assertions.equal(
			main.building_system.get_building_count(),
			building_count_before + 1,
			"valid pointer click creates one building"
		)
		var placed_buildings: Array[BuildingInstance] = (
			main.building_system.get_all_buildings()
		)
		var placed: BuildingInstance = placed_buildings[-1]
		assertions.equal(
			placed.construction_stage,
			BuildingInstance.ConstructionStage.FOUNDATION,
			"pointer placement starts at foundation"
		)
		assertions.equal(
			main.action_controller.get_selected_slot(),
			0,
			"continuous placement keeps barn selected"
		)
		assertions.equal(
			main.building_system.get_selected_building_id(),
			"barn",
			"continuous placement restores barn preview"
		)
		assertions.truthy(
			main.building_system.is_in_build_mode(),
			"continuous placement keeps build preview active"
		)

		main.action_controller.switch_mode(PlayerActionController.ActionMode.FARMING)
		assertions.truthy(
			not main.building_system.is_in_build_mode(),
			"returning to farming clears the building preview"
		)
	main.free()


func _nearest_reachable_farm_cell(main: Node) -> GridCell:
	var player_position: Vector3 = main.player.global_position
	var interaction_range: float = main.player.interaction_range
	var best: GridCell
	var best_distance := INF
	for candidate in main.grid_system._cells.values():
		if not main.grid_system.can_farm_at(candidate.gx, candidate.gz):
			continue
		var point: Vector3 = candidate.world_position_3d()
		var distance := Vector2(
			player_position.x - point.x,
			player_position.z - point.z
		).length()
		if distance <= interaction_range and distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _nearest_build_origin(main: Node, building_id: String) -> GridCell:
	var player_position: Vector3 = main.player.global_position
	var best: GridCell
	var best_distance := INF
	for candidate in main.grid_system._cells.values():
		if not main.building_system.can_place(building_id, candidate.gx, candidate.gz):
			continue
		var point: Vector3 = candidate.world_position_3d()
		var distance := Vector2(
			player_position.x - point.x,
			player_position.z - point.z
		).length()
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best
