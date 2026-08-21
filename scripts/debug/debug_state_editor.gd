class_name DebugStateEditor
extends RefCounted

const GameDataScript := preload("res://scripts/core/game_data.gd")
const EconomyLimitsScript := preload("res://scripts/core/economy_limits.gd")
const PlayerStateScript := preload("res://scripts/data/player_state.gd")

var _game_state: Variant
var _season: Variant
var _inventory: Variant
var _production: Variant
var _economy: Variant
var _market: Variant
var _npc: Variant
var _daily: Variant
var _resources: Variant
var _event_bus: Variant
var _progression: Variant
var _configured := false


func configure(
	game_state: Variant,
	season: Variant,
	inventory: Variant,
	production: Variant,
	economy: Variant,
	market: Variant,
	npc: Variant,
	daily: Variant,
	resources: Variant,
	event_bus: Variant,
	progression: Variant = null
) -> bool:
	if (
		game_state == null
		or not _has_properties(game_state, ["gold", "player_state"])
		or game_state.get("player_state") == null
		or not _has_properties(
			game_state.get("player_state"),
			["level", "exp", "stamina", "max_stamina"]
		)
		or not _has_properties(
			season,
			["current_season", "current_day", "total_days", "hour", "minute"]
		)
		or not _has_properties(inventory, ["slots", "max_slots", "quick_slot_mappings"])
		or not _has_methods(inventory, ["get_item_count", "restore_state"])
		or not _has_methods(production, ["sync_daily_cursor", "get_current_day"])
		or not _has_methods(economy, ["to_dict", "from_dict", "reset_order_state"])
		or not _has_properties(market, ["last_settled_day"])
		or not _has_properties(npc, ["last_simulated_day"])
		or not _has_methods(npc, ["sync_daily_cursor"])
		or not _has_properties(daily, ["last_simulated_day"])
		or not _has_methods(resources, ["to_resource_dicts", "restore_resource_dicts"])
		or event_bus == null
		or (
			progression != null
			and not _has_methods(progression, ["debug_unlock_gate_eligible_blueprints"])
		)
	):
		return false
	_game_state = game_state
	_season = season
	_inventory = inventory
	_production = production
	_economy = economy
	_market = market
	_npc = npc
	_daily = daily
	_resources = resources
	_event_bus = event_bus
	_progression = progression
	_configured = true
	return true


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	var item_rows: Array[Dictionary] = []
	for value in GameDataScript.get_all_items():
		if value is Dictionary:
			item_rows.append((value as Dictionary).duplicate(true))
	item_rows.sort_custom(_sort_item_definitions)
	var items := {}
	for definition in item_rows:
		var item_id := str(definition.get("id", ""))
		if item_id.is_empty():
			continue
		items[item_id] = {
			"id": item_id,
			"name": str(definition.get("name", item_id)),
			"category": str(definition.get("category", "other")),
			"max_stack": int(
				definition.get("max_stack", GameDataScript.DEFAULT_MAX_STACK)
			),
			"quantity": int(_inventory.call("get_item_count", item_id)),
		}
	var player_state: Variant = _game_state.get("player_state")
	return {
		"level": int(player_state.get("level")),
		"elapsed_days": maxi(0, int(_season.get("total_days")) - 1),
		"gold": int(_game_state.get("gold")),
		"stamina": int(player_state.get("stamina")),
		"max_stamina": int(player_state.get("max_stamina")),
		"max_slots": int(_inventory.get("max_slots")),
		"items": items,
	}


func validate(draft: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("not_configured")
	if not _integer_in_range(
		draft.get("level"),
		1,
		PlayerStateScript.LEVEL_THRESHOLDS.size()
	):
		return _failure("invalid_level")
	if not _integer_in_range(
		draft.get("elapsed_days"),
		0,
		EconomyLimitsScript.MAX_SAFE_DATE - 1
	):
		return _failure("invalid_elapsed_days")
	if not _integer_in_range(
		draft.get("gold"),
		0,
		EconomyLimitsScript.MAX_SAFE_INTEGER
	):
		return _failure("invalid_gold")
	var player_state: Variant = _game_state.get("player_state")
	if not _integer_in_range(
		draft.get("stamina"),
		0,
		int(player_state.get("max_stamina"))
	):
		return _failure("invalid_stamina")
	var items_value: Variant = draft.get("items")
	if not items_value is Dictionary:
		return _failure("invalid_items")
	var required_slots := 0
	for item_id_value in items_value:
		var item_id := str(item_id_value)
		var definition: Variant = GameDataScript.get_item(item_id)
		if not definition is Dictionary:
			return _failure("unknown_item", {"item_id": item_id})
		var record: Variant = (items_value as Dictionary).get(item_id_value)
		if not record is Dictionary:
			return _failure("invalid_item_quantity", {"item_id": item_id})
		var max_stack := int(
			(definition as Dictionary).get(
				"max_stack", GameDataScript.DEFAULT_MAX_STACK
			)
		)
		var maximum := max_stack * int(_inventory.get("max_slots"))
		var quantity_value: Variant = (record as Dictionary).get("quantity")
		if max_stack <= 0 or not _integer_in_range(quantity_value, 0, maximum):
			return _failure("invalid_item_quantity", {"item_id": item_id})
		var quantity := int(quantity_value)
		if quantity > 0:
			required_slots += ceili(float(quantity) / float(max_stack))
	if required_slots > int(_inventory.get("max_slots")):
		return _failure(
			"inventory_capacity",
			{
				"required_slots": required_slots,
				"available_slots": int(_inventory.get("max_slots")),
			}
		)
	return {
		"ok": true,
		"reason": "",
		"required_slots": required_slots,
		"available_slots": int(_inventory.get("max_slots")),
	}


func apply(draft: Dictionary) -> Dictionary:
	if not OS.is_debug_build():
		return _failure("debug_build_required")
	var validation := validate(draft)
	if not bool(validation.get("ok", false)):
		return validation

	var target_total_days := int(draft.get("elapsed_days")) + 1
	var before := _capture_state()
	var target_inventory := _build_target_inventory(draft.get("items") as Dictionary)
	if target_inventory.is_empty():
		return _failure("transaction_failed")

	if not bool(_production.call("sync_daily_cursor", target_total_days)):
		_restore_cursors(before)
		return _failure("transaction_failed")
	if not bool(_npc.call("sync_daily_cursor", target_total_days)):
		_restore_cursors(before)
		return _failure("transaction_failed")
	var resource_state: Variant = before.get("resources")
	if not bool(
		_resources.call(
			"restore_resource_dicts",
			resource_state,
			target_total_days
		)
	):
		_restore_cursors(before)
		_resources.call(
			"restore_resource_dicts",
			resource_state,
			int(before.get("resource_day", before.get("total_days", 1)))
		)
		return _failure("transaction_failed")
	if (
		target_total_days != int(before.economy_day)
		and not bool(_economy.call("reset_order_state", target_total_days))
	):
		_restore_cursors(before)
		_resources.call(
			"restore_resource_dicts",
			resource_state,
			int(before.get("resource_day", before.get("total_days", 1)))
		)
		return _failure("transaction_failed")

	_market.set("last_settled_day", target_total_days)
	_daily.set("last_simulated_day", target_total_days)
	_apply_date_fields(int(draft.get("elapsed_days")), target_total_days)
	var player_state: Variant = _game_state.get("player_state")
	var level := int(draft.get("level"))
	player_state.set("level", level)
	player_state.set(
		"exp",
		int(PlayerStateScript.LEVEL_THRESHOLDS[level - 1])
		if level != int(before.level)
		else int(before.exp)
	)
	player_state.set("stamina", int(draft.get("stamina")))
	_game_state.set("gold", int(draft.get("gold")))
	_inventory.call(
		"restore_state",
		target_inventory.get("slots"),
		target_inventory.get("quick_mappings")
	)
	var unlocked_blueprint_count := 0
	if _progression != null:
		var unlock_result: Dictionary = _progression.call(
			"debug_unlock_gate_eligible_blueprints"
		)
		if not bool(unlock_result.get("ok", false)):
			return _failure(str(unlock_result.get("reason", "transaction_failed")))
		unlocked_blueprint_count = (unlock_result.get("blueprints", []) as Array).size()
	_emit_success_events(before, draft)
	var message := "调试数据已应用；尚未写入存档"
	if unlocked_blueprint_count > 0:
		message = "调试数据已应用；新解锁 %d 个蓝图；尚未写入存档" % unlocked_blueprint_count
	return {
		"ok": true,
		"reason": "",
		"message": message,
	}


func _apply_date_fields(elapsed_days: int, target_total_days: int) -> void:
	var days_per_season := int(_season.DAYS_PER_SEASON)
	_season.set("total_days", target_total_days)
	_season.set("current_day", elapsed_days % days_per_season + 1)
	_season.set(
		"current_season",
		floori(float(elapsed_days) / float(days_per_season)) % 4
	)


func _capture_state() -> Dictionary:
	var player_state: Variant = _game_state.get("player_state")
	var economy_state: Dictionary = _economy.call("to_dict")
	return {
		"level": int(player_state.get("level")),
		"exp": int(player_state.get("exp")),
		"stamina": int(player_state.get("stamina")),
		"gold": int(_game_state.get("gold")),
		"season": int(_season.get("current_season")),
		"day": int(_season.get("current_day")),
		"total_days": int(_season.get("total_days")),
		"hour": int(_season.get("hour")),
		"minute": int(_season.get("minute")),
		"slots": (_inventory.get("slots") as Array).duplicate(true),
		"quick_mappings": (
			_inventory.get("quick_slot_mappings") as Array
		).duplicate(),
		"production_day": int(_production.call("get_current_day")),
		"economy_day": int(economy_state.get("last_processed_day", 0)),
		"economy_state": economy_state,
		"market_day": int(_market.get("last_settled_day")),
		"npc_day": int(_npc.get("last_simulated_day")),
		"daily_day": int(_daily.get("last_simulated_day")),
		"resource_day": int(_season.get("total_days")),
		"resources": _resources.call("to_resource_dicts"),
		"item_counts": _item_counts(),
	}


func _restore_cursors(before: Dictionary) -> void:
	if not bool(_production.call("sync_daily_cursor", int(before.production_day))):
		if _has_properties(_production, ["_current_day"]):
			_production.set("_current_day", int(before.production_day))
	if not bool(_npc.call("sync_daily_cursor", int(before.npc_day))):
		_npc.set("last_simulated_day", int(before.npc_day))
	_economy.call("from_dict", before.economy_state)
	_market.set("last_settled_day", int(before.market_day))
	_daily.set("last_simulated_day", int(before.daily_day))


func _build_target_inventory(items: Dictionary) -> Dictionary:
	var item_ids: Array[String] = []
	for item_id_value in items:
		item_ids.append(str(item_id_value))
	item_ids.sort()
	var slots: Array[Dictionary] = []
	for item_id in item_ids:
		var quantity := int((items[item_id] as Dictionary).get("quantity", 0))
		if quantity <= 0:
			continue
		var definition := GameDataScript.get_item(item_id) as Dictionary
		var max_stack := int(
			definition.get("max_stack", GameDataScript.DEFAULT_MAX_STACK)
		)
		while quantity > 0:
			var stack_quantity := mini(quantity, max_stack)
			slots.append({"item_id": item_id, "quantity": stack_quantity})
			quantity -= stack_quantity
	if slots.size() > int(_inventory.get("max_slots")):
		return {}
	while slots.size() < int(_inventory.get("max_slots")):
		slots.append({})

	var previous_quick_items: Array[String] = []
	var previous_slots := _inventory.get("slots") as Array
	for mapping_value in _inventory.get("quick_slot_mappings") as Array:
		var slot_index := int(mapping_value)
		var item_id := ""
		if slot_index >= 0 and slot_index < previous_slots.size():
			item_id = str((previous_slots[slot_index] as Dictionary).get("item_id", ""))
		previous_quick_items.append(item_id)
	var first_slot_by_item := {}
	for index in range(slots.size()):
		var item_id := str(slots[index].get("item_id", ""))
		if not item_id.is_empty() and not first_slot_by_item.has(item_id):
			first_slot_by_item[item_id] = index
	var quick_mappings: Array[int] = []
	for item_id in previous_quick_items:
		quick_mappings.append(int(first_slot_by_item.get(item_id, -1)))
	return {"slots": slots, "quick_mappings": quick_mappings}


func _item_counts() -> Dictionary:
	var counts := {}
	for definition_value in GameDataScript.get_all_items():
		var definition := definition_value as Dictionary
		var item_id := str(definition.get("id", ""))
		if not item_id.is_empty():
			counts[item_id] = int(_inventory.call("get_item_count", item_id))
	return counts


func _emit_success_events(before: Dictionary, draft: Dictionary) -> void:
	if int(draft.level) != int(before.level):
		_emit_signal_if_available("level_changed", [int(draft.level)])
		_emit_signal_if_available("exp_gained", [0])
	if int(draft.gold) != int(before.gold):
		_emit_signal_if_available("gold_changed", [int(draft.gold)])
	if int(draft.stamina) != int(before.stamina):
		_emit_signal_if_available("stamina_changed", [int(draft.stamina)])
	var before_counts := before.item_counts as Dictionary
	var item_ids: Array[String] = []
	for item_id_value in draft.items:
		item_ids.append(str(item_id_value))
	item_ids.sort()
	for item_id in item_ids:
		var previous := int(before_counts.get(item_id, 0))
		var current := int((draft.items[item_id] as Dictionary).get("quantity", 0))
		if current > previous:
			_emit_signal_if_available("item_added", [item_id, current - previous])
		elif current < previous:
			_emit_signal_if_available("item_removed", [item_id, previous - current])
	var current_season := int(_season.get("current_season"))
	if current_season != int(before.season):
		_emit_signal_if_available("season_changed", [current_season])


func _emit_signal_if_available(signal_name: StringName, arguments: Array) -> void:
	if _event_bus != null and _event_bus.has_signal(signal_name):
		_event_bus.callv("emit_signal", [signal_name] + arguments)


func _failure(reason: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "reason": reason}
	result.merge(details, true)
	return result


func _sort_item_definitions(left: Dictionary, right: Dictionary) -> bool:
	var left_key := "%s|%s|%s" % [
		str(left.get("category", "")),
		str(left.get("name", "")),
		str(left.get("id", "")),
	]
	var right_key := "%s|%s|%s" % [
		str(right.get("category", "")),
		str(right.get("name", "")),
		str(right.get("id", "")),
	]
	return left_key < right_key


func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
		and int(value) >= minimum
		and int(value) <= maximum
	)


func _has_properties(target: Variant, names: Array[String]) -> bool:
	if target == null:
		return false
	var available := {}
	for property in target.get_property_list():
		available[str(property.get("name", ""))] = true
	for property_name in names:
		if not available.has(property_name):
			return false
	return true


func _has_methods(target: Variant, names: Array[String]) -> bool:
	if target == null:
		return false
	for method_name in names:
		if not target.has_method(method_name):
			return false
	return true
