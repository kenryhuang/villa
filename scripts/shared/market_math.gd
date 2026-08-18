class_name MarketMath
extends RefCounted

const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")


static func target_price(
	base: int,
	stock: int,
	target_stock: int,
	demand: int,
	supply: int,
	liquidity: int,
	season: float,
	event: float
) -> int:
	var safe_stock := maxi(target_stock, 1)
	var safe_flow := maxi(liquidity, 1)
	var sf := clampf(1.0 + float(safe_stock - stock) / safe_stock * 0.6, 0.70, 1.60)
	var df := clampf(1.0 + float(demand - supply) / safe_flow * 0.60, 0.70, 1.60)
	var raw := base * sf * df * clampf(season, 0.85, 1.25) * clampf(event, 0.80, 1.50)
	return clampi(roundi(raw), ceili(base * 0.50), floori(base * 2.50))


static func smooth_price(current: int, target: int, base: int) -> int:
	var global_min := ceili(base * 0.5)
	var global_max := floori(base * 2.5)
	var normalized_current := clampi(current, global_min, global_max)
	var daily_lower := maxi(global_min, ceili(float(normalized_current * 85) / 100.0))
	var daily_upper := mini(global_max, floori(float(normalized_current * 115) / 100.0))
	if target > normalized_current:
		daily_upper = maxi(daily_upper, mini(global_max, normalized_current + 1))
	elif target < normalized_current:
		daily_lower = mini(daily_lower, maxi(global_min, normalized_current - 1))
	return clampi(target, daily_lower, daily_upper)


static func quote_total(mid: int, quantity: int, liquidity: int, is_buy: bool) -> int:
	if (
		mid <= 0
		or mid > EconomyLimitsScript.MAX_SAFE_INTEGER
		or quantity <= 0
		or quantity > EconomyLimitsScript.MAX_TRADE_QUANTITY
	):
		return 0
	var safe_liquidity := maxi(liquidity, 1)
	var spread := 1.10 if is_buy else 0.90
	var max_pressure := float(quantity - 1) / safe_liquidity if is_buy else 0.0
	var max_slip := 1.0 + max_pressure * 0.20 if is_buy else 1.0
	var max_raw_unit := float(mid) * spread * max_slip
	if not is_finite(max_raw_unit) or max_raw_unit > EconomyLimitsScript.MAX_SAFE_INTEGER:
		return 0
	var max_unit := maxi(1, roundi(max_raw_unit))
	if max_unit > floori(float(EconomyLimitsScript.MAX_SAFE_INTEGER) / quantity):
		return 0
	var total := 0
	for i in range(quantity):
		var pressure := float(i) / safe_liquidity
		var slip := 1.0 + pressure * 0.20 if is_buy else maxf(0.50, 1.0 - pressure * 0.20)
		var raw_unit := float(mid) * spread * slip
		if not is_finite(raw_unit) or raw_unit > EconomyLimitsScript.MAX_SAFE_INTEGER:
			return 0
		var unit_price := maxi(1, roundi(raw_unit))
		if unit_price > EconomyLimitsScript.MAX_SAFE_INTEGER - total:
			return 0
		total += unit_price
	return total
