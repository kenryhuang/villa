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


class UpgradeWalletPlayer:
	extends RefCounted
	var level := 99


class UpgradeRejectingWallet:
	extends Node
	var gold := 1000
	var player_state := UpgradeWalletPlayer.new()
	var production: ProductionSystem
	var building: BuildingInstance

	func spend_gold(amount: int) -> bool:
		gold -= amount
		production.unregister_building(building)
		return true

	func add_gold(amount: int) -> bool:
		gold += amount
		return true


class CapacityEventRecorder:
	extends RefCounted
	var events: Array[Dictionary] = []

	func record(used: int, total: int) -> void:
		events.append({"used": used, "total": total})


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
		main.hud.debug_actions.visible,
		OS.is_debug_build(),
		"Main exposes debug actions only in debug builds"
	)
	assertions.truthy(
		main.hud.has_signal("debug_panel_requested"),
		"HUD exposes the runtime debug panel request"
	)
	if OS.is_debug_build():
		assertions.truthy(main.debug_state_editor != null, "Main creates a debug state editor")
		assertions.truthy(main.debug_panel != null, "Main creates a runtime debug panel")
		assertions.truthy(
			main.hud.debug_panel_requested.is_connected(
				Callable(main, "_on_debug_panel_requested")
			),
			"HUD debug panel request is connected to Main"
		)
		assertions.truthy(
			main.debug_panel.apply_requested.is_connected(
				Callable(main, "_on_debug_panel_apply_requested")
			),
			"runtime debug panel apply is connected to Main"
		)
		assertions.truthy(not main.debug_panel.visible, "runtime debug panel starts closed")
		main.hud.debug_panel_requested.emit()
		assertions.truthy(main.debug_panel.visible, "HUD request opens runtime debug panel")
		main.debug_panel.close()
		var progression_before: Dictionary = main.economy_progression_system.to_dict()
		var debug_state_before: Dictionary = main.debug_state_editor.snapshot()
		assertions.truthy(
			not main.economy_progression_system.is_blueprint_unlocked("barn"),
			"tier-one barn starts locked before a debug progression jump"
		)
		var progression_draft := debug_state_before.duplicate(true)
		progression_draft["level"] = 2
		progression_draft["elapsed_days"] = 7
		var progression_result: Dictionary = main.debug_state_editor.apply(progression_draft)
		assertions.truthy(
			bool(progression_result.get("ok", false)),
			"debug progression jump applies"
		)
		assertions.truthy(
			main.economy_progression_system.is_blueprint_unlocked("barn"),
			"debug progression jump grants gate-eligible blueprints"
		)
		assertions.truthy(
			main.economy_progression_system.is_recipe_unlocked("flour"),
			"debug blueprint grant includes its tier recipe"
		)
		assertions.truthy(
			str(main.building_system.diagnose_availability("barn").get("code", ""))
			!= "blueprint_locked",
			"building availability observes debug-unlocked blueprints"
		)
		assertions.truthy(
			main.economy_progression_system.from_dict(progression_before),
			"debug progression fixture restores blueprint ownership"
		)
		assertions.truthy(
			bool(main.debug_state_editor.apply(debug_state_before).get("ok", false)),
			"debug progression fixture restores actor and date state"
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
	assertions.truthy(_has_property(main, "farm_storage_system"), "main exposes central farm storage")
	if _has_property(main, "farm_storage_system"):
		assertions.truthy(main.farm_storage_system != null, "main instantiates central farm storage")
		assertions.equal(main.farm_storage_system.name, "FarmStorageSystem", "main names central farm storage")
		assertions.truthy(main.farm_storage_system.is_in_group("farm_storage_system"), "central storage joins discovery group")
		assertions.equal(main.farm_storage_system.get_total_capacity(), 200, "main starts with default storage capacity")
		assertions.equal(action_controller.farm_storage_system, main.farm_storage_system, "controller shares central farm storage")
		_test_farm_storage_capacity_lifecycle(assertions, main)
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
		"",
		"new game keeps planting command independent of quick mappings"
	)
	assertions.equal(
		main.action_controller.get_selected_plant_item_id(),
		"grain_seed",
		"new game initializes grain as the selected seed"
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
	var maintenance_day_before: int = main.production_system.get_current_day()
	assertions.truthy(
		main.production_system.set_maintenance_due_day(kiln, maintenance_day_before + 1),
		"main maintenance fixture enters the warning window"
	)
	assertions.equal(
		kiln.get_maintenance_visual_state(),
		"warning",
		"direct maintenance date change refreshes the building warning visual"
	)
	assertions.truthy(
		main.production_system.sync_daily_cursor(maintenance_day_before + 1),
		"direct date jump reaches the maintenance deadline"
	)
	assertions.equal(
		kiln.get_maintenance_visual_state(),
		"overdue",
		"direct date jump refreshes the building broken visual"
	)
	assertions.equal(
		kiln.get_node("EconomyIndicator").text,
		"",
		"broken buildings never render the legacy repair glyph"
	)
	main.production_system.set_maintenance_due_day(kiln, maintenance_day_before + 14)
	main.production_system.sync_daily_cursor(maintenance_day_before)
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
		var backpack_grain_before: int = main.inventory_system.get_item_count("grain")
		var storage_grain_before: int = main.farm_storage_system.get_count("grain")
		var expected_grain: int = int(
			main.farming_system.preview_harvest(farm_cell).items.grain
		)
		assertions.truthy(expected_grain >= 2 and expected_grain <= 4, "main grain uses authored yield range")
		action_controller.select_slot(0)
		assertions.truthy(action_controller.perform_cell_action(farm_cell), "main player harvests grain")
		assertions.equal(
			main.farm_storage_system.get_count("grain"),
			storage_grain_before + expected_grain,
			"main harvest adds grain to central storage"
		)
		assertions.equal(
			main.inventory_system.get_item_count("grain"),
			backpack_grain_before,
			"main harvest leaves backpack grain unchanged"
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
		"",
		"legacy seed migration clears only obsolete slot six mapping"
	)
	assertions.equal(
		main.action_controller.get_selected_plant_item_id(),
		"carrot_seed",
		"legacy seed migration preserves the mapped roster seed as selection"
	)

	main.inventory_system.reset_slots()
	main.inventory_system.slots[1] = {"item_id": "grain_seed", "quantity": 3}
	main.call("_auto_map_seed_to_quick_slot")
	assertions.equal(
		main.inventory_system.get_quick_item(5),
		"grain_seed",
		"auto seed map discovers and maps the seed in inventory"
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
		"",
		"debug reset keeps slot six independent of inventory mappings"
	)
	assertions.equal(
		main.action_controller.get_selected_plant_item_id(),
		"grain_seed",
		"debug reset restores the starter seed selection"
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


func _test_farm_storage_capacity_lifecycle(assertions: TestAssert, main: Node) -> void:
	var has_capacity_formula := main.has_method("_farm_storage_capacity")
	assertions.truthy(has_capacity_formula, "Main exposes the authoritative farm storage capacity formula")
	if not has_capacity_formula:
		return
	var slots_before: Array[Dictionary] = []
	slots_before.assign(main.inventory_system.slots.duplicate(true))
	var mappings_before: Array[int] = []
	mappings_before.assign(main.inventory_system.quick_slot_mappings.duplicate())
	var gold_before := int((main.get_node_or_null("/root/GameState") as Node).get("gold"))
	var recorder := CapacityEventRecorder.new()
	main.farm_storage_system.capacity_changed.connect(recorder.record)
	assertions.equal(main.call("_farm_storage_capacity"), 200, "no barns keeps base capacity 200")
	assertions.equal(main.farm_storage_system.get_total_capacity(), 200, "configured storage starts at derived base capacity")

	var first := _add_capacity_barn(main, 40, 40, false)
	assertions.equal(main.call("_farm_storage_capacity"), 200, "under-construction barn contributes zero")
	assertions.equal(main.farm_storage_system.get_total_capacity(), 200, "placing unfinished barn does not refresh capacity")
	assertions.equal(recorder.events, [], "unfinished barn emits no capacity event")
	var completion_token: Variant = main.farm_storage_system.begin_atomic_transaction()
	first.complete_construction()
	assertions.equal(main.call("_farm_storage_capacity"), 400, "one completed barn adds 200")
	assertions.equal(main.farm_storage_system.get_total_capacity(), 200, "in-flight completion defers cached capacity")
	assertions.equal(recorder.events, [], "in-flight completion emits no capacity event")
	assertions.truthy(
		main.farm_storage_system.commit_atomic_transaction(completion_token),
		"storage transaction publishes completed barn capacity"
	)
	assertions.equal(main.farm_storage_system.get_total_capacity(), 400, "completion refreshes at stable commit")
	assertions.equal(recorder.events, [{"used": 0, "total": 400}], "construction completion refreshes exactly once")
	main.farm_storage_system.refresh_capacity()
	assertions.equal(recorder.events.size(), 1, "unchanged authoritative refresh emits nothing")

	var current_day: int = main.production_system.get_current_day()
	assertions.truthy(main.production_system.set_maintenance_due_day(first, current_day), "barn can become maintenance overdue")
	assertions.truthy(main.production_system.is_maintenance_paused(first), "barn maintenance fixture is paused")
	assertions.equal(main.call("_farm_storage_capacity"), 400, "maintenance pause does not lower capacity")
	assertions.equal(recorder.events.size(), 1, "maintenance changes do not refresh farm storage")
	assertions.truthy(main.production_system.set_maintenance_due_day(first, current_day + 14), "barn maintenance fixture resets")

	var failed_quote: Dictionary = main.economy_progression_system.get_upgrade_quote(first, "storage")
	for item_id in failed_quote.materials:
		var needed: int = int(failed_quote.materials[item_id]) - main.inventory_system.get_item_count(str(item_id))
		if needed > 0:
			main.inventory_system.add_item(str(item_id), needed)
	var failed_slots: Array[Dictionary] = []
	failed_slots.assign(main.inventory_system.slots.duplicate(true))
	var failed_mappings: Array[int] = []
	failed_mappings.assign(main.inventory_system.quick_slot_mappings.duplicate())
	var original_wallet: Variant = main.economy_progression_system._wallet
	var rejecting_wallet := UpgradeRejectingWallet.new()
	rejecting_wallet.production = main.production_system
	rejecting_wallet.building = first
	main.add_child(rejecting_wallet)
	main.economy_progression_system._wallet = rejecting_wallet
	var failed_gold := rejecting_wallet.gold
	var failed_event_count := recorder.events.size()
	assertions.truthy(
		not main.economy_progression_system.upgrade(first, "storage"),
		"null-state barn domain failure rolls back upgrade transaction"
	)
	assertions.equal(rejecting_wallet.gold, failed_gold, "failed barn upgrade restores gold")
	assertions.equal(main.inventory_system.slots, failed_slots, "failed barn upgrade restores materials")
	assertions.equal(main.inventory_system.quick_slot_mappings, failed_mappings, "failed barn upgrade restores quick mappings")
	assertions.equal(
		main.economy_progression_system.get_upgrade_level(first, "storage"),
		0,
		"failed barn upgrade preserves prior level"
	)
	assertions.equal(first.producer_state, null, "failed barn upgrade keeps producer state null")
	assertions.equal(main.farm_storage_system.get_total_capacity(), 400, "failed barn upgrade preserves capacity")
	assertions.equal(recorder.events.size(), failed_event_count, "failed barn upgrade emits no capacity event")
	main.economy_progression_system._wallet = original_wallet
	assertions.truthy(main.production_system.register_building(first), "failed upgrade fixture re-registers barn")
	rejecting_wallet.free()

	for expected_level in range(1, 4):
		var quote: Dictionary = main.economy_progression_system.get_upgrade_quote(first, "storage")
		assertions.equal(quote.get("effect"), "中央仓库容量 +100", "barn upgrade quote exposes central capacity")
		var upgrade_token: Variant = null
		if expected_level == 1:
			upgrade_token = main.farm_storage_system.begin_atomic_transaction()
		assertions.truthy(
			main.economy_progression_system.upgrade(first, "storage"),
			"completed barn storage level %d commits" % expected_level
		)
		if expected_level == 1:
			assertions.equal(main.farm_storage_system.get_total_capacity(), 400, "in-flight upgrade defers cached capacity")
			assertions.equal(recorder.events.size(), 1, "in-flight upgrade emits no capacity event")
			assertions.truthy(
				main.farm_storage_system.commit_atomic_transaction(upgrade_token),
				"storage transaction publishes upgraded barn capacity"
			)
		assertions.equal(
			main.farm_storage_system.get_total_capacity(),
			400 + expected_level * 100,
			"barn storage level %d adds exactly 100" % expected_level
		)
		assertions.equal(recorder.events.size(), 1 + expected_level, "committed upgrade refreshes exactly once")
	assertions.equal(main.call("_farm_storage_capacity"), 700, "levels one through three derive 500, 600, and 700 totals")
	assertions.equal(first.producer_state, null, "barn storage levels do not create producer output state")

	var second := _add_capacity_barn(main, 44, 40, true)
	assertions.equal(main.farm_storage_system.get_total_capacity(), 900, "multiple completed barns stack base capacity")
	assertions.truthy(main.economy_progression_system.upgrade(second, "storage"), "second barn storage level commits")
	assertions.equal(main.farm_storage_system.get_total_capacity(), 1000, "multiple barn upgrade levels stack")
	assertions.equal(recorder.events.size(), 6, "second completion and upgrade each refresh once")

	var demolition_token: Variant = main.farm_storage_system.begin_atomic_transaction()
	assertions.truthy(
		main.farm_storage_system.stage_add_items(demolition_token, {"grain": 800}),
		"demolition fixture stages a harvest below the old total"
	)
	var first_key: String = main.economy_progression_system.building_key(first)
	assertions.truthy(main.building_system.remove_building(first), "upgraded barn demolition commits")
	assertions.equal(main.farm_storage_system.get_total_capacity(), 1000, "in-flight demolition defers cached capacity")
	assertions.equal(recorder.events.size(), 6, "in-flight demolition and harvest emit no early capacity event")
	assertions.truthy(
		main.farm_storage_system.commit_atomic_transaction(demolition_token),
		"staged harvest publishes after demolition reaches stable storage boundary"
	)
	assertions.equal(main.farm_storage_system.get_total_capacity(), 500, "demolition removes barn base and upgrade capacity")
	assertions.equal(main.farm_storage_system.get_count("grain"), 800, "demolition retains overloaded contents")
	assertions.truthy(not main.farm_storage_system.add_items({"grain": 1}), "overloaded storage blocks additions")
	assertions.truthy(
		not main.economy_progression_system.upgrade_levels.has(first_key),
		"demolition clears removed barn progression after capacity refresh"
	)
	assertions.equal(
		recorder.events.slice(recorder.events.size() - 2),
		[{"used": 800, "total": 1000}, {"used": 800, "total": 500}],
		"demolition publishes staged harvest before deferred overloaded capacity"
	)
	assertions.equal(recorder.events.back(), {"used": 800, "total": 500}, "demolition publishes the correct overloaded total")
	assertions.truthy(main.farm_storage_system.remove_items({"grain": 301}), "overload can be reduced by removals")
	assertions.truthy(main.farm_storage_system.add_items({"grain": 1}), "additions resume once contents fit capacity")

	assertions.truthy(main.building_system.remove_building(second), "second barn demolition commits")
	assertions.equal(main.farm_storage_system.get_total_capacity(), 200, "removing all barns restores base capacity")
	assertions.truthy(main.farm_storage_system.restore_items_unchecked({}), "capacity fixture clears central contents")
	main.inventory_system.restore_state(slots_before, mappings_before)
	main.hud.call("_refresh_material_counts")
	var game_state := main.get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.gold = gold_before
	main.farm_storage_system.capacity_changed.disconnect(recorder.record)


func _add_capacity_barn(
	main: Node,
	gx: int,
	gz: int,
	completed: bool
) -> BuildingInstance:
	var barn := BuildingInstance.new()
	main.buildings_container.add_child(barn)
	barn.configure(
		BuildingData.from_dictionary(GameDataScript.get_building("barn")),
		gx,
		gz,
		[]
	)
	barn.start_construction()
	main.building_system._buildings.append(barn)
	main.building_system.call("_connect_construction_signals", barn)
	main.building_system.building_instance_placed.emit(barn)
	if completed:
		barn.complete_construction()
	return barn


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
