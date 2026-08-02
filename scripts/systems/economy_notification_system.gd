class_name EconomyNotificationSystem
extends Node

signal notification_pushed(record: Dictionary, merged: bool)
signal notifications_changed
signal unread_count_changed(count: int)

const GameDataScript = preload("res://scripts/core/game_data.gd")

const VERSION := 1
const MAX_RECORDS := 20
const MERGE_WINDOW_SECONDS := 3.0
const MAX_SAFE_DAY := 2147483647
const MAX_COUNT := 1000000
const MAX_TITLE_LENGTH := 128
const MAX_BODY_LENGTH := 512
const MAX_ID_LENGTH := 256
const SHORTAGE_RATIO := 0.35

const KINDS := [
	"price_up", "price_down", "shortage", "recovery",
	"caravan_arrived", "caravan_departed",
	"completed", "full", "feed_shortage", "maintenance_due",
	"order_due", "order_completed", "order_expired",
	"contract_breached", "contract_completed", "contract_expired",
	"unlock", "tool_broken",
]
const TARGET_TYPES := ["", "market_item", "building", "order", "contract", "service", "tool"]
const URGENT_KINDS := [
	"shortage", "full", "feed_shortage", "maintenance_due",
	"order_due", "order_expired", "contract_breached", "contract_expired", "tool_broken",
]

var _records: Array[Dictionary] = []
var _merge_state: Dictionary = {}
var _event_bus: Node
var _market: Variant
var _economy: Variant
var _season: Variant
var _last_prices: Dictionary = {}
var _shortage_state: Dictionary = {}


func configure(
	event_bus: Node,
	market: Variant = null,
	economy: Variant = null,
	season: Variant = null
) -> bool:
	if event_bus == null or not is_instance_valid(event_bus):
		return false
	_disconnect_event_bus()
	_event_bus = event_bus
	_market = market
	_economy = economy
	_season = season
	_refresh_market_baselines()
	_connect_event_bus()
	return true


func push(
	kind: String,
	title: String,
	body: String,
	total_day: int,
	target_type: String = "",
	target_id: String = "",
	timestamp_seconds: float = -1.0
) -> String:
	if not _valid_payload(kind, title, body, total_day, target_type, target_id):
		return ""
	var now := timestamp_seconds
	if now == -1.0:
		now = float(Time.get_ticks_msec()) / 1000.0
	if not is_finite(now) or now < 0.0:
		return ""
	var merge_key := _merge_key(kind, target_type, target_id)
	var merge_value: Variant = _merge_state.get(merge_key)
	if merge_value is Dictionary:
		var merge_entry := merge_value as Dictionary
		var elapsed := now - float(merge_entry.get("timestamp", -MERGE_WINDOW_SECONDS))
		var index := _find_record(str(merge_entry.get("notification_id", "")))
		if elapsed >= 0.0 and elapsed < MERGE_WINDOW_SECONDS and index >= 0:
			var record: Dictionary = _records[index]
			if int(record.count) < MAX_COUNT:
				record["title"] = title
				record["body"] = body
				record["total_day"] = total_day
				record["count"] = int(record.count) + 1
				record["unread"] = true
				_records.remove_at(index)
				_records.push_front(record)
				_merge_state[merge_key] = {
					"notification_id": str(record.notification_id),
					"timestamp": now,
				}
				_emit_state_change(record, true)
				return str(record.notification_id)

	var notification_id := _next_notification_id(kind, total_day, target_id)
	if notification_id.is_empty():
		return ""
	var record := {
		"notification_id": notification_id,
		"kind": kind,
		"title": title,
		"body": body,
		"total_day": total_day,
		"target_type": target_type,
		"target_id": target_id,
		"unread": true,
		"count": 1,
	}
	_records.push_front(record)
	while _records.size() > MAX_RECORDS:
		var removed: Dictionary = _records.pop_back()
		_remove_merge_entries_for_id(str(removed.notification_id))
	_merge_state[merge_key] = {
		"notification_id": notification_id,
		"timestamp": now,
	}
	_emit_state_change(record, false)
	return notification_id


func mark_read(notification_id: String) -> bool:
	var index := _find_record(notification_id)
	if index < 0 or not bool(_records[index].unread):
		return false
	_records[index]["unread"] = false
	_emit_read_change(notification_id)
	return true


func mark_all_read() -> void:
	var changed := false
	for record in _records:
		if bool(record.unread):
			record["unread"] = false
			changed = true
	if changed:
		notifications_changed.emit()
		unread_count_changed.emit(0)
		_emit_event_bus_change("", false)


func get_recent(limit: int = MAX_RECORDS) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(mini(maxi(limit, 0), _records.size())):
		result.append(_records[index].duplicate(true))
	return result


func get_unread_count() -> int:
	var result := 0
	for record in _records:
		if bool(record.unread):
			result += 1
	return result


func to_dict() -> Dictionary:
	return {"version": VERSION, "records": _records.duplicate(true)}


func validate_dict(data: Dictionary) -> bool:
	return _parse_dict(data) != null


func from_dict(data: Dictionary) -> bool:
	var parsed: Variant = _parse_dict(data)
	if not parsed is Array:
		return false
	var next_records: Array[Dictionary] = []
	next_records.assign(parsed)
	_records = next_records
	_merge_state.clear()
	_refresh_market_baselines()
	notifications_changed.emit()
	unread_count_changed.emit(get_unread_count())
	_emit_event_bus_change("", false)
	return true


func reset_notifications() -> void:
	var had_records := not _records.is_empty()
	_records.clear()
	_merge_state.clear()
	_refresh_market_baselines()
	if had_records:
		notifications_changed.emit()
		unread_count_changed.emit(0)
		_emit_event_bus_change("", false)


static func is_urgent_kind(kind: String) -> bool:
	return kind in URGENT_KINDS


func _parse_dict(data: Dictionary) -> Variant:
	if not _has_exact_fields(data, ["version", "records"]):
		return null
	if not _is_integer_number(data.version) or int(data.version) != VERSION or not data.records is Array:
		return null
	var source := data.records as Array
	if source.size() > MAX_RECORDS:
		return null
	var parsed: Array[Dictionary] = []
	var ids := {}
	for value in source:
		if not value is Dictionary:
			return null
		var record := value as Dictionary
		if not _valid_record(record):
			return null
		var notification_id := str(record.notification_id)
		if ids.has(notification_id):
			return null
		ids[notification_id] = true
		parsed.append(record.duplicate(true))
	return parsed


func _valid_record(record: Dictionary) -> bool:
	if not _has_exact_fields(record, [
		"notification_id", "kind", "title", "body", "total_day",
		"target_type", "target_id", "unread", "count",
	]):
		return false
	if (
		typeof(record.notification_id) != TYPE_STRING
		or typeof(record.kind) != TYPE_STRING
		or typeof(record.title) != TYPE_STRING
		or typeof(record.body) != TYPE_STRING
		or typeof(record.target_type) != TYPE_STRING
		or typeof(record.target_id) != TYPE_STRING
		or typeof(record.unread) != TYPE_BOOL
		or not _is_integer_number(record.total_day)
		or not _is_integer_number(record.count)
	):
		return false
	if not _valid_payload(
		str(record.kind), str(record.title), str(record.body), int(record.total_day),
		str(record.target_type), str(record.target_id)
	):
		return false
	if int(record.count) < 1 or int(record.count) > MAX_COUNT:
		return false
	return _notification_id_matches(record)


func _valid_payload(
	kind: String,
	title: String,
	body: String,
	total_day: int,
	target_type: String,
	target_id: String
) -> bool:
	if kind not in KINDS or target_type not in TARGET_TYPES:
		return false
	if title.is_empty() or title.length() > MAX_TITLE_LENGTH:
		return false
	if body.is_empty() or body.length() > MAX_BODY_LENGTH:
		return false
	if total_day < 0 or total_day > MAX_SAFE_DAY:
		return false
	if (target_type.is_empty()) != (target_id.is_empty()):
		return false
	return _valid_identifier(target_id, true)


func _notification_id_matches(record: Dictionary) -> bool:
	var notification_id := str(record.notification_id)
	if not _valid_identifier(notification_id, false):
		return false
	var unsuffixed := notification_id
	var suffix_index := notification_id.rfind("#")
	if suffix_index >= 0:
		var suffix := notification_id.substr(suffix_index + 1)
		if not suffix.is_valid_int() or int(suffix) < 2:
			return false
		unsuffixed = notification_id.substr(0, suffix_index)
	var prefix := _category_for_kind(str(record.kind)) + ":"
	if not unsuffixed.begins_with(prefix):
		return false
	var remainder := unsuffixed.substr(prefix.length())
	var separator := remainder.find(":")
	if separator <= 0:
		return false
	var id_day := remainder.substr(0, separator)
	var id_target := remainder.substr(separator + 1)
	return (
		id_day.is_valid_int()
		and int(id_day) >= 0
		and int(id_day) <= MAX_SAFE_DAY
		and id_target == (str(record.target_id) if not str(record.target_id).is_empty() else "general")
	)


func _next_notification_id(kind: String, total_day: int, target_id: String) -> String:
	var base := "%s:%d:%s" % [
		_category_for_kind(kind), total_day, target_id if not target_id.is_empty() else "general",
	]
	if _find_record(base) < 0:
		return base
	var suffix := 2
	while suffix <= MAX_COUNT:
		var candidate := "%s#%d" % [base, suffix]
		if _find_record(candidate) < 0:
			return candidate
		suffix += 1
	return ""


func _find_record(notification_id: String) -> int:
	for index in range(_records.size()):
		if str(_records[index].notification_id) == notification_id:
			return index
	return -1


func _merge_key(kind: String, target_type: String, target_id: String) -> String:
	return "%s\n%s\n%s" % [kind, target_type, target_id]


func _remove_merge_entries_for_id(notification_id: String) -> void:
	for key in _merge_state.keys():
		if str((_merge_state[key] as Dictionary).get("notification_id", "")) == notification_id:
			_merge_state.erase(key)


func _emit_state_change(record: Dictionary, merged: bool) -> void:
	notification_pushed.emit(record.duplicate(true), merged)
	notifications_changed.emit()
	unread_count_changed.emit(get_unread_count())
	_emit_event_bus_change(str(record.notification_id), merged)


func _emit_read_change(notification_id: String) -> void:
	notifications_changed.emit()
	unread_count_changed.emit(get_unread_count())
	_emit_event_bus_change(notification_id, false)


func _emit_event_bus_change(notification_id: String, merged: bool) -> void:
	if _event_bus != null and is_instance_valid(_event_bus) and _event_bus.has_signal("economy_notification_changed"):
		_event_bus.emit_signal("economy_notification_changed", notification_id, merged)


func _connect_event_bus() -> void:
	for binding in _event_bindings():
		var signal_name: StringName = binding[0]
		var callback: Callable = binding[1]
		if _event_bus.has_signal(signal_name) and not _event_bus.is_connected(signal_name, callback):
			_event_bus.connect(signal_name, callback)


func _disconnect_event_bus() -> void:
	if _event_bus == null or not is_instance_valid(_event_bus):
		_event_bus = null
		return
	for binding in _event_bindings():
		var signal_name: StringName = binding[0]
		var callback: Callable = binding[1]
		if _event_bus.has_signal(signal_name) and _event_bus.is_connected(signal_name, callback):
			_event_bus.disconnect(signal_name, callback)
	_event_bus = null


func _event_bindings() -> Array:
	return [
		[&"market_price_changed", Callable(self, "_on_market_price_changed")],
		[&"market_stock_changed", Callable(self, "_on_market_stock_changed")],
		[&"market_caravan_changed", Callable(self, "_on_market_caravan_changed")],
		[&"production_job_completed", Callable(self, "_on_production_completed")],
		[&"production_output_blocked", Callable(self, "_on_production_blocked")],
		[&"production_feed_shortage", Callable(self, "_on_feed_shortage")],
		[&"production_maintenance_changed", Callable(self, "_on_maintenance_changed")],
		[&"order_updated", Callable(self, "_on_order_updated")],
		[&"contract_updated", Callable(self, "_on_contract_updated")],
		[&"service_unlocked", Callable(self, "_on_service_unlocked")],
		[&"building_upgrade_changed", Callable(self, "_on_building_upgrade_changed")],
		[&"tool_durability_changed", Callable(self, "_on_tool_durability_changed")],
		[&"day_changed", Callable(self, "_on_day_changed")],
	]


func _refresh_market_baselines() -> void:
	_last_prices.clear()
	_shortage_state.clear()
	if _market == null or not _market.has_method("to_dict"):
		return
	var snapshot: Variant = _market.call("to_dict")
	if not snapshot is Dictionary or not snapshot.get("items", null) is Dictionary:
		return
	for item_id_value in (snapshot.items as Dictionary).keys():
		var item_id := str(item_id_value)
		var state: Dictionary = snapshot.items[item_id]
		_last_prices[item_id] = int(state.get("mid_price", 0))
		_shortage_state[item_id] = _is_shortage(int(state.get("stock", 0)), int(state.get("target_stock", 1)))


func _on_market_price_changed(item_id: String, new_price: int) -> void:
	var old_price := int(_last_prices.get(item_id, 0))
	_last_prices[item_id] = new_price
	if old_price <= 0 or new_price <= 0:
		return
	var ratio := absf(float(new_price - old_price)) / float(old_price)
	if ratio + 0.000001 < 0.10:
		return
	var item_name := _item_name(item_id)
	var kind := "price_up" if new_price > old_price else "price_down"
	var direction := "上涨" if new_price > old_price else "下跌"
	push(kind, "价格%s" % direction, "%s价格%s %d%%" % [item_name, direction, roundi(ratio * 100.0)], _current_day(), "market_item", item_id)


func _on_market_stock_changed(item_id: String, new_stock: int) -> void:
	var target_stock := 1
	if _market != null and _market.has_method("get_item_state"):
		target_stock = int((_market.call("get_item_state", item_id) as Dictionary).get("target_stock", 1))
	var shortage := _is_shortage(new_stock, target_stock)
	var previous := bool(_shortage_state.get(item_id, false))
	_shortage_state[item_id] = shortage
	if shortage == previous:
		return
	var kind := "shortage" if shortage else "recovery"
	push(kind, "库存紧缺" if shortage else "库存恢复", "%s%s" % [_item_name(item_id), "进入紧缺" if shortage else "恢复正常"], _current_day(), "market_item", item_id)


func _on_market_caravan_changed(
	caravan_id: String,
	item_id: String,
	quantity: int,
	total_day: int,
	arrived: bool
) -> void:
	push(
		"caravan_arrived" if arrived else "caravan_departed",
		"商队到访" if arrived else "商队离开",
		"%s%s：%s ×%d" % [caravan_id, "已到访" if arrived else "已离开", item_id, quantity],
		total_day
	)


func _on_production_completed(building: BuildingInstance, recipe_id: String, outputs: Dictionary) -> void:
	var parts: Array[String] = []
	var item_ids: Array[String] = []
	item_ids.assign(outputs.keys())
	item_ids.sort()
	for item_id in item_ids:
		parts.append("%s ×%d" % [_item_name(item_id), int(outputs[item_id])])
	push("completed", "生产完成", "%s完成了%s" % [_building_name(building), "、".join(parts)], _current_day(), "building" if building != null else "", _building_key(building))


func _on_production_blocked(building: BuildingInstance, _recipe_id: String) -> void:
	push("full", "产物已满", "%s的产物仓库已满" % _building_name(building), _current_day(), "building" if building != null else "", _building_key(building))


func _on_feed_shortage(
	building: BuildingInstance,
	item_id: String,
	shortage: bool,
	total_day: int
) -> void:
	if not shortage:
		return
	push("feed_shortage", "缺少饲料", "%s缺少%s" % [_building_name(building), _item_name(item_id)], total_day, "building" if building != null else "", _building_key(building))


func _on_maintenance_changed(building: BuildingInstance, due_day: int) -> void:
	if due_day <= _current_day():
		push("maintenance_due", "维护到期", "%s需要维护" % _building_name(building), _current_day(), "building" if building != null else "", _building_key(building))


func _on_order_updated(order_id: String) -> void:
	var order := _find_economy_record("get_orders", "order_id", order_id)
	if order.is_empty():
		return
	var kind := ""
	var title := ""
	if bool(order.get("completed", false)):
		kind = "order_completed"
		title = "订单完成"
	elif bool(order.get("expired", false)):
		kind = "order_expired"
		title = "订单失效"
	elif int(order.get("expires_day", MAX_SAFE_DAY)) - _current_day() <= 1:
		kind = "order_due"
		title = "订单临期"
	if not kind.is_empty():
		if _has_record(kind, "order", order_id):
			return
		push(kind, title, "%s：%s ×%d" % [order_id, _item_name(str(order.get("item_id", ""))), int(order.get("quantity", 0))], _current_day(), "order", order_id)


func _on_contract_updated(contract_id: String) -> void:
	var contract := _find_economy_record("get_contracts", "contract_id", contract_id)
	if contract.is_empty():
		return
	var kind := ""
	var title := ""
	var body := contract_id
	if bool(contract.get("completed", false)):
		kind = "contract_completed"
		title = "合同全部履约"
	elif bool(contract.get("expired", false)):
		kind = "contract_expired"
		title = "合同失效"
	elif int(contract.get("breaches", 0)) > 0:
		kind = "contract_breached"
		title = "合同未完成"
		body = "%s：第 %d 次违约" % [contract_id, int(contract.get("breaches", 0))]
	if not kind.is_empty():
		if kind == "contract_breached" and _has_contract_breach_occurrence(contract_id, body):
			return
		if kind != "contract_breached" and _has_record(kind, "contract", contract_id):
			return
		if kind == "contract_breached":
			_merge_state.erase(_merge_key(kind, "contract", contract_id))
		push(kind, title, body, _current_day(), "contract", contract_id)


func _has_contract_breach_occurrence(contract_id: String, body: String) -> bool:
	for record in _records:
		if (
			str(record.kind) == "contract_breached"
			and str(record.target_type) == "contract"
			and str(record.target_id) == contract_id
			and str(record.body) == body
		):
			return true
	return false


func _has_record(kind: String, target_type: String, target_id: String) -> bool:
	for record in _records:
		if str(record.kind) == kind and str(record.target_type) == target_type and str(record.target_id) == target_id:
			return true
	return false


func _on_service_unlocked(kind: String, target_id: String) -> void:
	push("unlock", "经营解锁", "%s：%s" % [kind, target_id], _current_day())


func _on_building_upgrade_changed(building: BuildingInstance, upgrade_id: String, level: int) -> void:
	push("unlock", "建筑升级", "%s的%s达到 %d 级" % [_building_name(building), upgrade_id, level], _current_day(), "building" if building != null else "", _building_key(building))


func _on_tool_durability_changed(tool_id: String, current: int, _maximum: int) -> void:
	if current == 0:
		push("tool_broken", "工具损坏", "%s耐久已归零" % tool_id, _current_day(), "tool", tool_id)


func _on_day_changed(_total_day: int) -> void:
	if _economy == null:
		return
	if _economy.has_method("get_orders"):
		for order in _economy.call("get_orders"):
			_on_order_updated(str(order.get("order_id", "")))
	if _economy.has_method("get_contracts"):
		for contract in _economy.call("get_contracts"):
			_on_contract_updated(str(contract.get("contract_id", "")))


func _find_economy_record(method_name: String, id_field: String, target_id: String) -> Dictionary:
	if _economy == null or not _economy.has_method(method_name):
		return {}
	for value in _economy.call(method_name):
		if value is Dictionary and str(value.get(id_field, "")) == target_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _current_day() -> int:
	if _season != null:
		for property in _season.get_property_list():
			if str(property.get("name", "")) == "total_days":
				return maxi(0, int(_season.get("total_days")))
	if _market != null:
		for property in _market.get_property_list():
			if str(property.get("name", "")) == "last_settled_day":
				return maxi(0, int(_market.get("last_settled_day")))
	return 0


func _is_shortage(stock: int, target_stock: int) -> bool:
	return float(stock) / maxf(1.0, float(target_stock)) < SHORTAGE_RATIO


func _item_name(item_id: String) -> String:
	var definition: Variant = GameDataScript.get_item(item_id)
	return str(definition.get("name", item_id)) if definition is Dictionary else item_id


func _building_name(building: BuildingInstance) -> String:
	if building == null:
		return "建筑"
	var definition := GameDataScript.get_building(building.building_id)
	return str(definition.get("name", building.building_id))


func _building_key(building: BuildingInstance) -> String:
	if building == null:
		return ""
	return "%s:%d:%d" % [building.building_id, building.grid_x, building.grid_z]


func _category_for_kind(kind: String) -> String:
	if kind in ["price_up", "price_down", "shortage", "recovery"]:
		return "market"
	if kind in ["completed", "full", "feed_shortage", "maintenance_due"]:
		return "production"
	if kind.begins_with("order_"):
		return "order"
	if kind.begins_with("contract_"):
		return "contract"
	if kind.begins_with("caravan_"):
		return "caravan"
	if kind == "tool_broken":
		return "tool"
	return "unlock"


func _valid_identifier(value: String, allow_empty: bool) -> bool:
	if value.is_empty():
		return allow_empty
	if value.length() > MAX_ID_LENGTH or value.contains("\n") or value.contains("\r"):
		return false
	return true


func _has_exact_fields(data: Dictionary, fields: Array) -> bool:
	if data.size() != fields.size():
		return false
	for field in fields:
		if not data.has(field):
			return false
	return true


func _is_integer_number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
	)


func _exit_tree() -> void:
	_disconnect_event_bus()
