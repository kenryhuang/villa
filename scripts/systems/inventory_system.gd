class_name InventorySystem
extends Node

## 背包系统 - 管理玩家物品
## 包含主背包（20格）和快捷栏（6格）

const GameDataScript = preload("res://scripts/core/game_data.gd")
const QUICK_SLOT_COUNT := 6
const DEFAULT_MAX_SLOTS := 20

signal quick_slot_mapping_changed(quick_index: int, item_id: String)

var slots: Array[Dictionary] = []  # [{item_id, quantity}, ...]
var max_slots: int = DEFAULT_MAX_SLOTS
var quick_slot_mappings: Array[int] = [-1, -1, -1, -1, -1, -1]  # 快捷栏 → 背包槽位映射

var _event_bus
var _mapping_transaction_active := false
var _mapping_transaction_items: Array[String] = []


func _init() -> void:
	reset_slots()


func _ready() -> void:
	add_to_group("inventory_system")
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null


func add_item(item_id: String, quantity: int = 1) -> bool:
	if item_id.is_empty() or quantity <= 0:
		return false
	var item_data = GameDataScript.get_item(item_id)
	if item_data == null:
		return false
	var max_stack := int(item_data.get("max_stack", GameDataScript.DEFAULT_MAX_STACK))
	var capacity := 0
	for slot in slots:
		if slot.is_empty():
			capacity += max_stack
		elif slot.get("item_id", "") == item_id:
			capacity += maxi(0, max_stack - int(slot.get("quantity", 0)))
	if capacity < quantity:
		return false
	var previous_items := _snapshot_quick_items()

	# 1. 尝试堆叠到已有槽位
	for i in range(slots.size()):
		if quantity <= 0:
			break
		var slot = slots[i]
		if not slot.is_empty() and slot.get("item_id", "") == item_id:
			var can_add = mini(quantity, max_stack - slot.quantity)
			if can_add > 0:
				slot.quantity += can_add
				quantity -= can_add
				if _event_bus:
					_event_bus.item_added.emit(item_id, can_add)

	# 2. 放入空槽位
	for i in range(slots.size()):
		if quantity <= 0:
			break
		if slots[i].is_empty():
			var add_qty = mini(quantity, max_stack)
			slots[i] = {"item_id": item_id, "quantity": add_qty}
			quantity -= add_qty
			if _event_bus:
				_event_bus.item_added.emit(item_id, add_qty)

	var added_all := quantity <= 0
	_emit_changed_quick_items(previous_items)
	return added_all


func remove_item(item_id: String, quantity: int = 1) -> bool:
	if item_id.is_empty() or quantity <= 0:
		return false

	var total = get_item_count(item_id)
	if total < quantity:
		return false
	var previous_items := _snapshot_quick_items()

	var remaining = quantity
	var i = 0
	while i < slots.size() and remaining > 0:
		if not slots[i].is_empty() and slots[i].get("item_id", "") == item_id:
			var remove_qty = mini(remaining, slots[i].quantity)
			slots[i].quantity -= remove_qty
			remaining -= remove_qty
			if _event_bus:
				_event_bus.item_removed.emit(item_id, remove_qty)
			if slots[i].quantity <= 0:
				slots[i] = {}
		i += 1

	var removed_all: bool = remaining <= 0
	_emit_changed_quick_items(previous_items)
	return removed_all


func has_item(item_id: String, quantity: int = 1) -> bool:
	return get_item_count(item_id) >= quantity


func get_item_count(item_id: String) -> int:
	var total := 0
	for slot in slots:
		if not slot.is_empty() and slot.get("item_id", "") == item_id:
			total += slot.quantity
	return total


func can_add_item(item_id: String, quantity: int = 1) -> bool:
	if item_id.is_empty() or quantity <= 0:
		return false
	var item_data = GameDataScript.get_item(item_id)
	if item_data == null:
		return false
	var max_stack := int(item_data.get("max_stack", GameDataScript.DEFAULT_MAX_STACK))
	var capacity := 0
	for slot in slots:
		if slot.is_empty():
			capacity += max_stack
		elif slot.get("item_id", "") == item_id:
			capacity += maxi(0, max_stack - int(slot.get("quantity", 0)))
		if capacity >= quantity:
			return true
	return false


func preflight_add_items(requested: Dictionary) -> Dictionary:
	var result := {
		"ok": false,
		"reason": "invalid_request",
		"requested_quantity": 0,
		"available_quantity": 0,
		"missing_quantity": 0,
		"required_slots": 0,
		"available_slots": 0,
		"missing_slots": 0,
		"missing": {},
	}
	if requested.is_empty():
		return result
	var simulated: Array = slots.duplicate(true)
	for slot in simulated:
		if (slot as Dictionary).is_empty():
			result.available_slots += 1
	var item_ids: Array[String] = []
	for item_id_value in requested:
		item_ids.append(str(item_id_value))
	item_ids.sort()
	for item_id in item_ids:
		var quantity := int(requested.get(item_id, 0))
		var item_data = GameDataScript.get_item(item_id)
		if item_data == null or quantity <= 0:
			return result
		var max_stack := int(item_data.get("max_stack", GameDataScript.DEFAULT_MAX_STACK))
		if max_stack <= 0:
			return result
		result.requested_quantity += quantity
		var remaining_for_slots := quantity
		for slot_value in slots:
			var slot := slot_value as Dictionary
			if slot.get("item_id", "") == item_id:
				remaining_for_slots -= mini(remaining_for_slots, maxi(0, max_stack - int(slot.get("quantity", 0))))
		result.required_slots += ceili(float(maxi(0, remaining_for_slots)) / float(max_stack))

		var remaining := quantity
		for index in range(simulated.size()):
			var slot := simulated[index] as Dictionary
			if slot.get("item_id", "") != item_id:
				continue
			var added := mini(remaining, maxi(0, max_stack - int(slot.get("quantity", 0))))
			if added > 0:
				slot["quantity"] = int(slot.get("quantity", 0)) + added
				remaining -= added
			if remaining <= 0:
				break
		for index in range(simulated.size()):
			if remaining <= 0:
				break
			if (simulated[index] as Dictionary).is_empty():
				var added := mini(remaining, max_stack)
				simulated[index] = {"item_id": item_id, "quantity": added}
				remaining -= added
		if remaining > 0:
			result.missing[item_id] = remaining
			result.missing_quantity += remaining
	result.available_quantity = result.requested_quantity - result.missing_quantity
	result.missing_slots = maxi(0, int(result.required_slots) - int(result.available_slots))
	result.ok = int(result.missing_quantity) == 0
	result.reason = "" if bool(result.ok) else "inventory_capacity"
	return result


func swap_slots(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= slots.size():
		return
	if to_index < 0 or to_index >= slots.size():
		return
	var previous_items := _snapshot_quick_items()
	var temp = slots[from_index]
	slots[from_index] = slots[to_index]
	slots[to_index] = temp
	_emit_changed_quick_items(previous_items)


func set_quick_slot(slot_index: int, quick_index: int) -> bool:
	if quick_index < 0 or quick_index >= 6:
		return false
	var valid_slot := slot_index >= 0 and slot_index < slots.size()
	var next_mapping := slot_index if valid_slot else -1
	var previous_items := _snapshot_quick_items()
	if quick_slot_mappings[quick_index] != next_mapping:
		quick_slot_mappings[quick_index] = next_mapping
		_emit_changed_quick_items(previous_items)
	return valid_slot


func get_quick_item(quick_index: int) -> String:
	if quick_index < 0 or quick_index >= 6:
		return ""
	var slot_idx = quick_slot_mappings[quick_index]
	if slot_idx < 0 or slot_idx >= slots.size():
		return ""
	return slots[slot_idx].get("item_id", "")


func begin_mapping_transaction() -> bool:
	if _mapping_transaction_active:
		return false
	_mapping_transaction_items = _snapshot_quick_items()
	_mapping_transaction_active = true
	return true


func end_mapping_transaction(commit_changes: bool) -> bool:
	if not _mapping_transaction_active:
		return false
	var previous_items := _mapping_transaction_items.duplicate()
	_mapping_transaction_items.clear()
	_mapping_transaction_active = false
	if commit_changes:
		_emit_changed_quick_items(previous_items)
	return true


func use_item(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var slot = slots[slot_index]
	if slot.is_empty() or slot.get("quantity", 0) <= 0:
		return false

	# 消耗品使用后减少数量
	var item_data = GameDataScript.get_item(slot.item_id)
	if item_data and item_data.get("category") in ["crop", "material"]:
		var previous_items := _snapshot_quick_items()
		slot.quantity -= 1
		if _event_bus:
			_event_bus.item_removed.emit(slot.item_id, 1)
		if slot.quantity <= 0:
			slots[slot_index] = {}
		_emit_changed_quick_items(previous_items)
		return true

	return false


func get_slot_count() -> int:
	var count := 0
	for slot in slots:
		if not slot.is_empty():
			count += 1
	return count


func is_full() -> bool:
	for slot in slots:
		if slot.is_empty():
			return false
	return true


func clear() -> void:
	reset_slots()


func restore_state(saved_slots: Variant, saved_quick_mappings: Variant) -> void:
	var previous_items := _snapshot_quick_items()

	var normalized_slots: Array[Dictionary] = []
	if saved_slots is Array:
		for saved_slot in saved_slots:
			if normalized_slots.size() >= max_slots:
				break
			if saved_slot is Dictionary:
				normalized_slots.append(saved_slot.duplicate(true))
			else:
				normalized_slots.append({})
	while normalized_slots.size() < max_slots:
		normalized_slots.append({})
	slots.assign(normalized_slots)

	var normalized_mappings: Array[int] = []
	for quick_index in range(QUICK_SLOT_COUNT):
		var slot_index := -1
		if saved_quick_mappings is Array and quick_index < saved_quick_mappings.size():
			slot_index = int(saved_quick_mappings[quick_index])
		if slot_index < 0 or slot_index >= slots.size():
			slot_index = -1
		normalized_mappings.append(slot_index)
	quick_slot_mappings.assign(normalized_mappings)
	_emit_changed_quick_items(previous_items)


func normalize_saved_state(saved_slots: Variant, saved_quick_mappings: Variant) -> Variant:
	if (
		not saved_slots is Array
		or saved_slots.size() > max_slots
		or not saved_quick_mappings is Array
		or saved_quick_mappings.size() != QUICK_SLOT_COUNT
	):
		return null
	var normalized: Array[Dictionary] = []
	var target_by_index: Array[String] = []
	var migration_targets: Array[String] = []
	var previous_stack_quantity := {}
	for slot_value in saved_slots:
		if not slot_value is Dictionary:
			return null
		var slot := slot_value as Dictionary
		if slot.is_empty():
			normalized.append({})
			target_by_index.append("")
			continue
		if slot.size() != 2 or not slot.has("item_id") or not slot.has("quantity"):
			return null
		if typeof(slot.item_id) != TYPE_STRING or not _is_integer_number(slot.quantity):
			return null
		var item_id := str(slot.item_id)
		var definition: Variant = GameDataScript.get_item(item_id)
		if not definition is Dictionary:
			return null
		var max_stack := int((definition as Dictionary).get("max_stack", 0))
		var quantity := int(slot.quantity)
		if max_stack <= 0 or quantity <= 0 or quantity > max_stack:
			return null
		if previous_stack_quantity.has(item_id) and int(previous_stack_quantity[item_id]) < max_stack:
			return null
		previous_stack_quantity[item_id] = quantity
		var target_id := str((definition as Dictionary).get("migrate_to", item_id))
		if target_id.is_empty():
			target_id = item_id
		var target_definition: Variant = GameDataScript.get_item(target_id)
		if not target_definition is Dictionary:
			return null
		if target_id != item_id and not migration_targets.has(target_id):
			migration_targets.append(target_id)
		normalized.append({"item_id": item_id, "quantity": quantity})
		target_by_index.append(target_id)

	var mappings: Array[int] = []
	for mapping_value in saved_quick_mappings:
		if not _is_integer_number(mapping_value):
			return null
		var slot_index := int(mapping_value)
		if slot_index < -1 or slot_index >= normalized.size():
			return null
		if slot_index >= 0 and normalized[slot_index].is_empty():
			return null
		mappings.append(slot_index)

	while normalized.size() < max_slots:
		normalized.append({})
		target_by_index.append("")
	for target_id in migration_targets:
		var affected: Array[int] = []
		var total := 0
		for index in range(target_by_index.size()):
			if target_by_index[index] == target_id:
				affected.append(index)
				total += int(normalized[index].get("quantity", 0))
		var target_definition: Dictionary = GameDataScript.get_item(target_id)
		var target_max_stack := int(target_definition.get("max_stack", 0))
		if target_max_stack <= 0:
			return null
		for index in affected:
			normalized[index] = {}
		var destinations := affected.duplicate()
		for index in range(normalized.size()):
			if normalized[index].is_empty() and not destinations.has(index):
				destinations.append(index)
		var needed := ceili(float(total) / float(target_max_stack))
		if needed > destinations.size():
			return null
		var first_destination := int(destinations[0])
		var remaining := total
		for destination_index in range(needed):
			var quantity := mini(remaining, target_max_stack)
			normalized[destinations[destination_index]] = {
				"item_id": target_id,
				"quantity": quantity,
			}
			remaining -= quantity
		for quick_index in range(mappings.size()):
			if mappings[quick_index] in affected:
				mappings[quick_index] = first_destination

	return {"slots": normalized, "quick_mappings": mappings}


func reset_slots() -> void:
	var previous_items := _snapshot_quick_items()
	slots.clear()
	slots.resize(max_slots)
	for i in range(max_slots):
		slots[i] = {}
	quick_slot_mappings = [-1, -1, -1, -1, -1, -1]
	_emit_changed_quick_items(previous_items)


func _snapshot_quick_items() -> Array[String]:
	var result: Array[String] = []
	for quick_index in range(QUICK_SLOT_COUNT):
		result.append(get_quick_item(quick_index))
	return result


func _emit_changed_quick_items(previous_items: Array[String]) -> void:
	if _mapping_transaction_active:
		return
	for quick_index in range(6):
		var previous_item := (
			previous_items[quick_index]
			if quick_index < previous_items.size()
			else ""
		)
		var current_item := get_quick_item(quick_index)
		if previous_item != current_item:
			quick_slot_mapping_changed.emit(quick_index, current_item)


func _is_integer_number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
	)
