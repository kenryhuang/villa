extends RefCounted

const BUILDING_ECONOMY_UI_SCRIPT := "res://scripts/ui/building_economy_ui.gd"
const ProductionSystemScript = preload("res://scripts/systems/production_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const ProgressionSystemScript = preload("res://scripts/systems/economy_progression_system.gd")
const ModalCoordinatorScript = preload("res://scripts/ui/economy_modal_coordinator.gd")
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")
const ToolSystemScript = preload("res://scripts/systems/tool_system.gd")

const UI_SCENE := "res://scenes/ui/economy/building_economy_ui.tscn"
const PRODUCTION_SCENE := "res://scenes/ui/economy/building_production_panel.tscn"
const STATUS_SCENE := "res://scenes/ui/economy/building_status_panel.tscn"
const MAINTENANCE_SCENE := "res://scenes/ui/economy/building_maintenance_card.tscn"

var _owned_nodes: Array[Node] = []


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_owned_nodes.clear()
	_test_routing(assertions)
	_test_scene_contracts(assertions)
	if not _feature_resources_exist():
		return
	await _test_production_panel_transactions_and_persistence(assertions, tree)
	await _test_status_view_data_and_atomic_actions(assertions, tree)
	await _test_range_and_modal_lifecycle(assertions, tree)
	await _test_main_route_and_construction_regression(assertions, tree)
	_cleanup_nodes()


func _test_routing(assertions: TestAssert) -> void:
	assertions.truthy(ResourceLoader.exists(BUILDING_ECONOMY_UI_SCRIPT), "building economy router script exists")
	if not ResourceLoader.exists(BUILDING_ECONOMY_UI_SCRIPT):
		return
	var BuildingEconomyUIScript = load(BUILDING_ECONOMY_UI_SCRIPT)
	assertions.equal(BuildingEconomyUIScript.panel_kind_for("windmill", "crafting"), "production", "windmill uses production panel")
	assertions.equal(BuildingEconomyUIScript.panel_kind_for("beehive", "honey"), "status", "hive uses status panel")
	assertions.equal(BuildingEconomyUIScript.panel_kind_for("waterwheel", "irrigation"), "status", "waterwheel uses status panel")
	assertions.equal(BuildingEconomyUIScript.panel_kind_for("unknown", ""), "", "unknown effect opens nothing")


func _test_scene_contracts(assertions: TestAssert) -> void:
	_check_scene(assertions, UI_SCENE, [
		"ScreenLayer/ModalLayer/BuildingPanel/Margin/Shell/Header/TitleLabel",
		"ScreenLayer/ModalLayer/BuildingPanel/Margin/Shell/Header/StateLabel",
		"ScreenLayer/ModalLayer/BuildingPanel/Margin/Shell/Header/CloseButton",
		"ScreenLayer/ModalLayer/BuildingPanel/Margin/Shell/PageHost/ProductionPanel",
		"ScreenLayer/ModalLayer/BuildingPanel/Margin/Shell/PageHost/StatusPanel",
		"WorldRangeOverlay",
	])
	_check_scene(assertions, PRODUCTION_SCENE, [
		"Sections/RecipeColumn/Content/RecipeScroll/RecipeList",
		"Sections/ProcessColumn/Content/Flow/InputItems/InputLabel",
		"Sections/ProcessColumn/Content/Flow/OutputItems/OutputLabel",
		"Sections/ProcessColumn/Content/Metrics/DurationLabel",
		"Sections/ProcessColumn/Content/Metrics/PricingLabel",
		"Sections/ProcessColumn/Content/MissingLabel",
		"Sections/RightColumn/Content/QueueCard/QueueScroll/QueueSlots",
		"Sections/RightColumn/Content/StorageCard/StorageList",
		"Sections/RightColumn/Content/StorageCard/CollectAllButton",
		"FeedbackLabel",
		"Sections/ProcessColumn/Content/BatchControls/BatchSpinBox",
		"Sections/ProcessColumn/Content/BatchControls/MaxButton",
		"Sections/ProcessColumn/Content/BatchControls/StartButton",
	])
	_check_scene(assertions, STATUS_SCENE, [
		"MaintenanceCard",
		"SummaryFields",
		"InputActions",
		"StorageList",
		"Actions/CollectAllButton",
		"Actions/RangePreviewButton",
		"FeedbackLabel",
	])
	_check_scene(assertions, MAINTENANCE_SCENE, [
		"Header/StateDot",
		"Header/StateLabel",
		"DeadlineLabel",
		"Costs/GoldLabel",
		"Costs/WoodLabel",
		"Costs/StoneLabel",
		"RepairProgress",
		"ActionButton",
		"FeedbackLabel",
	])
	var production_panel := (load(PRODUCTION_SCENE) as PackedScene).instantiate() as Control
	var sections := production_panel.get_node("Sections") as HBoxContainer
	var recipe_card := production_panel.get_node("Sections/RecipeColumn") as Control
	var process_card := production_panel.get_node("Sections/ProcessColumn") as Control
	var activity_card := production_panel.get_node("Sections/RightColumn") as Control
	assertions.equal(recipe_card.custom_minimum_size.x, 280.0, "production recipe card has a stable width")
	assertions.equal(process_card.custom_minimum_size.x, 520.0, "production process card owns the center")
	assertions.equal(activity_card.custom_minimum_size.x, 300.0, "production activity card has a stable width")
	assertions.equal(recipe_card.size_flags_horizontal, Control.SIZE_FILL, "production recipe card remains fixed width")
	assertions.equal(activity_card.size_flags_horizontal, Control.SIZE_FILL, "production activity card remains fixed width")
	assertions.equal(process_card.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "production process card receives flexible width")
	assertions.equal(sections.get_theme_constant("separation"), 16, "production cards use the shared grid gap")
	for control_path in [
		"Sections/ProcessColumn/Content/BatchControls/BatchSpinBox",
		"Sections/ProcessColumn/Content/BatchControls/MaxButton",
		"Sections/ProcessColumn/Content/BatchControls/StartButton",
		"Sections/RightColumn/Content/StorageCard/CollectAllButton",
	]:
		assertions.equal(
			(production_panel.get_node(control_path) as Control).custom_minimum_size.y,
			44.0,
			"production control %s uses the standard height" % control_path
		)
	assertions.equal(
		(production_panel.get_node("Sections/ProcessColumn/Content/BatchControls/StartButton") as Control).custom_minimum_size.x,
		148.0,
		"production primary action uses the designed width"
	)
	production_panel.free()


func _feature_resources_exist() -> bool:
	return ResourceLoader.exists(BUILDING_ECONOMY_UI_SCRIPT) and ResourceLoader.exists(UI_SCENE) and ResourceLoader.exists(PRODUCTION_SCENE) and ResourceLoader.exists(STATUS_SCENE) and ResourceLoader.exists("res://scripts/ui/world_range_overlay.gd")


func _test_production_panel_transactions_and_persistence(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _systems_fixture()
	var production: ProductionSystem = fixture.production
	var inventory: InventorySystem = fixture.inventory
	var progression: EconomyProgressionSystem = fixture.progression
	_unlock_recipe(progression, "flour")
	production.set_progression_system(progression)
	inventory.add_item("grain", 8)
	var windmill := _scene_building("windmill", tree)
	production.register_building(windmill)
	var ui = _instantiate_scene(UI_SCENE, tree)
	var modal := ModalCoordinatorScript.new()
	assertions.truthy(ui.configure(production, inventory, progression, fixture.grid, modal), "building UI configures real economy systems")
	assertions.truthy(ui.configure(production, inventory, progression, fixture.grid, modal), "repeated building UI configure is idempotent")
	var locked_workbench := _scene_building("workbench", tree)
	production.register_building(locked_workbench)
	assertions.truthy(ui.open_for(locked_workbench), "workbench opens with locked advanced recipes visible")
	var locked_panel = ui.production_panel
	var crate_row := {}
	for row in locked_panel.recipe_rows:
		if str(row.get("recipe_id", "")) == "wooden_crate":
			crate_row = row
			break
	assertions.truthy(not crate_row.is_empty(), "locked wooden crate recipe remains in the list")
	assertions.equal(crate_row.get("unlock_service_id"), "recipe_wooden_crate", "locked recipe exposes its service target")
	var crate_button := locked_panel.recipe_list.get_node_or_null("Recipe_wooden_crate") as Button
	assertions.truthy(crate_button != null and not crate_button.disabled, "locked recipe remains clickable")
	assertions.truthy(ui.has_signal("unlock_requested"), "building economy UI forwards recipe unlock requests")
	var unlock_requests: Array[String] = []
	if ui.has_signal("unlock_requested"):
		ui.connect("unlock_requested", func(service_id: String) -> void: unlock_requests.append(service_id))
	if crate_button != null:
		crate_button.pressed.emit()
	assertions.equal(unlock_requests, ["recipe_wooden_crate"], "locked recipe click requests its exact service")
	ui.close()
	assertions.truthy(ui.open_for(windmill), "completed windmill opens")
	var panel = ui.production_panel
	assertions.equal(panel.recipe_rows.size(), 3, "windmill exposes all three recipes")
	panel.apply_responsive_layout(Vector2(800.0, 720.0))
	panel.open_details_drawer()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	ui.call("_unhandled_input", escape)
	assertions.truthy(ui.is_open(), "first Escape returns from production details without closing the building window")
	assertions.truthy(panel.recipe_card.visible, "first Escape restores the production recipe list")
	assertions.equal(panel.process_card.get_parent(), panel.sections, "first Escape restores the production card hierarchy")
	panel.apply_responsive_layout(Vector2(1920.0, 1080.0))
	var first_recipe_button := panel.recipe_list.get_child(0) as Button
	assertions.equal(first_recipe_button.custom_minimum_size.y, 52.0, "dynamic recipe rows use the aligned list height")
	assertions.truthy(first_recipe_button.clip_text, "dynamic recipe names clip inside the recipe card")
	assertions.equal(first_recipe_button.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "dynamic recipe names use ellipsis")
	assertions.equal(panel.storage_capacity_label.text, "产物种类 0/3", "crafting storage shows authoritative output type slots")
	panel.select_recipe("flour")
	panel.set_batches(1)
	assertions.truthy(panel.pricing_label.text.contains("盈利"), "recipe margin renders in Chinese")
	assertions.truthy(not panel.pricing_label.text.contains("profit"), "recipe margin hides internal status keys")
	assertions.equal(panel.recipe_detail.get("inputs"), {"grain": 2}, "recipe details expose exact inputs")
	assertions.equal(panel.recipe_detail.get("outputs"), {"flour": 1}, "recipe details expose exact outputs")
	assertions.equal(panel.queue_slots.size(), 2, "production view always exposes two queue slots")
	assertions.equal(panel.queue_slot_nodes[0].custom_minimum_size.y, 52.0, "queue slots use the shared dynamic row height")
	assertions.truthy(panel.recipe_detail.has("margin_status"), "recipe detail exposes margin status")
	assertions.truthy(panel.recipe_detail.has("duration_minutes"), "recipe detail exposes duration")
	var grain_before := inventory.get_item_count("grain")
	panel.start_button.pressed.emit()
	assertions.equal(inventory.get_item_count("grain"), grain_before - 2, "one press deducts one batch exactly once after repeated configure")
	assertions.equal(windmill.producer_state.jobs.size(), 1, "one press creates one authoritative job")
	assertions.equal(panel.queue_slot_nodes[0].get_node("Content/Header/StateLabel").text, "生产中", "running queue state renders in Chinese")
	assertions.equal(ui.state_label.text, "运行中", "shell title state updates in the same frame when production starts")
	ui.close()
	assertions.truthy(
		ui.production_panel.has_method("_flush_snapshot_refresh"),
		"production panel exposes a deferred event refresh flush"
	)
	assertions.truthy(
		ui.status_panel.has_method("_flush_snapshot_refresh"),
		"status panel exposes a deferred event refresh flush"
	)
	var event_bus := tree.root.get_node_or_null("EventBus")
	if event_bus != null:
		event_bus.item_added.emit("wood", 1)
	assertions.equal(
		ui.production_panel.get("_snapshot_refresh_queued"),
		false,
		"hidden production panel skips inventory refresh work"
	)
	assertions.equal(
		ui.status_panel.get("_snapshot_refresh_queued"),
		false,
		"hidden status panel skips inventory refresh work"
	)
	assertions.truthy(ui.open_for(windmill), "windmill reopens")
	assertions.equal(windmill.producer_state.jobs.size(), 1, "closing and reopening preserves authoritative job")
	assertions.equal(ui.production_panel.selected_recipe_id, "flour", "closing preserves selected recipe")
	assertions.equal(ui.production_panel.batches, 1, "temporary batch resets on reopen")
	ui.status_tab.pressed.emit()
	ui.production_panel.snapshot = {"debug_stale": true}
	if event_bus != null:
		event_bus.item_added.emit("wood", 1)
	assertions.equal(
		ui.production_panel.get("_snapshot_refresh_queued"),
		false,
		"hidden production tab defers work until selected"
	)
	ui.production_tab.pressed.emit()
	assertions.truthy(
		not ui.production_panel.snapshot.has("debug_stale"),
		"selecting a previously hidden building tab refreshes authoritative state"
	)
	production.advance_minutes(360)
	panel.refresh_snapshot()
	assertions.equal(ui.state_label.text, "空闲", "shell title state updates in the same frame when production finishes")

	var missing_windmill := _scene_building("windmill", tree)
	production.register_building(missing_windmill)
	ui.open_for(missing_windmill)
	panel.select_recipe("flour")
	inventory.remove_item("grain", inventory.get_item_count("grain"))
	panel.set_batches(2)
	assertions.equal(panel.preflight.get("missing"), {"grain": 4}, "missing material view reports exact multiplied quantity")
	assertions.truthy(panel.disabled_reason.contains("×4"), "disabled reason displays exact missing quantity")

	var blocked_inventory := InventorySystemScript.new() as InventorySystem
	_track(blocked_inventory)
	blocked_inventory.add_item("grain", 2)
	var blocked_production := ProductionSystemScript.new() as ProductionSystem
	_track(blocked_production)
	blocked_production.set_progression_system(progression)
	var blocked := _scene_building("windmill", tree)
	blocked.producer_state.outputs = {"wood": 1, "stone": 1, "fiber": 1}
	blocked_production.register_building(blocked)
	assertions.truthy(blocked_production.start_recipe(blocked, "flour", 1, blocked_inventory), "output-full fixture starts through ProductionSystem")
	blocked_production.advance_minutes(360)
	ui.configure(blocked_production, blocked_inventory, progression, fixture.grid, modal)
	ui.open_for(blocked)
	panel = ui.production_panel
	assertions.equal(panel.queue_slots[0].state, "output-full", "UI output-full state comes from production snapshot")
	assertions.equal(panel.queue_slot_nodes[0].get_node("Content/Header/StateLabel").text, "产物已满", "output-full queue state renders in Chinese")
	assertions.equal(ui.state_label.text, "仓满暂停", "shell title state reflects output-full immediately")
	blocked_production.set_maintenance_due_day(blocked, blocked_production.get_current_day())
	panel.refresh_snapshot()
	assertions.equal(panel.queue_slots[0].state, "maintenance-paused", "UI maintenance pause comes from production snapshot")
	assertions.equal(panel.queue_slot_nodes[0].get_node("Content/Header/StateLabel").text, "维护暂停", "maintenance queue state renders in Chinese")
	assertions.equal(ui.state_label.text, "维护暂停", "shell title state reflects maintenance immediately")
	ui.close()
	assertions.truthy(ui.open_for(blocked), "overdue crafting building reopens")
	assertions.truthy(ui.status_panel.visible, "overdue crafting building opens maintenance status page")
	assertions.truthy(not ui.production_tab.disabled, "overdue crafting building keeps production tab available")
	assertions.truthy(not ui.status_tab.disabled, "overdue crafting building keeps status tab available")
	ui.production_tab.pressed.emit()
	assertions.truthy(ui.production_panel.visible, "crafting production tab remains selectable during repair stop")
	var connections: int = panel.get_signal_connection_list("snapshot_changed").size() if panel.has_signal("snapshot_changed") else 0
	assertions.equal(connections, 1, "repeated configure keeps exactly one shell snapshot listener")
	blocked.producer_state.outputs = {"honey": 2}
	blocked_inventory.max_slots = 1
	blocked_inventory.reset_slots()
	blocked_inventory.add_item("honey", 98)
	panel.refresh_snapshot()
	var output_row := panel.storage_list.get_child(0) as Control
	assertions.equal(output_row.custom_minimum_size.y, 52.0, "dynamic output rows use the aligned list height")
	assertions.truthy(output_row.has_node("CollectButton"), "dynamic output rows expose an independent collect control")
	panel.request_collect_item("honey")
	assertions.equal(panel.failure_reason, "inventory_capacity", "production item collect exposes structured capacity reason")
	assertions.truthy(panel.failure_message.contains("×1"), "production item collect shows exact missing quantity")
	panel.request_collect_all()
	assertions.equal(panel.failure_reason, "inventory_capacity", "production collect-all exposes structured capacity reason")
	panel.refresh_snapshot()
	assertions.truthy(panel.feedback_label.text.contains("×1"), "production collection failure survives refresh")

	var upgraded := _scene_building("windmill", tree)
	upgraded.grid_x = 12
	production.register_building(upgraded)
	assertions.truthy(production.apply_upgrade(upgraded, "queue_slots", 2), "level-two queue upgrade applies through ProductionSystem")
	upgraded.producer_state.jobs.assign([
		{"recipe_id": "flour", "batches": 1, "remaining_minutes": 300, "status": "running"},
		{"recipe_id": "flour", "batches": 1, "remaining_minutes": 300, "status": "queued"},
		{"recipe_id": "flour", "batches": 1, "remaining_minutes": 300, "status": "queued"},
		{"recipe_id": "flour", "batches": 1, "remaining_minutes": 300, "status": "queued"},
	])
	ui.configure(production, inventory, progression, fixture.grid, modal)
	ui.open_for(upgraded)
	panel = ui.production_panel
	assertions.equal(panel.queue_slots.size(), 4, "level-two queue upgrade exposes all four authoritative slots")
	assertions.equal(panel.queue_slot_nodes.size(), 4, "queue UI builds four visible slot nodes dynamically")
	if panel.queue_slot_nodes.size() >= 4:
		assertions.equal(panel.queue_slot_nodes[3].get_node("Content/Header/StateLabel").text, "等待中", "fourth queued job is visible with a localized state")
		var stale_slot: WeakRef = weakref(panel.queue_slot_nodes[3])
		upgraded.producer_state.jobs.resize(1)
		upgraded.producer_state.max_queue_slots = 2
		panel.refresh_snapshot()
		assertions.equal(panel.queue_slot_nodes.size(), 2, "queue downgrade removes surplus slot nodes")
		assertions.truthy(stale_slot.get_ref() == null, "queue downgrade frees stale slot nodes and callbacks")
	panel.show_building(windmill)
	assertions.equal(panel.queue_slot_nodes.size(), 2, "switching to a normal building rebuilds exactly its authoritative slots")
	ui.close()


func _test_status_view_data_and_atomic_actions(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _systems_fixture()
	var production: ProductionSystem = fixture.production
	var inventory: InventorySystem = fixture.inventory
	var panel = _instantiate_scene(STATUS_SCENE, tree)
	var overlay = preload("res://scripts/ui/world_range_overlay.gd").new()
	_track(overlay)
	panel.configure(production, inventory, fixture.progression, fixture.grid, overlay)
	var maintenance_building := _scene_building("workbench", tree)
	maintenance_building.grid_x = 40
	maintenance_building.grid_z = 40
	production.register_building(maintenance_building)
	production.set_maintenance_due_day(maintenance_building, production.get_current_day() + 1)
	var maintenance_quote: Dictionary = fixture.progression.get_maintenance_quote(maintenance_building)
	for item_id in maintenance_quote.materials:
		inventory.add_item(str(item_id), int(maintenance_quote.materials[item_id]))
	var wallet := tree.root.get_node_or_null("GameState")
	var gold_before := int(wallet.gold)
	wallet.gold = int(maintenance_quote.gold_cost)
	panel.show_building(maintenance_building)
	var maintenance_card := panel.get_node("MaintenanceCard")
	assertions.equal(maintenance_card.maintenance_state, "warning", "status card shows advance warning")
	assertions.equal(maintenance_card.get_node("ActionButton").text, "提前维修", "warning offers early repair")
	assertions.truthy(maintenance_card.get_node("ActionButton").visible, "warning repair button is visible")
	maintenance_card.get_node("ActionButton").pressed.emit()
	assertions.equal(production.get_maintenance_state(maintenance_building), "repairing", "card starts authoritative repair")
	assertions.truthy(maintenance_card.get_node("RepairProgress").visible, "repairing card shows progress")
	production.advance_repair_time(3.0)
	maintenance_card.refresh()
	assertions.equal(maintenance_card.maintenance_state, "normal", "completed repair returns card to normal")
	assertions.truthy(not maintenance_card.get_node("ActionButton").visible, "normal card hides repair action")
	wallet.gold = gold_before
	var required := {
		"beehive": ["next_output", "mature_flowers", "bonus", "storage"],
		"chicken_coop": ["animal_count", "feed_stock", "feed_days", "daily_egg_output"],
		"waterwheel": ["water_connected", "irrigation_radius", "covered_farmland", "covered_greenhouses"],
		"greenhouse": ["planting_cells", "water_connected", "season_protection", "crop_maturity_days", "waterwheel_connected", "planting_hint"],
		"barn": ["nearby_buildings", "pending_outputs", "total_capacity", "grouped_outputs"],
		"lumberyard": ["output_table", "next_settlement", "maintenance", "stored_capacity"],
		"quarry": ["output_table", "next_settlement", "maintenance", "stored_capacity"],
		"mine": ["output_table", "next_settlement", "maintenance", "stored_capacity", "depth_tier"],
	}
	for building_id in required:
		var building := _scene_building(building_id, tree)
		production.register_building(building)
		panel.show_building(building)
		assertions.equal(panel.view_data.building_id, building_id, "%s uses typed status ViewData" % building_id)
		for field in required[building_id]:
			assertions.truthy(panel.view_data.fields.has(field), "%s exposes %s" % [building_id, field])
	var localized_wheel := _scene_building("waterwheel", tree)
	localized_wheel.grid_x = 25
	localized_wheel.grid_z = 20
	fixture.grid.get_cell(24, 20).state = GridCell.State.WATER
	for position in [Vector2i(25, 22), Vector2i(27, 20), Vector2i(28, 20), Vector2i(25, 24)]:
		fixture.grid.get_cell(position.x, position.y).state = GridCell.State.FARMLAND
	production.register_building(localized_wheel)
	panel.show_building(localized_wheel)
	assertions.equal(panel.summary_fields.get_node("WaterConnectedLabel").text, "连接水源：是", "waterwheel boolean uses a friendly Chinese value")
	assertions.equal(panel.summary_fields.get_node("IrrigationRadiusLabel").text, "灌溉半径：4格", "waterwheel radius uses a friendly Chinese unit")
	assertions.equal(panel.summary_fields.get_node("CoveredFarmlandLabel").text, "覆盖农田：4", "waterwheel farmland label is localized")
	assertions.equal(panel.summary_fields.get_node("CoveredGreenhousesLabel").text, "覆盖温室：0", "waterwheel greenhouse label is localized")
	var seeded_greenhouse := _scene_building("greenhouse", tree)
	seeded_greenhouse.grid_x = 10
	seeded_greenhouse.grid_z = 10
	production.register_building(seeded_greenhouse)
	var crop_data := CropData.new()
	crop_data.crop_id = "tomato"
	crop_data.growth_days = 4
	var crop_instance := CropInstance.new()
	crop_instance.crop_data = crop_data
	crop_instance.growth_progress = 1.5
	var crop_cell: Vector2i = production.get_greenhouse_cells(seeded_greenhouse)[0]
	fixture.grid.get_cell(crop_cell.x, crop_cell.y).state = GridCell.State.PLANTED
	fixture.grid.get_cell(crop_cell.x, crop_cell.y).crop_instance = crop_instance
	panel.show_building(seeded_greenhouse)
	var maturity: Array = panel.view_data.fields.crop_maturity_days
	assertions.equal(maturity[0].get("remaining_days"), 3, "greenhouse UI renders authoritative crop maturity instead of a placeholder")

	var coop := _scene_building("chicken_coop", tree)
	production.register_building(coop)
	inventory.add_item("animal_feed", 2)
	panel.show_building(coop)
	panel.request_add_input("animal_feed", 2)
	assertions.equal(inventory.get_item_count("animal_feed"), 0, "feed transfer updates inventory in the same frame")
	assertions.equal(coop.producer_state.get_input_count("animal_feed"), 2, "feed transfer updates producer in the same frame")
	var inventory_before := inventory.slots.duplicate(true)
	var input_before := coop.producer_state.inputs.duplicate(true)
	panel.request_add_input("animal_feed", 2147483647)
	assertions.equal(panel.failure_reason, "missing_input", "extreme feed failure exposes precise reason")
	assertions.equal(inventory.slots, inventory_before, "failed extreme feed transfer has zero inventory side effects")
	assertions.equal(coop.producer_state.inputs, input_before, "failed extreme feed transfer has zero producer side effects")

	coop.producer_state.outputs = {"egg": 1, "honey": 1}
	inventory.max_slots = 1
	inventory.reset_slots()
	panel.refresh_snapshot()
	panel.request_collect_all()
	assertions.equal(panel.failure_reason, "inventory_capacity", "atomic collect failure exposes precise reason")
	assertions.equal(inventory.get_slot_count(), 0, "failed collection moves no inventory items")
	assertions.equal(coop.producer_state.outputs, {"egg": 1, "honey": 1}, "failed collection preserves all building outputs")
	inventory.max_slots = 20
	inventory.reset_slots()
	panel.request_collect_all()
	assertions.equal(inventory.get_item_count("egg"), 1, "successful collection refreshes inventory in same frame")
	assertions.equal(coop.producer_state.outputs, {}, "successful collection refreshes storage in same frame")

	var partial_coop := _scene_building("chicken_coop", tree)
	partial_coop.grid_x = 20
	production.register_building(partial_coop)
	partial_coop.producer_state.outputs = {"honey": 2}
	inventory.max_slots = 1
	inventory.reset_slots()
	inventory.add_item("honey", 98)
	panel.show_building(partial_coop)
	panel.request_collect_all()
	assertions.equal(panel.failure_reason, "inventory_capacity", "partial-capacity status collect exposes capacity reason")
	assertions.truthy(panel.failure_message.contains("×1"), "status feedback shows the exact missing quantity")
	panel.refresh_snapshot()
	assertions.truthy(panel.feedback_label.text.contains("×1"), "status failure feedback survives refresh")

	var barn := _scene_building("barn", tree)
	var hive := _scene_building("beehive", tree)
	barn.grid_x = 30
	barn.grid_z = 30
	hive.grid_x = 31
	hive.grid_z = 30
	production.register_building(barn)
	production.register_building(hive)
	hive.producer_state.outputs = {"honey": 2, "beeswax": 1}
	inventory.max_slots = 20
	inventory.reset_slots()
	panel.show_building(barn)
	var source_key := ProductionSystemScript.building_key(hive)
	assertions.truthy(panel.has_method("request_collect_group_item"), "barn panel exposes per-source per-item collection action")
	if panel.has_method("request_collect_group_item"):
		panel.call("request_collect_group_item", source_key, "honey")
		assertions.equal(inventory.get_item_count("honey"), 2, "barn group button action collects selected item")
		assertions.equal(hive.producer_state.outputs, {"beeswax": 1}, "barn group action preserves unselected output")
		inventory.max_slots = 1
		inventory.reset_slots()
		inventory.add_item("grain", 99)
		panel.call("request_collect_group_item", source_key, "beeswax")
		assertions.equal(panel.failure_reason, "inventory_capacity", "barn group failure exposes structured capacity reason")
		assertions.truthy(panel.feedback_label.text.contains("×1"), "barn group failure remains visibly precise after refresh")


func _test_range_and_modal_lifecycle(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _systems_fixture()
	var production: ProductionSystem = fixture.production
	var grid: GridSystem = fixture.grid
	var waterwheel := _scene_building("waterwheel", tree)
	waterwheel.grid_x = 10
	waterwheel.grid_z = 10
	for position in [Vector2i(8, 10), Vector2i(9, 10), Vector2i(10, 8), Vector2i(14, 11)]:
		grid.get_cell(position.x, position.y).state = GridCell.State.FARMLAND
	grid.get_cell(8, 10).terrain_height = 1.25
	grid.get_cell(9, 10).terrain_height = -0.5
	production.register_building(waterwheel)
	var ui = _instantiate_scene(UI_SCENE, tree)
	var modal := ModalCoordinatorScript.new()
	assertions.truthy(ui.configure(production, fixture.inventory, fixture.progression, grid, modal), "range fixture configures UI")
	tree.paused = false
	assertions.truthy(ui.open_for(waterwheel), "waterwheel opens status panel")
	assertions.truthy(tree.paused, "full-screen building UI pauses previously running tree")
	ui.status_panel.set_range_preview(true)
	assertions.equal(ui.range_overlay.cells, production.get_irrigated_cells(waterwheel), "range overlay exactly matches authoritative irrigated cells")
	assertions.equal(ui.range_overlay.get_child_count(), ui.range_overlay.cells.size(), "range overlay creates only non-collision cell geometry")
	var high_cell := _overlay_cell(ui.range_overlay, Vector2i(8, 10))
	var low_cell := _overlay_cell(ui.range_overlay, Vector2i(9, 10))
	assertions.truthy(high_cell != null and low_cell != null, "range overlay authors geometry for both terrain samples")
	if high_cell != null and low_cell != null:
		assertions.near(high_cell.position.y, 1.25 + ui.range_overlay.CELL_LIFT, 0.0001, "range overlay follows the high terrain sample")
		assertions.near(low_cell.position.y, -0.5 + ui.range_overlay.CELL_LIFT, 0.0001, "range overlay follows the low terrain sample")
		assertions.truthy(not is_equal_approx(high_cell.position.y, low_cell.position.y), "range overlay height is not a constant plane")
	for child in ui.range_overlay.get_children():
		assertions.truthy(child is MeshInstance3D, "range preview geometry has no collision node")
	ui.close()
	assertions.equal(ui.range_overlay.cells, [], "close clears every range cell")
	assertions.truthy(not tree.paused, "close restores previously running pause state")
	tree.paused = true
	assertions.truthy(ui.open_for(waterwheel), "waterwheel reopens from paused state")
	ui.status_panel.set_range_preview(true)
	ui.on_build_mode_entered()
	assertions.equal(ui.range_overlay.cells, [], "build mode clears every range cell")
	assertions.truthy(tree.paused, "close restores previously paused state")
	ui.range_overlay.show_cells(production.get_irrigated_cells(waterwheel), grid)
	assertions.truthy(tree.paused, "range overlay alone never changes pause state")
	ui.range_overlay.clear()
	tree.paused = false


func _test_main_route_and_construction_regression(assertions: TestAssert, tree: SceneTree) -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main = main_scene.instantiate()
	_track(main)
	main.load_save_on_start = false
	tree.root.add_child(main)
	assertions.truthy(main.building_economy_ui != null, "Main authors building economy UI")
	assertions.truthy(main.building_economy_ui.is_configured(), "Main configures building UI with authoritative systems")
	assertions.truthy(main.building_economy_ui.has_signal("unlock_requested"), "Main building UI exposes unlock navigation")
	if main.building_economy_ui.has_signal("unlock_requested"):
		assertions.truthy(
			main.building_economy_ui.is_connected("unlock_requested", Callable(main, "_on_building_unlock_requested")),
			"Main connects recipe unlock navigation exactly once"
		)
	var completed := _scene_building("windmill", tree)
	main.call("_on_building_instance_placed", completed)
	assertions.truthy(completed.interacted.is_connected(Callable(main, "_on_building_interacted")), "Main connects BuildingInstance.interacted exactly once")
	main.call("_on_building_instance_placed", completed)
	var route_count := 0
	for connection in completed.interacted.get_connections():
		if connection.callable.get_object() == main:
			route_count += 1
	assertions.equal(route_count, 1, "repeated placement routing never duplicates interaction callback")
	completed.interact(main.player)
	assertions.truthy(main.building_economy_ui.is_open(), "completed economic building interaction opens UI")
	main.building_economy_ui.close()
	var construction := _scene_building("windmill", tree)
	construction.start_construction()
	main.call("_on_building_instance_placed", construction)
	construction.interact(main.player)
	assertions.truthy(not main.building_economy_ui.is_open(), "construction-state building cannot open economy UI")
	assertions.equal(construction.construction_stage, BuildingInstance.ConstructionStage.FOUNDATION, "construction interaction preserves existing construction lifecycle")
	main.call("_on_building_interacted", construction, main.player)
	assertions.truthy(not main.building_economy_ui.is_open(), "Main independently rejects incomplete economy routing")


func _systems_fixture() -> Dictionary:
	var grid := _track(GridSystemScript.new()) as GridSystem
	var farming := _track(FarmingSystemScript.new()) as FarmingSystem
	farming.configure(grid, null, null)
	var inventory := _track(InventorySystemScript.new()) as InventorySystem
	var production := _track(ProductionSystemScript.new()) as ProductionSystem
	production.configure(grid, farming, null, inventory)
	var progression := _track(ProgressionSystemScript.new()) as EconomyProgressionSystem
	var tool := _track(ToolSystemScript.new()) as ToolSystem
	tool.configure(grid, inventory, null)
	var wallet := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameState")
	progression.configure(tool, production, inventory, null, wallet)
	return {"grid": grid, "farming": farming, "inventory": inventory, "production": production, "progression": progression, "tool": tool}


func _unlock_recipe(progression: EconomyProgressionSystem, recipe_id: String) -> void:
	var state := progression.to_dict()
	var recipe = preload("res://scripts/core/recipe_database.gd").get_recipe(recipe_id)
	var station := str(recipe.get("station", ""))
	if station not in state.unlocked_blueprints:
		state.unlocked_blueprints.append(station)
	for station_recipe in preload("res://scripts/core/recipe_database.gd").get_recipes_for_station(station):
		if str(station_recipe.id) not in state.unlocked_recipes:
			state.unlocked_recipes.append(str(station_recipe.id))
	progression.from_dict(state)


func _scene_building(building_id: String, tree: SceneTree) -> BuildingInstance:
	var scene := load("res://scenes/buildings/%s.tscn" % building_id) as PackedScene
	var building := scene.instantiate() as BuildingInstance
	_track(building)
	tree.root.add_child(building)
	return building


func _instantiate_scene(path: String, tree: SceneTree) -> Node:
	var scene := load(path) as PackedScene
	var node := scene.instantiate()
	_track(node)
	tree.root.add_child(node)
	return node


func _overlay_cell(overlay: Node3D, position: Vector2i) -> MeshInstance3D:
	for child in overlay.get_children():
		if child is MeshInstance3D and child.get_meta("grid_cell", Vector2i(-1, -1)) == position:
			return child
	return null


func _check_scene(assertions: TestAssert, path: String, required_paths: Array[String]) -> void:
	assertions.truthy(ResourceLoader.exists(path), "scene exists: %s" % path)
	var packed := load(path) as PackedScene
	assertions.truthy(packed != null, "scene loads: %s" % path)
	if packed == null:
		return
	var instance := packed.instantiate()
	for node_path in required_paths:
		assertions.truthy(instance.get_node_or_null(node_path) != null, "%s authors %s" % [path, node_path])
	instance.free()


func _track(node: Node) -> Node:
	_owned_nodes.append(node)
	return node


func _cleanup_nodes() -> void:
	for index in range(_owned_nodes.size() - 1, -1, -1):
		var node := _owned_nodes[index]
		if is_instance_valid(node):
			node.free()
	_owned_nodes.clear()
