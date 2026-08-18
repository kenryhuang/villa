extends RefCounted

const MarketMath = preload("res://scripts/shared/market_math.gd")
const EconomyLimits = preload("res://scripts/core/economy_limits.gd")


func run(assertions: TestAssert) -> void:
	_test_target_price_limits(assertions)
	_test_smooth_price_daily_caps(assertions)
	_test_smooth_price_low_value_movement(assertions)
	_test_smooth_price_normalizes_out_of_bounds_current(assertions)
	_test_quote_spread_and_slippage(assertions)
	_test_safe_boundaries(assertions)
	_test_quote_overflow_and_independent_trade_limit(assertions)
	_test_deterministic_results(assertions)


func _test_target_price_limits(assertions: TestAssert) -> void:
	assertions.equal(
		MarketMath.target_price(100, 0, 100, 100, 0, 100, 1.0, 1.0),
		250,
		"target price reaches global ceiling"
	)
	assertions.equal(
		MarketMath.target_price(100, 400, 100, 0, 100, 100, 1.0, 1.0),
		50,
		"target price reaches global floor"
	)


func _test_smooth_price_daily_caps(assertions: TestAssert) -> void:
	assertions.equal(MarketMath.smooth_price(100, 250, 100), 115, "smoothing limits a daily rise")
	assertions.equal(MarketMath.smooth_price(100, 50, 100), 85, "smoothing limits a daily fall")


func _test_smooth_price_low_value_movement(assertions: TestAssert) -> void:
	assertions.equal(MarketMath.smooth_price(3, 8, 3), 4, "low price advances toward an upward target")
	assertions.equal(MarketMath.smooth_price(3, 1, 3), 2, "low price falls toward a downward target")
	assertions.equal(MarketMath.smooth_price(2, 5, 2), 3, "base two price advances by one")
	var price := 3
	for day in range(4):
		price = MarketMath.smooth_price(price, 7, 3)
	assertions.equal(price, 7, "repeated low-price smoothing reaches its target")


func _test_smooth_price_normalizes_out_of_bounds_current(assertions: TestAssert) -> void:
	assertions.equal(MarketMath.smooth_price(20, 2, 3), 6, "above-ceiling current normalizes before falling")
	assertions.equal(MarketMath.smooth_price(0, 7, 3), 3, "below-floor current normalizes before rising")


func _test_quote_spread_and_slippage(assertions: TestAssert) -> void:
	assertions.equal(MarketMath.quote_total(100, 1, 20, true), 110, "buy quote applies spread")
	assertions.equal(MarketMath.quote_total(100, 1, 20, false), 90, "sell quote applies spread")
	assertions.truthy(MarketMath.quote_total(100, 20, 20, true) > 2200, "buy quote includes slippage")
	assertions.truthy(MarketMath.quote_total(100, 20, 20, false) < 1800, "sell quote includes slippage")


func _test_safe_boundaries(assertions: TestAssert) -> void:
	assertions.equal(MarketMath.quote_total(0, 1, 20, true), 0, "zero mid has no quote")
	assertions.equal(MarketMath.quote_total(-1, 1, 20, false), 0, "negative mid has no quote")
	assertions.equal(MarketMath.quote_total(100, 0, 20, true), 0, "zero quantity has no quote")
	assertions.equal(MarketMath.quote_total(100, -1, 20, false), 0, "negative quantity has no quote")
	assertions.equal(
		MarketMath.target_price(100, 0, 0, 100, 0, 0, 1.0, 1.0),
		250,
		"zero target stock and liquidity remain safe"
	)


func _test_quote_overflow_and_independent_trade_limit(assertions: TestAssert) -> void:
	assertions.truthy(
		EconomyLimits.MAX_TRADE_QUANTITY >= 200_000,
		"trade limit covers theoretical upgraded central storage"
	)
	assertions.truthy(
		EconomyLimits.MAX_TRADE_QUANTITY != EconomyLimits.MAX_DELIVERY_QUANTITY,
		"trade limit is independent from backpack delivery capacity"
	)
	var started := Time.get_ticks_usec()
	assertions.equal(
		MarketMath.quote_total(
			EconomyLimits.MAX_SAFE_INTEGER,
			EconomyLimits.MAX_SAFE_INTEGER,
			EconomyLimits.MAX_SAFE_INTEGER,
			true
		),
		0,
		"MAX_SAFE quote saturates to failure"
	)
	assertions.truthy(
		Time.get_ticks_usec() - started < 100_000,
		"MAX_SAFE quote fails before quantity iteration"
	)
	assertions.equal(
		MarketMath.quote_total(EconomyLimits.MAX_SAFE_INTEGER, 1, EconomyLimits.MAX_SAFE_INTEGER, true),
		0,
		"unsafe rounded unit price fails"
	)
	assertions.equal(
		MarketMath.quote_total(EconomyLimits.MAX_SAFE_INTEGER, 2, EconomyLimits.MAX_SAFE_INTEGER, false),
		0,
		"unsafe total multiplication fails"
	)
	assertions.equal(
		MarketMath.quote_total(1, EconomyLimits.MAX_TRADE_QUANTITY, EconomyLimits.MAX_SAFE_INTEGER, false),
		EconomyLimits.MAX_TRADE_QUANTITY,
		"largest supported low-price quote remains exact"
	)
	var negative_inputs_price: int = MarketMath.target_price(100, 100, -1, 100, 0, -1, 1.0, 1.0)
	assertions.truthy(negative_inputs_price > 0, "negative target stock and liquidity remain positive")
	assertions.truthy(
		negative_inputs_price >= 50 and negative_inputs_price <= 250,
		"negative target stock and liquidity stay within global price bounds"
	)
	assertions.equal(
		MarketMath.target_price(100, 100, -1, 100, 0, -1, 1.0, 1.0),
		negative_inputs_price,
		"negative target stock and liquidity remain deterministic"
	)


func _test_deterministic_results(assertions: TestAssert) -> void:
	var first_target := MarketMath.target_price(100, 47, 100, 37, 11, 20, 1.07, 1.12)
	var second_target := MarketMath.target_price(100, 47, 100, 37, 11, 20, 1.07, 1.12)
	assertions.equal(first_target, second_target, "target price is deterministic")
	var first_quote := MarketMath.quote_total(73, 9, 12, true)
	var second_quote := MarketMath.quote_total(73, 9, 12, true)
	assertions.equal(first_quote, second_quote, "quote total is deterministic")
