extends RefCounted

const EconomySystem = preload("res://scripts/systems/economy_system.gd")
const InventorySystem = preload("res://scripts/systems/inventory_system.gd")
const MarketSystem = preload("res://scripts/systems/market_system.gd")
const FarmStorageSystem = preload("res://scripts/systems/farm_storage_system.gd")
const ItemContainerRouter = preload("res://scripts/systems/item_container_router.gd")
const EconomyLimits = preload("res://scripts/core/economy_limits.gd")


class WalletDouble:
	extends Node

	var gold := 1000
	var fail_next_add := false
	var fail_next_spend := false
	var fail_all_add := false
	var fail_all_spend := false
	var _event_bus: Node

	func _ready() -> void:
		_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null

	func add_gold(amount: int) -> bool:
		if fail_all_add:
			if amount > 0:
				gold += amount
				_emit_gold_changed()
			return false
		if fail_next_add:
			fail_next_add = false
			if amount > 0:
				gold += amount
				_emit_gold_changed()
			return false
		if amount <= 0:
			return false
		gold += amount
		_emit_gold_changed()
		return true

	func spend_gold(amount: int) -> bool:
		if fail_all_spend:
			if amount > 0 and amount <= gold:
				gold -= amount
				_emit_gold_changed()
			return false
		if fail_next_spend:
			fail_next_spend = false
			if amount > 0 and amount <= gold:
				gold -= amount
				_emit_gold_changed()
			return false
		if amount <= 0 or amount > gold:
			return false
		gold -= amount
		_emit_gold_changed()
		return true

	func restore_gold_unchecked(value: int) -> bool:
		if value < 0 or value > EconomyLimits.MAX_SAFE_INTEGER:
			return false
		gold = value
		return true

	func can_restore_gold_unchecked() -> bool:
		return true

	func _emit_gold_changed() -> void:
		if _event_bus != null:
			_event_bus.gold_changed.emit(gold)


class InventoryDouble:
	extends InventorySystem

	var fail_next_add := false
	var fail_next_remove := false

	func add_item(item_id: String, quantity: int = 1) -> bool:
		if fail_next_add:
			fail_next_add = false
			super.add_item(item_id, quantity)
			return false
		return super.add_item(item_id, quantity)

	func remove_item(item_id: String, quantity: int = 1) -> bool:
		if fail_next_remove:
			fail_next_remove = false
			super.remove_item(item_id, quantity)
			return false
		return super.remove_item(item_id, quantity)


class UnrestorableWallet:
	extends Node

	var gold := 1000

	func add_gold(amount: int) -> bool:
		gold += amount
		return true

	func spend_gold(amount: int) -> bool:
		gold -= amount
		return true


class RejectingRestoreWallet:
	extends UnrestorableWallet

	func restore_gold_unchecked(_value: int) -> bool:
		return false

	func can_restore_gold_unchecked() -> bool:
		return false


class QuickMappingRecorder:
	extends RefCounted
	var events: Array[Dictionary] = []

	func on_mapping_changed(quick_index: int, item_id: String) -> void:
		events.append({"quick_index": quick_index, "item_id": item_id})


class MarketDouble:
	extends MarketSystem

	var fail_next_buy := false
	var fail_next_sell := false
	var fail_next_commit_end := false
	var fail_next_finalize := false
	var fail_all_restore := false
	var fail_next_rollback_dirty := false

	func stage_buy(transaction: Variant, item_id: String, quantity: int) -> bool:
		if fail_next_buy:
			fail_next_buy = false
			super.stage_buy(transaction, item_id, quantity)
			return false
		return super.stage_buy(transaction, item_id, quantity)

	func stage_sell(transaction: Variant, item_id: String, quantity: int) -> bool:
		if fail_next_sell:
			fail_next_sell = false
			super.stage_sell(transaction, item_id, quantity)
			return false
		return super.stage_sell(transaction, item_id, quantity)

	func seal_atomic_transaction(transaction: Variant) -> RefCounted:
		if fail_next_commit_end:
			fail_next_commit_end = false
			return null
		return super.seal_atomic_transaction(transaction)

	func finalize_sealed_publication(publication: Variant) -> RefCounted:
		if fail_next_finalize:
			fail_next_finalize = false
			return null
		return super.finalize_sealed_publication(publication)

	func rollback_atomic_transaction(transaction: Variant) -> bool:
		if fail_next_rollback_dirty:
			fail_next_rollback_dirty = false
			var staged := to_dict()
			super.rollback_atomic_transaction(transaction)
			super.from_dict(staged)
			return false
		return super.rollback_atomic_transaction(transaction)

	func from_dict(data: Dictionary) -> bool:
		if fail_all_restore:
			return false
		return super.from_dict(data)


class CapacityProvider:
	extends RefCounted

	var capacity := FarmStorageSystem.DEFAULT_CAPACITY

	func get_capacity() -> int:
		return capacity


class FailingStorage:
	extends FarmStorageSystem

	var fail_next_add := false
	var fail_next_remove := false

	func stage_add_items(token: Variant, requested: Dictionary) -> bool:
		if fail_next_add:
			fail_next_add = false
			super.stage_add_items(token, requested)
			return false
		return super.stage_add_items(token, requested)

	func stage_remove_items(token: Variant, requested: Dictionary) -> bool:
		if fail_next_remove:
			fail_next_remove = false
			super.stage_remove_items(token, requested)
			return false
		return super.stage_remove_items(token, requested)


class FailingRouter:
	extends ItemContainerRouter

	var fail_next_arm := false
	var fail_next_publish := false
	var fail_next_finalize := false

	func arm_sealed_transaction(publication: Variant) -> bool:
		if fail_next_arm:
			fail_next_arm = false
			return false
		return super.arm_sealed_transaction(publication)

	func publish_sealed_transaction(publication: Variant) -> bool:
		return super.publish_sealed_transaction(publication)

	func can_publish_sealed_transaction(
		publication: Variant,
		allow_blocked_event_bus: bool = false
	) -> bool:
		if fail_next_publish:
			fail_next_publish = false
			return false
		return super.can_publish_sealed_transaction(publication, allow_blocked_event_bus)

	func finalize_sealed_publication(publication: Variant) -> RefCounted:
		if fail_next_finalize:
			fail_next_finalize = false
			return null
		return super.finalize_sealed_publication(publication)


class TradeRecorder:
	extends RefCounted

	var economy: EconomySystem
	var router: ItemContainerRouter
	var wallet: WalletDouble
	var market: MarketSystem
	var item_events: Array[Dictionary] = []
	var gold_events: Array[int] = []
	var market_events: Array[Dictionary] = []
	var local_market_events: Array[Dictionary] = []
	var storage_events: Array[Dictionary] = []
	var storage_bus_events: Array[Dictionary] = []
	var storage_capacity_events: Array[Dictionary] = []
	var storage_capacity_bus_events: Array[Dictionary] = []
	var mapping_events: Array[Dictionary] = []
	var observations: Array[Dictionary] = []
	var attempt_reentry := false
	var reblock_before_reentry := false
	var attack_market_during_router_publish := false
	var reblock_on_local_market := false
	var market_attack_results: Dictionary = {}
	var reentry_results: Array[bool] = []

	func on_item_added(item_id: String, quantity: int) -> void:
		item_events.append({"kind": "add", "item_id": item_id, "quantity": quantity})
		_record_observation("item_added")

	func on_item_removed(item_id: String, quantity: int) -> void:
		item_events.append({"kind": "remove", "item_id": item_id, "quantity": quantity})
		_record_observation("item_removed")

	func on_gold_changed(gold: int) -> void:
		gold_events.append(gold)
		_record_observation("gold")

	func on_market_changed(item_id: String, stock: int) -> void:
		market_events.append({"item_id": item_id, "stock": stock})
		_record_observation("market_bus")

	func on_local_market_changed(item_id: String, stock: int) -> void:
		local_market_events.append({"item_id": item_id, "stock": stock})
		_record_observation("market_local")
		if reblock_on_local_market:
			var event_bus := (Engine.get_main_loop() as SceneTree).root.get_node("EventBus")
			event_bus.set_block_signals(true)

	func on_storage_changed(changes: Dictionary) -> void:
		storage_events.append(changes.duplicate(true))
		_record_observation("storage")
		if attack_market_during_router_publish:
			attack_market_during_router_publish = false
			var forged_finalized := RefCounted.new()
			market_attack_results = {
				"begin": market.begin_atomic_transaction(),
				"buy": market.commit_buy("grain", 1),
				"sell": market.commit_sell("grain", 1),
				"demand": market.add_external_demand("grain", 1),
				"supply": market.add_external_supply("grain", 1),
				"publish_null": (
					bool(market.call("publish_sealed_transaction", null))
					if market.has_method("publish_sealed_transaction")
					else false
				),
				"cancel_null": (
					bool(market.call("cancel_sealed_transaction", null))
					if market.has_method("cancel_sealed_transaction")
					else false
				),
				"dispatch_forged_finalized": market.dispatch_finalized_publication(forged_finalized),
				"cancel_forged_finalized": market.cancel_finalized_publication(forged_finalized),
				"legacy_publish": (
					bool(market.call("publish_deferred_atomic_events"))
					if market.has_method("publish_deferred_atomic_events")
					else false
				),
			}
		if attempt_reentry:
			attempt_reentry = false
			if reblock_before_reentry:
				var event_bus := (Engine.get_main_loop() as SceneTree).root.get_node("EventBus")
				event_bus.set_block_signals(true)
			reentry_results.append(economy.buy_item("grain_seed", 1))

	func on_storage_bus_changed(changes: Dictionary) -> void:
		storage_bus_events.append(changes.duplicate(true))
		_record_observation("storage_bus")

	func on_storage_capacity_changed(used: int, total: int) -> void:
		storage_capacity_events.append({"used": used, "total": total})
		_record_observation("storage_capacity")

	func on_storage_capacity_bus_changed(used: int, total: int) -> void:
		storage_capacity_bus_events.append({"used": used, "total": total})
		_record_observation("storage_capacity_bus")

	func on_mapping_changed(quick_index: int, item_id: String) -> void:
		mapping_events.append({"quick_index": quick_index, "item_id": item_id})
		_record_observation("mapping")

	func _record_observation(source: String) -> void:
		observations.append({
			"source": source,
			"gold": wallet.gold,
			"seed": router.get_count("grain_seed"),
			"crop": router.get_count("grain"),
			"seed_stock": market.get_stock("grain_seed"),
			"crop_stock": market.get_stock("grain"),
		})


class LegacyMarketDouble:
	extends Node

	var market := MarketSystem.new()

	func _init() -> void:
		add_child(market)
		market.configure([{
			"id": "wood",
			"base_price": 100,
			"initial_stock": 10,
			"target_stock": 10,
			"daily_liquidity": 10,
		}])

	func can_buy(item_id: String, quantity: int) -> bool:
		return market.can_buy(item_id, quantity)

	func quote_buy(item_id: String, quantity: int) -> int:
		return market.quote_buy(item_id, quantity)

	func quote_sell(item_id: String, quantity: int) -> int:
		return market.quote_sell(item_id, quantity)

	func commit_buy(item_id: String, quantity: int) -> bool:
		return market.commit_buy(item_id, quantity)

	func commit_sell(item_id: String, quantity: int) -> bool:
		return market.commit_sell(item_id, quantity)

	func to_dict() -> Dictionary:
		return market.to_dict()

	func from_dict(data: Dictionary) -> bool:
		return market.from_dict(data)

	func get_stock(item_id: String) -> int:
		return market.get_stock(item_id)


func run(assertions: TestAssert) -> void:
	_test_successful_buy_and_sell(assertions)
	_test_preflight_failures_preserve_state(assertions)
	_test_buy_rolls_back_each_mutation_boundary(assertions)
	_test_sell_rolls_back_each_mutation_boundary(assertions)
	_test_event_bus_only_observes_committed_trade(assertions)
	_test_mapping_signals_only_observe_committed_trade(assertions)
	_test_nested_market_transaction_is_preflight_failure(assertions)
	_test_market_without_optional_transaction_api_still_trades(assertions)
	_test_seed_and_crop_trade_through_authoritative_containers(assertions)
	_test_routed_trade_preflight_reports_stable_exact_failures(assertions)
	_test_routed_trade_failures_restore_all_domains(assertions)
	_test_routed_trade_bounds_and_ledger_preflight(assertions)
	_test_routed_finalization_failures_are_atomic(assertions)
	_test_routed_trade_rejects_unrestorable_wallet(assertions)
	_test_routed_router_lifecycle_is_required(assertions)
	_test_routed_trade_publication_is_final_and_nonreentrant(assertions)
	_test_router_listener_cannot_mutate_or_consume_market_publication(assertions)
	_test_finalized_dispatch_survives_destroyed_market(assertions)
	_test_routed_preflight_rejects_unpublishable_outer_state(assertions)


func _new_market() -> MarketDouble:
	var market := MarketDouble.new()
	market.configure([{
		"id": "wood",
		"base_price": 100,
		"initial_stock": 10,
		"target_stock": 10,
		"daily_liquidity": 10,
	}])
	return market


func _snapshot(inventory: InventorySystem, wallet: WalletDouble, market: MarketSystem) -> Dictionary:
	return {
		"gold": wallet.gold,
		"slots": inventory.slots.duplicate(true),
		"can_add_one": inventory.can_add_item("wood", 1),
		"market": market.to_dict(),
	}


func _assert_preserved(
	assertions: TestAssert,
	before: Dictionary,
	inventory: InventorySystem,
	wallet: WalletDouble,
	market: MarketSystem,
	message: String
) -> void:
	assertions.equal(wallet.gold, before["gold"], message + " preserves wallet")
	assertions.equal(inventory.slots, before["slots"], message + " preserves inventory")
	assertions.equal(inventory.can_add_item("wood", 1), before["can_add_one"], message + " preserves capacity")
	assertions.equal(market.to_dict(), before["market"], message + " preserves market and ledgers")


func _test_successful_buy_and_sell(assertions: TestAssert) -> void:
	var inventory := InventoryDouble.new()
	var wallet := WalletDouble.new()
	var market := _new_market()
	var economy := EconomySystem.new()
	assertions.truthy(economy.configure(inventory, wallet, market), "trade dependencies configure")
	var buy_total := market.quote_buy("wood", 2)
	assertions.truthy(economy.buy_item("wood", 2), "player buy succeeds")
	assertions.equal(wallet.gold, 1000 - buy_total, "buy spends authoritative wallet")
	assertions.equal(inventory.get_item_count("wood"), 2, "buy adds player items")
	assertions.equal(market.get_stock("wood"), 8, "buy removes finite market stock")
	assertions.equal(market.get_item_state("wood").get("demand"), 2, "buy records market demand")

	var sell_total := market.quote_sell("wood", 1)
	assertions.truthy(economy.sell_item("wood", 1), "player sale succeeds")
	assertions.equal(wallet.gold, 1000 - buy_total + sell_total, "sale credits authoritative wallet")
	assertions.equal(inventory.get_item_count("wood"), 1, "sale removes player items")
	assertions.equal(market.get_stock("wood"), 9, "sale adds finite market stock")
	assertions.equal(market.get_item_state("wood").get("supply"), 1, "sale records market supply")
	economy.free()
	market.free()
	inventory.free()
	wallet.free()


func _test_preflight_failures_preserve_state(assertions: TestAssert) -> void:
	var inventory := InventoryDouble.new()
	var wallet := WalletDouble.new()
	var market := _new_market()
	var economy := EconomySystem.new()
	assertions.truthy(economy.configure(inventory, wallet, market), "preflight fixture configures")

	wallet.gold = 1
	var before := _snapshot(inventory, wallet, market)
	assertions.truthy(not economy.buy_item("wood", 1), "insufficient gold rejects buy")
	_assert_preserved(assertions, before, inventory, wallet, market, "insufficient gold")

	wallet.gold = 1000
	before = _snapshot(inventory, wallet, market)
	assertions.truthy(not economy.buy_item("wood", 11), "insufficient market stock rejects buy")
	_assert_preserved(assertions, before, inventory, wallet, market, "insufficient market stock")

	for quantity in [0, -1]:
		before = _snapshot(inventory, wallet, market)
		assertions.truthy(not economy.buy_item("wood", quantity), "nonpositive buy is rejected")
		assertions.truthy(not economy.sell_item("wood", quantity), "nonpositive sale is rejected")
		_assert_preserved(assertions, before, inventory, wallet, market, "nonpositive quantity")

	var no_market_economy := EconomySystem.new()
	assertions.truthy(no_market_economy.configure(inventory, wallet), "market remains optional for configuration")
	before = _snapshot(inventory, wallet, market)
	assertions.truthy(not no_market_economy.buy_item("wood", 1), "buy requires market")
	assertions.truthy(not no_market_economy.sell_item("wood", 1), "sale requires market")
	_assert_preserved(assertions, before, inventory, wallet, market, "missing market")

	var missing_inventory_economy := EconomySystem.new()
	assertions.truthy(not missing_inventory_economy.configure(null, wallet, market), "missing inventory configuration is rejected")
	before = _snapshot(inventory, wallet, market)
	assertions.truthy(not missing_inventory_economy.buy_item("wood", 1), "missing inventory rejects buy")
	assertions.truthy(not missing_inventory_economy.sell_item("wood", 1), "missing inventory rejects sale")
	_assert_preserved(assertions, before, inventory, wallet, market, "missing inventory")

	var full_inventory := InventoryDouble.new()
	full_inventory.max_slots = 1
	full_inventory.reset_slots()
	assertions.truthy(full_inventory.add_item("stone", 99), "full inventory fixture fills its only slot")
	var full_economy := EconomySystem.new()
	assertions.truthy(full_economy.configure(full_inventory, wallet, market), "full inventory economy configures")
	before = _snapshot(full_inventory, wallet, market)
	assertions.truthy(not full_economy.buy_item("wood", 1), "full inventory rejects buy")
	_assert_preserved(assertions, before, full_inventory, wallet, market, "full inventory")

	full_economy.free()
	full_inventory.free()
	missing_inventory_economy.free()
	no_market_economy.free()
	economy.free()
	market.free()
	inventory.free()
	wallet.free()


func _test_buy_rolls_back_each_mutation_boundary(assertions: TestAssert) -> void:
	var inventory := InventoryDouble.new()
	var wallet := WalletDouble.new()
	var market := _new_market()
	var economy := EconomySystem.new()
	var stock_events: Array[int] = []
	market.market_stock_changed.connect(func(_item_id: String, stock: int) -> void: stock_events.append(stock))
	assertions.truthy(economy.configure(inventory, wallet, market), "buy rollback fixture configures")

	wallet.fail_next_spend = true
	var before := _snapshot(inventory, wallet, market)
	assertions.truthy(not economy.buy_item("wood", 1), "buy source removal failure is reported")
	_assert_preserved(assertions, before, inventory, wallet, market, "buy source removal failure")
	assertions.equal(stock_events, [], "buy source failure emits no market stock change")

	market.fail_next_buy = true
	before = _snapshot(inventory, wallet, market)
	assertions.truthy(not economy.buy_item("wood", 1), "buy market commit failure is reported")
	_assert_preserved(assertions, before, inventory, wallet, market, "buy market commit failure")
	assertions.equal(stock_events, [], "buy commit failure emits no market stock change")

	inventory.fail_next_add = true
	before = _snapshot(inventory, wallet, market)
	assertions.truthy(not economy.buy_item("wood", 1), "buy destination add failure is reported")
	_assert_preserved(assertions, before, inventory, wallet, market, "buy destination add failure")
	assertions.equal(stock_events, [], "buy destination failure emits no market stock change")

	economy.free()
	market.free()
	inventory.free()
	wallet.free()


func _test_sell_rolls_back_each_mutation_boundary(assertions: TestAssert) -> void:
	var inventory := InventoryDouble.new()
	var wallet := WalletDouble.new()
	var market := _new_market()
	var economy := EconomySystem.new()
	var stock_events: Array[int] = []
	market.market_stock_changed.connect(func(_item_id: String, stock: int) -> void: stock_events.append(stock))
	assertions.truthy(inventory.add_item("wood", 3), "sale rollback fixture owns items")
	assertions.truthy(economy.configure(inventory, wallet, market), "sale rollback fixture configures")

	inventory.fail_next_remove = true
	var before := _snapshot(inventory, wallet, market)
	assertions.truthy(not economy.sell_item("wood", 1), "sale source removal failure is reported")
	_assert_preserved(assertions, before, inventory, wallet, market, "sale source removal failure")
	assertions.equal(stock_events, [], "sale source failure emits no market stock change")

	market.fail_next_sell = true
	before = _snapshot(inventory, wallet, market)
	assertions.truthy(not economy.sell_item("wood", 1), "sale market commit failure is reported")
	_assert_preserved(assertions, before, inventory, wallet, market, "sale market commit failure")
	assertions.equal(stock_events, [], "sale commit failure emits no market stock change")

	wallet.fail_next_add = true
	before = _snapshot(inventory, wallet, market)
	assertions.truthy(not economy.sell_item("wood", 1), "sale destination add failure is reported")
	_assert_preserved(assertions, before, inventory, wallet, market, "sale destination add failure")
	assertions.equal(stock_events, [], "sale destination failure emits no market stock change")

	economy.free()
	market.free()
	inventory.free()
	wallet.free()


func _test_event_bus_only_observes_committed_trade(assertions: TestAssert) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var event_bus := tree.root.get_node_or_null("EventBus")
	assertions.truthy(event_bus != null, "transaction signal fixture finds EventBus")
	if event_bus == null:
		return
	var inventory := InventoryDouble.new()
	var wallet := WalletDouble.new()
	var market := _new_market()
	var economy := EconomySystem.new()
	tree.root.add_child(inventory)
	tree.root.add_child(wallet)
	tree.root.add_child(market)
	tree.root.add_child(economy)
	assertions.truthy(economy.configure(inventory, wallet, market), "transaction signal fixture configures")

	var gold_events: Array[int] = []
	var item_events: Array[Dictionary] = []
	var market_events: Array[Dictionary] = []
	var on_gold := func(gold: int) -> void: gold_events.append(gold)
	var on_item := func(item_id: String, quantity: int) -> void:
		item_events.append({"item_id": item_id, "quantity": quantity})
	var on_market := func(item_id: String, stock: int) -> void:
		market_events.append({"item_id": item_id, "stock": stock})
	event_bus.gold_changed.connect(on_gold)
	event_bus.item_added.connect(on_item)
	event_bus.market_stock_changed.connect(on_market)

	inventory.fail_next_add = true
	assertions.truthy(not economy.buy_item("wood", 1), "failed observed trade is rejected")
	assertions.equal(gold_events, [], "failed trade publishes no gold event")
	assertions.equal(item_events, [], "failed trade publishes no inventory event")
	assertions.equal(market_events, [], "failed trade publishes no market event")

	var total := market.quote_buy("wood", 1)
	assertions.truthy(economy.buy_item("wood", 1), "observed trade succeeds")
	assertions.equal(gold_events, [1000 - total], "successful trade publishes one final gold event")
	assertions.equal(item_events, [{"item_id": "wood", "quantity": 1}], "successful trade publishes one item event")
	assertions.equal(market_events, [{"item_id": "wood", "stock": 9}], "successful trade publishes one market event")

	event_bus.gold_changed.disconnect(on_gold)
	event_bus.item_added.disconnect(on_item)
	event_bus.market_stock_changed.disconnect(on_market)
	economy.free()
	market.free()
	inventory.free()
	wallet.free()


func _test_mapping_signals_only_observe_committed_trade(assertions: TestAssert) -> void:
	var inventory := InventoryDouble.new()
	var wallet := WalletDouble.new()
	var market := _new_market()
	var economy := EconomySystem.new()
	inventory.set_quick_slot(0, 5)
	var recorder := QuickMappingRecorder.new()
	inventory.quick_slot_mapping_changed.connect(recorder.on_mapping_changed)
	assertions.truthy(economy.configure(inventory, wallet, market), "mapping trade fixture configures")

	inventory.fail_next_add = true
	assertions.truthy(not economy.buy_item("wood", 1), "failed mapped buy rolls back")
	assertions.equal(recorder.events, [], "failed buy emits no transient mapping signals")
	assertions.truthy(economy.buy_item("wood", 1), "successful mapped buy commits")
	assertions.equal(
		recorder.events,
		[{"quick_index": 5, "item_id": "wood"}],
		"successful buy emits one net mapping signal"
	)

	recorder.events.clear()
	wallet.fail_next_add = true
	assertions.truthy(not economy.sell_item("wood", 1), "failed mapped sell rolls back")
	assertions.equal(recorder.events, [], "failed sell emits no transient mapping signals")
	assertions.truthy(economy.sell_item("wood", 1), "successful mapped sell commits")
	assertions.equal(
		recorder.events,
		[{"quick_index": 5, "item_id": ""}],
		"successful sell emits one net mapping signal"
	)

	economy.free()
	market.free()
	inventory.free()
	wallet.free()


func _test_nested_market_transaction_is_preflight_failure(assertions: TestAssert) -> void:
	_run_nested_market_rejection(assertions, true, true, false, "nested buy with destination failure")
	_run_nested_market_rejection(assertions, false, true, false, "otherwise valid nested buy")
	_run_nested_market_rejection(assertions, false, false, false, "otherwise valid nested sale")
	_run_nested_market_rejection(assertions, false, true, true, "nested buy preserves outer queue")


func _run_nested_market_rejection(
	assertions: TestAssert,
	inject_destination_failure: bool,
	is_buy: bool,
	queue_outer_stock_event: bool,
	message: String
) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var event_bus := tree.root.get_node_or_null("EventBus")
	assertions.truthy(event_bus != null, message + " finds EventBus")
	if event_bus == null:
		return
	var inventory := InventoryDouble.new()
	var wallet := WalletDouble.new()
	var market := _new_market()
	var economy := EconomySystem.new()
	tree.root.add_child(inventory)
	tree.root.add_child(wallet)
	tree.root.add_child(market)
	tree.root.add_child(economy)
	assertions.truthy(economy.configure(inventory, wallet, market), message + " configures")
	if not is_buy:
		assertions.truthy(inventory.add_item("wood", 2), message + " prepares sale inventory")

	var local_stock_events: Array[int] = []
	var bus_gold_events: Array[int] = []
	var bus_item_events: Array[Dictionary] = []
	var bus_stock_events: Array[int] = []
	var on_local_stock := func(_item_id: String, stock: int) -> void: local_stock_events.append(stock)
	var on_gold := func(gold: int) -> void: bus_gold_events.append(gold)
	var on_item := func(item_id: String, quantity: int) -> void:
		bus_item_events.append({"item_id": item_id, "quantity": quantity})
	var on_bus_stock := func(_item_id: String, stock: int) -> void: bus_stock_events.append(stock)
	market.market_stock_changed.connect(on_local_stock)
	event_bus.gold_changed.connect(on_gold)
	event_bus.item_added.connect(on_item)
	event_bus.market_stock_changed.connect(on_bus_stock)

	var outer_transaction: Variant = market.begin_atomic_transaction()
	assertions.truthy(outer_transaction != null, message + " acquires outer market transaction")
	if queue_outer_stock_event:
		assertions.truthy(
			market.stage_buy(outer_transaction, "wood", 1),
			message + " queues outer stock event"
		)
	var before := _snapshot(inventory, wallet, market)
	inventory.fail_next_add = inject_destination_failure
	var trade_result := economy.buy_item("wood", 1) if is_buy else economy.sell_item("wood", 1)
	assertions.truthy(not trade_result, message + " is rejected")
	_assert_preserved(assertions, before, inventory, wallet, market, message)
	assertions.equal(
		inventory.fail_next_add,
		inject_destination_failure,
		message + " never reaches inventory destination"
	)
	assertions.truthy(
		market.end_atomic_transaction(outer_transaction, true),
		message + " releases outer transaction"
	)
	var expected_stock_events: Array = [9] if queue_outer_stock_event else []
	assertions.equal(local_stock_events, expected_stock_events, message + " preserves local outer queue")
	assertions.equal(bus_gold_events, [], message + " emits no gold signal")
	assertions.equal(bus_item_events, [], message + " emits no inventory signal")
	assertions.equal(bus_stock_events, expected_stock_events, message + " preserves EventBus outer queue")
	_assert_preserved(assertions, before, inventory, wallet, market, message + " after outer commit")

	market.market_stock_changed.disconnect(on_local_stock)
	event_bus.gold_changed.disconnect(on_gold)
	event_bus.item_added.disconnect(on_item)
	event_bus.market_stock_changed.disconnect(on_bus_stock)
	economy.free()
	market.free()
	inventory.free()
	wallet.free()


func _test_market_without_optional_transaction_api_still_trades(assertions: TestAssert) -> void:
	var inventory := InventoryDouble.new()
	var wallet := WalletDouble.new()
	var market := LegacyMarketDouble.new()
	var economy := EconomySystem.new()
	assertions.truthy(economy.configure(inventory, wallet, market), "legacy market configures")
	var total := market.quote_buy("wood", 1)
	assertions.truthy(economy.buy_item("wood", 1), "legacy market without transaction methods can trade")
	assertions.equal(wallet.gold, 1000 - total, "legacy market trade spends wallet")
	assertions.equal(inventory.get_item_count("wood"), 1, "legacy market trade adds inventory")
	assertions.equal(market.get_stock("wood"), 9, "legacy market trade commits stock")
	economy.free()
	market.free()
	inventory.free()
	wallet.free()


func _market_definition(item_id: String, base_price: int, stock: int) -> Dictionary:
	return {
		"id": item_id,
		"base_price": base_price,
		"initial_stock": stock,
		"target_stock": maxi(stock, 1),
		"daily_liquidity": 20,
	}


func _item_slot(inventory: InventorySystem, item_id: String) -> int:
	for index in range(inventory.slots.size()):
		if str(inventory.slots[index].get("item_id", "")) == item_id:
			return index
	return -1


func _make_routed_fixture(capacity: int = FarmStorageSystem.DEFAULT_CAPACITY) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var inventory := InventoryDouble.new()
	var wallet := WalletDouble.new()
	var market := MarketDouble.new()
	var storage := FailingStorage.new()
	var provider := CapacityProvider.new()
	var router := FailingRouter.new()
	var economy := EconomySystem.new()
	provider.capacity = capacity
	market.configure([
		_market_definition("wood", 100, 10),
		_market_definition("grain_seed", 4, 10),
		_market_definition("grain", 28, 10),
	])
	for node in [inventory, wallet, market, storage, router, economy]:
		tree.root.add_child(node)
	storage.configure(Callable(provider, "get_capacity"))
	router.configure(inventory, storage)
	economy.configure(inventory, wallet, market, null, router)
	return {
		"inventory": inventory,
		"wallet": wallet,
		"market": market,
		"storage": storage,
		"provider": provider,
		"router": router,
		"economy": economy,
	}


func _free_routed_fixture(fixture: Dictionary) -> void:
	for key in ["economy", "router", "storage", "market", "wallet", "inventory"]:
		var node: Variant = fixture.get(key)
		if is_instance_valid(node):
			node.free()


func _routed_snapshot(fixture: Dictionary) -> Dictionary:
	var inventory: InventorySystem = fixture.inventory
	var storage: FarmStorageSystem = fixture.storage
	var wallet: WalletDouble = fixture.wallet
	var market: MarketSystem = fixture.market
	return {
		"gold": wallet.gold,
		"slots": inventory.slots.duplicate(true),
		"mappings": inventory.quick_slot_mappings.duplicate(),
		"storage": storage.get_items().duplicate(true),
		"market": market.to_dict(),
	}


func _assert_routed_snapshot(
	assertions: TestAssert,
	expected: Dictionary,
	fixture: Dictionary,
	message: String
) -> void:
	var inventory: InventorySystem = fixture.inventory
	assertions.equal(fixture.wallet.gold, expected.gold, message + " preserves wallet")
	assertions.equal(inventory.slots, expected.slots, message + " preserves inventory slots")
	assertions.equal(
		inventory.quick_slot_mappings,
		expected.mappings,
		message + " preserves quick mappings"
	)
	assertions.equal(fixture.storage.get_items(), expected.storage, message + " preserves storage")
	assertions.equal(fixture.market.to_dict(), expected.market, message + " preserves market")


func _connect_trade_recorder(fixture: Dictionary) -> TradeRecorder:
	var recorder := TradeRecorder.new()
	recorder.economy = fixture.economy
	recorder.router = fixture.router
	recorder.wallet = fixture.wallet
	recorder.market = fixture.market
	var event_bus := (Engine.get_main_loop() as SceneTree).root.get_node("EventBus")
	event_bus.item_added.connect(recorder.on_item_added)
	event_bus.item_removed.connect(recorder.on_item_removed)
	event_bus.gold_changed.connect(recorder.on_gold_changed)
	event_bus.market_stock_changed.connect(recorder.on_market_changed)
	event_bus.farm_storage_changed.connect(recorder.on_storage_bus_changed)
	event_bus.farm_storage_capacity_changed.connect(recorder.on_storage_capacity_bus_changed)
	fixture.market.market_stock_changed.connect(recorder.on_local_market_changed)
	fixture.storage.contents_changed.connect(recorder.on_storage_changed)
	fixture.storage.capacity_changed.connect(recorder.on_storage_capacity_changed)
	fixture.inventory.quick_slot_mapping_changed.connect(recorder.on_mapping_changed)
	return recorder


func _disconnect_trade_recorder(fixture: Dictionary, recorder: TradeRecorder) -> void:
	var event_bus := (Engine.get_main_loop() as SceneTree).root.get_node("EventBus")
	event_bus.item_added.disconnect(recorder.on_item_added)
	event_bus.item_removed.disconnect(recorder.on_item_removed)
	event_bus.gold_changed.disconnect(recorder.on_gold_changed)
	event_bus.market_stock_changed.disconnect(recorder.on_market_changed)
	event_bus.farm_storage_changed.disconnect(recorder.on_storage_bus_changed)
	event_bus.farm_storage_capacity_changed.disconnect(recorder.on_storage_capacity_bus_changed)
	fixture.market.market_stock_changed.disconnect(recorder.on_local_market_changed)
	fixture.storage.contents_changed.disconnect(recorder.on_storage_changed)
	fixture.storage.capacity_changed.disconnect(recorder.on_storage_capacity_changed)
	fixture.inventory.quick_slot_mapping_changed.disconnect(recorder.on_mapping_changed)


func _assert_trade_recorder_silent(
	assertions: TestAssert,
	recorder: TradeRecorder,
	message: String
) -> void:
	assertions.equal(recorder.item_events, [], message + " emits no item event")
	assertions.equal(recorder.gold_events, [], message + " emits no gold event")
	assertions.equal(recorder.market_events, [], message + " emits no market bus event")
	assertions.equal(recorder.local_market_events, [], message + " emits no local market event")
	assertions.equal(recorder.storage_events, [], message + " emits no storage event")
	assertions.equal(recorder.storage_bus_events, [], message + " emits no storage bus event")
	assertions.equal(recorder.storage_capacity_events, [], message + " emits no storage capacity event")
	assertions.equal(
		recorder.storage_capacity_bus_events,
		[],
		message + " emits no storage capacity bus event"
	)
	assertions.equal(recorder.mapping_events, [], message + " emits no mapping event")


func _test_seed_and_crop_trade_through_authoritative_containers(assertions: TestAssert) -> void:
	var fixture := _make_routed_fixture()
	var economy: EconomySystem = fixture.economy
	var inventory: InventorySystem = fixture.inventory
	var storage: FarmStorageSystem = fixture.storage
	assertions.truthy(economy.has_method("get_owned_quantity"), "economy exposes routed owned quantity")
	assertions.truthy(economy.has_method("quote_trade_failure"), "economy exposes stable trade preflight")
	if not economy.has_method("get_owned_quantity") or not economy.has_method("quote_trade_failure"):
		_free_routed_fixture(fixture)
		return

	assertions.truthy(economy.buy_item("grain_seed", 3), "seed purchase succeeds")
	assertions.equal(inventory.get_item_count("grain_seed"), 3, "seed purchase enters backpack")
	assertions.equal(storage.get_count("grain_seed"), 0, "seed purchase never enters storage")
	assertions.equal(economy.get_owned_quantity("grain_seed"), 3, "seed ownership reads backpack")
	var inventory_after_seed := inventory.slots.duplicate(true)

	assertions.truthy(economy.buy_item("grain", 4), "crop purchase succeeds")
	assertions.equal(storage.get_count("grain"), 4, "crop purchase enters farm storage")
	assertions.equal(inventory.get_item_count("grain"), 0, "crop purchase never enters backpack")
	assertions.equal(inventory.slots, inventory_after_seed, "crop purchase leaves backpack untouched")
	assertions.equal(economy.get_owned_quantity("grain"), 4, "crop ownership reads storage")

	assertions.truthy(economy.sell_item("grain_seed", 2), "seed sale succeeds")
	assertions.equal(inventory.get_item_count("grain_seed"), 1, "seed sale removes from backpack")
	assertions.equal(storage.get_count("grain"), 4, "seed sale leaves crop storage untouched")
	assertions.truthy(economy.sell_item("grain", 3), "crop sale succeeds")
	assertions.equal(storage.get_count("grain"), 1, "crop sale removes from storage")
	assertions.equal(inventory.get_item_count("grain_seed"), 1, "crop sale leaves backpack untouched")
	_free_routed_fixture(fixture)


func _test_routed_trade_preflight_reports_stable_exact_failures(assertions: TestAssert) -> void:
	var fixture := _make_routed_fixture()
	var economy: EconomySystem = fixture.economy
	if not economy.has_method("quote_trade_failure"):
		assertions.truthy(false, "routed trade preflight API exists")
		_free_routed_fixture(fixture)
		return

	fixture.wallet.gold = 0
	var result: Dictionary = economy.quote_trade_failure("grain_seed", 1, true)
	assertions.equal(result.get("reason"), "insufficient_gold", "buy reports insufficient gold")
	var before := _routed_snapshot(fixture)
	assertions.truthy(not economy.buy_item("grain_seed", 1), "insufficient gold rejects seed buy")
	_assert_routed_snapshot(assertions, before, fixture, "insufficient gold")

	fixture.wallet.gold = 1000
	result = economy.quote_trade_failure("grain", 11, true)
	assertions.equal(result.get("reason"), "market_stock", "buy reports finite market stock")
	before = _routed_snapshot(fixture)
	assertions.truthy(not economy.buy_item("grain", 11), "market stock rejects crop buy")
	_assert_routed_snapshot(assertions, before, fixture, "market stock")
	_free_routed_fixture(fixture)

	fixture = _make_routed_fixture()
	fixture.inventory.max_slots = 1
	fixture.inventory.reset_slots()
	fixture.inventory.add_item("stone", 99)
	result = fixture.economy.quote_trade_failure("grain_seed", 2, true)
	assertions.equal(result.get("reason"), "inventory_capacity", "seed buy reports backpack capacity")
	assertions.equal(result.get("item_id"), "grain_seed", "backpack failure identifies seed")
	assertions.equal(result.get("missing_quantity"), 2, "backpack failure reports exact missing items")
	before = _routed_snapshot(fixture)
	assertions.truthy(not fixture.economy.buy_item("grain_seed", 2), "full backpack rejects seed buy")
	_assert_routed_snapshot(assertions, before, fixture, "full backpack")
	_free_routed_fixture(fixture)

	fixture = _make_routed_fixture(3)
	fixture.storage.add_items({"grain": 2})
	result = fixture.economy.quote_trade_failure("grain", 2, true)
	assertions.equal(result.get("reason"), "storage_capacity", "crop buy reports storage capacity")
	assertions.equal(result.get("missing_capacity"), 1, "storage failure reports exact missing capacity")
	before = _routed_snapshot(fixture)
	assertions.truthy(not fixture.economy.buy_item("grain", 2), "full storage rejects crop buy")
	_assert_routed_snapshot(assertions, before, fixture, "full storage")
	_free_routed_fixture(fixture)

	fixture = _make_routed_fixture(1)
	fixture.storage.restore_items_unchecked({"grain": 2})
	result = fixture.economy.quote_trade_failure("grain", 1, true)
	assertions.equal(result.get("reason"), "storage_capacity", "overload blocks crop additions")
	assertions.equal(result.get("missing_capacity"), 2, "overload reports capacity needed to fit addition")
	before = _routed_snapshot(fixture)
	assertions.truthy(not fixture.economy.buy_item("grain", 1), "overloaded storage rejects crop buy")
	_assert_routed_snapshot(assertions, before, fixture, "overloaded storage")
	_free_routed_fixture(fixture)

	fixture = _make_routed_fixture()
	result = fixture.economy.quote_trade_failure("grain_seed", 2, false)
	assertions.equal(result.get("reason"), "insufficient_seed", "seed sale reports seed shortage")
	assertions.equal(result.get("missing_quantity"), 2, "seed shortage reports exact quantity")
	before = _routed_snapshot(fixture)
	assertions.truthy(not fixture.economy.sell_item("grain_seed", 2), "seed shortage rejects sale")
	_assert_routed_snapshot(assertions, before, fixture, "seed shortage")
	result = fixture.economy.quote_trade_failure("grain", 3, false)
	assertions.equal(result.get("reason"), "insufficient_crop", "crop sale reports crop shortage")
	assertions.equal(result.get("missing_quantity"), 3, "crop shortage reports exact quantity")
	before = _routed_snapshot(fixture)
	assertions.truthy(not fixture.economy.sell_item("grain", 3), "crop shortage rejects sale")
	_assert_routed_snapshot(assertions, before, fixture, "crop shortage")
	fixture.storage.add_items({"grain": 1})
	fixture.wallet.gold = EconomyLimits.MAX_SAFE_INTEGER
	result = fixture.economy.quote_trade_failure("grain", 1, false)
	assertions.equal(result.get("reason"), "wallet_overflow", "sale reports wallet overflow")
	before = _routed_snapshot(fixture)
	assertions.truthy(not fixture.economy.sell_item("grain", 1), "wallet overflow rejects crop sale")
	_assert_routed_snapshot(assertions, before, fixture, "wallet overflow")
	_free_routed_fixture(fixture)


func _test_routed_trade_failures_restore_all_domains(assertions: TestAssert) -> void:
	var cases := [
		{"name": "wallet spend", "is_buy": true, "item_id": "grain_seed", "failure": "spend"},
		{"name": "market buy commit", "is_buy": true, "item_id": "grain", "failure": "market_buy"},
		{"name": "container buy finalize", "is_buy": true, "item_id": "grain", "failure": "container_finalize"},
		{"name": "container sale mutation", "is_buy": false, "item_id": "grain", "failure": "storage_remove"},
		{"name": "market sale commit", "is_buy": false, "item_id": "grain_seed", "failure": "market_sell"},
		{"name": "wallet credit", "is_buy": false, "item_id": "grain", "failure": "add"},
	]
	for case_value in cases:
		var case := case_value as Dictionary
		var fixture := _make_routed_fixture()
		if not bool(case.is_buy):
			fixture.router.add_items({str(case.item_id): 2})
			if str(case.item_id) == "grain_seed":
				var slot_index := _item_slot(fixture.inventory, "grain_seed")
				fixture.inventory.set_quick_slot(slot_index, 0)
		var recorder := _connect_trade_recorder(fixture)
		match str(case.failure):
			"spend":
				fixture.wallet.fail_next_spend = true
			"market_buy":
				fixture.market.fail_next_buy = true
			"container_finalize":
				fixture.router.fail_next_finalize = true
			"storage_remove":
				fixture.storage.fail_next_remove = true
			"market_sell":
				fixture.market.fail_next_sell = true
			"add":
				fixture.wallet.fail_next_add = true
		var before := _routed_snapshot(fixture)
		var traded: bool = (
			fixture.economy.buy_item(str(case.item_id), 1)
			if bool(case.is_buy)
			else fixture.economy.sell_item(str(case.item_id), 1)
		)
		assertions.truthy(not traded, str(case.name) + " failure is reported")
		_assert_routed_snapshot(assertions, before, fixture, str(case.name))
		_assert_trade_recorder_silent(assertions, recorder, str(case.name))
		_disconnect_trade_recorder(fixture, recorder)
		_free_routed_fixture(fixture)


func _test_routed_trade_bounds_and_ledger_preflight(assertions: TestAssert) -> void:
	var fixture := _make_routed_fixture()
	var before := _routed_snapshot(fixture)
	var started := Time.get_ticks_usec()
	var result: Dictionary = fixture.economy.quote_trade_failure(
		"grain_seed", EconomyLimits.MAX_SAFE_INTEGER, true
	)
	var elapsed := Time.get_ticks_usec() - started
	assertions.equal(result.get("reason"), "invalid_request", "huge trade quantity is invalid")
	assertions.truthy(elapsed < 100_000, "huge trade quote returns without per-unit iteration")
	_assert_routed_snapshot(assertions, before, fixture, "huge trade quote")
	result = fixture.economy.quote_trade_failure(
		"grain_seed", EconomyLimits.MAX_TRADE_QUANTITY + 1, true
	)
	assertions.equal(result.get("reason"), "invalid_request", "trade limit plus one is invalid")

	var market_state: Dictionary = fixture.market.to_dict()
	market_state["items"]["grain_seed"]["demand"] = EconomyLimits.MAX_SAFE_INTEGER
	assertions.truthy(fixture.market.from_dict(market_state), "buy ledger boundary fixture restores")
	before = _routed_snapshot(fixture)
	result = fixture.economy.quote_trade_failure("grain_seed", 1, true)
	assertions.equal(result.get("reason"), "market_ledger_overflow", "buy demand overflow is stable")
	assertions.truthy(not fixture.economy.buy_item("grain_seed", 1), "buy demand overflow rejects trade")
	_assert_routed_snapshot(assertions, before, fixture, "buy demand overflow")
	_free_routed_fixture(fixture)

	fixture = _make_routed_fixture()
	fixture.router.add_items({"grain": 1})
	market_state = fixture.market.to_dict()
	market_state["items"]["grain"]["supply"] = EconomyLimits.MAX_SAFE_INTEGER
	assertions.truthy(fixture.market.from_dict(market_state), "sale ledger boundary fixture restores")
	before = _routed_snapshot(fixture)
	result = fixture.economy.quote_trade_failure("grain", 1, false)
	assertions.equal(result.get("reason"), "market_ledger_overflow", "sale supply overflow is stable")
	assertions.truthy(not fixture.economy.sell_item("grain", 1), "sale supply overflow rejects trade")
	_assert_routed_snapshot(assertions, before, fixture, "sale supply overflow")
	_free_routed_fixture(fixture)

	fixture = _make_routed_fixture()
	fixture.router.add_items({"grain": 1})
	market_state = fixture.market.to_dict()
	market_state["items"]["grain"]["stock"] = EconomyLimits.MAX_SAFE_INTEGER
	assertions.truthy(fixture.market.from_dict(market_state), "sale stock boundary fixture restores")
	before = _routed_snapshot(fixture)
	result = fixture.economy.quote_trade_failure("grain", 1, false)
	assertions.equal(result.get("reason"), "market_ledger_overflow", "sale stock overflow is stable")
	assertions.truthy(not fixture.economy.sell_item("grain", 1), "sale stock overflow rejects trade")
	_assert_routed_snapshot(assertions, before, fixture, "sale stock overflow")
	_free_routed_fixture(fixture)


func _test_routed_finalization_failures_are_atomic(assertions: TestAssert) -> void:
	for failure in [
		"market_seal", "market_finalize", "router_finalize",
		"rollback_false_dirty_market", "persistent_market_restore",
		"persistent_wallet_compensation"
	]:
		var fixture := _make_routed_fixture()
		var recorder := _connect_trade_recorder(fixture)
		var before := _routed_snapshot(fixture)
		match failure:
			"market_seal":
				fixture.market.fail_next_commit_end = true
			"market_finalize":
				fixture.market.fail_next_finalize = true
			"router_finalize":
				fixture.router.fail_next_finalize = true
			"rollback_false_dirty_market":
				fixture.market.fail_next_buy = true
				fixture.market.fail_next_rollback_dirty = true
			"persistent_market_restore":
				fixture.market.fail_next_buy = true
				fixture.market.fail_all_restore = true
			"persistent_wallet_compensation":
				fixture.wallet.fail_all_spend = true
		assertions.truthy(not fixture.economy.buy_item("grain_seed", 1), failure + " is reported")
		_assert_routed_snapshot(assertions, before, fixture, failure)
		_assert_trade_recorder_silent(assertions, recorder, failure)
		var router_probe: Variant = fixture.router.begin_atomic_transaction()
		assertions.truthy(router_probe != null, failure + " releases Router lock")
		if router_probe != null:
			fixture.router.rollback_atomic_transaction(router_probe)
		var market_probe: Variant = fixture.market.begin_atomic_transaction()
		assertions.truthy(market_probe != null, failure + " releases Market lock")
		if market_probe != null:
			fixture.market.rollback_atomic_transaction(market_probe)
		_disconnect_trade_recorder(fixture, recorder)
		_free_routed_fixture(fixture)


func _test_routed_router_lifecycle_is_required(assertions: TestAssert) -> void:
	var fixture := _make_routed_fixture()
	var router: ItemContainerRouter = fixture.router
	fixture.erase("router")
	router.free()
	var before := _routed_snapshot(fixture)
	var result: Dictionary = fixture.economy.quote_trade_failure("grain_seed", 1, true)
	assertions.equal(result.get("reason"), "transaction_failed", "freed required router is stable")
	assertions.truthy(not fixture.economy.buy_item("grain_seed", 1), "freed router cannot use legacy path")
	_assert_routed_snapshot(assertions, before, fixture, "freed required router")
	_free_routed_fixture(fixture)


func _test_routed_trade_rejects_unrestorable_wallet(assertions: TestAssert) -> void:
	_test_routed_wallet_capability_rejection(assertions, UnrestorableWallet.new(), "missing")
	_test_routed_wallet_capability_rejection(assertions, RejectingRestoreWallet.new(), "persistent")


func _test_routed_wallet_capability_rejection(
	assertions: TestAssert,
	wallet: Node,
	label: String
) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var inventory := InventoryDouble.new()
	var market := MarketDouble.new()
	var storage := FailingStorage.new()
	var router := FailingRouter.new()
	var economy := EconomySystem.new()
	market.configure([_market_definition("grain_seed", 4, 10)])
	for node in [inventory, wallet, market, storage, router, economy]:
		tree.root.add_child(node)
	storage.configure()
	router.configure(inventory, storage)
	assertions.truthy(
		not economy.configure(inventory, wallet, market, null, router),
		"routed economy rejects " + label + " exact restore capability"
	)
	assertions.equal(
		economy.quote_trade_failure("grain_seed", 1, true).get("reason"),
		"not_configured",
		label + " restore capability fails before mutation"
	)
	assertions.truthy(not economy.buy_item("grain_seed", 1), label + " restore wallet cannot trade")
	assertions.equal(wallet.get("gold"), 1000, label + " restore wallet is unchanged")
	assertions.equal(inventory.get_item_count("grain_seed"), 0, label + " restore inventory is unchanged")
	assertions.equal(market.get_stock("grain_seed"), 10, label + " restore market is unchanged")
	for node in [economy, router, storage, market, wallet, inventory]:
		node.free()


func _test_routed_trade_publication_is_final_and_nonreentrant(assertions: TestAssert) -> void:
	var fixture := _make_routed_fixture()
	var recorder := _connect_trade_recorder(fixture)
	recorder.attempt_reentry = true
	recorder.reblock_before_reentry = true
	var before_gold: int = fixture.wallet.gold
	var crop_total: int = fixture.market.quote_buy("grain", 2)
	assertions.truthy(fixture.economy.buy_item("grain", 2), "observed crop buy succeeds")
	assertions.equal(recorder.reentry_results, [false], "trade listener cannot start a nested trade")
	var event_bus := (Engine.get_main_loop() as SceneTree).root.get_node("EventBus")
	assertions.truthy(not event_bus.is_blocking_signals(), "listener reblock is cleared before final events")
	assertions.equal(fixture.router.get_count("grain_seed"), 0, "reentrant seed buy changes nothing")
	assertions.equal(recorder.storage_events, [{"grain": 2}], "crop buy publishes one storage delta")
	assertions.equal(recorder.item_events, [], "crop buy publishes no backpack item event")
	assertions.equal(recorder.gold_events, [before_gold - crop_total], "crop buy publishes final gold once")
	assertions.equal(
		recorder.market_events,
		[{"item_id": "grain", "stock": 8}],
		"crop buy publishes final market stock once"
	)
	for observation in recorder.observations:
		assertions.equal(observation.gold, before_gold - crop_total, "listener sees final wallet")
		assertions.equal(observation.crop, 2, "listener sees final crop storage")
		assertions.equal(observation.crop_stock, 8, "listener sees final crop market stock")
	if not recorder.observations.is_empty():
		assertions.equal(recorder.observations[0].source, "storage", "Router publishes container first")
		assertions.equal(recorder.observations[-1].source, "gold", "gold notification publishes last")
	assertions.truthy(
		recorder.observations.find({
			"source": "market_bus",
			"gold": before_gold - crop_total,
			"seed": 0,
			"crop": 2,
			"seed_stock": 10,
			"crop_stock": 8,
		}) > 0,
		"market notification follows Router publication"
	)

	_disconnect_trade_recorder(fixture, recorder)
	_free_routed_fixture(fixture)


func _test_finalized_dispatch_survives_destroyed_market(assertions: TestAssert) -> void:
	var fixture := _make_routed_fixture()
	var event_bus := (Engine.get_main_loop() as SceneTree).root.get_node("EventBus")
	var market_events: Array[Dictionary] = []
	var on_market := func(item_id: String, stock: int) -> void:
		market_events.append({"item_id": item_id, "stock": stock})
	event_bus.market_stock_changed.connect(on_market)
	var market: MarketSystem = fixture.market
	var on_storage := func(_changes: Dictionary) -> void:
		if is_instance_valid(market):
			market.free()
	fixture.storage.contents_changed.connect(on_storage)
	var total: int = fixture.market.quote_buy("grain", 2)
	assertions.truthy(
		fixture.economy.buy_item("grain", 2),
		"unified dispatch survives listener destroying Market"
	)
	assertions.truthy(not is_instance_valid(market), "storage listener destroys Market during dispatch")
	assertions.equal(fixture.storage.get_count("grain"), 2, "destroyed Market leaves container committed")
	assertions.equal(fixture.wallet.gold, 1000 - total, "destroyed Market leaves wallet committed")
	assertions.equal(
		market_events,
		[{"item_id": "grain", "stock": 8}],
		"captured Market EventBus batch still dispatches once"
	)
	var router_probe: Variant = fixture.router.begin_atomic_transaction()
	assertions.truthy(router_probe != null, "destroy callback leaves Router unlocked")
	if router_probe != null:
		fixture.router.rollback_atomic_transaction(router_probe)
	fixture.storage.contents_changed.disconnect(on_storage)
	event_bus.market_stock_changed.disconnect(on_market)
	_free_routed_fixture(fixture)


func _test_router_listener_cannot_mutate_or_consume_market_publication(
	assertions: TestAssert
) -> void:
	var fixture := _make_routed_fixture()
	var recorder := _connect_trade_recorder(fixture)
	recorder.attack_market_during_router_publish = true
	recorder.reblock_on_local_market = true
	var total: int = fixture.market.quote_buy("grain", 2)
	assertions.truthy(fixture.economy.buy_item("grain", 2), "malicious Router listener cannot break trade")
	assertions.equal(recorder.market_attack_results, {
		"begin": null,
		"buy": false,
		"sell": false,
		"demand": false,
		"supply": false,
		"publish_null": false,
		"cancel_null": false,
		"dispatch_forged_finalized": false,
		"cancel_forged_finalized": false,
		"legacy_publish": false,
	}, "finalized Market rejects every unowned callback attack")
	assertions.equal(fixture.market.get_stock("grain"), 8, "malicious callback preserves final stock")
	assertions.equal(fixture.market.get_item_state("grain").get("demand"), 2, "malicious callback preserves demand")
	assertions.equal(fixture.wallet.gold, 1000 - total, "malicious callback preserves wallet")
	assertions.equal(fixture.storage.get_count("grain"), 2, "malicious callback preserves storage")
	assertions.equal(
		recorder.local_market_events,
		[{"item_id": "grain", "stock": 8}],
		"Market local committed notification emits exactly once"
	)
	assertions.equal(
		recorder.market_events,
		[{"item_id": "grain", "stock": 8}],
		"Market EventBus committed notification survives local reblock exactly once"
	)
	var event_bus := (Engine.get_main_loop() as SceneTree).root.get_node("EventBus")
	assertions.truthy(not event_bus.is_blocking_signals(), "Market publication clears listener reblock")
	_disconnect_trade_recorder(fixture, recorder)
	_free_routed_fixture(fixture)


func _test_routed_preflight_rejects_unpublishable_outer_state(assertions: TestAssert) -> void:
	var fixture := _make_routed_fixture()
	var event_bus := (Engine.get_main_loop() as SceneTree).root.get_node("EventBus")
	event_bus.set_block_signals(true)
	var before := _routed_snapshot(fixture)
	var result: Dictionary = fixture.economy.quote_trade_failure("grain", 1, true)
	assertions.equal(result.get("reason"), "transaction_failed", "blocked event bus rejects routed trade")
	assertions.truthy(not fixture.economy.buy_item("grain", 1), "blocked event bus cannot strand publication")
	_assert_routed_snapshot(assertions, before, fixture, "blocked event bus")
	event_bus.set_block_signals(false)
	_free_routed_fixture(fixture)

	var tree := Engine.get_main_loop() as SceneTree
	var inventory := InventoryDouble.new()
	var wallet := WalletDouble.new()
	var market := LegacyMarketDouble.new()
	var storage := FailingStorage.new()
	var router := FailingRouter.new()
	var economy := EconomySystem.new()
	for node in [inventory, wallet, market, storage, router, economy]:
		tree.root.add_child(node)
	storage.configure()
	router.configure(inventory, storage)
	assertions.truthy(
		economy.configure(inventory, wallet, market, null, router),
		"legacy market remains structurally configurable"
	)
	result = economy.quote_trade_failure("wood", 1, true)
	assertions.equal(result.get("reason"), "transaction_failed", "routed trade requires atomic market")
	assertions.truthy(not economy.buy_item("wood", 1), "non-atomic market cannot leak routed trade")
	assertions.equal(wallet.gold, 1000, "non-atomic routed rejection preserves wallet")
	assertions.equal(inventory.get_item_count("wood"), 0, "non-atomic routed rejection preserves inventory")
	assertions.equal(market.get_stock("wood"), 10, "non-atomic routed rejection preserves market")
	for node in [economy, router, storage, market, wallet, inventory]:
		node.free()
