class_name EconomySystem
extends Node

## 经济系统 - 金币管理、订单系统、资源消耗

const GameDataScript = preload("res://scripts/core/game_data.gd")

var orders: Array[Dictionary] = []

var _inventory_ref: InventorySystem
var _wallet_ref: Node
var _market_ref: Node
var _is_configured := false
var _event_bus
var _affinity: Dictionary = {}


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null


func configure(inventory: InventorySystem, wallet: Node, market: Node = null) -> bool:
	_inventory_ref = inventory
	_wallet_ref = wallet
	_market_ref = market
	_is_configured = (
		_inventory_ref != null
		and _wallet_ref != null
		and _wallet_ref.has_method("add_gold")
		and _wallet_ref.has_method("spend_gold")
	)
	if not _is_configured:
		return false
	# 连接每日事件
	if _event_bus:
		_event_bus.day_changed.connect(_on_day_changed)
	return true


# ============================================================
# 金币管理
# ============================================================

func add_gold(amount: int) -> bool:
	if not _is_configured or _wallet_ref == null:
		return false
	return bool(_wallet_ref.call("add_gold", amount))


func spend_gold(amount: int) -> bool:
	if not _is_configured or _wallet_ref == null:
		return false
	return bool(_wallet_ref.call("spend_gold", amount))


# ============================================================
# 订单系统
# ============================================================

func generate_daily_orders() -> void:
	var count = randi_range(2, 3)
	for _i in range(count):
		var order = _generate_single_order()
		if not order.is_empty():
			orders.append(order)
			if _event_bus:
				_event_bus.order_generated.emit(orders.size() - 1)


func _generate_single_order() -> Dictionary:
	# 从作物和材料中随机选择
	var candidates = GameDataScript.get_items_by_category("crop")
	candidates.append_array(GameDataScript.get_items_by_category("material"))
	if candidates.is_empty():
		return {}

	var item = candidates[randi() % candidates.size()]
	var quantity = randi_range(1, 5)
	var reward_gold = _calculate_reward(item.id, quantity)
	var villagers = GameDataScript.get_all_villagers()
	var villager_id = ""
	if not villagers.is_empty():
		villager_id = villagers[randi() % villagers.size()].id

	return {
		"item_id": item.id,
		"item_name": item.name,
		"quantity": quantity,
		"reward_gold": reward_gold,
		"reward_exp": reward_gold / 2,
		"days_remaining": 3,
		"villager_id": villager_id,
	}


func _calculate_reward(item_id: String, quantity: int) -> int:
	var base_price = GameDataScript.get_sell_price(item_id)
	if base_price <= 0:
		base_price = 5
	return base_price * quantity * 2


func complete_order(order_index: int) -> bool:
	if order_index < 0 or order_index >= orders.size():
		return false
	if _inventory_ref == null:
		return false

	var order = orders[order_index]
	if not _inventory_ref.has_item(order.item_id, order.quantity):
		return false

	# 消耗物品
	_inventory_ref.remove_item(order.item_id, order.quantity)

	# 奖励金币和经验
	add_gold(order.reward_gold)
	var game_state = get_node_or_null("/root/GameState") if is_inside_tree() else null
	if game_state:
		game_state.add_exp(order.reward_exp)

	# 提升村民好感度
	if not order.villager_id.is_empty():
		_affinity[order.villager_id] = get_affinity(order.villager_id) + 10
		var villager_system = get_node_or_null("/root/VillagerSystem") if is_inside_tree() else null
		if villager_system:
			villager_system.add_affinity(order.villager_id, 10)

	if _event_bus:
		_event_bus.order_completed.emit(order_index)

	orders.remove_at(order_index)
	return true


func get_affinity(villager_id: String) -> int:
	return int(_affinity.get(villager_id, 0))


func get_order_count() -> int:
	return orders.size()


# ============================================================
# 资源检查
# ============================================================

func has_resources(cost_dict: Dictionary) -> bool:
	return get_resource_shortages(cost_dict).is_empty()


func get_resource_report(cost_dict: Dictionary) -> Dictionary:
	var report := {}
	for item_id in cost_dict:
		var required := int(cost_dict[item_id])
		var available := (
			_inventory_ref.get_item_count(str(item_id))
			if _inventory_ref != null
			else 0
		)
		report[str(item_id)] = {
			"required": required,
			"available": available,
			"missing": maxi(required - available, 0),
		}
	return report


func get_resource_shortages(cost_dict: Dictionary) -> Dictionary:
	var shortages := {}
	var report := get_resource_report(cost_dict)
	for item_id in report:
		var entry: Dictionary = report[item_id]
		if int(entry.missing) > 0:
			shortages[item_id] = entry
	return shortages


func spend_resources(cost_dict: Dictionary) -> bool:
	if not has_resources(cost_dict):
		return false
	for item_id in cost_dict:
		_inventory_ref.remove_item(item_id, cost_dict[item_id])
	return true


# ============================================================
# 事件处理
# ============================================================

func _on_day_changed(_total_day: int) -> void:
	# 订单倒计时
	var i = orders.size() - 1
	while i >= 0:
		orders[i].days_remaining -= 1
		if orders[i].days_remaining <= 0:
			orders.remove_at(i)
		i -= 1

	# 生成新订单
	generate_daily_orders()
