extends RefCounted

const ProgressionScript = preload("res://scripts/systems/economy_progression_system.gd")
const ToolSystemScript = preload("res://scripts/systems/tool_system.gd")
const ProductionSystemScript = preload("res://scripts/systems/production_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const ProducerStateScript = preload("res://scripts/data/producer_state.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const BuildingCatalogScript = preload("res://scripts/core/building_catalog.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")


class DaySource:
	extends RefCounted
	var total_days := 1


class DailySource:
	extends Node
	var last_simulated_day := 0


class GridDouble:
	extends RefCounted

	func set_cell_state(gx: int, gz: int, next_state: int) -> bool:
		return gx >= 0 and gz >= 0 and next_state == GridCell.State.FARMLAND

	func water_cell(_gx: int, _gz: int) -> bool:
		return false


class GoldCounter:
	extends RefCounted
	var count := 0
	var last_gold := -1

	func record(value: int) -> void:
		count += 1
		last_gold = value


class PlayerDouble:
	extends RefCounted
	var level := 2


class RejectingWallet:
	extends Node
	var gold := 1000
	var player_state := PlayerDouble.new()

	func spend_gold(_amount: int) -> bool:
		return false

	func add_gold(amount: int) -> bool:
		gold += amount
		return true


class ItemSignalCounter:
	extends RefCounted
	var count := 0

	func record(_item_id: String, _quantity: int) -> void:
		count += 1


class PurchaseReentryObserver:
	extends RefCounted
	var progression: Variant
	var attempted := false
	var nested_result := true

	func on_gold(_value: int) -> void:
		if attempted:
			return
		attempted = true
		nested_result = bool(progression.purchase("blueprint_windmill"))


class UpgradeRemovalObserver:
	extends RefCounted
	var production: Variant
	var building: BuildingInstance
	var attempted := false

	func on_gold(_value: int) -> void:
		if attempted:
			return
		attempted = true
		production.unregister_building(building)


class MaintenanceReentryObserver:
	extends RefCounted
	var production: Variant
	var building: BuildingInstance
	var wallet: Variant
	var inventory: InventorySystem
	var attempted := false
	var nested_result := true

	func on_gold(_value: int) -> void:
		if attempted:
			return
		attempted = true
		nested_result = bool(production.maintain(building, wallet, inventory))


var _owned_nodes: Array[Node] = []


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var wallet := tree.root.get_node_or_null("GameState")
	assertions.truthy(wallet != null, "progression tests find authoritative wallet")
	if wallet == null:
		return
	var original_gold := int(wallet.gold)
	var original_level := int(wallet.player_state.level)
	var original_stamina := int(wallet.player_state.stamina)
	_test_unlock_gates_and_strict_state(assertions, wallet)
	_test_debug_gate_unlocks(assertions, wallet)
	_test_complete_unlock_routes_and_v1_migration(assertions)
	_test_tool_durability_and_atomic_repair(assertions, wallet)
	_test_failed_service_transactions_are_signal_atomic(assertions)
	_test_service_transactions_reject_signal_reentry(assertions, wallet)
	_test_maintenance_and_upgrades(assertions, wallet)
	_test_save_json_round_trip_atomic_rejection_and_legacy(assertions, wallet)
	wallet.gold = original_gold
	wallet.player_state.level = original_level
	wallet.player_state.stamina = original_stamina
	_cleanup_nodes()


func _test_unlock_gates_and_strict_state(assertions: TestAssert, wallet: Node) -> void:
	var inventory := _inventory()
	var tool := _tool(inventory)
	var production := _production()
	var day := DaySource.new()
	var progression = _track(ProgressionScript.new())
	assertions.truthy(
		progression.configure(tool, production, inventory, day, wallet),
		"progression configures authoritative dependencies"
	)
	for id in ["workbench", "stone_kiln", "beehive", "well", "fence"]:
		assertions.truthy(progression.is_blueprint_unlocked(id), "tier zero unlocks %s" % id)
	for id in ["barn", "windmill", "chicken_coop", "waterwheel", "furnace", "lumberyard", "quarry", "lamp"]:
		assertions.truthy(not progression.is_blueprint_unlocked(id), "tier one locks %s" % id)
	for id in ["greenhouse", "mine", "textile_machine", "food_workshop"]:
		assertions.truthy(not progression.is_blueprint_unlocked(id), "tier two locks %s" % id)
	for recipe_id in ["plank", "rope", "charcoal", "stone_brick", "brick"]:
		assertions.truthy(progression.is_recipe_unlocked(recipe_id), "tier zero exposes %s" % recipe_id)
	var locked_windmill := _building("windmill", 11, 12)
	production.register_building(locked_windmill)
	production.sync_daily_cursor(1)
	inventory.add_item("grain", 2)
	var locked_preflight: Dictionary = production.preflight_recipe(locked_windmill, "flour", 1, inventory)
	assertions.equal(locked_preflight.reason, "recipe_locked", "production enforces progression recipe lock")
	var grain_before_locked := inventory.get_item_count("grain")
	assertions.truthy(not production.start_recipe(locked_windmill, "flour", 1, inventory), "locked recipe cannot start")
	assertions.equal(inventory.get_item_count("grain"), grain_before_locked, "locked recipe consumes no input")

	wallet.gold = 2000
	wallet.player_state.level = 1
	var before_gate := _asset_snapshot(wallet, inventory)
	assertions.truthy(not progression.purchase("blueprint_windmill"), "day and level gate reject early blueprint")
	_assert_assets(assertions, before_gate, wallet, inventory, "early blueprint")
	day.total_days = 8
	assertions.truthy(not progression.purchase("blueprint_windmill"), "level gate remains authoritative")
	_assert_assets(assertions, before_gate, wallet, inventory, "level-gated blueprint")
	wallet.player_state.level = 2
	var service: Dictionary = _service(progression, "blueprint_windmill")
	_give_cost(inventory, service.get("materials", {}))
	var before_purchase := _asset_snapshot(wallet, inventory)
	assertions.truthy(progression.purchase("blueprint_windmill"), "eligible blueprint purchase succeeds")
	assertions.equal(
		int(wallet.gold),
		int(before_purchase.gold) - int(service.gold_cost),
		"blueprint deducts exact gold once"
	)
	_assert_material_delta(assertions, before_purchase, inventory, service.materials, "blueprint")
	assertions.truthy(progression.is_blueprint_unlocked("windmill"), "purchase owns windmill")
	assertions.truthy(progression.is_recipe_unlocked("flour"), "windmill purchase exposes station recipe")
	assertions.truthy(
		bool(production.preflight_recipe(locked_windmill, "flour", 1, inventory).ok),
		"purchased blueprint unlocks production preflight"
	)
	var after_purchase := _asset_snapshot(wallet, inventory)
	assertions.truthy(not progression.purchase("blueprint_windmill"), "owned blueprint cannot repurchase")
	_assert_assets(assertions, after_purchase, wallet, inventory, "owned blueprint")

	var saved: Dictionary = progression.to_dict()
	var restored = _track(ProgressionScript.new())
	assertions.truthy(restored.from_dict(saved), "progression strict state round trips")
	assertions.equal(restored.to_dict(), saved, "progression round trip is exact")
	var before_bad: Dictionary = restored.to_dict()
	var duplicate := saved.duplicate(true)
	duplicate.unlocked_blueprints.append(duplicate.unlocked_blueprints[0])
	assertions.truthy(not restored.from_dict(duplicate), "duplicate blueprint rejects whole payload")
	assertions.equal(restored.to_dict(), before_bad, "duplicate rejection has no pollution")
	var unknown := saved.duplicate(true)
	unknown.unlocked_recipes.append("unknown_recipe")
	assertions.truthy(not restored.from_dict(unknown), "unknown recipe rejects whole payload")
	assertions.equal(restored.to_dict(), before_bad, "unknown rejection has no pollution")
	var bad_level := saved.duplicate(true)
	bad_level.upgrade_levels = [{
		"building_key": "windmill:3:4",
		"levels": [{"upgrade_id": "speed", "level": 99}],
	}]
	assertions.truthy(not restored.from_dict(bad_level), "out-of-range upgrade rejects whole payload")
	assertions.equal(restored.to_dict(), before_bad, "range rejection has no pollution")
	var noncanonical := saved.duplicate(true)
	noncanonical.upgrade_levels = [{
		"building_key": "windmill:03:4",
		"levels": [{"upgrade_id": "speed", "level": 1}],
	}]
	assertions.truthy(not restored.from_dict(noncanonical), "non-canonical building key rejects")
	var missing_tier_zero_recipe := saved.duplicate(true)
	missing_tier_zero_recipe.unlocked_recipes.erase("plank")
	assertions.truthy(not restored.from_dict(missing_tier_zero_recipe), "missing tier-zero recipe rejects")
	var recipe_without_station := saved.duplicate(true)
	recipe_without_station.unlocked_recipes.append("flour")
	assertions.truthy(not restored.from_dict(recipe_without_station), "recipe without unlocked station blueprint rejects")
	var unobtainable_high_tier := saved.duplicate(true)
	unobtainable_high_tier.unlocked_recipes.append("perfume")
	assertions.truthy(not restored.from_dict(unobtainable_high_tier), "recipe without its locked station rejects")
	assertions.equal(restored.to_dict(), before_bad, "unobtainable recipe rejection is atomic")


func _test_debug_gate_unlocks(assertions: TestAssert, wallet: Node) -> void:
	var inventory := _inventory()
	var tool := _tool(inventory)
	var production := _production()
	var day := DaySource.new()
	var progression = _track(ProgressionScript.new())
	assertions.truthy(
		progression.configure(tool, production, inventory, day, wallet),
		"debug unlock fixture configures progression"
	)
	wallet.player_state.level = 2
	day.total_days = 7
	var before_gate: Dictionary = progression.debug_unlock_gate_eligible_blueprints()
	assertions.equal(before_gate.blueprints, [], "debug unlock preserves blueprints before the day gate")
	assertions.truthy(not progression.is_blueprint_unlocked("barn"), "debug unlock respects the day gate")

	day.total_days = 8
	var tier_one: Dictionary = progression.debug_unlock_gate_eligible_blueprints()
	assertions.truthy(bool(tier_one.ok), "debug unlock grants eligible tier-one progression")
	assertions.equal(tier_one.blueprints.size(), 8, "debug unlock grants every tier-one blueprint")
	assertions.truthy(progression.is_blueprint_unlocked("barn"), "debug unlock owns the barn blueprint")
	assertions.truthy(progression.is_recipe_unlocked("flour"), "debug unlock grants blueprint tier recipes")
	assertions.truthy(not progression.is_blueprint_unlocked("greenhouse"), "debug unlock keeps tier two gated")
	var repeated: Dictionary = progression.debug_unlock_gate_eligible_blueprints()
	assertions.equal(repeated.blueprints, [], "debug unlock is idempotent")

	wallet.player_state.level = 1
	day.total_days = 1
	progression.debug_unlock_gate_eligible_blueprints()
	assertions.truthy(progression.is_blueprint_unlocked("barn"), "lower debug values do not relock ownership")


func _test_complete_unlock_routes_and_v1_migration(assertions: TestAssert) -> void:
	var progression = _track(ProgressionScript.new())
	for method_name in [
		"get_blueprint_service_id", "get_recipe_service_id", "get_blueprint_lock_info",
		"can_eventually_unlock_recipe", "reconcile_placed_buildings",
	]:
		assertions.truthy(progression.has_method(method_name), "progression exposes %s" % method_name)
	for building_id in BuildingCatalogScript.all_building_ids():
		assertions.truthy(
			progression.is_blueprint_managed(building_id),
			"%s has explicit progression" % building_id
		)
	if progression.has_method("get_blueprint_service_id"):
		assertions.equal(
			progression.call("get_blueprint_service_id", "lumberyard"),
			"blueprint_lumberyard",
			"lumberyard service is addressable"
		)
		assertions.equal(
			progression.call("get_blueprint_service_id", "food_workshop"),
			"blueprint_food_workshop",
			"food workshop service is addressable"
		)
	if progression.has_method("get_recipe_service_id"):
		assertions.equal(
			progression.call("get_recipe_service_id", "machine_parts"),
			"recipe_machine_parts",
			"machine parts service is addressable"
		)
	if progression.has_method("can_eventually_unlock_recipe"):
		for recipe in RecipeDatabaseScript.get_all_recipes():
			assertions.truthy(
				progression.call("can_eventually_unlock_recipe", str(recipe.id)),
				"%s is reachable" % recipe.id
			)
	var version_one := {
		"version": 1,
		"unlocked_blueprints": ["workbench", "stone_kiln", "beehive"],
		"unlocked_recipes": ["plank", "rope", "charcoal", "stone_brick", "brick"],
		"upgrade_levels": [],
	}
	assertions.truthy(progression.from_dict(version_one), "version-one progression migrates")
	for building_id in ["workbench", "stone_kiln", "beehive", "well", "fence"]:
		assertions.truthy(
			progression.is_blueprint_unlocked(building_id),
			"version-one migration adds tier-zero %s" % building_id
		)
	assertions.equal(progression.to_dict().version, 2, "migrated progression writes version two")
	var future_version: Dictionary = progression.to_dict()
	future_version.version = 3
	assertions.truthy(not progression.from_dict(future_version), "future progression version rejects")
	if progression.has_method("reconcile_placed_buildings"):
		var lumberyard := _building("lumberyard", 17, 18)
		assertions.equal(
			progression.call("reconcile_placed_buildings", [lumberyard]),
			1,
			"placed lumberyard reconciles exactly once"
		)
		assertions.truthy(progression.is_blueprint_unlocked("lumberyard"), "placed lumberyard unlock is preserved")
		assertions.equal(
			progression.call("reconcile_placed_buildings", [lumberyard]),
			0,
			"placed lumberyard reconciliation is idempotent"
		)
		lumberyard.free()


func _test_tool_durability_and_atomic_repair(assertions: TestAssert, wallet: Node) -> void:
	var inventory := _inventory()
	var tool := _tool(inventory, GridDouble.new())
	(Engine.get_main_loop() as SceneTree).root.add_child(tool)
	tool.switch_tool(ToolSystem.ToolType.HOE)
	var game_state := wallet
	game_state.player_state.stamina = 100
	var invalid := GridCell.new()
	invalid.gx = 1
	invalid.gz = 1
	invalid.state = GridCell.State.FARMLAND
	var before_failed: Dictionary = tool.get_durability("hoe")
	assertions.truthy(not tool.use_tool_on(invalid), "failed action is rejected")
	assertions.equal(tool.get_durability("hoe"), before_failed, "failed action consumes no durability")
	var valid := GridCell.new()
	valid.gx = 2
	valid.gz = 2
	valid.state = GridCell.State.WASTELAND
	assertions.truthy(tool.use_tool_on(valid), "successful action commits")
	assertions.equal(
		int(tool.get_durability("hoe").current),
		int(before_failed.current) - 1,
		"successful action consumes one durability"
	)

	var damaged: Dictionary = tool.to_dict()
	for record in damaged.tools:
		if record.tool_id == "hoe":
			record.current = 40
	assertions.truthy(tool.from_dict(damaged), "durability fixture restores valid damage")
	var quote: Dictionary = tool.get_repair_quote("hoe")
	assertions.truthy(int(quote.gold_cost) > 0, "damaged tool has deterministic gold quote")
	assertions.truthy(not quote.materials.is_empty(), "damaged tool has deterministic material quote")
	wallet.gold = int(quote.gold_cost) - 1
	_give_cost(inventory, quote.materials)
	var before_poor := _asset_snapshot(wallet, inventory)
	assertions.truthy(not tool.repair_tool("hoe"), "insufficient gold rejects repair")
	_assert_assets(assertions, before_poor, wallet, inventory, "insufficient repair")
	assertions.equal(int(tool.get_durability("hoe").current), 40, "failed repair preserves durability")
	wallet.gold = 1000
	var before_repair := _asset_snapshot(wallet, inventory)
	var gold_counter := GoldCounter.new()
	var event_bus := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("EventBus")
	if event_bus != null:
		event_bus.gold_changed.connect(gold_counter.record)
	assertions.truthy(tool.repair_tool("hoe"), "funded repair succeeds")
	assertions.equal(tool.get_durability("hoe").current, tool.get_durability("hoe").max, "repair restores max")
	assertions.equal(int(wallet.gold), int(before_repair.gold) - int(quote.gold_cost), "repair deducts exact gold")
	_assert_material_delta(assertions, before_repair, inventory, quote.materials, "repair")
	if event_bus != null:
		assertions.equal(gold_counter.count, 1, "successful repair emits one committed gold update")
		assertions.equal(gold_counter.last_gold, int(wallet.gold), "repair gold update carries committed balance")
		event_bus.gold_changed.disconnect(gold_counter.record)
	var after_repair := _asset_snapshot(wallet, inventory)
	assertions.truthy(not tool.repair_tool("hoe"), "full durability cannot be repaired")
	assertions.truthy(not tool.repair_tool("unknown"), "unknown tool cannot be repaired")
	_assert_assets(assertions, after_repair, wallet, inventory, "full or unknown repair")

	var tool_saved: Dictionary = tool.to_dict()
	var tool_before_bad: Dictionary = tool.to_dict()
	var duplicate := tool_saved.duplicate(true)
	duplicate.tools.append(duplicate.tools[0].duplicate(true))
	assertions.truthy(not tool.from_dict(duplicate), "duplicate durability record rejects")
	assertions.equal(tool.to_dict(), tool_before_bad, "duplicate durability has no pollution")
	var out_of_range := tool_saved.duplicate(true)
	out_of_range.tools[0].current = out_of_range.tools[0].max + 1
	assertions.truthy(not tool.from_dict(out_of_range), "durability above max rejects")
	assertions.equal(tool.to_dict(), tool_before_bad, "invalid durability has no pollution")
	var overflow_max := tool_saved.duplicate(true)
	overflow_max.tools[0].max = 9007199254740991
	assertions.truthy(not tool.from_dict(overflow_max), "overflow-prone repair maximum rejects")
	assertions.equal(tool.to_dict(), tool_before_bad, "overflow maximum has no pollution")

	var full_inventory := _inventory()
	full_inventory.max_slots = 1
	full_inventory.reset_slots()
	assertions.truthy(full_inventory.add_item("wood", 99), "failed fishing fixture fills inventory")
	var fishing_tool := _tool(full_inventory)
	fishing_tool.switch_tool(ToolSystem.ToolType.FISHING_ROD)
	var fishing_before: Dictionary = fishing_tool.get_durability("fishing_rod")
	assertions.truthy(not fishing_tool.use_tool_on(null), "fishing with no reward capacity is not a successful action")
	assertions.equal(fishing_tool.get_durability("fishing_rod"), fishing_before, "failed fishing consumes no durability")


func _test_maintenance_and_upgrades(assertions: TestAssert, wallet: Node) -> void:
	var inventory := _inventory()
	var tool := _tool(inventory)
	var production := _production()
	var day := DaySource.new()
	var progression = _track(ProgressionScript.new())
	assertions.truthy(progression.configure(tool, production, inventory, day, wallet), "upkeep fixture configures")
	var unlocked_fixture: Dictionary = progression.to_dict()
	unlocked_fixture.unlocked_blueprints.append("windmill")
	for recipe_id in ["flour", "animal_feed", "sunflower_oil"]:
		unlocked_fixture.unlocked_recipes.append(recipe_id)
	assertions.truthy(progression.from_dict(unlocked_fixture), "upkeep fixture unlocks its windmill recipe")
	production.set_progression_system(progression)
	var windmill := _building("windmill", 3, 4)
	assertions.truthy(production.register_building(windmill), "maintenance registers producer")
	assertions.truthy(inventory.add_item("grain", 20), "maintenance fixture adds inputs")
	production.sync_daily_cursor(1)
	assertions.truthy(production.set_maintenance_due_day(windmill, 2), "fixture sets stable due day")
	assertions.truthy(production.start_recipe(windmill, "flour", 10, inventory), "pre-due long job starts")
	var remaining_before := int(windmill.producer_state.jobs[0].remaining_minutes)
	production.sync_daily_cursor(2)
	production.advance_minutes(120)
	assertions.equal(int(windmill.producer_state.jobs[0].remaining_minutes), remaining_before, "overdue queue does not advance")
	assertions.equal(str(production.get_building_snapshot(windmill).jobs[0].status), "maintenance_paused", "overdue queue is visibly paused")
	var grain_before_blocked := inventory.get_item_count("grain")
	assertions.truthy(not production.start_recipe(windmill, "flour", 1, inventory), "overdue producer cannot start")
	assertions.equal(inventory.get_item_count("grain"), grain_before_blocked, "overdue start consumes no inputs")
	var quote: Dictionary = production.get_maintenance_quote(windmill)
	wallet.gold = 1000
	_give_cost(inventory, quote.materials)
	var before_maintain := _asset_snapshot(wallet, inventory)
	assertions.truthy(progression.maintain(windmill), "exact maintenance payment resumes producer")
	assertions.equal(int(wallet.gold), int(before_maintain.gold) - int(quote.gold_cost), "maintenance deducts exact gold")
	_assert_material_delta(assertions, before_maintain, inventory, quote.materials, "maintenance")
	assertions.equal(production.get_maintenance_due_day(windmill), 9, "maintenance schedules next weekly due day")
	production.advance_minutes(120)
	assertions.truthy(int(windmill.producer_state.jobs[0].remaining_minutes) < remaining_before, "maintained queue resumes")

	var market := _track(MarketSystemScript.new())
	assertions.truthy(market.configure(GameDataScript.get_market_items()), "upgrade market snapshot configures")
	var market_before: Dictionary = market.to_dict()
	var queue_before := windmill.producer_state.max_queue_slots
	var capacity_before := windmill.producer_state.output_capacity
	for upgrade_id in ["queue_slots", "speed", "storage"]:
		var upgrade_quote: Dictionary = progression.get_upgrade_quote(windmill, upgrade_id)
		wallet.gold = 1000
		_give_cost(inventory, upgrade_quote.materials)
		assertions.truthy(progression.upgrade(windmill, upgrade_id), "%s upgrade succeeds" % upgrade_id)
	assertions.equal(windmill.producer_state.max_queue_slots, queue_before + 1, "queue upgrade adds one slot")
	assertions.equal(windmill.producer_state.output_capacity, capacity_before + 1, "storage upgrade adds one slot")
	assertions.equal(progression.get_upgrade_level(windmill, "speed"), 1, "speed level is owned by progression")
	var hive := _building("beehive", 13, 14)
	hive.producer_state.outputs = {"honey": 6}
	assertions.truthy(production.register_building(hive), "passive storage fixture registers hive")
	var hive_storage_quote: Dictionary = progression.get_upgrade_quote(hive, "storage")
	wallet.gold = 1000
	_give_cost(inventory, hive_storage_quote.materials)
	assertions.truthy(progression.upgrade(hive, "storage"), "passive producer storage upgrade succeeds")
	assertions.equal(int(production.get_building_snapshot(hive).get("storage_quantity_capacity", 0)), 7, "passive storage snapshot exposes upgraded quantity capacity")
	production.finish_daily_outputs(4)
	assertions.equal(hive.producer_state.outputs, {"honey": 7}, "storage upgrade stores more of an existing passive output item")
	var speed_fixture := _building("windmill", 23, 24)
	assertions.truthy(production.register_building(speed_fixture), "idle speed-credit fixture registers")
	var speed_quote: Dictionary = progression.get_upgrade_quote(speed_fixture, "speed")
	wallet.gold = 1000
	_give_cost(inventory, speed_quote.materials)
	assertions.truthy(progression.upgrade(speed_fixture, "speed"), "idle speed-credit fixture upgrades")
	speed_fixture.producer_state.jobs = [{
		"recipe_id": "flour", "batches": 1, "remaining_minutes": 1, "status": "running",
	}]
	production.advance_minutes(3)
	assertions.truthy(speed_fixture.producer_state.jobs.is_empty(), "one-minute job completes during longer advance")
	assertions.truthy(speed_fixture.producer_state.enqueue_job({
		"recipe_id": "flour", "batches": 1, "remaining_minutes": 10, "status": "queued",
	}), "next speed-credit job queues")
	production.advance_minutes(1)
	assertions.equal(int(speed_fixture.producer_state.jobs[0].remaining_minutes), 9, "idle minutes grant no speed credit to the next job")
	var before_tick_speed := int(windmill.producer_state.jobs[0].remaining_minutes)
	for _tick in range(4):
		production.advance_minutes(1)
	assertions.equal(
		before_tick_speed - int(windmill.producer_state.jobs[0].remaining_minutes),
		5,
		"speed upgrade accumulates exact bonus across real one-minute ticks"
	)
	var before_speed := int(windmill.producer_state.jobs[0].remaining_minutes)
	production.advance_minutes(100)
	assertions.truthy(before_speed - int(windmill.producer_state.jobs[0].remaining_minutes) > 100, "speed upgrade accelerates real queue")
	assertions.equal(market.to_dict(), market_before, "upgrades never mutate market state or quotes")
	var after_upgrade := _asset_snapshot(wallet, inventory)
	var saved_progression: Dictionary = progression.to_dict()
	var restored = _track(ProgressionScript.new())
	assertions.truthy(restored.from_dict(saved_progression), "per-building stable upgrades persist")
	assertions.equal(restored.get_upgrade_level(windmill, "queue_slots"), 1, "queue level restores by stable building key")
	assertions.equal(restored.get_upgrade_level(hive, "storage"), 1, "passive quantity storage level persists by building key")
	_assert_assets(assertions, after_upgrade, wallet, inventory, "progression serialization")

	var maintenance_saved: Dictionary = production.to_dict()
	var restored_production := _production()
	assertions.truthy(restored_production.from_dict(maintenance_saved), "maintenance due days round trip")
	assertions.equal(restored_production.get_maintenance_due_day(windmill), 9, "maintenance restores by stable building key")
	var before_bad: Dictionary = restored_production.to_dict()
	var duplicate := maintenance_saved.duplicate(true)
	duplicate.maintenance.append(duplicate.maintenance[0].duplicate(true))
	assertions.truthy(not restored_production.from_dict(duplicate), "duplicate maintenance key rejects")
	assertions.equal(restored_production.to_dict(), before_bad, "maintenance rejection has no pollution")


func _test_failed_service_transactions_are_signal_atomic(assertions: TestAssert) -> void:
	var inventory := _inventory()
	(Engine.get_main_loop() as SceneTree).root.add_child(inventory)
	var tool := _tool(inventory)
	var production := _production()
	var wallet := _track(RejectingWallet.new())
	var day := DaySource.new()
	day.total_days = 8
	var progression = _track(ProgressionScript.new())
	assertions.truthy(progression.configure(tool, production, inventory, day, wallet), "rejecting wallet progression configures")
	var service := _service(progression, "blueprint_windmill")
	_give_cost(inventory, service.materials)
	var counter := ItemSignalCounter.new()
	var event_bus := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("EventBus")
	if event_bus != null:
		event_bus.item_removed.connect(counter.record)
	var before_purchase := _asset_snapshot(wallet, inventory)
	assertions.truthy(not progression.purchase("blueprint_windmill"), "wallet commit failure rejects purchase")
	_assert_assets(assertions, before_purchase, wallet, inventory, "wallet-rejected purchase")
	if event_bus != null:
		assertions.equal(counter.count, 0, "failed purchase emits no rolled-back item signal")

	var building := _building("windmill", 19, 20)
	production.register_building(building)
	production.sync_daily_cursor(1)
	production.set_maintenance_due_day(building, 1)
	var quote: Dictionary = production.get_maintenance_quote(building)
	_give_cost(inventory, quote.materials)
	counter.count = 0
	var before_maintain := _asset_snapshot(wallet, inventory)
	assertions.truthy(not production.maintain(building, wallet, inventory), "wallet commit failure rejects maintenance")
	_assert_assets(assertions, before_maintain, wallet, inventory, "wallet-rejected maintenance")
	if event_bus != null:
		assertions.equal(counter.count, 0, "failed maintenance emits no rolled-back item signal")
		event_bus.item_removed.disconnect(counter.record)


func _test_service_transactions_reject_signal_reentry(assertions: TestAssert, wallet: Node) -> void:
	var event_bus := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("EventBus")
	if event_bus == null:
		return
	var inventory := _inventory()
	(Engine.get_main_loop() as SceneTree).root.add_child(inventory)
	var tool := _tool(inventory)
	var production := _production()
	var day := DaySource.new()
	day.total_days = 8
	var progression = _track(ProgressionScript.new())
	assertions.truthy(progression.configure(tool, production, inventory, day, wallet), "reentry fixture configures")
	wallet.player_state.level = 2
	wallet.gold = 5000
	var purchase_service := _service(progression, "blueprint_windmill")
	for item_id in purchase_service.materials:
		inventory.add_item(str(item_id), int(purchase_service.materials[item_id]) * 2)
	var purchase_before := _asset_snapshot(wallet, inventory)
	var purchase_observer := PurchaseReentryObserver.new()
	purchase_observer.progression = progression
	event_bus.gold_changed.connect(purchase_observer.on_gold)
	assertions.truthy(progression.purchase("blueprint_windmill"), "outer purchase commits")
	event_bus.gold_changed.disconnect(purchase_observer.on_gold)
	assertions.truthy(not purchase_observer.nested_result, "purchase signal reentry is rejected")
	assertions.equal(int(wallet.gold), int(purchase_before.gold) - int(purchase_service.gold_cost), "reentrant purchase charges once")
	_assert_material_delta(assertions, purchase_before, inventory, purchase_service.materials, "reentrant purchase")

	var building := _building("windmill", 27, 28)
	assertions.truthy(production.register_building(building), "upgrade removal fixture registers")
	var upgrade_quote: Dictionary = progression.get_upgrade_quote(building, "speed")
	_give_cost(inventory, upgrade_quote.materials)
	wallet.gold = 5000
	var upgrade_before := _asset_snapshot(wallet, inventory)
	var removal_observer := UpgradeRemovalObserver.new()
	removal_observer.production = production
	removal_observer.building = building
	event_bus.gold_changed.connect(removal_observer.on_gold)
	assertions.truthy(progression.upgrade(building, "speed"), "upgrade domain commits before removal listener runs")
	event_bus.gold_changed.disconnect(removal_observer.on_gold)
	assertions.equal(progression.get_upgrade_level(building, "speed"), 1, "listener removal cannot roll back committed upgrade")
	assertions.equal(int(wallet.gold), int(upgrade_before.gold) - int(upgrade_quote.gold_cost), "upgrade removal listener charges once")
	_assert_material_delta(assertions, upgrade_before, inventory, upgrade_quote.materials, "upgrade removal listener")

	assertions.truthy(production.register_building(building), "maintenance reentry fixture re-registers")
	production.sync_daily_cursor(1)
	production.set_maintenance_due_day(building, 1)
	var maintenance_quote: Dictionary = production.get_maintenance_quote(building)
	for item_id in maintenance_quote.materials:
		var needed := int(maintenance_quote.materials[item_id]) * 2 - inventory.get_item_count(str(item_id))
		if needed > 0:
			inventory.add_item(str(item_id), needed)
	wallet.gold = 5000
	var maintenance_before := _asset_snapshot(wallet, inventory)
	var maintenance_observer := MaintenanceReentryObserver.new()
	maintenance_observer.production = production
	maintenance_observer.building = building
	maintenance_observer.wallet = wallet
	maintenance_observer.inventory = inventory
	event_bus.gold_changed.connect(maintenance_observer.on_gold)
	assertions.truthy(production.maintain(building, wallet, inventory), "outer maintenance commits")
	event_bus.gold_changed.disconnect(maintenance_observer.on_gold)
	assertions.truthy(not maintenance_observer.nested_result, "maintenance signal reentry is rejected")
	assertions.equal(int(wallet.gold), int(maintenance_before.gold) - int(maintenance_quote.gold_cost), "reentrant maintenance charges once")
	_assert_material_delta(assertions, maintenance_before, inventory, maintenance_quote.materials, "reentrant maintenance")


func _test_save_json_round_trip_atomic_rejection_and_legacy(
	assertions: TestAssert,
	wallet: Node
) -> void:
	var inventory := _inventory()
	var tool := _tool(inventory)
	var production := _production()
	var progression = _track(ProgressionScript.new())
	var day := DaySource.new()
	assertions.truthy(progression.configure(tool, production, inventory, day, wallet), "save progression configures")
	var building := _building("windmill", 7, 8)
	production.register_building(building)
	production.sync_daily_cursor(3)
	production.set_maintenance_due_day(building, 6)
	var market := _track(MarketSystemScript.new())
	assertions.truthy(market.configure(GameDataScript.get_market_items()), "save market configures")
	market.last_settled_day = 0
	var daily := _track(DailySource.new())
	var manager := _track(SaveManagerScript.new())
	(Engine.get_main_loop() as SceneTree).root.add_child(manager)
	assertions.truthy(
		manager.configure_economy(
			market, daily, null, null, null, null,
			progression, tool, production
		),
		"save manager accepts progression durability and upkeep dependencies"
	)
	var damaged: Dictionary = tool.to_dict()
	for record in damaged.tools:
		if record.tool_id == "axe":
			record.current = 17
	tool.from_dict(damaged)
	var progress_saved: Dictionary = progression.to_dict()
	progress_saved.unlocked_blueprints.append("windmill")
	for recipe_id in ["flour", "animal_feed", "sunflower_oil"]:
		progress_saved.unlocked_recipes.append(recipe_id)
	assertions.truthy(progression.from_dict(progress_saved), "save fixture owns valid progression")
	var gathered: Dictionary = manager._gather_save_data()
	assertions.equal(gathered.get("economy_version"), 1, "new upkeep remains in economy version one")
	assertions.equal(gathered.get("progression"), progression.to_dict(), "save gathers progression")
	assertions.equal(gathered.get("tool_durability"), tool.to_dict(), "save gathers durability")
	assertions.equal(gathered.get("production_upkeep"), production.to_dict(), "save gathers maintenance")
	var json := JSON.new()
	assertions.equal(json.parse(JSON.stringify(gathered)), OK, "upkeep save is JSON serializable")
	var parsed := json.data as Dictionary
	progression.reset_to_new_game()
	tool.reset_durability()
	production.reset_maintenance(0)
	assertions.truthy(manager._apply_save_data(parsed), "real save manager reapplies JSON upkeep bundle")
	assertions.equal(progression.to_dict(), gathered.progression, "JSON restores progression exactly")
	assertions.equal(tool.to_dict(), gathered.tool_durability, "JSON restores durability exactly")
	assertions.equal(production.to_dict(), gathered.production_upkeep, "JSON restores maintenance exactly")

	var before_bad := {
		"gold": int(wallet.gold), "market": market.to_dict(), "daily": daily.last_simulated_day,
		"progression": progression.to_dict(), "tools": tool.to_dict(), "production": production.to_dict(),
	}
	var malformed := gathered.duplicate(true)
	malformed.progression.unlocked_blueprints.append(malformed.progression.unlocked_blueprints[0])
	malformed.gold = int(malformed.gold) + 111
	assertions.truthy(not manager._apply_save_data(malformed), "malformed progression rejects complete save")
	assertions.equal(int(wallet.gold), int(before_bad.gold), "malformed upkeep preserves earlier gold")
	assertions.equal(market.to_dict(), before_bad.market, "malformed upkeep preserves market")
	assertions.equal(daily.last_simulated_day, before_bad.daily, "malformed upkeep preserves daily cursor")
	assertions.equal(progression.to_dict(), before_bad.progression, "malformed upkeep preserves progression")
	assertions.equal(tool.to_dict(), before_bad.tools, "malformed upkeep preserves durability")
	assertions.equal(production.to_dict(), before_bad.production, "malformed upkeep preserves maintenance")
	const MAX_SAFE_DATE := 9007199254740984
	var too_late := gathered.duplicate(true)
	too_late.last_simulated_day = MAX_SAFE_DATE + 1
	too_late.market.last_settled_day = MAX_SAFE_DATE + 1
	var before_date_rejection := {
		"market": market.to_dict(), "daily": daily.last_simulated_day,
		"production": production.to_dict(), "production_day": production._current_day,
	}
	assertions.truthy(not manager._apply_save_data(too_late), "date beyond maintenance-safe maximum rejects")
	assertions.equal(market.to_dict(), before_date_rejection.market, "overflow date rejection preserves market")
	assertions.equal(daily.last_simulated_day, before_date_rejection.daily, "overflow date rejection preserves daily cursor")
	assertions.equal(production.to_dict(), before_date_rejection.production, "overflow date rejection preserves upkeep")
	assertions.equal(production._current_day, before_date_rejection.production_day, "overflow date rejection preserves production cursor")
	var boundary := gathered.duplicate(true)
	boundary.last_simulated_day = MAX_SAFE_DATE
	boundary.market.last_settled_day = MAX_SAFE_DATE
	assertions.truthy(manager._apply_save_data(boundary), "maintenance-safe maximum date loads")
	assertions.equal(production._current_day, MAX_SAFE_DATE, "safe boundary synchronizes production cursor during apply")
	assertions.truthy(manager._apply_save_data(gathered), "date boundary fixture restores ordinary state")
	var partial_upkeep := gathered.duplicate(true)
	partial_upkeep.erase("tool_durability")
	assertions.truthy(not manager._apply_save_data(partial_upkeep), "partial upkeep bundle rejects atomically")
	var orphan_bundle := {
		"buildings": [{"building_id": "windmill", "gx": 1, "gz": 1}],
		"progression": gathered.progression.duplicate(true),
		"production_upkeep": gathered.production_upkeep.duplicate(true),
	}
	orphan_bundle.progression.upgrade_levels = [{
		"building_key": "windmill:9:9", "levels": [{"upgrade_id": "speed", "level": 1}],
	}]
	assertions.truthy(not manager._validate_economy_building_keys(orphan_bundle), "orphan upgrade key rejects")
	var forged_capacity_bundle := {
		"buildings": [{
			"building_id": "windmill", "gx": 1, "gz": 1,
			"producer_state": {"max_queue_slots": 99, "output_capacity": 99},
		}],
		"progression": gathered.progression.duplicate(true),
		"production_upkeep": {"maintenance": [], "speed_accumulators": []},
	}
	forged_capacity_bundle.progression.upgrade_levels = [{
		"building_key": "windmill:1:1",
		"levels": [
			{"upgrade_id": "queue_slots", "level": 1},
			{"upgrade_id": "storage", "level": 1},
		],
	}]
	assertions.truthy(not manager._validate_economy_building_keys(forged_capacity_bundle), "forged high producer capacities reject")
	forged_capacity_bundle.buildings[0].producer_state.max_queue_slots = 2
	forged_capacity_bundle.buildings[0].producer_state.output_capacity = 3
	assertions.truthy(not manager._validate_economy_building_keys(forged_capacity_bundle), "forged low producer capacities reject")
	forged_capacity_bundle.buildings[0].producer_state.max_queue_slots = 3
	forged_capacity_bundle.buildings[0].producer_state.output_capacity = 4
	assertions.truthy(manager._validate_economy_building_keys(forged_capacity_bundle), "authoritative upgraded producer capacities validate")

	var legacy := gathered.duplicate(true)
	legacy.erase("progression")
	legacy.erase("tool_durability")
	legacy.erase("production_upkeep")
	assertions.truthy(manager._apply_save_data(legacy), "legacy economy v1 without upkeep fields loads")
	for id in ["workbench", "stone_kiln", "beehive"]:
		assertions.truthy(progression.is_blueprint_unlocked(id), "legacy initializes tier zero %s once" % id)
	assertions.truthy(not progression.is_blueprint_unlocked("windmill"), "legacy does not grant tier one")
	for tool_id in tool.get_tool_ids():
		assertions.equal(tool.get_durability(tool_id).current, tool.get_durability(tool_id).max, "legacy initializes full %s durability" % tool_id)
	production.register_building(building)
	assertions.equal(production.get_maintenance_due_day(building), 7, "legacy initializes one weekly maintenance deadline")


func _building(id: String, gx: int, gz: int) -> BuildingInstance:
	var building := _track(BuildingInstance.new()) as BuildingInstance
	building.authored_building_id = id
	building.data = BuildingDataScript.from_dictionary(GameDataScript.get_building(id))
	building.grid_x = gx
	building.grid_z = gz
	building.producer_state = ProducerStateScript.new(id)
	return building


func _inventory() -> InventorySystem:
	var inventory := _track(InventorySystemScript.new()) as InventorySystem
	inventory.reset_slots()
	return inventory


func _tool(inventory: InventorySystem, grid: Variant = null) -> ToolSystem:
	var tool := _track(ToolSystemScript.new()) as ToolSystem
	tool.configure(grid, inventory, null)
	return tool


func _production() -> ProductionSystem:
	return _track(ProductionSystemScript.new()) as ProductionSystem


func _service(progression: Node, service_id: String) -> Dictionary:
	for service in progression.get_available_services():
		if str(service.get("id", "")) == service_id:
			return service
	return {}


func _give_cost(inventory: InventorySystem, materials: Dictionary) -> void:
	for item_id in materials:
		var needed := int(materials[item_id]) - inventory.get_item_count(str(item_id))
		if needed > 0:
			inventory.add_item(str(item_id), needed)


func _asset_snapshot(wallet: Node, inventory: InventorySystem) -> Dictionary:
	var counts := {}
	for slot in inventory.slots:
		var item_id := str(slot.get("item_id", ""))
		if not item_id.is_empty():
			counts[item_id] = int(counts.get(item_id, 0)) + int(slot.get("quantity", 0))
	return {"gold": int(wallet.gold), "counts": counts}


func _assert_assets(
	assertions: TestAssert,
	expected: Dictionary,
	wallet: Node,
	inventory: InventorySystem,
	message: String
) -> void:
	assertions.equal(int(wallet.gold), int(expected.gold), "%s preserves gold" % message)
	assertions.equal(_asset_snapshot(wallet, inventory).counts, expected.counts, "%s preserves materials" % message)


func _assert_material_delta(
	assertions: TestAssert,
	before: Dictionary,
	inventory: InventorySystem,
	materials: Dictionary,
	message: String
) -> void:
	for item_id in materials:
		assertions.equal(
			inventory.get_item_count(str(item_id)),
			int(before.counts.get(item_id, 0)) - int(materials[item_id]),
			"%s deducts exact %s" % [message, item_id]
		)


func _track(node: Node) -> Node:
	_owned_nodes.append(node)
	return node


func _cleanup_nodes() -> void:
	for index in range(_owned_nodes.size() - 1, -1, -1):
		var node := _owned_nodes[index]
		if is_instance_valid(node):
			node.free()
	_owned_nodes.clear()
