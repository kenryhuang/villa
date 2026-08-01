class_name MarketMath
extends RefCounted


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
	return clampi(
		target,
		maxi(ceili(base * 0.5), ceili(float(current * 85) / 100.0)),
		mini(floori(base * 2.5), floori(float(current * 115) / 100.0))
	)


static func quote_total(mid: int, quantity: int, liquidity: int, is_buy: bool) -> int:
	if mid <= 0 or quantity <= 0:
		return 0
	var total := 0
	for i in range(quantity):
		var pressure := float(i) / maxi(liquidity, 1)
		var spread := 1.10 if is_buy else 0.90
		var slip := 1.0 + pressure * 0.20 if is_buy else maxf(0.50, 1.0 - pressure * 0.20)
		total += maxi(1, roundi(mid * spread * slip))
	return total
