extends RefCounted

const BUILDING_ECONOMY_UI_SCRIPT := "res://scripts/ui/building_economy_ui.gd"
const ProductionSystemScript = preload("res://scripts/systems/production_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const ProgressionSystemScript = preload("res://scripts/systems/economy_progression_system.gd")
const ModalCoordinatorScript = preload("res://scripts/ui/economy_modal_coordinator.gd")
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")

const UI_SCENE := "res://scenes/ui/economy/building_economy_ui.tscn"
const PRODUCTION_SCENE := "res://scenes/ui/economy/building_production_panel.tscn"
const STATUS_SCENE := "res://scenes/ui/economy/building_status_panel.tscn"

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
		"ModalLayer/BuildingPanel/Margin/Shell/Header/TitleLabel",
		"ModalLayer/BuildingPanel/Margin/Shell/Header/StateLabel",
		"ModalLayer/BuildingPanel/Margin/Shell/Header/CloseButton",
		"ModalLayer/BuildingPanel/Margin/Shell/PageHost/ProductionPanel",
		"ModalLayer/BuildingPanel/Margin/Shell/PageHost/StatusPanel",
		"WorldRangeOverlay",
	])
	_check_scene(assertions, PRODUCTION_SCENE, [
		"ThreeColumns/RecipeColumn/RecipeList",
		"ThreeColumns/QueueColumn/QueueSlots/Slot1/StateLabel",
		"ThreeColumns/QueueColumn/QueueSlots/Slot2/StateLabel",
		"ThreeColumns/StorageColumn/StorageList",
		"ThreeColumns/StorageColumn/CollectAllButton",
		"RecipeDetails/InputLabel",
		"RecipeDetails/OutputLabel",
		"RecipeDetails/DurationLabel",
		"RecipeDetails/PricingLabel",
		"RecipeDetails/MissingLabel",
		"RecipeDetails/BatchControls/BatchSpinBox",
		"RecipeDetails/BatchControls/MaxButton",
		"RecipeDetails/BatchControls/StartButton",
	])
	_check_scene(assertions, STATUS_SCENE, [
		"SummaryFields",
		"InputActions",
		"StorageList",
		"Actions/CollectAllButton",
		"Actions/RangePreviewButton",
		"FeedbackLabel",
	])


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
	assertions.truthy(ui.configure(production, inventory, progression, modal), "building UI configures real economy systems")
	assertions.truthy(ui.configure(production, inventory, progression, modal), "repeated building UI configure is idempotent")
	assertions.truthy(ui.open_for(windmill), "completed windmill opens")
	var panel = ui.production_panel
	assertions.equal(panel.recipe_rows.size(), 3, "windmill exposes all three recipes")
	panel.select_recipe("flour")
	panel.set_batches(1)
	assertions.equal(panel.recipe_detail.get("inputs"), {"grain": 2}, "recipe details expose exact inputs")
	assertions.equal(panel.recipe_detail.get("outputs"), {"flour": 1}, "recipe details expose exact outputs")
	assertions.equal(panel.queue_slots.size(), 2, "production view always exposes two queue slots")
	assertions.truthy(panel.recipe_detail.has("margin_status"), "recipe detail exposes margin status")
	assertions.truthy(panel.recipe_detail.has("duration_minutes"), "recipe detail exposes duration")
	var grain_before := inventory.get_item_count("grain")
	panel.start_button.pressed.emit()
	assertions.equal(inventory.get_item_count("grain"), grain_before - 2, "one press deducts one batch exactly once after repeated configure")
	assertions.equal(windmill.producer_state.jobs.size(), 1, "one press creates one authoritative job")
	ui.close()
	assertions.truthy(ui.open_for(windmill), "windmill reopens")
	assertions.equal(windmill.producer_state.jobs.size(), 1, "closing and reopening preserves authoritative job")
	assertions.equal(ui.production_panel.selected_recipe_id, "flour", "closing preserves selected recipe")
	assertions.equal(ui.production_panel.batches, 1, "temporary batch resets on reopen")

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
	panel.configure(blocked_production, blocked_inventory, progression)
	panel.show_building(blocked)
	assertions.equal(panel.queue_slots[0].state, "output-full", "UI output-full state comes from production snapshot")
	blocked_production.set_maintenance_due_day(blocked, blocked_production.get_current_day())
	panel.refresh_snapshot()
	assertions.equal(panel.queue_slots[0].state, "maintenance-paused", "UI maintenance pause comes from production snapshot")
	ui.close()


func _test_status_view_data_and_atomic_actions(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _systems_fixture()
	var production: ProductionSystem = fixture.production
	var inventory: InventorySystem = fixture.inventory
	var panel = _instantiate_scene(STATUS_SCENE, tree)
	var overlay = preload("res://scripts/ui/world_range_overlay.gd").new()
	_track(overlay)
	panel.configure(production, inventory, overlay)
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


func _test_range_and_modal_lifecycle(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _systems_fixture()
	var production: ProductionSystem = fixture.production
	var grid: GridSystem = fixture.grid
	var waterwheel := _scene_building("waterwheel", tree)
	waterwheel.grid_x = 10
	waterwheel.grid_z = 10
	for position in [Vector2i(8, 10), Vector2i(9, 10), Vector2i(10, 8), Vector2i(14, 11)]:
		grid.get_cell(position.x, position.y).state = GridCell.State.FARMLAND
	production.register_building(waterwheel)
	var ui = _instantiate_scene(UI_SCENE, tree)
	var modal := ModalCoordinatorScript.new()
	assertions.truthy(ui.configure(production, fixture.inventory, fixture.progression, modal), "range fixture configures UI")
	tree.paused = false
	assertions.truthy(ui.open_for(waterwheel), "waterwheel opens status panel")
	assertions.truthy(tree.paused, "full-screen building UI pauses previously running tree")
	ui.status_panel.set_range_preview(true)
	assertions.equal(ui.range_overlay.cells, production.get_irrigated_cells(waterwheel), "range overlay exactly matches authoritative irrigated cells")
	assertions.equal(ui.range_overlay.get_child_count(), ui.range_overlay.cells.size(), "range overlay creates only non-collision cell geometry")
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
	return {"grid": grid, "farming": farming, "inventory": inventory, "production": production, "progression": progression}


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
