class_name ToolSystem
extends Node

## 工具系统 - 管理玩家工具和使用逻辑

const GameDataScript = preload("res://scripts/core/game_data.gd")
const MAX_SAFE_INTEGER := 9007199254740991
const DEFAULT_MAX_DURABILITY := 100

enum ToolType { HOE, WATERING_CAN, AXE, PICKAXE, FISHING_ROD }

var current_tool: ToolType = ToolType.HOE
var tool_levels := {
	ToolType.HOE: 1,
	ToolType.WATERING_CAN: 1,
	ToolType.AXE: 1,
	ToolType.PICKAXE: 1,
	ToolType.FISHING_ROD: 1,
}
var tool_durability: Dictionary = {}

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
var _active_repair_transactions: Dictionary = {}
var _active_gather_transactions: Dictionary = {}


func _init() -> void:
	reset_durability()


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


func switch_tool_by_id(tool_id: String) -> bool:
	var tool_type := _item_id_to_tool(tool_id)
	if tool_type < 0:
		return false
	switch_tool(tool_type as ToolType)
	return true


func preview_gather_unit(target: Node, require_range: bool = true) -> Dictionary:
	var result := {
		"allowed": false,
		"reason": "invalid_target",
		"tool_id": "",
		"item_id": "",
		"quantity": 0,
		"stamina_cost": 0,
		"durability_cost": 1,
		"remaining_before": -1,
		"remaining_after": -1,
	}
	if (
		target == null
		or not target.has_method("can_gather")
		or not target.has_method("preview_reward")
		or not target.has_method("commit_gather")
	):
		return result
	var required_tool := _target_string_property(target, "required_tool")
	var tool_type := _item_id_to_tool(required_tool)
	if required_tool not in ["axe", "pickaxe"] or tool_type < 0:
		return result
	result.tool_id = required_tool
	var remaining := _target_int_property(target, "remaining_units", -1)
	result.remaining_before = remaining
	result.remaining_after = remaining - 1 if remaining > 0 else remaining
	if remaining == 0 or not bool(target.call("can_gather", required_tool)):
		result.reason = "resource_depleted"
		return result
	var reward := _normalized_rewards(target.call("preview_reward", required_tool))
	if reward.size() != 1:
		return result
	var reward_item := str(reward.keys()[0])
	if int(reward[reward_item]) != 1:
		return result
	result.item_id = reward_item
	result.quantity = 1
	result.stamina_cost = int(TOOL_STAMINA_COST.get(tool_type, 5))
	var durability := get_durability(required_tool)
	if durability.is_empty() or int(durability.current) <= 0:
		result.reason = "tool_broken"
		return result
	var game_state = _game_state()
	if game_state == null or int(game_state.player_state.stamina) < int(result.stamina_cost):
		result.reason = "insufficient_stamina"
		return result
	if inventory_ref == null or not _can_add_rewards({reward_item: 1}):
		result.reason = "inventory_full"
		return result
	if require_range and not _target_is_in_range(target, tool_type):
		result.reason = "out_of_range"
		return result
	result.allowed = true
	result.reason = ""
	return result


func commit_gather_unit(target: Node) -> Dictionary:
	if target == null:
		return _gather_failure("invalid_target")
	var transaction_id := target.get_instance_id()
	if _active_gather_transactions.has(transaction_id):
		return _gather_failure("transaction_busy")
	var preview := preview_gather_unit(target)
	if not bool(preview.allowed):
		return preview
	_active_gather_transactions[transaction_id] = true
	var game_state = _game_state()
	var inventory_snapshot := _inventory_snapshot()
	var target_snapshot: Dictionary = target.call("to_dict") if target.has_method("to_dict") else {}
	var stamina_before := int(game_state.player_state.stamina)
	var durability_snapshot := tool_durability.duplicate(true)
	var tool_before := current_tool
	var owns_event_transaction := _begin_inventory_event_transaction()
	var owns_mapping_transaction := _begin_inventory_mapping_transaction()
	var owns_target_transaction := (
		target.has_method("begin_gather_transaction")
		and target.has_method("end_gather_transaction")
		and bool(target.call("begin_gather_transaction"))
	)
	var tool_type := _item_id_to_tool(str(preview.tool_id)) as ToolType
	current_tool = tool_type
	if not bool(inventory_ref.call("add_item", str(preview.item_id), 1)):
		_rollback_gather(
			target, target_snapshot, inventory_snapshot, stamina_before,
			durability_snapshot, tool_before, owns_mapping_transaction, owns_event_transaction,
			owns_target_transaction
		)
		_active_gather_transactions.erase(transaction_id)
		return _gather_failure("inventory_write_failed", preview)
	var committed := _normalized_rewards(
		target.call("commit_gather", str(preview.tool_id), _current_total_day())
	)
	if committed != {str(preview.item_id): 1}:
		_rollback_gather(
			target, target_snapshot, inventory_snapshot, stamina_before,
			durability_snapshot, tool_before, owns_mapping_transaction, owns_event_transaction,
			owns_target_transaction
		)
		_active_gather_transactions.erase(transaction_id)
		return _gather_failure("target_changed", preview)
	game_state.player_state.stamina = stamina_before - int(preview.stamina_cost)
	tool_durability[str(preview.tool_id)]["current"] = (
		int(tool_durability[str(preview.tool_id)].current) - int(preview.durability_cost)
	)
	if owns_target_transaction:
		target.call("end_gather_transaction", true)
	_end_inventory_mapping_transaction(owns_mapping_transaction, true)
	_end_inventory_event_transaction(owns_event_transaction)
	_emit_committed_rewards({str(preview.item_id): 1}, owns_event_transaction)
	if _event_bus != null:
		_event_bus.stamina_changed.emit(int(game_state.player_state.stamina))
		_emit_durability_changed(str(preview.tool_id))
		_event_bus.item_added.emit(str(preview.tool_id), 0)
	_active_gather_transactions.erase(transaction_id)
	return preview


func _rollback_gather(
	target: Node,
	target_snapshot: Dictionary,
	inventory_snapshot: Dictionary,
	stamina_before: int,
	durability_snapshot: Dictionary,
	tool_before: ToolType,
	owns_mapping_transaction: bool,
	owns_event_transaction: bool,
	owns_target_transaction: bool
) -> void:
	_restore_inventory(inventory_snapshot)
	if not target_snapshot.is_empty() and target.has_method("from_dict"):
		target.call("from_dict", target_snapshot)
	if owns_target_transaction:
		target.call("end_gather_transaction", false)
	var game_state = _game_state()
	if game_state != null:
		game_state.player_state.stamina = stamina_before
	tool_durability = durability_snapshot.duplicate(true)
	current_tool = tool_before
	_end_inventory_mapping_transaction(owns_mapping_transaction, false)
	_end_inventory_event_transaction(owns_event_transaction)


func _gather_failure(reason: String, source: Dictionary = {}) -> Dictionary:
	var result := {
		"allowed": false,
		"reason": reason,
		"tool_id": "",
		"item_id": "",
		"quantity": 0,
		"stamina_cost": 0,
		"durability_cost": 1,
		"remaining_before": -1,
		"remaining_after": -1,
	}
	for key in source:
		result[key] = source[key]
	result.allowed = false
	result.reason = reason
	return result


func _target_string_property(target: Object, property_name: String) -> String:
	return str(target.get(property_name)) if _has_property(target, property_name) else ""


func _target_int_property(target: Object, property_name: String, fallback: int) -> int:
	if not _has_property(target, property_name):
		return fallback
	var value: Variant = target.get(property_name)
	return int(value) if _valid_integer(value, -1, MAX_SAFE_INTEGER) else fallback


func _target_is_in_range(target: Node, tool_type: ToolType) -> bool:
	if not player_ref is Node3D or not target is Node3D:
		return true
	var player_node := player_ref as Node3D
	var target_node := target as Node3D
	var player_position := player_node.global_position if player_node.is_inside_tree() else player_node.position
	var target_position := target_node.global_position if target_node.is_inside_tree() else target_node.position
	var maximum_range := float(TOOL_RANGE.get(tool_type, 2.0))
	if _has_property(player_node, "interaction_range"):
		maximum_range = float(player_node.get("interaction_range"))
	if target.has_method("get_interaction_radius"):
		maximum_range += maxf(0.0, float(target.call("get_interaction_radius")))
	return Vector2(player_position.x, player_position.z).distance_to(
		Vector2(target_position.x, target_position.z)
	) <= maximum_range


func use_tool_on(target: Variant) -> bool:
	if current_tool in [ToolType.AXE, ToolType.PICKAXE]:
		if not target is Node:
			return false
		var current_tool_id := _tool_to_item_id(current_tool)
		if _target_string_property(target, "required_tool") != current_tool_id:
			return false
		return bool(commit_gather_unit(target).allowed)
	# 检查体力
	var game_state = _game_state()
	if game_state == null:
		return false
	var tool_id := _tool_to_item_id(current_tool)
	if get_durability(tool_id).is_empty() or int(get_durability(tool_id).current) <= 0:
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
	tool_durability[tool_id]["current"] = int(tool_durability[tool_id].current) - 1
	if _event_bus:
		_event_bus.stamina_changed.emit(game_state.player_state.stamina)
		_emit_durability_changed(tool_id)
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
		var amount := randi_range(1, 3)
		var snapshot := _inventory_snapshot()
		if not inventory_ref.add_item("fiber", amount):
			_restore_inventory(snapshot)
			return false
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


func get_current_tool_id() -> String:
	return _tool_to_item_id(current_tool)


func upgrade_tool(tool_type: ToolType) -> void:
	tool_levels[tool_type] += 1


func get_tool_ids() -> Array[String]:
	var result: Array[String] = []
	for tool_type in ToolType.values():
		result.append(_tool_to_item_id(tool_type as ToolType))
	result.sort()
	return result


func get_tool_display_name(tool_id: String) -> String:
	var names := {
		"hoe": "锄头", "watering_can": "浇水壶", "axe": "斧头",
		"pickaxe": "镐", "fishing_rod": "鱼竿",
	}
	return str(names.get(tool_id, tool_id))


func get_durability(tool_id: String) -> Dictionary:
	if not tool_durability.has(tool_id):
		return {}
	return (tool_durability[tool_id] as Dictionary).duplicate(true)


func get_repair_quote(tool_id: String) -> Dictionary:
	var durability := get_durability(tool_id)
	if durability.is_empty():
		return {}
	var missing := int(durability.max) - int(durability.current)
	if missing <= 0:
		return {}
	var material_by_tool := {
		"hoe": "wood", "watering_can": "fiber", "axe": "wood",
		"pickaxe": "stone", "fishing_rod": "fiber",
	}
	return {
		"gold_cost": missing * 2,
		"materials": {str(material_by_tool[tool_id]): ceili(float(missing) / 20.0)},
		"restored": missing,
	}


func repair_tool(tool_id: String) -> bool:
	if _active_repair_transactions.has(tool_id):
		return false
	var quote := get_repair_quote(tool_id)
	if quote.is_empty() or inventory_ref == null:
		return false
	var game_state = _game_state()
	if game_state == null or int(game_state.gold) < int(quote.gold_cost):
		return false
	for item_id in quote.materials:
		if not inventory_ref.has_item(str(item_id), int(quote.materials[item_id])):
			return false
	_active_repair_transactions[tool_id] = true
	var inventory_snapshot := _inventory_snapshot()
	var owns_event_transaction := _begin_inventory_event_transaction()
	var owns_mapping_transaction := _begin_inventory_mapping_transaction()
	for item_id in quote.materials:
		if not inventory_ref.remove_item(str(item_id), int(quote.materials[item_id])):
			_restore_inventory(inventory_snapshot)
			_end_inventory_mapping_transaction(owns_mapping_transaction, false)
			_end_inventory_event_transaction(owns_event_transaction)
			_active_repair_transactions.erase(tool_id)
			return false
	if not game_state.spend_gold(int(quote.gold_cost)):
		_restore_inventory(inventory_snapshot)
		_end_inventory_mapping_transaction(owns_mapping_transaction, false)
		_end_inventory_event_transaction(owns_event_transaction)
		_active_repair_transactions.erase(tool_id)
		return false
	tool_durability[tool_id]["current"] = int(tool_durability[tool_id].max)
	_end_inventory_mapping_transaction(owns_mapping_transaction, true)
	_end_inventory_event_transaction(owns_event_transaction)
	if owns_event_transaction and _event_bus != null:
		_event_bus.gold_changed.emit(int(game_state.gold))
		for item_id in quote.materials:
			_event_bus.item_removed.emit(str(item_id), int(quote.materials[item_id]))
	_emit_durability_changed(tool_id)
	_active_repair_transactions.erase(tool_id)
	return true


func _emit_durability_changed(tool_id: String) -> void:
	if _event_bus == null:
		_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	var durability := get_durability(tool_id)
	if _event_bus != null and _event_bus.has_signal("tool_durability_changed") and not durability.is_empty():
		_event_bus.tool_durability_changed.emit(tool_id, int(durability.current), int(durability.max))


func reset_durability() -> bool:
	tool_durability.clear()
	for tool_id in ["hoe", "watering_can", "axe", "pickaxe", "fishing_rod"]:
		tool_durability[tool_id] = {
			"current": DEFAULT_MAX_DURABILITY,
			"max": DEFAULT_MAX_DURABILITY,
		}
	return true


func to_dict() -> Dictionary:
	var records: Array[Dictionary] = []
	for tool_id in get_tool_ids():
		var durability: Dictionary = tool_durability[tool_id]
		records.append({
			"tool_id": tool_id,
			"current": int(durability.current),
			"max": int(durability.max),
		})
	return {"version": 1, "tools": records}


func validate_dict(data: Dictionary) -> bool:
	return _parse_durability(data) != null


func from_dict(data: Dictionary) -> bool:
	var parsed: Variant = _parse_durability(data)
	if not parsed is Dictionary:
		return false
	tool_durability = parsed
	return true


func _parse_durability(data: Dictionary) -> Variant:
	if data.size() != 2 or not _valid_integer(data.get("version"), 1, 1) or not data.get("tools") is Array:
		return null
	var expected := get_tool_ids()
	var result := {}
	for value in data.tools:
		if not value is Dictionary:
			return null
		var record := value as Dictionary
		if record.size() != 3 or not record.get("tool_id") is String:
			return null
		var tool_id := str(record.tool_id)
		if tool_id not in expected or result.has(tool_id):
			return null
		if not _valid_integer(record.get("max"), DEFAULT_MAX_DURABILITY, DEFAULT_MAX_DURABILITY):
			return null
		if not _valid_integer(record.get("current"), 0, int(record.max)):
			return null
		result[tool_id] = {"current": int(record.current), "max": int(record.max)}
	return result if result.size() == expected.size() else null


static func _valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
		and float(value) >= float(minimum)
		and float(value) <= float(maximum)
	)


func _game_state() -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/GameState")
	var loop := Engine.get_main_loop()
	return loop.root.get_node_or_null("GameState") if loop is SceneTree else null


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


func _item_id_to_tool(tool_id: String) -> int:
	match tool_id:
		"hoe":
			return ToolType.HOE
		"watering_can":
			return ToolType.WATERING_CAN
		"axe":
			return ToolType.AXE
		"pickaxe":
			return ToolType.PICKAXE
		"fishing_rod":
			return ToolType.FISHING_ROD
	return -1
