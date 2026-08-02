class_name ToolSystem
extends Node

## 工具系统 - 管理玩家工具和使用逻辑

const GameDataScript = preload("res://scripts/core/game_data.gd")

enum ToolType { HOE, WATERING_CAN, AXE, PICKAXE, FISHING_ROD }

var current_tool: ToolType = ToolType.HOE
var tool_levels := {
	ToolType.HOE: 1,
	ToolType.WATERING_CAN: 1,
	ToolType.AXE: 1,
	ToolType.PICKAXE: 1,
	ToolType.FISHING_ROD: 1,
}

const TOOL_STAMINA_COST := {
	ToolType.HOE: 5,
	ToolType.WATERING_CAN: 3,
	ToolType.AXE: 10,
	ToolType.PICKAXE: 8,
	ToolType.FISHING_ROD: 5,
}

const TOOL_RANGE := {
	ToolType.HOE: 2.0,
	ToolType.WATERING_CAN: 2.0,
	ToolType.AXE: 2.0,
	ToolType.PICKAXE: 2.0,
	ToolType.FISHING_ROD: 3.0,
}

var grid_system_ref
var inventory_ref
var player_ref
var _event_bus


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")


func configure(grid_sys, inv, player) -> void:
	grid_system_ref = grid_sys
	inventory_ref = inv
	player_ref = player


func switch_tool(tool_type: ToolType) -> void:
	current_tool = tool_type
	if _event_bus:
		_event_bus.item_added.emit(_tool_to_item_id(tool_type), 0)


func use_tool_on(target: Variant) -> bool:
	# 检查体力
	var game_state = get_node_or_null("/root/GameState")
	if game_state == null:
		return false

	var stamina_cost = TOOL_STAMINA_COST.get(current_tool, 5)
	if game_state.player_state.stamina < stamina_cost:
		return false

	# 执行工具功能
	var succeeded := false
	match current_tool:
		ToolType.HOE:
			succeeded = _use_hoe(target)
		ToolType.WATERING_CAN:
			succeeded = _use_watering_can(target)
		ToolType.AXE:
			succeeded = _use_axe(target)
		ToolType.PICKAXE:
			succeeded = _use_pickaxe(target)
		ToolType.FISHING_ROD:
			succeeded = _use_fishing_rod(target)

	if not succeeded:
		return false
	game_state.player_state.stamina -= stamina_cost
	if _event_bus:
		_event_bus.stamina_changed.emit(game_state.player_state.stamina)
	return true


func _use_hoe(target: Variant) -> bool:
	if grid_system_ref == null:
		return false
	if target is GridCell:
		if target.state == GridCell.State.WASTELAND:
			return grid_system_ref.set_cell_state(target.gx, target.gz, GridCell.State.FARMLAND)
	return false


func _use_watering_can(target: Variant) -> bool:
	if grid_system_ref == null:
		return false
	if target is GridCell:
		return grid_system_ref.water_cell(target.gx, target.gz)
	return false


func _use_axe(target: Variant) -> bool:
	return _use_gather_tool(target, "axe")


func _use_pickaxe(target: Variant) -> bool:
	return _use_gather_tool(target, "pickaxe")


func _use_gather_tool(target: Variant, tool_id: String) -> bool:
	if (
		target == null
		or inventory_ref == null
		or not target.has_method("can_gather")
		or not target.has_method("preview_reward")
		or not target.has_method("commit_gather")
		or not bool(target.call("can_gather", tool_id))
	):
		return false
	var rewards := _normalized_rewards(target.call("preview_reward", tool_id))
	if rewards.is_empty() or not _can_add_rewards(rewards):
		return false
	var inventory_snapshot := _inventory_snapshot()
	var target_snapshot: Dictionary = (
		target.call("to_dict")
		if target.has_method("to_dict")
		else {}
	)
	var owns_event_transaction := _begin_inventory_event_transaction()
	var owns_mapping_transaction := _begin_inventory_mapping_transaction()
	for item_id in rewards:
		if not bool(inventory_ref.call("add_item", str(item_id), int(rewards[item_id]))):
			_restore_inventory(inventory_snapshot)
			_end_inventory_mapping_transaction(owns_mapping_transaction, false)
			_end_inventory_event_transaction(owns_event_transaction)
			return false
	var committed := _normalized_rewards(
		target.call("commit_gather", tool_id, _current_total_day())
	)
	if committed != rewards:
		_restore_inventory(inventory_snapshot)
		if not target_snapshot.is_empty() and target.has_method("from_dict"):
			target.call("from_dict", target_snapshot)
		_end_inventory_mapping_transaction(owns_mapping_transaction, false)
		_end_inventory_event_transaction(owns_event_transaction)
		return false
	_end_inventory_mapping_transaction(owns_mapping_transaction, true)
	_end_inventory_event_transaction(owns_event_transaction)
	_emit_committed_rewards(rewards, owns_event_transaction)
	return true


func _normalized_rewards(value: Variant) -> Dictionary:
	var result := {}
	if not value is Dictionary:
		return result
	for item_id in value:
		var quantity_value: Variant = value[item_id]
		if (
			str(item_id).is_empty()
			or (typeof(quantity_value) != TYPE_INT and typeof(quantity_value) != TYPE_FLOAT)
			or not is_finite(float(quantity_value))
			or floorf(float(quantity_value)) != float(quantity_value)
			or int(quantity_value) <= 0
		):
			return {}
		result[str(item_id)] = int(quantity_value)
	return result


func _can_add_rewards(rewards: Dictionary) -> bool:
	if inventory_ref == null or not inventory_ref.has_method("can_add_item"):
		return false
	if not _has_property(inventory_ref, "slots"):
		for item_id in rewards:
			if not bool(inventory_ref.call("can_add_item", str(item_id), int(rewards[item_id]))):
				return false
		return true
	var virtual_slots: Array = inventory_ref.get("slots").duplicate(true)
	for item_id in rewards:
		var item_data: Variant = GameDataScript.get_item(str(item_id))
		if not item_data is Dictionary or item_data.is_empty():
			return false
		var remaining := int(rewards[item_id])
		var max_stack := int(item_data.get("max_stack", 99))
		for slot in virtual_slots:
			if remaining <= 0:
				break
			if not slot.is_empty() and str(slot.get("item_id", "")) == str(item_id):
				var added := mini(remaining, maxi(0, max_stack - int(slot.get("quantity", 0))))
				slot["quantity"] = int(slot.get("quantity", 0)) + added
				remaining -= added
		for slot_index in range(virtual_slots.size()):
			if remaining <= 0:
				break
			if virtual_slots[slot_index].is_empty():
				var added := mini(remaining, max_stack)
				virtual_slots[slot_index] = {"item_id": str(item_id), "quantity": added}
				remaining -= added
		if remaining > 0:
			return false
	return true


func _inventory_snapshot() -> Dictionary:
	if not _has_property(inventory_ref, "slots"):
		return {}
	return {
		"slots": inventory_ref.get("slots").duplicate(true),
		"quick_slot_mappings": (
			inventory_ref.get("quick_slot_mappings").duplicate()
			if _has_property(inventory_ref, "quick_slot_mappings")
			else []
		),
	}


func _restore_inventory(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or not inventory_ref.has_method("restore_state"):
		return
	inventory_ref.call(
		"restore_state",
		snapshot.get("slots", []),
		snapshot.get("quick_slot_mappings", [])
	)


func _begin_inventory_event_transaction() -> bool:
	if _event_bus == null:
		_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if _event_bus == null or _event_bus.is_blocking_signals():
		return false
	_event_bus.set_block_signals(true)
	return true


func _end_inventory_event_transaction(owns_transaction: bool) -> void:
	if owns_transaction and _event_bus != null:
		_event_bus.set_block_signals(false)


func _begin_inventory_mapping_transaction() -> bool:
	return (
		inventory_ref != null
		and inventory_ref.has_method("begin_mapping_transaction")
		and bool(inventory_ref.call("begin_mapping_transaction"))
	)


func _end_inventory_mapping_transaction(owns_transaction: bool, commit_changes: bool) -> void:
	if owns_transaction and inventory_ref.has_method("end_mapping_transaction"):
		inventory_ref.call("end_mapping_transaction", commit_changes)


func _emit_committed_rewards(rewards: Dictionary, owns_transaction: bool) -> void:
	if not owns_transaction or _event_bus == null:
		return
	for item_id in rewards:
		_event_bus.item_added.emit(str(item_id), int(rewards[item_id]))


func _current_total_day() -> int:
	var season = get_node_or_null("/root/SeasonSystem") if is_inside_tree() else null
	if season == null and get_parent() != null:
		season = get_parent().get_node_or_null("SeasonSystem")
	return maxi(int(season.total_days), 0) if season != null else 0


func _has_property(target: Variant, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _use_fishing_rod(target: Variant) -> bool:
	# 钓鱼 → 随机获得鱼
	if inventory_ref:
		# Phase 3 实现钓鱼小游戏，这里先给基础奖励
		inventory_ref.add_item("fiber", randi_range(1, 3))
		return true
	return false


func get_current_tool_name() -> String:
	match current_tool:
		ToolType.HOE:
			return "锄头"
		ToolType.WATERING_CAN:
			return "浇水壶"
		ToolType.AXE:
			return "斧头"
		ToolType.PICKAXE:
			return "镐"
		ToolType.FISHING_ROD:
			return "鱼竿"
	return "未知"


func upgrade_tool(tool_type: ToolType) -> void:
	tool_levels[tool_type] += 1


func _tool_to_item_id(tool_type: ToolType) -> String:
	match tool_type:
		ToolType.HOE:
			return "hoe"
		ToolType.WATERING_CAN:
			return "watering_can"
		ToolType.AXE:
			return "axe"
		ToolType.PICKAXE:
			return "pickaxe"
		ToolType.FISHING_ROD:
			return "fishing_rod"
	return ""
