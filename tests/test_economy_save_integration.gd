extends RefCounted

const DailySimulationSystem = preload("res://scripts/systems/daily_simulation_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
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
