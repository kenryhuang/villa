class_name ItemContainerRouter
extends Node

const GameDataScript = preload("res://scripts/core/game_data.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")
const FinalizedPublicationBatchScript = preload("res://scripts/shared/finalized_publication_batch.gd")

const INVENTORY_KIND := &"inventory"
const STORAGE_KIND := &"farm_storage"
const UNKNOWN_KIND := &"unknown"

var _inventory: InventorySystem
var _storage: FarmStorageSystem

var _transaction_owner: WeakRef
var _transaction_inventory_snapshot: Dictionary = {}
var _transaction_storage_snapshot: Dictionary = {}
var _transaction_storage_token: RefCounted

var _sealed_owner: WeakRef
var _sealed_inventory_snapshot: Dictionary = {}
var _sealed_storage_snapshot: Dictionary = {}
var _sealed_storage_publication: RefCounted
var _sealed_armed := false
var _publication_in_progress := false
var _tearing_down := false


func _init() -> void:
	set_process(false)


func _enter_tree() -> void:
	_tearing_down = false
	_update_process_monitor()


func _ready() -> void:
	_update_process_monitor()


func _process(_delta: float) -> void:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	_update_process_monitor()


func _exit_tree() -> void:
	_tearing_down = true
	set_process(false)
	if _has_atomic_state():
		_rollback_active_transaction()
	if _has_sealed_state():
		if _sealed_armed:
			_publish_sealed_transaction()
		else:
			_cancel_sealed_transaction()


func configure(inventory: InventorySystem, storage: FarmStorageSystem) -> bool:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	if _publication_in_progress or _has_atomic_state() or _has_sealed_state():
		return false
	if not is_instance_valid(inventory) or not is_instance_valid(storage):
		return false
	_inventory = inventory
	_storage = storage
	return true


func is_configured_with(inventory: InventorySystem, storage: FarmStorageSystem) -> bool:
	return _is_configured() and _inventory == inventory and _storage == storage


func container_kind(item_id: String) -> StringName:
	var definition: Variant = GameDataScript.get_item(item_id)
	if not definition is Dictionary:
		return UNKNOWN_KIND
	return STORAGE_KIND if (definition as Dictionary).get("category") == "crop" else INVENTORY_KIND


func get_count(item_id: String) -> int:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	if not _is_configured():
		return 0
	match container_kind(item_id):
		INVENTORY_KIND:
			return _inventory.get_item_count(item_id)
		STORAGE_KIND:
			return _storage.get_count(item_id)
	return 0


func can_add(items: Dictionary) -> Dictionary:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	var prepared := _prepare(items)
	if not bool(prepared.get("ok", false)):
		return prepared
	return _preflight_add(prepared)


func add_items(items: Dictionary) -> bool:
	var token := begin_atomic_transaction()
	if token == null:
		return false
	if not stage_add_items(token, items):
		rollback_atomic_transaction(token)
		return false
	return commit_atomic_transaction(token)


func can_remove(items: Dictionary) -> Dictionary:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	var prepared := _prepare(items)
	if not bool(prepared.get("ok", false)):
		return prepared
	return _preflight_remove(prepared)


func remove_items(items: Dictionary) -> bool:
	var token := begin_atomic_transaction()
	if token == null:
		return false
	if not stage_remove_items(token, items):
		rollback_atomic_transaction(token)
		return false
	return commit_atomic_transaction(token)


func begin_atomic_transaction() -> RefCounted:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	if not _is_configured() or _publication_in_progress or _has_atomic_state() or _has_sealed_state():
		return null
	var inventory_snapshot := _inventory_state()
	var storage_snapshot := _storage.get_items().duplicate(true)
	if not _inventory.begin_restore_notification_transaction():
		return null
	var storage_token := _storage.begin_atomic_transaction()
	if storage_token == null:
		_inventory.end_restore_notification_transaction(false)
		return null
	var token := RefCounted.new()
	_transaction_owner = weakref(token)
	_transaction_inventory_snapshot = inventory_snapshot
	_transaction_storage_snapshot = storage_snapshot
	_transaction_storage_token = storage_token
	_update_process_monitor()
	return token


func stage_add_items(token: Variant, items: Dictionary) -> bool:
	return _stage_items(token, items, true)


func stage_remove_items(token: Variant, items: Dictionary) -> bool:
	return _stage_items(token, items, false)


func commit_atomic_transaction(token: Variant) -> bool:
	var publication := seal_atomic_transaction(token)
	if publication == null:
		return false
	if not arm_sealed_transaction(publication):
		cancel_sealed_transaction(publication)
		return false
	return publish_sealed_transaction(publication)


func seal_atomic_transaction(token: Variant) -> RefCounted:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	if not _owns_atomic_transaction(token) or _has_sealed_state() or _publication_in_progress:
		return null
	var storage_publication := _storage.seal_atomic_transaction(_transaction_storage_token)
	if storage_publication == null:
		_rollback_active_transaction()
		return null
	var publication := RefCounted.new()
	_sealed_owner = weakref(publication)
	_sealed_inventory_snapshot = _transaction_inventory_snapshot
	_sealed_storage_snapshot = _transaction_storage_snapshot
	_sealed_storage_publication = storage_publication
	_sealed_armed = false
	_clear_transaction_state()
	_update_process_monitor()
	return publication


func can_arm_sealed_transaction(publication: Variant) -> bool:
	_recover_abandoned_seal()
	return (
		_owns_sealed_transaction(publication)
		and not _sealed_armed
		and is_instance_valid(_storage)
		and _storage.can_arm_sealed_transaction(_sealed_storage_publication)
	)


func arm_sealed_transaction(publication: Variant) -> bool:
	if not can_arm_sealed_transaction(publication):
		return false
	_storage.arm_sealed_transaction(_sealed_storage_publication)
	_sealed_armed = true
	return true


func can_publish_sealed_transaction(
	publication: Variant,
	allow_blocked_event_bus: bool = false
) -> bool:
	_recover_abandoned_seal()
	if _publication_in_progress or not _owns_sealed_transaction(publication):
		return false
	if not _sealed_armed and not can_arm_sealed_transaction(publication):
		return false
	var event_bus := _event_bus()
	return (
		allow_blocked_event_bus
		or not is_instance_valid(event_bus)
		or not event_bus.is_blocking_signals()
	)


func publish_sealed_transaction(publication: Variant) -> bool:
	_recover_abandoned_seal()
	if not can_publish_sealed_transaction(publication):
		return false
	if not _sealed_armed and not arm_sealed_transaction(publication):
		return false
	var batch := finalize_sealed_publication(publication)
	return dispatch_finalized_publication(batch)


func finalize_sealed_publication(publication: Variant) -> RefCounted:
	_recover_abandoned_seal()
	if _publication_in_progress or not _owns_sealed_transaction(publication):
		return null
	return _finalize_sealed_publication()


func dispatch_finalized_publication(batch: Variant) -> bool:
	return (
		batch is RefCounted
		and batch.get_script() == FinalizedPublicationBatchScript
		and bool(batch.call("is_from", self))
		and bool(batch.call("dispatch"))
	)


func cancel_sealed_transaction(publication: Variant) -> bool:
	_recover_abandoned_seal()
	if not _owns_sealed_transaction(publication) or _sealed_armed:
		return false
	return _cancel_sealed_transaction()


func rollback_atomic_transaction(token: Variant) -> bool:
	if _owns_atomic_transaction(token):
		return _rollback_active_transaction()
	_recover_abandoned_transaction()
	return false


func owns_atomic_transaction(token: Variant) -> bool:
	_recover_abandoned_transaction()
	return _owns_atomic_transaction(token)


func owns_sealed_transaction(publication: Variant) -> bool:
	_recover_abandoned_seal()
	return _owns_sealed_transaction(publication)


func snapshot_for(items: Dictionary) -> Dictionary:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	var prepared := _prepare(items)
	if not bool(prepared.get("ok", false)):
		return {}
	return _freeze_variant(_snapshot_prepared(prepared)) as Dictionary


func snapshot_matches(snapshot: Dictionary) -> bool:
	var normalized: Variant = _normalize_snapshot(snapshot)
	if not normalized is Dictionary:
		return false
	var expected := normalized as Dictionary
	if expected.has(INVENTORY_KIND) and _inventory_state() != expected[INVENTORY_KIND]:
		return false
	if (
		expected.has(STORAGE_KIND)
		and _storage.get_items() != (expected[STORAGE_KIND] as Dictionary).items
	):
		return false
	return true


func restore_snapshot(snapshot: Dictionary) -> bool:
	_recover_abandoned_transaction()
	_recover_abandoned_seal()
	if not _is_configured() or _publication_in_progress or _has_atomic_state() or _has_sealed_state():
		return false
	var normalized_value: Variant = _normalize_snapshot(snapshot)
	if normalized_value == null:
		return false
	var normalized := normalized_value as Dictionary
	var inventory_state: Variant = normalized.get(INVENTORY_KIND)
	var storage_state: Variant = normalized.get(STORAGE_KIND)
	var inventory_transaction := false
	var storage_transaction := false
	if inventory_state != null:
		inventory_transaction = _inventory.begin_restore_notification_transaction()
		if not inventory_transaction:
			return false
	if storage_state != null:
		storage_transaction = _storage.begin_restore_notification_transaction()
		if not storage_transaction:
			if inventory_transaction:
				_inventory.end_restore_notification_transaction(false)
			return false
	var event_bus := _event_bus()
	var event_bus_was_blocked := is_instance_valid(event_bus) and event_bus.is_blocking_signals()
	if is_instance_valid(event_bus) and not event_bus_was_blocked:
		event_bus.set_block_signals(true)

	var restored := true
	if storage_state != null:
		restored = _storage.restore_items_unchecked(storage_state.items)
	if restored and inventory_state != null:
		_inventory.restore_state(inventory_state.slots, inventory_state.quick_mappings)
	if inventory_transaction:
		_inventory.end_restore_notification_transaction(false)
	if storage_transaction:
		_storage.end_restore_notification_transaction(false)
	_restore_event_bus(event_bus, event_bus_was_blocked)
	return restored


func _stage_items(token: Variant, items: Dictionary, is_add: bool) -> bool:
	_recover_abandoned_transaction()
	if not _owns_atomic_transaction(token):
		return false
	var prepared := _prepare(items)
	if not bool(prepared.get("ok", false)):
		return false
	var preflight := _preflight_add(prepared) if is_add else _preflight_remove(prepared)
	if not bool(preflight.get("ok", false)):
		return false
	var before_inventory := _inventory_state()
	var before_storage := _storage.get_items().duplicate(true)
	var event_bus := _event_bus()
	var event_bus_was_blocked := is_instance_valid(event_bus) and event_bus.is_blocking_signals()
	if is_instance_valid(event_bus) and not event_bus_was_blocked:
		event_bus.set_block_signals(true)
	var succeeded := _mutate_inventory(prepared.inventory, is_add)
	if succeeded and not (prepared.storage as Dictionary).is_empty():
		succeeded = (
			_storage.stage_add_items(_transaction_storage_token, prepared.storage)
			if is_add
			else _storage.stage_remove_items(_transaction_storage_token, prepared.storage)
		)
	if succeeded:
		_restore_event_bus(event_bus, event_bus_was_blocked)
		return true
	_restore_active_stage(before_inventory, before_storage)
	_restore_event_bus(event_bus, event_bus_was_blocked)
	return false


func _prepare(items: Dictionary) -> Dictionary:
	if not _is_configured():
		return _failure("not_configured")
	if items.is_empty():
		return _failure("invalid_request")
	var normalized: Dictionary = {}
	var inventory_items: Dictionary = {}
	var storage_items: Dictionary = {}
	var categories: Dictionary = {}
	var item_ids: Array[String] = []
	for item_id_value in items:
		if typeof(item_id_value) != TYPE_STRING or (item_id_value as String).is_empty():
			return _failure("invalid_request")
		var item_id := item_id_value as String
		var quantity: Variant = items[item_id_value]
		if typeof(quantity) != TYPE_INT or int(quantity) <= 0 or int(quantity) > EconomyLimitsScript.MAX_SAFE_INTEGER:
			return _failure("invalid_request", item_id)
		var definition: Variant = GameDataScript.get_item(item_id)
		if not definition is Dictionary:
			return _failure("unknown_item", item_id)
		var category := str((definition as Dictionary).get("category", ""))
		normalized[item_id] = int(quantity)
		categories[item_id] = category
		item_ids.append(item_id)
		if category == "crop":
			storage_items[item_id] = int(quantity)
		else:
			inventory_items[item_id] = int(quantity)
	item_ids.sort()
	return {
		"ok": true,
		"reason": "",
		"normalized": normalized,
		"inventory": inventory_items,
		"storage": storage_items,
		"categories": categories,
		"item_ids": item_ids,
	}


func _preflight_add(prepared: Dictionary) -> Dictionary:
	var inventory_items: Dictionary = prepared.inventory
	if not inventory_items.is_empty():
		var inventory_result: Dictionary = _inventory.preflight_add_items(inventory_items)
		if not bool(inventory_result.get("ok", false)):
			var missing: Variant = inventory_result.get("missing", {})
			var failed_item := (
				_first_item_id(missing as Dictionary)
				if missing is Dictionary and not (missing as Dictionary).is_empty()
				else _first_item_id(inventory_items)
			)
			inventory_result["ok"] = false
			inventory_result["reason"] = "inventory_capacity"
			inventory_result["item_id"] = failed_item
			return inventory_result
	var storage_items: Dictionary = prepared.storage
	if not storage_items.is_empty():
		var missing_capacity := _storage.get_missing_capacity(storage_items)
		if missing_capacity < 0:
			return _failure("invalid_request", _first_item_id(storage_items))
		if missing_capacity > 0:
			return {
				"ok": false,
				"reason": "storage_capacity",
				"missing_capacity": missing_capacity,
				"item_id": _first_item_id(storage_items),
			}
	return {"ok": true, "reason": ""}


func _preflight_remove(prepared: Dictionary) -> Dictionary:
	for item_id in prepared.item_ids:
		var requested := int(prepared.normalized[item_id])
		var category := str(prepared.categories[item_id])
		var available := _storage.get_count(item_id) if category == "crop" else _inventory.get_item_count(item_id)
		if available >= requested:
			continue
		var reason := "insufficient_resources"
		if category == "seed":
			reason = "insufficient_seed"
		elif category == "crop":
			reason = "insufficient_crop"
		return {
			"ok": false,
			"reason": reason,
			"item_id": item_id,
			"requested_quantity": requested,
			"available_quantity": available,
			"missing_quantity": requested - available,
		}
	return {"ok": true, "reason": ""}


func _mutate_inventory(items: Dictionary, is_add: bool) -> bool:
	var item_ids: Array[String] = []
	for item_id_value in items:
		item_ids.append(str(item_id_value))
	item_ids.sort()
	for item_id in item_ids:
		var succeeded := _inventory.add_item(item_id, int(items[item_id])) if is_add else _inventory.remove_item(item_id, int(items[item_id]))
		if not succeeded:
			return false
	return true


func _restore_active_stage(inventory_state: Dictionary, storage_items: Dictionary) -> bool:
	_inventory.restore_state(inventory_state.slots, inventory_state.quick_mappings)
	if not _storage.rollback_atomic_transaction(_transaction_storage_token):
		_rollback_active_transaction()
		return false
	if not _storage.begin_restore_notification_transaction():
		_rollback_active_transaction()
		return false
	var restored := _storage.restore_items_unchecked(storage_items)
	_storage.end_restore_notification_transaction(false)
	if not restored:
		_rollback_active_transaction()
		return false
	_transaction_storage_token = _storage.begin_atomic_transaction()
	if _transaction_storage_token == null:
		_rollback_active_transaction()
		return false
	return true


func _rollback_active_transaction() -> bool:
	if not _has_atomic_state():
		return false
	var event_bus := _event_bus()
	var event_bus_was_blocked := is_instance_valid(event_bus) and event_bus.is_blocking_signals()
	if is_instance_valid(event_bus) and not event_bus_was_blocked:
		event_bus.set_block_signals(true)
	var storage_restored := true
	if is_instance_valid(_storage):
		storage_restored = _storage.rollback_atomic_transaction(_transaction_storage_token)
		if storage_restored:
			storage_restored = _restore_storage_silently(_transaction_storage_snapshot)
	if is_instance_valid(_inventory):
		_inventory.restore_state(
			_transaction_inventory_snapshot.slots,
			_transaction_inventory_snapshot.quick_mappings
		)
		_inventory.end_restore_notification_transaction(false)
	_restore_event_bus(event_bus, event_bus_was_blocked)
	_clear_transaction_state()
	return storage_restored


func _finalize_sealed_publication() -> RefCounted:
	if not _has_sealed_state() or _publication_in_progress:
		return null
	var inventory := _inventory if is_instance_valid(_inventory) else null
	var storage := _storage if is_instance_valid(_storage) else null
	var inventory_snapshot := _sealed_inventory_snapshot
	var storage_publication := _sealed_storage_publication
	var storage_batch: RefCounted
	if is_instance_valid(storage):
		storage_batch = storage.finalize_sealed_publication(storage_publication)
		if storage_batch == null:
			return null
	_publication_in_progress = true
	_clear_sealed_state()
	var inventory_publication: Dictionary = _freeze_variant({"item_events": [], "quick_events": []})
	if is_instance_valid(inventory):
		var final_inventory := {
			"slots": inventory.slots.duplicate(true),
			"quick_mappings": inventory.quick_slot_mappings.duplicate(),
		}
		inventory.end_restore_notification_transaction(false)
		inventory_publication = _prepare_inventory_publication(inventory_snapshot, final_inventory)
	_publication_in_progress = false
	_update_process_monitor()
	var event_bus := _event_bus()
	var actions: Array[Dictionary] = []
	for event_value in inventory_publication.item_events:
		var event := event_value as Dictionary
		actions.append({
			"event_bus": event_bus,
			"bus_signal": event.signal,
			"arguments": [event.item_id, event.quantity],
		})
	for event_value in inventory_publication.quick_events:
		var event := event_value as Dictionary
		actions.append({
			"local_target": inventory,
			"local_signal": &"quick_slot_mapping_changed",
			"arguments": [event.quick_index, event.item_id],
		})
	var children: Array = []
	if storage_batch is RefCounted and storage_batch.get_script() == FinalizedPublicationBatchScript:
		children.append(storage_batch)
	return FinalizedPublicationBatchScript.new(
		self,
		actions,
		children,
		Callable(self, "_begin_finalized_dispatch"),
		Callable(self, "_end_finalized_dispatch")
	)


func _publish_sealed_transaction() -> bool:
	var batch := _finalize_sealed_publication()
	return batch != null and FinalizedPublicationBatchScript.dispatch_all([batch])


func _cancel_sealed_transaction() -> bool:
	if not _has_sealed_state():
		return false
	var event_bus := _event_bus()
	var event_bus_was_blocked := is_instance_valid(event_bus) and event_bus.is_blocking_signals()
	if is_instance_valid(event_bus) and not event_bus_was_blocked:
		event_bus.set_block_signals(true)
	var storage_cancelled := true
	if is_instance_valid(_storage):
		storage_cancelled = _storage.cancel_sealed_transaction(_sealed_storage_publication)
	if not storage_cancelled:
		_restore_event_bus(event_bus, event_bus_was_blocked)
		return false
	var storage_restored := true
	if is_instance_valid(_storage):
		storage_restored = _restore_storage_silently(_sealed_storage_snapshot)
	if is_instance_valid(_inventory):
		_inventory.restore_state(
			_sealed_inventory_snapshot.slots,
			_sealed_inventory_snapshot.quick_mappings
		)
		_inventory.end_restore_notification_transaction(false)
	_restore_event_bus(event_bus, event_bus_was_blocked)
	_clear_sealed_state()
	return storage_restored


func _restore_storage_silently(items: Dictionary) -> bool:
	if not is_instance_valid(_storage):
		return true
	if not _storage.begin_restore_notification_transaction():
		return false
	var restored := _storage.restore_items_unchecked(items)
	_storage.end_restore_notification_transaction(false)
	return restored


func _prepare_inventory_publication(
	previous: Dictionary,
	current: Dictionary
) -> Dictionary:
	var item_events: Array[Dictionary] = []
	var previous_counts := _inventory_counts(previous.slots)
	var current_counts := _inventory_counts(current.slots)
	var item_ids: Array[String] = []
	for item_id_value in previous_counts:
		item_ids.append(str(item_id_value))
	for item_id_value in current_counts:
		var item_id := str(item_id_value)
		if not item_ids.has(item_id):
			item_ids.append(item_id)
	item_ids.sort()
	for item_id in item_ids:
		var delta := int(current_counts.get(item_id, 0)) - int(previous_counts.get(item_id, 0))
		if delta > 0:
			item_events.append({"signal": &"item_added", "item_id": item_id, "quantity": delta})
		elif delta < 0:
			item_events.append({"signal": &"item_removed", "item_id": item_id, "quantity": -delta})
	var previous_quick := _quick_items(previous)
	var current_quick := _quick_items(current)
	var quick_events: Array[Dictionary] = []
	for quick_index in range(InventorySystem.QUICK_SLOT_COUNT):
		if previous_quick[quick_index] != current_quick[quick_index]:
			quick_events.append({"quick_index": quick_index, "item_id": current_quick[quick_index]})
	return _freeze_variant({"item_events": item_events, "quick_events": quick_events})


func _begin_finalized_dispatch() -> void:
	_publication_in_progress = true


func _end_finalized_dispatch() -> void:
	_publication_in_progress = false


func _inventory_counts(slots: Array) -> Dictionary:
	var counts: Dictionary = {}
	for slot_value in slots:
		if not slot_value is Dictionary or (slot_value as Dictionary).is_empty():
			continue
		var slot := slot_value as Dictionary
		var item_id := str(slot.get("item_id", ""))
		if not item_id.is_empty():
			counts[item_id] = int(counts.get(item_id, 0)) + int(slot.get("quantity", 0))
	return counts


func _quick_items(state: Dictionary) -> Array[String]:
	var items: Array[String] = []
	for quick_index in range(InventorySystem.QUICK_SLOT_COUNT):
		var slot_index := int(state.quick_mappings[quick_index])
		var item_id := ""
		if slot_index >= 0 and slot_index < state.slots.size():
			item_id = str(state.slots[slot_index].get("item_id", ""))
		items.append(item_id)
	return items


func _snapshot_prepared(prepared: Dictionary) -> Dictionary:
	var snapshot: Dictionary = {}
	if not (prepared.inventory as Dictionary).is_empty():
		snapshot[INVENTORY_KIND] = _inventory_state()
	if not (prepared.storage as Dictionary).is_empty():
		snapshot[STORAGE_KIND] = {"items": _storage.get_items().duplicate(true)}
	return snapshot


func _normalize_snapshot(snapshot: Dictionary) -> Variant:
	if snapshot.is_empty() or snapshot.size() > 2:
		return null
	var normalized: Dictionary = {}
	for key in snapshot:
		var kind := StringName(str(key))
		if kind != INVENTORY_KIND and kind != STORAGE_KIND or normalized.has(kind):
			return null
		var value: Variant = snapshot[key]
		if kind == INVENTORY_KIND:
			if not value is Dictionary:
				return null
			var state := value as Dictionary
			if state.size() != 2 or not state.has("slots") or not state.has("quick_mappings"):
				return null
			var inventory_normalized: Variant = _inventory.normalize_saved_state(state.slots, state.quick_mappings)
			if not inventory_normalized is Dictionary:
				return null
			normalized[kind] = (inventory_normalized as Dictionary).duplicate(true)
		else:
			if not value is Dictionary or not _storage.validate_dict(value as Dictionary):
				return null
			normalized[kind] = {"items": (value as Dictionary).items.duplicate(true)}
	return normalized


func _inventory_state() -> Dictionary:
	return {
		"slots": _inventory.slots.duplicate(true),
		"quick_mappings": _inventory.quick_slot_mappings.duplicate(),
	}


func _freeze_variant(value: Variant) -> Variant:
	if value is Dictionary:
		var dictionary := value as Dictionary
		for key in dictionary.keys():
			dictionary[key] = _freeze_variant(dictionary[key])
		dictionary.make_read_only()
		return dictionary
	if value is Array:
		var array := value as Array
		for index in range(array.size()):
			array[index] = _freeze_variant(array[index])
		array.make_read_only()
		return array
	return value


func _is_configured() -> bool:
	return is_instance_valid(_inventory) and is_instance_valid(_storage)


func _has_atomic_state() -> bool:
	return _transaction_storage_token != null or not _transaction_inventory_snapshot.is_empty()


func _owns_atomic_transaction(token: Variant) -> bool:
	return token is RefCounted and _transaction_owner != null and _transaction_owner.get_ref() == token


func _has_sealed_state() -> bool:
	return _sealed_storage_publication != null or not _sealed_inventory_snapshot.is_empty()


func _owns_sealed_transaction(publication: Variant) -> bool:
	return publication is RefCounted and _sealed_owner != null and _sealed_owner.get_ref() == publication


func _recover_abandoned_transaction() -> void:
	if not _has_atomic_state():
		return
	if (
		_transaction_owner == null
		or _transaction_owner.get_ref() == null
		or not _is_configured()
	):
		_rollback_active_transaction()


func _recover_abandoned_seal() -> void:
	if not _has_sealed_state():
		return
	var abandoned := _sealed_owner == null or _sealed_owner.get_ref() == null
	if not abandoned and _is_configured():
		return
	if _sealed_armed:
		_publish_sealed_transaction()
	else:
		_cancel_sealed_transaction()


func _clear_transaction_state() -> void:
	_transaction_owner = null
	_transaction_inventory_snapshot = {}
	_transaction_storage_snapshot = {}
	_transaction_storage_token = null
	_update_process_monitor()


func _clear_sealed_state() -> void:
	_sealed_owner = null
	_sealed_inventory_snapshot = {}
	_sealed_storage_snapshot = {}
	_sealed_storage_publication = null
	_sealed_armed = false
	_update_process_monitor()


func _update_process_monitor() -> void:
	if _tearing_down or not is_inside_tree():
		return
	set_process(_has_atomic_state() or _has_sealed_state())


func _event_bus() -> Node:
	return (
		_inventory.get_node_or_null("/root/EventBus")
		if is_instance_valid(_inventory) and _inventory.is_inside_tree()
		else null
	)


func _restore_event_bus(event_bus: Node, was_blocked: bool) -> void:
	if is_instance_valid(event_bus) and not was_blocked:
		event_bus.set_block_signals(false)


func _first_item_id(items: Dictionary) -> String:
	var item_ids: Array[String] = []
	for item_id_value in items:
		item_ids.append(str(item_id_value))
	item_ids.sort()
	return item_ids[0] if not item_ids.is_empty() else ""


func _failure(reason: String, item_id: String = "") -> Dictionary:
	var result := {"ok": false, "reason": reason}
	if not item_id.is_empty():
		result["item_id"] = item_id
	return result
