class_name MarketSystem
extends Node

const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")

const MarketMath = preload("res://scripts/shared/market_math.gd")

signal market_stock_changed(item_id: String, new_stock: int)
signal market_price_changed(item_id: String, new_price: int)
signal market_settled(total_day: int)

var last_settled_day: int = 0

var _items: Dictionary = {}
var _catalog_defaults: Dictionary = {}
var _event_bus: Node
var _transaction_owner: WeakRef
var _transaction_snapshot: Dictionary = {}
var _pending_stock_events: Dictionary = {}
var _pending_price_events: Dictionary = {}
var _pending_settlement_day := 0
var _sealed_owner: WeakRef
var _sealed_snapshot: Dictionary = {}
var _sealed_stock_events: Dictionary = {}
var _sealed_price_events: Dictionary = {}
var _sealed_settlement_day := 0
var _sealed_armed := false
var _publication_in_progress := false


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null


func configure(item_definitions: Array) -> bool:
	_recover_abandoned_state()
	if _has_atomic_state() or _has_sealed_state() or _publication_in_progress or item_definitions.is_empty():
		return false
	var configured_items: Dictionary = {}
	for definition_value in item_definitions:
		if not definition_value is Dictionary:
			return false
		var definition: Dictionary = definition_value
		if typeof(definition.get("id", null)) != TYPE_STRING:
			return false
		for field in ["base_price", "initial_stock", "target_stock", "daily_liquidity"]:
			if not definition.has(field) or not _is_integer_number(definition[field]):
				return false
		var item_id := str(definition.get("id", ""))
		var base_price := int(definition.get("base_price", 0))
		var initial_stock := int(definition.get("initial_stock", -1))
		var target_stock := int(definition.get("target_stock", 0))
		var daily_liquidity := int(definition.get("daily_liquidity", 0))
		if (
			item_id.is_empty()
			or configured_items.has(item_id)
			or base_price <= 0
			or initial_stock < 0
			or target_stock <= 0
			or daily_liquidity <= 0
			or base_price > EconomyLimitsScript.MAX_SAFE_INTEGER
			or initial_stock > EconomyLimitsScript.MAX_SAFE_INTEGER
			or target_stock > EconomyLimitsScript.MAX_SAFE_INTEGER
			or daily_liquidity > EconomyLimitsScript.MAX_SAFE_INTEGER
		):
			return false
		configured_items[item_id] = {
			"item_id": item_id,
			"base_price": base_price,
			"mid_price": base_price,
			"stock": initial_stock,
			"target_stock": target_stock,
			"daily_liquidity": daily_liquidity,
			"demand": 0,
			"supply": 0,
			"history": [base_price],
		}
	_items = configured_items
	_catalog_defaults = configured_items.duplicate(true)
	last_settled_day = 0
	return true


func get_item_state(item_id: String) -> Dictionary:
	if not _items.has(item_id):
		return {}
	return (_items[item_id] as Dictionary).duplicate(true)


func get_stock(item_id: String) -> int:
	if not _items.has(item_id):
		return 0
	return int((_items[item_id] as Dictionary).get("stock", 0))


func get_mid_price(item_id: String) -> int:
	if not _items.has(item_id):
		return 0
	return int((_items[item_id] as Dictionary).get("mid_price", 0))


func get_history(item_id: String) -> Array:
	if not _items.has(item_id):
		return []
	var history: Array = (_items[item_id] as Dictionary).get("history", [])
	return history.duplicate(true)


func quote_buy(item_id: String, quantity: int) -> int:
	if quantity <= 0 or quantity > EconomyLimitsScript.MAX_TRADE_QUANTITY or not _items.has(item_id):
		return 0
	var state: Dictionary = _items[item_id]
	return MarketMath.quote_total(
		int(state.get("mid_price", 0)),
		quantity,
		int(state.get("daily_liquidity", 0)),
		true
	)


func quote_sell(item_id: String, quantity: int) -> int:
	if quantity <= 0 or quantity > EconomyLimitsScript.MAX_TRADE_QUANTITY or not _items.has(item_id):
		return 0
	var state: Dictionary = _items[item_id]
	return MarketMath.quote_total(
		int(state.get("mid_price", 0)),
		quantity,
		int(state.get("daily_liquidity", 0)),
		false
	)


func can_buy(item_id: String, quantity: int) -> bool:
	return (
		quantity > 0
		and quantity <= EconomyLimitsScript.MAX_TRADE_QUANTITY
		and _items.has(item_id)
		and get_stock(item_id) >= quantity
	)


func begin_atomic_transaction() -> RefCounted:
	_recover_abandoned_state()
	if _items.is_empty() or _has_atomic_state() or _has_sealed_state() or _publication_in_progress:
		return null
	var token := RefCounted.new()
	_transaction_owner = weakref(token)
	_transaction_snapshot = to_dict()
	_pending_stock_events.clear()
	_pending_price_events.clear()
	_pending_settlement_day = 0
	return token


func end_atomic_transaction(transaction: Variant, commit_changes: Variant = null) -> bool:
	if typeof(commit_changes) != TYPE_BOOL or not _owns_atomic_transaction(transaction):
		return false
	if not commit_changes:
		return rollback_atomic_transaction(transaction)
	var stock_events := _pending_stock_events.duplicate()
	var price_events := _pending_price_events.duplicate()
	var settlement_day := _pending_settlement_day
	_clear_transaction_state()
	_publish_immediate_events(stock_events, price_events, settlement_day)
	return true


func rollback_atomic_transaction(transaction: Variant) -> bool:
	if not _owns_atomic_transaction(transaction):
		return false
	var before := _transaction_snapshot.duplicate(true)
	_clear_transaction_state()
	return _restore_transaction_snapshot(before)


func owns_atomic_transaction(transaction: Variant) -> bool:
	_recover_abandoned_state()
	return _owns_atomic_transaction(transaction)


func seal_atomic_transaction(transaction: Variant) -> RefCounted:
	_recover_abandoned_state()
	if not _owns_atomic_transaction(transaction) or _has_sealed_state() or _publication_in_progress:
		return null
	var publication := RefCounted.new()
	_sealed_owner = weakref(publication)
	_sealed_snapshot = _transaction_snapshot.duplicate(true)
	_sealed_stock_events = _pending_stock_events.duplicate()
	_sealed_price_events = _pending_price_events.duplicate()
	_sealed_settlement_day = _pending_settlement_day
	_sealed_armed = false
	_clear_transaction_state()
	return publication


func can_arm_sealed_transaction(publication: Variant) -> bool:
	_recover_abandoned_state()
	return _owns_sealed_transaction(publication) and not _sealed_armed and not _publication_in_progress


func arm_sealed_transaction(publication: Variant) -> bool:
	if not can_arm_sealed_transaction(publication):
		return false
	_sealed_armed = true
	return true


func can_publish_sealed_transaction(
	publication: Variant,
	allow_blocked_event_bus: bool = false
) -> bool:
	_recover_abandoned_state()
	if _publication_in_progress or not _owns_sealed_transaction(publication):
		return false
	if not _sealed_armed and not can_arm_sealed_transaction(publication):
		return false
	return (
		allow_blocked_event_bus
		or not is_instance_valid(_event_bus)
		or not _event_bus.is_blocking_signals()
	)


func publish_sealed_transaction(publication: Variant) -> bool:
	_recover_abandoned_state()
	if not can_publish_sealed_transaction(publication):
		return false
	if not _sealed_armed and not arm_sealed_transaction(publication):
		return false
	return _publish_sealed_transaction()


func cancel_sealed_transaction(publication: Variant) -> bool:
	_recover_abandoned_state()
	if not _owns_sealed_transaction(publication) or _sealed_armed or _publication_in_progress:
		return false
	var before := _sealed_snapshot.duplicate(true)
	_clear_sealed_state()
	return _restore_transaction_snapshot(before)


func owns_sealed_transaction(publication: Variant) -> bool:
	_recover_abandoned_state()
	return _owns_sealed_transaction(publication)


func commit_buy(item_id: String, quantity: int) -> bool:
	if not _can_mutate() or not can_buy(item_id, quantity):
		return false
	var state: Dictionary = _items[item_id]
	if not _can_add_safely(int(state.get("demand", -1)), quantity):
		return false
	state["stock"] = int(state.get("stock", 0)) - quantity
	state["demand"] = int(state.get("demand", 0)) + quantity
	_items[item_id] = state
	_emit_stock_changed(item_id, int(state["stock"]))
	return true


func commit_sell(item_id: String, quantity: int) -> bool:
	if (
		not _can_mutate()
		or quantity <= 0
		or quantity > EconomyLimitsScript.MAX_TRADE_QUANTITY
		or not _items.has(item_id)
	):
		return false
	var state: Dictionary = _items[item_id]
	if (
		not _can_add_safely(int(state.get("stock", -1)), quantity)
		or not _can_add_safely(int(state.get("supply", -1)), quantity)
	):
		return false
	state["stock"] = int(state.get("stock", 0)) + quantity
	state["supply"] = int(state.get("supply", 0)) + quantity
	_items[item_id] = state
	_emit_stock_changed(item_id, int(state["stock"]))
	return true


func add_external_demand(item_id: String, quantity: int) -> bool:
	if not _can_mutate() or quantity <= 0 or not _items.has(item_id):
		return false
	var state: Dictionary = _items[item_id]
	if not _can_add_safely(int(state.get("demand", -1)), quantity):
		return false
	state["demand"] = int(state.get("demand", 0)) + quantity
	_items[item_id] = state
	return true


func add_external_supply(item_id: String, quantity: int) -> bool:
	if not _can_mutate() or quantity <= 0 or not _items.has(item_id):
		return false
	var state: Dictionary = _items[item_id]
	if not _can_add_safely(int(state.get("supply", -1)), quantity):
		return false
	state["supply"] = int(state.get("supply", 0)) + quantity
	_items[item_id] = state
	return true


func can_settle_day(total_day: int) -> bool:
	return (
		_can_mutate()
		and EconomyLimitsScript.is_safe_date(total_day, false)
		and total_day > last_settled_day
		and not _items.is_empty()
	)


func settle_day(
	total_day: int,
	season_factors: Dictionary = {},
	event_factors: Dictionary = {}
) -> bool:
	if not can_settle_day(total_day):
		return false
	for item_id_value in _items.keys():
		var item_id := str(item_id_value)
		var state: Dictionary = _items[item_id]
		var old_price := int(state.get("mid_price", 0))
		var target_price := MarketMath.target_price(
			int(state.get("base_price", 0)),
			int(state.get("stock", 0)),
			int(state.get("target_stock", 0)),
			int(state.get("demand", 0)),
			int(state.get("supply", 0)),
			int(state.get("daily_liquidity", 0)),
			_factor_for_item(season_factors, item_id),
			_factor_for_item(event_factors, item_id)
		)
		var new_price := MarketMath.smooth_price(
			old_price,
			target_price,
			int(state.get("base_price", 0))
		)
		state["mid_price"] = new_price
		state["demand"] = 0
		state["supply"] = 0
		var history: Array = state.get("history", [])
		history.append(new_price)
		while history.size() > 7:
			history.pop_front()
		state["history"] = history
		_items[item_id] = state
		if new_price != old_price:
			_emit_price_changed(item_id, new_price)
	last_settled_day = total_day
	_emit_settled(total_day)
	return true


func to_dict() -> Dictionary:
	return {
		"last_settled_day": last_settled_day,
		"items": _items.duplicate(true),
	}


func from_dict(data: Dictionary) -> bool:
	_recover_abandoned_state()
	if _has_atomic_state() or _has_sealed_state() or _publication_in_progress:
		return false
	if not data.has("last_settled_day") or not data.has("items"):
		return false
	if not EconomyLimitsScript.is_safe_date(data["last_settled_day"]):
		return false
	if not data["items"] is Dictionary or (data["items"] as Dictionary).is_empty():
		return false
	var restored_items: Dictionary = {}
	for item_key in (data["items"] as Dictionary).keys():
		if not (data["items"] as Dictionary)[item_key] is Dictionary:
			return false
		var state: Dictionary = (data["items"] as Dictionary)[item_key]
		var normalized := _normalize_runtime_state(str(item_key), state)
		if normalized.is_empty():
			return false
		restored_items[str(item_key)] = normalized
	_items = restored_items
	last_settled_day = int(data["last_settled_day"])
	return true


func restore_from_dict_with_current_catalog(data: Dictionary) -> bool:
	_recover_abandoned_state()
	if _has_atomic_state() or _has_sealed_state() or _publication_in_progress or _catalog_defaults.is_empty():
		return false
	if not data.has("last_settled_day") or not data.has("items"):
		return false
	if not EconomyLimitsScript.is_safe_date(data["last_settled_day"]):
		return false
	if not data["items"] is Dictionary or (data["items"] as Dictionary).is_empty():
		return false
	var saved_items: Dictionary = {}
	for item_key in (data["items"] as Dictionary).keys():
		if not (data["items"] as Dictionary)[item_key] is Dictionary:
			return false
		var normalized := _normalize_runtime_state(
			str(item_key),
			(data["items"] as Dictionary)[item_key]
		)
		if normalized.is_empty():
			return false
		saved_items[str(item_key)] = normalized

	var migrated_items := _catalog_defaults.duplicate(true)
	for item_key in migrated_items.keys():
		var item_id := str(item_key)
		if not saved_items.has(item_id):
			continue
		var catalog_state: Dictionary = migrated_items[item_id]
		var saved_state: Dictionary = saved_items[item_id]
		var base_price := int(catalog_state["base_price"])
		var saved_base_price := int(saved_state["base_price"])
		var global_min := ceili(base_price * 0.5)
		var global_max := floori(base_price * 2.5)
		var mid_price := clampi(
			roundi(float(saved_state["mid_price"]) * float(base_price) / float(saved_base_price)),
			global_min,
			global_max
		)
		var history: Array[int] = []
		for value in saved_state["history"]:
			history.append(clampi(
				roundi(float(value) * float(base_price) / float(saved_base_price)),
				global_min,
				global_max
			))
		history[-1] = mid_price
		catalog_state["mid_price"] = mid_price
		catalog_state["stock"] = int(saved_state["stock"])
		catalog_state["demand"] = int(saved_state["demand"])
		catalog_state["supply"] = int(saved_state["supply"])
		catalog_state["history"] = history
		migrated_items[item_id] = catalog_state

	_items = migrated_items
	last_settled_day = int(data["last_settled_day"])
	return true


func _normalize_runtime_state(item_key: String, state: Dictionary) -> Dictionary:
	var required_numeric := [
		"base_price", "mid_price", "stock", "target_stock", "daily_liquidity", "demand", "supply"
	]
	for field in required_numeric:
		if not state.has(field) or not _is_integer_number(state[field]):
			return {}
	var item_id := str(state.get("item_id", ""))
	if item_id.is_empty() or item_id != item_key:
		return {}
	if (
		int(state["base_price"]) <= 0
		or int(state["mid_price"]) <= 0
		or int(state["stock"]) < 0
		or int(state["target_stock"]) <= 0
		or int(state["daily_liquidity"]) <= 0
		or int(state["demand"]) < 0
		or int(state["supply"]) < 0
		or int(state["base_price"]) > EconomyLimitsScript.MAX_SAFE_INTEGER
		or int(state["mid_price"]) > EconomyLimitsScript.MAX_SAFE_INTEGER
		or int(state["stock"]) > EconomyLimitsScript.MAX_SAFE_INTEGER
		or int(state["target_stock"]) > EconomyLimitsScript.MAX_SAFE_INTEGER
		or int(state["daily_liquidity"]) > EconomyLimitsScript.MAX_SAFE_INTEGER
		or int(state["demand"]) > EconomyLimitsScript.MAX_SAFE_INTEGER
		or int(state["supply"]) > EconomyLimitsScript.MAX_SAFE_INTEGER
	):
		return {}
	var global_min := ceili(int(state["base_price"]) * 0.5)
	var global_max := floori(int(state["base_price"]) * 2.5)
	if int(state["mid_price"]) < global_min or int(state["mid_price"]) > global_max:
		return {}
	if not state.get("history", null) is Array:
		return {}
	var source_history: Array = state["history"]
	if source_history.is_empty() or source_history.size() > 7:
		return {}
	var history: Array[int] = []
	for price_value in source_history:
		if (
			not _is_integer_number(price_value)
			or int(price_value) < global_min
			or int(price_value) > global_max
		):
			return {}
		history.append(int(price_value))
	if history[-1] != int(state["mid_price"]):
		return {}
	return {
		"item_id": item_id,
		"base_price": int(state["base_price"]),
		"mid_price": int(state["mid_price"]),
		"stock": int(state["stock"]),
		"target_stock": int(state["target_stock"]),
		"daily_liquidity": int(state["daily_liquidity"]),
		"demand": int(state["demand"]),
		"supply": int(state["supply"]),
		"history": history,
	}


func _factor_for_item(factors: Dictionary, item_id: String) -> float:
	var value: Variant = factors.get(item_id, 1.0)
	return float(value) if _is_number(value) else 1.0


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _is_integer_number(value: Variant) -> bool:
	return _is_number(value) and is_finite(float(value)) and floorf(float(value)) == float(value)


func _emit_stock_changed(item_id: String, new_stock: int) -> void:
	if _has_atomic_state():
		_pending_stock_events[item_id] = new_stock
		return
	market_stock_changed.emit(item_id, new_stock)
	_emit_event_bus("market_stock_changed", [item_id, new_stock])


func _emit_price_changed(item_id: String, new_price: int) -> void:
	if _has_atomic_state():
		_pending_price_events[item_id] = new_price
		return
	market_price_changed.emit(item_id, new_price)
	_emit_event_bus("market_price_changed", [item_id, new_price])


func _emit_settled(total_day: int) -> void:
	if _has_atomic_state():
		_pending_settlement_day = total_day
		return
	market_settled.emit(total_day)
	_emit_event_bus("market_settled", [total_day])


func _emit_event_bus(signal_name: StringName, arguments: Array) -> void:
	if _event_bus != null and _event_bus.has_signal(signal_name):
		if arguments.size() == 2:
			_event_bus.emit_signal(signal_name, arguments[0], arguments[1])
		elif arguments.size() == 1:
			_event_bus.emit_signal(signal_name, arguments[0])


func _can_add_safely(current: int, quantity: int) -> bool:
	return (
		current >= 0
		and quantity > 0
		and current <= EconomyLimitsScript.MAX_SAFE_INTEGER - quantity
	)


func _restore_transaction_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.is_empty():
		return false
	_items = (snapshot.get("items", {}) as Dictionary).duplicate(true)
	last_settled_day = int(snapshot.get("last_settled_day", 0))
	return to_dict() == snapshot


func _can_mutate() -> bool:
	_recover_abandoned_state()
	return not _has_sealed_state() and not _publication_in_progress


func _publish_sealed_transaction() -> bool:
	if not _has_sealed_state() or _publication_in_progress:
		return false
	var stock_events := _sealed_stock_events.duplicate()
	var price_events := _sealed_price_events.duplicate()
	var settlement_day := _sealed_settlement_day
	_publication_in_progress = true
	_clear_sealed_state()
	_publish_committed_events(stock_events, price_events, settlement_day)
	_publication_in_progress = false
	_ensure_event_bus_unblocked()
	return true


func _publish_committed_events(
	stock_events: Dictionary,
	price_events: Dictionary,
	settlement_day: int
) -> void:
	for item_id in stock_events:
		var normalized_id := str(item_id)
		var stock := int(stock_events[item_id])
		market_stock_changed.emit(normalized_id, stock)
		_ensure_event_bus_unblocked()
		_emit_event_bus("market_stock_changed", [normalized_id, stock])
	for item_id in price_events:
		var normalized_id := str(item_id)
		var price := int(price_events[item_id])
		market_price_changed.emit(normalized_id, price)
		_ensure_event_bus_unblocked()
		_emit_event_bus("market_price_changed", [normalized_id, price])
	if settlement_day > 0:
		market_settled.emit(settlement_day)
		_ensure_event_bus_unblocked()
		_emit_event_bus("market_settled", [settlement_day])


func _publish_immediate_events(
	stock_events: Dictionary,
	price_events: Dictionary,
	settlement_day: int
) -> void:
	for item_id in stock_events:
		_emit_stock_changed(str(item_id), int(stock_events[item_id]))
	for item_id in price_events:
		_emit_price_changed(str(item_id), int(price_events[item_id]))
	if settlement_day > 0:
		_emit_settled(settlement_day)


func _ensure_event_bus_unblocked() -> void:
	if is_instance_valid(_event_bus) and _event_bus.is_blocking_signals():
		_event_bus.set_block_signals(false)


func _has_atomic_state() -> bool:
	return _transaction_owner != null or not _transaction_snapshot.is_empty()


func _owns_atomic_transaction(transaction: Variant) -> bool:
	return (
		transaction is RefCounted
		and _transaction_owner != null
		and _transaction_owner.get_ref() == transaction
	)


func _has_sealed_state() -> bool:
	return _sealed_owner != null or not _sealed_snapshot.is_empty()


func _owns_sealed_transaction(publication: Variant) -> bool:
	return (
		publication is RefCounted
		and _sealed_owner != null
		and _sealed_owner.get_ref() == publication
	)


func _recover_abandoned_state() -> void:
	if _has_atomic_state() and (
		_transaction_owner == null or _transaction_owner.get_ref() == null
	):
		var before := _transaction_snapshot.duplicate(true)
		_clear_transaction_state()
		_restore_transaction_snapshot(before)
	if _has_sealed_state() and (_sealed_owner == null or _sealed_owner.get_ref() == null):
		if _sealed_armed:
			_publish_sealed_transaction()
		else:
			var before := _sealed_snapshot.duplicate(true)
			_clear_sealed_state()
			_restore_transaction_snapshot(before)


func _clear_transaction_state() -> void:
	_transaction_owner = null
	_transaction_snapshot.clear()
	_pending_stock_events.clear()
	_pending_price_events.clear()
	_pending_settlement_day = 0


func _clear_sealed_state() -> void:
	_sealed_owner = null
	_sealed_snapshot.clear()
	_sealed_stock_events.clear()
	_sealed_price_events.clear()
	_sealed_settlement_day = 0
	_sealed_armed = false
