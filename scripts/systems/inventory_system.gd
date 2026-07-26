class_name InventorySystem
extends Node

## 背包系统 - 管理玩家物品
## 包含主背包（20格）和快捷栏（6格）

var slots: Array[Dictionary] = []  # [{item_id, quantity}, ...]
var max_slots: int = 20
var quick_slot_mappings: Array[int] = [-1, -1, -1, -1, -1, -1]  # 快捷栏 → 背包槽位映射

var _event_bus


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")


func add_item(item_id: String, quantity: int = 1) -> bool:
	if item_id.is_empty() or quantity <= 0:
		return false

	# 1. 尝试堆叠到已有槽位
	for i in range(slots.size()):
		var slot = slots[i]
		if slot.item_id == item_id:
			var item_data = GameData.get_item(item_id)
			var max_stack = item_data.get("max_stack", 99) if item_data else 99
			var can_add = mini(quantity, max_stack - slot.quantity)
			if can_add > 0:
				slot.quantity += can_add
				quantity -= can_add
				if _event_bus:
					_event_bus.item_added.emit(item_id, can_add)
				if quantity <= 0:
					return true

	# 2. 放入空槽位
	while quantity > 0 and slots.size() < max_slots:
		var item_data = GameData.get_item(item_id)
		var max_stack = item_data.get("max_stack", 99) if item_data else 99
		var add_qty = mini(quantity, max_stack)
		slots.append({"item_id": item_id, "quantity": add_qty})
		quantity -= add_qty
		if _event_bus:
			_event_bus.item_added.emit(item_id, add_qty)

	return quantity <= 0


func remove_item(item_id: String, quantity: int = 1) -> bool:
	if item_id.is_empty() or quantity <= 0:
		return false

	var total = get_item_count(item_id)
	if total < quantity:
		return false

	var remaining = quantity
	var i = slots.size() - 1
	while i >= 0 and remaining > 0:
		if slots[i].item_id == item_id:
			var remove_qty = mini(remaining, slots[i].quantity)
			slots[i].quantity -= remove_qty
			remaining -= remove_qty
			if _event_bus:
				_event_bus.item_removed.emit(item_id, remove_qty)
			if slots[i].quantity <= 0:
				# 更新快捷栏映射
				_on_slot_removed(i)
				slots.remove_at(i)
		i -= 1

	return remaining <= 0


func has_item(item_id: String, quantity: int = 1) -> bool:
	return get_item_count(item_id) >= quantity


func get_item_count(item_id: String) -> int:
	var total := 0
	for slot in slots:
		if slot.item_id == item_id:
			total += slot.quantity
	return total


func swap_slots(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= slots.size():
		return
	if to_index < 0 or to_index >= slots.size():
		return
	var temp = slots[from_index]
	slots[from_index] = slots[to_index]
	slots[to_index] = temp


func set_quick_slot(slot_index: int, quick_index: int) -> bool:
	if quick_index < 0 or quick_index >= 6:
		return false
	if slot_index < 0 or slot_index >= slots.size():
		quick_slot_mappings[quick_index] = -1
		return false
	quick_slot_mappings[quick_index] = slot_index
	return true


func get_quick_item(quick_index: int) -> String:
	if quick_index < 0 or quick_index >= 6:
		return ""
	var slot_idx = quick_slot_mappings[quick_index]
	if slot_idx < 0 or slot_idx >= slots.size():
		return ""
	return slots[slot_idx].item_id


func use_item(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var slot = slots[slot_index]
	if slot.quantity <= 0:
		return false

	# 消耗品使用后减少数量
	var item_data = GameData.get_item(slot.item_id)
	if item_data and item_data.get("category") in ["crop", "material"]:
		slot.quantity -= 1
		if _event_bus:
			_event_bus.item_removed.emit(slot.item_id, 1)
		if slot.quantity <= 0:
			_on_slot_removed(slot_index)
			slots.remove_at(slot_index)
		return true

	return false


func _on_slot_removed(slot_index: int) -> void:
	# 更新快捷栏映射
	for i in range(quick_slot_mappings.size()):
		if quick_slot_mappings[i] == slot_index:
			quick_slot_mappings[i] = -1
		elif quick_slot_mappings[i] > slot_index:
			quick_slot_mappings[i] -= 1


func get_slot_count() -> int:
	return slots.size()


func is_full() -> bool:
	return slots.size() >= max_slots


func clear() -> void:
	slots.clear()
	quick_slot_mappings = [-1, -1, -1, -1, -1, -1]
