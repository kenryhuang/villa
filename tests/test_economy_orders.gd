class_name EconomyOrdersTest
extends RefCounted

const EconomySystemScript = preload("res://scripts/systems/economy_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomySystemScript = preload("res://scripts/systems/npc_economy_system.gd")
const DailySimulationSystemScript = preload("res://scripts/systems/daily_simulation_system.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")

const TEST_SAVE_DIR := "user://task11_economy_orders/"
const TEST_SLOT := 11


class WalletDouble extends Node:
	var gold := 100
	var fail_next_add := false

	func get_gold() -> int:
		return gold

	func add_gold(amount: int) -> bool:
		if fail_next_add:
			fail_next_add = false
			return false
		if amount <= 0:
			return false
		gold += amount
		return true

	func spend_gold(amount: int) -> bool:
		if amount <= 0 or amount > gold:
			return false
		gold -= amount
		return true


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_required_api(assertions)
	_test_shortage_premiums_cap_and_dedup(assertions)
	_test_order_completion_is_atomic_and_once_only(assertions)
	_test_expired_and_failed_orders_preserve_assets(assertions)
	_test_contract_delivery_reload_and_breach_idempotence(assertions)
	_test_snapshots_and_strict_atomic_restore(assertions)
	_test_save_manager_round_trip(assertions, tree)


func _test_required_api(assertions: TestAssert) -> void:
	var economy := EconomySystemScript.new()
	for method_name in [
		"get_orders", "get_contracts", "complete_order", "sign_contract",
		"deliver_contract", "to_dict", "from_dict", "validate_dict",
	]:
		assertions.truthy(economy.has_method(method_name), "economy exposes %s" % method_name)
	economy.free()


func _test_shortage_premiums_cap_and_dedup(assertions: TestAssert) -> void:
	var fixture := _fixture([
		_profile("daily_npc", {"iron_ore": 5}),
		_profile("urgent_npc", {"iron_ore": 12}),
	])
	var economy: Node = fixture.economy
	if not economy.has_method("get_orders"):
		assertions.truthy(false, "shortage tests require stable order API")
		_free_fixture(fixture)
		return

	economy.call("generate_demand_orders", 12)
	var orders: Array = economy.call("get_orders")
	assertions.equal(orders.size(), 2, "one real order is generated per NPC and item shortage")
	var daily := _record_for(orders, "daily_npc:iron_ore:12")
	var urgent := _record_for(orders, "urgent_npc:iron_ore:12")
	assertions.equal(daily.get("quantity"), 5, "daily order uses the real five-unit shortage")
	assertions.equal(daily.get("kind"), "daily", "small shortage creates a daily order")
	assertions.truthy(
		int(daily.get("unit_price", 0)) >= 115 and int(daily.get("unit_price", 0)) <= 130,
		"daily premium stays within fifteen to thirty percent"
	)
	assertions.equal(daily.get("expires_day"), 14, "daily order lasts two days")
	assertions.equal(urgent.get("quantity"), 10, "large shortage is capped at ten units")
	assertions.equal(urgent.get("kind"), "urgent", "ten-unit shortage creates an urgent order")
	assertions.truthy(
		int(urgent.get("unit_price", 0)) >= 140 and int(urgent.get("unit_price", 0)) <= 160,
		"urgent premium stays within forty to sixty percent"
	)
	assertions.equal(
		urgent.get("reward_gold"),
		int(urgent.get("quantity", 0)) * int(urgent.get("unit_price", 0)),
		"reward is the overflow-safe quantity and unit price product"
	)
	economy.call("generate_demand_orders", 12)
	economy.call("generate_demand_orders", 13)
	assertions.equal((economy.call("get_orders") as Array).size(), 2, "open NPC item demand is deduplicated across calls")
	_free_fixture(fixture)


func _test_order_completion_is_atomic_and_once_only(assertions: TestAssert) -> void:
	var fixture := _fixture([_profile("urgent_npc", {"iron_ore": 10})])
	var economy: Node = fixture.economy
	if not economy.has_method("get_orders"):
		assertions.truthy(false, "completion tests require stable order API")
		_free_fixture(fixture)
		return
	economy.call("generate_demand_orders", 12)
	var order: Dictionary = (economy.call("get_orders") as Array)[0]
	var quantity := int(order.quantity)
	var missing_before := _asset_snapshot(fixture, "urgent_npc", "iron_ore")
	assertions.truthy(not bool(economy.call("complete_order", str(order.order_id))), "insufficient player inventory rejects completion")
	_assert_assets(assertions, fixture, missing_before, "urgent_npc", "iron_ore", "insufficient inventory")
	assertions.truthy(fixture.inventory.add_item("iron_ore", quantity), "player order inventory is prepared")
	var reward := int(order.reward_gold)
	var gold_before := int(fixture.wallet.gold)
	assertions.truthy(bool(economy.call("complete_order", str(order.order_id))), "known live order completes")
	assertions.equal(fixture.inventory.get_item_count("iron_ore"), 0, "completion removes player items once")
	assertions.equal(
		fixture.npc.get_npc_state("urgent_npc").inventory.get("iron_ore", 0),
		quantity,
		"completion transfers items into the real NPC inventory"
	)
	assertions.equal(fixture.wallet.gold, gold_before + reward, "completion pays the authoritative wallet once")
	assertions.truthy(bool((economy.call("get_orders") as Array)[0].completed), "completed state remains persisted by stable ID")
	assertions.truthy(not bool(economy.call("complete_order", str(order.order_id))), "completed order cannot pay twice")
	assertions.equal(fixture.wallet.gold, gold_before + reward, "duplicate completion preserves wallet")
	assertions.equal(
		fixture.npc.get_npc_state("urgent_npc").inventory.get("iron_ore", 0),
		quantity,
		"duplicate completion preserves NPC inventory"
	)
	_free_fixture(fixture)


func _test_expired_and_failed_orders_preserve_assets(assertions: TestAssert) -> void:
	var fixture := _fixture([_profile("urgent_npc", {"iron_ore": 10})])
	var economy: Node = fixture.economy
	if not economy.has_method("get_orders"):
		assertions.truthy(false, "rollback tests require stable order API")
		_free_fixture(fixture)
		return
	economy.call("generate_demand_orders", 12)
	var order: Dictionary = (economy.call("get_orders") as Array)[0]
	var quantity := int(order.quantity)
	assertions.truthy(fixture.inventory.add_item("iron_ore", quantity), "expired order fixture owns items")
	var before := _asset_snapshot(fixture, "urgent_npc", "iron_ore")
	economy.call("advance_order_deadlines", 14)
	assertions.truthy(bool((economy.call("get_orders") as Array)[0].expired), "deadline advancement marks order expired")
	assertions.truthy(not bool(economy.call("complete_order", str(order.order_id))), "expired order rejects completion")
	_assert_assets(assertions, fixture, before, "urgent_npc", "iron_ore", "expired order")
	_free_fixture(fixture)

	fixture = _fixture([_profile("urgent_npc", {"iron_ore": 10})])
	economy = fixture.economy
	economy.call("generate_demand_orders", 12)
	order = (economy.call("get_orders") as Array)[0]
	assertions.truthy(fixture.inventory.add_item("iron_ore", int(order.quantity)), "payment rollback fixture owns items")
	before = _asset_snapshot(fixture, "urgent_npc", "iron_ore")
	fixture.wallet.fail_next_add = true
	assertions.truthy(not bool(economy.call("complete_order", str(order.order_id))), "wallet failure rejects completion")
	_assert_assets(assertions, fixture, before, "urgent_npc", "iron_ore", "wallet failure")
	assertions.truthy(not bool((economy.call("get_orders") as Array)[0].completed), "failed payment leaves order incomplete")
	assertions.truthy(not bool(economy.call("complete_order", "unknown:iron_ore:12")), "unknown order ID is rejected")
	_free_fixture(fixture)

	fixture = _fixture([_profile("urgent_npc", {"iron_ore": 10})])
	economy = fixture.economy
	economy.call("generate_demand_orders", 12)
	order = (economy.call("get_orders") as Array)[0]
	assertions.truthy(fixture.inventory.add_item("iron_ore", int(order.quantity)), "overflow fixture owns items")
	fixture.wallet.gold = 9223372036854775807
	before = _asset_snapshot(fixture, "urgent_npc", "iron_ore")
	assertions.truthy(not bool(economy.call("complete_order", str(order.order_id))), "wallet overflow rejects completion")
	_assert_assets(assertions, fixture, before, "urgent_npc", "iron_ore", "wallet overflow")
	_free_fixture(fixture)


func _test_contract_delivery_reload_and_breach_idempotence(assertions: TestAssert) -> void:
	var fixture := _fixture([_profile("grain_npc", {"grain": 15})])
	var economy: Node = fixture.economy
	if not economy.has_method("from_dict"):
		assertions.truthy(false, "contract tests require persistence API")
		_free_fixture(fixture)
		return
	var persisted := {
		"last_processed_day": 0,
		"orders": [],
		"contracts": [_contract_record()],
	}
	assertions.truthy(bool(economy.call("from_dict", persisted)), "valid three-day contract restores")
	assertions.truthy(not bool(economy.call("deliver_contract", "grain_npc:grain:1:3", 5)), "unsigned contract rejects delivery")
	assertions.truthy(not bool(economy.call("deliver_contract", "unknown", 5)), "unknown contract rejects delivery")
	assertions.truthy(bool(economy.call("sign_contract", "grain_npc:grain:1:3")), "available contract signs once")
	assertions.truthy(not bool(economy.call("sign_contract", "grain_npc:grain:1:3")), "signed contract cannot sign twice")
	economy.call("advance_order_deadlines", 1)
	assertions.truthy(fixture.inventory.add_item("grain", 10), "two delivery days are prepared")
	var gold_before := int(fixture.wallet.gold)
	assertions.truthy(not bool(economy.call("deliver_contract", "grain_npc:grain:1:3", 4)), "wrong daily quantity is rejected")
	assertions.equal(fixture.inventory.get_item_count("grain"), 10, "wrong quantity removes no items")
	assertions.truthy(bool(economy.call("deliver_contract", "grain_npc:grain:1:3", 5)), "first daily contract delivery succeeds")
	assertions.equal(fixture.wallet.gold, gold_before + 50, "first contract delivery pays once")

	persisted = economy.call("to_dict")
	var reloaded := EconomySystemScript.new()
	assertions.truthy(bool(reloaded.call("configure", fixture.inventory, fixture.wallet, fixture.market, fixture.npc)), "reloaded economy configures dependencies")
	assertions.truthy(bool(reloaded.call("from_dict", persisted)), "signed contract and first delivery reload")
	assertions.truthy(not bool(reloaded.call("deliver_contract", "grain_npc:grain:1:3", 5)), "reload cannot duplicate same-day delivery payment")
	assertions.equal(fixture.wallet.gold, gold_before + 50, "duplicate delivery after reload preserves wallet")

	reloaded.call("advance_order_deadlines", 2)
	reloaded.call("advance_order_deadlines", 3)
	assertions.equal((reloaded.call("get_contracts") as Array)[0].breaches, 1, "one missed day records one breach")
	reloaded.call("advance_order_deadlines", 3)
	assertions.equal((reloaded.call("get_contracts") as Array)[0].breaches, 1, "same-day deadline processing is idempotent")
	assertions.truthy(bool(reloaded.call("deliver_contract", "grain_npc:grain:1:3", 5)), "third-day delivery succeeds after one miss")
	var contract: Dictionary = (reloaded.call("get_contracts") as Array)[0]
	assertions.equal(contract.delivered_days, [1, 3], "contract persists the exact delivered days")
	assertions.equal(contract.breaches, 1, "delivery does not alter recorded breach count")
	assertions.equal(fixture.wallet.gold, gold_before + 100, "two delivered days pay exactly twice")
	assertions.equal(fixture.npc.get_npc_state("grain_npc").inventory.get("grain", 0), 10, "contract goods enter NPC inventory")
	reloaded.free()
	_free_fixture(fixture)

	fixture = _fixture([_profile("grain_npc", {"grain": 5})])
	economy = fixture.economy
	var available := {
		"last_processed_day": 2,
		"orders": [],
		"contracts": [_contract_record()],
	}
	var restored_available := bool(economy.call("from_dict", available))
	assertions.truthy(restored_available, "unsigned available contract accrues no breach before signing")
	if restored_available:
		economy.call("advance_order_deadlines", 4)
		assertions.truthy(bool((economy.call("get_contracts") as Array)[0].expired), "unsigned contract expires after its offer window")
		assertions.equal((economy.call("get_contracts") as Array)[0].breaches, 0, "unsigned expired contract never records breach")
	_free_fixture(fixture)


func _test_snapshots_and_strict_atomic_restore(assertions: TestAssert) -> void:
	var fixture := _fixture([_profile("daily_npc", {"iron_ore": 5}), _profile("grain_npc", {"grain": 5})])
	var economy: Node = fixture.economy
	if not economy.has_method("get_orders"):
		assertions.truthy(false, "snapshot tests require stable order API")
		_free_fixture(fixture)
		return
	economy.call("generate_demand_orders", 12)
	var snapshot: Array = economy.call("get_orders")
	var original_quantity := int(snapshot[0].quantity)
	snapshot[0].quantity = 999
	assertions.equal((economy.call("get_orders") as Array)[0].quantity, original_quantity, "order snapshots cannot mutate internal records")

	var valid_state: Dictionary = economy.call("to_dict")
	valid_state.contracts.append(_contract_record())
	assertions.truthy(bool(economy.call("from_dict", valid_state)), "valid order and contract state restores")
	var contracts: Array = economy.call("get_contracts")
	contracts[0].delivered_days.append(99)
	assertions.equal((economy.call("get_contracts") as Array)[0].delivered_days, [], "nested contract snapshots cannot mutate internal records")
	var before: Dictionary = economy.call("to_dict")

	var malformed := before.duplicate(true)
	malformed.orders.append(malformed.orders[0].duplicate(true))
	assertions.truthy(not bool(economy.call("from_dict", malformed)), "duplicate stable order IDs are rejected")
	assertions.equal(economy.call("to_dict"), before, "duplicate-ID rejection is atomic")
	malformed = before.duplicate(true)
	malformed.contracts[0].npc_id = "unknown_npc"
	assertions.truthy(not bool(economy.call("from_dict", malformed)), "unknown NPC contract is rejected")
	assertions.equal(economy.call("to_dict"), before, "unknown-NPC rejection is atomic")
	malformed = before.duplicate(true)
	malformed.orders[0].item_id = "unknown_item"
	assertions.truthy(not bool(economy.call("from_dict", malformed)), "unknown item order is rejected")
	assertions.equal(economy.call("to_dict"), before, "unknown-item rejection is atomic")
	malformed = before.duplicate(true)
	malformed.orders[0].reward_gold += 1
	assertions.truthy(not bool(economy.call("from_dict", malformed)), "reward cross-field mismatch is rejected")
	assertions.equal(economy.call("to_dict"), before, "cross-field rejection is atomic")
	malformed = before.duplicate(true)
	malformed.contracts[0].breaches = -1
	assertions.truthy(not bool(economy.call("from_dict", malformed)), "negative contract values are rejected")
	assertions.equal(economy.call("to_dict"), before, "range rejection is atomic")
	_free_fixture(fixture)


func _test_save_manager_round_trip(assertions: TestAssert, tree: SceneTree) -> void:
	_cleanup_save()
	var manager := SaveManagerScript.new()
	if _method_arg_count(manager, "configure_economy") < 6:
		assertions.truthy(false, "SaveManager accepts the stable order system dependency")
		manager.free()
		return
	var fixture := _fixture([_profile("grain_npc", {"grain": 5})])
	var economy: Node = fixture.economy
	var daily := DailySimulationSystemScript.new()
	manager.save_directory = TEST_SAVE_DIR
	for node in [fixture.market, fixture.npc, fixture.inventory, fixture.wallet, economy, daily, manager]:
		tree.root.add_child(node)
	assertions.truthy(fixture.market.settle_day(1), "save fixture market settles to contract day")
	assertions.truthy(fixture.npc.sync_daily_cursor(1), "save fixture NPC cursor synchronizes")
	daily.last_simulated_day = 1
	assertions.truthy(bool(economy.call("from_dict", {
		"last_processed_day": 0,
		"orders": [],
		"contracts": [_contract_record()],
	})), "save fixture restores available contract")
	assertions.truthy(bool(economy.call("sign_contract", "grain_npc:grain:1:3")), "save fixture signs contract")
	economy.call("advance_order_deadlines", 1)
	assertions.truthy(fixture.inventory.add_item("grain", 5), "save fixture prepares contract goods")
	assertions.truthy(bool(economy.call("deliver_contract", "grain_npc:grain:1:3", 5)), "save fixture records first delivery")
	assertions.truthy(bool(manager.call(
		"configure_economy", fixture.market, daily, null, null, fixture.npc, economy
	)), "SaveManager configures stable economy state")
	var expected: Dictionary = economy.call("to_dict")
	assertions.truthy(manager.save_game(TEST_SLOT), "stable order and contract state saves")
	assertions.equal(manager._gather_save_data().get("economy_state"), expected, "save payload includes stable IDs and delivery state")
	assertions.truthy(bool(economy.call("reset_order_state", 1)), "runtime order state diverges after save")
	assertions.truthy(manager.load_game(TEST_SLOT), "stable order and contract state loads")
	assertions.equal(economy.call("to_dict"), expected, "IDs completion delivery and breach state round trip")
	for node in [manager, daily, economy, fixture.wallet, fixture.inventory, fixture.npc, fixture.market]:
		tree.root.remove_child(node)
		node.free()
	_cleanup_save()


func _fixture(profiles: Array) -> Dictionary:
	var market := MarketSystemScript.new()
	market.configure([
		_definition("iron_ore", 100),
		_definition("grain", 10),
	])
	var npc := NpcEconomySystemScript.new()
	npc.configure(market, profiles, [])
	var inventory := InventorySystemScript.new()
	var wallet := WalletDouble.new()
	var economy := EconomySystemScript.new()
	if economy.has_method("get_orders"):
		economy.call("configure", inventory, wallet, market, npc)
	else:
		economy.call("configure", inventory, wallet, market)
	return {
		"market": market,
		"npc": npc,
		"inventory": inventory,
		"wallet": wallet,
		"economy": economy,
	}


func _profile(npc_id: String, targets: Dictionary) -> Dictionary:
	return {
		"id": npc_id,
		"display_name": npc_id,
		"gold": 0,
		"inventory": {},
		"essential_targets": {},
		"reserve_targets": targets,
		"production_recipes": [],
		"sale_targets": {},
		"investment_gold_threshold": 1000,
		"import_buffer": false,
	}


func _definition(item_id: String, base_price: int) -> Dictionary:
	return {
		"id": item_id,
		"base_price": base_price,
		"initial_stock": 0,
		"target_stock": 20,
		"daily_liquidity": 10,
	}


func _contract_record() -> Dictionary:
	return {
		"contract_id": "grain_npc:grain:1:3",
		"npc_id": "grain_npc",
		"item_id": "grain",
		"quantity_per_day": 5,
		"unit_price": 10,
		"reward_gold": 50,
		"start_day": 1,
		"end_day": 3,
		"delivered_days": [],
		"breaches": 0,
		"signed": false,
		"completed": false,
		"expired": false,
	}


func _record_for(records: Array, record_id: String) -> Dictionary:
	for value in records:
		if value is Dictionary and str(value.get("order_id", "")) == record_id:
			return value
	return {}


func _asset_snapshot(fixture: Dictionary, npc_id: String, item_id: String) -> Dictionary:
	return {
		"player": fixture.inventory.get_item_count(item_id),
		"npc": fixture.npc.get_npc_state(npc_id).inventory.get(item_id, 0),
		"gold": fixture.wallet.gold,
	}


func _assert_assets(
	assertions: TestAssert,
	fixture: Dictionary,
	expected: Dictionary,
	npc_id: String,
	item_id: String,
	message: String
) -> void:
	assertions.equal(fixture.inventory.get_item_count(item_id), expected.player, message + " preserves player inventory")
	assertions.equal(fixture.npc.get_npc_state(npc_id).inventory.get(item_id, 0), expected.npc, message + " preserves NPC inventory")
	assertions.equal(fixture.wallet.gold, expected.gold, message + " preserves wallet")


func _free_fixture(fixture: Dictionary) -> void:
	for key in ["economy", "inventory", "wallet", "npc", "market"]:
		(fixture[key] as Node).free()


func _method_arg_count(target: Object, method_name: String) -> int:
	for method in target.get_method_list():
		if str(method.get("name", "")) == method_name:
			return (method.get("args", []) as Array).size()
	return -1


func _cleanup_save() -> void:
	var path := TEST_SAVE_DIR.path_join("save_%d.json" % TEST_SLOT)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var directory := TEST_SAVE_DIR.trim_suffix("/")
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)
