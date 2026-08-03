extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomySystemScript = preload("res://scripts/systems/npc_economy_system.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const EconomySystemScript = preload("res://scripts/systems/economy_system.gd")
const ProductionSystemScript = preload("res://scripts/systems/production_system.gd")
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")
const DailySimulationSystemScript = preload("res://scripts/systems/daily_simulation_system.gd")
const GameStateScript = preload("res://scripts/core/game_state.gd")
const BuildingInstanceScript = preload("res://scripts/buildings/building_instance.gd")
const ProducerStateScript = preload("res://scripts/data/producer_state.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")
const GridCellScript = preload("res://scripts/data/grid_cell.gd")


class SaveDouble extends Node:
	var current_slot := 0
	var save_count := 0

	func save_game(_slot: int) -> bool:
		save_count += 1
		return true

const SIMULATION_SEED := 20260801
const SIMULATION_DAYS := 28
const ROUTES := {
	"raw_gathering": {
		"daily_output": {"wood": 1, "stone": 1, "fiber": 1, "clay": 1, "sand": 1},
		"recipes": {"early": [], "mid": [], "late": []},
		"purchased_inputs": [],
		"daily_gold_cost": 1,
	},
	"crop_farming": {
		"daily_output": {"grain": 1, "carrot": 3},
		"recipes": {"early": [], "mid": ["flour"], "late": ["flour"]},
		"purchased_inputs": [],
		"passive_buildings": ["chicken_coop"],
		"daily_gold_cost": 0,
	},
	"flower_apiary": {
		"daily_output": {"rose": 2, "fiber": 2},
		"recipes": {"early": [], "mid": ["bouquet"], "late": ["bouquet"]},
		"purchased_inputs": [],
		"passive_buildings": ["beehive"],
		"daily_gold_cost": 0,
	},
	"mining_manufacturing": {
		"daily_output": {"coal": 1, "iron_ore": 3, "wood": 1},
		"recipes": {
			"early": [], "mid": ["iron_ingot", "plank"],
			"late": ["iron_ingot", "plank"],
		},
		"purchased_inputs": [],
		"passive_buildings": [],
		"daily_gold_cost": 0,
	},
	"orchard_processing": {
		"daily_output": {"strawberry": 3, "apple": 1, "honey": 1},
		"recipes": {"early": [], "mid": ["fruit_jam"], "late": ["fruit_jam"]},
		"purchased_inputs": ["honey", "glass_jar"],
		"passive_buildings": [],
		"daily_gold_cost": 0,
	},
}
const STAGE_RANGES := {
	"early": Vector2i(1, 7),
	"mid": Vector2i(8, 18),
	"late": Vector2i(19, 28),
}
const ROUTE_STAGE_CAPACITY := {
	"raw_gathering": {"early": 1, "mid": 4, "late": 18},
	"crop_farming": {"early": 1, "mid": 4, "late": 16},
	"flower_apiary": {"early": 1, "mid": 4, "late": 18},
	"mining_manufacturing": {"early": 1, "mid": 3, "late": 12},
	"orchard_processing": {"early": 1, "mid": 4, "late": 18},
}
const STAGE_BATCHES := {"early": 1, "mid": 2, "late": 4}
const STAGE_INCOME_LIMITS := {
	"early": Vector2i(40, 80),
	"mid": Vector2i(150, 300),
	"late": Vector2i(500, 1000),
}


func run(assertions: TestAssert) -> void:
	var first := _run_acceptance_suite(assertions, SIMULATION_SEED, true)
	_test_authoritative_acceptance_contract(assertions, first)
	var repeated := _run_acceptance_suite(assertions, SIMULATION_SEED, false)
	assertions.equal(
		repeated,
		first,
		"route=all day=28 deterministic replay actual=second expected=first seed=%d" % SIMULATION_SEED
	)
	_assert_route_balance(assertions, first)
	_test_essential_shortage_recovers(assertions)
	_test_dumping_depresses_then_recovers(assertions)
	_test_authoritative_maintenance_pause(assertions)
	_test_recipe_value_ladders(assertions)
	_test_no_instant_recipe_arbitrage(assertions)


func _test_authoritative_acceptance_contract(assertions: TestAssert, suite: Dictionary) -> void:
	for route_id_value in suite.routes.keys():
		var route_id := str(route_id_value)
		var result: Dictionary = suite.routes[route_id]
		assertions.truthy(
			result.has("authoritative") and bool(result.get("authoritative", false)),
			"route=%s day=28 uses authoritative inventory/production/economy systems" % route_id
		)
		assertions.equal(
			int(result.get("daily_cursor", -1)),
			SIMULATION_DAYS,
			"route=%s day=28 daily cursor is authoritative" % route_id
		)
		assertions.equal(
			int(result.get("economy_cursor", -1)),
			SIMULATION_DAYS,
			"route=%s day=28 economy order cursor is authoritative" % route_id
		)
		var essential_streaks: Dictionary = result.get("essential_max_zero_streaks", {})
		assertions.equal(
			essential_streaks.keys().size(),
			_essential_counter_map().keys().size(),
			"route=%s day=28 records every essential item" % route_id
		)
		for item_id_value in essential_streaks.keys():
			var item_id := str(item_id_value)
			assertions.truthy(
				int(essential_streaks[item_id]) <= 3,
				"route=%s day=28 item=%s essential zero streak actual=%d expected=<=3" % [
					route_id, item_id, int(essential_streaks[item_id]),
				]
			)
		if route_id == "no_player":
			assertions.truthy(bool(result.market_changed), "route=no_player day=28 market changes without player")
			assertions.truthy(bool(result.npc_changed), "route=no_player day=28 NPC inventories/gold change")
			assertions.truthy(int(result.orders_created) > 0, "route=no_player day=28 shortage creates demand order")
		else:
			assertions.truthy(int(result.transactions.sells) > 0, "route=%s uses EconomySystem sells" % route_id)
			if route_id != "raw_gathering":
				assertions.truthy(
					int(result.maintenance_events) > 0,
					"route=%s uses ProductionSystem maintenance cycles" % route_id
				)
		if route_id == "crop_farming":
			assertions.truthy(int(result.farming_harvests) >= 9, "crop route advances and harvests real Farming plot")
	for recipe in RecipeDatabaseScript.get_all_recipes():
		for output_id_value in (recipe.outputs as Dictionary).keys():
			var output_id := str(output_id_value)
			var definition: Variant = GameDataScript.get_item(output_id)
			assertions.truthy(
				definition != null and int(definition.get("base_price", 0)) > 0,
				"route=catalog day=0 recipe=%s output=%s is tradable" % [str(recipe.id), output_id]
			)


func _test_authoritative_maintenance_pause(assertions: TestAssert) -> void:
	var context := _create_route_context(assertions, "mining_manufacturing", true)
	var inventory: InventorySystem = context.inventory
	var wallet: Node = context.wallet
	var economy: EconomySystem = context.economy
	var production: ProductionSystem = context.production
	var building := _new_building("workbench", "workbench")
	context.buildings.append(building)
	context.building_by_station.workbench = building
	assertions.truthy(production.register_building(building), "maintenance fixture registers real workbench")
	assertions.truthy(inventory.add_item("plank", 4), "maintenance fixture adds furniture planks")
	assertions.truthy(inventory.add_item("cloth", 2), "maintenance fixture adds furniture cloth")
	assertions.truthy(production.begin_day(6), "maintenance fixture reaches day 6")
	assertions.truthy(production.start_recipe(building, "furniture", 1, inventory), "long furniture job starts through ProductionSystem")
	production.advance_minutes(60)
	var before_pause: Dictionary = production.get_building_snapshot(building)
	assertions.truthy(production.begin_day(7), "maintenance fixture reaches due day")
	assertions.truthy(production.is_maintenance_overdue(building), "producer is overdue on quoted due day")
	production.advance_minutes(60)
	var paused: Dictionary = production.get_building_snapshot(building)
	assertions.equal(
		int(paused.jobs[0].remaining_minutes),
		int(before_pause.jobs[0].remaining_minutes),
		"overdue maintenance pauses the real ProducerState job"
	)
	assertions.equal(str(paused.jobs[0].status), "maintenance_paused", "overdue job exposes maintenance-paused status")
	var quote := production.get_maintenance_quote(building)
	for item_id_value in (quote.materials as Dictionary).keys():
		var item_id := str(item_id_value)
		assertions.truthy(economy.buy_item(item_id, int(quote.materials[item_id])), "maintenance fixture buys %s" % item_id)
	var gold_before := int(wallet.gold)
	var material_before := _inventory_counts(inventory, quote.materials.keys())
	assertions.truthy(production.maintain(building, wallet, inventory), "ProductionSystem.maintain succeeds")
	assertions.equal(gold_before - int(wallet.gold), int(quote.gold_cost), "maintain deducts its real quote")
	for item_id_value in (quote.materials as Dictionary).keys():
		var item_id := str(item_id_value)
		assertions.equal(
			int(material_before[item_id]) - inventory.get_item_count(item_id),
			int(quote.materials[item_id]),
			"maintain consumes quoted %s" % item_id
		)
	production.advance_minutes(60)
	var after_resume: Dictionary = production.get_building_snapshot(building)
	assertions.truthy(
		int(after_resume.jobs[0].remaining_minutes) < int(before_pause.jobs[0].remaining_minutes),
		"maintained ProducerState job resumes"
	)
	_cleanup_route_context(context)


func _run_acceptance_suite(assertions: TestAssert, seed: int, verify: bool) -> Dictionary:
	var results := {"seed": seed, "days": SIMULATION_DAYS, "routes": {}}
	var route_ids: Array[String] = ["no_player"]
	for route_id_value in ROUTES.keys():
		route_ids.append(str(route_id_value))
	route_ids.sort()
	for route_id in route_ids:
		var result := _simulate_route(assertions, route_id, seed, verify)
		results.routes[route_id] = result
	return results


func _simulate_route(
	assertions: TestAssert,
	route_id: String,
	seed: int,
	verify: bool
) -> Dictionary:
	var context := _create_route_context(assertions, route_id, verify)
	var market: MarketSystem = context.market
	var npc: NpcEconomySystem = context.npc
	var inventory: InventorySystem = context.inventory
	var wallet: Node = context.wallet
	var economy: EconomySystem = context.economy
	var production: ProductionSystem = context.production
	var daily: DailySimulationSystem = context.daily
	var initial_market: Dictionary = market.to_dict()
	var initial_npc: Dictionary = npc.to_dict()
	var daily_income: Array[int] = []
	var previous_prices: Dictionary = {}
	var zero_streaks := _essential_counter_map()
	var max_zero_streaks := zero_streaks.duplicate()
	var maintenance_events := 0
	var maintenance_pause_checks := 0
	var transactions := {"buys": 0, "sells": 0, "recipes": 0, "collections": 0}
	for definition in GameDataScript.get_market_items():
		previous_prices[str(definition.id)] = int(definition.base_price)
	for day in range(1, SIMULATION_DAYS + 1):
		var gold_before := int(wallet.gold)
		assertions.truthy(production.begin_day(day), "route=%s day=%d production begins" % [route_id, day])
		if route_id != "no_player":
			var day_result := _run_authoritative_route_day(
				assertions, context, route_id, _stage_for_day(day), day, verify
			)
			maintenance_events += int(day_result.maintenance_events)
			maintenance_pause_checks += int(day_result.maintenance_pause_checks)
			for key in transactions:
				transactions[key] = int(transactions[key]) + int(day_result.transactions[key])
		var day_ok := daily.run_day(day)
		if route_id == "crop_farming":
			_advance_farm_witness(assertions, context, day)
		daily_income.append(int(wallet.gold) - gold_before)
		if verify:
			assertions.truthy(
				day_ok,
				"route=%s day=%d authoritative daily simulation actual=%s expected=true" % [route_id, day, day_ok]
			)
			_assert_daily_invariants(assertions, market, npc, previous_prices, route_id, day)
		_update_essential_streaks(market, zero_streaks, max_zero_streaks)
		for definition in GameDataScript.get_market_items():
			var item_id := str(definition.id)
			previous_prices[item_id] = market.get_mid_price(item_id)
	var economy_state := economy.to_dict()
	var producer_snapshots: Array[Dictionary] = []
	for building in context.buildings:
		var snapshot := production.get_building_snapshot(building)
		producer_snapshots.append({
			"building_id": str(snapshot.get("building_id", "")),
			"station_id": str(snapshot.get("station_id", "")),
			"jobs": snapshot.get("jobs", []).duplicate(true),
			"outputs": snapshot.get("outputs", {}).duplicate(true),
			"inputs": snapshot.get("inputs", {}).duplicate(true),
			"maintenance_due_day": int(snapshot.get("maintenance_due_day", -1)),
		})
	var result := {
		"authoritative": true,
		"daily_cursor": daily.last_simulated_day,
		"daily_income": daily_income,
		"stage_income": _stage_averages(daily_income),
		"market": market.to_dict(),
		"npc": npc.to_dict(),
		"inventory": inventory.slots.duplicate(true),
		"wallet_gold": int(wallet.gold),
		"producer_snapshots": producer_snapshots,
		"essential_max_zero_streaks": max_zero_streaks,
		"maintenance_events": maintenance_events,
		"maintenance_pause_checks": maintenance_pause_checks,
		"transactions": transactions,
		"economy_cursor": int(economy_state.last_processed_day),
		"market_changed": market.to_dict() != initial_market,
		"npc_changed": npc.to_dict() != initial_npc,
		"orders_created": (economy_state.orders as Array).size(),
		"farming_harvests": int(context.farming_harvests),
		"seed": seed,
	}
	_cleanup_route_context(context)
	return result


func _create_route_context(assertions: TestAssert, route_id: String, verify: bool) -> Dictionary:
	var market := MarketSystemScript.new()
	var npc := NpcEconomySystemScript.new()
	var inventory := InventorySystemScript.new()
	var wallet := GameStateScript.new()
	var economy := EconomySystemScript.new()
	var grid := GridSystemScript.new()
	var farming := FarmingSystemScript.new()
	var production := ProductionSystemScript.new()
	var daily := DailySimulationSystemScript.new()
	var save := SaveDouble.new()
	inventory.max_slots = 200
	inventory.reset_slots()
	wallet.gold = 1000000
	var configured := market.configure(GameDataScript.get_market_items())
	configured = configured and npc.configure(
		market, GameDataScript.get_npc_economy_profiles(), GameDataScript.get_population_demand_profiles()
	)
	configured = configured and farming.configure(grid, null, wallet)
	configured = configured and production.configure(grid, farming, null, inventory)
	configured = configured and economy.configure(inventory, wallet, market, npc)
	var buildings: Array[BuildingInstance] = []
	var building_by_station := {}
	if route_id != "no_player":
		var route: Dictionary = ROUTES[route_id]
		for passive_id_value in route.get("passive_buildings", []):
			var passive_id := str(passive_id_value)
			var passive := _new_building(passive_id, passive_id)
			passive.producer_state = null
			buildings.append(passive)
			building_by_station[passive_id] = passive
			configured = configured and production.register_building(passive)
	configured = configured and daily.configure(production, farming, npc, economy, market, save)
	var farm_cell: GridCell = null
	var farm_crop: CropData = null
	if route_id == "crop_farming":
		farm_cell = GridCellScript.new()
		farm_cell.gx = 1
		farm_cell.gz = 1
		farm_cell.state = GridCell.State.FARMLAND
		grid._cells[GridSystemScript.cell_key(1, 1)] = farm_cell
		farm_crop = CropDataScript.new()
		farm_crop.crop_id = "grain"
		farm_crop.growth_days = 3
		farm_crop.yield_min = 1
		farm_crop.yield_max = 1
		configured = configured and grid.plant_crop(1, 1, farm_crop) != null
	if verify:
		assertions.truthy(configured, "route=%s day=0 authoritative fixture configured" % route_id)
	return {
		"market": market, "npc": npc, "inventory": inventory, "wallet": wallet,
		"economy": economy, "grid": grid, "farming": farming, "production": production,
		"daily": daily, "save": save, "buildings": buildings,
		"building_by_station": building_by_station,
		"farm_cell": farm_cell, "farm_crop": farm_crop, "farming_harvests": 0,
	}


func _new_building(building_id: String, station_id: String) -> BuildingInstance:
	var building := BuildingInstanceScript.new()
	building.authored_building_id = building_id
	building.producer_state = ProducerStateScript.new(station_id)
	return building


func _run_authoritative_route_day(
	assertions: TestAssert,
	context: Dictionary,
	route_id: String,
	stage: String,
	day: int,
	verify: bool
) -> Dictionary:
	var inventory: InventorySystem = context.inventory
	var wallet: Node = context.wallet
	var economy: EconomySystem = context.economy
	var production: ProductionSystem = context.production
	var route: Dictionary = ROUTES[route_id]
	var result := {
		"maintenance_events": 0, "maintenance_pause_checks": 0,
		"transactions": {"buys": 0, "sells": 0, "recipes": 0, "collections": 0},
	}
	var daily_cost := int(route.get("daily_gold_cost", 0))
	if daily_cost > 0:
		assertions.truthy(wallet.spend_gold(daily_cost), "route=%s day=%d route cost paid" % [route_id, day])
	for recipe_id_value in route.recipes[stage]:
		var station := str(RecipeDatabaseScript.get_recipe(str(recipe_id_value)).station)
		if context.building_by_station.has(station):
			continue
		var unlocked_building := _new_building(station, station)
		context.buildings.append(unlocked_building)
		context.building_by_station[station] = unlocked_building
		assertions.truthy(
			production.register_building(unlocked_building),
			"route=%s day=%d station=%s registers on unlock" % [route_id, day, station]
		)
	for building in context.buildings:
		if not production.is_maintenance_overdue(building):
			continue
		var quote := production.get_maintenance_quote(building)
		var snapshot := production.get_building_snapshot(building)
		if not (snapshot.jobs as Array).is_empty():
			production.advance_minutes(60)
			assertions.equal(
				production.get_building_snapshot(building).jobs,
				snapshot.jobs,
				"route=%s day=%d overdue producer pauses" % [route_id, day]
			)
			result.maintenance_pause_checks += 1
		for item_id_value in (quote.materials as Dictionary).keys():
			var item_id := str(item_id_value)
			var missing := maxi(0, int(quote.materials[item_id]) - inventory.get_item_count(item_id))
			if missing > 0:
				var before_purchase := int(wallet.gold)
				assertions.truthy(
					economy.buy_item(item_id, missing),
					"route=%s day=%d maintenance material=%s bought from market" % [route_id, day, item_id]
				)
				assertions.truthy(int(wallet.gold) < before_purchase, "maintenance purchase changes real wallet")
				result.transactions.buys += 1
		var gold_before := int(wallet.gold)
		var materials_before := _inventory_counts(inventory, quote.materials.keys())
		assertions.truthy(production.maintain(building, wallet, inventory), "route=%s day=%d maintenance succeeds" % [route_id, day])
		assertions.equal(gold_before - int(wallet.gold), int(quote.gold_cost), "maintenance uses quoted gold")
		for item_id_value in (quote.materials as Dictionary).keys():
			var item_id := str(item_id_value)
			assertions.equal(
				int(materials_before[item_id]) - inventory.get_item_count(item_id),
				int(quote.materials[item_id]),
				"maintenance uses quoted %s" % item_id
			)
		assertions.truthy(not production.is_maintenance_overdue(building), "maintenance resumes producer")
		result.maintenance_events += 1
	var capacity := int(ROUTE_STAGE_CAPACITY[route_id][stage])
	for item_id_value in (route.daily_output as Dictionary).keys():
		var item_id := str(item_id_value)
		assertions.truthy(
			inventory.add_item(item_id, int(route.daily_output[item_id]) * capacity),
			"route=%s day=%d external output=%s enters real inventory" % [route_id, day, item_id]
		)
	for passive_id_value in route.get("passive_buildings", []):
		var passive: BuildingInstance = context.building_by_station[str(passive_id_value)]
		if passive.building_id == "chicken_coop":
			if inventory.get_item_count("animal_feed") <= 0:
				var before := int(wallet.gold)
				if economy.buy_item("animal_feed", 1):
					result.transactions.buys += 1
					assertions.truthy(int(wallet.gold) < before, "chicken feed purchase changes real wallet")
			if inventory.get_item_count("animal_feed") > 0:
				assertions.truthy(production.add_input(passive, "animal_feed", 1, inventory), "chicken feed enters ProducerState")
	for recipe_id_value in route.recipes[stage]:
		var recipe_id := str(recipe_id_value)
		var recipe := RecipeDatabaseScript.get_recipe(recipe_id)
		var building: BuildingInstance = context.building_by_station[str(recipe.station)]
		if not (production.get_building_snapshot(building).jobs as Array).is_empty():
			continue
		var batches := int(STAGE_BATCHES[stage])
		for input_id_value in (recipe.inputs as Dictionary).keys():
			var input_id := str(input_id_value)
			var required := int(recipe.inputs[input_id]) * batches
			var missing := maxi(0, required - inventory.get_item_count(input_id))
			if missing > 0 and input_id in route.purchased_inputs:
				var before := int(wallet.gold)
				if economy.buy_item(input_id, missing):
					result.transactions.buys += 1
					assertions.truthy(int(wallet.gold) < before, "route=%s day=%d buy=%s changes real wallet" % [route_id, day, input_id])
			batches = mini(batches, int(inventory.get_item_count(input_id) / int(recipe.inputs[input_id])))
		if batches > 0 and production.start_recipe(building, recipe_id, batches, inventory):
			result.transactions.recipes += 1
	production.advance_minutes(1440)
	production.finish_daily_outputs(day)
	for building in context.buildings:
		if production.collect_all(building, inventory):
			result.transactions.collections += 1
	var sale_ids: Array[String] = []
	for slot in inventory.slots:
		if not slot.is_empty() and str(slot.item_id) not in sale_ids:
			sale_ids.append(str(slot.item_id))
	sale_ids.sort()
	for item_id in sale_ids:
		var quantity := inventory.get_item_count(item_id)
		if quantity <= 0:
			continue
		var before := int(wallet.gold)
		if economy.sell_item(item_id, quantity):
			result.transactions.sells += 1
			if verify:
				assertions.truthy(int(wallet.gold) > before, "route=%s day=%d sell=%s changes real wallet" % [route_id, day, item_id])
	return result


func _advance_farm_witness(assertions: TestAssert, context: Dictionary, day: int) -> void:
	var cell: GridCell = context.farm_cell
	if cell == null or cell.crop_instance == null or not cell.crop_instance.is_mature():
		return
	var harvest: Dictionary = context.farming.harvest(cell)
	assertions.truthy(not harvest.is_empty(), "route=crop_farming day=%d real crop harvest completes" % day)
	for item_id_value in (harvest.get("items", {}) as Dictionary).keys():
		var item_id := str(item_id_value)
		assertions.truthy(
			context.inventory.add_item(item_id, int(harvest.items[item_id])),
			"route=crop_farming day=%d harvest=%s enters real inventory" % [day, item_id]
		)
	context.farming_harvests = int(context.farming_harvests) + 1
	assertions.truthy(
		context.grid.plant_crop(cell.gx, cell.gz, context.farm_crop) != null,
		"route=crop_farming day=%d witness crop replants" % day
	)


func _inventory_counts(inventory: InventorySystem, item_ids: Array) -> Dictionary:
	var result := {}
	for item_id_value in item_ids:
		var item_id := str(item_id_value)
		result[item_id] = inventory.get_item_count(item_id)
	return result


func _essential_counter_map() -> Dictionary:
	var result := {}
	for definition in GameDataScript.get_market_items():
		if str(definition.get("volatility", "")) == "essential":
			result[str(definition.id)] = 0
	return result


func _update_essential_streaks(market: MarketSystem, streaks: Dictionary, maximums: Dictionary) -> void:
	for item_id_value in streaks.keys():
		var item_id := str(item_id_value)
		streaks[item_id] = int(streaks[item_id]) + 1 if market.get_stock(item_id) == 0 else 0
		maximums[item_id] = maxi(int(maximums[item_id]), int(streaks[item_id]))


func _cleanup_route_context(context: Dictionary) -> void:
	for building in context.buildings:
		if is_instance_valid(building):
			building.free()
	for key in ["daily", "save", "economy", "production", "farming", "grid", "npc", "market", "inventory", "wallet"]:
		var node: Node = context[key]
		if is_instance_valid(node):
			node.free()


func _assert_daily_invariants(
	assertions: TestAssert,
	market: MarketSystem,
	npc: NpcEconomySystem,
	previous_prices: Dictionary,
	route_id: String,
	day: int
) -> void:
	for definition in GameDataScript.get_market_items():
		var item_id := str(definition.id)
		var state := market.get_item_state(item_id)
		var base := int(definition.base_price)
		var price := int(state.mid_price)
		var lower := ceili(base * 0.5)
		var upper := floori(base * 2.5)
		assertions.truthy(
			int(state.stock) >= 0 and int(state.demand) >= 0 and int(state.supply) >= 0,
			"route=%s day=%d item=%s nonnegative market actual=%s expected=>=0" % [
				route_id, day, item_id, state,
			]
		)
		assertions.truthy(
			price >= lower and price <= upper,
			"route=%s day=%d item=%s price bound actual=%d expected=%d..%d" % [
				route_id, day, item_id, price, lower, upper,
			]
		)
		var previous := int(previous_prices[item_id])
		var daily_lower := maxi(lower, ceili(float(previous * 85) / 100.0))
		var daily_upper := mini(upper, floori(float(previous * 115) / 100.0))
		assertions.truthy(
			price >= daily_lower and price <= daily_upper,
			"route=%s day=%d item=%s daily movement actual=%d expected=%d..%d previous=%d" % [
				route_id, day, item_id, price, daily_lower, daily_upper, previous,
			]
		)
	var npc_snapshot := npc.to_dict()
	for state_value in npc_snapshot.npc_states:
		var state: Dictionary = state_value
		assertions.truthy(
			int(state.gold) >= 0,
			"route=%s day=%d npc=%s gold actual=%d expected=>=0" % [
				route_id, day, str(state.npc_id), int(state.gold),
			]
		)
		for item_id_value in (state.inventory as Dictionary).keys():
			var item_id := str(item_id_value)
			assertions.truthy(
				int(state.inventory[item_id]) >= 0,
				"route=%s day=%d npc=%s item=%s inventory actual=%d expected=>=0" % [
					route_id, day, str(state.npc_id), item_id, int(state.inventory[item_id]),
				]
			)


func _assert_route_balance(assertions: TestAssert, suite: Dictionary) -> void:
	for stage in ["early", "mid", "late"]:
		var incomes: Dictionary = {}
		for route_id_value in ROUTES.keys():
			var route_id := str(route_id_value)
			var average := int(suite.routes[route_id].stage_income[stage])
			incomes[route_id] = average
			var limits: Vector2i = STAGE_INCOME_LIMITS[stage]
			assertions.truthy(
				average >= limits.x and average <= limits.y,
				"route=%s stage=%s income actual=%d expected=%d..%d" % [
					route_id, stage, average, limits.x, limits.y,
				]
			)
		var values: Array = incomes.values()
		var lowest := int(values.min())
		var highest := int(values.max())
		var spread := float(highest - lowest) / float(maxi(highest, 1))
		assertions.truthy(
			spread <= 0.20,
			"route=all stage=%s unit-time spread actual=%.4f expected=<=0.2000 incomes=%s" % [
				stage, spread, incomes,
			]
		)
		print("ECONOMY_SIM stage=%s incomes=%s spread=%.4f" % [stage, incomes, spread])


func _test_essential_shortage_recovers(assertions: TestAssert) -> void:
	var market := MarketSystemScript.new()
	market.configure([_definition("grain", 8, 0, 10, 5, "essential", "crop")])
	var npc := NpcEconomySystemScript.new()
	var importer := {
		"id": "shortage_importer", "display_name": "短缺商队", "gold": 2000,
		"inventory": {}, "essential_targets": {"grain": 5}, "reserve_targets": {},
		"production_recipes": [], "sale_targets": {},
		"investment_gold_threshold": 4000, "import_buffer": true,
	}
	assertions.truthy(
		npc.configure(market, [importer], []),
		"route=no_player day=0 item=grain shortage fixture actual=configured expected=true"
	)
	var inventory := InventorySystemScript.new()
	var wallet := GameStateScript.new()
	var economy := EconomySystemScript.new()
	wallet.gold = 1000
	assertions.truthy(economy.configure(inventory, wallet, market, npc), "shortage order fixture configures")
	var longest_zero_streak := 0
	var zero_streak := 0
	var recovery_day := 0
	for day in range(1, 8):
		npc.simulate_day(day)
		economy.advance_order_deadlines(day)
		market.settle_day(day)
		economy.generate_demand_orders(day)
		if market.get_stock("grain") == 0:
			zero_streak += 1
			longest_zero_streak = maxi(longest_zero_streak, zero_streak)
		else:
			if recovery_day == 0:
				recovery_day = day
			zero_streak = 0
	assertions.truthy(
		longest_zero_streak <= 3,
		"route=no_player day=%d item=grain essential shortage actual=%d expected=<=3" % [
			recovery_day, longest_zero_streak,
		]
	)
	assertions.truthy(
		recovery_day > 0 and recovery_day <= 3,
		"route=no_player day=%d item=grain recovery actual=%d expected=1..3" % [
			recovery_day, recovery_day,
		]
	)
	assertions.truthy(not economy.get_orders().is_empty(), "essential shortage creates a real demand order")
	print("ECONOMY_SIM shortage item=grain max_zero_days=%d recovery_day=%d" % [
		longest_zero_streak, recovery_day,
	])
	npc.free()
	market.free()
	economy.free()
	inventory.free()
	wallet.free()


func _test_dumping_depresses_then_recovers(assertions: TestAssert) -> void:
	var market := MarketSystemScript.new()
	market.configure([
		_definition("wood", 100, 100, 100, 20, "essential", "material"),
		_definition("plank", 34, 35, 45, 18, "industrial", "processed_material"),
	])
	var npc := NpcEconomySystemScript.new()
	var consumer := {
		"id": "wood_consumer", "display_name": "木材合作社", "gold": 20000,
		"inventory": {}, "essential_targets": {"wood": 20}, "reserve_targets": {},
		"production_recipes": ["plank"], "sale_targets": {"plank": 1},
		"investment_gold_threshold": 40000, "import_buffer": false,
	}
	assertions.truthy(
		npc.configure(market, [consumer], [{"id": "builders", "display_name": "建筑工人", "demands": {"wood": 8}, "demand_tag": "建设需求"}]),
		"dump fixture configures real NPC and population demand"
	)
	var inventory := InventorySystemScript.new()
	inventory.max_slots = 20
	inventory.reset_slots()
	var wallet := GameStateScript.new()
	wallet.gold = 1000
	var economy := EconomySystemScript.new()
	assertions.truthy(economy.configure(inventory, wallet, market, npc), "dump fixture configures real EconomySystem")
	var prices: Array[int] = [market.get_mid_price("wood")]
	var stock_after_dump := 0
	for day in range(1, 11):
		if day <= 2:
			assertions.truthy(inventory.add_item("wood", 80), "dump day=%d external wood enters real inventory" % day)
			assertions.truthy(economy.sell_item("wood", 80), "dump day=%d uses EconomySystem.sell_item" % day)
		npc.simulate_day(day)
		economy.advance_order_deadlines(day)
		market.settle_day(day)
		economy.generate_demand_orders(day)
		prices.append(market.get_mid_price("wood"))
		if day == 2:
			stock_after_dump = market.get_stock("wood")
	var dump_low := prices[2]
	assertions.truthy(
		dump_low < prices[0],
		"route=dump day=2 item=wood depressed price actual=%d expected=<%d trace=%s" % [
			dump_low, prices[0], prices,
		]
	)
	assertions.truthy(
		prices[-1] > dump_low,
		"route=dump day=10 item=wood recovery actual=%d expected=>%d trace=%s" % [
			prices[-1], dump_low, prices,
		]
	)
	var recovery_started := false
	for index in range(3, prices.size()):
		if prices[index] > prices[index - 1]:
			recovery_started = true
		if recovery_started:
			assertions.truthy(
				prices[index] >= prices[index - 1],
				"route=dump day=%d item=wood gradual recovery actual=%d expected=>=%d trace=%s" % [
					index, prices[index], prices[index - 1], prices,
				]
			)
	assertions.truthy(
		recovery_started,
		"route=dump day=10 item=wood recovery trend actual=%s expected=increase" % [prices]
	)
	assertions.truthy(
		market.get_stock("wood") < stock_after_dump,
		"route=dump day=10 natural NPC demand consumes dumped stock actual=%d expected=<%d" % [
			market.get_stock("wood"), stock_after_dump,
		]
	)
	print("ECONOMY_SIM dumping item=wood prices=%s" % [prices])
	npc.free()
	economy.free()
	inventory.free()
	wallet.free()
	market.free()


func _test_no_instant_recipe_arbitrage(assertions: TestAssert) -> void:
	var checked := 0
	var profitable := 0
	var losing := 0
	for recipe in RecipeDatabaseScript.get_all_recipes():
		var inputs: Dictionary = recipe.inputs
		var outputs: Dictionary = recipe.outputs
		var all_tradable := true
		for item_id_value in inputs.keys():
			var definition: Variant = GameDataScript.get_item(str(item_id_value))
			all_tradable = all_tradable and definition != null and int(definition.get("base_price", 0)) > 0
		for item_id_value in outputs.keys():
			var definition: Variant = GameDataScript.get_item(str(item_id_value))
			all_tradable = all_tradable and definition != null and int(definition.get("base_price", 0)) > 0
		if not all_tradable:
			continue
		checked += 1
		assertions.truthy(
			int(recipe.duration_minutes) > 0,
			"route=arbitrage_bot day=0 recipe=%s duration actual=%d expected=>0" % [
				str(recipe.id), int(recipe.duration_minutes),
			]
		)
		var result := _simulate_arbitrage_recipe(recipe)
		if int(result.total_profit) > 0:
			profitable += 1
		else:
			losing += 1
		assertions.truthy(
			int(result.batches) <= int(result.capacity),
			"route=arbitrage_bot day=28 recipe=%s batches actual=%d expected=<=%d" % [
				str(recipe.id), int(result.batches), int(result.capacity),
			]
		)
		assertions.equal(
			int(result.total_profit),
			_sum_ints(result.daily_profits),
			"route=arbitrage_bot day=28 recipe=%s accounting total equals daily sum" % str(recipe.id)
		)
		assertions.truthy(
			bool(result.authoritative) and int(result.recipes_started) > 0,
			"route=arbitrage_bot day=28 recipe=%s uses real Economy/Production transactions" % str(recipe.id)
		)
		if int(recipe.duration_minutes) > 1440:
			assertions.truthy(
				int(result.daily_profits[0]) <= 0,
				"route=arbitrage_bot day=1 recipe=%s cannot sell output before duration elapses" % str(recipe.id)
			)
		assertions.truthy(
			int(result.total_profit) <= 28 * int(STAGE_INCOME_LIMITS.late.y),
			"route=arbitrage_bot day=28 recipe=%s profit actual=%d expected=<=%d" % [
				str(recipe.id), int(result.total_profit), 28 * int(STAGE_INCOME_LIMITS.late.y),
			]
		)
	assertions.equal(
		checked,
		RecipeDatabaseScript.get_all_recipes().size(),
		"route=instant_recipe day=0 covers every tradable recipe"
	)
	assertions.truthy(
		profitable > 0 and losing > 0,
		"route=arbitrage_bot day=28 mixed outcomes actual=profit:%d loss:%d expected=both>0" % [
			profitable, losing,
		]
	)
	print("ECONOMY_SIM arbitrage recipes=%d profitable=%d losing=%d" % [checked, profitable, losing])


func _simulate_arbitrage_recipe(recipe: Dictionary) -> Dictionary:
	var market := MarketSystemScript.new()
	market.configure(GameDataScript.get_market_items())
	var inventory := InventorySystemScript.new()
	inventory.max_slots = 80
	inventory.reset_slots()
	var wallet := GameStateScript.new()
	wallet.gold = 1000000
	var economy := EconomySystemScript.new()
	economy.configure(inventory, wallet, market)
	var grid := GridSystemScript.new()
	var farming := FarmingSystemScript.new()
	farming.configure(grid, null, wallet)
	var production := ProductionSystemScript.new()
	production.configure(grid, farming, null, inventory)
	var building := _new_building(str(recipe.station), str(recipe.station))
	production.register_building(building)
	var total_profit := 0
	var early_profit := 0
	var late_profit := 0
	var batches := 0
	var recipes_started := 0
	var daily_profits: Array[int] = []
	for day in range(1, SIMULATION_DAYS + 1):
		production.begin_day(day)
		var gold_before := int(wallet.gold)
		if production.is_maintenance_overdue(building):
			var quote := production.get_maintenance_quote(building)
			var maintenance_ready := true
			for item_id_value in (quote.materials as Dictionary).keys():
				var item_id := str(item_id_value)
				var quantity := int(quote.materials[item_id])
				if inventory.get_item_count(item_id) < quantity:
					maintenance_ready = maintenance_ready and economy.buy_item(item_id, quantity)
			if maintenance_ready:
				production.maintain(building, wallet, inventory)
		if (production.get_building_snapshot(building).jobs as Array).is_empty():
			var can_trade := true
			var total_cost := 0
			for item_id_value in (recipe.inputs as Dictionary).keys():
				var item_id := str(item_id_value)
				var quantity := int(recipe.inputs[item_id])
				can_trade = can_trade and market.can_buy(item_id, quantity)
				total_cost += market.quote_buy(item_id, quantity)
			can_trade = can_trade and int(wallet.gold) >= total_cost
			if can_trade:
				for item_id_value in (recipe.inputs as Dictionary).keys():
					var item_id := str(item_id_value)
					can_trade = can_trade and economy.buy_item(item_id, int(recipe.inputs[item_id]))
				if can_trade and production.start_recipe(building, str(recipe.id), 1, inventory):
					batches += 1
					recipes_started += 1
		production.advance_minutes(1440)
		production.collect_all(building, inventory)
		for output_id_value in (recipe.outputs as Dictionary).keys():
			var output_id := str(output_id_value)
			var quantity := inventory.get_item_count(output_id)
			if quantity > 0:
				economy.sell_item(output_id, quantity)
		var day_profit := int(wallet.gold) - gold_before
		total_profit += day_profit
		daily_profits.append(day_profit)
		if day <= 7:
			early_profit += day_profit
		elif day >= 22:
			late_profit += day_profit
		market.settle_day(day)
	building.free()
	production.free()
	farming.free()
	grid.free()
	economy.free()
	inventory.free()
	wallet.free()
	market.free()
	return {
		"authoritative": true,
		"total_profit": total_profit,
		"early_profit": early_profit,
		"late_profit": late_profit,
		"batches": batches,
		"capacity": SIMULATION_DAYS,
		"recipes_started": recipes_started,
		"daily_profits": daily_profits,
	}


func _sum_ints(values: Array) -> int:
	var total := 0
	for value in values:
		total += int(value)
	return total


func _test_recipe_value_ladders(assertions: TestAssert) -> void:
	var categories := {
		"initial": [
			"plank", "rope", "charcoal", "stone_brick", "brick", "glass",
			"copper_ingot", "iron_ingot", "steel", "cloth", "flour", "animal_feed",
			"wooden_crate",
		],
		"food": [
			"sunflower_oil", "fruit_jam", "pickles", "tomato_sauce",
			"fruit_juice", "bread", "honey_cake",
		],
		"craft": [
			"furniture", "farm_tools", "machine_parts",
			"lamp", "sachet", "candle", "bouquet",
		],
		"luxury": ["perfume", "jewelry"],
	}
	var mapped: Array[String] = []
	for category in categories:
		for recipe_id_value in categories[category]:
			var recipe_id := str(recipe_id_value)
			assertions.truthy(recipe_id not in mapped, "recipe=%s appears in exactly one value category" % recipe_id)
			mapped.append(recipe_id)
	var actual: Array[String] = []
	for recipe in RecipeDatabaseScript.get_all_recipes():
		actual.append(str(recipe.id))
	mapped.sort()
	actual.sort()
	assertions.equal(mapped, actual, "recipe value categories exhaustively cover RecipeDatabase")
	for recipe_id in categories.initial:
		_assert_recipe_ratio(assertions, recipe_id, 1.20, 1.40)
	for recipe_id in categories.food:
		_assert_recipe_ratio(assertions, recipe_id, 1.40, 1.70)
	for recipe_id in categories.craft:
		_assert_recipe_ratio(assertions, recipe_id, 1.60, 2.00)
	for recipe_id in categories.luxury:
		_assert_recipe_ratio(assertions, recipe_id, 2.00, 2.20)


func _assert_recipe_ratio(
	assertions: TestAssert,
	recipe_id: String,
	minimum: float,
	maximum: float
) -> void:
	var recipe := RecipeDatabaseScript.get_recipe(recipe_id)
	var input_value := 0
	var output_value := 0
	for item_id_value in (recipe.inputs as Dictionary).keys():
		var item_id := str(item_id_value)
		input_value += int(GameDataScript.get_item(item_id).base_price) * int(recipe.inputs[item_id])
	for item_id_value in (recipe.outputs as Dictionary).keys():
		var item_id := str(item_id_value)
		output_value += int(GameDataScript.get_item(item_id).base_price) * int(recipe.outputs[item_id])
	var ratio := float(output_value) / float(maxi(input_value, 1))
	assertions.truthy(
		ratio >= minimum and ratio <= maximum,
		"route=recipe_value day=0 recipe=%s ratio actual=%.4f expected=%.2f..%.2f input=%d output=%d" % [
			recipe_id, ratio, minimum, maximum, input_value, output_value,
		]
	)


func _stage_for_day(day: int) -> String:
	if day <= int(STAGE_RANGES.early.y):
		return "early"
	if day <= int(STAGE_RANGES.mid.y):
		return "mid"
	return "late"


func _stage_averages(daily_income: Array[int]) -> Dictionary:
	var result := {}
	for stage in STAGE_RANGES:
		var days: Vector2i = STAGE_RANGES[stage]
		var total := 0
		for day in range(days.x, days.y + 1):
			total += daily_income[day - 1]
		result[stage] = roundi(float(total) / float(days.y - days.x + 1))
	return result


func _seeded_factor(rng: RandomNumberGenerator) -> float:
	return float(rng.randi_range(90, 110)) / 100.0


func _definition(
	item_id: String,
	base_price: int,
	initial_stock: int,
	target_stock: int,
	daily_liquidity: int,
	volatility: String,
	category: String
) -> Dictionary:
	return {
		"id": item_id,
		"base_price": base_price,
		"initial_stock": initial_stock,
		"target_stock": target_stock,
		"daily_liquidity": daily_liquidity,
		"volatility": volatility,
		"category": category,
	}
