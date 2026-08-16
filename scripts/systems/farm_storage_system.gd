class_name FarmStorageSystem
extends Node

const GameDataScript = preload("res://scripts/core/game_data.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")
const DEFAULT_CAPACITY := 200

signal contents_changed(changes: Dictionary)
signal capacity_changed(used: int, total: int)

var _items: Dictionary = {}
var _capacity_provider: Callable = Callable()
var _total_capacity := DEFAULT_CAPACITY


func configure(capacity_provider: Callable = Callable()) -> bool:
	var next_total := DEFAULT_CAPACITY
	if not capacity_provider.is_null():
		if not capacity_provider.is_valid():
			return false
		var provided: Variant = capacity_provider.call()
		if not _is_valid_capacity(provided):
			return false
		next_total = int(provided)
	_capacity_provider = capacity_provider
	_commit_capacity(next_total)
	return true


func get_count(item_id: String) -> int:
	return int(_items.get(item_id, 0))


func get_items() -> Dictionary:
	var snapshot := _items.duplicate(true)
	snapshot.make_read_only()
	return snapshot


func get_used_capacity() -> int:
	return _sum_quantities(_items)


func get_total_capacity() -> int:
	return _total_capacity


func get_missing_capacity(requested: Dictionary) -> int:
	var normalized_value: Variant = _normalize_items(requested, false)
	if normalized_value == null:
		return -1
	var requested_total := _sum_quantities(normalized_value as Dictionary)
	return maxi(get_used_capacity() + requested_total - _total_capacity, 0)


func can_add(requested: Dictionary) -> bool:
	return get_missing_capacity(requested) == 0


func add_items(requested: Dictionary) -> bool:
	var normalized_value: Variant = _normalize_items(requested, false)
	if normalized_value == null:
		return false
	var normalized := normalized_value as Dictionary
	if get_used_capacity() + _sum_quantities(normalized) > _total_capacity:
		return false
	var next_items := _items.duplicate(true)
	for item_id in normalized:
		next_items[item_id] = int(next_items.get(item_id, 0)) + int(normalized[item_id])
	_replace_items(next_items)
	return true


func can_remove(requested: Dictionary) -> bool:
	var normalized_value: Variant = _normalize_items(requested, false)
	if normalized_value == null:
		return false
	for item_id in normalized_value:
		if get_count(item_id) < int(normalized_value[item_id]):
			return false
	return true


func remove_items(requested: Dictionary) -> bool:
	var normalized_value: Variant = _normalize_items(requested, false)
	if normalized_value == null:
		return false
	var normalized := normalized_value as Dictionary
	for item_id in normalized:
		if get_count(item_id) < int(normalized[item_id]):
			return false
	var next_items := _items.duplicate(true)
	for item_id in normalized:
		var remaining := int(next_items[item_id]) - int(normalized[item_id])
		if remaining > 0:
			next_items[item_id] = remaining
		else:
			next_items.erase(item_id)
	_replace_items(next_items)
	return true


func to_dict() -> Dictionary:
	return {"items": _items.duplicate(true)}


func validate_dict(data: Dictionary) -> bool:
	if data.size() != 1 or not data.has("items") or not data.items is Dictionary:
		return false
	return _normalize_items(data.items as Dictionary, true) != null


func from_dict(data: Dictionary) -> bool:
	if not validate_dict(data):
		return false
	return restore_items_unchecked(data.items as Dictionary)


func restore_items_unchecked(items: Dictionary) -> bool:
	var normalized_value: Variant = _normalize_items(items, true)
	if normalized_value == null:
		return false
	_replace_items(normalized_value as Dictionary)
	return true


func refresh_capacity() -> void:
	if _capacity_provider.is_null() or not _capacity_provider.is_valid():
		return
	var provided: Variant = _capacity_provider.call()
	if not _is_valid_capacity(provided):
		return
	_commit_capacity(int(provided))


func _normalize_items(values: Dictionary, allow_empty: bool) -> Variant:
	if values.is_empty() and not allow_empty:
		return null
	var normalized: Dictionary = {}
	var total := 0
	for key in values:
		if typeof(key) != TYPE_STRING or (key as String).is_empty():
			return null
		var item_id := key as String
		var definition: Variant = GameDataScript.get_item(item_id)
		if not definition is Dictionary or (definition as Dictionary).get("category") != "crop":
			return null
		var value: Variant = values[key]
		if typeof(value) != TYPE_INT:
			return null
		var quantity := int(value)
		if quantity <= 0 or quantity > EconomyLimitsScript.MAX_SAFE_INTEGER:
			return null
		if quantity > EconomyLimitsScript.MAX_SAFE_INTEGER - total:
			return null
		total += quantity
		normalized[item_id] = quantity
	return normalized


func _replace_items(next_items: Dictionary) -> void:
	var previous_items := _items
	var previous_used := _sum_quantities(previous_items)
	var next_used := _sum_quantities(next_items)
	var changes := _changes_between(previous_items, next_items)
	_items = next_items.duplicate(true)
	if not changes.is_empty():
		contents_changed.emit(changes.duplicate(true))
		_emit_event(&"farm_storage_changed", [changes.duplicate(true)])
	if previous_used != next_used:
		_emit_capacity_changed(next_used, _total_capacity)


func _commit_capacity(next_total: int) -> void:
	if next_total == _total_capacity:
		return
	_total_capacity = next_total
	_emit_capacity_changed(get_used_capacity(), _total_capacity)


func _emit_capacity_changed(used: int, total: int) -> void:
	capacity_changed.emit(used, total)
	_emit_event(&"farm_storage_capacity_changed", [used, total])


func _emit_event(signal_name: StringName, arguments: Array) -> void:
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus != null and event_bus.has_signal(signal_name):
		event_bus.callv("emit_signal", [signal_name] + arguments)


static func _changes_between(previous: Dictionary, current: Dictionary) -> Dictionary:
	var changes: Dictionary = {}
	for item_id in previous:
		var delta := int(current.get(item_id, 0)) - int(previous[item_id])
		if delta != 0:
			changes[item_id] = delta
	for item_id in current:
		if previous.has(item_id):
			continue
		changes[item_id] = int(current[item_id])
	return changes


static func _sum_quantities(values: Dictionary) -> int:
	var total := 0
	for quantity in values.values():
		total += int(quantity)
	return total


static func _is_valid_capacity(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_INT
		and int(value) >= 0
		and int(value) <= EconomyLimitsScript.MAX_SAFE_INTEGER
	)
