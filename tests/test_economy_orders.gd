class_name EconomyOrdersTest
extends RefCounted

const EconomySystemScript = preload("res://scripts/systems/economy_system.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const FarmStorageSystemScript = preload("res://scripts/systems/farm_storage_system.gd")
const ItemContainerRouterScript = preload("res://scripts/systems/item_container_router.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomySystemScript = preload("res://scripts/systems/npc_economy_system.gd")
const DailySimulationSystemScript = preload("res://scripts/systems/daily_simulation_system.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const EventBusScript = preload("res://scripts/core/event_bus.gd")

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

	func restore_gold_unchecked(value: int) -> bool:
		if value < 0 or value > EconomyLimitsScript.MAX_SAFE_INTEGER:
			return false
		gold = value
		return true

	func can_restore_gold_unchecked() -> bool:
		return true


class FailingReceiptNpc extends NpcEconomySystem:
	var fail_next_receipt := true

	func receive_item(npc_id: String, item_id: String, quantity: int) -> bool:
		var result := super.receive_item(npc_id, item_id, quantity)
		if fail_next_receipt:
			fail_next_receipt = false
			return false
		return result


class FailingFinalizeRouter extends ItemContainerRouter:
	var fail_next_finalize := true

	func finalize_sealed_publication(publication: Variant) -> RefCounted:
		if fail_next_finalize:
			fail_next_finalize = false
			return null
		return super.finalize_sealed_publication(publication)


class ReentrantDeliveryObserver extends RefCounted:
	var reenter: Callable
	var attempted := false
	var inner_result := true
	var gold_events := 0
	var item_events := 0
	var storage_events := 0

	func _init(action: Callable) -> void:
		reenter = action

	func on_gold_changed(_new_gold: int) -> void:
		gold_events += 1
		if attempted:
			return
		attempted = true
		inner_result = bool(reenter.call())

	func on_item_removed(_item_id: String, _quantity: int) -> void:
		item_events += 1

	func on_storage_changed(_changes: Dictionary) -> void:
		storage_events += 1
		if attempted:
			return
		attempted = true
		inner_result = bool(reenter.call())


class DeliveryEventRecorder extends RefCounted:
	var count := 0

	func on_gold(_balance: int) -> void:
		count += 1

	func on_item(_item_id: String, _quantity: int) -> void:
		count += 1

	func on_storage(_changes: Dictionary) -> void:
		count += 1

	func on_order(_order_id: String) -> void:
		count += 1


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_required_api(assertions)
	_test_stable_event_bus_signal_shape(assertions)
	_test_shortage_premiums_cap_and_dedup(assertions)
	_test_order_completion_is_atomic_and_once_only(assertions)
	_test_routed_order_sources(assertions)
	_test_routed_delivery_failures_restore_every_authority(assertions, tree)
	_test_reentrant_delivery_signals_settle_once(assertions, tree)
	_test_expired_and_failed_orders_preserve_assets(assertions)
	_test_contract_delivery_reload_and_breach_idempotence(assertions)
	_test_contract_delivery_quantity_limit(assertions)
	_test_snapshots_and_strict_atomic_restore(assertions)
	_test_save_manager_round_trip(assertions, tree)
	_test_generation_requires_current_safe_day(assertions)


func _test_required_api(assertions: TestAssert) -> void:
	var economy := EconomySystemScript.new()
	for method_name in [
		"get_orders", "get_contracts", "complete_order", "sign_contract",
		"deliver_contract", "to_dict", "from_dict", "validate_dict",
	]:
		assertions.truthy(economy.has_method(method_name), "economy exposes %s" % method_name)
	economy.free()


func _test_stable_event_bus_signal_shape(assertions: TestAssert) -> void:
	var event_bus := EventBusScript.new()
	assertions.truthy(not event_bus.has_signal("order_generated"), "EventBus exposes no index-based generated-order signal")
	assertions.truthy(not event_bus.has_signal("order_completed"), "EventBus exposes no index-based completed-order signal")
	_assert_string_id_signal(assertions, event_bus, "order_updated", "order_id")
	_assert_string_id_signal(assertions, event_bus, "contract_updated", "contract_id")
	event_bus.free()


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

	economy.call("advance_order_deadlines", 12)
	economy.call("generate_demand_orders", 12)
	var orders: Array = economy.call("get_orders")
	assertions.equal(orders.size(), 2, "one real order is generated per NPC and item shortage")
	var daily := _record_for(orders, "daily_npc:iron_ore:12")
	var urgent := _record_for(orders, "urgent_npc:iron_ore:12")
	assertions.equal(daily.get("quantity"), 5, "daily order uses the real five-unit shortage")
	assertions.equal(daily.get("kind"), "daily", "small shortage creates a daily order")
	var daily_quote: int = fixture.market.quote_sell("iron_ore", int(daily.quantity))
	_assert_reward_premium(assertions, daily, daily_quote, 15, 30, "daily")
	assertions.equal(daily.get("expires_day"), 14, "daily order lasts two days")
	assertions.equal(urgent.get("quantity"), 10, "large shortage is capped at ten units")
	assertions.equal(urgent.get("kind"), "urgent", "ten-unit shortage creates an urgent order")
	var urgent_quote: int = fixture.market.quote_sell("iron_ore", int(urgent.quantity))
	_assert_reward_premium(assertions, urgent, urgent_quote, 40, 60, "urgent")
	assertions.equal(
		urgent.get("reward_gold"),
		int(urgent.get("quantity", 0)) * int(urgent.get("unit_price", 0)),
		"reward is the overflow-safe quantity and unit price product"
	)
	economy.call("generate_demand_orders", 12)
	economy.call("generate_demand_orders", 13)
	assertions.equal((economy.call("get_orders") as Array).size(), 2, "open NPC item demand is deduplicated across calls")
	_free_fixture(fixture)

	fixture = _fixture([_profile("tiny_npc", {"grain": 10})], 100, 1)
	economy = fixture.economy
	economy.call("advance_order_deadlines", 12)
	economy.call("generate_demand_orders", 12)
	assertions.equal((economy.call("get_orders") as Array).size(), 0, "no discrete in-range reward deterministically skips the unsafe order")
	_free_fixture(fixture)


func _test_order_completion_is_atomic_and_once_only(assertions: TestAssert) -> void:
	var fixture := _fixture([_profile("urgent_npc", {"iron_ore": 10})])
	var economy: Node = fixture.economy
	if not economy.has_method("get_orders"):
		assertions.truthy(false, "completion tests require stable order API")
		_free_fixture(fixture)
		return
	economy.call("advance_order_deadlines", 12)
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


func _test_routed_order_sources(assertions: TestAssert) -> void:
	var crop_fixture := _fixture([_profile("crop_npc", {"grain": 5})])
	var crop_economy: Node = crop_fixture.economy
	crop_economy.call("advance_order_deadlines", 12)
	assertions.truthy(bool(crop_economy.call("generate_demand_orders", 12)), "crop order generates")
	var crop_order: Dictionary = _record_for(crop_economy.call("get_orders"), "crop_npc:grain:12")
	var crop_quantity := int(crop_order.get("quantity", 0))
	assertions.truthy(crop_fixture.storage.add_items({"grain": crop_quantity}), "crop order stock enters farm storage")
	assertions.truthy(crop_economy.call("complete_order", "crop_npc:grain:12"), "crop order completes through router")
	assertions.equal(crop_fixture.storage.get_count("grain"), 0, "crop order removes farm storage")
	assertions.equal(crop_fixture.inventory.get_item_count("grain"), 0, "crop order never touches backpack")
	_free_fixture(crop_fixture)

	var seed_fixture := _fixture([_profile("seed_npc", {"grain_seed": 3})])
	var seed_economy: Node = seed_fixture.economy
	seed_economy.set("_last_processed_day", 12)
	var seed_orders: Array[Dictionary] = [{
		"order_id": "seed_npc:grain_seed:12", "npc_id": "seed_npc",
		"item_id": "grain_seed", "quantity": 3, "unit_price": 4,
		"reward_gold": 12, "expires_day": 14, "kind": "daily",
		"completed": false, "expired": false,
	}]
	seed_economy.set("_orders", seed_orders)
	var seed_order: Dictionary = _record_for(seed_economy.call("get_orders"), "seed_npc:grain_seed:12")
	var seed_quantity := int(seed_order.get("quantity", 0))
	assertions.truthy(seed_fixture.inventory.add_item("grain_seed", seed_quantity), "seed order stock enters backpack")
	assertions.truthy(seed_economy.call("complete_order", "seed_npc:grain_seed:12"), "seed order completes through router")
	assertions.equal(seed_fixture.inventory.get_item_count("grain_seed"), 0, "seed order removes backpack")
	assertions.equal(seed_fixture.storage.get_count("grain_seed"), 0, "seed order never touches farm storage")
	_free_fixture(seed_fixture)


func _test_routed_delivery_failures_restore_every_authority(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var failing_npc := FailingReceiptNpc.new()
	var receipt_fixture := _fixture(
		[_profile("receipt_npc", {"iron_ore": 4})], 100, 10, failing_npc
	)
	receipt_fixture.economy.advance_order_deadlines(12)
	receipt_fixture.economy.generate_demand_orders(12)
	var receipt_order: Dictionary = receipt_fixture.economy.get_orders()[0]
	receipt_fixture.inventory.add_item("iron_ore", int(receipt_order.quantity))
	var receipt_before := _full_delivery_snapshot(receipt_fixture)
	assertions.truthy(not receipt_fixture.economy.complete_order(receipt_order.order_id), "NPC receipt failure rejects routed order")
	assertions.equal(_full_delivery_snapshot(receipt_fixture), receipt_before, "NPC receipt failure restores every authority")
	_free_fixture(receipt_fixture)

	var failing_router := FailingFinalizeRouter.new()
	var finalize_fixture := _fixture(
		[_profile("finalize_npc", {"grain": 4})], 100, 10, null, failing_router
	)
	finalize_fixture.economy.advance_order_deadlines(12)
	finalize_fixture.economy.generate_demand_orders(12)
	var finalize_order: Dictionary = finalize_fixture.economy.get_orders()[0]
	finalize_fixture.storage.add_items({"grain": int(finalize_order.quantity)})
	var finalize_before := _full_delivery_snapshot(finalize_fixture)
	for node in [finalize_fixture.inventory, finalize_fixture.storage, finalize_fixture.router, finalize_fixture.economy]:
		tree.root.add_child(node)
	var recorder := DeliveryEventRecorder.new()
	var event_bus := tree.root.get_node("EventBus")
	event_bus.gold_changed.connect(recorder.on_gold)
	event_bus.item_removed.connect(recorder.on_item)
	event_bus.order_updated.connect(recorder.on_order)
	finalize_fixture.storage.contents_changed.connect(recorder.on_storage)
	assertions.truthy(not finalize_fixture.economy.complete_order(finalize_order.order_id), "router finalize failure rejects routed order")
	assertions.equal(_full_delivery_snapshot(finalize_fixture), finalize_before, "router finalize failure restores goods NPC gold and order state")
	assertions.equal(recorder.count, 0, "failed routed delivery publishes no temporary notifications")
	event_bus.gold_changed.disconnect(recorder.on_gold)
	event_bus.item_removed.disconnect(recorder.on_item)
	event_bus.order_updated.disconnect(recorder.on_order)
	finalize_fixture.storage.contents_changed.disconnect(recorder.on_storage)
	for node in [finalize_fixture.economy, finalize_fixture.router, finalize_fixture.storage, finalize_fixture.inventory]:
		tree.root.remove_child(node)
	_free_fixture(finalize_fixture)


func _test_reentrant_delivery_signals_settle_once(assertions: TestAssert, tree: SceneTree) -> void:
	var event_bus := tree.root.get_node_or_null("EventBus")
	assertions.truthy(event_bus != null, "real EventBus exists for reentrant delivery coverage")
	if event_bus == null:
		return
	var fixture := _fixture([_profile("urgent_npc", {"iron_ore": 10})])
	var economy: Node = fixture.economy
	for node in [fixture.inventory, fixture.storage, fixture.router, economy]:
		tree.root.add_child(node)
	economy.call("advance_order_deadlines", 12)
	assertions.equal(economy.call("generate_demand_orders", 12), true, "reentrant order fixture generates on its current day")
	var order: Dictionary = (economy.call("get_orders") as Array)[0]
	var quantity := int(order.quantity)
	var reward := int(order.reward_gold)
	assertions.truthy(fixture.inventory.add_item("iron_ore", quantity * 2), "reentrant order fixture owns two deliveries")
	var gold_before := int(fixture.wallet.gold)
	var order_observer := ReentrantDeliveryObserver.new(
		Callable(economy, "complete_order").bind(str(order.order_id))
	)
	event_bus.gold_changed.connect(order_observer.on_gold_changed)
	event_bus.item_removed.connect(order_observer.on_item_removed)
	assertions.truthy(bool(economy.call("complete_order", str(order.order_id))), "outer order delivery succeeds")
	event_bus.gold_changed.disconnect(order_observer.on_gold_changed)
	event_bus.item_removed.disconnect(order_observer.on_item_removed)
	assertions.truthy(order_observer.attempted, "gold signal attempts one reentrant order completion")
	assertions.truthy(not order_observer.inner_result, "reentrant completion of the same order is rejected")
	assertions.equal(fixture.inventory.get_item_count("iron_ore"), quantity, "reentrant order consumes one delivery")
	assertions.equal(fixture.npc.get_npc_state("urgent_npc").inventory.get("iron_ore", 0), quantity, "reentrant order credits NPC once")
	assertions.equal(fixture.wallet.gold, gold_before + reward, "reentrant order pays once")
	assertions.truthy(bool((economy.call("get_orders") as Array)[0].completed), "reentrant order records one completion")
	assertions.equal(order_observer.gold_events, 1, "reentrant order emits one final gold signal")
	assertions.equal(order_observer.item_events, 1, "reentrant order emits one final item signal")
	for node in [economy, fixture.router, fixture.storage, fixture.inventory]:
		tree.root.remove_child(node)
	_free_fixture(fixture)

	fixture = _fixture([_profile("grain_npc", {"grain": 15})])
	economy = fixture.economy
	for node in [fixture.inventory, fixture.storage, fixture.router, economy]:
		tree.root.add_child(node)
	assertions.truthy(bool(economy.call("from_dict", {
		"last_processed_day": 0,
		"orders": [],
		"contracts": [_contract_record()],
	})), "reentrant contract fixture restores")
	assertions.truthy(bool(economy.call("sign_contract", "grain_npc:grain:1:3")), "reentrant contract fixture signs")
	economy.call("advance_order_deadlines", 1)
	assertions.truthy(fixture.storage.add_items({"grain": 10}), "reentrant contract fixture owns two deliveries")
	gold_before = int(fixture.wallet.gold)
	var contract_observer := ReentrantDeliveryObserver.new(
		Callable(economy, "deliver_contract").bind("grain_npc:grain:1:3", 5)
	)
	event_bus.gold_changed.connect(contract_observer.on_gold_changed)
	event_bus.item_removed.connect(contract_observer.on_item_removed)
	fixture.storage.contents_changed.connect(contract_observer.on_storage_changed)
	assertions.truthy(bool(economy.call("deliver_contract", "grain_npc:grain:1:3", 5)), "outer contract delivery succeeds")
	event_bus.gold_changed.disconnect(contract_observer.on_gold_changed)
	event_bus.item_removed.disconnect(contract_observer.on_item_removed)
	fixture.storage.contents_changed.disconnect(contract_observer.on_storage_changed)
	assertions.truthy(contract_observer.attempted, "gold signal attempts one reentrant contract delivery")
	assertions.truthy(not contract_observer.inner_result, "reentrant delivery of the same contract day is rejected")
	assertions.equal(fixture.storage.get_count("grain"), 5, "reentrant contract consumes one delivery")
	assertions.equal(fixture.npc.get_npc_state("grain_npc").inventory.get("grain", 0), 5, "reentrant contract credits NPC once")
	assertions.equal(fixture.wallet.gold, gold_before + 50, "reentrant contract pays once")
	assertions.equal((economy.call("get_contracts") as Array)[0].delivered_days, [1], "reentrant contract records one delivered day")
	assertions.equal(contract_observer.gold_events, 1, "reentrant contract emits one final gold signal")
	assertions.equal(contract_observer.storage_events, 1, "reentrant contract emits one final storage signal")
	for node in [economy, fixture.router, fixture.storage, fixture.inventory]:
		tree.root.remove_child(node)
	_free_fixture(fixture)


func _test_expired_and_failed_orders_preserve_assets(assertions: TestAssert) -> void:
	var fixture := _fixture([_profile("urgent_npc", {"iron_ore": 10})])
	var economy: Node = fixture.economy
	if not economy.has_method("get_orders"):
		assertions.truthy(false, "rollback tests require stable order API")
		_free_fixture(fixture)
		return
	economy.call("advance_order_deadlines", 12)
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
	economy.call("advance_order_deadlines", 12)
	economy.call("generate_demand_orders", 12)
	order = (economy.call("get_orders") as Array)[0]
	assertions.truthy(fixture.inventory.add_item("iron_ore", int(order.quantity)), "payment rollback fixture owns items")
	before = _asset_snapshot(fixture, "urgent_npc", "iron_ore")
	fixture.wallet.fail_next_add = true
	assertions.truthy(not bool(economy.call("complete_order", str(order.order_id))), "wallet failure rejects completion")
	_assert_assets(assertions, fixture, before, "urgent_npc", "iron_ore", "wallet failure")
	assertions.truthy(not bool((economy.call("get_orders") as Array)[0].completed), "failed payment leaves order incomplete")
	assertions.truthy(bool(economy.call("complete_order", str(order.order_id))), "delivery guard clears after a failed transfer")
	assertions.truthy(not bool(economy.call("complete_order", "unknown:iron_ore:12")), "unknown order ID is rejected")
	_free_fixture(fixture)

	fixture = _fixture([_profile("urgent_npc", {"iron_ore": 10})])
	economy = fixture.economy
	economy.call("advance_order_deadlines", 12)
	economy.call("generate_demand_orders", 12)
	order = (economy.call("get_orders") as Array)[0]
	assertions.truthy(fixture.inventory.add_item("iron_ore", int(order.quantity)), "future-created defense fixture owns items")
	before = _asset_snapshot(fixture, "urgent_npc", "iron_ore")
	economy.set("_last_processed_day", 11)
	assertions.truthy(not bool(economy.call("complete_order", str(order.order_id))), "completion rejects an order created after the current cursor")
	_assert_assets(assertions, fixture, before, "urgent_npc", "iron_ore", "future-created completion defense")
	_free_fixture(fixture)

	fixture = _fixture([_profile("urgent_npc", {"iron_ore": 10})])
	economy = fixture.economy
	economy.call("advance_order_deadlines", 12)
	economy.call("generate_demand_orders", 12)
	order = (economy.call("get_orders") as Array)[0]
	assertions.truthy(fixture.inventory.add_item("iron_ore", int(order.quantity)), "cursor defense fixture owns items")
	before = _asset_snapshot(fixture, "urgent_npc", "iron_ore")
	economy.set("_last_processed_day", int(order.expires_day) + 1)
	assertions.truthy(not bool(economy.call("complete_order", str(order.order_id))), "completion rejects an overdue cursor even when the flag is stale")
	_assert_assets(assertions, fixture, before, "urgent_npc", "iron_ore", "overdue cursor defense")
	_free_fixture(fixture)

	fixture = _fixture([_profile("urgent_npc", {"iron_ore": 10})])
	economy = fixture.economy
	economy.call("advance_order_deadlines", 12)
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
	assertions.truthy(fixture.storage.add_items({"grain": 10}), "two delivery days are prepared")
	var gold_before := int(fixture.wallet.gold)
	assertions.truthy(not bool(economy.call("deliver_contract", "grain_npc:grain:1:3", 4)), "wrong daily quantity is rejected")
	assertions.equal(fixture.storage.get_count("grain"), 10, "wrong quantity removes no items")
	assertions.truthy(bool(economy.call("deliver_contract", "grain_npc:grain:1:3", 5)), "first daily contract delivery succeeds")
	assertions.equal(fixture.wallet.gold, gold_before + 50, "first contract delivery pays once")

	persisted = economy.call("to_dict")
	var reloaded := EconomySystemScript.new()
	assertions.truthy(bool(reloaded.call("configure", fixture.inventory, fixture.wallet, fixture.market, fixture.npc, fixture.router)), "reloaded economy configures dependencies")
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
		var available_before: Dictionary = economy.call("to_dict")
		var stale_available := available_before.duplicate(true)
		stale_available["last_processed_day"] = 4
		assertions.truthy(not bool(economy.call("from_dict", stale_available)), "cursor past contract end rejects an unexpired incomplete contract")
		assertions.equal(economy.call("to_dict"), available_before, "stale contract rejection is atomic")
		economy.call("advance_order_deadlines", 4)
		assertions.truthy(bool((economy.call("get_contracts") as Array)[0].expired), "unsigned contract expires after its offer window")
		assertions.equal((economy.call("get_contracts") as Array)[0].breaches, 0, "unsigned expired contract never records breach")
	_free_fixture(fixture)


func _test_contract_delivery_quantity_limit(assertions: TestAssert) -> void:
	var inventory_defaults := InventorySystemScript.new()
	var grain_definition: Dictionary = GameDataScript.get_item("grain")
	var default_capacity := inventory_defaults.max_slots * int(grain_definition.get("max_stack", 0))
	var economy_limit := EconomyLimitsScript.MAX_DELIVERY_QUANTITY
	var default_slots := InventorySystemScript.DEFAULT_MAX_SLOTS
	var default_stack := GameDataScript.DEFAULT_MAX_STACK
	inventory_defaults.free()
	assertions.equal(default_slots, 20, "inventory exposes its unchanged default slot count")
	assertions.equal(default_stack, int(grain_definition.get("max_stack", 0)), "game data exposes its unchanged default stack size")
	assertions.equal(economy_limit, default_capacity, "contract delivery limit matches default same-item inventory capacity")
	assertions.equal(economy_limit, default_slots * default_stack, "contract delivery limit derives from shared inventory constants")

	var fixture := _fixture([_profile("grain_npc", {"grain": 5})])
	var economy: Node = fixture.economy
	var over_limit := default_capacity + 1
	var oversized_contract := _contract_record()
	oversized_contract.quantity_per_day = over_limit
	oversized_contract.unit_price = 1
	oversized_contract.reward_gold = over_limit
	var oversized_state := {
		"last_processed_day": 0,
		"orders": [],
		"contracts": [oversized_contract],
	}
	var before: Dictionary = economy.call("to_dict")
	assertions.truthy(not bool(economy.call("validate_dict", oversized_state)), "shared max plus one contract fails validation")
	assertions.truthy(not bool(economy.call("from_dict", oversized_state)), "shared max plus one contract fails atomic restore")
	assertions.equal(economy.call("to_dict"), before, "oversized contract restore preserves authoritative state")

	economy.set("_contracts", [oversized_contract.duplicate(true)])
	assertions.truthy(not bool(economy.call("sign_contract", "grain_npc:grain:1:3")), "runtime signing rejects an oversized authoritative contract")
	oversized_contract.signed = true
	economy.set("_contracts", [oversized_contract.duplicate(true)])
	economy.set("_last_processed_day", 1)
	fixture.storage.configure(func() -> int: return over_limit)
	assertions.truthy(fixture.storage.add_items({"grain": over_limit}), "runtime defense fixture can physically hold max plus one")
	before = _asset_snapshot(fixture, "grain_npc", "grain")
	assertions.truthy(not bool(economy.call("deliver_contract", "grain_npc:grain:1:3", over_limit)), "runtime delivery rejects an oversized authoritative contract")
	_assert_assets(assertions, fixture, before, "grain_npc", "grain", "oversized runtime delivery")
	_free_fixture(fixture)


func _test_snapshots_and_strict_atomic_restore(assertions: TestAssert) -> void:
	var fixture := _fixture([_profile("daily_npc", {"iron_ore": 5}), _profile("grain_npc", {"grain": 5})])
	var economy: Node = fixture.economy
	if not economy.has_method("get_orders"):
		assertions.truthy(false, "snapshot tests require stable order API")
		_free_fixture(fixture)
		return
	economy.call("advance_order_deadlines", 12)
	economy.call("generate_demand_orders", 12)
	var snapshot: Array = economy.call("get_orders")
	var original_quantity := int(snapshot[0].quantity)
	snapshot[0].quantity = 999
	assertions.equal((economy.call("get_orders") as Array)[0].quantity, original_quantity, "order snapshots cannot mutate internal records")

	var valid_state: Dictionary = economy.call("to_dict")
	valid_state.contracts.append(_contract_record())
	valid_state.contracts[0]["expired"] = true
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
	malformed["last_processed_day"] = int(malformed.orders[0].expires_day) + 1
	malformed.orders[0]["expired"] = false
	assertions.truthy(not bool(economy.call("from_dict", malformed)), "cursor past order expiry rejects stale unexpired order state")
	assertions.equal(economy.call("to_dict"), before, "stale order rejection is atomic")
	malformed = before.duplicate(true)
	malformed.orders[0]["expired"] = true
	assertions.truthy(not bool(economy.call("from_dict", malformed)), "order cannot be expired before its deadline")
	assertions.equal(economy.call("to_dict"), before, "early-expiry rejection is atomic")
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
	assertions.truthy(fixture.storage.add_items({"grain": 5}), "save fixture prepares contract goods")
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


func _test_generation_requires_current_safe_day(assertions: TestAssert) -> void:
	var fixture := _fixture([_profile("daily_npc", {"iron_ore": 5})])
	var economy: Node = fixture.economy
	economy.call("advance_order_deadlines", 12)
	var before: Dictionary = economy.call("to_dict")
	assertions.equal(economy.call("generate_demand_orders", 13), false, "future generation day is rejected")
	assertions.equal(economy.call("to_dict"), before, "future generation adds no order and preserves cursor")
	assertions.equal(economy.call("generate_demand_orders", 0), false, "nonpositive generation day is rejected")
	assertions.equal(economy.call("generate_demand_orders", 12), true, "current generation day is accepted")
	assertions.equal((economy.call("get_orders") as Array).size(), 1, "accepted current day creates one shortage order")
	_free_fixture(fixture)

	fixture = _fixture([_profile("daily_npc", {"iron_ore": 5})])
	economy = fixture.economy
	economy.call("advance_order_deadlines", 9223372036854775807)
	before = economy.call("to_dict")
	assertions.equal(economy.call("generate_demand_orders", 9223372036854775807), false, "maximum integer generation day is rejected safely")
	assertions.equal(economy.call("to_dict"), before, "maximum day creates no wrapped ID or expiry")
	_free_fixture(fixture)


func _fixture(
	profiles: Array,
	iron_price: int = 100,
	grain_price: int = 10,
	npc_override: NpcEconomySystem = null,
	router_override: ItemContainerRouter = null
) -> Dictionary:
	var market := MarketSystemScript.new()
	market.configure([
		_definition("iron_ore", iron_price),
		_definition("grain", grain_price),
		_definition("grain_seed", 4),
	])
	var npc := npc_override if npc_override != null else NpcEconomySystemScript.new()
	npc.configure(market, profiles, [])
	var inventory := InventorySystemScript.new()
	var storage := FarmStorageSystemScript.new()
	var router := router_override if router_override != null else ItemContainerRouterScript.new()
	storage.configure(func() -> int: return 1000)
	router.configure(inventory, storage)
	var wallet := WalletDouble.new()
	var economy := EconomySystemScript.new()
	if economy.has_method("get_orders"):
		economy.call("configure", inventory, wallet, market, npc, router)
	else:
		economy.call("configure", inventory, wallet, market)
	return {
		"market": market,
		"npc": npc,
		"inventory": inventory,
		"storage": storage,
		"router": router,
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
		"player": fixture.economy.get_owned_quantity(item_id),
		"npc": fixture.npc.get_npc_state(npc_id).inventory.get(item_id, 0),
		"gold": fixture.wallet.gold,
	}


func _full_delivery_snapshot(fixture: Dictionary) -> Dictionary:
	return {
		"inventory": fixture.inventory.slots.duplicate(true),
		"quick": fixture.inventory.quick_slot_mappings.duplicate(),
		"storage": fixture.storage.get_items(),
		"npc": fixture.npc.to_dict(),
		"wallet": fixture.wallet.gold,
		"economy": fixture.economy.to_dict(),
	}


func _assert_assets(
	assertions: TestAssert,
	fixture: Dictionary,
	expected: Dictionary,
	npc_id: String,
	item_id: String,
	message: String
) -> void:
	assertions.equal(fixture.economy.get_owned_quantity(item_id), expected.player, message + " preserves player inventory")
	assertions.equal(fixture.npc.get_npc_state(npc_id).inventory.get(item_id, 0), expected.npc, message + " preserves NPC inventory")
	assertions.equal(fixture.wallet.gold, expected.gold, message + " preserves wallet")


func _free_fixture(fixture: Dictionary) -> void:
	for key in ["economy", "router", "storage", "inventory", "wallet", "npc", "market"]:
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


func _assert_reward_premium(
	assertions: TestAssert,
	order: Dictionary,
	market_sell_quote: int,
	minimum_percent: int,
	maximum_percent: int,
	message: String
) -> void:
	var reward := int(order.get("reward_gold", 0))
	assertions.truthy(market_sell_quote > 0, message + " market sell quote is positive")
	assertions.truthy(
		reward * 100 >= market_sell_quote * (100 + minimum_percent),
		message + " reward reaches the minimum premium over the real sell quote"
	)
	assertions.truthy(
		reward * 100 <= market_sell_quote * (100 + maximum_percent),
		message + " reward stays under the maximum premium over the real sell quote"
	)
	assertions.equal(reward, int(order.quantity) * int(order.unit_price), message + " reward remains quantity times integer unit price")


func _assert_string_id_signal(
	assertions: TestAssert,
	event_bus: Node,
	signal_name: String,
	argument_name: String
) -> void:
	assertions.truthy(event_bus.has_signal(signal_name), "EventBus exposes %s" % signal_name)
	for signal_data in event_bus.get_signal_list():
		if str(signal_data.get("name", "")) != signal_name:
			continue
		var arguments: Array = signal_data.get("args", [])
		assertions.equal(arguments.size(), 1, "%s exposes exactly one stable ID argument" % signal_name)
		if arguments.size() == 1:
			assertions.equal(str(arguments[0].get("name", "")), argument_name, "%s names its stable ID argument" % signal_name)
			assertions.equal(int(arguments[0].get("type", -1)), TYPE_STRING, "%s stable ID argument is String" % signal_name)
		return
