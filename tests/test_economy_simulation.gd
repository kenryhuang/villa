extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomySystemScript = preload("res://scripts/systems/npc_economy_system.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")

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
		"daily_gold_cost": 0,
	},
	"flower_apiary": {
		"daily_output": {"honey": 1, "beeswax": 1, "rose": 1, "fiber": 1},
		"recipes": {"early": [], "mid": ["bouquet"], "late": ["bouquet"]},
		"purchased_inputs": [],
		"daily_gold_cost": 0,
	},
	"mining_manufacturing": {
		"daily_output": {"coal": 1, "iron_ore": 2, "wood": 1},
		"recipes": {
			"early": [], "mid": ["iron_ingot", "plank"],
			"late": ["iron_ingot", "plank"],
		},
		"purchased_inputs": [],
		"daily_gold_cost": 0,
	},
	"orchard_processing": {
		"daily_output": {"strawberry": 3, "apple": 1, "honey": 1},
		"recipes": {"early": [], "mid": ["fruit_jam"], "late": ["fruit_jam"]},
		"purchased_inputs": ["honey", "glass_jar"],
		"daily_gold_cost": 0,
	},
}
const STAGE_RANGES := {
	"early": Vector2i(1, 7),
	"mid": Vector2i(8, 18),
	"late": Vector2i(19, 28),
}
const STAGE_CAPACITY := {"early": 1, "mid": 4, "late": 20}
const STAGE_STATIONS := {"early": 0, "mid": 1, "late": 3}
const MAINTENANCE_INTERVAL_DAYS := 7
const MAINTENANCE_GOLD_COST := 25
const STAGE_INCOME_LIMITS := {
	"early": Vector2i(40, 80),
	"mid": Vector2i(150, 300),
	"late": Vector2i(500, 1000),
}


func run(assertions: TestAssert) -> void:
	var first := _run_acceptance_suite(assertions, SIMULATION_SEED, true)
	var repeated := _run_acceptance_suite(assertions, SIMULATION_SEED, false)
	assertions.equal(
		repeated,
		first,
		"route=all day=28 deterministic replay actual=second expected=first seed=%d" % SIMULATION_SEED
	)
	_assert_route_balance(assertions, first)
	_test_essential_shortage_recovers(assertions)
	_test_dumping_depresses_then_recovers(assertions)
	_test_recipe_value_ladders(assertions)
	_test_no_instant_recipe_arbitrage(assertions)


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
	var market := MarketSystemScript.new()
	var configured := market.configure(GameDataScript.get_market_items())
	if verify:
		assertions.truthy(
			configured,
			"route=%s day=0 market configured actual=%s expected=true" % [route_id, configured]
		)
	var npc := NpcEconomySystemScript.new()
	configured = npc.configure(
		market,
		GameDataScript.get_npc_economy_profiles(),
		GameDataScript.get_population_demand_profiles()
	)
	if verify:
		assertions.truthy(
			configured,
			"route=%s day=0 NPC configured actual=%s expected=true" % [route_id, configured]
		)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var daily_income: Array[int] = []
	var previous_prices: Dictionary = {}
	for definition in GameDataScript.get_market_items():
		previous_prices[str(definition.id)] = int(definition.base_price)
	for day in range(1, SIMULATION_DAYS + 1):
		var income := 0
		if route_id != "no_player":
			income = _sell_route_output(market, route_id, _stage_for_day(day), day)
		daily_income.append(income)
		var population_factors := {
			"residents": _seeded_factor(rng),
			"builders": _seeded_factor(rng),
			"artisans": _seeded_factor(rng),
			"tourists": _seeded_factor(rng),
		}
		var npc_ok := npc.simulate_day(day, population_factors, {})
		var settle_ok := market.settle_day(day)
		if verify:
			assertions.truthy(
				npc_ok,
				"route=%s day=%d NPC step actual=%s expected=true" % [route_id, day, npc_ok]
			)
			assertions.truthy(
				settle_ok,
				"route=%s day=%d settlement actual=%s expected=true" % [route_id, day, settle_ok]
			)
			_assert_daily_invariants(assertions, market, npc, previous_prices, route_id, day)
		for definition in GameDataScript.get_market_items():
			var item_id := str(definition.id)
			previous_prices[item_id] = market.get_mid_price(item_id)
	var result := {
		"daily_income": daily_income,
		"stage_income": _stage_averages(daily_income),
		"market": market.to_dict(),
		"npc": npc.to_dict(),
	}
	npc.free()
	market.free()
	return result


func _sell_route_output(market: MarketSystem, route_id: String, stage: String, day: int) -> int:
	var revenue := 0
	var costs := int((ROUTES[route_id] as Dictionary).get("daily_gold_cost", 0))
	var capacity := int(STAGE_CAPACITY[stage])
	var route: Dictionary = ROUTES[route_id]
	var inventory: Dictionary = {}
	var output: Dictionary = route.daily_output
	for item_id_value in output.keys():
		var item_id := str(item_id_value)
		inventory[item_id] = int(output[item_id]) * capacity
	for recipe_id_value in route.recipes[stage]:
		var recipe_id := str(recipe_id_value)
		var recipe := RecipeDatabaseScript.get_recipe(recipe_id)
		var batch_limit := int(1440 * int(STAGE_STATIONS[stage])) / int(recipe.duration_minutes)
		var batches := batch_limit
		for item_id_value in (recipe.inputs as Dictionary).keys():
			var item_id := str(item_id_value)
			var required := int(recipe.inputs[item_id])
			var available := int(inventory.get(item_id, 0))
			if available < required * batches and item_id in route.purchased_inputs:
				var missing := required * batches - available
				var quote := market.quote_buy(item_id, missing)
				if quote > 0 and market.commit_buy(item_id, missing):
					costs += quote
					inventory[item_id] = available + missing
			batches = mini(batches, int(inventory.get(item_id, 0)) / required)
		if batches <= 0:
			continue
		for item_id_value in (recipe.inputs as Dictionary).keys():
			var item_id := str(item_id_value)
			inventory[item_id] = int(inventory.get(item_id, 0)) - int(recipe.inputs[item_id]) * batches
		for item_id_value in (recipe.outputs as Dictionary).keys():
			var item_id := str(item_id_value)
			inventory[item_id] = int(inventory.get(item_id, 0)) + int(recipe.outputs[item_id]) * batches
	if not (route.recipes[stage] as Array).is_empty() and day % MAINTENANCE_INTERVAL_DAYS == 0:
		var station_types: Dictionary = {}
		for recipe_id_value in route.recipes[stage]:
			var recipe := RecipeDatabaseScript.get_recipe(str(recipe_id_value))
			station_types[str(recipe.station)] = true
		costs += (
			MAINTENANCE_GOLD_COST
			* int(STAGE_STATIONS[stage])
			* station_types.size()
		)
	var item_ids := inventory.keys()
	item_ids.sort()
	for item_id_value in item_ids:
		var item_id := str(item_id_value)
		var quantity := int(inventory[item_id])
		if quantity <= 0:
			continue
		var quote := market.quote_sell(item_id, quantity)
		if quote > 0 and market.commit_sell(item_id, quantity):
			revenue += quote
	return revenue - costs


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
		"inventory": {}, "essential_targets": {}, "reserve_targets": {},
		"production_recipes": [], "sale_targets": {},
		"investment_gold_threshold": 4000, "import_buffer": true,
	}
	assertions.truthy(
		npc.configure(market, [importer], []),
		"route=no_player day=0 item=grain shortage fixture actual=configured expected=true"
	)
	var longest_zero_streak := 0
	var zero_streak := 0
	var recovery_day := 0
	for day in range(1, 8):
		npc.simulate_day(day)
		market.settle_day(day)
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
	print("ECONOMY_SIM shortage item=grain max_zero_days=%d recovery_day=%d" % [
		longest_zero_streak, recovery_day,
	])
	npc.free()
	market.free()


func _test_dumping_depresses_then_recovers(assertions: TestAssert) -> void:
	var market := MarketSystemScript.new()
	market.configure([_definition("wood", 100, 100, 100, 20, "essential", "material")])
	var prices: Array[int] = [market.get_mid_price("wood")]
	for day in range(1, 8):
		if day <= 2:
			market.commit_sell("wood", 80)
		else:
			var consumed := mini(80, market.get_stock("wood"))
			if consumed > 0:
				market.commit_buy("wood", consumed)
		market.settle_day(day)
		prices.append(market.get_mid_price("wood"))
	var dump_low := prices[2]
	assertions.truthy(
		dump_low < prices[0],
		"route=dump day=2 item=wood depressed price actual=%d expected=<%d trace=%s" % [
			dump_low, prices[0], prices,
		]
	)
	assertions.truthy(
		prices[-1] > dump_low,
		"route=dump day=7 item=wood recovery actual=%d expected=>%d trace=%s" % [
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
		"route=dump day=7 item=wood recovery trend actual=%s expected=increase" % [prices]
	)
	print("ECONOMY_SIM dumping item=wood prices=%s" % [prices])
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
			int(result.late_profit) <= maxi(int(result.early_profit), 0),
			"route=arbitrage_bot day=28 recipe=%s growth actual=%d expected=<=%d" % [
				str(recipe.id), int(result.late_profit), int(result.early_profit),
			]
		)
		assertions.truthy(
			int(result.total_profit) <= 28 * int(STAGE_INCOME_LIMITS.late.y),
			"route=arbitrage_bot day=28 recipe=%s profit actual=%d expected=<=%d" % [
				str(recipe.id), int(result.total_profit), 28 * int(STAGE_INCOME_LIMITS.late.y),
			]
		)
	assertions.truthy(
		checked >= 10,
		"route=instant_recipe day=0 coverage actual=%d expected=>=10" % checked
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
	var daily_capacity := maxi(1, int(1440 / int(recipe.duration_minutes)))
	var total_profit := 0
	var early_profit := 0
	var late_profit := 0
	var batches := 0
	var daily_profits: Array[int] = []
	for day in range(1, SIMULATION_DAYS + 1):
		var day_profit := 0
		for _batch in range(daily_capacity):
			var input_cost := 0
			var can_trade := true
			for item_id_value in (recipe.inputs as Dictionary).keys():
				var item_id := str(item_id_value)
				var quantity := int(recipe.inputs[item_id])
				if not market.can_buy(item_id, quantity):
					can_trade = false
					break
				input_cost += market.quote_buy(item_id, quantity)
			if not can_trade:
				break
			var output_revenue := 0
			for item_id_value in (recipe.outputs as Dictionary).keys():
				var item_id := str(item_id_value)
				output_revenue += market.quote_sell(item_id, int(recipe.outputs[item_id]))
			for item_id_value in (recipe.inputs as Dictionary).keys():
				market.commit_buy(str(item_id_value), int(recipe.inputs[item_id_value]))
			for item_id_value in (recipe.outputs as Dictionary).keys():
				market.commit_sell(str(item_id_value), int(recipe.outputs[item_id_value]))
			day_profit += output_revenue - input_cost
			batches += 1
		total_profit += day_profit
		daily_profits.append(day_profit)
		if day <= 7:
			early_profit += day_profit
		elif day >= 22:
			late_profit += day_profit
		market.settle_day(day)
	market.free()
	return {
		"total_profit": total_profit,
		"early_profit": early_profit,
		"late_profit": late_profit,
		"batches": batches,
		"capacity": daily_capacity * SIMULATION_DAYS,
		"daily_profits": daily_profits,
	}


func _sum_ints(values: Array) -> int:
	var total := 0
	for value in values:
		total += int(value)
	return total


func _test_recipe_value_ladders(assertions: TestAssert) -> void:
	var initial_ids := [
		"plank", "rope", "charcoal", "stone_brick", "brick", "glass",
		"copper_ingot", "iron_ingot", "steel", "cloth", "flour", "animal_feed",
	]
	var food_ids := [
		"sunflower_oil", "fruit_jam", "pickles", "tomato_sauce",
		"fruit_juice", "bread", "honey_cake",
	]
	var craft_ids := ["farm_tools", "bouquet"]
	for recipe_id in initial_ids:
		_assert_recipe_ratio(assertions, recipe_id, 1.20, 1.40)
	for recipe_id in food_ids:
		_assert_recipe_ratio(assertions, recipe_id, 1.40, 1.70)
	for recipe_id in craft_ids:
		_assert_recipe_ratio(assertions, recipe_id, 1.60, 2.00)
	_assert_recipe_ratio(assertions, "jewelry", 2.00, 2.20)


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
