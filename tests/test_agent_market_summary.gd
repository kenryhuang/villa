extends RefCounted

const AgentMarketSummaryScript = preload("res://scripts/ai_agent/agent_market_summary.gd")


func run(assertions: TestAssert) -> void:
	var builder := AgentMarketSummaryScript.new()
	var market := {
		"carrot_seed": _state("carrot_seed", 4, 4, 40, 50),
		"carrot": _state("carrot", 18, 14, 20, 55),
		"salt": _state("salt", 4, 5, 80, 45),
		"rainbow_trout": _state("rainbow_trout", 65, 50, 5, 12),
		"crystal": _state("crystal", 70, 70, 4, 10),
		"rope": _state("rope", 51, 51, 35, 45),
	}
	market.salt.agent_pressure = {"demand": 10, "supply": 0, "private_volume": 3, "price_bias_bps": 500}
	var catalog := {
		"carrot_seed": {"category": "seed"},
		"carrot": {"category": "crop"},
		"salt": {"category": "container"},
		"rainbow_trout": {"category": "fish", "tags": ["fish", "rare_fish"]},
		"crystal": {"category": "rare"},
		"rope": {"category": "processed_material"},
	}
	var actor := {"inventory": {"carrot_seed": 2, "salt": 3, "rope": 1}}
	var farm := [{"state": "planted", "crop_item_id": "carrot"}]
	var farmer: Dictionary = builder.build("farmer", 480, actor, farm, market, catalog)
	var merchant: Dictionary = builder.build("merchant", 480, actor, farm, market, catalog)
	var explorer: Dictionary = builder.build("explorer", 480, actor, farm, market, catalog)
	assertions.equal(farmer.role_id, "farmer", "farmer summary identifies active role")
	assertions.truthy(_signal_ids(farmer).has("carrot_seed"), "farmer sees owned seed")
	assertions.truthy(_reason_for(farmer, "carrot").has("active_crop"), "farmer sees active crop output")
	assertions.truthy(_reason_for(merchant, "salt").has("market_pressure"), "merchant sees pressured market")
	assertions.truthy(_signal_ids(explorer).has("rainbow_trout"), "explorer sees fish market")
	assertions.truthy(_signal_ids(explorer).has("crystal"), "explorer sees rare resource")
	assertions.equal(builder.build("farmer", 480, actor, farm, market, catalog), farmer, "summary ordering is deterministic")
	assertions.truthy(farmer != merchant and merchant != explorer, "active role changes summary content")
	assertions.equal(farmer.overview.shortage_count, 3, "overview counts market shortages")
	var zero_market := {"zero": _state("zero", 0, 0, 1, 0)}
	var zero_summary: Dictionary = builder.build("merchant", 0, {}, [], zero_market, {"zero": {"category": "material"}})
	assertions.equal(zero_summary.signals[0].price_change_bps, 0, "zero base price is safe")
	assertions.equal(zero_summary.signals[0].stock_ratio_bps, 10000, "zero target stock is neutral")
	var safe_max := 9007199254740991
	var large_value_summary: Dictionary = builder.build(
		"merchant", 0, {}, [],
		{"large": _state("large", safe_max, safe_max, safe_max, safe_max)},
		{"large": {"category": "material"}},
	)
	assertions.equal(large_value_summary.signals[0].price_change_bps, 0, "large safe prices do not overflow")
	assertions.equal(large_value_summary.signals[0].stock_ratio_bps, 10000, "large safe stocks do not overflow")
	var large_market := {}
	var large_catalog := {}
	for index in range(30):
		var item_id := "crop_%02d" % index
		large_market[item_id] = _state(item_id, 20 + index, 10, 5, 50)
		large_catalog[item_id] = {"category": "crop"}
	assertions.truthy(builder.build("farmer", 0, {}, [], large_market, large_catalog).signals.size() <= 12, "farmer summary is capped")
	assertions.truthy(builder.build("merchant", 0, {}, [], large_market, large_catalog).signals.size() <= 20, "merchant summary is capped")
	assertions.truthy(builder.build("explorer", 0, {}, [], large_market, large_catalog).signals.size() <= 10, "explorer summary is capped")
	assertions.equal(builder.build("farmer", 0, {}, [], {}, {}).signals, [], "empty market creates empty signals")


func _state(item_id: String, mid_price: int, base_price: int, stock: int, target_stock: int) -> Dictionary:
	return {
		"item_id": item_id,
		"mid_price": mid_price,
		"base_price": base_price,
		"stock": stock,
		"target_stock": target_stock,
		"daily_liquidity": 10,
		"demand": 0,
		"supply": 0,
		"history": [base_price, mid_price],
	}


func _signal_ids(summary: Dictionary) -> Array:
	return (summary.signals as Array).map(func(signal_record: Dictionary): return str(signal_record.item_id))


func _reason_for(summary: Dictionary, item_id: String) -> Array:
	for signal_value in summary.signals:
		var signal_record := signal_value as Dictionary
		if str(signal_record.item_id) == item_id:
			return signal_record.reason_codes
	return []
