extends RefCounted

const DailySimulationSystem = preload("res://scripts/systems/daily_simulation_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const TEST_SAVE_DIR := "user://villa_test_saves/economy_task_5/"
const TEST_SLOT := 3
const BAD_SLOT := 4


class RejectingMarketDouble:
	extends MarketSystemScript

	func configure(_definitions: Array) -> bool:
		return false


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_save_round_trip_and_legacy_load(assertions, tree)
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


func _test_main_wires_economy_runtime(assertions: TestAssert, tree: SceneTree) -> void:
	var manager := SaveManagerScript.new()
	manager.name = "EconomyMainWiringSaveManager"
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
	main.season_system.current_season = SeasonSystem.Season.SUMMER
	main.season_system.current_day = 4
	main.season_system.total_days = 11
	main.season_system.hour = 13
	main.season_system.minute = 20
	assertions.truthy(main.market_system.settle_day(11), "main save fixture settles its current day")
	main.daily_simulation_system.last_simulated_day = 11
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
	manager.free()


func _wood_definition() -> Dictionary:
	return {
		"id": "wood",
		"base_price": 100,
		"initial_stock": 10,
		"target_stock": 10,
		"daily_liquidity": 10,
	}


func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()


func _cleanup() -> void:
	for slot in [TEST_SLOT, BAD_SLOT]:
		var path := TEST_SAVE_DIR.path_join("save_%d.json" % slot)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var directory := TEST_SAVE_DIR.trim_suffix("/")
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)
