extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")

const TEST_SAVE_DIR := "user://villa_test_saves/production_chain/"
const TEST_SLOT := 7
const RAW_MARKET_STOCK := 2000


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_cleanup_save()
	var manager := SaveManagerScript.new()
	manager.name = "ProductionChainSaveManager"
	manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(manager)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.load_save_on_start = false
	main.save_manager = manager
	tree.root.add_child(main)
	await tree.process_frame

	var game_state := tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "production chain fixture has GameState")
	if game_state == null:
		main.free()
		manager.free()
		return
	_prepare_initial_fixture(main, game_state)

	var gathered_before: Array[Dictionary] = main.world.to_resource_dicts()
	var gathered_items := _gather_world_inputs(main)
	for item_id in ["wood", "clay", "sand", "copper_ore", "iron_ore"]:
		assertions.truthy(
			int(gathered_items.get(item_id, 0)) > 0,
			"real gathering commits %s before production starts" % item_id
		)
	assertions.truthy(
		main.world.to_resource_dicts() != gathered_before,
		"real gather commits persist resource-node depletion"
	)

	assertions.truthy(_buy_requirements(main, {"wood": 40, "stone": 40}), "market supplies starter construction gaps")
	var workbench := _place_and_finish(main, "workbench", assertions)
	var kiln := _place_and_finish(main, "stone_kiln", assertions)
	if workbench == null or kiln == null:
		_free_fixture(main, manager)
		return

	assertions.truthy(
		_buy_requirements(main, {"wood": 330, "fiber": 30, "stone": 180, "clay": 12, "coal": 80}),
		"market supplies only raw processing inputs"
	)
	assertions.truthy(_produce_collect(main, workbench, "plank", 110), "workbench produces and collects planks")
	assertions.truthy(_produce_collect(main, workbench, "rope", 8), "workbench produces and collects rope")
	assertions.truthy(_produce_collect(main, kiln, "charcoal", 8), "kiln produces and collects charcoal")
	assertions.truthy(_produce_collect(main, kiln, "stone_brick", 85), "kiln produces and collects stone brick")
	assertions.truthy(_produce_collect(main, kiln, "brick", 4), "kiln produces and collects brick")

	assertions.truthy(_buy_requirements(main, {"stone": 12, "coal": 3}), "market supplies furnace blueprint raw materials")
	assertions.truthy(main.economy_progression_system.purchase("blueprint_furnace"), "materials and gates unlock furnace blueprint")
	var furnace := _place_and_finish(main, "furnace", assertions)
	if furnace == null:
		_free_fixture(main, manager)
		return
	assertions.truthy(
		_buy_requirements(main, {"sand": 70, "coal": 102, "copper_ore": 20, "iron_ore": 80}),
		"market supplies smelting ores and fuel"
	)
	assertions.truthy(_produce_collect(main, furnace, "glass", 35), "furnace produces and collects glass")
	assertions.truthy(_produce_collect(main, furnace, "glass_jar", 1), "furnace produces and collects jars")
	assertions.truthy(_produce_collect(main, furnace, "glass_bottle", 1), "furnace produces and collects bottles")
	assertions.truthy(_produce_collect(main, furnace, "copper_ingot", 6), "furnace produces and collects copper ingots")
	assertions.truthy(_produce_collect(main, furnace, "iron_ingot", 36), "furnace produces and collects iron ingots")
	assertions.truthy(
		_sell_surplus(main, ["clay", "sand", "copper_ore", "iron_ore", "charcoal", "brick", "glass_jar", "glass_bottle"]),
		"surplus raw materials and verified containers sell to free inventory space"
	)

	assertions.truthy(main.economy_progression_system.purchase("recipe_farm_tools"), "iron ingot unlocks farm tools recipe")
	assertions.truthy(main.economy_progression_system.purchase("recipe_steel"), "iron ingots unlock steel recipe")
	assertions.truthy(_produce_collect(main, furnace, "steel", 9), "furnace produces advanced steel input")
	assertions.truthy(main.economy_progression_system.purchase("recipe_machine_parts"), "steel and copper unlock machine parts recipe")
	assertions.truthy(_produce_collect(main, workbench, "farm_tools", 1), "workbench produces farm tools")
	assertions.truthy(_produce_collect(main, workbench, "machine_parts", 4), "workbench produces machine parts")
	assertions.truthy(_sell_surplus(main, ["coal"]), "unused furnace fuel sells after advanced smelting")

	var blueprint_ids := [
		"windmill", "chicken_coop", "lumberyard", "quarry",
		"food_workshop", "textile_machine", "greenhouse", "mine",
	]
	for building_id in blueprint_ids:
		var service_id: String = main.economy_progression_system.get_blueprint_service_id(building_id)
		assertions.truthy(
			_purchase_blueprint(main, service_id),
			"real service purchase unlocks %s" % building_id
		)

	var construction_material_before: int = main.inventory_system.get_item_count("plank")
	var buildings := {
		"windmill": _place_and_finish(main, "windmill", assertions),
		"chicken_coop": _place_and_finish(main, "chicken_coop", assertions),
		"lumberyard": _place_and_finish(main, "lumberyard", assertions),
		"quarry": _place_and_finish(main, "quarry", assertions),
		"food_workshop": _place_and_finish(main, "food_workshop", assertions),
		"textile_machine": _place_and_finish(main, "textile_machine", assertions),
		"greenhouse": _place_and_finish(main, "greenhouse", assertions),
		"mine": _place_and_finish(main, "mine", assertions),
	}
	for building_id in buildings:
		assertions.truthy(buildings[building_id] != null, "%s is built from produced materials" % building_id)
	assertions.truthy(
		main.inventory_system.get_item_count("plank") < construction_material_before,
		"processed planks are consumed by real construction costs"
	)
	if buildings.values().has(null):
		_free_fixture(main, manager)
		return

	assertions.truthy(_buy_requirements(main, {"grain": 8, "fiber": 8}), "market supplies crop and fiber production inputs")
	assertions.truthy(_produce_collect(main, buildings.windmill, "flour", 2), "windmill produces flour")
	assertions.truthy(_produce_collect(main, buildings.windmill, "animal_feed", 1), "windmill produces animal feed")
	assertions.truthy(
		main.production_system.add_input(buildings.chicken_coop, "animal_feed", 1, main.inventory_system),
		"produced feed enters the chicken coop"
	)
	main.production_system.finish_daily_outputs(41)
	assertions.truthy(
		main.production_system.collect_all(buildings.chicken_coop, main.inventory_system),
		"chicken coop produces and collects eggs"
	)
	assertions.truthy(_produce_collect(main, buildings.food_workshop, "bread", 1), "food workshop produces food")
	assertions.truthy(_produce_collect(main, buildings.textile_machine, "cloth", 1), "textile machine produces cloth")
	assertions.truthy(main.inventory_system.has_item("machine_parts", 1), "chain retains a produced machine part")
	assertions.truthy(main.inventory_system.has_item("steel", 1), "chain retains an advanced building input")

	var gold_before_sale := int(game_state.gold)
	assertions.truthy(main.economy_system.sell_item("bread", 1), "processed food sells through EconomySystem")
	assertions.truthy(int(game_state.gold) > gold_before_sale, "processed food sale credits the wallet")

	assertions.truthy(_buy_requirements(main, {"wood": 8}), "market supplies final save-fixture timber")
	var unfinished_fence := _place_without_finishing(main, "fence", assertions)
	assertions.truthy(unfinished_fence != null and not unfinished_fence.is_construction_complete(), "save fixture includes active construction")
	assertions.truthy(_buy_requirements(main, {"wood": 2, "fiber": 4}), "market supplies queue fixture inputs")
	assertions.truthy(main.production_system.start_recipe(buildings.textile_machine, "cloth", 1, main.inventory_system), "save fixture starts output job")
	main.production_system.advance_minutes(int(RecipeDatabaseScript.get_recipe("cloth").duration_minutes))
	assertions.truthy(
		int(buildings.textile_machine.producer_state.outputs.get("cloth", 0)) > 0,
		"save fixture leaves a completed output in building storage"
	)
	assertions.truthy(main.production_system.start_recipe(workbench, "plank", 1, main.inventory_system), "save fixture includes a real queued job")

	assertions.truthy(manager.save_game(TEST_SLOT), "complete production chain saves through SaveManager")
	var expected := _persistent_snapshot(manager._gather_save_data())
	main.inventory_system.clear()
	main.building_system.clear_buildings(true)
	main.economy_progression_system.reset_to_new_game()
	main.market_system.commit_buy("wood", 1)
	assertions.truthy(manager.load_game(TEST_SLOT), "complete production chain loads through SaveManager")
	var restored := _persistent_snapshot(manager._gather_save_data())
	assertions.equal(restored, expected, "save/load preserves buildings, construction, queues, outputs, progression, resources, inventory, wallet, and market")

	_free_fixture(main, manager)
	_cleanup_save()


func _prepare_initial_fixture(main: Node, game_state: Node) -> void:
	main.inventory_system.clear()
	game_state.gold = 1000000
	game_state.player_state.max_stamina = 100
	game_state.player_state.stamina = 100
	game_state.player_state.level = 10
	game_state.player_state.exp = 0
	main.season_system.current_season = 1
	main.season_system.current_day = 5
	main.season_system.total_days = 40
	main.season_system.hour = 9
	main.season_system.minute = 0
	main.production_system.sync_daily_cursor(40)
	main.daily_simulation_system.last_simulated_day = 40
	main.npc_economy_system.sync_daily_cursor(40)
	main.economy_system.reset_order_state(40)
	main.market_system.settle_day(40)
	var market_state: Dictionary = main.market_system.to_dict()
	for item_id in market_state.get("items", {}):
		market_state.items[item_id]["stock"] = RAW_MARKET_STOCK
	main.market_system.from_dict(market_state)


func _gather_world_inputs(main: Node) -> Dictionary:
	var wanted := {
		"wood": false,
		"clay": false,
		"sand": false,
		"stone": false,
		"coal": false,
		"copper_ore": false,
		"iron_ore": false,
	}
	var gathered := {}
	for target in main.world.get_gatherable_nodes():
		var item_id := str(target.get("item_id"))
		if not wanted.has(item_id) or bool(wanted[item_id]):
			continue
		wanted[item_id] = true
		main.player.global_position = target.global_position
		main.tool_system.switch_tool_by_id(str(target.get("required_tool")))
		var result: Dictionary = main.tool_system.commit_gather_unit(target)
		if bool(result.get("allowed", false)):
			for reward_id in result.get("rewards", {}):
				gathered[reward_id] = int(gathered.get(reward_id, 0)) + int(result.rewards[reward_id])
	return gathered


func _buy_requirements(main: Node, requirements: Dictionary) -> bool:
	for item_id in requirements:
		var missing: int = int(requirements[item_id]) - main.inventory_system.get_item_count(str(item_id))
		if missing > 0 and not main.economy_system.buy_item(str(item_id), missing):
			return false
	return true


func _sell_surplus(main: Node, item_ids: Array[String]) -> bool:
	for item_id in item_ids:
		var quantity: int = main.inventory_system.get_item_count(item_id)
		if quantity > 0 and not main.economy_system.sell_item(item_id, quantity):
			return false
	return true


func _purchase_blueprint(main: Node, service_id: String) -> bool:
	var service := {}
	for candidate in main.economy_progression_system.get_available_services():
		if str(candidate.get("id", "")) == service_id:
			service = candidate
			break
	if service.is_empty():
		return false
	var raw_requirements := {}
	for item_id in service.get("materials", {}):
		if str(item_id) in ["wood", "stone", "fiber", "clay", "sand", "coal", "copper_ore", "iron_ore"]:
			raw_requirements[item_id] = int(service.materials[item_id])
	if not _buy_requirements(main, raw_requirements):
		return false
	return main.economy_progression_system.purchase(service_id)


func _produce_collect(main: Node, building: BuildingInstance, recipe_id: String, batches: int) -> bool:
	if building == null:
		return false
	var recipe := RecipeDatabaseScript.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if not main.production_system.start_recipe(building, recipe_id, batches, main.inventory_system):
		print("CHAIN: start failed %s %s" % [recipe_id, main.production_system.preflight_recipe(building, recipe_id, batches, main.inventory_system)])
		return false
	main.production_system.advance_minutes(int(recipe.duration_minutes) * batches)
	var collected: bool = main.production_system.collect_all(building, main.inventory_system)
	if not collected:
		print("CHAIN: collect failed %s %s" % [recipe_id, main.production_system.get_building_snapshot(building)])
	return collected


func _place_and_finish(main: Node, building_id: String, assertions: TestAssert) -> BuildingInstance:
	var building := _place_without_finishing(main, building_id, assertions)
	if building != null:
		building.complete_construction()
		main.production_system.register_building(building)
	return building


func _place_without_finishing(main: Node, building_id: String, assertions: TestAssert) -> BuildingInstance:
	var definition: Dictionary = GameDataScript.get_building(building_id)
	if definition.is_empty() or not _prepare_construction_requirements(main, definition.get("cost", {})):
		assertions.truthy(false, "%s construction inputs are available" % building_id)
		return null
	for gz in range(GridSystem.GRID_DEPTH):
		for gx in range(GridSystem.GRID_WIDTH):
			if not main.building_system.can_place_building(building_id, gx, gz):
				continue
			var building: BuildingInstance = main.building_system.place_building_by_id(building_id, gx, gz)
			assertions.truthy(building != null, "%s placement commits" % building_id)
			return building
	assertions.truthy(false, "%s finds a valid world footprint" % building_id)
	return null


func _prepare_construction_requirements(main: Node, cost: Dictionary) -> bool:
	var raw_market_items := ["wood", "stone", "fiber", "clay", "sand", "coal", "copper_ore", "iron_ore"]
	for item_id in cost:
		var missing: int = int(cost[item_id]) - main.inventory_system.get_item_count(str(item_id))
		if missing <= 0:
			continue
		if str(item_id) not in raw_market_items or not main.economy_system.buy_item(str(item_id), missing):
			return false
	return true


func _persistent_snapshot(data: Dictionary) -> Dictionary:
	var result := {}
	for key in [
		"gold", "player", "season", "day", "total_days", "hour", "minute",
		"inventory", "grid", "buildings", "market", "last_simulated_day", "economy_state",
		"progression", "tool_durability", "production_upkeep", "notifications", "resource_nodes",
	]:
		result[key] = data.get(key)
	return JSON.parse_string(JSON.stringify(result))


func _free_fixture(main: Node, manager: Node) -> void:
	main.free()
	manager.free()


func _cleanup_save() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_SAVE_DIR)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	for file_name in directory.get_files():
		directory.remove(file_name)
	DirAccess.remove_absolute(absolute)
