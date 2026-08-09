class_name DebugStateEditor
extends RefCounted

const GameDataScript := preload("res://scripts/core/game_data.gd")
const EconomyLimitsScript := preload("res://scripts/core/economy_limits.gd")
const PlayerStateScript := preload("res://scripts/data/player_state.gd")

var _game_state: Variant
var _season: Variant
var _inventory: Variant
var _production: Variant
var _market: Variant
var _npc: Variant
var _daily: Variant
var _resources: Variant
var _event_bus: Variant
var _configured := false


func configure(
	game_state: Variant,
	season: Variant,
	inventory: Variant,
	production: Variant,
	market: Variant,
	npc: Variant,
	daily: Variant,
	resources: Variant,
	event_bus: Variant
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
		or not _has_properties(market, ["last_settled_day"])
		or not _has_properties(npc, ["last_simulated_day"])
		or not _has_methods(npc, ["sync_daily_cursor"])
		or not _has_properties(daily, ["last_simulated_day"])
		or not _has_methods(resources, ["to_resource_dicts", "restore_resource_dicts"])
		or event_bus == null
	):
		return false
	_game_state = game_state
	_season = season
	_inventory = inventory
	_production = production
	_market = market
	_npc = npc
	_daily = daily
	_resources = resources
	_event_bus = event_bus
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


func apply(_draft: Dictionary) -> Dictionary:
	if not OS.is_debug_build():
		return _failure("debug_build_required")
	return _failure("not_implemented")


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
