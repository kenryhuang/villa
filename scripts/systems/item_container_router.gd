class_name ItemContainerRouter
extends Node

const GameDataScript = preload("res://scripts/core/game_data.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")

const INVENTORY_KIND := &"inventory"
const STORAGE_KIND := &"farm_storage"
const UNKNOWN_KIND := &"unknown"

var _inventory: InventorySystem
var _storage: FarmStorageSystem


func configure(inventory: InventorySystem, storage: FarmStorageSystem) -> bool:
	if inventory == null or storage == null:
		return false
	_inventory = inventory
	_storage = storage
	return true


func container_kind(item_id: String) -> StringName:
	var definition: Variant = GameDataScript.get_item(item_id)
	if not definition is Dictionary:
		return UNKNOWN_KIND
	return STORAGE_KIND if (definition as Dictionary).get("category") == "crop" else INVENTORY_KIND


func get_count(item_id: String) -> int:
	match container_kind(item_id):
		INVENTORY_KIND:
			return _inventory.get_item_count(item_id) if _inventory != null else 0
		STORAGE_KIND:
			return _storage.get_count(item_id) if _storage != null else 0
	return 0


func can_add(items: Dictionary) -> Dictionary:
	var prepared := _prepare(items)
	if not bool(prepared.get("ok", false)):
		return prepared
	return _preflight_add(prepared)


func add_items(items: Dictionary) -> bool:
	var prepared := _prepare(items)
	if not bool(prepared.get("ok", false)) or not bool(_preflight_add(prepared).get("ok", false)):
		return false
	return _mutate(prepared, true)


func can_remove(items: Dictionary) -> Dictionary:
	var prepared := _prepare(items)
	if not bool(prepared.get("ok", false)):
		return prepared
	return _preflight_remove(prepared)


func remove_items(items: Dictionary) -> bool:
	var prepared := _prepare(items)
	if not bool(prepared.get("ok", false)) or not bool(_preflight_remove(prepared).get("ok", false)):
		return false
	return _mutate(prepared, false)


func snapshot_for(items: Dictionary) -> Dictionary:
	var prepared := _prepare(items)
	if not bool(prepared.get("ok", false)):
		return {}
	return _snapshot_prepared(prepared)


func restore_snapshot(snapshot: Dictionary) -> bool:
	if _inventory == null or _storage == null or snapshot.is_empty():
		return false
	for key in snapshot:
		if key != INVENTORY_KIND and key != STORAGE_KIND:
			return false
	var inventory_state: Variant = snapshot.get(INVENTORY_KIND)
	var storage_state: Variant = snapshot.get(STORAGE_KIND)
	if inventory_state != null and not _valid_inventory_snapshot(inventory_state):
		return false
	if storage_state != null and not _valid_storage_snapshot(storage_state):
		return false

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

	if inventory_state != null:
		_inventory.restore_state(inventory_state.slots, inventory_state.quick_mappings)
	var restored_storage := true
	if storage_state != null:
		restored_storage = _storage.restore_items_unchecked(storage_state.items)
	if inventory_transaction:
		_inventory.end_restore_notification_transaction(false)
	if storage_transaction:
		_storage.end_restore_notification_transaction(false)
	return restored_storage


func _prepare(items: Dictionary) -> Dictionary:
	if _inventory == null or _storage == null:
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
		if (
			typeof(quantity) != TYPE_INT
			or int(quantity) <= 0
			or int(quantity) > EconomyLimitsScript.MAX_SAFE_INTEGER
		):
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
			inventory_result["ok"] = false
			inventory_result["reason"] = "inventory_capacity"
			inventory_result["item_id"] = _first_item_id(inventory_items)
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
		var available := (
			_storage.get_count(item_id)
			if category == "crop"
			else _inventory.get_item_count(item_id)
		)
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


func _mutate(prepared: Dictionary, is_add: bool) -> bool:
	var inventory_items: Dictionary = prepared.inventory
	var storage_items: Dictionary = prepared.storage
	var uses_inventory := not inventory_items.is_empty()
	var uses_storage := not storage_items.is_empty()
	var inventory_snapshot: Dictionary = {}
	if uses_inventory:
		inventory_snapshot = {
			"slots": _inventory.slots.duplicate(true),
			"quick_mappings": _inventory.quick_slot_mappings.duplicate(),
		}
		if not _inventory.begin_restore_notification_transaction():
			return false
	var storage_token: RefCounted
	if uses_storage:
		storage_token = _storage.begin_atomic_transaction()
		if storage_token == null:
			if uses_inventory:
				_inventory.end_restore_notification_transaction(false)
			return false

	var event_bus := _event_bus() if uses_inventory and uses_storage else null
	var event_bus_was_blocked := event_bus != null and event_bus.is_blocking_signals()
	if event_bus != null and not event_bus_was_blocked:
		event_bus.set_block_signals(true)

	var succeeded := _mutate_inventory(inventory_items, is_add)
	if succeeded and uses_storage:
		succeeded = (
			_storage.stage_add_items(storage_token, storage_items)
			if is_add
			else _storage.stage_remove_items(storage_token, storage_items)
		)
	if not succeeded:
		_rollback_mutation(inventory_snapshot, uses_inventory, storage_token, uses_storage)
		_restore_event_bus(event_bus, event_bus_was_blocked)
		return false

	var storage_publication: RefCounted
	if uses_storage:
		storage_publication = _storage.seal_atomic_transaction(storage_token)
		if storage_publication == null:
			_rollback_mutation(inventory_snapshot, uses_inventory, storage_token, true)
			_restore_event_bus(event_bus, event_bus_was_blocked)
			return false
	_restore_event_bus(event_bus, event_bus_was_blocked)
	if uses_inventory:
		_inventory.end_restore_notification_transaction(true)
	if storage_publication != null:
		_storage.publish_sealed_transaction(storage_publication)
	return true


func _mutate_inventory(items: Dictionary, is_add: bool) -> bool:
	if items.is_empty():
		return true
	var item_ids: Array[String] = []
	for item_id_value in items:
		item_ids.append(str(item_id_value))
	item_ids.sort()
	for item_id in item_ids:
		var succeeded := (
			_inventory.add_item(item_id, int(items[item_id]))
			if is_add
			else _inventory.remove_item(item_id, int(items[item_id]))
		)
		if not succeeded:
			return false
	return true


func _rollback_mutation(
	inventory_snapshot: Dictionary,
	uses_inventory: bool,
	storage_token: Variant,
	uses_storage: bool
) -> void:
	if uses_inventory:
		_inventory.restore_state(inventory_snapshot.slots, inventory_snapshot.quick_mappings)
		_inventory.end_restore_notification_transaction(false)
	if uses_storage and storage_token != null:
		_storage.rollback_atomic_transaction(storage_token)


func _snapshot_prepared(prepared: Dictionary) -> Dictionary:
	var snapshot: Dictionary = {}
	if not (prepared.inventory as Dictionary).is_empty():
		snapshot[INVENTORY_KIND] = {
			"slots": _inventory.slots.duplicate(true),
			"quick_mappings": _inventory.quick_slot_mappings.duplicate(),
		}
	if not (prepared.storage as Dictionary).is_empty():
		snapshot[STORAGE_KIND] = {"items": _storage.get_items().duplicate(true)}
	return snapshot


func _valid_inventory_snapshot(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var state := value as Dictionary
	if state.size() != 2 or not state.has("slots") or not state.has("quick_mappings"):
		return false
	return _inventory.normalize_saved_state(state.slots, state.quick_mappings) != null


func _valid_storage_snapshot(value: Variant) -> bool:
	return value is Dictionary and _storage.validate_dict(value as Dictionary)


func _event_bus() -> Node:
	return _inventory.get_node_or_null("/root/EventBus") if _inventory.is_inside_tree() else null


func _restore_event_bus(event_bus: Node, was_blocked: bool) -> void:
	if event_bus != null and not was_blocked:
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
