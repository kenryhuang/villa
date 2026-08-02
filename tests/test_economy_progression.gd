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
	_test_tool_durability_and_atomic_repair(assertions, wallet)
	_test_failed_service_transactions_are_signal_atomic(assertions)
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
	for id in ["workbench", "stone_kiln", "beehive"]:
		assertions.truthy(progression.is_blueprint_unlocked(id), "tier zero unlocks %s" % id)
	for id in ["windmill", "chicken_coop", "waterwheel", "furnace"]:
		assertions.truthy(not progression.is_blueprint_unlocked(id), "tier one locks %s" % id)
	for id in ["greenhouse", "mine", "textile_machine"]:
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
	unlocked_fixture.unlocked_recipes.append("flour")
	assertions.truthy(progression.from_dict(unlocked_fixture), "upkeep fixture unlocks its windmill recipe")
	production.set_progression_system(progression)
	var windmill := _building("windmill", 3, 4)
	assertions.truthy(production.register_building(windmill), "maintenance registers producer")
	assertions.truthy(inventory.add_item("grain", 20), "maintenance fixture adds inputs")
	production.sync_daily_cursor(1)
	assertions.truthy(production.set_maintenance_due_day(windmill, 2), "fixture sets stable due day")
	assertions.truthy(production.start_recipe(windmill, "flour", 1, inventory), "pre-due job starts")
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
	progress_saved.unlocked_recipes.append("flour")
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
