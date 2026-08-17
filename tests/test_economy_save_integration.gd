extends RefCounted

const DailySimulationSystem = preload("res://scripts/systems/daily_simulation_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomySystemScript = preload("res://scripts/systems/npc_economy_system.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const ProducerStateScript = preload("res://scripts/data/producer_state.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")
const FarmStorageSystemScript = preload("res://scripts/systems/farm_storage_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const PlayerActionControllerScript = preload("res://scripts/actors/player_action_controller.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")
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


class RegistryLoadObserver:
	extends RefCounted
	var main: Node
	var observed_producers: Array[Dictionary] = []

	func on_load_completed(_slot: int) -> void:
		observed_producers.clear()
		for building in main.production_system.get_registered_buildings():
			if building != null and building.has_method("to_dict"):
				observed_producers.append(building.to_dict())


class SettlementObserver:
	extends RefCounted
	var calls := 0

	func on_market_settled(_total_day: int) -> void:
		calls += 1


class LoadOnStorageObserver:
	extends RefCounted
	var manager: Node
	var slot := 0
	var results: Array[bool] = []

	func on_storage_changed(_changes: Dictionary) -> void:
		results.append(manager.load_game(slot))


class ExpSignalRecorder:
	extends RefCounted
	var amounts: Array[int] = []
	var levels: Array[int] = []
	var timeline: Array[String] = []

	func on_exp_gained(amount: int) -> void:
		amounts.append(amount)
		timeline.append("exp:%d" % amount)

	func on_level_changed(level: int) -> void:
		levels.append(level)
		timeline.append("level:%d" % level)


class LoadOnExpObserver:
	extends RefCounted
	var manager: Node
	var slot := 0
	var calls := 0
	var results: Array[bool] = []

	func on_exp_gained(amount: int) -> void:
		if calls > 0 or amount <= 0:
			return
		calls += 1
		results.append(manager.load_game(slot))


class RejectingGridRestore:
	extends GridSystemScript
	var reject_next_restore := false

	func from_dict(data: Dictionary) -> bool:
		if reject_next_restore:
			reject_next_restore = false
			return false
		return super.from_dict(data)


class EmptyBuildingRestore:
	extends Node

	func get_all_buildings() -> Array:
		return []

	func validate_restore_buildings(records: Array, _grid_data: Dictionary) -> bool:
		return records.is_empty()

	func clear_buildings(_restore_grid := true, _emit_public_signals := true) -> void:
		pass

	func restore_buildings(records: Array, _emit_public_signals := true) -> int:
		return records.size()


class RestoreNotificationObserver:
	extends RefCounted
	var game_state: Node
	var inventory: InventorySystem
	var grid: GridSystem
	var mutate_game_state := false
	var manager: Node
	var reentrant_slot := 0
	var attempt_reentrant_load := false
	var reentrant_attempted := false
	var reentrant_results: Array[bool] = []
	var quick_events: Array[Dictionary] = []
	var navigation_events: Array[Dictionary] = []

	func on_quick_changed(index: int, item_id: String) -> void:
		quick_events.append(_snapshot({"index": index, "item_id": item_id}))
		_mutate_if_requested()

	func on_navigation_changed(revision: int) -> void:
		navigation_events.append(_snapshot({"revision": revision}))
		_mutate_if_requested()
		if attempt_reentrant_load and not reentrant_attempted:
			reentrant_attempted = true
			reentrant_results.append(manager.load_game(reentrant_slot))

	func _snapshot(event: Dictionary) -> Dictionary:
		var snapshot := event.duplicate(true)
		snapshot["gold"] = int(game_state.gold)
		snapshot["exp"] = int(game_state.player_state.exp)
		snapshot["level"] = int(game_state.player_state.level)
		snapshot["quick_item"] = inventory.get_quick_item(0)
		snapshot["cell_state"] = int(grid.get_cell(2, 2).state)
		return snapshot

	func _mutate_if_requested() -> void:
		if not mutate_game_state:
			return
		game_state.reset_to_new_game()
		game_state.add_gold(7)
		game_state.add_exp(2)


class BuildingSignalObserver:
	extends RefCounted
	var local_removed := 0
	var local_placed := 0
	var bus_removed := 0
	var bus_placed := 0

	func on_local_removed(_building_id: String) -> void:
		local_removed += 1

	func on_local_placed(_building: BuildingInstance) -> void:
		local_placed += 1

	func on_bus_removed(_building: BuildingInstance) -> void:
		bus_removed += 1

	func on_bus_placed(_building: BuildingInstance) -> void:
		bus_placed += 1

	func reset() -> void:
		local_removed = 0
		local_placed = 0
		bus_removed = 0
		bus_placed = 0


class RejectingResourceWorld:
	extends RefCounted
	var records: Array[Dictionary] = [{"resource_id": "rock", "hits_remaining": 3}]
	var reject_next_restore := false
	var game_state: Node
	var observed_harvest_seeds: Array[int] = []

	func to_resource_dicts() -> Array[Dictionary]:
		return records.duplicate(true)

	func validate_resource_dicts(value: Variant, _loaded_day: int) -> bool:
		return value is Array

	func restore_resource_dicts(value: Variant, _loaded_day: int) -> bool:
		if reject_next_restore:
			reject_next_restore = false
			observed_harvest_seeds.append(
				int(game_state.harvest_seed) if game_state != null else -1
			)
			return false
		records.assign((value as Array).duplicate(true))
		return true

	func initialize_resources_at_day(_day: int) -> void:
		pass


class StateTransitionOwnerDouble:
	extends RefCounted
	var reasons: Array[String] = []

	func cancel_transient_actions(reason: String) -> void:
		reasons.append(reason)


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_harvest_seed_round_trip_migration_and_atomic_rejection(assertions, tree)
	_test_save_round_trip_and_legacy_load(assertions, tree)
	_test_harvest_storage_callback_load_invalidates_exp(assertions, tree)
	_test_failed_load_preserves_committed_harvest_exp_barrier(assertions, tree)
	_test_failed_load_preserves_prearm_harvest_exp_publication(assertions, tree)
	_test_failed_load_isolates_inventory_grid_restore_notifications(assertions, tree)
	_test_successful_load_publishes_final_inventory_grid_notifications(assertions, tree)
	_test_successful_load_from_leveling_exp_callback_suppresses_stale_level(assertions, tree)
	_test_npc_economy_round_trip_atomic_rejection_and_legacy_backfill(assertions, tree)
	_test_task13_full_json_round_trip_and_starter_lifecycle(assertions, tree)
	_test_task13_legacy_iron_migration_and_missing_economy_idempotence(assertions, tree)
	_test_task13_resource_apply_failure_rolls_back_economy(assertions, tree)
	_test_greenhouse_restore_finalizes_coverage_and_visuals(assertions, tree)
	_test_load_cancels_transient_gathering_before_commit(assertions, tree)
	_test_task13_corrupt_producer_load_is_atomic(assertions, tree)
	_test_task13_short_building_restore_is_atomic(assertions, tree)
	_test_task13_invalid_top_level_and_inventory_schema_is_atomic(assertions, tree)
	_test_task13_legacy_inventory_repack_preserves_quick_items(assertions, tree)
	_test_task13_building_load_signals_are_transactional(assertions, tree)
	_test_main_wires_economy_runtime(assertions, tree)


func _test_harvest_seed_round_trip_migration_and_atomic_rejection(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var game_state := tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "harvest seed save fixture has GameState")
	if game_state == null:
		return
	assertions.truthy(game_state.has_method("set_harvest_seed"), "GameState owns a validated harvest seed")
	if not game_state.has_method("set_harvest_seed"):
		return
	var original_seed := int(game_state.get("harvest_seed"))
	assertions.truthy(original_seed > 0, "new game starts with a valid harvest seed")
	var manager := SaveManagerScript.new()
	manager.name = "HarvestSeedSaveManagerFixture"
	tree.root.add_child(manager)

	assertions.truthy(game_state.call("set_harvest_seed", 123456789), "fixture accepts a valid harvest seed")
	var gathered: Dictionary = manager._gather_save_data()
	assertions.equal(gathered.get("harvest_seed"), 123456789, "save gathering includes harvest seed")
	var json_value: Variant = JSON.parse_string(JSON.stringify(gathered))
	assertions.truthy(json_value is Dictionary, "harvest seed crosses a JSON boundary")
	assertions.truthy(game_state.call("set_harvest_seed", 987654321), "runtime seed can diverge before load")
	assertions.truthy(manager._apply_save_data(json_value), "valid save reapplies harvest seed")
	assertions.equal(game_state.get("harvest_seed"), 123456789, "round trip preserves harvest seed")

	var gold_before := int(game_state.gold)
	for invalid_seed in [0, -1, 1.5, 2147483648]:
		var invalid_payload: Dictionary = gathered.duplicate(true)
		invalid_payload["harvest_seed"] = invalid_seed
		invalid_payload["gold"] = gold_before + 10
		assertions.truthy(not manager._apply_save_data(invalid_payload), "invalid harvest seed rejects save atomically: %s" % invalid_seed)
		assertions.equal(game_state.get("harvest_seed"), 123456789, "invalid seed preserves prior harvest seed: %s" % invalid_seed)
		assertions.equal(game_state.gold, gold_before, "invalid seed applies no earlier gold field: %s" % invalid_seed)

	var legacy_payload: Dictionary = gathered.duplicate(true)
	legacy_payload.erase("harvest_seed")
	assertions.truthy(manager._apply_save_data(legacy_payload), "legacy save missing harvest seed migrates")
	assertions.equal(game_state.get("harvest_seed"), 42, "legacy save receives deterministic harvest seed default")
	assertions.truthy(game_state.call("set_harvest_seed", original_seed), "harvest seed fixture restores original state")
	manager.free()


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

	var old_catalog_market := MarketSystemScript.new()
	assertions.truthy(
		old_catalog_market.configure([_legacy_wood_definition()]),
		"versioned old-catalog fixture configures"
	)
	var old_catalog_snapshot := old_catalog_market.to_dict()
	old_catalog_snapshot.last_settled_day = 9
	old_catalog_snapshot.items.wood.mid_price = 4
	old_catalog_snapshot.items.wood.stock = 14
	old_catalog_snapshot.items.wood.supply = 4
	old_catalog_snapshot.items.wood.history = [2, 3, 4]
	old_catalog_market.free()
	assertions.truthy(
		market.configure([_current_migrated_wood_definition(), _crate_definition()]),
		"runtime adopts current market catalog before loading old versioned save"
	)
	assertions.truthy(market.commit_buy("crate", 2), "prior save mutates a newly added product")
	assertions.truthy(market.settle_day(8), "prior save records a divergent new-product history")
	assertions.truthy(
		market.get_item_state("crate") != _expected_crate_default_state(),
		"new-product fixture is polluted before loading the old save"
	)
	_write_json(manager._save_path(TEST_SLOT), {
		"economy_version": 1,
		"market": old_catalog_snapshot,
		"last_simulated_day": 9,
	})
	assertions.truthy(
		manager.load_game(TEST_SLOT),
		"versioned save from an older market catalog migrates"
	)
	var migrated_wood := market.get_item_state("wood")
	assertions.equal(migrated_wood.get("base_price"), 14, "migration adopts current base price")
	assertions.equal(migrated_wood.get("target_stock"), 80, "migration adopts current stock target")
	assertions.equal(migrated_wood.get("daily_liquidity"), 10, "migration adopts current liquidity")
	assertions.equal(
		migrated_wood.get("stock"),
		old_catalog_snapshot.items.wood.stock,
		"migration preserves saved market stock"
	)
	assertions.equal(
		migrated_wood.get("history"),
		[9, 14, 19],
		"migration rescales saved price history relative to the new base price"
	)
	assertions.equal(
		migrated_wood.get("mid_price"),
		19,
		"migration keeps the rescaled history tail and current price consistent"
	)
	assertions.equal(
		market.get_item_state("crate"),
		_expected_crate_default_state(),
		"migration backfills added products from immutable catalog defaults"
	)
	assertions.equal(market.last_settled_day, 9, "migration preserves market day cursor")
	assertions.equal(daily.last_simulated_day, 9, "migration preserves simulation day cursor")

	manager.free()
	daily.free()
	market.free()
	_cleanup()


func _test_harvest_storage_callback_load_invalidates_exp(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_cleanup()
	var game_state := tree.root.get_node_or_null("GameState")
	var event_bus := tree.root.get_node_or_null("EventBus")
	assertions.truthy(game_state != null and event_bus != null, "load-during-harvest fixture has core autoloads")
	if game_state == null or event_bus == null:
		return
	var original := {
		"gold": game_state.gold,
		"harvest_seed": game_state.harvest_seed,
		"stamina": game_state.player_state.stamina,
		"max_stamina": game_state.player_state.max_stamina,
		"level": game_state.player_state.level,
		"exp": game_state.player_state.exp,
	}
	var market := MarketSystemScript.new()
	var daily := DailySimulationSystem.new()
	var manager := SaveManagerScript.new()
	manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(market)
	tree.root.add_child(daily)
	tree.root.add_child(manager)
	assertions.truthy(manager.configure_economy(market, daily), "load-during-harvest manager configures")
	assertions.truthy(market.configure([_wood_definition()]), "load-during-harvest market configures")
	game_state.gold = 321
	game_state.player_state.stamina = 77
	game_state.player_state.max_stamina = 120
	game_state.player_state.level = 3
	game_state.player_state.exp = 250
	assertions.truthy(manager.save_game(TEST_SLOT), "load-during-harvest fixture saves replacement state")
	game_state.player_state.level = 1
	game_state.player_state.exp = 0

	var grid := GridSystemScript.new()
	grid._event_bus = event_bus
	var farming := FarmingSystemScript.new()
	farming.configure(grid, null, game_state)
	farming._event_bus = event_bus
	var storage := FarmStorageSystemScript.new()
	tree.root.add_child(storage)
	var inventory := InventorySystemScript.new()
	var controller := PlayerActionControllerScript.new()
	tree.root.add_child(controller)
	controller.configure(null, grid, farming, null, null, inventory, storage)
	var crop := CropDataScript.new()
	crop.crop_id = "grain"
	crop.growth_days = 3
	crop.yield_min = 1
	crop.yield_max = 1
	crop.exp_reward = 4
	crop.lifecycle_type = "annual"
	grid.set_cell_state(15, 15, GridCell.State.FARMLAND)
	var cell := grid.get_cell(15, 15)
	var instance: CropInstance = farming.plant(cell, crop)
	instance.set_growth_state(3.0, CropInstance.LifecycleState.MATURE)
	var loader := LoadOnStorageObserver.new()
	loader.manager = manager
	loader.slot = TEST_SLOT
	var exp_recorder := ExpSignalRecorder.new()
	storage.contents_changed.connect(loader.on_storage_changed)
	event_bus.exp_gained.connect(exp_recorder.on_exp_gained)

	assertions.truthy(controller._harvest(cell), "atomic harvest remains committed when storage callback loads")
	assertions.equal(loader.results, [true], "storage callback completes one public save load")
	assertions.equal(game_state.player_state.exp, 250, "load keeps exact restored EXP")
	assertions.equal(game_state.player_state.level, 3, "load keeps exact restored level")
	assertions.equal(exp_recorder.amounts, [], "invalidated harvest EXP never publishes after load")
	assertions.equal(storage.get_items(), {"grain": 1}, "load callback does not roll storage back")
	assertions.equal(cell.state, GridCell.State.FARMLAND, "load callback does not roll crop harvest back")

	storage.contents_changed.disconnect(loader.on_storage_changed)
	event_bus.exp_gained.disconnect(exp_recorder.on_exp_gained)
	controller.free()
	storage.free()
	inventory.free()
	farming.free()
	grid.free()
	manager.free()
	daily.free()
	market.free()
	game_state.gold = int(original.gold)
	game_state.harvest_seed = int(original.harvest_seed)
	game_state.player_state.stamina = int(original.stamina)
	game_state.player_state.max_stamina = int(original.max_stamina)
	game_state.player_state.level = int(original.level)
	game_state.player_state.exp = int(original.exp)
	_cleanup()


func _test_failed_load_preserves_committed_harvest_exp_barrier(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_test_failed_load_preserves_pending_harvest_exp(assertions, tree, true)


func _test_failed_load_preserves_prearm_harvest_exp_publication(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_test_failed_load_preserves_pending_harvest_exp(assertions, tree, false)


func _test_failed_load_preserves_pending_harvest_exp(
	assertions: TestAssert,
	tree: SceneTree,
	arm_before_load: bool
) -> void:
	_cleanup()
	var scenario := "committed barrier" if arm_before_load else "pre-arm publication"
	var game_state := tree.root.get_node_or_null("GameState")
	var event_bus := tree.root.get_node_or_null("EventBus")
	assertions.truthy(game_state != null and event_bus != null, "%s failure fixture has core autoloads" % scenario)
	if game_state == null or event_bus == null:
		return
	var original := _capture_game_state_scalars(game_state)
	var manager := SaveManagerScript.new()
	manager.save_directory = TEST_SAVE_DIR
	var rejecting_grid := RejectingGridRestore.new()
	var buildings := EmptyBuildingRestore.new()
	tree.root.add_child(manager)
	tree.root.add_child(rejecting_grid)
	rejecting_grid.add_to_group("grid_system")
	tree.root.add_child(buildings)
	buildings.add_to_group("building_system")
	game_state.gold = 654
	game_state.harvest_seed = 909
	game_state.player_state.level = 3
	game_state.player_state.exp = 250
	assertions.truthy(manager.save_game(BAD_SLOT), "%s fixture writes a valid replacement save" % scenario)
	game_state.gold = 111
	game_state.harvest_seed = 707
	game_state.player_state.level = 1
	game_state.player_state.exp = 0
	var fixture := _prepare_pending_harvest(game_state, event_bus)
	var farming: FarmingSystem = fixture.farming
	var publication: Variant = fixture.publication
	assertions.truthy(publication is RefCounted, "%s fixture seals Farming and EXP publication" % scenario)
	if arm_before_load:
		assertions.truthy(farming.can_arm_harvest_publication(publication), "%s fixture prevalidates publication" % scenario)
		farming.arm_harvest_publication(publication)
	var recorder := ExpSignalRecorder.new()
	event_bus.exp_gained.connect(recorder.on_exp_gained)
	rejecting_grid.reject_next_restore = true

	assertions.truthy(not manager.load_game(BAD_SLOT), "late Grid rejection fails public load with %s" % scenario)
	assertions.equal(game_state.gold, 111, "failed load preserves %s gold" % scenario)
	assertions.equal(game_state.harvest_seed, 707, "failed load restores %s harvest seed" % scenario)
	assertions.equal(game_state.player_state.exp, 4, "failed load preserves silently applied %s EXP" % scenario)
	if arm_before_load:
		farming.publish_harvest_publication(publication)
		assertions.equal(recorder.amounts, [4], "preserved committed barrier publishes harvest EXP exactly once")
	else:
		assertions.truthy(farming.can_arm_harvest_publication(publication), "failed load preserves pre-arm Farming and EXP ownership")
		assertions.truthy(farming.cancel_harvest_publication(publication), "preserved pre-arm publication can still roll back")
		assertions.equal(game_state.player_state.exp, 0, "pre-arm rollback restores EXP exactly")
		assertions.equal(fixture.cell.state, GridCell.State.PLANTED, "pre-arm rollback restores the crop")
		assertions.equal(recorder.amounts, [], "pre-arm rollback publishes no EXP notification")

	event_bus.exp_gained.disconnect(recorder.on_exp_gained)
	_free_pending_harvest(fixture)
	buildings.free()
	rejecting_grid.free()
	manager.free()
	_restore_game_state_scalars(game_state, original)
	_cleanup()


func _test_failed_load_isolates_inventory_grid_restore_notifications(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_cleanup()
	var game_state := tree.root.get_node_or_null("GameState")
	var event_bus := tree.root.get_node_or_null("EventBus")
	assertions.truthy(game_state != null and event_bus != null, "restore isolation failure fixture has core autoloads")
	if game_state == null or event_bus == null:
		return
	var original := _capture_game_state_scalars(game_state)
	var manager := SaveManagerScript.new()
	manager.save_directory = TEST_SAVE_DIR
	var inventory := InventorySystemScript.new()
	var rejecting_grid := RejectingGridRestore.new()
	var buildings := EmptyBuildingRestore.new()
	tree.root.add_child(manager)
	tree.root.add_child(inventory)
	tree.root.add_child(rejecting_grid)
	rejecting_grid.add_to_group("grid_system")
	tree.root.add_child(buildings)
	buildings.add_to_group("building_system")
	inventory.restore_state(
		[{"item_id": "carrot_seed", "quantity": 3}],
		[0, -1, -1, -1, -1, -1]
	)
	game_state.gold = 654
	game_state.harvest_seed = 909
	game_state.player_state.level = 3
	game_state.player_state.exp = 250
	assertions.truthy(manager.save_game(BAD_SLOT), "restore isolation fixture writes a valid later-rejected save")
	inventory.restore_state(
		[{"item_id": "grain_seed", "quantity": 2}],
		[0, -1, -1, -1, -1, -1]
	)
	game_state.gold = 111
	game_state.harvest_seed = 707
	game_state.player_state.level = 1
	game_state.player_state.exp = 0
	var inventory_before := {
		"slots": inventory.slots.duplicate(true),
		"quick_mappings": inventory.quick_slot_mappings.duplicate(),
	}
	var fixture := _prepare_pending_harvest(game_state, event_bus)
	var farming: FarmingSystem = fixture.farming
	var publication: Variant = fixture.publication
	assertions.truthy(farming.can_arm_harvest_publication(publication), "restore isolation fixture prevalidates harvest publication")
	farming.arm_harvest_publication(publication)
	var observer := RestoreNotificationObserver.new()
	observer.game_state = game_state
	observer.inventory = inventory
	observer.grid = rejecting_grid
	observer.mutate_game_state = true
	var exp_recorder := ExpSignalRecorder.new()
	inventory.quick_slot_mapping_changed.connect(observer.on_quick_changed)
	rejecting_grid.navigation_changed.connect(observer.on_navigation_changed)
	event_bus.exp_gained.connect(exp_recorder.on_exp_gained)
	rejecting_grid.reject_next_restore = true

	assertions.truthy(not manager.load_game(BAD_SLOT), "late Grid rejection fails after tentative Inventory restore")
	assertions.equal(observer.quick_events, [], "failed load invokes no tentative or rollback Inventory listener")
	assertions.equal(observer.navigation_events, [], "failed load invokes no tentative or rollback Grid listener")
	assertions.equal(game_state.gold, 111, "failed notification-isolated load preserves gold")
	assertions.equal(game_state.harvest_seed, 707, "failed notification-isolated load restores harvest seed")
	assertions.equal(game_state.player_state.exp, 4, "failed notification-isolated load preserves pending harvest EXP")
	assertions.equal(game_state.player_state.level, 1, "failed notification-isolated load preserves pending harvest level")
	assertions.equal(inventory.slots, inventory_before.slots, "failed load restores exact Inventory slots")
	assertions.equal(inventory.quick_slot_mappings, inventory_before.quick_mappings, "failed load restores exact quick mappings")
	assertions.equal(inventory.get_quick_item(0), "grain_seed", "failed load restores the original effective quick item")
	farming.publish_harvest_publication(publication)
	assertions.equal(exp_recorder.amounts, [4], "surviving harvest barrier publishes exactly one EXP notification")

	inventory.quick_slot_mapping_changed.disconnect(observer.on_quick_changed)
	rejecting_grid.navigation_changed.disconnect(observer.on_navigation_changed)
	event_bus.exp_gained.disconnect(exp_recorder.on_exp_gained)
	_free_pending_harvest(fixture)
	buildings.free()
	rejecting_grid.free()
	inventory.free()
	manager.free()
	_restore_game_state_scalars(game_state, original)
	_cleanup()


func _test_successful_load_publishes_final_inventory_grid_notifications(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_cleanup()
	var game_state := tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "successful restore notification fixture has GameState")
	if game_state == null:
		return
	var original := _capture_game_state_scalars(game_state)
	var manager := SaveManagerScript.new()
	manager.save_directory = TEST_SAVE_DIR
	var inventory := InventorySystemScript.new()
	var grid := RejectingGridRestore.new()
	var buildings := EmptyBuildingRestore.new()
	tree.root.add_child(manager)
	tree.root.add_child(inventory)
	tree.root.add_child(grid)
	grid.add_to_group("grid_system")
	tree.root.add_child(buildings)
	buildings.add_to_group("building_system")
	inventory.restore_state(
		[{"item_id": "carrot_seed", "quantity": 3}],
		[0, -1, -1, -1, -1, -1]
	)
	grid.set_cell_state(2, 2, GridCell.State.FARMLAND)
	game_state.gold = 654
	game_state.harvest_seed = 909
	game_state.player_state.level = 3
	game_state.player_state.exp = 250
	assertions.truthy(manager.save_game(TEST_SLOT), "successful restore notification fixture saves final state")
	inventory.restore_state(
		[{"item_id": "grain_seed", "quantity": 2}],
		[0, -1, -1, -1, -1, -1]
	)
	grid.reset_state()
	game_state.gold = 111
	game_state.harvest_seed = 707
	game_state.player_state.level = 1
	game_state.player_state.exp = 0
	var observer := RestoreNotificationObserver.new()
	observer.game_state = game_state
	observer.inventory = inventory
	observer.grid = grid
	observer.manager = manager
	observer.reentrant_slot = TEST_SLOT
	observer.attempt_reentrant_load = true
	inventory.quick_slot_mapping_changed.connect(observer.on_quick_changed)
	grid.navigation_changed.connect(observer.on_navigation_changed)

	assertions.truthy(manager.load_game(TEST_SLOT), "successful load commits final Inventory and Grid state")
	assertions.equal(observer.quick_events.size(), 1, "successful load emits one coalesced quick-slot notification")
	assertions.equal(observer.navigation_events.size(), 1, "successful load emits one coalesced navigation notification")
	assertions.equal(observer.reentrant_results, [false], "restore publication rejects a nested SaveManager owner")
	for event in observer.quick_events + observer.navigation_events:
		assertions.equal(event.gold, 654, "restore notification sees authoritative loaded gold")
		assertions.equal(event.exp, 250, "restore notification sees authoritative loaded EXP")
		assertions.equal(event.level, 3, "restore notification sees authoritative loaded level")
		assertions.equal(event.quick_item, "carrot_seed", "restore notification sees final quick item")
		assertions.equal(event.cell_state, GridCell.State.FARMLAND, "restore notification sees final Grid state")
	assertions.equal(observer.quick_events[0].item_id, "carrot_seed", "coalesced quick notification carries final item")
	assertions.equal(observer.navigation_events[0].revision, grid.get_navigation_revision(), "coalesced navigation carries final revision")

	inventory.quick_slot_mapping_changed.disconnect(observer.on_quick_changed)
	grid.navigation_changed.disconnect(observer.on_navigation_changed)
	observer.attempt_reentrant_load = false
	assertions.truthy(manager.load_game(TEST_SLOT), "SaveManager accepts the next load after publication closes")
	buildings.free()
	grid.free()
	inventory.free()
	manager.free()
	_restore_game_state_scalars(game_state, original)
	_cleanup()


func _test_successful_load_from_leveling_exp_callback_suppresses_stale_level(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_cleanup()
	var game_state := tree.root.get_node_or_null("GameState")
	var event_bus := tree.root.get_node_or_null("EventBus")
	assertions.truthy(game_state != null and event_bus != null, "EXP callback load fixture has core autoloads")
	if game_state == null or event_bus == null:
		return
	var original := _capture_game_state_scalars(game_state)
	var manager := SaveManagerScript.new()
	manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(manager)
	game_state.gold = 432
	game_state.player_state.stamina = 88
	game_state.player_state.max_stamina = 130
	game_state.player_state.level = 3
	game_state.player_state.exp = 250
	assertions.truthy(manager.save_game(TEST_SLOT), "EXP callback fixture saves authoritative replacement state")
	game_state.gold = 100
	game_state.player_state.stamina = 100
	game_state.player_state.max_stamina = 100
	game_state.player_state.level = 1
	game_state.player_state.exp = 0
	var recorder := ExpSignalRecorder.new()
	var loader := LoadOnExpObserver.new()
	loader.manager = manager
	loader.slot = TEST_SLOT
	event_bus.exp_gained.connect(recorder.on_exp_gained)
	event_bus.level_changed.connect(recorder.on_level_changed)
	event_bus.exp_gained.connect(loader.on_exp_gained)

	assertions.truthy(game_state.add_exp(100), "leveling EXP remains successful when its listener loads")
	assertions.equal(loader.results, [true], "leveling EXP listener completes one successful load")
	assertions.equal(game_state.gold, 432, "callback load keeps authoritative gold")
	assertions.equal(game_state.player_state.exp, 250, "callback load keeps authoritative EXP")
	assertions.equal(game_state.player_state.level, 3, "callback load keeps authoritative level")
	assertions.equal(recorder.timeline, ["exp:100"], "callback load suppresses stale old level notification")

	event_bus.exp_gained.disconnect(loader.on_exp_gained)
	event_bus.level_changed.disconnect(recorder.on_level_changed)
	event_bus.exp_gained.disconnect(recorder.on_exp_gained)
	manager.free()
	_restore_game_state_scalars(game_state, original)
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
	var expected_starter_items := {
		"grain_seed": 99,
		"wood": 99,
		"stone": 99,
		"fiber": 99,
		"plank": 99,
		"stone_brick": 99,
		"brick": 99,
		"charcoal": 99,
		"glass": 99,
		"iron_ingot": 99,
		"rope": 99,
		"steel": 99,
		"wooden_crate": 99,
		"farm_tools": 99,
		"machine_parts": 99,
		"lamp": 99,
	}
	for item_id in expected_starter_items:
		assertions.equal(
			main.inventory_system.get_item_count(item_id),
			expected_starter_items[item_id],
			"new game grants large starter stack for %s" % item_id
		)
	assertions.equal(main.inventory_system.get_item_count("iron"), 0, "new game grants no legacy debug iron")
	assertions.equal(game_state.gold if game_state != null else -1, 50_000, "new game starts with debug-friendly gold")
	main._initial_game_state()
	assertions.equal(main.inventory_system.get_item_count("grain_seed"), 99, "re-entering new-game lifecycle cannot duplicate seeds")
	assertions.equal(main.inventory_system.get_item_count("wood"), 99, "re-entering new-game lifecycle cannot duplicate wood")
	assertions.equal(game_state.gold if game_state != null else -1, 50_000, "re-entering new-game lifecycle preserves exact gold")

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
	var saved_workbench := main.building_system.get_all_buildings()[0] as BuildingInstance
	var saved_workbench_key: String = str(
		main.production_system.building_key(saved_workbench)
	)
	main.production_system.repair_remaining_seconds[saved_workbench_key] = 2.25
	var depleted_resources: Array[Dictionary] = main.world.to_resource_dicts()
	depleted_resources[0]["remaining_units"] = 0
	depleted_resources[0]["respawn_day"] = 7
	depleted_resources[0]["visual_stage"] = 3
	assertions.truthy(
		main.world.restore_resource_dicts(depleted_resources, 4),
		"round-trip fixture depletes a real resource"
	)

	assertions.truthy(manager.save_game(TEST_SLOT), "Task 13 fixture writes real JSON")
	var encoded: Dictionary = _read_json(manager._save_path(TEST_SLOT))
	assertions.equal(encoded.get("economy_version"), 1, "real JSON carries economy version 1")
	assertions.equal(encoded.get("building_layout_version"), 2, "real JSON carries yard layout version 2")
	assertions.equal(encoded.get("last_simulated_day"), 4, "real JSON carries last simulated day")
	assertions.equal(encoded.market.items.wood.history.size(), 2, "real JSON carries complete market history")
	assertions.equal(int(encoded.market.items.wood.stock), main.market_system.get_stock("wood"), "real JSON carries current market stock")
	assertions.equal(int(_npc_state_record(encoded.npc_economy, "lao_li").gold), 321, "real JSON carries NPC wallet")
	assertions.equal(int(_npc_state_record(encoded.npc_economy, "lao_li").inventory.salt), 11, "real JSON carries NPC inventory")
	assertions.equal(encoded.economy_state.contracts.size(), 1, "real JSON carries signed contract")
	assertions.equal(str(encoded.economy_state.contracts[0].contract_id), contract.contract_id, "real JSON preserves contract identity")
	assertions.equal(encoded.buildings[0].producer_state.jobs.size(), 1, "real JSON carries queued producer job")
	assertions.equal(int(encoded.buildings[0].producer_state.outputs.plank), 2, "real JSON carries staged producer output")
	assertions.equal(encoded.buildings[0].occupied_cells.size(), 9, "real JSON carries the complete 3x3 yard footprint")
	assertions.near(
		float(encoded.production_upkeep.repairing[0].remaining_seconds),
		2.25,
		0.001,
		"real JSON carries in-progress repair time"
	)
	assertions.truthy(
		manager._validate_economy_save_data(encoded),
		"yard round-trip economy payload validates before runtime mutation"
	)
	assertions.truthy(
		main.grid_system.validate_dict(encoded.grid),
		"yard round-trip grid payload validates before runtime mutation"
	)
	assertions.truthy(
		main.building_system.validate_restore_buildings(encoded.buildings, encoded.grid),
		"yard round-trip building payload validates before runtime mutation"
	)
	assertions.truthy(
		manager._validate_economy_building_keys(encoded),
		"yard round-trip building economy keys validate before runtime mutation"
	)
	assertions.truthy(
		manager._validate_save_data(encoded),
		"yard round-trip complete payload validates before runtime mutation"
	)
	assertions.equal(encoded.resource_nodes[0].remaining_units, 0, "real JSON carries depleted resource")
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
	assertions.equal(restored.occupied_cells.size(), 9, "load restores every production-yard occupied cell")
	assertions.near(
		main.production_system.get_repair_remaining_seconds(restored),
		2.25,
		0.001,
		"load restores in-progress building repair"
	)
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
	var game_state := tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "atomic resource fixture has GameState")
	if game_state == null:
		manager.free()
		daily.free()
		market.free()
		return
	var original_seed := int(game_state.harvest_seed)
	assertions.truthy(game_state.set_harvest_seed(111), "atomic resource fixture sets prior harvest seed")
	resources.game_state = game_state
	assertions.truthy(market.settle_day(2), "atomic resource fixture creates target market")
	daily.last_simulated_day = 2
	var target_market: Dictionary = market.to_dict()
	var target := {
		"economy_version": 1,
		"market": target_market,
		"last_simulated_day": 2,
		"total_days": 2,
		"harvest_seed": 222,
		"resource_nodes": [{"resource_id": "rock", "hits_remaining": 0}],
	}
	assertions.truthy(market.configure([_wood_definition()]), "atomic resource fixture rewinds market")
	daily.last_simulated_day = 0
	var market_before: Dictionary = market.to_dict()
	var resources_before: Array = resources.to_resource_dicts()
	resources.reject_next_restore = true
	assertions.truthy(not manager._apply_save_data(target), "resource apply failure rejects whole economy snapshot")
	assertions.equal(
		resources.observed_harvest_seeds[0]
		if not resources.observed_harvest_seeds.is_empty()
		else -1,
		222,
		"downstream resource failure occurs after incoming harvest seed applies"
	)
	assertions.equal(game_state.harvest_seed, 111, "resource apply failure restores prior harvest seed")
	assertions.equal(market.to_dict(), market_before, "resource apply failure rolls market back")
	assertions.equal(daily.last_simulated_day, 0, "resource apply failure rolls daily cursor back")
	assertions.equal(resources.to_resource_dicts(), resources_before, "resource apply failure preserves resources")
	assertions.truthy(game_state.set_harvest_seed(original_seed), "atomic resource fixture restores original harvest seed")
	manager.free()
	daily.free()
	market.free()


func _test_greenhouse_restore_finalizes_coverage_and_visuals(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_cleanup()
	var manager := SaveManagerScript.new()
	manager.name = "GreenhouseRestoreSaveManager"
	manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(manager)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.load_save_on_start = false
	main.save_manager = manager
	tree.root.add_child(main)
	var location := _find_restore_location(main, "greenhouse")
	assertions.truthy(location.x >= 0, "greenhouse restore fixture finds a valid location")
	if location.x < 0:
		main.free()
		manager.free()
		_cleanup()
		return
	assertions.equal(
		main.building_system.restore_buildings([_plain_building_record(main, "greenhouse", location)]),
		1,
		"greenhouse restore fixture restores one greenhouse"
	)
	main.production_system.rebuild_registered_buildings()
	var greenhouse := main.building_system.get_all_buildings()[0] as BuildingInstance
	var crop_position := Vector2i(-1, -1)
	for candidate in main.production_system.get_greenhouse_cells(greenhouse):
		if main.grid_system.get_cell(candidate.x, candidate.y) != null:
			crop_position = candidate
			break
	assertions.truthy(crop_position.x >= 0, "greenhouse restore fixture finds a covered crop cell")
	if crop_position.x < 0:
		main.free()
		manager.free()
		_cleanup()
		return
	main.grid_system.set_cell_state(crop_position.x, crop_position.y, GridCell.State.FARMLAND)
	var crop: CropData = tree.root.get_node("GameData").get_crop("lemon")
	assertions.truthy(crop != null and crop.environment == "greenhouse_only", "greenhouse restore fixture uses a greenhouse-only crop")
	var crop_cell: GridCell = main.grid_system.get_cell(crop_position.x, crop_position.y)
	var crop_instance: CropInstance = main.farming_system.plant(crop_cell, crop)
	assertions.truthy(crop_instance != null, "greenhouse restore fixture plants covered crop")
	crop_instance.set_growth_state(1.0, CropInstance.LifecycleState.GROWING)
	main.farming_system.call("_update_visual", crop_cell, crop_instance)
	var saved: Dictionary = manager._gather_save_data().duplicate(true)
	_write_json(manager._save_path(TEST_SLOT), saved)
	main.farming_system.clear_visuals()
	assertions.equal(main.farming_system.get_visual_count(), 0, "runtime load fixture starts without crop visuals")
	assertions.truthy(manager.load_game(TEST_SLOT), "runtime greenhouse load succeeds")
	crop_cell = main.grid_system.get_cell(crop_position.x, crop_position.y)
	var loaded_visual: Node3D = main.farming_system.get_crop_visual(crop_cell)
	assertions.truthy(loaded_visual != null, "successful runtime load rebuilds greenhouse crop visuals")
	if loaded_visual == null:
		main.farming_system.rebuild_visuals()
		loaded_visual = main.farming_system.get_crop_visual(crop_cell)
	assertions.equal(loaded_visual.get_meta("crop_id", ""), "lemon", "runtime load rebuilds the correct crop visual")
	assertions.equal(loaded_visual.get_meta("lifecycle_state", -1), CropInstance.LifecycleState.GROWING, "runtime load visual matches restored lifecycle")
	assertions.truthy(main.farming_system.is_greenhouse_cell(crop_cell), "runtime load finalizes active greenhouse coverage")

	var before_snapshot: Dictionary = main.grid_system.get_crop_snapshot(crop_position.x, crop_position.y)
	var before_visual: Node3D = loaded_visual
	var rejected: Dictionary = manager._gather_save_data().duplicate(true)
	for maintenance_value in rejected.production_upkeep.maintenance:
		var maintenance := maintenance_value as Dictionary
		maintenance["due_day"] = 0
	var resources := RejectingResourceWorld.new()
	resources.game_state = tree.root.get_node("GameState")
	resources.reject_next_restore = true
	manager._resource_world = resources
	rejected["resource_nodes"] = [{"resource_id": "rock", "hits_remaining": 0}]
	assertions.truthy(not manager._apply_save_data(rejected), "downstream failure rolls greenhouse restore back")
	crop_cell = main.grid_system.get_cell(crop_position.x, crop_position.y)
	assertions.equal(main.grid_system.get_crop_snapshot(crop_position.x, crop_position.y), before_snapshot, "failed restore preserves complete greenhouse crop data")
	assertions.equal(crop_cell.crop_instance.lifecycle_state, CropInstance.LifecycleState.GROWING, "failed restore preserves greenhouse crop lifecycle")
	assertions.truthy(main.farming_system.is_greenhouse_cell(crop_cell), "failed restore restores active greenhouse coverage")
	assertions.truthy(not main.farming_system.is_paused_greenhouse_cell(crop_cell), "failed restore removes intermediate paused coverage")
	var rolled_back_visual: Node3D = main.farming_system.get_crop_visual(crop_cell)
	assertions.truthy(rolled_back_visual != null, "failed restore rebuilds the rolled-back crop visual")
	assertions.truthy(rolled_back_visual != before_visual, "failed restore replaces any intermediate crop visual")
	assertions.equal(rolled_back_visual.get_meta("crop_id", ""), "lemon", "failed restore visual matches rolled-back crop identity")
	assertions.equal(rolled_back_visual.get_meta("lifecycle_state", -1), CropInstance.LifecycleState.GROWING, "failed restore visual matches rolled-back lifecycle")
	main.free()
	manager.free()
	_cleanup()


func _test_load_cancels_transient_gathering_before_commit(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var market := MarketSystemScript.new()
	var daily := DailySimulationSystem.new()
	var manager := SaveManagerScript.new()
	var owner := StateTransitionOwnerDouble.new()
	tree.root.add_child(market)
	tree.root.add_child(daily)
	tree.root.add_child(manager)
	assertions.truthy(market.configure([_wood_definition()]), "load-cancel fixture configures market")
	assertions.truthy(
		manager.configure_economy(
			market, daily, null, null, null, null, null, null, null, null, owner
		),
		"save manager accepts a transient-action owner"
	)
	var payload: Dictionary = manager._gather_save_data().duplicate(true)
	assertions.truthy(manager._apply_save_data(payload), "valid payload applies after cancellation")
	assertions.equal(
		owner.reasons,
		["save_restore"],
		"load cancels movement and animation before applying state"
	)
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


func _test_task13_invalid_top_level_and_inventory_schema_is_atomic(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	for scenario in [
		"negative_gold",
		"fractional_gold",
		"player_wrong_type",
		"player_nonfinite",
		"missing_gold",
		"missing_player",
		"inventory_wrong_type",
		"missing_inventory",
		"unknown_item",
		"negative_quantity",
		"zero_quantity",
		"over_max_stack",
		"over_max_slots",
		"duplicate_underfilled_stack",
		"malformed_stack",
		"invalid_quick_index",
		"quick_mapping_to_empty_slot",
		"grid_cells_wrong_type",
		"malformed_grid_entry",
		"duplicate_grid_cell",
		"invalid_grid_state",
		"watered_wrong_type",
		"crop_wrong_type",
		"unknown_crop",
		"crop_negative_progress",
		"crop_nonfinite_progress",
		"crop_progress_past_growth",
		"crop_fractional_harvest_count",
		"crop_watered_wrong_type",
		"crop_extra_stage_field",
		"crop_on_non_planted_cell",
		"planted_cell_without_crop",
		"missing_buildings",
		"orphan_building_cell",
		"missing_building_layout_version",
		"negative_building_layout_version",
		"fractional_building_layout_version",
		"wrong_building_layout_version",
	]:
		_test_task13_invalid_schema_case(assertions, tree, scenario)


func _test_task13_invalid_schema_case(
	assertions: TestAssert,
	tree: SceneTree,
	scenario: String
) -> void:
	_cleanup()
	var manager := SaveManagerScript.new()
	manager.name = "Task13SchemaSaveManager"
	manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(manager)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.load_save_on_start = false
	main.save_manager = manager
	tree.root.add_child(main)
	var game_state := tree.root.get_node_or_null("GameState")
	var location := _find_restore_location(main, "workbench")
	assertions.equal(
		main.building_system.restore_buildings([_producer_building_record(main, location)]),
		1,
		"%s fixture restores a producer" % scenario
	)
	main.production_system.register_existing_buildings()
	main.inventory_system.restore_state(
		[{"item_id": "grain_seed", "quantity": 7}, {"item_id": "wood", "quantity": 9}],
		[1, 0, -1, -1, -1, -1]
	)
	game_state.gold = 211
	manager.current_slot = TEST_SLOT
	var before := _capture_atomic_load_state(main, manager, game_state)
	var incoming: Dictionary = JSON.parse_string(JSON.stringify(manager._gather_save_data()))
	_mutate_invalid_schema_payload(incoming, scenario)
	_write_json(manager._save_path(BAD_SLOT), incoming)

	assertions.truthy(not manager.load_game(BAD_SLOT), "%s rejects real JSON" % scenario)
	assertions.equal(manager.current_slot, TEST_SLOT, "%s preserves current slot" % scenario)
	_assert_atomic_load_state(assertions, main, manager, game_state, before, scenario)
	main.free()
	manager.free()
	_cleanup()


func _mutate_invalid_schema_payload(payload: Dictionary, scenario: String) -> void:
	match scenario:
		"negative_gold":
			payload.gold = -1
		"fractional_gold":
			payload.gold = 1.5
		"player_wrong_type":
			payload.player = "invalid"
		"player_nonfinite":
			payload.player.stamina = INF
		"missing_gold":
			payload.erase("gold")
		"missing_building_layout_version":
			payload.erase("building_layout_version")
		"negative_building_layout_version":
			payload.building_layout_version = -1
		"fractional_building_layout_version":
			payload.building_layout_version = 2.5
		"wrong_building_layout_version":
			payload.building_layout_version = 1
		"missing_player":
			payload.erase("player")
		"inventory_wrong_type":
			payload.inventory = []
		"missing_inventory":
			payload.erase("inventory")
		"unknown_item":
			payload.inventory.slots[0] = {"item_id": "missing_item", "quantity": 1}
		"negative_quantity":
			payload.inventory.slots[0].quantity = -1
		"zero_quantity":
			payload.inventory.slots[0].quantity = 0
		"over_max_stack":
			payload.inventory.slots[0] = {"item_id": "moonflower", "quantity": 2}
		"over_max_slots":
			payload.inventory.slots.append({})
		"duplicate_underfilled_stack":
			payload.inventory.slots[0] = {"item_id": "wood", "quantity": 1}
			payload.inventory.slots[1] = {"item_id": "wood", "quantity": 1}
		"malformed_stack":
			payload.inventory.slots[0] = "invalid"
		"invalid_quick_index":
			payload.inventory.quick_mappings[0] = 999
		"quick_mapping_to_empty_slot":
			payload.inventory.quick_mappings[0] = payload.inventory.slots.size() - 1
		"grid_cells_wrong_type":
			payload.grid.cells = {}
		"malformed_grid_entry":
			payload.grid.cells.append("invalid")
		"duplicate_grid_cell":
			payload.grid.cells.append(payload.grid.cells[0].duplicate(true))
		"invalid_grid_state":
			payload.grid.cells.append({"gx": 1, "gz": 0, "state": 999, "watered": false})
		"watered_wrong_type":
			payload.grid.cells.append({"gx": 1, "gz": 0, "state": GridCell.State.FARMLAND, "watered": "yes"})
		"crop_wrong_type":
			var entry := _valid_crop_grid_entry()
			entry.crop = "invalid"
			payload.grid.cells.append(entry)
		"unknown_crop":
			var entry := _valid_crop_grid_entry()
			entry.crop.crop_id = "missing_crop"
			payload.grid.cells.append(entry)
		"crop_negative_progress":
			var entry := _valid_crop_grid_entry()
			entry.crop.growth_progress = -1
			payload.grid.cells.append(entry)
		"crop_nonfinite_progress":
			var entry := _valid_crop_grid_entry()
			entry.crop.growth_progress = INF
			payload.grid.cells.append(entry)
		"crop_progress_past_growth":
			var entry := _valid_crop_grid_entry()
			entry.crop.growth_progress = 999
			payload.grid.cells.append(entry)
		"crop_fractional_harvest_count":
			var entry := _valid_crop_grid_entry()
			entry.crop.harvest_count = 1.5
			payload.grid.cells.append(entry)
		"crop_watered_wrong_type":
			var entry := _valid_crop_grid_entry()
			entry.crop.is_watered_today = "yes"
			payload.grid.cells.append(entry)
		"crop_extra_stage_field":
			var entry := _valid_crop_grid_entry()
			entry.crop.growth_stage = 99
			payload.grid.cells.append(entry)
		"crop_on_non_planted_cell":
			var entry := _valid_crop_grid_entry()
			entry.state = GridCell.State.FARMLAND
			payload.grid.cells.append(entry)
		"planted_cell_without_crop":
			payload.grid.cells.append({"gx": 1, "gz": 0, "state": GridCell.State.PLANTED, "watered": false})
		"missing_buildings":
			payload.erase("buildings")
		"orphan_building_cell":
			payload.grid.cells.append({"gx": 1, "gz": 0, "state": GridCell.State.BUILDING, "watered": false})


func _valid_crop_grid_entry() -> Dictionary:
	return {
		"gx": 1,
		"gz": 0,
		"state": GridCell.State.PLANTED,
		"watered": true,
		"crop": {
			"crop_id": "grain",
			"growth_progress": 1,
			"is_watered_today": true,
			"harvest_count": 0,
			"lifecycle_state": CropInstance.LifecycleState.GROWING,
		},
	}


func _test_task13_legacy_inventory_repack_preserves_quick_items(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_cleanup()
	var manager := SaveManagerScript.new()
	manager.name = "Task13LegacyRepackSaveManager"
	manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(manager)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.load_save_on_start = false
	main.save_manager = manager
	tree.root.add_child(main)
	var slots: Array[Dictionary] = [{"item_id": "iron_ingot", "quantity": 8}]
	while slots.size() < main.inventory_system.max_slots - 1:
		slots.append({})
	slots.append({"item_id": "iron", "quantity": 5})
	_write_json(manager._save_path(TEST_SLOT), {
		"total_days": 3,
		"inventory": {
			"slots": slots,
			"quick_mappings": [slots.size() - 1, 0, -1, -1, -1, -1],
		},
	})
	assertions.truthy(manager.load_game(TEST_SLOT), "legacy inventory repacks migrated iron")
	assertions.equal(main.inventory_system.get_item_count("iron"), 0, "legacy repack removes iron")
	assertions.equal(main.inventory_system.get_item_count("iron_ingot"), 13, "legacy repack preserves total quantity")
	assertions.equal(main.inventory_system.get_quick_item(0), "iron_ingot", "moved legacy quick item follows migrated stack")
	assertions.equal(main.inventory_system.get_quick_item(1), "iron_ingot", "existing target quick item remains mapped")
	assertions.equal(main.inventory_system.quick_slot_mappings[0], 0, "legacy source quick index relocates deterministically")
	main.free()
	manager.free()
	_cleanup()


func _test_task13_building_load_signals_are_transactional(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	_cleanup()
	var manager := SaveManagerScript.new()
	manager.name = "Task13SilentBuildingSaveManager"
	manager.save_directory = TEST_SAVE_DIR
	tree.root.add_child(manager)
	var registry_observer := RegistryLoadObserver.new()
	manager.load_completed.connect(registry_observer.on_load_completed)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.load_save_on_start = false
	main.save_manager = manager
	tree.root.add_child(main)
	registry_observer.main = main
	var game_state := tree.root.get_node_or_null("GameState")
	var location := _find_restore_location(main, "workbench")
	assertions.equal(
		main.building_system.restore_buildings([_producer_building_record(main, location)]),
		1,
		"silent load fixture restores existing producer"
	)
	main.production_system.register_existing_buildings()
	manager.current_slot = TEST_SLOT
	var before := _capture_atomic_load_state(main, manager, game_state)
	var valid_payload: Dictionary = manager._gather_save_data().duplicate(true)
	var invalid_payload: Dictionary = valid_payload.duplicate(true)
	invalid_payload.buildings.append((invalid_payload.buildings[0] as Dictionary).duplicate(true))
	var observer := BuildingSignalObserver.new()
	var event_bus := tree.root.get_node_or_null("EventBus")
	main.building_system.building_removed.connect(observer.on_local_removed)
	main.building_system.building_instance_placed.connect(observer.on_local_placed)
	event_bus.building_removed.connect(observer.on_bus_removed)
	event_bus.building_placed.connect(observer.on_bus_placed)

	_write_json(manager._save_path(BAD_SLOT), invalid_payload)
	assertions.truthy(not manager.load_game(BAD_SLOT), "invalid second building rejects before commit")
	_assert_no_public_building_signals(assertions, observer, "failed building load")
	_assert_atomic_load_state(assertions, main, manager, game_state, before, "failed building load")

	observer.reset()
	var load_observer := LoadObserver.new(manager)
	manager.load_completed.connect(load_observer.on_load_completed)
	_write_json(manager._save_path(BAD_SLOT), valid_payload)
	assertions.truthy(manager.load_game(BAD_SLOT), "valid building load commits")
	assertions.equal(load_observer.calls, 1, "successful building load emits one load completion")
	_assert_no_public_building_signals(assertions, observer, "successful building load")
	assertions.equal(
		_serialize_registered_producers(main),
		before.registered_producers,
		"successful silent building load rebuilds producer registry"
	)
	assertions.equal(
		registry_observer.observed_producers,
		before.registered_producers,
		"early load observer sees rebuilt producer registry"
	)
	main.free()
	manager.free()
	_cleanup()


func _assert_no_public_building_signals(
	assertions: TestAssert,
	observer: BuildingSignalObserver,
	scenario: String
) -> void:
	assertions.equal(observer.local_removed, 0, "%s emits no BuildingSystem removal" % scenario)
	assertions.equal(observer.local_placed, 0, "%s emits no BuildingSystem placement" % scenario)
	assertions.equal(observer.bus_removed, 0, "%s emits no EventBus removal" % scenario)
	assertions.equal(observer.bus_placed, 0, "%s emits no EventBus placement" % scenario)


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
	assertions.truthy(
		not incoming.buildings.is_empty(),
		"%s fixture serializes its queued producer" % scenario
	)
	if incoming.buildings.is_empty():
		main.free()
		manager.free()
		_cleanup()
		return
	assertions.equal(
		str(incoming.buildings[0].get("building_id", "")),
		"workbench",
		"%s fixture serializes the owned building system" % scenario
	)
	var incoming_jobs: Array = incoming.buildings[0].get("producer_state", {}).get("jobs", [])
	assertions.truthy(
		not incoming_jobs.is_empty(),
		"%s fixture serializes the queued production job" % scenario
	)
	if incoming_jobs.is_empty():
		main.free()
		manager.free()
		_cleanup()
		return
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
	var migration_location := _find_restore_location(main, "lumberyard")
	assertions.truthy(migration_location.x >= 0, "v1 migration finds a lumberyard footprint")
	var version_one_save := main_save.duplicate(true)
	version_one_save.progression = {
		"version": 1,
		"unlocked_blueprints": ["workbench", "stone_kiln", "beehive"],
		"unlocked_recipes": ["plank", "rope", "charcoal", "stone_brick", "brick"],
		"upgrade_levels": [],
	}
	version_one_save.buildings = [_plain_building_record(main, "lumberyard", migration_location)]
	var migration_inventory: Dictionary = version_one_save.inventory.duplicate(true)
	assertions.truthy(manager._apply_save_data(version_one_save), "version-one save with placed lumberyard loads")
	assertions.equal(main.inventory_system.slots, migration_inventory.slots, "v1 migration preserves inventory")
	assertions.equal(main.building_system.get_building_count(), 1, "v1 migration preserves placed buildings")
	assertions.truthy(
		main.economy_progression_system.is_blueprint_unlocked("lumberyard"),
		"v1 migration reconciles the placed lumberyard blueprint"
	)
	assertions.equal(main.economy_progression_system.to_dict().version, 2, "v1 runtime migration adopts progression v2")
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
	persisted.pending_caravan_departures = [{
		"caravan_id": "lao_li_emergency_import",
		"item_id": "wood",
		"quantity": 4,
		"departure_day": 5,
	}]
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
		if int(resource.remaining_units) > 1:
			resource.remaining_units = int(resource.remaining_units) - 1
			var remaining := int(resource.remaining_units)
			var capacity := int(resource.max_units)
			resource.visual_stage = 0 if remaining >= capacity else (1 if remaining * 3 > capacity else 2)
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
		"harvest_seed": game_state.harvest_seed,
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
		"harvest_seed",
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
		"remaining_minutes": int(RecipeDatabaseScript.get_recipe("plank").duration_minutes),
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


func _plain_building_record(main: Node, building_id: String, location: Vector2i) -> Dictionary:
	if location.x < 0:
		return {}
	var definition: Dictionary = GameDataScript.get_building(building_id)
	var occupied_cells: Array[Dictionary] = []
	for z in range(location.y, location.y + int(definition.get("footprint_z", 1))):
		for x in range(location.x, location.x + int(definition.get("footprint_x", 1))):
			var cell: GridCell = main.grid_system.get_cell(x, z)
			occupied_cells.append({"gx": x, "gz": z, "previous_state": int(cell.state)})
	return {
		"building_id": building_id,
		"gx": location.x,
		"gz": location.y,
		"occupied_cells": occupied_cells,
	}


func _wood_definition() -> Dictionary:
	return {
		"id": "wood",
		"base_price": 100,
		"initial_stock": 10,
		"target_stock": 10,
		"daily_liquidity": 10,
	}


func _legacy_wood_definition() -> Dictionary:
	return {
		"id": "wood",
		"base_price": 3,
		"initial_stock": 10,
		"target_stock": 6,
		"daily_liquidity": 4,
	}


func _current_migrated_wood_definition() -> Dictionary:
	return {
		"id": "wood",
		"base_price": 14,
		"initial_stock": 60,
		"target_stock": 80,
		"daily_liquidity": 10,
	}


func _crate_definition() -> Dictionary:
	return {
		"id": "crate",
		"base_price": 50,
		"initial_stock": 3,
		"target_stock": 8,
		"daily_liquidity": 5,
	}


func _expected_crate_default_state() -> Dictionary:
	return {
		"item_id": "crate",
		"base_price": 50,
		"mid_price": 50,
		"stock": 3,
		"target_stock": 8,
		"daily_liquidity": 5,
		"demand": 0,
		"supply": 0,
		"history": [50],
	}


func _npc_state_record(snapshot: Dictionary, npc_id: String) -> Dictionary:
	for state_value in snapshot.get("npc_states", []):
		if state_value is Dictionary and str(state_value.get("npc_id", "")) == npc_id:
			return state_value
	return {}


func _set_npc_snapshot_day(snapshot: Dictionary, total_day: int) -> void:
	snapshot["last_simulated_day"] = total_day
	if snapshot.has("pending_caravan_departures"):
		snapshot["pending_caravan_departures"] = []
	for state_value in snapshot.get("npc_states", []):
		if state_value is Dictionary:
			state_value["last_simulated_day"] = total_day


func _prepare_pending_harvest(game_state: Node, event_bus: Node) -> Dictionary:
	var grid := GridSystemScript.new()
	grid._event_bus = event_bus
	var farming := FarmingSystemScript.new()
	farming.configure(grid, null, game_state)
	farming._event_bus = event_bus
	var crop := CropDataScript.new()
	crop.crop_id = "grain"
	crop.growth_days = 3
	crop.yield_min = 1
	crop.yield_max = 1
	crop.exp_reward = 4
	crop.lifecycle_type = "annual"
	grid.set_cell_state(13, 13, GridCell.State.FARMLAND)
	var cell := grid.get_cell(13, 13)
	var instance: CropInstance = farming.plant(cell, crop)
	instance.set_growth_state(3.0, CropInstance.LifecycleState.MATURE)
	var preview := farming.preview_harvest(cell)
	var token := farming.prepare_harvest(cell, preview)
	if token == null or not farming.apply_prepared_harvest(token):
		return {"grid": grid, "farming": farming, "cell": cell, "publication": null}
	return {
		"grid": grid,
		"farming": farming,
		"cell": cell,
		"publication": farming.seal_prepared_harvest(token),
	}


func _free_pending_harvest(fixture: Dictionary) -> void:
	var farming: Variant = fixture.get("farming")
	if farming != null and is_instance_valid(farming):
		farming.free()
	var grid: Variant = fixture.get("grid")
	if grid != null and is_instance_valid(grid):
		grid.free()


func _capture_game_state_scalars(game_state: Node) -> Dictionary:
	return {
		"gold": game_state.gold,
		"harvest_seed": game_state.harvest_seed,
		"stamina": game_state.player_state.stamina,
		"max_stamina": game_state.player_state.max_stamina,
		"level": game_state.player_state.level,
		"exp": game_state.player_state.exp,
	}


func _restore_game_state_scalars(game_state: Node, snapshot: Dictionary) -> void:
	game_state.invalidate_exp_state_for_replacement()
	game_state.gold = int(snapshot.gold)
	game_state.harvest_seed = int(snapshot.harvest_seed)
	game_state.player_state.stamina = int(snapshot.stamina)
	game_state.player_state.max_stamina = int(snapshot.max_stamina)
	game_state.player_state.level = int(snapshot.level)
	game_state.player_state.exp = int(snapshot.exp)


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
