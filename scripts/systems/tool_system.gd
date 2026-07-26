class_name ToolSystem
extends Node

## 工具系统 - 管理玩家工具和使用逻辑

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

	# 消耗体力
	game_state.player_state.stamina -= stamina_cost
	if _event_bus:
		_event_bus.stamina_changed.emit(game_state.player_state.stamina)

	# 执行工具功能
	match current_tool:
		ToolType.HOE:
			return _use_hoe(target)
		ToolType.WATERING_CAN:
			return _use_watering_can(target)
		ToolType.AXE:
			return _use_axe(target)
		ToolType.PICKAXE:
			return _use_pickaxe(target)
		ToolType.FISHING_ROD:
			return _use_fishing_rod(target)

	return false


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
	# 砍树 → 获得木材
	if inventory_ref:
		inventory_ref.add_item("wood", tool_levels[ToolType.AXE])
		return true
	return false


func _use_pickaxe(target: Variant) -> bool:
	# 采矿 → 获得石头
	if inventory_ref:
		inventory_ref.add_item("stone", tool_levels[ToolType.PICKAXE])
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
