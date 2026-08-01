extends RefCounted

const TEST_SAVE_SLOT := 4
const TEST_SAVE_PATH := "user://villa_saves/save_4.json"

func run(assertions: TestAssert, tree: SceneTree) -> void:
	_cleanup_test_save()
	var main_scene = load("res://scenes/main.tscn") as PackedScene
	assertions.truthy(main_scene != null, "main scene loads")
	if main_scene == null:
		return
	var default_main = main_scene.instantiate()
	var has_save_slot := _has_property(default_main, "save_slot")
	assertions.truthy(has_save_slot, "main exposes a current save slot")
	if has_save_slot:
		assertions.equal(default_main.save_slot, 0, "main defaults to save slot zero")
	assertions.truthy(
		default_main.has_method("reset_debug_state"),
		"main exposes debug reset state preparation"
	)
	default_main.free()
	var save_manager := tree.root.get_node_or_null("SaveManager")
	assertions.truthy(save_manager != null, "save manager autoload is available")
	if save_manager:
		assertions.truthy(save_manager.has_method("has_save"), "save manager can query a slot")
		assertions.truthy(
			save_manager.has_method("clear_save"),
			"save manager can idempotently clear a slot"
		)

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
	if not has_save_slot:
		main.free()
		return
	main.save_slot = TEST_SAVE_SLOT
	tree.root.add_child(main)
	assertions.truthy(
		main.hud.debug_reset_requested.is_connected(
			Callable(main, "_on_debug_reset_requested")
		),
		"HUD debug reset request is connected to Main"
	)
	assertions.equal(
		main.hud.debug_reset_button.visible,
		OS.is_debug_build(),
		"Main exposes the reset button only in debug builds"
	)
	var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	var initial_state_source := _get_method_source(main_source, "_initial_game_state")
	assertions.truthy(
		initial_state_source.contains("save_manager.load_game(save_slot)"),
		"Main loads its selected save slot at startup"
	)
	var reset_source := _get_method_source(main_source, "reset_debug_state")
	assertions.truthy(
		reset_source.contains("OS.is_debug_build()"),
		"Main debug reset state method enforces the release-build gate"
	)
	var handler_source := _get_method_source(main_source, "_on_debug_reset_requested")
	assertions.truthy(
		handler_source.contains("OS.is_debug_build()"),
		"Main debug reset handler independently enforces the release-build gate"
	)
	assertions.truthy(
		handler_source.contains("_prepare_debug_reload()"),
		"Main handler preserves the selected slot before reloading"
	)

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
	assertions.truthy(
		_has_property(main.build_ui, "keyboard_shortcut_enabled"),
		"legacy build UI exposes shortcut ownership"
	)
	if _has_property(main.build_ui, "keyboard_shortcut_enabled"):
		assertions.truthy(
			not main.build_ui.keyboard_shortcut_enabled,
			"main disables the legacy build UI B shortcut"
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
	assertions.equal(main.hud.get_material_count_text("wood"), "250", "HUD shows starting wood")
	assertions.equal(main.hud.get_material_count_text("stone"), "150", "HUD shows starting stone")
	assertions.equal(main.hud.get_material_count_text("iron"), "50", "HUD shows starting iron")
	assertions.equal(main.hud.get_material_count_text("glass"), "50", "HUD shows starting glass")

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
		var event_bus = tree.root.get_node_or_null("EventBus")
		var autosave_callback := Callable(main.save_manager, "_on_day_changed")
		var autosave_was_connected: bool = (
			event_bus != null
			and event_bus.day_changed.is_connected(autosave_callback)
		)
		if autosave_was_connected:
			event_bus.day_changed.disconnect(autosave_callback)
		var next_day := InputEventKey.new()
		next_day.keycode = KEY_N
		next_day.pressed = true
		main._unhandled_input(next_day)
		assertions.near(
			farm_cell.crop_instance.growth_progress,
			1.5,
			0.001,
			"debug N advances watered grain through the normal day event"
		)
		assertions.equal(
			farm_cell.crop_instance.get_current_stage(),
			1,
			"first watered day displays the sprout stage"
		)
		assertions.equal(main.hud.season_label.text, "春 2/7", "debug N refreshes the HUD day")
		assertions.truthy(
			action_controller.perform_cell_action(farm_cell),
			"grain can be watered again on the next day"
		)
		main._unhandled_input(next_day)
		if autosave_was_connected:
			event_bus.day_changed.connect(autosave_callback)
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
				main.inventory_system.get_item_count("wood"),
				240,
				"main fence placement spends ten wood"
			)
			assertions.equal(
				main.hud.get_material_count_text("wood"),
				"240",
				"HUD immediately reflects building material spend"
			)
			assertions.equal(
				building.construction_stage,
				BuildingInstance.ConstructionStage.FOUNDATION,
				"main building starts at foundation"
			)
			assertions.truthy(
				main.inventory_system.remove_item("wood", 231),
				"integration fixture drains wood below fence cost"
			)
			assertions.truthy(
				action_controller.switch_mode(PlayerActionController.ActionMode.BUILDING),
				"main switches to building palette with low materials"
			)
			var fence_button := main.hud.quick_bar.get_child(8) as Button
			assertions.truthy(
				fence_button.disabled,
				"real main HUD disables fence below ten wood"
			)

	var save_data: Dictionary = main.save_manager.call("_gather_save_data")
	assertions.truthy(save_data.has("inventory"), "save manager finds runtime inventory")
	if save_data.has("inventory"):
		assertions.equal(
			save_data.inventory.quick_mappings[5],
			main.inventory_system.quick_slot_mappings[5],
			"save manager preserves seed quick mapping"
		)

	main.inventory_system.reset_slots()
	main.inventory_system.slots[1] = {"item_id": "grain_seed", "quantity": 3}
	assertions.truthy(
		main.call("_map_grain_seed_to_quick_slot"),
		"legacy seed backfill skips empty dictionary slots"
	)
	assertions.equal(
		main.inventory_system.get_quick_item(5),
		"grain_seed",
		"legacy seed backfill maps the discovered dictionary slot"
	)

	assertions.equal(
		main.building_system.get_building_count(),
		1,
		"debug reset fixture has one real building"
	)
	assertions.truthy(
		main.save_manager.save_game(TEST_SAVE_SLOT),
		"debug reset fixture saves only the isolated slot"
	)
	assertions.truthy(
		main.save_manager.has_save(TEST_SAVE_SLOT),
		"save manager reports the isolated fixture save"
	)
	var reset_result: bool = main.reset_debug_state()
	assertions.truthy(reset_result, "debug reset prepares a clean new game")
	assertions.equal(
		main.building_system.get_building_count(),
		0,
		"debug reset clears every building"
	)
	assertions.equal(
		main.inventory_system.get_item_count("wood"),
		250,
		"debug reset restores starter wood"
	)
	assertions.equal(
		main.inventory_system.get_item_count("stone"),
		150,
		"debug reset restores starter stone"
	)
	assertions.equal(
		main.inventory_system.get_item_count("iron"),
		50,
		"debug reset restores starter iron"
	)
	assertions.equal(
		main.inventory_system.get_item_count("glass"),
		50,
		"debug reset restores starter glass"
	)
	assertions.equal(
		main.inventory_system.get_item_count("grain_seed"),
		20,
		"debug reset restores starter grain seed"
	)
	assertions.equal(
		main.inventory_system.get_quick_item(5),
		"grain_seed",
		"debug reset restores the starter quick slot"
	)
	assertions.truthy(
		not main.save_manager.has_save(TEST_SAVE_SLOT),
		"debug reset deletes only the current isolated slot"
	)
	assertions.truthy(
		main.save_manager.clear_save(TEST_SAVE_SLOT),
		"clearing a missing save is idempotent"
	)
	assertions.truthy(
		not main.save_manager.delete_save(TEST_SAVE_SLOT),
		"legacy delete keeps returning false for a missing save"
	)
	var has_reload_slot_handoff := main.has_method("_prepare_debug_reload")
	assertions.truthy(
		has_reload_slot_handoff,
		"Main can preserve its current slot across a scene reload"
	)
	if not has_reload_slot_handoff:
		main.free()
		_cleanup_test_save()
		return
	main.call("_prepare_debug_reload")

	main.free()
	var reloaded_main = main_scene.instantiate()
	reloaded_main.load_save_on_start = false
	tree.root.add_child(reloaded_main)
	assertions.equal(
		reloaded_main.save_slot,
		TEST_SAVE_SLOT,
		"a reloaded Main continues the reset slot instead of loading slot zero"
	)
	reloaded_main.free()
	_cleanup_test_save()


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false


func _get_method_source(source: String, method_name: String) -> String:
	var start := source.find("func %s(" % method_name)
	if start < 0:
		return ""
	var next_method := source.find("\nfunc ", start + 1)
	return source.substr(start) if next_method < 0 else source.substr(start, next_method - start)


func _cleanup_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)


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
