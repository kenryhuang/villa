class_name AgentMarketSummary
extends RefCounted

const ROLE_SIGNAL_LIMITS := {"farmer": 12, "merchant": 20, "explorer": 10}
const SHORTAGE_RATIO_BPS := 7500
const SURPLUS_RATIO_BPS := 12500
const PRICE_MOVE_BPS := 500


func build(
	role_id: String,
	game_minute: int,
	actor_state: Dictionary,
	farm: Array,
	market: Dictionary,
	catalog: Dictionary
) -> Dictionary:
	var overview := {
		"item_count": market.size(),
		"shortage_count": 0,
		"surplus_count": 0,
		"rising_count": 0,
		"falling_count": 0,
	}
	var inventory: Dictionary = (
		(actor_state.get("inventory", {}) as Dictionary)
		if actor_state.get("inventory", {}) is Dictionary
		else {}
	)
	var active_crops := {}
	for plot_value in farm:
		if plot_value is Dictionary:
			var crop_item_id := str((plot_value as Dictionary).get("crop_item_id", ""))
			if not crop_item_id.is_empty():
				active_crops[crop_item_id] = true
	var owned_crop_outputs := {}
	for item_id_value in inventory:
		if int(inventory[item_id_value]) <= 0:
			continue
		var item_id := str(item_id_value)
		if item_id.ends_with("_seed"):
			owned_crop_outputs[item_id.trim_suffix("_seed")] = true
		elif item_id.ends_with("_sapling"):
			owned_crop_outputs[item_id.trim_suffix("_sapling")] = true
	var candidates: Array[Dictionary] = []
	var item_ids := market.keys()
	item_ids.sort()
	for item_id_value in item_ids:
		var item_id := str(item_id_value)
		var state_value: Variant = market[item_id_value]
		if not state_value is Dictionary:
			continue
		var state := state_value as Dictionary
		var definition: Dictionary = (
			(catalog.get(item_id, {}) as Dictionary)
			if catalog.get(item_id, {}) is Dictionary
			else {}
		)
		var base_price := int(state.get("base_price", 0))
		var mid_price := int(state.get("mid_price", base_price))
		var stock := int(state.get("stock", 0))
		var target_stock := int(state.get("target_stock", 0))
		var stock_ratio_bps := _ratio_bps(stock, target_stock, 10000)
		var price_change_bps := _change_bps(mid_price, base_price)
		var reasons: Array[String] = []
		if stock_ratio_bps < SHORTAGE_RATIO_BPS:
			overview.shortage_count += 1
			reasons.append("shortage")
		elif stock_ratio_bps > SURPLUS_RATIO_BPS:
			overview.surplus_count += 1
			reasons.append("surplus")
		if price_change_bps >= PRICE_MOVE_BPS:
			overview.rising_count += 1
			reasons.append("rising")
		elif price_change_bps <= -PRICE_MOVE_BPS:
			overview.falling_count += 1
			reasons.append("falling")
		var priority := _add_role_reasons(
			role_id, item_id, definition, state, inventory, active_crops,
			owned_crop_outputs, reasons
		)
		if priority < 0:
			continue
		var pressure_bias := 0
		var pressure_value: Variant = state.get("agent_pressure", {})
		if pressure_value is Dictionary:
			pressure_bias = int((pressure_value as Dictionary).get("price_bias_bps", 0))
		candidates.append({
			"item_id": item_id,
			"mid_price": mid_price,
			"base_price": base_price,
			"stock_ratio_bps": stock_ratio_bps,
			"price_change_bps": price_change_bps,
			"reason_codes": reasons,
			"_priority": priority,
			"_anomaly": absi(price_change_bps) + absi(stock_ratio_bps - 10000) + absi(pressure_bias),
		})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left._priority) != int(right._priority):
			return int(left._priority) > int(right._priority)
		if int(left._anomaly) != int(right._anomaly):
			return int(left._anomaly) > int(right._anomaly)
		return str(left.item_id) < str(right.item_id)
	)
	var signals: Array[Dictionary] = []
	var limit := int(ROLE_SIGNAL_LIMITS.get(role_id, 0))
	for index in range(mini(limit, candidates.size())):
		var signal_record := candidates[index].duplicate(true)
		signal_record.erase("_priority")
		signal_record.erase("_anomaly")
		signals.append(signal_record)
	return {
		"schema_version": 1,
		"role_id": role_id,
		"generated_game_minute": maxi(0, game_minute),
		"overview": overview,
		"signals": signals,
	}


func _add_role_reasons(
	role_id: String,
	item_id: String,
	definition: Dictionary,
	state: Dictionary,
	inventory: Dictionary,
	active_crops: Dictionary,
	owned_crop_outputs: Dictionary,
	reasons: Array[String]
) -> int:
	var owned := int(inventory.get(item_id, 0)) > 0
	var category := str(definition.get("category", ""))
	var priority := -1
	match role_id:
		"farmer":
			if category in ["seed", "crop"]:
				priority = 20
				_append_reason(reasons, "agriculture")
			if owned:
				priority = maxi(priority, 100)
				_append_reason(reasons, "owned_item")
			if active_crops.has(item_id):
				priority = maxi(priority, 90)
				_append_reason(reasons, "active_crop")
			if owned_crop_outputs.has(item_id):
				priority = maxi(priority, 80)
				_append_reason(reasons, "crop_output")
		"merchant":
			priority = 10
			_append_reason(reasons, "market_scope")
			if owned:
				priority = 100
				_append_reason(reasons, "owned_item")
			var pressure: Dictionary = (
				(state.get("agent_pressure", {}) as Dictionary)
				if state.get("agent_pressure", {}) is Dictionary
				else {}
			)
			if not pressure.is_empty() and (
				int(pressure.get("demand", 0)) != 0
				or int(pressure.get("supply", 0)) != 0
				or int(pressure.get("private_volume", 0)) != 0
				or int(pressure.get("price_bias_bps", 0)) != 0
			):
				priority = maxi(priority, 80)
				_append_reason(reasons, "market_pressure")
			if "shortage" in reasons or "surplus" in reasons:
				priority = maxi(priority, 60)
			if "rising" in reasons or "falling" in reasons:
				priority = maxi(priority, 50)
		"explorer":
			if owned:
				priority = 100
				_append_reason(reasons, "expedition_supply")
			if category == "rare":
				priority = maxi(priority, 80)
				_append_reason(reasons, "rare_resource")
			elif category == "fish" or "fish" in (definition.get("tags", []) as Array):
				priority = maxi(priority, 70)
				_append_reason(reasons, "fish_market")
			if priority >= 0 and ("shortage" in reasons or "surplus" in reasons or "rising" in reasons or "falling" in reasons):
				priority += 10
	return priority


func _append_reason(reasons: Array[String], reason: String) -> void:
	if not reasons.has(reason):
		reasons.append(reason)


func _ratio_bps(value: int, reference: int, fallback: int) -> int:
	if reference <= 0:
		return fallback
	return roundi(float(value) / float(reference) * 10000.0)


func _change_bps(value: int, reference: int) -> int:
	if reference <= 0:
		return 0
	return roundi((float(value) - float(reference)) / float(reference) * 10000.0)
