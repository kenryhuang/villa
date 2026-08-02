extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomyStateScript = preload("res://scripts/data/npc_economy_state.gd")
const NpcEconomySystemScript = preload("res://scripts/systems/npc_economy_system.gd")


func run(assertions: TestAssert) -> void:
	_test_state_contract_is_strict_and_atomic(assertions)
	_test_woodworker_uses_finite_market_and_protects_reserves(assertions)
	_test_failed_trades_have_no_partial_mutations(assertions)
	_test_unmet_essential_blocks_later_production_spending(assertions)
	_test_population_groups_add_tagged_factor_demand(assertions)
	_test_third_zero_stock_day_imports_essentials_only(assertions)
	_test_day_cursor_and_snapshot_are_atomic(assertions)
	_test_registered_profiles_and_determinism(assertions)
	_test_default_crafted_sale_targets_trade_on_finite_market(assertions)


func _test_state_contract_is_strict_and_atomic(assertions: TestAssert) -> void:
	var state := NpcEconomyStateScript.new()
	var snapshot := {
		"npc_id": "woodworker",
		"gold": 240.0,
		"inventory": {"wood": 7.0, "plank": 2},
		"reserve_targets": {"wood": 5.0},
		"production_recipes": ["plank"],
		"sale_targets": {"plank": 1.0},
		"last_simulated_day": 4.0,
		"investment_planned": true,
	}
	assertions.truthy(state.from_dict(snapshot), "NPC state accepts JSON integral numbers")
	assertions.equal(state.to_dict(), {
		"npc_id": "woodworker",
		"gold": 240,
		"inventory": {"wood": 7, "plank": 2},
		"reserve_targets": {"wood": 5},
		"production_recipes": ["plank"],
		"sale_targets": {"plank": 1},
		"last_simulated_day": 4,
		"investment_planned": true,
	}, "NPC state normalizes and round trips its complete contract")
	var exposed := state.to_dict()
	exposed.inventory.wood = 999
	assertions.equal(state.inventory.wood, 7, "NPC state serialization is a deep copy")

	var before := state.to_dict()
	var malformed_cases: Array[Dictionary] = []
	var fractional := before.duplicate(true)
	fractional.gold = 1.5
	malformed_cases.append(fractional)
	var unknown_item := before.duplicate(true)
	unknown_item.inventory = {"not_an_item": 1}
	malformed_cases.append(unknown_item)
	var unknown_recipe := before.duplicate(true)
	unknown_recipe.production_recipes = ["not_a_recipe"]
	malformed_cases.append(unknown_recipe)
	var negative := before.duplicate(true)
	negative.inventory.wood = -1
	malformed_cases.append(negative)
	var wrong_type := before.duplicate(true)
	wrong_type.sale_targets = []
	malformed_cases.append(wrong_type)
	var missing := before.duplicate(true)
	missing.erase("npc_id")
	malformed_cases.append(missing)
	for malformed in malformed_cases:
		assertions.truthy(not state.from_dict(malformed), "malformed NPC state is rejected")
		assertions.equal(state.to_dict(), before, "failed NPC state restore is atomic")


func _test_woodworker_uses_finite_market_and_protects_reserves(assertions: TestAssert) -> void:
	var market := MarketSystemScript.new()
	assertions.truthy(market.configure([
		_definition("wood", 10, 20, 20, 20, "essential", "material"),
		_definition("plank", 20, 5, 10, 10, "industrial", "processed_material"),
	]), "woodworker market configures")
	var system := NpcEconomySystemScript.new()
	assertions.truthy(system.configure(market, [_woodworker_profile()], []), "woodworker configures")
	var state = system.get_npc_state("woodworker")
	var expected_buy := market.quote_buy("wood", 3)
	assertions.truthy(system.simulate_day(1), "woodworker simulates first day")
	assertions.equal(state.inventory.get("wood"), 5, "woodworker buys exactly the reserve deficit")
	assertions.equal(state.inventory.get("plank", 0), 0, "protected reserve is not consumed for production")
	assertions.equal(state.gold, 300 - expected_buy, "NPC buy uses the market quote")
	assertions.equal(market.get_stock("wood"), 17, "NPC buy consumes finite market stock")
	assertions.equal(market.get_item_state("wood").demand, 3, "NPC buy records demand")

	state.inventory.wood = 7
	var expected_sale := market.quote_sell("plank", 1)
	assertions.truthy(system.simulate_day(2), "woodworker simulates a later day")
	assertions.equal(state.inventory.wood, 5, "production retains the wood reserve")
	assertions.equal(state.inventory.get("plank", 0), 0, "excess plank is sold after production")
	assertions.equal(state.gold, 300 - expected_buy + expected_sale, "NPC sale uses the market quote")
	assertions.equal(market.get_stock("plank"), 6, "NPC sale adds finite market stock")
	assertions.equal(market.get_item_state("plank").supply, 1, "NPC sale records supply")
	market.free()
	system.free()


func _test_failed_trades_have_no_partial_mutations(assertions: TestAssert) -> void:
	var stock_limited_market := MarketSystemScript.new()
	stock_limited_market.configure([
		_definition("wood", 10, 2, 10, 10, "essential", "material"),
		_definition("plank", 20, 0, 10, 10, "industrial", "processed_material"),
	])
	var stock_limited := NpcEconomySystemScript.new()
	var profile := _woodworker_profile()
	profile.inventory = {"wood": 0}
	stock_limited.configure(stock_limited_market, [profile], [])
	var before_market := stock_limited_market.to_dict()
	var before_state := stock_limited.get_npc_state("woodworker").to_dict()
	stock_limited.simulate_day(1)
	assertions.equal(stock_limited_market.to_dict(), before_market, "insufficient stock causes no partial market buy")
	assertions.equal(stock_limited.get_npc_state("woodworker").to_dict().inventory, before_state.inventory, "insufficient stock causes no partial NPC inventory")
	assertions.equal(stock_limited.get_npc_state("woodworker").gold, before_state.gold, "insufficient stock causes no wallet mutation")

	var gold_limited_market := MarketSystemScript.new()
	gold_limited_market.configure([
		_definition("wood", 10, 10, 10, 10, "essential", "material"),
		_definition("plank", 20, 0, 10, 10, "industrial", "processed_material"),
	])
	var gold_limited := NpcEconomySystemScript.new()
	profile.gold = 1
	gold_limited.configure(gold_limited_market, [profile], [])
	var gold_market_before := gold_limited_market.to_dict()
	gold_limited.simulate_day(1)
	assertions.equal(gold_limited_market.to_dict(), gold_market_before, "insufficient gold causes no partial market buy")
	assertions.equal(gold_limited.get_npc_state("woodworker").inventory.wood, 0, "insufficient gold adds no inventory")
	assertions.equal(gold_limited.get_npc_state("woodworker").gold, 1, "insufficient gold leaves wallet unchanged")

	var recipe_market := MarketSystemScript.new()
	recipe_market.configure([
		_definition("iron_ingot", 20, 2, 10, 10, "industrial", "processed_material"),
		_definition("plank", 10, 0, 10, 10, "industrial", "processed_material"),
		_definition("farm_tools", 60, 0, 5, 5, "crafted", "product"),
	])
	var recipe_system := NpcEconomySystemScript.new()
	recipe_system.configure(recipe_market, [{
		"id": "toolmaker", "display_name": "工具匠", "gold": 500,
		"inventory": {}, "essential_targets": {}, "reserve_targets": {},
		"production_recipes": ["farm_tools"], "sale_targets": {"farm_tools": 0},
		"investment_gold_threshold": 900, "import_buffer": false,
	}], [])
	var recipe_market_before := recipe_market.to_dict()
	recipe_system.simulate_day(1)
	assertions.equal(recipe_market.to_dict(), recipe_market_before, "missing second recipe input rolls back the whole purchase bundle")
	assertions.equal(recipe_system.get_npc_state("toolmaker").inventory, {}, "failed recipe bundle adds no first input")
	assertions.equal(recipe_system.get_npc_state("toolmaker").gold, 500, "failed recipe bundle charges no gold")
	stock_limited.free()
	stock_limited_market.free()
	gold_limited.free()
	gold_limited_market.free()
	recipe_system.free()
	recipe_market.free()


func _test_unmet_essential_blocks_later_production_spending(assertions: TestAssert) -> void:
	var market := MarketSystemScript.new()
	market.configure([
		_definition("bread", 30, 0, 10, 5, "essential", "product"),
		_definition("iron_ingot", 20, 5, 10, 10, "industrial", "processed_material"),
		_definition("plank", 10, 5, 10, 10, "industrial", "processed_material"),
		_definition("farm_tools", 90, 1, 5, 4, "crafted", "crafted_good"),
	])
	var system := NpcEconomySystemScript.new()
	assertions.truthy(system.configure(market, [{
		"id": "essential_first", "display_name": "优先级测试", "gold": 500,
		"inventory": {}, "essential_targets": {"bread": 1}, "reserve_targets": {},
		"production_recipes": ["farm_tools"], "sale_targets": {"farm_tools": 0},
		"investment_gold_threshold": 900, "import_buffer": false,
	}], []), "essential priority fixture configures")
	var production_market_before := {
		"iron_ingot": market.get_item_state("iron_ingot"),
		"plank": market.get_item_state("plank"),
		"farm_tools": market.get_item_state("farm_tools"),
	}
	assertions.truthy(system.simulate_day(1), "essential shortage day is consumed")
	var state = system.get_npc_state("essential_first")
	assertions.equal(state.gold, 500, "failed essential purchase prevents later spending")
	assertions.equal(state.inventory, {}, "failed essential purchase prevents inputs and production")
	assertions.equal(market.get_item_state("iron_ingot"), production_market_before.iron_ingot, "essential shortage leaves ingot market untouched")
	assertions.equal(market.get_item_state("plank"), production_market_before.plank, "essential shortage leaves plank market untouched")
	assertions.equal(market.get_item_state("farm_tools"), production_market_before.farm_tools, "essential shortage leaves output market untouched")
	system.free()
	market.free()


func _test_population_groups_add_tagged_factor_demand(assertions: TestAssert) -> void:
	var market := MarketSystemScript.new()
	market.configure(GameDataScript.get_market_items())
	var system := NpcEconomySystemScript.new()
	system.configure(market, [], GameDataScript.get_population_demand_profiles())
	assertions.truthy(system.simulate_day(1, {
		"residents": 1.5,
		"builders": 2.0,
		"artisans": 0.5,
		"tourists": 2.0,
	}, {"tourists": 1.5}), "population demand accepts explicit factors")
	assertions.equal(market.get_item_state("grain").demand, 6, "residents add season-scaled food demand")
	assertions.equal(market.get_item_state("plank").demand, 6, "builders add plank demand")
	assertions.equal(market.get_item_state("brick").demand, 4, "builders add brick demand")
	assertions.equal(market.get_item_state("iron_ingot").demand, 1, "artisans add ingot demand")
	assertions.equal(market.get_item_state("honey_cake").demand, 3, "tourists add clamped luxury demand")
	var tags := system.get_demand_tags()
	for group_id in ["residents", "builders", "artisans", "tourists"]:
		assertions.truthy(tags.has(group_id), "%s has a human-readable demand tag" % group_id)
		assertions.truthy(not str(tags[group_id]).is_empty(), "%s demand tag is not empty" % group_id)
	market.free()
	system.free()


func _test_third_zero_stock_day_imports_essentials_only(assertions: TestAssert) -> void:
	var market := MarketSystemScript.new()
	market.configure([
		_definition("wood", 10, 0, 12, 4, "essential", "material"),
		_definition("crystal", 50, 0, 8, 3, "rare", "rare"),
	])
	var system := NpcEconomySystemScript.new()
	var importer := {
		"id": "lao_li", "display_name": "老李", "gold": 1000,
		"inventory": {}, "essential_targets": {}, "reserve_targets": {},
		"production_recipes": [], "sale_targets": {},
		"investment_gold_threshold": 2000, "import_buffer": true,
	}
	system.configure(market, [importer], [])
	var start_gold := system.get_npc_state("lao_li").gold
	assertions.truthy(system.simulate_day(1), "first shortage day simulates")
	assertions.truthy(system.simulate_day(2), "second shortage day simulates")
	assertions.equal(market.get_stock("wood"), 0, "essential remains empty before third day")
	assertions.truthy(system.simulate_day(3), "third shortage day simulates")
	assertions.equal(market.get_stock("wood"), 4, "third day imports capped essential quantity")
	assertions.equal(market.get_item_state("wood").supply, 4, "import records coherent market supply")
	assertions.truthy(system.get_npc_state("lao_li").gold < start_gold, "import charges Lao Li an elevated cost")
	assertions.equal(market.get_stock("crystal"), 0, "rare goods are never imported")
	assertions.equal(system.get_essential_zero_streaks().get("wood"), 0, "successful import resets shortage streak")
	var after := system.to_dict()
	assertions.truthy(not system.simulate_day(3), "import cannot repeat on the same day")
	assertions.equal(system.to_dict(), after, "same-day import retry changes nothing")
	market.free()
	system.free()


func _test_day_cursor_and_snapshot_are_atomic(assertions: TestAssert) -> void:
	var market := MarketSystemScript.new()
	market.configure(GameDataScript.get_market_items())
	var system := NpcEconomySystemScript.new()
	system.configure(market, GameDataScript.get_npc_economy_profiles(), GameDataScript.get_population_demand_profiles())
	system.simulate_day(5)
	var snapshot := system.to_dict()
	assertions.truthy(not system.simulate_day(5), "same NPC day is rejected")
	assertions.truthy(not system.simulate_day(4), "earlier NPC day is rejected")
	assertions.equal(system.to_dict(), snapshot, "rejected NPC day preserves all state")
	var restored := NpcEconomySystemScript.new()
	restored.configure(market, GameDataScript.get_npc_economy_profiles(), GameDataScript.get_population_demand_profiles())
	assertions.truthy(restored.from_dict(snapshot), "valid NPC system snapshot restores")
	assertions.equal(restored.to_dict(), snapshot, "NPC system snapshot round trips exactly")
	var malformed := snapshot.duplicate(true)
	malformed.npc_states[0].last_simulated_day = 4.5
	var before := restored.to_dict()
	assertions.truthy(not restored.from_dict(malformed), "fractional nested cursor is rejected")
	assertions.equal(restored.to_dict(), before, "failed NPC system restore is atomic")
	var incoherent := snapshot.duplicate(true)
	incoherent.npc_states[0].last_simulated_day = 4
	assertions.truthy(not restored.from_dict(incoherent), "NPC cursor must match system cursor")
	assertions.equal(restored.to_dict(), before, "incoherent cursor restore is atomic")
	market.free()
	system.free()
	restored.free()


func _test_registered_profiles_and_determinism(assertions: TestAssert) -> void:
	var profiles := GameDataScript.get_npc_economy_profiles()
	var expected := {
		"lao_li": "老李",
		"xiao_hua": "小花",
		"tiejiang_zhang": "铁匠张",
		"afu_shui": "阿水",
		"xuezhe_lin": "学者林",
	}
	assertions.equal(profiles.size(), expected.size(), "five important economy profiles are registered")
	for profile in profiles:
		assertions.equal(profile.display_name, expected.get(profile.id), "%s uses stable ASCII id and Chinese display name" % profile.id)

	var market_a := MarketSystemScript.new()
	var market_b := MarketSystemScript.new()
	market_a.configure(GameDataScript.get_market_items())
	market_b.configure(GameDataScript.get_market_items())
	var system_a := NpcEconomySystemScript.new()
	var system_b := NpcEconomySystemScript.new()
	system_a.configure(market_a, profiles, GameDataScript.get_population_demand_profiles())
	system_b.configure(market_b, profiles, GameDataScript.get_population_demand_profiles())
	for day in range(1, 4):
		system_a.simulate_day(day, {"tourists": 1.25}, {"builders": 1.5})
		system_b.simulate_day(day, {"tourists": 1.25}, {"builders": 1.5})
	assertions.equal(system_a.to_dict(), system_b.to_dict(), "NPC simulation is deterministic without random state")
	assertions.equal(market_a.to_dict(), market_b.to_dict(), "deterministic NPC simulation writes identical market ledgers")
	market_a.free()
	market_b.free()
	system_a.free()
	system_b.free()


func _test_default_crafted_sale_targets_trade_on_finite_market(assertions: TestAssert) -> void:
	var market := MarketSystemScript.new()
	assertions.truthy(market.configure(GameDataScript.get_market_items()), "default crafted-sale market configures")
	var system := NpcEconomySystemScript.new()
	assertions.truthy(system.configure(
		market,
		GameDataScript.get_npc_economy_profiles(),
		[]
	), "default crafted-sale NPCs configure")
	var sales := {
		"xiao_hua": "bouquet",
		"tiejiang_zhang": "farm_tools",
		"xuezhe_lin": "jewelry",
	}
	var stocks_before: Dictionary = {}
	for npc_id in sales:
		var item_id: String = sales[npc_id]
		var state = system.get_npc_state(npc_id)
		state.production_recipes.clear()
		state.inventory[item_id] = int(state.sale_targets[item_id]) + 1
		stocks_before[item_id] = market.get_stock(item_id)
		assertions.truthy(market.quote_sell(item_id, 1) > 0, "%s has a valid shared market quote" % item_id)
	assertions.truthy(system.simulate_day(1), "default crafted excess sales simulate")
	for npc_id in sales:
		var item_id: String = sales[npc_id]
		assertions.equal(market.get_stock(item_id), int(stocks_before[item_id]) + 1, "%s sale adds finite stock" % item_id)
		assertions.equal(market.get_item_state(item_id).supply, 1, "%s sale records shared market supply" % item_id)
		assertions.equal(
			system.get_npc_state(npc_id).inventory[item_id],
			system.get_npc_state(npc_id).sale_targets[item_id],
			"%s sale retains its target" % item_id
		)
	system.free()
	market.free()


func _woodworker_profile() -> Dictionary:
	return {
		"id": "woodworker",
		"display_name": "木匠",
		"gold": 300,
		"inventory": {"wood": 2},
		"essential_targets": {},
		"reserve_targets": {"wood": 5},
		"production_recipes": ["plank"],
		"sale_targets": {"plank": 0},
		"investment_gold_threshold": 500,
		"import_buffer": false,
	}


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
