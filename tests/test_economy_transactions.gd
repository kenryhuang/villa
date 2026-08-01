extends RefCounted

const EconomySystem = preload("res://scripts/systems/economy_system.gd")
const InventorySystem = preload("res://scripts/systems/inventory_system.gd")
const MarketSystem = preload("res://scripts/systems/market_system.gd")


class WalletDouble:
	extends Node

	var gold := 1000
	var fail_next_add := false
	var fail_next_spend := false
	var _event_bus: Node

	func _ready() -> void:
		_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null

	func add_gold(amount: int) -> bool:
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


class MarketDouble:
	extends MarketSystem

	var fail_next_buy := false
	var fail_next_sell := false

	func commit_buy(item_id: String, quantity: int) -> bool:
		if fail_next_buy:
			fail_next_buy = false
			super.commit_buy(item_id, quantity)
			return false
		return super.commit_buy(item_id, quantity)

	func commit_sell(item_id: String, quantity: int) -> bool:
		if fail_next_sell:
			fail_next_sell = false
			super.commit_sell(item_id, quantity)
			return false
		return super.commit_sell(item_id, quantity)


func run(assertions: TestAssert) -> void:
	_test_successful_buy_and_sell(assertions)
	_test_preflight_failures_preserve_state(assertions)
	_test_buy_rolls_back_each_mutation_boundary(assertions)
	_test_sell_rolls_back_each_mutation_boundary(assertions)
	_test_event_bus_only_observes_committed_trade(assertions)


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
