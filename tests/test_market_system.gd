extends RefCounted

const MarketSystem = preload("res://scripts/systems/market_system.gd")
const EconomyLimits = preload("res://scripts/core/economy_limits.gd")


func run(assertions: TestAssert) -> void:
	_test_finite_stock_ledger_and_quotes(assertions)
	_test_seed_and_crop_market_entries_are_independent(assertions)
	_test_invalid_operations_are_atomic(assertions)
	_test_safe_ledger_boundaries_and_transaction_rollback(assertions)
	_test_sealed_publication_requires_ownership(assertions)
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


func _test_seed_and_crop_market_entries_are_independent(assertions: TestAssert) -> void:
	var market := MarketSystem.new()
	assertions.truthy(market.configure([
		{
			"id": "grain_seed",
			"base_price": 4,
			"initial_stock": 20,
			"target_stock": 20,
			"daily_liquidity": 10,
		},
		{
			"id": "grain",
			"base_price": 28,
			"initial_stock": 12,
			"target_stock": 12,
			"daily_liquidity": 10,
		},
	]), "market configures seed and crop entries")
	assertions.truthy(market.commit_buy("grain_seed", 3), "market sells seed stock")
	assertions.equal(market.get_stock("grain_seed"), 17, "seed stock decreases independently")
	assertions.equal(market.get_stock("grain"), 12, "seed purchase leaves crop stock unchanged")
	assertions.truthy(market.commit_sell("grain", 2), "market accepts crop stock")
	assertions.equal(market.get_stock("grain"), 14, "crop stock increases independently")
	assertions.equal(market.get_stock("grain_seed"), 17, "crop sale leaves seed stock unchanged")
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


func _test_safe_ledger_boundaries_and_transaction_rollback(assertions: TestAssert) -> void:
	var market := MarketSystem.new()
	assertions.truthy(market.configure([_wood_definition()]), "safe-ledger fixture configures")
	var configured := market.to_dict()
	var quote_started := Time.get_ticks_usec()
	assertions.equal(
		market.quote_buy("wood", EconomyLimits.MAX_SAFE_INTEGER),
		0,
		"market rejects huge quote before MarketMath"
	)
	assertions.truthy(
		Time.get_ticks_usec() - quote_started < 100_000,
		"market huge quote returns promptly"
	)
	var unsafe_definition := _wood_definition()
	unsafe_definition["initial_stock"] = EconomyLimits.MAX_SAFE_INTEGER + 1
	assertions.truthy(
		not market.configure([unsafe_definition]),
		"market rejects unsafe catalog stock"
	)
	assertions.equal(market.to_dict(), configured, "unsafe catalog preserves market state")
	for field in ["stock", "demand", "supply"]:
		var unsafe_saved := configured.duplicate(true)
		unsafe_saved["items"]["wood"][field] = EconomyLimits.MAX_SAFE_INTEGER + 1
		assertions.truthy(not market.from_dict(unsafe_saved), "market rejects unsafe saved " + field)
		assertions.equal(market.to_dict(), configured, "unsafe saved " + field + " preserves state")

	var buy_boundary := configured.duplicate(true)
	buy_boundary["items"]["wood"]["demand"] = EconomyLimits.MAX_SAFE_INTEGER
	assertions.truthy(market.from_dict(buy_boundary), "safe demand boundary restores")
	assertions.truthy(not market.commit_buy("wood", 1), "buy cannot overflow demand ledger")
	assertions.equal(market.to_dict(), buy_boundary, "demand overflow preserves market")

	var sell_boundary := configured.duplicate(true)
	sell_boundary["items"]["wood"]["stock"] = EconomyLimits.MAX_SAFE_INTEGER
	assertions.truthy(market.from_dict(sell_boundary), "safe stock boundary restores")
	assertions.truthy(not market.commit_sell("wood", 1), "sale cannot overflow stock ledger")
	assertions.equal(market.to_dict(), sell_boundary, "stock overflow preserves market")

	assertions.truthy(market.from_dict(configured), "transaction rollback fixture restores")
	var rollback_transaction: Variant = market.begin_atomic_transaction()
	assertions.truthy(rollback_transaction != null, "market transaction begins")
	assertions.truthy(not market.from_dict(configured), "active market rejects external restore")
	assertions.truthy(not market.configure([_wood_definition()]), "active market rejects reconfigure")
	assertions.truthy(market.commit_buy("wood", 1), "market transaction mutates state")
	assertions.truthy(
		market.end_atomic_transaction(rollback_transaction, false),
		"market transaction rolls back"
	)
	assertions.equal(market.to_dict(), configured, "market rollback restores exact snapshot")
	market.free()


func _test_sealed_publication_requires_ownership(assertions: TestAssert) -> void:
	var market := MarketSystem.new()
	assertions.truthy(market.configure([_wood_definition()]), "sealed market fixture configures")
	var required_methods := [
		"seal_atomic_transaction", "can_arm_sealed_transaction", "arm_sealed_transaction",
		"publish_sealed_transaction", "cancel_sealed_transaction", "owns_sealed_transaction",
	]
	for method_name in required_methods:
		assertions.truthy(market.has_method(method_name), "market exposes " + method_name)
	if required_methods.any(func(method_name: String) -> bool: return not market.has_method(method_name)):
		market.free()
		return

	var stock_events: Array[int] = []
	market.market_stock_changed.connect(func(_item_id: String, stock: int) -> void:
		stock_events.append(stock)
	)
	var transaction: Variant = market.begin_atomic_transaction()
	assertions.truthy(transaction is RefCounted, "market transaction has an unforgeable owner")
	var has_transaction_ownership := market.has_method("owns_atomic_transaction")
	assertions.truthy(has_transaction_ownership, "market exposes transaction ownership")
	if has_transaction_ownership:
		assertions.truthy(
			bool(market.call("owns_atomic_transaction", transaction)),
			"market recognizes its active transaction owner"
		)
	assertions.truthy(
		not market.end_atomic_transaction(true),
		"market transaction cannot end without its owner token"
	)
	assertions.truthy(
		not market.rollback_atomic_transaction(RefCounted.new()),
		"forged transaction owner cannot roll back market"
	)
	assertions.truthy(market.commit_buy("wood", 1), "owned market transaction mutates")
	var publication: Variant = market.call("seal_atomic_transaction", transaction)
	assertions.truthy(publication is RefCounted, "market seal returns an owned publication")
	if has_transaction_ownership:
		assertions.truthy(
			not bool(market.call("owns_atomic_transaction", transaction)),
			"sealed market no longer owns the consumed transaction token"
		)
	assertions.truthy(
		bool(market.call("owns_sealed_transaction", publication)),
		"market recognizes its publication owner"
	)
	var forged := RefCounted.new()
	assertions.truthy(not bool(market.call("publish_sealed_transaction", null)), "null cannot publish market")
	assertions.truthy(not bool(market.call("publish_sealed_transaction", forged)), "forged owner cannot publish market")
	assertions.truthy(not bool(market.call("cancel_sealed_transaction", null)), "null cannot discard market")
	assertions.truthy(not bool(market.call("cancel_sealed_transaction", forged)), "forged owner cannot discard market")
	assertions.equal(market.begin_atomic_transaction(), null, "sealed market rejects another transaction")
	assertions.truthy(not market.commit_buy("wood", 1), "sealed market rejects buy mutation")
	assertions.truthy(not market.commit_sell("wood", 1), "sealed market rejects sale mutation")
	assertions.truthy(not market.add_external_demand("wood", 1), "sealed market rejects demand mutation")
	assertions.truthy(not market.add_external_supply("wood", 1), "sealed market rejects supply mutation")
	assertions.truthy(not market.settle_day(1), "sealed market rejects settlement mutation")
	assertions.equal(stock_events, [], "sealed market has published no transient event")
	assertions.truthy(
		bool(market.call("can_arm_sealed_transaction", publication)),
		"owned market publication can arm"
	)
	assertions.truthy(bool(market.call("arm_sealed_transaction", publication)), "market publication arms")
	assertions.truthy(
		not bool(market.call("cancel_sealed_transaction", publication)),
		"armed market publication cannot roll back"
	)
	assertions.truthy(bool(market.call("publish_sealed_transaction", publication)), "owned market publishes")
	assertions.equal(stock_events, [9], "owned market publication emits exactly once")
	assertions.truthy(
		not bool(market.call("publish_sealed_transaction", publication)),
		"consumed market publication cannot replay"
	)
	var committed_state := market.to_dict()
	var cancel_transaction: Variant = market.begin_atomic_transaction()
	assertions.truthy(market.commit_sell("wood", 1), "cancellable market transaction mutates")
	var cancel_publication: Variant = market.call("seal_atomic_transaction", cancel_transaction)
	assertions.truthy(
		bool(market.call("cancel_sealed_transaction", cancel_publication)),
		"owned unarmed market publication cancels"
	)
	assertions.equal(market.to_dict(), committed_state, "owned market cancellation restores exact state")
	assertions.equal(stock_events, [9], "market cancellation emits no event")
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
	assertions.truthy(market.has_method("can_settle_day"), "market exposes settlement preflight")
	if not market.has_method("can_settle_day"):
		market.free()
		return
	var empty_market := MarketSystem.new()
	assertions.truthy(
		not bool(empty_market.call("can_settle_day", 2)),
		"unconfigured market cannot settle"
	)
	empty_market.free()
	assertions.truthy(bool(market.call("can_settle_day", 2)), "new positive day can settle")
	assertions.truthy(not bool(market.call("can_settle_day", 0)), "nonpositive day cannot settle")
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
	assertions.truthy(not bool(market.call("can_settle_day", 2)), "settled day fails preflight")
	assertions.truthy(not bool(market.call("can_settle_day", 1)), "older day fails preflight")
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
