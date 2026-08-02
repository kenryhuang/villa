extends RefCounted

const DailySimulationSystem = preload("res://scripts/systems/daily_simulation_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomySystemScript = preload("res://scripts/systems/npc_economy_system.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const ProducerStateScript = preload("res://scripts/data/producer_state.gd")
const TEST_SAVE_DIR := "user://villa_test_saves/economy_task_5/"
const TEST_SLOT := 3
const BAD_SLOT := 4


class RejectingMarketDouble:
	extends MarketSystemScript

	func configure(_definitions: Array) -> bool:
		return false


class LoadObserver:
	extends RefCounted
	var calls := 0
	var adopted_slot := -1
	var manager: Node

	func _init(source: Node) -> void:
		manager = source

	func on_load_completed(slot: int) -> void:
		calls += 1
		adopted_slot = int(manager.get("current_slot"))
		assert(slot == adopted_slot)


class SettlementObserver:
	extends RefCounted
	var calls := 0

	func on_market_settled(_total_day: int) -> void:
		calls += 1


class RejectingResourceWorld:
	extends RefCounted
	var records: Array[Dictionary] = [{"resource_id": "rock", "hits_remaining": 3}]
	var reject_next_restore := false

	func to_resource_dicts() -> Array[Dictionary]:
		return records.duplicate(true)

	func validate_resource_dicts(value: Variant, _loaded_day: int) -> bool:
		return value is Array

	func restore_resource_dicts(value: Variant, _loaded_day: int) -> bool:
		if reject_next_restore:
			reject_next_restore = false
			return false
		records.assign((value as Array).duplicate(true))
		return true

	func initialize_resources_at_day(_day: int) -> void:
		pass


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_save_round_trip_and_legacy_load(assertions, tree)
	_test_npc_economy_round_trip_atomic_rejection_and_legacy_backfill(assertions, tree)
	_test_task13_full_json_round_trip_and_starter_lifecycle(assertions, tree)
	_test_task13_legacy_iron_migration_and_missing_economy_idempotence(assertions, tree)
	_test_task13_resource_apply_failure_rolls_back_economy(assertions, tree)
	_test_task13_corrupt_producer_load_is_atomic(assertions, tree)
	_test_task13_short_building_restore_is_atomic(assertions, tree)
	_test_main_wires_economy_runtime(assertions, tree)


func _test_save_round_trip_and_legacy_load(assertions: TestAssert, tree: SceneTree) -> void:
	_cleanup()
	var market := MarketSystemScript.new()
	var daily := DailySimulationSystem.new()
	var manager := SaveManagerScript.new()
	manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(market)
	tree.root.add_child(daily)
	tree.root.add_child(manager)
	assertions.truthy(manager.configure_economy(market, daily), "save manager accepts economy dependencies")
	assertions.truthy(market.configure([_wood_definition()]), "save market fixture configures")
	assertions.truthy(market.commit_buy("wood", 3), "save fixture changes stock")
	assertions.truthy(market.settle_day(4), "save fixture changes price history")
	daily.last_simulated_day = 4
	var expected_market := market.to_dict()
	assertions.truthy(manager.save_game(TEST_SLOT), "economy state writes through public save API")
	var gathered: Dictionary = manager._gather_save_data()
	assertions.equal(gathered.get("economy_version"), 1, "save includes economy version")
	assertions.equal(gathered.get("market"), expected_market, "save includes complete market state")
	assertions.equal(gathered.get("last_simulated_day"), 4, "save includes coordinator day")

	assertions.truthy(market.commit_sell("wood", 5), "runtime market diverges after save")
	assertions.truthy(market.settle_day(5), "runtime settlement day diverges after save")
	daily.last_simulated_day = 5
	assertions.truthy(manager.load_game(TEST_SLOT), "economy state restores through public load API")
	assertions.equal(manager.current_slot, TEST_SLOT, "successful load adopts requested slot")
	assertions.equal(market.to_dict(), expected_market, "load restores stock, price, history, and ledger")
	assertions.equal(market.last_settled_day, 4, "load restores last settled day")
	assertions.equal(daily.last_simulated_day, 4, "load restores last simulated day")

	var state_before_bad_load := market.to_dict()
	var simulated_day_before_bad_load := daily.last_simulated_day
	_write_json(manager._save_path(BAD_SLOT), {
		"gold": 1,
		"economy_version": 1,
		"market": {"last_settled_day": 9, "items": {"wood": {}}},
		"last_simulated_day": 9,
	})
	var game_state := tree.root.get_node_or_null("GameState")
	var gold_before_bad_load: Variant = game_state.gold if game_state != null else null
	assertions.truthy(not manager.load_game(BAD_SLOT), "malformed economy state rejects the save")
	assertions.equal(manager.current_slot, TEST_SLOT, "failed load preserves current slot")
	assertions.equal(market.to_dict(), state_before_bad_load, "malformed economy state preserves market")
	assertions.equal(
		daily.last_simulated_day,
		simulated_day_before_bad_load,
		"malformed economy state preserves coordinator day"
	)
	if game_state != null:
		assertions.equal(game_state.gold, gold_before_bad_load, "malformed economy state applies no earlier fields")

	var mismatched_days := state_before_bad_load.duplicate(true)
	mismatched_days["last_settled_day"] = 9
	_write_json(manager._save_path(BAD_SLOT), {
		"gold": 1,
		"economy_version": 1,
		"market": mismatched_days,
		"last_simulated_day": 4,
	})
	assertions.truthy(not manager.load_game(BAD_SLOT), "mismatched economy days reject the save")
	assertions.equal(market.to_dict(), state_before_bad_load, "mismatched days preserve market")
	assertions.equal(
		daily.last_simulated_day,
		simulated_day_before_bad_load,
		"mismatched days preserve coordinator"
	)
	_write_json(manager._save_path(BAD_SLOT), {
		"gold": 1,
		"market": state_before_bad_load,
	})
	assertions.truthy(not manager.load_game(BAD_SLOT), "partial unversioned economy fields reject the save")
	assertions.equal(market.to_dict(), state_before_bad_load, "partial economy fields preserve market")
	if game_state != null:
		assertions.equal(game_state.gold, gold_before_bad_load, "partial economy fields apply no earlier fields")

	for invalid_total_days in [-1, 4.5, 5]:
		_write_json(manager._save_path(BAD_SLOT), {
			"gold": 1,
			"total_days": invalid_total_days,
			"economy_version": 1,
			"market": state_before_bad_load,
			"last_simulated_day": 4,
		})
		assertions.truthy(
			not manager.load_game(BAD_SLOT),
			"invalid versioned calendar day rejects save: %s" % invalid_total_days
		)
		assertions.equal(
			market.to_dict(),
			state_before_bad_load,
			"invalid versioned calendar preserves market: %s" % invalid_total_days
		)
		assertions.equal(
			daily.last_simulated_day,
			simulated_day_before_bad_load,
			"invalid versioned calendar preserves coordinator: %s" % invalid_total_days
		)
		if game_state != null:
			assertions.equal(
				game_state.gold,
				gold_before_bad_load,
				"invalid versioned calendar applies no earlier fields: %s" % invalid_total_days
			)

	_write_json(manager._save_path(TEST_SLOT), {"total_days": 8})
	assertions.truthy(manager.load_game(TEST_SLOT), "legacy save without economy fields loads")
	var wood_definition: Dictionary = GameDataScript.get_item("wood")
	assertions.equal(
		market.get_stock("wood"),
		int(wood_definition.get("initial_stock", 0)),
		"legacy save rebuilds market from current catalog"
	)
	assertions.equal(
		market.get_mid_price("wood"),
		int(wood_definition.get("base_price", 0)),
		"legacy save rebuilds market at base price"
	)
	assertions.equal(market.last_settled_day, 8, "legacy market starts at loaded day without settlement")
	assertions.equal(daily.last_simulated_day, 8, "legacy coordinator starts at loaded day")
	assertions.truthy(not daily.run_day(8), "loaded legacy day cannot replay")

	manager.free()
	daily.free()
	market.free()
	_cleanup()


func _test_task13_full_json_round_trip_and_starter_lifecycle(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_cleanup()
	var manager := SaveManagerScript.new()
	manager.name = "Task13RoundTripSaveManager"
	manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(manager)
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	main.load_save_on_start = false
	main.save_manager = manager
	tree.root.add_child(main)
	var game_state := tree.root.get_node_or_null("GameState")
	assertions.equal(main.inventory_system.get_item_count("grain_seed"), 12, "new game grants exactly 12 grain seeds")
	assertions.equal(main.inventory_system.get_item_count("wood"), 30, "new game grants exactly 30 wood")
	assertions.equal(main.inventory_system.get_item_count("stone"), 20, "new game grants exactly 20 stone")
	assertions.equal(main.inventory_system.get_item_count("fiber"), 10, "new game grants exactly 10 fiber")
	assertions.equal(main.inventory_system.get_item_count("iron"), 0, "new game grants no legacy debug iron")
	assertions.equal(main.inventory_system.get_item_count("glass"), 0, "new game grants no debug glass")
	assertions.equal(game_state.gold if game_state != null else -1, 150, "new game starts with exactly 150 gold")
	main._initial_game_state()
	assertions.equal(main.inventory_system.get_item_count("grain_seed"), 12, "re-entering new-game lifecycle cannot duplicate seeds")
	assertions.equal(main.inventory_system.get_item_count("wood"), 30, "re-entering new-game lifecycle cannot duplicate wood")
	assertions.equal(game_state.gold if game_state != null else -1, 150, "re-entering new-game lifecycle preserves exact gold")

	main.season_system.current_season = SeasonSystem.Season.SPRING
	main.season_system.current_day = 4
	main.season_system.total_days = 4
	main.season_system.hour = 10
	main.season_system.minute = 25
	assertions.truthy(main.market_system.commit_buy("wood", 2), "round-trip fixture records market demand")
	assertions.truthy(main.market_system.settle_day(4), "round-trip fixture creates price history")
	main.daily_simulation_system.last_simulated_day = 4
	main.npc_economy_system.sync_daily_cursor(4)
	var npc_snapshot: Dictionary = main.npc_economy_system.to_dict()
	var lao_li: Dictionary = _npc_state_record(npc_snapshot, "lao_li")
	lao_li.gold = 321
	lao_li.inventory.salt = 11
	lao_li.investment_planned = true
	assertions.truthy(main.npc_economy_system.from_dict(npc_snapshot), "round-trip fixture adopts NPC wallet, inventory, and plan")
	var contract := {
		"contract_id": "lao_li:wood:4:6",
		"npc_id": "lao_li",
		"item_id": "wood",
		"quantity_per_day": 2,
		"unit_price": 10,
		"reward_gold": 20,
		"start_day": 4,
		"end_day": 6,
		"delivered_days": [],
		"breaches": 0,
		"signed": true,
		"completed": false,
		"expired": false,
	}
	assertions.truthy(
		main.economy_system.from_dict({
			"last_processed_day": 4,
			"orders": [],
			"contracts": [contract],
		}),
		"round-trip fixture adopts a signed contract"
	)
	var workbench_location := _find_restore_location(main, "workbench")
	var workbench_record := _producer_building_record(main, workbench_location)
	assertions.equal(main.building_system.restore_buildings([workbench_record]), 1, "round-trip fixture restores queued producer")
	main.production_system.register_existing_buildings()
	var depleted_resources: Array[Dictionary] = main.world.to_resource_dicts()
	depleted_resources[0]["hits_remaining"] = 0
	depleted_resources[0]["respawn_day"] = 7
	assertions.truthy(
		main.world.restore_resource_dicts(depleted_resources, 4),
		"round-trip fixture depletes a real resource"
	)

	assertions.truthy(manager.save_game(TEST_SLOT), "Task 13 fixture writes real JSON")
	var encoded: Dictionary = _read_json(manager._save_path(TEST_SLOT))
	assertions.equal(encoded.get("economy_version"), 1, "real JSON carries economy version 1")
	assertions.equal(encoded.get("last_simulated_day"), 4, "real JSON carries last simulated day")
	assertions.equal(encoded.market.items.wood.history.size(), 2, "real JSON carries complete market history")
	assertions.equal(int(encoded.market.items.wood.stock), main.market_system.get_stock("wood"), "real JSON carries current market stock")
	assertions.equal(int(_npc_state_record(encoded.npc_economy, "lao_li").gold), 321, "real JSON carries NPC wallet")
	assertions.equal(int(_npc_state_record(encoded.npc_economy, "lao_li").inventory.salt), 11, "real JSON carries NPC inventory")
	assertions.equal(encoded.economy_state.contracts.size(), 1, "real JSON carries signed contract")
	assertions.equal(str(encoded.economy_state.contracts[0].contract_id), contract.contract_id, "real JSON preserves contract identity")
	assertions.equal(encoded.buildings[0].producer_state.jobs.size(), 1, "real JSON carries queued producer job")
	assertions.equal(int(encoded.buildings[0].producer_state.outputs.plank), 2, "real JSON carries staged producer output")
	assertions.equal(encoded.resource_nodes[0].hits_remaining, 0, "real JSON carries depleted resource")
	var expected_market: Dictionary = main.market_system.to_dict()
	var expected_npc: Dictionary = main.npc_economy_system.to_dict()
	var expected_economy: Dictionary = main.economy_system.to_dict()
	var expected_resources: Array = main.world.to_resource_dicts()

	assertions.truthy(main.market_system.commit_sell("wood", 1), "round-trip runtime market diverges")
	var divergent_npc: Dictionary = main.npc_economy_system.to_dict()
	_npc_state_record(divergent_npc, "lao_li").gold = 1
	assertions.truthy(main.npc_economy_system.from_dict(divergent_npc), "round-trip runtime NPC diverges")
	assertions.truthy(main.economy_system.reset_order_state(4), "round-trip runtime contract diverges")
	main.building_system.clear_buildings(true)
	main.world.advance_resource_day(int(expected_resources[0].respawn_day))
	var settlement_observer := SettlementObserver.new()
	main.market_system.market_settled.connect(settlement_observer.on_market_settled)
	assertions.truthy(manager.load_game(TEST_SLOT), "Task 13 real JSON restores through public API")
	assertions.equal(main.market_system.to_dict(), expected_market, "load restores full market history and ledger")
	assertions.equal(main.npc_economy_system.to_dict(), expected_npc, "load restores full NPC state")
	assertions.equal(main.economy_system.to_dict(), expected_economy, "load restores contract state")
	assertions.equal(main.world.to_resource_dicts(), expected_resources, "load restores depleted resource state")
	assertions.equal(main.daily_simulation_system.last_simulated_day, 4, "load restores last simulated day")
	var restored := main.building_system.get_all_buildings()[0] as BuildingInstance
	assertions.equal(restored.producer_state.jobs.size(), 1, "load restores queued producer job")
	assertions.equal(restored.producer_state.outputs, {"plank": 2}, "load restores staged producer output")
	assertions.truthy(manager.load_game(TEST_SLOT), "same-day save can be loaded repeatedly")
	assertions.equal(settlement_observer.calls, 0, "same-day load never settles market again")
	assertions.equal(main.market_system.to_dict(), expected_market, "same-day load cannot change determined market history")
	main.free()
	manager.free()
	_cleanup()


func _test_task13_legacy_iron_migration_and_missing_economy_idempotence(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_cleanup()
	var manager := SaveManagerScript.new()
	manager.name = "Task13LegacySaveManager"
	manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(manager)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.load_save_on_start = false
	main.save_manager = manager
	tree.root.add_child(main)
	var slots: Array[Dictionary] = [{"item_id": "iron", "quantity": 5}, {"item_id": "iron_ingot", "quantity": 3}]
	while slots.size() < main.inventory_system.max_slots:
		slots.append({})
	_write_json(manager._save_path(TEST_SLOT), {
		"total_days": 3,
		"inventory": {"slots": slots, "quick_mappings": [0, -1, -1, -1, -1, -1]},
	})
	var resource_count: int = main.world.to_resource_dicts().size()
	var settlement_observer := SettlementObserver.new()
	main.market_system.market_settled.connect(settlement_observer.on_market_settled)
	assertions.truthy(manager.load_game(TEST_SLOT), "legacy JSON without economy fields loads")
	assertions.equal(main.inventory_system.get_item_count("iron"), 0, "legacy iron stack is removed")
	assertions.equal(main.inventory_system.get_item_count("iron_ingot"), 8, "legacy iron quantity migrates without loss")
	assertions.equal(main.inventory_system.get_quick_item(0), "iron_ingot", "legacy quick mapping follows migrated stack")
	var first_market: Dictionary = main.market_system.to_dict()
	var first_npc: Dictionary = main.npc_economy_system.to_dict()
	assertions.truthy(manager.load_game(TEST_SLOT), "legacy JSON remains idempotent on repeated load")
	assertions.equal(main.market_system.to_dict(), first_market, "missing market field initializes to one stable state")
	assertions.equal(main.npc_economy_system.to_dict(), first_npc, "missing NPC field initializes to one stable state")
	assertions.equal(main.world.to_resource_dicts().size(), resource_count, "missing resource field does not duplicate world resources")
	assertions.equal(settlement_observer.calls, 0, "legacy same-day loads never trigger settlement")
	assertions.equal(main.daily_simulation_system.last_simulated_day, 3, "legacy load sets same-day simulation guard")
	assertions.truthy(manager.save_game(TEST_SLOT), "migrated legacy state can be saved as version 1")
	var migrated: Dictionary = _read_json(manager._save_path(TEST_SLOT))
	var migrated_iron := 0
	var migrated_ingots := 0
	for slot in migrated.inventory.slots:
		if slot.get("item_id", "") == "iron":
			migrated_iron += int(slot.get("quantity", 0))
		elif slot.get("item_id", "") == "iron_ingot":
			migrated_ingots += int(slot.get("quantity", 0))
	assertions.equal(migrated_iron, 0, "re-saved version 1 contains no legacy iron stack")
	assertions.equal(migrated_ingots, 8, "re-saved version 1 preserves migrated ingot quantity")
	main.free()
	manager.free()
	_cleanup()


func _test_task13_resource_apply_failure_rolls_back_economy(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var market := MarketSystemScript.new()
	var daily := DailySimulationSystem.new()
	var resources := RejectingResourceWorld.new()
	var manager := SaveManagerScript.new()
	tree.root.add_child(market)
	tree.root.add_child(daily)
	tree.root.add_child(manager)
	assertions.truthy(market.configure([_wood_definition()]), "atomic resource fixture configures market")
	assertions.truthy(manager.configure_economy(market, daily, null, resources), "atomic resource fixture configures save manager")
	assertions.truthy(market.settle_day(2), "atomic resource fixture creates target market")
	daily.last_simulated_day = 2
	var target_market: Dictionary = market.to_dict()
	var target := {
		"economy_version": 1,
		"market": target_market,
		"last_simulated_day": 2,
		"total_days": 2,
		"resource_nodes": [{"resource_id": "rock", "hits_remaining": 0}],
	}
	assertions.truthy(market.configure([_wood_definition()]), "atomic resource fixture rewinds market")
	daily.last_simulated_day = 0
	var market_before: Dictionary = market.to_dict()
	var resources_before: Array = resources.to_resource_dicts()
	resources.reject_next_restore = true
	assertions.truthy(not manager._apply_save_data(target), "resource apply failure rejects whole economy snapshot")
	assertions.equal(market.to_dict(), market_before, "resource apply failure rolls market back")
	assertions.equal(daily.last_simulated_day, 0, "resource apply failure rolls daily cursor back")
	assertions.equal(resources.to_resource_dicts(), resources_before, "resource apply failure preserves resources")
	manager.free()
	daily.free()
	market.free()


func _test_task13_corrupt_producer_load_is_atomic(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_test_task13_failed_building_load_is_atomic(assertions, tree, false)


func _test_task13_short_building_restore_is_atomic(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_test_task13_failed_building_load_is_atomic(assertions, tree, true)


func _test_task13_failed_building_load_is_atomic(
	assertions: TestAssert,
	tree: SceneTree,
	duplicate_record: bool
) -> void:
	_cleanup()
	var scenario := "restore count shortage" if duplicate_record else "corrupt producer state"
	var manager := SaveManagerScript.new()
	manager.name = "Task13AtomicBuildingSaveManager"
	manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(manager)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.load_save_on_start = false
	main.save_manager = manager
	tree.root.add_child(main)
	var game_state := tree.root.get_node_or_null("GameState")

	var location := _find_restore_location(main, "workbench")
	var existing_record := _producer_building_record(main, location)
	assertions.equal(
		main.building_system.restore_buildings([existing_record]),
		1,
		"%s fixture restores existing queued producer" % scenario
	)
	main.production_system.register_existing_buildings()
	main.inventory_system.restore_state(
		[{
			"item_id": "grain_seed",
			"quantity": 7,
		}, {
			"item_id": "wood",
			"quantity": 9,
		}],
		[1, 0, -1, -1, -1, -1]
	)
	game_state.gold = 211
	game_state.player_state.stamina = 73
	manager.current_slot = TEST_SLOT
	var before := _capture_atomic_load_state(main, manager, game_state)
	var incoming: Dictionary = manager._gather_save_data().duplicate(true)
	_prepare_divergent_atomic_payload(assertions, main, incoming, scenario)
	if duplicate_record:
		incoming.buildings.append((incoming.buildings[0] as Dictionary).duplicate(true))
	else:
		incoming.buildings[0].producer_state.jobs[0].recipe_id = "missing_recipe"
	_write_json(manager._save_path(BAD_SLOT), incoming)

	assertions.truthy(
		not manager.load_game(BAD_SLOT),
		"%s rejects the complete v1 save" % scenario
	)
	assertions.equal(
		manager.current_slot,
		TEST_SLOT,
		"%s preserves the adopted save slot" % scenario
	)
	_assert_atomic_load_state(assertions, main, manager, game_state, before, scenario)
	main.free()
	manager.free()
	_cleanup()


func _test_main_wires_economy_runtime(assertions: TestAssert, tree: SceneTree) -> void:
	_cleanup()
	var manager := SaveManagerScript.new()
	manager.name = "EconomyMainWiringSaveManager"
	manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(manager)
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	assertions.truthy(main_scene != null, "main scene loads for economy wiring")
	if main_scene == null:
		manager.free()
		return
	var main := main_scene.instantiate()
	assertions.truthy(main.get_script() != null, "main script compiles for economy wiring")
	if main.get_script() == null:
		main.free()
		manager.free()
		return
	main.load_save_on_start = false
	main.save_manager = manager
	tree.root.add_child(main)
	assertions.truthy(main.market_system != null, "main creates market system")
	assertions.truthy(main.npc_economy_system != null, "main creates NPC economy system")
	assertions.truthy(main.daily_simulation_system != null, "main creates daily coordinator")
	assertions.truthy(main.market_system.get_stock("wood") > 0, "main initializes market catalog")
	assertions.equal(
		main.market_system.last_settled_day,
		main.season_system.total_days,
		"new main market cursor starts at authoritative calendar day"
	)
	assertions.equal(
		main.daily_simulation_system.last_simulated_day,
		main.season_system.total_days,
		"new main coordinator starts at authoritative calendar day"
	)
	assertions.equal(
		main.economy_system._market_ref,
		main.market_system,
		"main injects market into player economy"
	)
	assertions.equal(
		manager._market_system,
		main.market_system,
		"main injects market into save manager"
	)
	assertions.equal(
		manager._daily_simulation_system,
		main.daily_simulation_system,
		"main injects coordinator into save manager"
	)
	assertions.equal(
		manager._npc_economy_system,
		main.npc_economy_system,
		"main injects NPC economy into save manager"
	)
	main.season_system.current_season = SeasonSystem.Season.SUMMER
	main.season_system.current_day = 4
	main.season_system.total_days = 11
	main.season_system.hour = 13
	main.season_system.minute = 20
	assertions.truthy(main.market_system.settle_day(11), "main save fixture settles its current day")
	main.daily_simulation_system.last_simulated_day = 11
	main.npc_economy_system.sync_daily_cursor(11)
	main.economy_system.reset_order_state(11)
	var main_save: Dictionary = manager._gather_save_data()
	assertions.equal(main_save.get("total_days"), 11, "main save reads its child season system")
	for missing_calendar_field in ["season", "day", "total_days", "hour", "minute"]:
		var missing_calendar_save := main_save.duplicate(true)
		missing_calendar_save.erase(missing_calendar_field)
		assertions.truthy(
			not manager._apply_save_data(missing_calendar_save),
			"injected v1 save requires calendar field: %s" % missing_calendar_field
		)
		assertions.equal(
			main.season_system.total_days,
			11,
			"missing calendar bundle does not mutate season: %s" % missing_calendar_field
		)
	for invalid_calendar in [
		{"field": "season", "value": 4},
		{"field": "season", "value": SeasonSystem.Season.WINTER},
		{"field": "day", "value": 0},
		{"field": "day", "value": 7},
		{"field": "total_days", "value": 11.5},
		{"field": "hour", "value": 24},
		{"field": "minute", "value": 60},
	]:
		var invalid_calendar_save := main_save.duplicate(true)
		invalid_calendar_save[invalid_calendar.field] = invalid_calendar.value
		assertions.truthy(
			not manager._apply_save_data(invalid_calendar_save),
			"injected v1 save rejects invalid calendar field: %s" % invalid_calendar.field
		)
		assertions.equal(
			main.season_system.total_days,
			11,
			"invalid calendar bundle does not mutate season: %s" % invalid_calendar.field
		)
	var zero_day_save := main_save.duplicate(true)
	zero_day_save.market["last_settled_day"] = 0
	zero_day_save["last_simulated_day"] = 0
	zero_day_save["total_days"] = 0
	zero_day_save["season"] = SeasonSystem.Season.SPRING
	zero_day_save["day"] = 1
	assertions.truthy(
		not manager._apply_save_data(zero_day_save),
		"injected v1 calendar rejects total day zero"
	)
	assertions.equal(
		main.season_system.total_days,
		11,
		"zero-day injected calendar does not mutate season"
	)
	main.season_system.current_season = SeasonSystem.Season.SPRING
	main.season_system.current_day = 1
	main.season_system.total_days = 1
	main.season_system.hour = 6
	main.season_system.minute = 0
	assertions.truthy(manager._apply_save_data(main_save), "main runtime save data reapplies")
	assertions.equal(main.season_system.current_season, SeasonSystem.Season.SUMMER, "load restores season")
	assertions.equal(main.season_system.current_day, 4, "load restores season day")
	assertions.equal(main.season_system.total_days, 11, "load restores authoritative total day")
	assertions.equal(main.season_system.hour, 13, "load restores hour")
	assertions.equal(main.season_system.minute, 20, "load restores minute")

	var restore_location := _find_restore_location(main, "chicken_coop")
	assertions.truthy(restore_location.x >= 0, "runtime load fixture finds a buildable coop footprint")
	var restored_record := _passive_building_record(main, "chicken_coop", restore_location)
	var runtime_save := main_save.duplicate(true)
	runtime_save["season"] = SeasonSystem.Season.SPRING
	runtime_save["day"] = 4
	runtime_save["total_days"] = 4
	runtime_save["hour"] = 9
	runtime_save["minute"] = 15
	runtime_save["last_simulated_day"] = 4
	runtime_save.market["last_settled_day"] = 4
	_set_npc_snapshot_day(runtime_save.npc_economy, 4)
	runtime_save.economy_state["last_processed_day"] = 4
	runtime_save["buildings"] = [restored_record]
	_write_json(manager._save_path(TEST_SLOT), runtime_save)
	var observer := LoadObserver.new(manager)
	var has_load_completed := manager.has_signal("load_completed")
	assertions.truthy(has_load_completed, "save manager exposes a successful-load notification")
	if has_load_completed:
		manager.connect("load_completed", observer.on_load_completed)
	main.production_system.sync_daily_cursor(12)
	main.production_system.sync_clock(21, 40)
	main.building_system.clear_buildings(true)
	assertions.equal(main.production_system.get_registered_buildings().size(), 0, "runtime fixture clears the production registry")
	assertions.truthy(manager.load_game(TEST_SLOT), "later public load succeeds")
	assertions.equal(observer.calls, 1, "successful public load emits one completion notification")
	assertions.equal(observer.adopted_slot, TEST_SLOT, "load completion follows current-slot adoption")
	assertions.equal(main.production_system._last_daily_effects_day, 4, "runtime load rewinds daily effects to the restored day")
	assertions.equal(main.production_system._last_finished_outputs_day, 4, "runtime load rewinds passive outputs to the restored day")
	assertions.equal(main.production_system._last_clock_minutes, 9 * 60 + 15, "runtime load synchronizes the restored clock")
	assertions.equal(main.building_system.get_building_count(), 1, "runtime load restores the saved building")
	assertions.equal(main.production_system.get_registered_buildings().size(), 1, "runtime load re-registers the restored building")
	var restored_coop := main.building_system.get_all_buildings()[0] as BuildingInstance
	main.production_system.finish_daily_outputs(5)
	assertions.equal(restored_coop.producer_state.outputs, {"egg": 2}, "first day after runtime load produces exactly once")
	assertions.equal(restored_coop.producer_state.inputs, {"animal_feed": 1}, "first day after runtime load consumes exactly one feed")
	main.production_system.finish_daily_outputs(5)
	assertions.equal(restored_coop.producer_state.outputs, {"egg": 2}, "runtime load cannot duplicate the next-day output")

	var main_load_connections := 0
	if has_load_completed:
		for connection in manager.get_signal_connection_list("load_completed"):
			var callback: Callable = connection.get("callable", Callable())
			if callback.is_valid() and callback.get_object() == main:
				main_load_connections += 1
	assertions.equal(main_load_connections, 1, "Main owns exactly one load-completed connection")
	main.production_system.sync_daily_cursor(12)
	main.production_system.sync_clock(21, 40)
	var registered_before_failed_load: Array[BuildingInstance] = main.production_system.get_registered_buildings()
	_write_json(manager._save_path(BAD_SLOT), {"economy_version": 1, "market": {}})
	assertions.truthy(not manager.load_game(BAD_SLOT), "failed later public load is rejected")
	assertions.equal(observer.calls, 1, "failed public load emits no completion notification")
	assertions.equal(main.production_system._last_daily_effects_day, 12, "failed load preserves the daily effect cursor")
	assertions.equal(main.production_system._last_finished_outputs_day, 12, "failed load preserves the passive output cursor")
	assertions.equal(main.production_system._last_clock_minutes, 21 * 60 + 40, "failed load preserves the production clock")
	assertions.equal(main.production_system.get_registered_buildings(), registered_before_failed_load, "failed load preserves the production registry")
	var event_bus := tree.root.get_node_or_null("EventBus")
	var daily_connections := 0
	if event_bus != null:
		for connection in event_bus.day_changed.get_connections():
			var callable: Callable = connection.get("callable", Callable())
			if callable.is_valid() and callable.get_object() == main.daily_simulation_system:
				daily_connections += 1
	assertions.equal(daily_connections, 1, "main coordinator owns one authoritative day connection")
	main.daily_simulation_system.free()
	var rejecting_market := RejectingMarketDouble.new()
	rejecting_market.name = "RejectingMarket"
	main.add_child(rejecting_market)
	var replacement_daily := DailySimulationSystem.new()
	replacement_daily.name = "ReplacementDailySimulationSystem"
	main.add_child(replacement_daily)
	main.market_system = rejecting_market
	main.daily_simulation_system = replacement_daily
	main._connect_systems()
	assertions.truthy(
		not replacement_daily._is_configured,
		"main market failure leaves replacement coordinator inactive"
	)
	var replacement_connections := 0
	if event_bus != null:
		for connection in event_bus.day_changed.get_connections():
			var callable: Callable = connection.get("callable", Callable())
			if callable.is_valid() and callable.get_object() == replacement_daily:
				replacement_connections += 1
	assertions.equal(replacement_connections, 0, "failed main wiring leaves no live coordinator")
	main.free()

	var startup_main := main_scene.instantiate()
	startup_main.save_manager = manager
	startup_main.save_slot = TEST_SLOT
	startup_main.load_save_on_start = true
	tree.root.add_child(startup_main)
	assertions.equal(observer.calls, 2, "startup public load emits one additional completion notification")
	assertions.equal(startup_main.season_system.total_days, 4, "startup load restores the saved day")
	assertions.equal(startup_main.npc_economy_system.last_simulated_day, 4, "startup load restores NPC cursor")
	assertions.equal(startup_main.production_system._last_daily_effects_day, 4, "startup handler and setup leave the exact effect cursor")
	assertions.equal(startup_main.production_system._last_finished_outputs_day, 4, "startup handler and setup leave the exact output cursor")
	assertions.equal(startup_main.production_system._last_clock_minutes, 9 * 60 + 15, "startup handler and setup leave the exact clock")
	assertions.equal(startup_main.production_system.get_registered_buildings().size(), 1, "startup handler and setup register one restored building")
	var startup_coop := startup_main.building_system.get_all_buildings()[0] as BuildingInstance
	startup_main.production_system.finish_daily_outputs(5)
	assertions.equal(startup_coop.producer_state.outputs, {"egg": 2}, "startup load produces once on the following day")
	assertions.equal(startup_coop.producer_state.inputs, {"animal_feed": 1}, "startup load consumes one feed on the following day")
	startup_main.production_system.finish_daily_outputs(5)
	assertions.equal(startup_coop.producer_state.outputs, {"egg": 2}, "startup synchronization cannot duplicate following-day output")
	var startup_load_connections := 0
	for connection in manager.get_signal_connection_list("load_completed"):
		var callback: Callable = connection.get("callable", Callable())
		if callback.is_valid() and callback.get_object() == startup_main:
			startup_load_connections += 1
	assertions.equal(startup_load_connections, 1, "startup Main owns one load-completed connection")
	startup_main.free()
	manager.free()
	_cleanup()


func _test_npc_economy_round_trip_atomic_rejection_and_legacy_backfill(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_cleanup()
	var market := MarketSystemScript.new()
	var daily := DailySimulationSystem.new()
	var npc := NpcEconomySystemScript.new()
	var manager := SaveManagerScript.new()
	manager.save_directory = TEST_SAVE_DIR
	for dependency in [market, daily, npc, manager]:
		tree.root.add_child(dependency)
	assertions.truthy(market.configure(GameDataScript.get_market_items()), "NPC save market configures")
	assertions.truthy(npc.configure(
		market,
		GameDataScript.get_npc_economy_profiles(),
		GameDataScript.get_population_demand_profiles()
	), "NPC save system configures")
	assertions.truthy(
		manager.configure_economy(market, daily, null, null, npc),
		"save manager accepts NPC economy dependency"
	)
	assertions.truthy(market.settle_day(4), "NPC save market advances to persisted day")
	daily.last_simulated_day = 4
	npc.sync_daily_cursor(4)
	var legacy_expected := npc.to_dict()
	var persisted := npc.to_dict()
	var lao_li: Dictionary = _npc_state_record(persisted, "lao_li")
	lao_li.gold = 321
	lao_li.inventory.salt = 11
	lao_li.investment_planned = true
	persisted.essential_zero_streaks.wood = 2
	persisted.demand_tags = {"residents": "持久化居民需求"}
	assertions.truthy(npc.from_dict(persisted), "NPC save fixture adopts changed runtime state")
	var expected_npc := npc.to_dict()
	assertions.truthy(manager.save_game(TEST_SLOT), "NPC economy writes through real SaveManager")
	var gathered := manager._gather_save_data()
	assertions.equal(gathered.get("npc_economy"), expected_npc, "save payload includes full NPC system state")

	var divergent := npc.to_dict()
	_npc_state_record(divergent, "lao_li").gold = 999
	_set_npc_snapshot_day(divergent, 5)
	assertions.truthy(npc.from_dict(divergent), "NPC runtime diverges after save")
	assertions.truthy(market.settle_day(5), "NPC save market diverges after save")
	daily.last_simulated_day = 5
	assertions.truthy(manager.load_game(TEST_SLOT), "real SaveManager restores NPC economy")
	assertions.equal(npc.to_dict(), expected_npc, "NPC wallet inventory plan streaks tags and cursor round trip")

	var malformed_save := gathered.duplicate(true)
	var malformed_state: Dictionary = malformed_save.npc_economy.npc_states[0]
	malformed_state.inventory["unknown_item"] = 1
	_write_json(manager._save_path(BAD_SLOT), malformed_save)
	var market_before_bad := market.to_dict()
	var daily_before_bad := daily.last_simulated_day
	var npc_before_bad := npc.to_dict()
	var game_state := tree.root.get_node_or_null("GameState")
	var gold_before_bad: Variant = game_state.gold if game_state != null else null
	assertions.truthy(not manager.load_game(BAD_SLOT), "malformed NPC payload rejects the whole save")
	assertions.equal(market.to_dict(), market_before_bad, "malformed NPC payload preserves market")
	assertions.equal(daily.last_simulated_day, daily_before_bad, "malformed NPC payload preserves daily cursor")
	assertions.equal(npc.to_dict(), npc_before_bad, "malformed NPC payload preserves all NPC state")
	if game_state != null:
		assertions.equal(game_state.gold, gold_before_bad, "malformed NPC payload applies no earlier player fields")

	var legacy_save := gathered.duplicate(true)
	legacy_save.erase("npc_economy")
	_write_json(manager._save_path(TEST_SLOT), legacy_save)
	var legacy_divergent := npc.to_dict()
	_npc_state_record(legacy_divergent, "lao_li").gold = 1
	_set_npc_snapshot_day(legacy_divergent, 7)
	assertions.truthy(npc.from_dict(legacy_divergent), "legacy fixture dirties current NPC state")
	assertions.truthy(manager.load_game(TEST_SLOT), "legacy economy save without NPC payload loads")
	assertions.equal(npc.to_dict(), legacy_expected, "legacy load restores profile defaults at loaded day")
	assertions.truthy(not npc.simulate_day(4), "legacy loaded NPC day cannot replay")

	for dependency in [manager, npc, daily, market]:
		dependency.free()
	_cleanup()


func _prepare_divergent_atomic_payload(
	assertions: TestAssert,
	main: Node,
	incoming: Dictionary,
	scenario: String
) -> void:
	incoming["gold"] = int(incoming.get("gold", 0)) + 701
	incoming.player.stamina = 12
	incoming.player.level = 4
	var slots: Array[Dictionary] = [{"item_id": "stone", "quantity": 3}]
	while slots.size() < main.inventory_system.max_slots:
		slots.append({})
	incoming["inventory"] = {
		"slots": slots,
		"quick_mappings": [0, -1, -1, -1, -1, -1],
	}

	var incoming_market := MarketSystemScript.new()
	assertions.truthy(
		incoming_market.from_dict(incoming.market),
		"%s divergent market fixture restores" % scenario
	)
	assertions.truthy(
		incoming_market.commit_buy("wood", 1),
		"%s divergent market fixture changes stock" % scenario
	)
	incoming["market"] = incoming_market.to_dict()
	incoming_market.free()

	var incoming_npc: Dictionary = incoming.npc_economy
	var lao_li := _npc_state_record(incoming_npc, "lao_li")
	lao_li.gold = int(lao_li.gold) + 37
	assertions.truthy(
		main.npc_economy_system.validate_dict(incoming_npc),
		"%s divergent NPC fixture remains valid" % scenario
	)
	incoming["npc_economy"] = incoming_npc
	var total_day := int(incoming.last_simulated_day)
	var contract := {
		"contract_id": "lao_li:wood:%d:%d" % [total_day, total_day + 2],
		"npc_id": "lao_li",
		"item_id": "wood",
		"quantity_per_day": 2,
		"unit_price": 10,
		"reward_gold": 20,
		"start_day": total_day,
		"end_day": total_day + 2,
		"delivered_days": [],
		"breaches": 0,
		"signed": true,
		"completed": false,
		"expired": false,
	}
	incoming["economy_state"] = {
		"last_processed_day": total_day,
		"orders": [],
		"contracts": [contract],
	}
	assertions.truthy(
		main.economy_system.validate_dict(incoming.economy_state),
		"%s divergent order fixture remains valid" % scenario
	)

	if not incoming.resource_nodes.is_empty():
		var resource: Dictionary = incoming.resource_nodes[0]
		if int(resource.hits_remaining) > 1:
			resource.hits_remaining = int(resource.hits_remaining) - 1
		incoming.resource_nodes[0] = resource

	var added_grid_divergence := false
	for gz in range(GridSystem.GRID_DEPTH):
		if added_grid_divergence:
			break
		for gx in range(GridSystem.GRID_WIDTH):
			var cell: GridCell = main.grid_system.get_cell(gx, gz)
			if cell != null and cell.state == GridCell.State.WASTELAND:
				incoming.grid.cells.append({
					"gx": gx,
					"gz": gz,
					"state": GridCell.State.FARMLAND,
					"watered": true,
				})
				added_grid_divergence = true
				break
	assertions.truthy(added_grid_divergence, "%s fixture changes an unrelated grid cell" % scenario)


func _capture_atomic_load_state(main: Node, manager: Node, game_state: Node) -> Dictionary:
	return {
		"gold": game_state.gold,
		"player": {
			"stamina": game_state.player_state.stamina,
			"max_stamina": game_state.player_state.max_stamina,
			"level": game_state.player_state.level,
			"exp": game_state.player_state.exp,
		},
		"calendar": {
			"season": main.season_system.current_season,
			"day": main.season_system.current_day,
			"total_days": main.season_system.total_days,
			"hour": main.season_system.hour,
			"minute": main.season_system.minute,
		},
		"inventory_slots": main.inventory_system.slots.duplicate(true),
		"quick_mappings": main.inventory_system.quick_slot_mappings.duplicate(),
		"grid": main.grid_system.to_dict(),
		"buildings": manager._serialize_buildings(main.building_system),
		"registered_producers": _serialize_registered_producers(main),
		"market": main.market_system.to_dict(),
		"last_simulated_day": main.daily_simulation_system.last_simulated_day,
		"npc_economy": main.npc_economy_system.to_dict(),
		"economy_state": main.economy_system.to_dict(),
		"resource_nodes": main.world.to_resource_dicts(),
	}


func _assert_atomic_load_state(
	assertions: TestAssert,
	main: Node,
	manager: Node,
	game_state: Node,
	expected: Dictionary,
	scenario: String
) -> void:
	var actual := _capture_atomic_load_state(main, manager, game_state)
	for field in [
		"gold",
		"player",
		"calendar",
		"inventory_slots",
		"quick_mappings",
		"grid",
		"buildings",
		"registered_producers",
		"market",
		"last_simulated_day",
		"npc_economy",
		"economy_state",
		"resource_nodes",
	]:
		assertions.equal(
			actual[field],
			expected[field],
			"%s leaves prior %s state untouched" % [scenario, field]
		)


func _serialize_registered_producers(main: Node) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for building in main.production_system.get_registered_buildings():
		if building != null and building.has_method("to_dict"):
			records.append(building.to_dict())
	return records


func _find_restore_location(main: Node, building_id: String) -> Vector2i:
	var definition: Dictionary = GameDataScript.get_building(building_id)
	var width := int(definition.get("footprint_x", 1))
	var depth := int(definition.get("footprint_z", 1))
	for gz in range(GridSystem.GRID_DEPTH - depth + 1):
		for gx in range(GridSystem.GRID_WIDTH - width + 1):
			var valid := true
			for z in range(gz, gz + depth):
				for x in range(gx, gx + width):
					var cell: GridCell = main.grid_system.get_cell(x, z)
					if cell == null or cell.state not in [GridCell.State.WASTELAND, GridCell.State.FARMLAND]:
						valid = false
						break
				if not valid:
					break
			if valid:
				return Vector2i(gx, gz)
	return Vector2i(-1, -1)


func _producer_building_record(main: Node, location: Vector2i) -> Dictionary:
	if location.x < 0:
		return {}
	var definition: Dictionary = GameDataScript.get_building("workbench")
	var occupied_cells: Array[Dictionary] = []
	for z in range(location.y, location.y + int(definition.get("footprint_z", 1))):
		for x in range(location.x, location.x + int(definition.get("footprint_x", 1))):
			var cell: GridCell = main.grid_system.get_cell(x, z)
			occupied_cells.append({"gx": x, "gz": z, "previous_state": int(cell.state)})
	var state := ProducerStateScript.new("workbench")
	state.enqueue_job({
		"recipe_id": "plank",
		"batches": 1,
		"remaining_minutes": 60,
		"status": "running",
	})
	state.add_outputs({"plank": 2})
	return {
		"building_id": "workbench",
		"gx": location.x,
		"gz": location.y,
		"occupied_cells": occupied_cells,
		"producer_state": state.to_dict(),
	}


func _passive_building_record(main: Node, building_id: String, location: Vector2i) -> Dictionary:
	if location.x < 0:
		return {}
	var definition: Dictionary = GameDataScript.get_building(building_id)
	var occupied_cells: Array[Dictionary] = []
	for z in range(location.y, location.y + int(definition.get("footprint_z", 1))):
		for x in range(location.x, location.x + int(definition.get("footprint_x", 1))):
			var cell: GridCell = main.grid_system.get_cell(x, z)
			occupied_cells.append({"gx": x, "gz": z, "previous_state": int(cell.state)})
	var state := ProducerStateScript.new(building_id)
	state.inputs = {"animal_feed": 2}
	return {
		"building_id": building_id,
		"gx": location.x,
		"gz": location.y,
		"occupied_cells": occupied_cells,
		"producer_state": state.to_dict(),
	}


func _wood_definition() -> Dictionary:
	return {
		"id": "wood",
		"base_price": 100,
		"initial_stock": 10,
		"target_stock": 10,
		"daily_liquidity": 10,
	}


func _npc_state_record(snapshot: Dictionary, npc_id: String) -> Dictionary:
	for state_value in snapshot.get("npc_states", []):
		if state_value is Dictionary and str(state_value.get("npc_id", "")) == npc_id:
			return state_value
	return {}


func _set_npc_snapshot_day(snapshot: Dictionary, total_day: int) -> void:
	snapshot["last_simulated_day"] = total_day
	for state_value in snapshot.get("npc_states", []):
		if state_value is Dictionary:
			state_value["last_simulated_day"] = total_day


func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _cleanup() -> void:
	for slot in [TEST_SLOT, BAD_SLOT]:
		var path := TEST_SAVE_DIR.path_join("save_%d.json" % slot)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var directory := TEST_SAVE_DIR.trim_suffix("/")
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)
