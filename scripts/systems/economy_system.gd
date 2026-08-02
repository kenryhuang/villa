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
		and (_market_ref == null or _is_market_compatible(_market_ref))
	)
	if not _is_configured:
		return false
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
# 市场交易
# ============================================================

func buy_item(item_id: String, quantity: int) -> bool:
	if not _can_trade() or item_id.is_empty() or quantity <= 0:
		return false
	if not bool(_market_ref.call("can_buy", item_id, quantity)):
		return false
	if not _inventory_ref.can_add_item(item_id, quantity):
		return false
	var total := int(_market_ref.call("quote_buy", item_id, quantity))
	if total <= 0:
		return false
	var market_before: Dictionary = _market_ref.call("to_dict")
	var inventory_before := _snapshot_inventory()
	var wallet_before: Variant = _get_wallet_balance()
	var owns_market_transaction := _begin_market_transaction()
	if _market_supports_atomic_transactions() and not owns_market_transaction:
		return false
	var owns_event_bus_transaction := _begin_event_bus_transaction()
	var owns_mapping_transaction: bool = _inventory_ref.begin_mapping_transaction()
	if not spend_gold(total):
		_restore_wallet(wallet_before)
		_end_market_transaction(owns_market_transaction, false)
		_end_mapping_transaction(owns_mapping_transaction, false)
		_end_event_bus_transaction(owns_event_bus_transaction, false, item_id, quantity, true)
		return false
	if not bool(_market_ref.call("commit_buy", item_id, quantity)):
		_restore_market(market_before)
		_restore_wallet(wallet_before)
		_end_market_transaction(owns_market_transaction, false)
		_end_mapping_transaction(owns_mapping_transaction, false)
		_end_event_bus_transaction(owns_event_bus_transaction, false, item_id, quantity, true)
		return false
	if not _inventory_ref.add_item(item_id, quantity):
		_restore_inventory(inventory_before)
		_restore_market(market_before)
		_restore_wallet(wallet_before)
		_end_market_transaction(owns_market_transaction, false)
		_end_mapping_transaction(owns_mapping_transaction, false)
		_end_event_bus_transaction(owns_event_bus_transaction, false, item_id, quantity, true)
		return false
	_end_market_transaction(owns_market_transaction, true)
	_end_mapping_transaction(owns_mapping_transaction, true)
	_end_event_bus_transaction(owns_event_bus_transaction, true, item_id, quantity, true)
	return true


func sell_item(item_id: String, quantity: int) -> bool:
	if not _can_trade() or item_id.is_empty() or quantity <= 0:
		return false
	if not _inventory_ref.has_item(item_id, quantity):
		return false
	var total := int(_market_ref.call("quote_sell", item_id, quantity))
	if total <= 0:
		return false
	var market_before: Dictionary = _market_ref.call("to_dict")
	var inventory_before := _snapshot_inventory()
	var wallet_before: Variant = _get_wallet_balance()
	var owns_market_transaction := _begin_market_transaction()
	if _market_supports_atomic_transactions() and not owns_market_transaction:
		return false
	var owns_event_bus_transaction := _begin_event_bus_transaction()
	var owns_mapping_transaction: bool = _inventory_ref.begin_mapping_transaction()
	if not _inventory_ref.remove_item(item_id, quantity):
		_restore_inventory(inventory_before)
		_end_market_transaction(owns_market_transaction, false)
		_end_mapping_transaction(owns_mapping_transaction, false)
		_end_event_bus_transaction(owns_event_bus_transaction, false, item_id, quantity, false)
		return false
	if not bool(_market_ref.call("commit_sell", item_id, quantity)):
		_restore_market(market_before)
		_restore_inventory(inventory_before)
		_end_market_transaction(owns_market_transaction, false)
		_end_mapping_transaction(owns_mapping_transaction, false)
		_end_event_bus_transaction(owns_event_bus_transaction, false, item_id, quantity, false)
		return false
	if not add_gold(total):
		_restore_market(market_before)
		_restore_inventory(inventory_before)
		_restore_wallet(wallet_before)
		_end_market_transaction(owns_market_transaction, false)
		_end_mapping_transaction(owns_mapping_transaction, false)
		_end_event_bus_transaction(owns_event_bus_transaction, false, item_id, quantity, false)
		return false
	_end_market_transaction(owns_market_transaction, true)
	_end_mapping_transaction(owns_mapping_transaction, true)
	_end_event_bus_transaction(owns_event_bus_transaction, true, item_id, quantity, false)
	return true


func _can_trade() -> bool:
	return (
		_is_configured
		and _inventory_ref != null
		and _wallet_ref != null
		and _market_ref != null
		and _get_wallet_balance() != null
	)


func _is_market_compatible(market: Node) -> bool:
	for method_name in [
		"can_buy", "quote_buy", "quote_sell", "commit_buy", "commit_sell", "to_dict", "from_dict"
	]:
		if not market.has_method(method_name):
			return false
	return true


func _restore_market(snapshot: Dictionary) -> bool:
	return _market_ref != null and bool(_market_ref.call("from_dict", snapshot))


func _begin_market_transaction() -> bool:
	return (
		_market_supports_atomic_transactions()
		and bool(_market_ref.call("begin_atomic_transaction"))
	)


func _market_supports_atomic_transactions() -> bool:
	return (
		_market_ref != null
		and _market_ref.has_method("begin_atomic_transaction")
		and _market_ref.has_method("end_atomic_transaction")
	)


func _end_market_transaction(owns_transaction: bool, commit_changes: bool) -> void:
	if owns_transaction and _market_supports_atomic_transactions():
		_market_ref.call("end_atomic_transaction", commit_changes)


func _begin_event_bus_transaction() -> bool:
	if _event_bus == null or _event_bus.is_blocking_signals():
		return false
	_event_bus.set_block_signals(true)
	return true


func _end_event_bus_transaction(
	owns_transaction: bool,
	commit_changes: bool,
	item_id: String,
	quantity: int,
	is_buy: bool
) -> void:
	if not owns_transaction or _event_bus == null:
		return
	_event_bus.set_block_signals(false)
	if not commit_changes:
		return
	var balance: Variant = _get_wallet_balance()
	if balance != null:
		_event_bus.emit_signal("gold_changed", int(balance))
	_event_bus.emit_signal("item_added" if is_buy else "item_removed", item_id, quantity)
	if _market_ref.has_method("get_stock"):
		_event_bus.emit_signal("market_stock_changed", item_id, int(_market_ref.call("get_stock", item_id)))


func _get_wallet_balance() -> Variant:
	if _wallet_ref == null:
		return null
	if _wallet_ref.has_method("get_gold"):
		return int(_wallet_ref.call("get_gold"))
	for property in _wallet_ref.get_property_list():
		if str(property.get("name", "")) == "gold":
			return int(_wallet_ref.get("gold"))
	return null


func _restore_wallet(expected_balance: Variant) -> bool:
	if expected_balance == null:
		return false
	var current_balance: Variant = _get_wallet_balance()
	if current_balance == null:
		return false
	var difference := int(expected_balance) - int(current_balance)
	if difference > 0:
		_wallet_ref.call("add_gold", difference)
	elif difference < 0:
		_wallet_ref.call("spend_gold", -difference)
	return _get_wallet_balance() == expected_balance


func _snapshot_inventory() -> Dictionary:
	return {
		"slots": _inventory_ref.slots.duplicate(true),
		"quick_slot_mappings": _inventory_ref.quick_slot_mappings.duplicate(),
	}


func _restore_inventory(snapshot: Dictionary) -> void:
	_inventory_ref.restore_state(snapshot.get("slots", []), snapshot.get("quick_slot_mappings", []))


func _end_mapping_transaction(owns_transaction: bool, commit_changes: bool) -> void:
	if owns_transaction:
		_inventory_ref.end_mapping_transaction(commit_changes)


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

func advance_order_deadlines(_day: int) -> void:
	var i = orders.size() - 1
	while i >= 0:
		orders[i].days_remaining -= 1
		if orders[i].days_remaining <= 0:
			orders.remove_at(i)
		i -= 1


func generate_demand_orders(_day: int) -> void:
	generate_daily_orders()
