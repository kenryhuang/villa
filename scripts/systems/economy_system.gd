class_name EconomySystem
extends Node

## 经济系统 - 金币管理、订单系统、资源消耗

const GameDataScript = preload("res://scripts/core/game_data.gd")

const MAX_ORDER_QUANTITY := 10
const URGENT_SHORTAGE_THRESHOLD := 10
const DAILY_PREMIUM_MIN := 15
const DAILY_PREMIUM_MAX := 30
const URGENT_PREMIUM_MIN := 40
const URGENT_PREMIUM_MAX := 60
const ORDER_FIELDS := [
	"order_id", "npc_id", "item_id", "quantity", "unit_price", "reward_gold",
	"expires_day", "kind", "completed", "expired",
]
const CONTRACT_FIELDS := [
	"contract_id", "npc_id", "item_id", "quantity_per_day", "unit_price",
	"reward_gold", "start_day", "end_day", "delivered_days", "breaches",
	"signed", "completed", "expired",
]
const STATE_FIELDS := ["last_processed_day", "orders", "contracts"]

var _orders: Array[Dictionary] = []
var _contracts: Array[Dictionary] = []
var _last_processed_day := 0

var _inventory_ref: InventorySystem
var _wallet_ref: Node
var _market_ref: Node
var _npc_ref: Node
var _is_configured := false
var _event_bus
var _affinity: Dictionary = {}


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null


func configure(
	inventory: InventorySystem,
	wallet: Node,
	market: Node = null,
	npc_economy_system: Node = null
) -> bool:
	_inventory_ref = inventory
	_wallet_ref = wallet
	_market_ref = market
	_npc_ref = npc_economy_system
	_is_configured = (
		_inventory_ref != null
		and _wallet_ref != null
		and _wallet_ref.has_method("add_gold")
		and _wallet_ref.has_method("spend_gold")
		and (_market_ref == null or _is_market_compatible(_market_ref))
		and (_npc_ref == null or _is_npc_compatible(_npc_ref))
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


func _is_npc_compatible(npc: Node) -> bool:
	for method_name in [
		"has_npc", "has_item", "get_shortages", "can_receive_item", "receive_item",
		"to_dict", "from_dict",
	]:
		if not npc.has_method(method_name):
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
# 订单与合同
# ============================================================

func generate_daily_orders() -> void:
	generate_demand_orders(_last_processed_day)


func get_orders() -> Array[Dictionary]:
	return _orders.duplicate(true)


func get_contracts() -> Array[Dictionary]:
	return _contracts.duplicate(true)


func complete_order(order_id: String) -> bool:
	var index := _find_record(_orders, "order_id", order_id)
	if index < 0:
		return false
	var order: Dictionary = _orders[index]
	if (
		bool(order.completed)
		or bool(order.expired)
		or _last_processed_day > int(order.expires_day)
	):
		return false
	if not _transfer_player_delivery(
		str(order.npc_id), str(order.item_id), int(order.quantity), int(order.reward_gold)
	):
		return false
	_orders[index]["completed"] = true
	_emit_record_updated("order_updated", order_id)
	return true


func sign_contract(contract_id: String) -> bool:
	var index := _find_record(_contracts, "contract_id", contract_id)
	if index < 0:
		return false
	var contract: Dictionary = _contracts[index]
	if (
		bool(contract.signed)
		or bool(contract.completed)
		or bool(contract.expired)
		or _last_processed_day > int(contract.start_day)
	):
		return false
	_contracts[index]["signed"] = true
	_emit_record_updated("contract_updated", contract_id)
	return true


func deliver_contract(contract_id: String, quantity: int) -> bool:
	var index := _find_record(_contracts, "contract_id", contract_id)
	if index < 0:
		return false
	var contract: Dictionary = _contracts[index]
	if (
		not bool(contract.signed)
		or bool(contract.completed)
		or bool(contract.expired)
		or quantity != int(contract.quantity_per_day)
		or _last_processed_day < int(contract.start_day)
		or _last_processed_day > int(contract.end_day)
		or _last_processed_day in (contract.delivered_days as Array)
	):
		return false
	if not _transfer_player_delivery(
		str(contract.npc_id), str(contract.item_id), quantity, int(contract.reward_gold)
	):
		return false
	var delivered_days: Array = _contracts[index].delivered_days
	delivered_days.append(_last_processed_day)
	delivered_days.sort()
	_contracts[index]["completed"] = delivered_days.size() == _contract_duration(contract)
	_emit_record_updated("contract_updated", contract_id)
	return true


func _transfer_player_delivery(
	npc_id: String,
	item_id: String,
	quantity: int,
	reward_gold: int
) -> bool:
	if (
		not _is_configured
		or _inventory_ref == null
		or _wallet_ref == null
		or _npc_ref == null
		or quantity <= 0
		or reward_gold <= 0
		or not _inventory_ref.has_item(item_id, quantity)
		or not bool(_npc_ref.call("can_receive_item", npc_id, item_id, quantity))
	):
		return false
	var inventory_before := _snapshot_inventory()
	var npc_before: Dictionary = _npc_ref.call("to_dict")
	var wallet_before: Variant = _get_wallet_balance()
	if (
		wallet_before == null
		or int(wallet_before) < 0
		or int(wallet_before) > 9223372036854775807 - reward_gold
	):
		return false
	var owns_event_bus_transaction := _begin_event_bus_transaction()
	var owns_mapping_transaction := _inventory_ref.begin_mapping_transaction()
	var success := (
		_inventory_ref.remove_item(item_id, quantity)
		and bool(_npc_ref.call("receive_item", npc_id, item_id, quantity))
		and add_gold(reward_gold)
	)
	if not success:
		_restore_inventory(inventory_before)
		_npc_ref.call("from_dict", npc_before)
		_restore_wallet(wallet_before)
		_end_mapping_transaction(owns_mapping_transaction, false)
		_end_delivery_event_transaction(owns_event_bus_transaction, false, item_id, quantity)
		return false
	_end_mapping_transaction(owns_mapping_transaction, true)
	_end_delivery_event_transaction(owns_event_bus_transaction, true, item_id, quantity)
	return true


func _end_delivery_event_transaction(
	owns_transaction: bool,
	commit_changes: bool,
	item_id: String,
	quantity: int
) -> void:
	if not owns_transaction or _event_bus == null:
		return
	_event_bus.set_block_signals(false)
	if not commit_changes:
		return
	var balance: Variant = _get_wallet_balance()
	if balance != null:
		_event_bus.emit_signal("gold_changed", int(balance))
	_event_bus.emit_signal("item_removed", item_id, quantity)


func _emit_record_updated(signal_name: String, record_id: String) -> void:
	if _event_bus != null and _event_bus.has_signal(signal_name):
		_event_bus.emit_signal(signal_name, record_id)


func _find_record(records: Array[Dictionary], id_field: String, record_id: String) -> int:
	if record_id.is_empty():
		return -1
	for index in range(records.size()):
		if str(records[index].get(id_field, "")) == record_id:
			return index
	return -1


func get_affinity(villager_id: String) -> int:
	return int(_affinity.get(villager_id, 0))


func get_order_count() -> int:
	return _orders.size()


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

func advance_order_deadlines(day: int) -> void:
	if day <= _last_processed_day or day <= 0:
		return
	for index in range(_orders.size()):
		var order: Dictionary = _orders[index]
		if not bool(order.completed) and not bool(order.expired) and day > int(order.expires_day):
			_orders[index]["expired"] = true
			_emit_record_updated("order_updated", str(order.order_id))
	for index in range(_contracts.size()):
		var contract: Dictionary = _contracts[index]
		if bool(contract.completed) or bool(contract.expired):
			continue
		if bool(contract.signed):
			var first_missed_day := maxi(int(contract.start_day), _last_processed_day)
			var last_missed_day := mini(int(contract.end_day), day - 1)
			for missed_day in range(first_missed_day, last_missed_day + 1):
				if missed_day not in (contract.delivered_days as Array):
					_contracts[index]["breaches"] = int(_contracts[index].breaches) + 1
		if day > int(contract.end_day):
			_contracts[index]["expired"] = true
		_emit_record_updated("contract_updated", str(contract.contract_id))
	_last_processed_day = day


func generate_demand_orders(day: int) -> void:
	if day <= 0 or _npc_ref == null or _market_ref == null:
		return
	var shortages: Array = _npc_ref.call("get_shortages")
	for shortage_value in shortages:
		if not shortage_value is Dictionary:
			continue
		var shortage: Dictionary = shortage_value
		var npc_id := str(shortage.get("npc_id", ""))
		var item_id := str(shortage.get("item_id", ""))
		var shortage_quantity := int(shortage.get("quantity", 0))
		if (
			npc_id.is_empty()
			or item_id.is_empty()
			or shortage_quantity <= 0
			or _has_open_order(npc_id, item_id)
		):
			continue
		var quantity := mini(shortage_quantity, MAX_ORDER_QUANTITY)
		var kind := "urgent" if shortage_quantity >= URGENT_SHORTAGE_THRESHOLD else "daily"
		var premium := _deterministic_premium(day, npc_id, item_id, kind)
		var market_sell_quote := int(_market_ref.call("quote_sell", item_id, quantity))
		var price := _order_price_for_quote(market_sell_quote, quantity, premium, kind)
		if price.is_empty():
			continue
		var order_id := "%s:%s:%d" % [npc_id, item_id, day]
		if _find_record(_orders, "order_id", order_id) >= 0:
			continue
		_orders.append({
			"order_id": order_id,
			"npc_id": npc_id,
			"item_id": item_id,
			"quantity": quantity,
			"unit_price": int(price.unit_price),
			"reward_gold": int(price.reward_gold),
			"expires_day": day + (1 if kind == "urgent" else 2),
			"kind": kind,
			"completed": false,
			"expired": false,
		})
		_emit_record_updated("order_updated", order_id)


func _has_open_order(npc_id: String, item_id: String) -> bool:
	for order in _orders:
		if (
			str(order.npc_id) == npc_id
			and str(order.item_id) == item_id
			and not bool(order.completed)
			and not bool(order.expired)
		):
			return true
	return false


func _order_price_for_quote(
	market_sell_quote: int,
	quantity: int,
	target_premium: int,
	kind: String
) -> Dictionary:
	if market_sell_quote <= 0 or quantity <= 0:
		return {}
	var minimum := URGENT_PREMIUM_MIN if kind == "urgent" else DAILY_PREMIUM_MIN
	var maximum := URGENT_PREMIUM_MAX if kind == "urgent" else DAILY_PREMIUM_MAX
	var minimum_reward := _scaled_ceil(market_sell_quote, 100 + minimum, 100)
	var maximum_reward := _scaled_floor(market_sell_quote, 100 + maximum, 100)
	if minimum_reward <= 0 or maximum_reward < minimum_reward:
		return {}
	var minimum_unit := _ceil_div_positive(minimum_reward, quantity)
	var maximum_unit := maximum_reward / quantity
	if minimum_unit <= 0 or minimum_unit > maximum_unit:
		return {}
	var target_reward := _scaled_ceil(market_sell_quote, 100 + target_premium, 100)
	var target_unit := maximum_unit if target_reward <= 0 else _ceil_div_positive(target_reward, quantity)
	var unit_price := clampi(target_unit, minimum_unit, maximum_unit)
	if unit_price <= 0 or unit_price > 9223372036854775807 / quantity:
		return {}
	return {
		"unit_price": unit_price,
		"reward_gold": unit_price * quantity,
	}


func _scaled_ceil(value: int, factor: int, divisor: int) -> int:
	if value <= 0 or factor <= 0 or divisor <= 0:
		return -1
	var whole := value / divisor
	var remainder := value % divisor
	if whole > 9223372036854775807 / factor:
		return -1
	var scaled := whole * factor
	var extra := (remainder * factor + divisor - 1) / divisor
	if scaled > 9223372036854775807 - extra:
		return -1
	return scaled + extra


func _scaled_floor(value: int, factor: int, divisor: int) -> int:
	if value <= 0 or factor <= 0 or divisor <= 0:
		return -1
	var whole := value / divisor
	var remainder := value % divisor
	if whole > 9223372036854775807 / factor:
		return 9223372036854775807
	var scaled := whole * factor
	var extra := remainder * factor / divisor
	if scaled > 9223372036854775807 - extra:
		return 9223372036854775807
	return scaled + extra


func _ceil_div_positive(value: int, divisor: int) -> int:
	if value <= 0 or divisor <= 0:
		return -1
	return (value - 1) / divisor + 1


func _deterministic_premium(day: int, npc_id: String, item_id: String, kind: String) -> int:
	var minimum := URGENT_PREMIUM_MIN if kind == "urgent" else DAILY_PREMIUM_MIN
	var maximum := URGENT_PREMIUM_MAX if kind == "urgent" else DAILY_PREMIUM_MAX
	var value := 0
	var key := "%d:%s:%s:%s" % [day, npc_id, item_id, kind]
	for index in range(key.length()):
		value = (value * 31 + key.unicode_at(index)) % 2147483647
	return minimum + value % (maximum - minimum + 1)


func to_dict() -> Dictionary:
	return {
		"last_processed_day": _last_processed_day,
		"orders": _orders.duplicate(true),
		"contracts": _contracts.duplicate(true),
	}


func from_dict(data: Dictionary) -> bool:
	var normalized: Variant = _normalize_state(data)
	if normalized == null:
		return false
	_last_processed_day = int(normalized.last_processed_day)
	_orders.assign(normalized.orders)
	_contracts.assign(normalized.contracts)
	return true


func validate_dict(data: Dictionary) -> bool:
	return _normalize_state(data) != null


func reset_order_state(day: int) -> bool:
	if day < 0:
		return false
	_orders.clear()
	_contracts.clear()
	_last_processed_day = day
	return true


func _normalize_state(data: Dictionary) -> Variant:
	if not _is_configured or not _has_exact_fields(data, STATE_FIELDS):
		return null
	if not _is_nonnegative_integer(data.last_processed_day):
		return null
	if not data.orders is Array or not data.contracts is Array:
		return null
	var cursor := int(data.last_processed_day)
	var normalized_orders: Array[Dictionary] = []
	var order_ids: Dictionary = {}
	var open_pairs: Dictionary = {}
	for value in data.orders as Array:
		var normalized_order: Variant = _normalize_order(value, cursor)
		if normalized_order == null:
			return null
		var order: Dictionary = normalized_order
		if order_ids.has(order.order_id):
			return null
		order_ids[order.order_id] = true
		if not bool(order.completed) and not bool(order.expired):
			var pair := "%s:%s" % [order.npc_id, order.item_id]
			if open_pairs.has(pair):
				return null
			open_pairs[pair] = true
		normalized_orders.append(order)
	var normalized_contracts: Array[Dictionary] = []
	var contract_ids: Dictionary = {}
	for value in data.contracts as Array:
		var normalized_contract: Variant = _normalize_contract(value, cursor)
		if normalized_contract == null:
			return null
		var contract: Dictionary = normalized_contract
		if contract_ids.has(contract.contract_id):
			return null
		contract_ids[contract.contract_id] = true
		normalized_contracts.append(contract)
	return {
		"last_processed_day": cursor,
		"orders": normalized_orders,
		"contracts": normalized_contracts,
	}


func _normalize_order(value: Variant, cursor: int) -> Variant:
	if not value is Dictionary:
		return null
	var order: Dictionary = value
	if not _has_exact_fields(order, ORDER_FIELDS):
		return null
	if not _valid_record_identity(order.npc_id, order.item_id):
		return null
	for field in ["quantity", "unit_price", "reward_gold", "expires_day"]:
		if not _is_positive_integer(order[field]):
			return null
	if (
		typeof(order.order_id) != TYPE_STRING
		or typeof(order.kind) != TYPE_STRING
		or str(order.kind) not in ["daily", "urgent"]
		or typeof(order.completed) != TYPE_BOOL
		or typeof(order.expired) != TYPE_BOOL
		or (bool(order.completed) and bool(order.expired))
		or int(order.quantity) > MAX_ORDER_QUANTITY
		or int(order.quantity) > 9223372036854775807 / int(order.unit_price)
		or int(order.reward_gold) != int(order.quantity) * int(order.unit_price)
	):
		return null
	var parts := str(order.order_id).split(":")
	if parts.size() != 3 or parts[0] != str(order.npc_id) or parts[1] != str(order.item_id):
		return null
	if not parts[2].is_valid_int() or int(parts[2]) <= 0:
		return null
	var created_day := int(parts[2])
	if created_day > 9223372036854775805 or created_day > cursor:
		return null
	var expected_expiry := created_day + (1 if str(order.kind) == "urgent" else 2)
	if (
		int(order.expires_day) != expected_expiry
		or (bool(order.expired) and cursor <= int(order.expires_day))
		or (
			not bool(order.completed)
			and not bool(order.expired)
			and cursor > int(order.expires_day)
		)
	):
		return null
	var normalized := order.duplicate(true)
	for field in ["quantity", "unit_price", "reward_gold", "expires_day"]:
		normalized[field] = int(order[field])
	return normalized


func _normalize_contract(value: Variant, cursor: int) -> Variant:
	if not value is Dictionary:
		return null
	var contract: Dictionary = value
	if not _has_exact_fields(contract, CONTRACT_FIELDS):
		return null
	if not _valid_record_identity(contract.npc_id, contract.item_id):
		return null
	for field in ["quantity_per_day", "unit_price", "reward_gold", "start_day", "end_day"]:
		if not _is_positive_integer(contract[field]):
			return null
	if (
		not _is_nonnegative_integer(contract.breaches)
		or typeof(contract.contract_id) != TYPE_STRING
		or typeof(contract.signed) != TYPE_BOOL
		or typeof(contract.completed) != TYPE_BOOL
		or typeof(contract.expired) != TYPE_BOOL
		or not contract.delivered_days is Array
		or int(contract.end_day) < int(contract.start_day)
		or int(contract.quantity_per_day) > 9223372036854775807 / int(contract.unit_price)
		or int(contract.reward_gold) != int(contract.quantity_per_day) * int(contract.unit_price)
		or (bool(contract.completed) and bool(contract.expired))
	):
		return null
	var expected_id := "%s:%s:%d:%d" % [
		str(contract.npc_id), str(contract.item_id), int(contract.start_day), int(contract.end_day),
	]
	if str(contract.contract_id) != expected_id:
		return null
	var delivered_days: Array[int] = []
	for delivered_value in contract.delivered_days as Array:
		if (
			not _is_positive_integer(delivered_value)
			or int(delivered_value) < int(contract.start_day)
			or int(delivered_value) > int(contract.end_day)
			or int(delivered_value) > cursor
			or int(delivered_value) in delivered_days
		):
			return null
		delivered_days.append(int(delivered_value))
	delivered_days.sort()
	var duration := _contract_duration(contract)
	var eligible_missed_days := 0
	if bool(contract.signed):
		for day in range(int(contract.start_day), mini(int(contract.end_day), cursor - 1) + 1):
			if day not in delivered_days:
				eligible_missed_days += 1
	if (
		int(contract.breaches) != eligible_missed_days
		or (not bool(contract.signed) and (not delivered_days.is_empty() or int(contract.breaches) > 0))
		or bool(contract.completed) != (delivered_days.size() == duration)
		or (bool(contract.expired) and cursor <= int(contract.end_day))
		or (
			not bool(contract.completed)
			and not bool(contract.expired)
			and cursor > int(contract.end_day)
		)
	):
		return null
	var normalized := contract.duplicate(true)
	for field in [
		"quantity_per_day", "unit_price", "reward_gold", "start_day", "end_day", "breaches",
	]:
		normalized[field] = int(contract[field])
	normalized["delivered_days"] = delivered_days
	return normalized


func _valid_record_identity(npc_id_value: Variant, item_id_value: Variant) -> bool:
	if typeof(npc_id_value) != TYPE_STRING or typeof(item_id_value) != TYPE_STRING:
		return false
	var npc_id := str(npc_id_value)
	var item_id := str(item_id_value)
	return (
		not npc_id.is_empty()
		and not item_id.is_empty()
		and _npc_ref != null
		and bool(_npc_ref.call("has_npc", npc_id))
		and bool(_npc_ref.call("has_item", item_id))
		and GameDataScript.get_item(item_id) != null
	)


func _contract_duration(contract: Dictionary) -> int:
	return int(contract.end_day) - int(contract.start_day) + 1


func _has_exact_fields(data: Dictionary, fields: Array) -> bool:
	if data.size() != fields.size():
		return false
	for field in fields:
		if not data.has(field):
			return false
	return true


func _is_positive_integer(value: Variant) -> bool:
	return _is_integer_number(value) and int(value) > 0


func _is_nonnegative_integer(value: Variant) -> bool:
	return _is_integer_number(value) and int(value) >= 0


func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) and absf(number) <= 9007199254740991.0
