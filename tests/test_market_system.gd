extends RefCounted

const MarketSystem = preload("res://scripts/systems/market_system.gd")


func run(assertions: TestAssert) -> void:
	_test_finite_stock_ledger_and_quotes(assertions)
	_test_invalid_operations_are_atomic(assertions)
	_test_settlement_is_idempotent_and_bounded(assertions)
	_test_state_is_deep_copied_and_persistent(assertions)


func _wood_definition() -> Dictionary:
	return {
		"id": "wood",
		"base_price": 100,
		"initial_stock": 10,
		"target_stock": 10,
		"daily_liquidity": 10,
	}


func _test_finite_stock_ledger_and_quotes(assertions: TestAssert) -> void:
	var market := MarketSystem.new()
	var stock_events: Array[Dictionary] = []
	market.market_stock_changed.connect(func(item_id: String, stock: int) -> void:
		stock_events.append({"item_id": item_id, "stock": stock})
	)
	assertions.truthy(market.configure([_wood_definition()]), "market accepts valid definitions")
	assertions.equal(market.get_item_state("wood"), {
		"item_id": "wood",
		"base_price": 100,
		"mid_price": 100,
		"stock": 10,
		"target_stock": 10,
		"daily_liquidity": 10,
		"demand": 0,
		"supply": 0,
		"history": [100],
	}, "market builds the required runtime entry")
	assertions.equal(market.get_stock("wood"), 10, "market starts with finite stock")
	assertions.equal(market.get_mid_price("wood"), 100, "market starts at base price")
	assertions.equal(market.get_history("wood"), [100], "market starts one-point history")
	assertions.equal(market.quote_buy("wood", 1), 110, "market quotes a buy")
	assertions.equal(market.quote_sell("wood", 1), 90, "market quotes a sale")
	assertions.truthy(market.can_buy("wood", 10), "available stock can be bought")
	assertions.truthy(not market.can_buy("wood", 11), "buy cannot exceed stock")

	assertions.truthy(market.commit_buy("wood", 3), "market commits a player buy")
	assertions.equal(market.get_stock("wood"), 7, "player buy reduces stock")
	assertions.equal(market.get_item_state("wood").get("demand"), 3, "player buy records demand")
	assertions.truthy(market.commit_sell("wood", 5), "market commits a player sale")
	assertions.equal(market.get_stock("wood"), 12, "player sale increases stock")
	assertions.equal(market.get_item_state("wood").get("supply"), 5, "player sale records supply")
	assertions.equal(stock_events.size(), 2, "stock changes emit exactly once")
	assertions.equal(stock_events[0], {"item_id": "wood", "stock": 7}, "buy emits resulting stock")
	assertions.equal(stock_events[1], {"item_id": "wood", "stock": 12}, "sale emits resulting stock")
	market.free()


func _test_invalid_operations_are_atomic(assertions: TestAssert) -> void:
	var market := MarketSystem.new()
	assertions.truthy(market.configure([_wood_definition()]), "market fixture configures")
	var initial := market.to_dict()
	for quantity in [0, -1, 11]:
		assertions.truthy(not market.commit_buy("wood", quantity), "invalid buy quantity is rejected")
		assertions.equal(market.to_dict(), initial, "invalid buy preserves all market state")
	for quantity in [0, -1]:
		assertions.truthy(not market.commit_sell("wood", quantity), "invalid sale quantity is rejected")
		assertions.equal(market.to_dict(), initial, "invalid sale preserves all market state")
	assertions.truthy(not market.commit_buy("missing", 1), "missing buy item is rejected")
	assertions.truthy(not market.commit_sell("missing", 1), "missing sale item is rejected")
	assertions.truthy(not market.add_external_demand("missing", 1), "missing demand item is rejected")
	assertions.truthy(not market.add_external_supply("missing", 1), "missing supply item is rejected")
	assertions.truthy(not market.add_external_demand("wood", 0), "nonpositive demand is rejected")
	assertions.truthy(not market.add_external_supply("wood", -1), "nonpositive supply is rejected")
	assertions.equal(market.to_dict(), initial, "all invalid operations preserve market state")
	assertions.equal(market.quote_buy("missing", 1), 0, "missing item has no buy quote")
	assertions.equal(market.quote_sell("wood", 0), 0, "nonpositive quantity has no sale quote")
	assertions.equal(market.get_stock("missing"), 0, "missing item reports no stock")
	assertions.equal(market.get_mid_price("missing"), 0, "missing item reports no price")
	assertions.equal(market.get_history("missing"), [], "missing item reports no history")
	market.free()


func _test_settlement_is_idempotent_and_bounded(assertions: TestAssert) -> void:
	var market := MarketSystem.new()
	var settled_days: Array[int] = []
	var price_events: Array[Dictionary] = []
	market.market_settled.connect(func(day: int) -> void: settled_days.append(day))
	market.market_price_changed.connect(func(item_id: String, price: int) -> void:
		price_events.append({"item_id": item_id, "price": price})
	)
	assertions.truthy(market.configure([_wood_definition()]), "settlement fixture configures")
	assertions.truthy(market.add_external_demand("wood", 10), "external demand is recorded")
	assertions.truthy(market.add_external_supply("wood", 2), "external supply is recorded")
	assertions.truthy(
		market.settle_day(2, {"wood": 1.25}, {"wood": 1.5}),
		"day settles with per-item factors"
	)
	var settled_state := market.get_item_state("wood")
	assertions.equal(settled_state.get("mid_price"), 115, "settlement uses market math daily cap")
	assertions.equal(settled_state.get("demand"), 0, "settlement resets demand")
	assertions.equal(settled_state.get("supply"), 0, "settlement resets supply")
	var after_day_two := market.to_dict()
	assertions.truthy(not market.settle_day(2), "same day settlement is rejected")
	assertions.truthy(not market.settle_day(1), "older day settlement is rejected")
	assertions.equal(market.to_dict(), after_day_two, "rejected settlement preserves state")
	for day in range(3, 12):
		assertions.truthy(market.settle_day(day), "later day settles")
	assertions.equal(market.get_history("wood").size(), 7, "history is trimmed to seven days")
	assertions.equal(settled_days.size(), 10, "only successful settlements emit")
	assertions.equal(settled_days[0], 2, "settlement signal reports day")
	assertions.truthy(not price_events.is_empty(), "changed price emits a price signal")
	market.free()


func _test_state_is_deep_copied_and_persistent(assertions: TestAssert) -> void:
	var market := MarketSystem.new()
	assertions.truthy(market.configure([_wood_definition()]), "persistence fixture configures")
	assertions.truthy(market.commit_buy("wood", 2), "persisted stock changes")
	assertions.truthy(market.settle_day(4), "persisted settlement changes history")

	var exposed_state := market.get_item_state("wood")
	exposed_state["stock"] = 999
	exposed_state["history"].append(999)
	var exposed_history := market.get_history("wood")
	exposed_history.append(999)
	assertions.equal(market.get_stock("wood"), 8, "item state cannot mutate market stock")
	assertions.equal(market.get_history("wood").size(), 2, "returned history cannot mutate market history")

	var saved := market.to_dict()
	var restored := MarketSystem.new()
	assertions.truthy(restored.from_dict(saved), "valid market snapshot restores")
	assertions.equal(restored.to_dict(), saved, "market snapshot round trips exactly")
	assertions.truthy(not restored.settle_day(4), "restored settlement day stays idempotent")
	saved["items"]["wood"]["stock"] = 500
	saved["items"]["wood"]["history"].append(500)
	assertions.equal(restored.get_stock("wood"), 8, "restored stock is deep copied")
	assertions.equal(restored.get_history("wood").size(), 2, "restored history is deep copied")

	var before_malformed := restored.to_dict()
	assertions.truthy(not restored.from_dict({"last_settled_day": 5, "items": {"wood": {}}}), "malformed snapshot is rejected")
	assertions.equal(restored.to_dict(), before_malformed, "malformed restore preserves prior state")
	var fractional_day := before_malformed.duplicate(true)
	fractional_day["last_settled_day"] = 4.5
	assertions.truthy(not restored.from_dict(fractional_day), "fractional settlement day is rejected")
	assertions.equal(restored.to_dict(), before_malformed, "fractional day preserves prior state")
	var impossible_price := before_malformed.duplicate(true)
	impossible_price["items"]["wood"]["mid_price"] = 999
	impossible_price["items"]["wood"]["history"][-1] = 999
	assertions.truthy(not restored.from_dict(impossible_price), "out-of-bounds persisted price is rejected")
	assertions.equal(restored.to_dict(), before_malformed, "impossible price preserves prior state")
	var mismatched_history := before_malformed.duplicate(true)
	mismatched_history["items"]["wood"]["history"][-1] = 100
	assertions.truthy(not restored.from_dict(mismatched_history), "history tail must match current price")
	assertions.equal(restored.to_dict(), before_malformed, "mismatched history preserves prior state")
	assertions.truthy(not market.configure([{"id": "bad", "base_price": 0}]), "malformed definitions are rejected")
	assertions.equal(market.get_stock("wood"), 8, "failed configure preserves prior market")
	assertions.truthy(not market.configure([{
		"id": "bad",
		"base_price": "100",
		"initial_stock": 1,
		"target_stock": 1,
		"daily_liquidity": 1,
	}]), "nonnumeric definition fields are rejected")
	assertions.equal(market.get_stock("wood"), 8, "type-invalid configure preserves prior market")
	restored.free()
	market.free()
