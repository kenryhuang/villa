extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomyStateScript = preload("res://scripts/data/npc_economy_state.gd")
const NpcEconomySystemScript = preload("res://scripts/systems/npc_economy_system.gd")
const NotificationSystemScript = preload("res://scripts/systems/economy_notification_system.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")


class FailingPublicationMarket:
	extends MarketSystemScript

	var fail_next_finalize := false
	var fail_next_dispatch := false

	func finalize_sealed_publication(publication: Variant) -> RefCounted:
		if fail_next_finalize:
			fail_next_finalize = false
			return null
		return super.finalize_sealed_publication(publication)

	func dispatch_finalized_publication(batch: Variant) -> bool:
		if fail_next_dispatch:
			fail_next_dispatch = false
			return false
		return super.dispatch_finalized_publication(batch)


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_state_contract_is_strict_and_atomic(assertions)
	_test_woodworker_uses_finite_market_and_protects_reserves(assertions)
	_test_failed_trades_have_no_partial_mutations(assertions)
	_test_unmet_essential_blocks_later_production_spending(assertions)
	_test_unmet_reserve_blocks_excess_sale_and_investment(assertions)
	_test_sale_floor_protects_overlapping_reserve(assertions)
	_test_population_groups_add_tagged_factor_demand(assertions)
	_test_third_zero_stock_day_imports_essentials_only(assertions, tree)
	_test_notification_day_limit_keeps_departure(assertions, tree)
	_test_max_day_import_schedules_no_overflow_departure(assertions)
	_test_day_cursor_and_snapshot_are_atomic(assertions)
	_test_registered_profiles_and_determinism(assertions)
	_test_default_crafted_sale_targets_trade_on_finite_market(assertions)
	_test_npc_trade_publication_failures_are_atomic(assertions, tree)
	_test_npc_trade_dispatch_preserves_event_bus_state(assertions, tree)
	_test_emergency_import_publication_failures_are_atomic(assertions, tree)


func _test_npc_trade_publication_failures_are_atomic(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var market := FailingPublicationMarket.new()
	var system := NpcEconomySystemScript.new()
	tree.root.add_child(market)
	tree.root.add_child(system)
	assertions.truthy(market.configure([
		_definition("wood", 10, 20, 20, 20, "essential", "material"),
		_definition("plank", 20, 5, 10, 10, "industrial", "processed_material"),
	]), "NPC publication failure market configures")
	assertions.truthy(system.configure(market, [_woodworker_profile()], []), "NPC publication failure system configures")
	var state = system.get_npc_state("woodworker")
	var event_bus := tree.root.get_node("EventBus")
	var market_events: Array[Dictionary] = []
	var on_market := func(item_id: String, stock: int) -> void:
		market_events.append({"item_id": item_id, "stock": stock})
	event_bus.market_stock_changed.connect(on_market)

	for failure in ["buy_finalize", "buy_dispatch", "sell_finalize", "sell_dispatch"]:
		state.inventory = {"plank": 2} if failure.begins_with("sell") else {}
		state.gold = 300
		var npc_before := state.to_dict()
		var market_before := market.to_dict()
		market_events.clear()
		market.fail_next_finalize = failure.ends_with("finalize")
		market.fail_next_dispatch = failure.ends_with("dispatch")
		var succeeded := (
			bool(system.call("_sell_bundle", state, {"plank": 1}))
			if failure.begins_with("sell")
			else bool(system.call("_buy_bundle", state, {"wood": 1}))
		)
		assertions.truthy(not succeeded, failure + " is reported")
		assertions.equal(state.to_dict(), npc_before, failure + " restores NPC exactly")
		assertions.equal(market.to_dict(), market_before, failure + " restores Market exactly")
		assertions.equal(market_events, [], failure + " emits no EventBus notification")
		var probe: Variant = market.begin_atomic_transaction()
		assertions.truthy(probe != null, failure + " releases Market transaction lock")
		if probe != null:
			market.rollback_atomic_transaction(probe)

	event_bus.market_stock_changed.disconnect(on_market)
	system.free()
	market.free()


func _test_npc_trade_dispatch_preserves_event_bus_state(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var market := MarketSystemScript.new()
	var system := NpcEconomySystemScript.new()
	tree.root.add_child(market)
	tree.root.add_child(system)
	market.configure([
		_definition("wood", 10, 20, 20, 20, "essential", "material"),
		_definition("plank", 20, 5, 10, 10, "industrial", "processed_material"),
	])
	system.configure(market, [_woodworker_profile()], [])
	var state = system.get_npc_state("woodworker")
	var event_bus := tree.root.get_node("EventBus")
	var local_events: Array[int] = []
	var bus_events: Array[int] = []
	var on_local := func(_item_id: String, stock: int) -> void:
		local_events.append(stock)
		event_bus.set_block_signals(true)
	var on_bus := func(_item_id: String, stock: int) -> void:
		bus_events.append(stock)
	market.market_stock_changed.connect(on_local)
	event_bus.market_stock_changed.connect(on_bus)

	assertions.truthy(
		bool(system.call("_buy_bundle", state, {"wood": 1})),
		"NPC immediate buy dispatches finalized transaction"
	)
	assertions.equal(local_events, [19], "NPC Market local notification emits once")
	assertions.equal(bus_events, [19], "NPC Market bus notification survives local reblock once")
	assertions.truthy(not event_bus.is_blocking_signals(), "NPC dispatch restores initially unblocked EventBus")

	local_events.clear()
	bus_events.clear()
	event_bus.set_block_signals(true)
	assertions.truthy(
		bool(system.call("_sell_bundle", state, {"wood": 1})),
		"NPC immediate sale dispatches while EventBus was blocked"
	)
	assertions.equal(local_events, [20], "blocked NPC sale local notification emits once")
	assertions.equal(bus_events, [20], "blocked NPC sale bus notification emits once")
	assertions.truthy(event_bus.is_blocking_signals(), "NPC dispatch restores initially blocked EventBus")
	event_bus.set_block_signals(false)
	market.market_stock_changed.disconnect(on_local)
	event_bus.market_stock_changed.disconnect(on_bus)
	system.free()
	market.free()


func _test_emergency_import_publication_failures_are_atomic(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var market := FailingPublicationMarket.new()
	var system := NpcEconomySystemScript.new()
	tree.root.add_child(market)
	tree.root.add_child(system)
	assertions.truthy(market.configure([
		_definition("wood", 10, 0, 12, 4, "essential", "material"),
	]), "failed import market configures")
	assertions.truthy(system.configure(market, [{
		"id": "lao_li", "display_name": "老李", "gold": 1000,
		"inventory": {}, "essential_targets": {}, "reserve_targets": {},
		"production_recipes": [], "sale_targets": {},
		"investment_gold_threshold": 2000, "import_buffer": true,
	}], []), "failed import NPC fixture configures")
	var event_bus := tree.root.get_node("EventBus")
	var caravan_events: Array[Dictionary] = []
	var on_caravan := func(
		caravan_id: String,
		item_id: String,
		quantity: int,
		total_day: int,
		arrived: bool
	) -> void:
		caravan_events.append({
			"caravan_id": caravan_id,
			"item_id": item_id,
			"quantity": quantity,
			"total_day": total_day,
			"arrived": arrived,
		})
	event_bus.market_caravan_changed.connect(on_caravan)

	for failure in ["finalize", "dispatch"]:
		var npc_before := system.to_dict()
		var market_before := market.to_dict()
		caravan_events.clear()
		market.fail_next_finalize = failure == "finalize"
		market.fail_next_dispatch = failure == "dispatch"
		assertions.truthy(
			not bool(system.call("_import_essential", "wood", 3)),
			"emergency import reports %s failure" % failure
		)
		assertions.equal(system.to_dict(), npc_before, "failed import restores NPC system for " + failure)
		assertions.equal(market.to_dict(), market_before, "failed import restores Market for " + failure)
		assertions.equal(caravan_events, [], "failed import emits no caravan event for " + failure)
		var probe: Variant = market.begin_atomic_transaction()
		assertions.truthy(probe != null, "failed import releases Market lock for " + failure)
		if probe != null:
			market.rollback_atomic_transaction(probe)

	event_bus.market_caravan_changed.disconnect(on_caravan)
	system.free()
	market.free()


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


func _test_unmet_reserve_blocks_excess_sale_and_investment(assertions: TestAssert) -> void:
	var market := MarketSystemScript.new()
	market.configure([
		_definition("bread", 30, 0, 10, 5, "essential", "product"),
		_definition("jewelry", 180, 2, 5, 2, "luxury", "crafted_good"),
	])
	var system := NpcEconomySystemScript.new()
	assertions.truthy(system.configure(market, [{
		"id": "reserve_first", "display_name": "储备优先测试", "gold": 850,
		"inventory": {"jewelry": 1}, "essential_targets": {},
		"reserve_targets": {"bread": 1}, "production_recipes": [],
		"sale_targets": {"jewelry": 0}, "investment_gold_threshold": 900,
		"import_buffer": false,
	}], []), "reserve priority fixture configures")
	var jewelry_before := market.get_item_state("jewelry")
	assertions.truthy(market.quote_sell("jewelry", 1) > 50, "luxury sale would cross investment threshold")
	assertions.truthy(system.simulate_day(1), "reserve shortage day is consumed")
	var state = system.get_npc_state("reserve_first")
	assertions.equal(state.gold, 850, "unmet reserve blocks later sale income")
	assertions.equal(state.inventory.jewelry, 1, "unmet reserve retains excess luxury item")
	assertions.equal(market.get_item_state("jewelry"), jewelry_before, "unmet reserve leaves luxury market untouched")
	assertions.truthy(not state.investment_planned, "unmet reserve blocks investment planning")
	system.free()
	market.free()


func _test_sale_floor_protects_overlapping_reserve(assertions: TestAssert) -> void:
	var market := MarketSystemScript.new()
	market.configure([
		_definition("salt", 5, 10, 20, 10, "essential", "container"),
	])
	var system := NpcEconomySystemScript.new()
	assertions.truthy(system.configure(market, [{
		"id": "salt_keeper", "display_name": "储备出售测试", "gold": 100,
		"inventory": {"salt": 8}, "essential_targets": {},
		"reserve_targets": {"salt": 8}, "production_recipes": [],
		"sale_targets": {"salt": 4}, "investment_gold_threshold": 500,
		"import_buffer": false,
	}], []), "overlapping reserve and sale fixture configures")
	var market_before := market.get_item_state("salt")
	assertions.truthy(system.simulate_day(1), "overlapping reserve day simulates")
	var state = system.get_npc_state("salt_keeper")
	assertions.equal(state.inventory.salt, 8, "sale floor never drops inventory below reserve")
	assertions.equal(state.gold, 100, "protected reserve generates no sale income")
	assertions.equal(market.get_item_state("salt"), market_before, "protected reserve does not enter market supply")
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


func _test_third_zero_stock_day_imports_essentials_only(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var market := MarketSystemScript.new()
	market.configure([
		_definition("wood", 10, 0, 12, 4, "essential", "material"),
		_definition("crystal", 50, 0, 8, 3, "rare", "rare"),
	])
	var system := NpcEconomySystemScript.new()
	var notifications := NotificationSystemScript.new()
	var importer := {
		"id": "lao_li", "display_name": "老李", "gold": 1000,
		"inventory": {}, "essential_targets": {}, "reserve_targets": {},
		"production_recipes": [], "sale_targets": {},
		"investment_gold_threshold": 2000, "import_buffer": true,
	}
	tree.root.add_child(system)
	tree.root.add_child(notifications)
	assertions.truthy(system.configure(market, [importer], []), "import NPC fixture configures")
	assertions.truthy(
		notifications.configure(tree.root.get_node("EventBus"), market),
		"caravan notifications subscribe to the real EventBus"
	)
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
	var caravan_records := notifications.get_recent()
	assertions.equal(caravan_records.size(), 1, "authoritative third-day import emits one caravan notification")
	if not caravan_records.is_empty():
		assertions.equal(str(caravan_records[0].kind), "caravan_arrived", "successful import is an arrival")
		assertions.equal(int(caravan_records[0].total_day), 3, "caravan notification keeps the import day")
		assertions.truthy(str(caravan_records[0].body).contains("wood"), "caravan notification keeps the item id")
		assertions.truthy(str(caravan_records[0].body).contains("×4"), "caravan notification keeps the quantity")
	var after := system.to_dict()
	assertions.equal((after.get("pending_caravan_departures", []) as Array).size(), 1, "successful import persists one pending departure")
	assertions.truthy(not system.simulate_day(3), "import cannot repeat on the same day")
	assertions.equal(system.to_dict(), after, "same-day import retry changes nothing")
	assertions.equal(notifications.get_recent().size(), 1, "same-day retry emits no duplicate caravan notification")
	var saved_notifications := notifications.to_dict()
	notifications.free()
	system.free()

	var restored := NpcEconomySystemScript.new()
	var restored_notifications := NotificationSystemScript.new()
	tree.root.add_child(restored)
	tree.root.add_child(restored_notifications)
	assertions.truthy(restored.configure(market, [importer], []), "loaded caravan NPC fixture configures")
	assertions.truthy(restored.from_dict(after), "day-three pending departure restores")
	assertions.truthy(restored.sync_daily_cursor(3), "Main-style same-day cursor sync succeeds after load")
	assertions.equal(restored.to_dict(), after, "Main-style same-day cursor sync preserves restored departure")
	assertions.truthy(restored_notifications.configure(tree.root.get_node("EventBus"), market), "loaded caravan notifications configure")
	assertions.truthy(restored_notifications.from_dict(saved_notifications), "arrival notification restores without replay")
	var pending_before_invalid_day := restored.to_dict()
	assertions.truthy(not restored.simulate_day(EconomyLimitsScript.MAX_SAFE_DATE + 1), "invalid future simulation is rejected before departure consumption")
	assertions.equal(restored.to_dict(), pending_before_invalid_day, "invalid future simulation preserves pending departure")
	var reentry_results: Array[bool] = []
	var reentry_callback := func(
		_caravan_id: String,
		_item_id: String,
		_quantity: int,
		departure_day: int,
		arrived: bool
	) -> void:
		if not arrived:
			reentry_results.append(restored.simulate_day(departure_day + 1))
	var event_bus := tree.root.get_node("EventBus")
	event_bus.market_caravan_changed.connect(reentry_callback)
	assertions.truthy(restored.simulate_day(4), "day after arrival simulates")
	event_bus.market_caravan_changed.disconnect(reentry_callback)
	assertions.equal(reentry_results, [false], "departure listener cannot reenter a future simulation day")
	var after_departure := restored_notifications.get_recent()
	assertions.equal(after_departure.size(), 2, "loaded caravan departs exactly once on day four")
	if after_departure.size() == 2:
		assertions.equal(str(after_departure[0].kind), "caravan_departed", "day-four event is a departure")
		assertions.equal(int(after_departure[0].total_day), 4, "departure keeps its authoritative scheduled day")
		assertions.equal(int(after_departure[0].count), 1, "departure does not merge with arrival")
		assertions.equal(str(after_departure[1].kind), "caravan_arrived", "restored arrival remains distinct")
		assertions.equal(int(after_departure[1].count), 1, "arrival remains singular after departure")
		assertions.truthy(str(after_departure[0].body).contains("wood"), "departure keeps the imported item")
		assertions.truthy(str(after_departure[0].body).contains("×4"), "departure keeps the imported quantity")
	assertions.equal((restored.to_dict().get("pending_caravan_departures", []) as Array).size(), 0, "departure commit clears pending state")
	var departed_state := restored.to_dict()
	assertions.equal(int(departed_state.last_simulated_day), 4, "future-day reentry cannot advance the outer simulation cursor")
	assertions.truthy(restored.validate_dict(departed_state), "outer departure snapshot remains strictly valid after rejected reentry")
	assertions.truthy(not restored.simulate_day(4), "same departure day cannot simulate twice")
	assertions.equal(restored.to_dict(), departed_state, "same-day retry cannot consume or recreate departure state")
	assertions.equal(restored_notifications.get_recent().size(), 2, "same departure day emits no duplicate")
	assertions.truthy(restored.simulate_day(5), "simulation guard releases after the outer day completes")
	assertions.truthy(restored.validate_dict(restored.to_dict()), "post-guard next-day snapshot remains valid")
	restored_notifications.free()
	restored.free()
	market.free()


func _test_notification_day_limit_keeps_departure(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	const LEGACY_NOTIFICATION_LIMIT := 2147483647
	var market := MarketSystemScript.new()
	market.configure([_definition("wood", 10, 0, 12, 4, "essential", "material")])
	var importer := {
		"id": "lao_li", "display_name": "老李", "gold": 1000,
		"inventory": {}, "essential_targets": {}, "reserve_targets": {},
		"production_recipes": [], "sale_targets": {},
		"investment_gold_threshold": 2000, "import_buffer": true,
	}
	var system := NpcEconomySystemScript.new()
	var notifications := NotificationSystemScript.new()
	tree.root.add_child(system)
	tree.root.add_child(notifications)
	assertions.truthy(system.configure(market, [importer], []), "wide-day caravan fixture configures")
	assertions.truthy(notifications.configure(tree.root.get_node("EventBus"), market), "wide-day notification fixture configures")
	var before_arrival := system.to_dict()
	before_arrival["last_simulated_day"] = LEGACY_NOTIFICATION_LIMIT - 1
	before_arrival["essential_zero_streaks"]["wood"] = 2
	for state_value in before_arrival.npc_states:
		state_value["last_simulated_day"] = LEGACY_NOTIFICATION_LIMIT - 1
	assertions.truthy(system.from_dict(before_arrival), "wide-day caravan cursor restores")
	assertions.truthy(system.simulate_day(LEGACY_NOTIFICATION_LIMIT), "last legacy notification day emits arrival")
	assertions.truthy(system.simulate_day(LEGACY_NOTIFICATION_LIMIT + 1), "next safe day emits departure")
	var records := notifications.get_recent()
	assertions.equal(records.size(), 2, "notification date range retains arrival and next-day departure")
	if records.size() == 2:
		assertions.equal(str(records[0].kind), "caravan_departed", "wide-day second record is departure")
		assertions.equal(int(records[0].total_day), LEGACY_NOTIFICATION_LIMIT + 1, "wide-day departure keeps D plus one")
		assertions.equal(str(records[1].kind), "caravan_arrived", "wide-day first record is arrival")
	notifications.free()
	system.free()
	market.free()


func _test_max_day_import_schedules_no_overflow_departure(assertions: TestAssert) -> void:
	var market := MarketSystemScript.new()
	market.configure([_definition("wood", 10, 0, 12, 4, "essential", "material")])
	var importer := {
		"id": "lao_li", "display_name": "老李", "gold": 1000,
		"inventory": {}, "essential_targets": {}, "reserve_targets": {},
		"production_recipes": [], "sale_targets": {},
		"investment_gold_threshold": 2000, "import_buffer": true,
	}
	var system := NpcEconomySystemScript.new()
	assertions.truthy(system.configure(market, [importer], []), "max-day caravan fixture configures")
	var near_limit := system.to_dict()
	near_limit["last_simulated_day"] = EconomyLimitsScript.MAX_SAFE_DATE - 1
	near_limit["essential_zero_streaks"]["wood"] = 2
	for state_value in near_limit.npc_states:
		state_value["last_simulated_day"] = EconomyLimitsScript.MAX_SAFE_DATE - 1
	assertions.truthy(system.from_dict(near_limit), "near-limit caravan state restores")
	assertions.truthy(system.simulate_day(EconomyLimitsScript.MAX_SAFE_DATE), "maximum safe day import simulates")
	assertions.equal(market.get_stock("wood"), 4, "maximum safe day can still import")
	assertions.equal((system.to_dict().get("pending_caravan_departures", []) as Array).size(), 0, "maximum day creates no overflowing departure")
	var at_limit := system.to_dict()
	assertions.truthy(not system.simulate_day(EconomyLimitsScript.MAX_SAFE_DATE + 1), "unsafe future day is rejected")
	assertions.equal(system.to_dict(), at_limit, "unsafe future day cannot consume departure state")
	system.free()
	market.free()


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
	var legacy := snapshot.duplicate(true)
	legacy.erase("pending_caravan_departures")
	assertions.truthy(restored.from_dict(legacy), "legacy NPC snapshot without caravan departure state restores")
	assertions.equal(restored.to_dict().get("pending_caravan_departures", null), [], "legacy NPC snapshot defaults pending departures empty")
	assertions.truthy(restored.from_dict(snapshot), "strict snapshot restores after legacy compatibility check")
	var malformed := snapshot.duplicate(true)
	malformed.npc_states[0].last_simulated_day = 4.5
	var before := restored.to_dict()
	assertions.truthy(not restored.from_dict(malformed), "fractional nested cursor is rejected")
	assertions.equal(restored.to_dict(), before, "failed NPC system restore is atomic")
	var incoherent := snapshot.duplicate(true)
	incoherent.npc_states[0].last_simulated_day = 4
	assertions.truthy(not restored.from_dict(incoherent), "NPC cursor must match system cursor")
	assertions.equal(restored.to_dict(), before, "incoherent cursor restore is atomic")
	var invalid_pending := snapshot.duplicate(true)
	invalid_pending["pending_caravan_departures"] = [{
		"caravan_id": "lao_li_emergency_import",
		"item_id": "wood",
		"quantity": 1,
		"departure_day": int(snapshot.last_simulated_day),
	}]
	assertions.truthy(not restored.from_dict(invalid_pending), "pending departure must be after the saved cursor")
	assertions.equal(restored.to_dict(), before, "invalid pending departure restore is atomic")
	invalid_pending.pending_caravan_departures[0].departure_day = int(snapshot.last_simulated_day) + 1
	invalid_pending.pending_caravan_departures[0].item_id = "unknown_item"
	assertions.truthy(not restored.from_dict(invalid_pending), "pending departure rejects unknown items")
	invalid_pending.pending_caravan_departures[0].item_id = "wood"
	invalid_pending.pending_caravan_departures[0].quantity = 0
	assertions.truthy(not restored.from_dict(invalid_pending), "pending departure rejects zero quantity")
	invalid_pending.pending_caravan_departures[0].quantity = 1
	invalid_pending.pending_caravan_departures.append(invalid_pending.pending_caravan_departures[0].duplicate(true))
	assertions.truthy(not restored.from_dict(invalid_pending), "pending departure rejects duplicate occurrence keys")
	market.free()
	system.free()
	restored.free()


func _test_registered_profiles_and_determinism(assertions: TestAssert) -> void:
	var profiles := GameDataScript.get_npc_economy_profiles()
	var expected := {
		"farmer_ahe": "阿禾",
		"lao_li": "老李",
		"xiao_hua": "小花",
		"tiejiang_zhang": "铁匠张",
		"afu_shui": "阿水",
		"xuezhe_lin": "学者林",
	}
	assertions.equal(profiles.size(), expected.size(), "six important economy profiles are registered")
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
