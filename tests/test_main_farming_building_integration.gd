extends RefCounted

func run(assertions: TestAssert, tree: SceneTree) -> void:
	var main_scene = load("res://scenes/main.tscn") as PackedScene
	assertions.truthy(main_scene != null, "main scene loads")
	if main_scene == null:
		return
	var main = main_scene.instantiate()
	var has_load_switch := _has_property(main, "load_save_on_start")
	assertions.truthy(
		has_load_switch,
		"main exposes deterministic save-load switch"
	)
	if not has_load_switch:
		main.free()
		return
	main.load_save_on_start = false
	tree.root.add_child(main)

	var action_controller = main.get_node_or_null("Actors/Player/ActionController")
	assertions.truthy(action_controller != null, "main authors player action controller")
	assertions.equal(main.action_controller, action_controller, "main exposes action controller")
	assertions.equal(action_controller.grid_system, main.grid_system, "controller shares main grid")
	assertions.equal(
		action_controller.farming_system,
		main.farming_system,
		"controller shares farming system"
	)
	assertions.equal(
		action_controller.building_system,
		main.building_system,
		"controller shares building system"
	)
	assertions.equal(
		action_controller.inventory_system,
		main.inventory_system,
		"controller shares inventory"
	)

	var game_data = tree.root.get_node_or_null("GameData")
	var grain: CropData = game_data.get_crop("grain") if game_data else null
	assertions.truthy(grain != null, "main registers grain crop")
	if grain:
		assertions.equal(grain.stage_scenes.size(), 4, "grain uses four verified stage scenes")
		for path in grain.stage_scenes:
			assertions.truthy(ResourceLoader.exists(path), "grain stage scene exists: %s" % path)

	assertions.equal(
		main.inventory_system.get_item_count("grain_seed"),
		20,
		"new game grants grain seed"
	)
	assertions.equal(
		main.inventory_system.get_quick_item(5),
		"grain_seed",
		"new game maps grain seed to slot six"
	)

	var farm_cell := _find_farm_cell(main.grid_system)
	assertions.truthy(farm_cell != null, "main has a buildable farm cell")
	if farm_cell:
		action_controller.select_slot(0)
		assertions.truthy(action_controller.perform_cell_action(farm_cell), "main player hoes cell")
		action_controller.select_slot(5)
		assertions.truthy(action_controller.perform_cell_action(farm_cell), "main player plants grain")
		assertions.equal(
			main.inventory_system.get_item_count("grain_seed"),
			19,
			"main planting consumes one seed"
		)
		action_controller.select_slot(1)
		assertions.truthy(action_controller.perform_cell_action(farm_cell), "main player waters grain")
		for day in range(3):
			main.farming_system.on_day_changed(day + 1)
		assertions.truthy(farm_cell.crop_instance.is_mature(), "main grain reaches maturity")
		var grain_before: int = main.inventory_system.get_item_count("grain")
		action_controller.select_slot(0)
		assertions.truthy(action_controller.perform_cell_action(farm_cell), "main player harvests grain")
		assertions.equal(
			main.inventory_system.get_item_count("grain"),
			grain_before + 1,
			"main harvest adds grain"
		)
		assertions.equal(
			farm_cell.state,
			GridCell.State.FARMLAND,
			"main harvest restores farmland"
		)

	var build_cell := _find_build_cell(main)
	assertions.truthy(build_cell != null, "main has a valid fence cell")
	if build_cell:
		assertions.truthy(
			main.building_system.enter_preview_mode("fence"),
			"main enters fence preview"
		)
		var building: BuildingInstance = action_controller.perform_build_action(
			build_cell.gx,
			build_cell.gz
		)
		assertions.truthy(building != null, "main player places fence")
		if building:
			assertions.equal(
				building.construction_stage,
				BuildingInstance.ConstructionStage.FOUNDATION,
				"main building starts at foundation"
			)

	var save_data: Dictionary = main.save_manager.call("_gather_save_data")
	assertions.truthy(save_data.has("inventory"), "save manager finds runtime inventory")
	if save_data.has("inventory"):
		assertions.equal(
			save_data.inventory.quick_mappings[5],
			main.inventory_system.quick_slot_mappings[5],
			"save manager preserves seed quick mapping"
		)

	main.free()


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false


func _find_farm_cell(grid: GridSystem) -> GridCell:
	for cell in grid._cells.values():
		if grid.can_farm_at(cell.gx, cell.gz):
			return cell
	return null


func _find_build_cell(main: Node) -> GridCell:
	for cell in main.grid_system._cells.values():
		if main.building_system.can_place("fence", cell.gx, cell.gz):
			return cell
	return null
