extends RefCounted

const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const GameDataScript := preload("res://scripts/core/game_data.gd")
const TEST_OUTPUT_SAVE_SLOT := 1
const TEST_SAVE_SLOT := 4
const TEST_SIBLING_SAVE_SLOT := 2
const TEST_SAVE_DIR := "user://villa_test_saves/debug_reset/"

class FailingClearSaveManager:
	extends Node
	var current_slot := 0

	func clear_save(_slot: int) -> bool:
		return false


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var official_saves_before := _snapshot_save_directory(SaveManagerScript.SAVE_DIR)
	_cleanup_test_save_directory()
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
	var official_save_manager := tree.root.get_node_or_null("SaveManager")
	assertions.truthy(official_save_manager != null, "save manager autoload is available")
	if official_save_manager:
		assertions.truthy(
			official_save_manager.has_method("has_save"),
			"save manager can query a slot"
		)
		assertions.truthy(
			official_save_manager.has_method("clear_save"),
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
	var isolated_save_manager := SaveManagerScript.new()
	isolated_save_manager.name = "DebugResetTestSaveManager"
	isolated_save_manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(isolated_save_manager)
	assertions.truthy(
		not DirAccess.dir_exists_absolute(TEST_SAVE_DIR.trim_suffix("/")),
		"readying a save manager does not touch its save directory before a write"
	)
	main.save_manager = isolated_save_manager
	main.save_slot = TEST_SAVE_SLOT
	tree.root.add_child(main)
	var has_current_slot := _has_property(isolated_save_manager, "current_slot")
	assertions.truthy(has_current_slot, "save manager exposes its autosave slot")
	if has_current_slot:
		assertions.equal(
			isolated_save_manager.current_slot,
			TEST_SAVE_SLOT,
			"Main synchronizes its selected slot to autosave"
		)
	main.save_slot = 3
	assertions.equal(
		isolated_save_manager.current_slot,
		3,
		"changing Main's selected slot updates autosave immediately"
	)
	main.save_slot = TEST_SAVE_SLOT
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
	assertions.truthy(
		handler_source.contains("_cancel_debug_reload()"),
		"Main handler cancels the pending slot when reload fails"
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
		99,
		"new game grants grain seed"
	)
	assertions.equal(
		main.inventory_system.get_quick_item(5),
		"grain_seed",
		"new game maps grain seed to slot six"
	)
	assertions.equal(main.hud.get_material_count_text("wood"), "99", "HUD shows starting wood")
	assertions.equal(main.hud.get_material_count_text("stone"), "99", "HUD shows starting stone")
	assertions.equal(main.hud.get_material_count_text("iron"), "0", "HUD shows no legacy starter iron")
	assertions.equal(main.hud.get_material_count_text("glass"), "99", "HUD shows starting glass")

	var inventory_slots_before_output: Array[Dictionary] = []
	inventory_slots_before_output.assign(main.inventory_system.slots.duplicate(true))
	var quick_mappings_before_output: Array[int] = []
	quick_mappings_before_output.assign(main.inventory_system.quick_slot_mappings.duplicate())
	var kiln_data := BuildingData.from_dictionary(GameDataScript.get_building("stone_kiln"))
	var kiln := (load(kiln_data.scene_path) as PackedScene).instantiate() as BuildingInstance
	main.buildings_container.add_child(kiln)
	kiln.configure(kiln_data, 0, 0, [])
	kiln.complete_construction()
	main.call("_on_building_instance_placed", kiln)
	assertions.truthy(main.production_system.register_building(kiln), "output pickup fixture registers kiln")
	kiln.producer_state.outputs = {"charcoal": 2, "stone_brick": 3}
	main.production_system.refresh_indicator(kiln)
	var charcoal_before: int = main.inventory_system.get_item_count("charcoal")
	var output_display: Variant = kiln.get_node("BuildingOutputDisplay")
	var charcoal_pile: Variant = output_display.call("get_pile", "charcoal")
	assertions.truthy(charcoal_pile != null, "finished charcoal creates a clickable painted pile")
	if charcoal_pile != null:
		charcoal_pile.set_pointer_hovered(true)
		assertions.equal(
			charcoal_pile.tooltip_text(),
			"木炭 ×2",
			"charcoal hover exposes the stored quantity"
		)
		var charcoal_click := InputEventMouseButton.new()
		charcoal_click.button_index = MOUSE_BUTTON_LEFT
		charcoal_click.pressed = true
		charcoal_pile.handle_direct_pointer_event(charcoal_click, true, false)
	assertions.equal(
		main.inventory_system.get_item_count("charcoal"),
		charcoal_before + 2,
		"pile request reaches player assets"
	)
	assertions.equal(
		kiln.producer_state.outputs,
		{"stone_brick": 3},
		"pile request removes only represented item"
	)
	assertions.equal(
		kiln.get_output_pile_item_ids(),
		["stone_brick"],
		"unrequested output pile remains"
	)
	for slot_index in range(main.inventory_system.slots.size()):
		if main.inventory_system.slots[slot_index].is_empty():
			main.inventory_system.slots[slot_index] = {"item_id": "wood", "quantity": 99}
	var brick_pile: Variant = output_display.call("get_pile", "stone_brick")
	assertions.truthy(brick_pile != null, "finished bricks remain a clickable painted pile")
	if brick_pile != null:
		var brick_click := InputEventMouseButton.new()
		brick_click.button_index = MOUSE_BUTTON_LEFT
		brick_click.pressed = true
		brick_pile.handle_direct_pointer_event(brick_click, true, false)
	assertions.equal(
		kiln.producer_state.outputs,
		{"stone_brick": 3},
		"full inventory preserves represented output"
	)
	assertions.equal(
		main.hud.build_feedback_label.text,
		"资产库空间不足",
		"full inventory gives explicit pickup feedback"
	)
	main.production_system.unregister_building(kiln)
	main.call("_on_economy_building_removed", kiln)
	kiln.queue_free()
	main.inventory_system.restore_state(
		inventory_slots_before_output,
		quick_mappings_before_output
	)

	var load_completed_callback := Callable(main, "_on_save_load_completed")
	assertions.truthy(
		isolated_save_manager.load_completed.is_connected(load_completed_callback),
		"isolated save manager connects load completion to Main"
	)
	var restored_output_cell := _find_building_cell(main, "stone_kiln")
	assertions.truthy(restored_output_cell != null, "save/load fixture finds a valid kiln footprint")
	var placed_kiln: BuildingInstance
	var restored_kiln: BuildingInstance
	var restored_output_snapshots: Array[Dictionary] = []
	if restored_output_cell != null:
		placed_kiln = main.building_system.place_building_by_id(
			"stone_kiln",
			restored_output_cell.gx,
			restored_output_cell.gz
		)
	assertions.truthy(placed_kiln != null, "save/load fixture places kiln through BuildingSystem")
	if placed_kiln != null:
		for snapshot in placed_kiln.occupied_cells:
			restored_output_snapshots.append({
				"gx": snapshot.gx,
				"gz": snapshot.gz,
				"previous_state": snapshot.previous_state,
			})
		placed_kiln.complete_construction()
		assertions.truthy(
			main.production_system.get_registered_buildings().has(placed_kiln),
			"completed save/load kiln is registered for production"
		)
		placed_kiln.producer_state.outputs = {"charcoal": 2}
		main.production_system.refresh_indicator(placed_kiln)
		var restored_charcoal_before: int = main.inventory_system.get_item_count("charcoal")
		assertions.truthy(
			isolated_save_manager.save_game(TEST_OUTPUT_SAVE_SLOT),
			"output pickup lifecycle saves through isolated SaveManager"
		)
		assertions.truthy(
			isolated_save_manager.load_game(TEST_OUTPUT_SAVE_SLOT),
			"output pickup lifecycle loads through isolated SaveManager"
		)
		for candidate in main.building_system.get_all_buildings():
			if candidate.building_id == "stone_kiln":
				restored_kiln = candidate
				break
		assertions.truthy(restored_kiln != null, "save/load restores the kiln through BuildingSystem")
		if restored_kiln != null:
			assertions.truthy(restored_kiln != placed_kiln, "save/load replaces the original kiln instance")
			assertions.truthy(
				main.production_system.get_registered_buildings().has(restored_kiln),
				"save/load rebuilds production registration for the restored kiln"
			)
			var restored_output_display: Variant = restored_kiln.get_node("BuildingOutputDisplay")
			var restored_charcoal_pile: Variant = restored_output_display.call("get_pile", "charcoal")
			assertions.truthy(
				restored_charcoal_pile != null,
				"restored charcoal creates a clickable painted pile"
			)
			if restored_charcoal_pile != null:
				var restored_charcoal_click := InputEventMouseButton.new()
				restored_charcoal_click.button_index = MOUSE_BUTTON_LEFT
				restored_charcoal_click.pressed = true
				restored_charcoal_pile.handle_direct_pointer_event(
					restored_charcoal_click,
					true,
					false
				)
			assertions.equal(
				main.inventory_system.get_item_count("charcoal"),
				restored_charcoal_before + 2,
				"load completion reconnects restored output pickup to player assets"
			)
			assertions.equal(
				restored_kiln.producer_state.outputs,
				{},
				"restored output pickup clears collected charcoal"
			)
	var active_kiln: BuildingInstance
	for candidate in main.building_system.get_all_buildings():
		if candidate.building_id == "stone_kiln":
			active_kiln = candidate
			break
	if active_kiln != null:
		assertions.truthy(
			main.building_system.remove_building(active_kiln),
			"save/load fixture removes the restored kiln and restores its grid"
		)
	for snapshot in restored_output_snapshots:
		assertions.equal(
			main.grid_system.get_cell(snapshot.gx, snapshot.gz).state,
			snapshot.previous_state,
			"save/load fixture restores each kiln footprint cell"
		)
	main.save_slot = TEST_SAVE_SLOT
	assertions.truthy(
		isolated_save_manager.clear_save(TEST_OUTPUT_SAVE_SLOT),
		"save/load fixture clears its isolated output slot"
	)
	assertions.truthy(
		not isolated_save_manager.has_save(TEST_OUTPUT_SAVE_SLOT),
		"save/load fixture leaves no isolated output save"
	)
	main.inventory_system.restore_state(
		inventory_slots_before_output,
		quick_mappings_before_output
	)
	assertions.equal(
		main.building_system.get_building_count(),
		0,
		"save/load fixture leaves no buildings for later integration checks"
	)
	assertions.equal(
		main.inventory_system.slots,
		inventory_slots_before_output,
		"save/load fixture restores inventory for later integration checks"
	)
	assertions.equal(
		main.inventory_system.quick_slot_mappings,
		quick_mappings_before_output,
		"save/load fixture restores quick mappings for later integration checks"
	)
	assertions.equal(
		isolated_save_manager.current_slot,
		TEST_SAVE_SLOT,
		"save/load fixture restores the autosave slot for later integration checks"
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
			98,
			"main planting consumes one seed"
		)
		action_controller.select_slot(1)
		assertions.truthy(action_controller.perform_cell_action(farm_cell), "main player waters grain")
		var event_bus = tree.root.get_node_or_null("EventBus")
		var official_autosave_callback := Callable(
			official_save_manager,
			"_on_day_changed"
		)
		var official_autosave_was_connected: bool = (
			event_bus != null
			and official_save_manager != null
			and event_bus.day_changed.is_connected(official_autosave_callback)
		)
		if official_autosave_was_connected:
			event_bus.day_changed.disconnect(official_autosave_callback)
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
		if official_autosave_was_connected:
			event_bus.day_changed.connect(official_autosave_callback)
		assertions.truthy(
			FileAccess.file_exists(_test_save_path(TEST_SAVE_SLOT)),
			"day change autosaves the isolated current slot"
		)
		assertions.truthy(
			not FileAccess.file_exists(_test_save_path(0)),
			"day change never falls back to isolated slot zero"
		)
		assertions.truthy(farm_cell.crop_instance.is_mature(), "main grain reaches maturity")
		var grain_before: int = main.inventory_system.get_item_count("grain")
		var expected_grain: int = int(
			main.grid_system.preview_harvest(farm_cell.gx, farm_cell.gz).items.grain
		)
		assertions.truthy(expected_grain >= 2 and expected_grain <= 4, "main grain uses authored yield range")
		action_controller.select_slot(0)
		assertions.truthy(action_controller.perform_cell_action(farm_cell), "main player harvests grain")
		assertions.equal(
			main.inventory_system.get_item_count("grain"),
			grain_before + expected_grain,
			"main harvest adds grain"
		)
		assertions.equal(
			farm_cell.state,
			GridCell.State.FARMLAND,
			"main harvest restores farmland"
		)

	var occupied_cell_snapshots: Array[Dictionary] = []
	var build_cell := _find_build_cell(main)
	assertions.truthy(build_cell != null, "main has a valid fence cell")
	if build_cell:
		var wood_before_fence: int = main.inventory_system.get_item_count("wood")
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
			for snapshot in building.occupied_cells:
				occupied_cell_snapshots.append({
					"gx": snapshot.gx,
					"gz": snapshot.gz,
					"previous_state": snapshot.previous_state,
				})
			assertions.equal(
				main.inventory_system.get_item_count("wood"),
				wood_before_fence - 2,
				"main fence placement spends two wood"
			)
			assertions.equal(
				main.hud.get_material_count_text("wood"),
				str(wood_before_fence - 2),
				"HUD immediately reflects building material spend"
			)
			assertions.equal(
				building.construction_stage,
				BuildingInstance.ConstructionStage.FOUNDATION,
				"main building starts at foundation"
			)
			var wood_to_remove: int = main.inventory_system.get_item_count("wood") - 1
			assertions.truthy(
				main.inventory_system.remove_item("wood", wood_to_remove),
				"integration fixture drains wood below fence cost"
			)
			assertions.truthy(
				action_controller.switch_mode(PlayerActionController.ActionMode.BUILDING),
				"main switches to building palette with low materials"
			)
			assertions.truthy(
				action_controller.set_building_category("decoration"),
				"main selects decoration building category"
			)
			var fence_button := main.hud.quick_bar.get_child(1) as ActionPaletteButton
			assertions.truthy(
				fence_button.build_state == "missing_resources" and not fence_button.disabled,
				"real main HUD marks fence missing below two wood"
			)

	var save_data: Dictionary = main.save_manager.call("_gather_save_data")
	assertions.truthy(save_data.has("inventory"), "save manager finds runtime inventory")
	if save_data.has("inventory"):
		assertions.equal(
			save_data.inventory.quick_mappings[5],
			main.inventory_system.quick_slot_mappings[5],
			"save manager preserves seed quick mapping"
		)
	main.inventory_system.add_item("carrot_seed", 1)
	var carrot_slot := -1
	for slot_index in range(main.inventory_system.slots.size()):
		if main.inventory_system.slots[slot_index].get("item_id", "") == "carrot_seed":
			carrot_slot = slot_index
			break
	assertions.truthy(carrot_slot >= 0, "quick mapping fixture finds carrot seed")
	main.inventory_system.set_quick_slot(carrot_slot, PlayerActionController.SEED_SLOT)
	main.call("_backfill_legacy_grain_slot")
	assertions.equal(
		main.inventory_system.get_quick_item(PlayerActionController.SEED_SLOT),
		"carrot_seed",
		"legacy grain backfill preserves an active roster seed"
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
	var game_state := tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "game state autoload is available")
	if game_state:
		game_state.gold = 999
		game_state.player_state.stamina = 12
		game_state.player_state.max_stamina = 222
		game_state.player_state.level = 7
		game_state.player_state.exp = 345
		game_state.play_time = 456.0
		var reset_event_bus = tree.root.get_node_or_null("EventBus")
		if reset_event_bus:
			reset_event_bus.gold_changed.emit(game_state.gold)
			reset_event_bus.stamina_changed.emit(game_state.player_state.stamina)
			reset_event_bus.level_changed.emit(game_state.player_state.level)
			reset_event_bus.exp_gained.emit(0)
	var failing_save_manager := FailingClearSaveManager.new()
	tree.root.add_child(failing_save_manager)
	main.save_manager = failing_save_manager
	var wood_before_failed_clear: int = main.inventory_system.get_item_count("wood")
	assertions.truthy(
		not main.reset_debug_state(),
		"debug reset reports a save clear failure"
	)
	assertions.equal(
		main.building_system.get_building_count(),
		1,
		"save clear failure preserves runtime buildings"
	)
	assertions.equal(
		main.inventory_system.get_item_count("wood"),
		wood_before_failed_clear,
		"save clear failure preserves runtime inventory"
	)
	if game_state:
		assertions.equal(game_state.gold, 999, "save clear failure preserves game state")
	main.save_manager = isolated_save_manager
	failing_save_manager.free()
	assertions.truthy(
		main.save_manager.save_game(TEST_SAVE_SLOT),
		"debug reset fixture saves only the isolated slot"
	)
	assertions.truthy(
		main.save_manager.has_save(TEST_SAVE_SLOT),
		"save manager reports the isolated fixture save"
	)
	assertions.truthy(
		main.save_manager.save_game(TEST_SIBLING_SAVE_SLOT),
		"debug reset fixture creates a sibling slot"
	)
	var sibling_path := _test_save_path(TEST_SIBLING_SAVE_SLOT)
	var sibling_hash_before := FileAccess.get_sha256(sibling_path)
	var reset_result: bool = main.reset_debug_state()
	assertions.truthy(reset_result, "debug reset prepares a clean new game")
	assertions.equal(
		main.building_system.get_building_count(),
		0,
		"debug reset clears every building"
	)
	for snapshot in occupied_cell_snapshots:
		var restored_cell = main.grid_system.get_cell(snapshot.gx, snapshot.gz)
		assertions.truthy(restored_cell != null, "debug reset keeps occupied grid cells")
		if restored_cell:
			assertions.equal(
				restored_cell.state,
				snapshot.previous_state,
				"debug reset restores each building cell's previous state"
			)
	assertions.equal(
		main.inventory_system.get_item_count("wood"),
		99,
		"debug reset restores starter wood"
	)
	assertions.equal(
		main.inventory_system.get_item_count("stone"),
		99,
		"debug reset restores starter stone"
	)
	assertions.equal(
		main.inventory_system.get_item_count("iron"),
		0,
		"debug reset restores starter iron"
	)
	assertions.equal(
		main.inventory_system.get_item_count("glass"),
		99,
		"debug reset restores starter glass"
	)
	assertions.equal(
		main.inventory_system.get_item_count("grain_seed"),
		99,
		"debug reset restores starter grain seed"
	)
	assertions.equal(
		main.inventory_system.get_quick_item(5),
		"grain_seed",
		"debug reset restores the starter quick slot"
	)
	if game_state:
		assertions.equal(game_state.gold, 50_000, "debug reset restores starter gold")
		assertions.equal(
			game_state.player_state.stamina,
			100,
			"debug reset restores starter stamina"
		)
		assertions.equal(
			game_state.player_state.max_stamina,
			100,
			"debug reset restores maximum stamina"
		)
		assertions.equal(game_state.player_state.level, 1, "debug reset restores level one")
		assertions.equal(game_state.player_state.exp, 0, "debug reset clears experience")
		assertions.near(game_state.play_time, 0.0, 0.001, "debug reset clears play time")
		assertions.equal(main.hud.gold_label.text, "💰 50000", "debug reset refreshes HUD gold")
		assertions.near(main.hud.stamina_bar.value, 100.0, 0.001, "debug reset refreshes HUD stamina")
		assertions.equal(main.hud.level_label.text, "Lv.1", "debug reset refreshes HUD level")
		assertions.near(main.hud.exp_bar.value, 0.0, 0.001, "debug reset refreshes HUD experience")
	assertions.truthy(
		not main.save_manager.has_save(TEST_SAVE_SLOT),
		"debug reset deletes only the current isolated slot"
	)
	assertions.truthy(
		main.save_manager.has_save(TEST_SIBLING_SAVE_SLOT),
		"debug reset preserves a sibling save slot"
	)
	assertions.equal(
		FileAccess.get_sha256(sibling_path),
		sibling_hash_before,
		"debug reset leaves sibling save contents unchanged"
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
		isolated_save_manager.free()
		_cleanup_test_save_directory()
		return
	main.call("_prepare_debug_reload")
	var has_reload_cancel := main.has_method("_cancel_debug_reload")
	assertions.truthy(has_reload_cancel, "Main can cancel a failed debug reload handoff")
	if has_reload_cancel:
		main.call("_cancel_debug_reload")
	var cancelled_reload_probe = main_scene.instantiate()
	cancelled_reload_probe.call("_consume_debug_reload_save_slot")
	assertions.equal(
		cancelled_reload_probe.save_slot,
		0,
		"a failed reload cannot leak its pending slot into a later Main"
	)
	cancelled_reload_probe.free()
	main.call("_prepare_debug_reload")

	main.free()
	var reloaded_main = main_scene.instantiate()
	reloaded_main.load_save_on_start = false
	reloaded_main.save_manager = isolated_save_manager
	tree.root.add_child(reloaded_main)
	assertions.equal(
		reloaded_main.save_slot,
		TEST_SAVE_SLOT,
		"a reloaded Main continues the reset slot instead of loading slot zero"
	)
	assertions.equal(
		isolated_save_manager.current_slot,
		TEST_SAVE_SLOT,
		"reloaded Main keeps autosave on the inherited slot"
	)
	reloaded_main.free()
	isolated_save_manager.free()
	_cleanup_test_save_directory()
	assertions.truthy(
		not DirAccess.dir_exists_absolute(TEST_SAVE_DIR.trim_suffix("/")),
		"debug reset integration removes its isolated save directory"
	)
	assertions.equal(
		_snapshot_save_directory(SaveManagerScript.SAVE_DIR),
		official_saves_before,
		"debug reset integration leaves every official save file unchanged"
	)


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


func _snapshot_save_directory(directory: String) -> Dictionary:
	var snapshot := {
		"exists": DirAccess.dir_exists_absolute(directory.trim_suffix("/")),
		"files": {},
	}
	var dir := DirAccess.open(directory)
	if dir == null:
		return snapshot
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir():
			var path := directory.path_join(file_name)
			snapshot.files[file_name] = {
				"sha256": FileAccess.get_sha256(path),
				"modified": FileAccess.get_modified_time(path),
			}
		file_name = dir.get_next()
	dir.list_dir_end()
	return snapshot


func _cleanup_test_save_directory() -> void:
	for slot in [0, TEST_OUTPUT_SAVE_SLOT, TEST_SIBLING_SAVE_SLOT, TEST_SAVE_SLOT]:
		var path := TEST_SAVE_DIR.path_join("save_%d.json" % slot)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var directory_path := TEST_SAVE_DIR.trim_suffix("/")
	if DirAccess.dir_exists_absolute(directory_path):
		DirAccess.remove_absolute(directory_path)


func _test_save_path(slot: int) -> String:
	return TEST_SAVE_DIR.path_join("save_%d.json" % slot)


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


func _find_building_cell(main: Node, building_id: String) -> GridCell:
	for gz in range(GridSystem.GRID_DEPTH):
		for gx in range(GridSystem.GRID_WIDTH):
			if main.building_system.can_place_building(building_id, gx, gz):
				return main.grid_system.get_cell(gx, gz)
	return null
