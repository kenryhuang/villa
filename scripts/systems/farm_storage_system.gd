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
var _notification_queue: Array[Dictionary] = []
var _is_dispatching_notifications := false
var _transaction_owner: WeakRef
var _transaction_items: Dictionary = {}
var _transaction_capacity := DEFAULT_CAPACITY
var _sealed_publication_owner: WeakRef
var _sealed_before_items: Dictionary = {}
var _sealed_before_capacity := DEFAULT_CAPACITY
var _sealed_batch_marker: RefCounted
var _sealed_armed := false
var _notification_dispatch_suspended := false


func configure(capacity_provider: Callable = Callable()) -> bool:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	if _has_atomic_transaction() or _has_sealed_transaction():
		return false
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


func begin_atomic_transaction() -> RefCounted:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	if _has_atomic_transaction() or _has_sealed_transaction():
		return null
	var token := RefCounted.new()
	_transaction_owner = weakref(token)
	_transaction_items = _items.duplicate(true)
	_transaction_capacity = _total_capacity
	call_deferred("_recover_abandoned_transaction")
	return token


func commit_atomic_transaction(token: Variant) -> bool:
	if not _owns_atomic_transaction(token):
		return false
	var publication := seal_atomic_transaction(token)
	if publication == null:
		return false
	publish_sealed_transaction(publication)
	return true


func seal_atomic_transaction(token: Variant) -> RefCounted:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	if not _owns_atomic_transaction(token) or _has_sealed_transaction():
		return null
	var previous_items := _transaction_items.duplicate(true)
	var previous_capacity := _transaction_capacity
	var previous_used := _sum_quantities(previous_items)
	var current_used := get_used_capacity()
	var changes := _changes_between(previous_items, _items)
	var publication := RefCounted.new()
	var marker := RefCounted.new()
	_sealed_publication_owner = weakref(publication)
	_sealed_before_items = previous_items
	_sealed_before_capacity = previous_capacity
	_sealed_batch_marker = marker
	_notification_dispatch_suspended = true
	_transaction_owner = null
	_transaction_items.clear()
	_transaction_capacity = _total_capacity
	_sealed_armed = false
	var batch := _make_notification_batch(
		changes,
		previous_used != current_used or previous_capacity != _total_capacity,
		current_used,
		_total_capacity
	)
	if not batch.is_empty():
		batch["sealed_marker"] = marker
		_notification_queue.append(batch)
	call_deferred("_recover_abandoned_seal")
	return publication


func publish_sealed_transaction(publication: Variant) -> void:
	if not owns_sealed_transaction(publication):
		push_error("Invalid storage publication ownership")
		return
	if not _sealed_armed:
		arm_sealed_transaction(publication)
	_publish_sealed_transaction()


func can_arm_sealed_transaction(publication: Variant) -> bool:
	return owns_sealed_transaction(publication) and not _sealed_armed


func arm_sealed_transaction(publication: Variant) -> void:
	if not _is_sealed_transaction_owner(publication):
		push_error("Invalid storage publication ownership at commit point")
		return
	_sealed_armed = true


func _publish_sealed_transaction() -> void:
	_clear_sealed_transaction()
	_notification_dispatch_suspended = false
	_drain_notification_queue()


func owns_sealed_transaction(publication: Variant) -> bool:
	_recover_abandoned_seal()
	return (
		publication is RefCounted
		and _sealed_publication_owner != null
		and _sealed_publication_owner.get_ref() == publication
	)


func cancel_sealed_transaction(publication: Variant) -> bool:
	if not owns_sealed_transaction(publication) or _sealed_armed:
		return false
	_cancel_sealed_transaction()
	return true


func rollback_sealed_transaction(publication: Variant) -> bool:
	return cancel_sealed_transaction(publication)


func _cancel_sealed_transaction() -> void:
	_items = _sealed_before_items.duplicate(true)
	_total_capacity = _sealed_before_capacity
	_remove_sealed_notification_batch()
	_clear_sealed_transaction()
	_notification_dispatch_suspended = false
	_drain_notification_queue()


func rollback_atomic_transaction(token: Variant) -> bool:
	_recover_abandoned_transaction()
	if not _owns_atomic_transaction(token):
		return false
	_items = _transaction_items.duplicate(true)
	_total_capacity = _transaction_capacity
	_transaction_owner = null
	_transaction_items.clear()
	_transaction_capacity = _total_capacity
	return true


func add_items(requested: Dictionary) -> bool:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	if _has_atomic_transaction() or _has_sealed_transaction():
		return false
	return _add_items(requested)


func stage_add_items(token: Variant, requested: Dictionary) -> bool:
	if not _owns_atomic_transaction(token):
		return false
	return _add_items(requested)


func _add_items(requested: Dictionary) -> bool:
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
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	if _has_atomic_transaction() or _has_sealed_transaction():
		return false
	return _remove_items(requested)


func stage_remove_items(token: Variant, requested: Dictionary) -> bool:
	if not _owns_atomic_transaction(token):
		return false
	return _remove_items(requested)


func _remove_items(requested: Dictionary) -> bool:
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


## Bypasses capacity enforcement only; crop IDs and quantities are still fully validated.
func restore_items_unchecked(items: Dictionary) -> bool:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	if _has_atomic_transaction() or _has_sealed_transaction():
		return false
	var normalized_value: Variant = _normalize_items(items, true)
	if normalized_value == null:
		return false
	_replace_items(normalized_value as Dictionary)
	return true


func refresh_capacity() -> void:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	if _has_atomic_transaction() or _has_sealed_transaction():
		return
	_refresh_capacity()


func stage_refresh_capacity(token: Variant) -> bool:
	if not _owns_atomic_transaction(token):
		return false
	return _refresh_capacity()


func _refresh_capacity() -> bool:
	if _capacity_provider.is_null() or not _capacity_provider.is_valid():
		return false
	var provided: Variant = _capacity_provider.call()
	if not _is_valid_capacity(provided):
		return false
	_commit_capacity(int(provided))
	return true


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
	if _has_atomic_transaction():
		return
	_queue_notification_batch(changes, previous_used != next_used, next_used, _total_capacity)


func _commit_capacity(next_total: int) -> void:
	if next_total == _total_capacity:
		return
	_total_capacity = next_total
	if _has_atomic_transaction():
		return
	_queue_notification_batch({}, true, get_used_capacity(), _total_capacity)


func _queue_notification_batch(
	changes: Dictionary,
	did_capacity_change: bool,
	used: int,
	total: int
) -> void:
	var batch := _make_notification_batch(changes, did_capacity_change, used, total)
	if batch.is_empty():
		return
	_notification_queue.append(batch)
	_drain_notification_queue()


func _make_notification_batch(
	changes: Dictionary,
	did_capacity_change: bool,
	used: int,
	total: int
) -> Dictionary:
	if changes.is_empty() and not did_capacity_change:
		return {}
	var change_snapshot := changes.duplicate(true)
	change_snapshot.make_read_only()
	return {
		"changes": change_snapshot,
		"capacity_changed": did_capacity_change,
		"used": used,
		"total": total,
	}


func _drain_notification_queue() -> void:
	if _is_dispatching_notifications or _notification_dispatch_suspended:
		return
	_is_dispatching_notifications = true
	while not _notification_queue.is_empty() and not _notification_dispatch_suspended:
		_dispatch_notification_batch(_notification_queue.pop_front())
	_is_dispatching_notifications = false


func _remove_sealed_notification_batch() -> void:
	if _sealed_batch_marker == null:
		return
	for index in range(_notification_queue.size()):
		if _notification_queue[index].get("sealed_marker") == _sealed_batch_marker:
			_notification_queue.remove_at(index)
			return


func _clear_sealed_transaction() -> void:
	_sealed_publication_owner = null
	_sealed_before_items.clear()
	_sealed_before_capacity = _total_capacity
	_sealed_batch_marker = null
	_sealed_armed = false


func _has_sealed_transaction() -> bool:
	return _sealed_publication_owner != null and _sealed_publication_owner.get_ref() != null


func _recover_abandoned_seal() -> void:
	if _sealed_publication_owner != null and _sealed_publication_owner.get_ref() == null:
		if _sealed_armed:
			_publish_sealed_transaction()
		else:
			_cancel_sealed_transaction()


func _has_atomic_transaction() -> bool:
	return _transaction_owner != null and _transaction_owner.get_ref() != null


func _owns_atomic_transaction(token: Variant) -> bool:
	return (
		token is RefCounted
		and _transaction_owner != null
		and _transaction_owner.get_ref() == token
	)


func _recover_abandoned_transaction() -> void:
	if _transaction_owner == null or _transaction_owner.get_ref() != null:
		return
	_items = _transaction_items.duplicate(true)
	_total_capacity = _transaction_capacity
	_transaction_owner = null
	_transaction_items.clear()
	_transaction_capacity = _total_capacity


func _is_sealed_transaction_owner(publication: Variant) -> bool:
	return (
		publication is RefCounted
		and _sealed_publication_owner != null
		and _sealed_publication_owner.get_ref() == publication
	)


func _dispatch_notification_batch(batch: Dictionary) -> void:
	var changes: Dictionary = batch.changes
	if not changes.is_empty():
		contents_changed.emit(changes)
		_emit_event(&"farm_storage_changed", [changes])
	if bool(batch.capacity_changed):
		var used := int(batch.used)
		var total := int(batch.total)
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
