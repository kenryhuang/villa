class_name ContractPanel
extends Control

const GameDataScript = preload("res://scripts/core/game_data.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")

signal sign_confirmation_requested(contract_id: String, snapshot: Dictionary)
signal delivery_succeeded(contract_id: String)

@onready var active_scroll: ScrollContainer = $Content/ActiveScroll
@onready var active_list: VBoxContainer = $Content/ActiveScroll/ActiveList
@onready var active_empty: Label = $Content/ActiveEmpty
@onready var available_scroll: ScrollContainer = $Content/AvailableScroll
@onready var available_list: VBoxContainer = $Content/AvailableScroll/AvailableList
@onready var available_empty: Label = $Content/AvailableEmpty
@onready var title_label: Label = $Content/Details/TitleLabel
@onready var daily_progress_label: Label = $Content/Details/DailyProgressLabel
@onready var next_deadline_label: Label = $Content/Details/NextDeadlineLabel
@onready var breaches_label: Label = $Content/Details/BreachesLabel
@onready var total_income_label: Label = $Content/Details/TotalIncomeLabel
@onready var relationship_label: Label = $Content/Details/RelationshipLabel
@onready var error_label: Label = $Content/Details/ErrorLabel
@onready var delivery_quantity: SpinBox = $Content/Details/DeliveryQuantity
@onready var sign_button: Button = $Content/Details/SignButton
@onready var deliver_button: Button = $Content/Details/DeliverButton

var selected_contract_id := ""
var _economy: EconomySystem
var _contracts: Array[Dictionary] = []
var _sign_in_progress := false
var _refresh_queued := false
var _refresh_pending := false


static func safe_delivery_quantity(value: Variant, authoritative_quantity: int) -> int:
	if (
		authoritative_quantity <= 0
		or authoritative_quantity > EconomyLimitsScript.MAX_DELIVERY_QUANTITY
	):
		return 0
	if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)):
		return 0
	if floorf(float(value)) != float(value):
		return 0
	return clampi(int(value), 0, authoritative_quantity)


static func list_section_for(contract: Dictionary, total_day: int) -> String:
	if bool(contract.get("completed", false)) or bool(contract.get("expired", false)):
		return ""
	if bool(contract.get("signed", false)):
		return "active"
	return "available" if total_day <= int(contract.get("start_day", -1)) else ""


static func next_deadline_day(contract: Dictionary, total_day: int) -> int:
	var delivered_days: Array = contract.get("delivered_days", [])
	var first_day := maxi(total_day, int(contract.get("start_day", 0)))
	var end_day := int(contract.get("end_day", -1))
	for day in range(first_day, end_day + 1):
		if day not in delivered_days:
			return day
	return -1


func _ready() -> void:
	if not sign_button.pressed.is_connected(_on_sign_pressed):
		sign_button.pressed.connect(_on_sign_pressed)
	if not deliver_button.pressed.is_connected(_on_deliver_pressed):
		deliver_button.pressed.connect(_on_deliver_pressed)
	_connect_runtime_signals()
	refresh_contracts()


func _exit_tree() -> void:
	_refresh_queued = false
	_refresh_pending = false
	_disconnect_runtime_signals()


func configure(economy: EconomySystem, _inventory: InventorySystem = null) -> bool:
	if economy == null:
		return false
	for method_name in ["get_contracts", "sign_contract", "deliver_contract", "get_owned_quantity", "to_dict"]:
		if not economy.has_method(method_name):
			return false
	_economy = economy
	_connect_runtime_signals()
	refresh_contracts()
	return true


func select_contract(contract_id: String) -> void:
	if _visible_contract_for_id(contract_id).is_empty():
		return
	selected_contract_id = contract_id
	_update_row_selection()
	_update_detail()


func request_sign(contract_id: String) -> void:
	if _economy == null:
		_set_error("合同系统未连接")
		return
	var contract := _visible_contract_for_id(contract_id)
	var reason := _sign_disabled_reason(contract)
	if not reason.is_empty():
		refresh_contracts()
		_set_error(reason)
		return
	selected_contract_id = contract_id
	_set_error("")
	sign_confirmation_requested.emit(contract_id, contract.duplicate(true))


func commit_confirmed_sign(contract_id: String, expected_snapshot: Dictionary) -> bool:
	if _sign_in_progress or _economy == null:
		_set_error("合同签订正在处理")
		return false
	_sign_in_progress = true
	var current := _authoritative_contract(contract_id)
	if current.is_empty() or current != expected_snapshot:
		_sign_in_progress = false
		refresh_contracts()
		_set_error("合同状态已变化，请重新确认")
		return false
	var succeeded := _economy.sign_contract(contract_id)
	_sign_in_progress = false
	refresh_contracts()
	_set_error("" if succeeded else _sign_disabled_reason(_visible_contract_for_id(contract_id), true))
	return succeeded


func request_delivery(contract_id: String, quantity: int) -> void:
	if _economy == null:
		_set_error("合同系统未连接")
		return
	var contract := _visible_contract_for_id(contract_id)
	var reason := _delivery_disabled_reason(contract, quantity)
	if not reason.is_empty():
		refresh_contracts()
		_set_error(reason)
		return
	if not _economy.deliver_contract(contract_id, quantity):
		refresh_contracts()
		_set_error(_delivery_disabled_reason(_visible_contract_for_id(contract_id), quantity, true))
		return
	refresh_contracts()
	_set_error("")
	delivery_succeeded.emit(contract_id)
	_emit_unread_notification("contract", contract_id)


func refresh_contracts() -> void:
	if not is_node_ready():
		return
	_refresh_pending = false
	var active_scroll_position := active_scroll.scroll_vertical
	var available_scroll_position := available_scroll.scroll_vertical
	_contracts.clear()
	if _economy != null:
		_contracts = _economy.get_contracts().duplicate(true)
	_clear_list(active_list)
	_clear_list(available_list)
	var active_count := 0
	var available_count := 0
	var first_active_id := ""
	var first_available_id := ""
	for contract in _contracts:
		var section := list_section_for(contract, _total_day())
		if section == "active":
			active_list.add_child(_build_contract_row(contract, true))
			active_count += 1
			if first_active_id.is_empty():
				first_active_id = str(contract.get("contract_id", ""))
		elif section == "available":
			available_list.add_child(_build_contract_row(contract, false))
			available_count += 1
			if first_available_id.is_empty():
				first_available_id = str(contract.get("contract_id", ""))
	active_empty.visible = active_count == 0
	available_empty.visible = available_count == 0
	if not selected_contract_id.is_empty() and _visible_contract_for_id(selected_contract_id).is_empty():
		selected_contract_id = ""
	if selected_contract_id.is_empty():
		selected_contract_id = first_active_id if not first_active_id.is_empty() else first_available_id
	_update_row_selection()
	_update_detail()
	active_scroll.scroll_vertical = active_scroll_position
	available_scroll.scroll_vertical = available_scroll_position


func get_contracts_snapshot() -> Array[Dictionary]:
	return _contracts.duplicate(true)


func get_selected_contract() -> Dictionary:
	return _visible_contract_for_id(selected_contract_id).duplicate(true)


func _build_contract_row(contract: Dictionary, active: bool) -> Button:
	var row := Button.new()
	row.name = "ContractRow"
	row.custom_minimum_size = Vector2(0.0, 92.0)
	row.toggle_mode = true
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var contract_id := str(contract.get("contract_id", ""))
	var item_id := str(contract.get("item_id", ""))
	var quantity := int(contract.get("quantity_per_day", 0))
	var delivered_days: Array = contract.get("delivered_days", [])
	var today_progress := quantity if _total_day() in delivered_days else 0
	row.text = "%s：每日%s ×%d｜固定单价 %d\n今日 %d/%d　完成 %d/%d 天　违约 %d" % [
		_npc_name(str(contract.get("npc_id", ""))),
		_item_name(item_id),
		quantity,
		int(contract.get("unit_price", 0)),
		today_progress,
		quantity,
		delivered_days.size(),
		_duration(contract),
		int(contract.get("breaches", 0)),
	]
	if not active:
		row.text += "　[可签订]"
	row.set_meta("contract_id", contract_id)
	row.pressed.connect(select_contract.bind(contract_id))
	return row


func _update_row_selection() -> void:
	for list in [active_list, available_list]:
		if list == null:
			continue
		for child in list.get_children():
			if child is Button:
				child.button_pressed = str(child.get_meta("contract_id", "")) == selected_contract_id


func _update_detail() -> void:
	var contract := _visible_contract_for_id(selected_contract_id)
	if contract.is_empty():
		title_label.text = "选择合同查看详情"
		daily_progress_label.text = "今日交付：0/0"
		next_deadline_label.text = "下一截止：—"
		breaches_label.text = "违约次数：0"
		total_income_label.text = "预计总收入：0"
		relationship_label.text = "关系影响：—"
		sign_button.disabled = true
		deliver_button.disabled = true
		delivery_quantity.value = 0
		return
	var quantity := int(contract.get("quantity_per_day", 0))
	var delivered_days: Array = contract.get("delivered_days", [])
	var today_delivered := _total_day() in delivered_days
	var today_progress := quantity if today_delivered else 0
	var duration := _duration(contract)
	title_label.text = "%s：每日%s ×%d，共 %d 天" % [
		_npc_name(str(contract.get("npc_id", ""))),
		_item_name(str(contract.get("item_id", ""))),
		quantity,
		duration,
	]
	daily_progress_label.text = "今日交付：%d/%d｜已完成 %d/%d 天" % [today_progress, quantity, delivered_days.size(), duration]
	var next_deadline := next_deadline_day(contract, _total_day())
	if next_deadline < 0:
		next_deadline_label.text = "下一截止：已无待交付日"
	else:
		next_deadline_label.text = "下一截止：第 %d 天（剩余 %d 天）" % [
			next_deadline, maxi(next_deadline - _total_day(), 0),
		]
	breaches_label.text = "违约次数：%d" % int(contract.get("breaches", 0))
	total_income_label.text = "预计总收入：%d｜固定单价 %d" % [int(contract.get("reward_gold", 0)) * duration, int(contract.get("unit_price", 0))]
	relationship_label.text = "关系影响：每日履约提升信任；违约会降低关系"
	delivery_quantity.max_value = mini(quantity, EconomyLimitsScript.MAX_DELIVERY_QUANTITY)
	delivery_quantity.value = safe_delivery_quantity(quantity, quantity)
	var sign_reason := _sign_disabled_reason(contract)
	var delivery_reason := _delivery_disabled_reason(contract, quantity)
	sign_button.disabled = not sign_reason.is_empty()
	sign_button.tooltip_text = sign_reason
	deliver_button.disabled = not delivery_reason.is_empty()
	deliver_button.tooltip_text = delivery_reason
	deliver_button.text = "交付 %d" % quantity


func _sign_disabled_reason(contract: Dictionary, after_failure: bool = false) -> String:
	if contract.is_empty():
		return "合同状态已变化"
	if bool(contract.get("signed", false)):
		return "合同已签订"
	if bool(contract.get("completed", false)):
		return "合同已完成"
	if bool(contract.get("expired", false)) or _total_day() > int(contract.get("start_day", 0)):
		return "合同签订期限已过"
	return "合同状态已变化" if after_failure else ""


func _delivery_disabled_reason(contract: Dictionary, quantity: int, after_failure: bool = false) -> String:
	if contract.is_empty():
		return "合同状态已变化"
	if not bool(contract.get("signed", false)):
		return "请先签订合同"
	if bool(contract.get("completed", false)):
		return "合同已全部履约"
	if bool(contract.get("expired", false)) or _total_day() > int(contract.get("end_day", 0)):
		return "合同已失效"
	if _total_day() < int(contract.get("start_day", 0)):
		return "合同尚未开始"
	if _total_day() in (contract.get("delivered_days", []) as Array):
		return "今日已交付，不能重复结算"
	var required := int(contract.get("quantity_per_day", 0))
	if quantity != required or safe_delivery_quantity(quantity, required) != required:
		return "每日必须交付 %d" % required
	var item_id := str(contract.get("item_id", ""))
	var owned := _economy.get_owned_quantity(item_id) if _economy != null else 0
	if owned < required:
		return "缺少%s ×%d" % [_item_name(item_id), required - owned]
	return "合同状态已变化" if after_failure else ""


func _authoritative_contract(contract_id: String) -> Dictionary:
	if _economy == null:
		return {}
	for contract in _economy.get_contracts():
		if str(contract.get("contract_id", "")) == contract_id:
			return contract.duplicate(true)
	return {}


func _visible_contract_for_id(contract_id: String) -> Dictionary:
	var total_day := _total_day()
	for contract in _contracts:
		if (
			str(contract.get("contract_id", "")) == contract_id
			and not list_section_for(contract, total_day).is_empty()
		):
			return contract
	return {}


func _duration(contract: Dictionary) -> int:
	return maxi(int(contract.get("end_day", 0)) - int(contract.get("start_day", 0)) + 1, 0)


func _total_day() -> int:
	if _economy == null:
		return 0
	return int((_economy.to_dict() as Dictionary).get("last_processed_day", 0))


func _npc_name(npc_id: String) -> String:
	var villager := GameDataScript.get_villager(npc_id)
	return str(villager.get("name", npc_id))


func _item_name(item_id: String) -> String:
	var item: Variant = GameDataScript.get_item(item_id)
	return str(item.get("name", item_id)) if item is Dictionary else item_id


func _clear_list(list: Node) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _set_error(message: String) -> void:
	if error_label != null:
		error_label.text = message


func _on_sign_pressed() -> void:
	request_sign(selected_contract_id)


func _on_deliver_pressed() -> void:
	var contract := _visible_contract_for_id(selected_contract_id)
	var required := int(contract.get("quantity_per_day", 0))
	request_delivery(selected_contract_id, safe_delivery_quantity(delivery_quantity.value, required))


func _connect_runtime_signals() -> void:
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus == null:
		return
	var contract_callback := Callable(self, "_on_contract_updated")
	if event_bus.has_signal("contract_updated") and not event_bus.is_connected("contract_updated", contract_callback):
		event_bus.connect("contract_updated", contract_callback)
	for signal_name in ["item_added", "item_removed"]:
		var inventory_callback := Callable(self, "_on_inventory_changed")
		if event_bus.has_signal(signal_name) and not event_bus.is_connected(signal_name, inventory_callback):
			event_bus.connect(signal_name, inventory_callback)
	var storage_callback := Callable(self, "_on_storage_changed")
	if event_bus.has_signal("farm_storage_changed") and not event_bus.is_connected("farm_storage_changed", storage_callback):
		event_bus.connect("farm_storage_changed", storage_callback)


func _disconnect_runtime_signals() -> void:
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus == null:
		return
	var connections := {
		"contract_updated": Callable(self, "_on_contract_updated"),
		"item_added": Callable(self, "_on_inventory_changed"),
		"item_removed": Callable(self, "_on_inventory_changed"),
		"farm_storage_changed": Callable(self, "_on_storage_changed"),
	}
	for signal_name in connections:
		var callback: Callable = connections[signal_name]
		if event_bus.has_signal(signal_name) and event_bus.is_connected(signal_name, callback):
			event_bus.disconnect(signal_name, callback)


func _on_contract_updated(_contract_id: String) -> void:
	_queue_refresh()


func _on_inventory_changed(_item_id: String, _quantity: int) -> void:
	_queue_refresh()


func _queue_refresh() -> void:
	_refresh_pending = true
	if not is_visible_in_tree():
		return
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_do_queued_refresh")


func _do_queued_refresh() -> void:
	_refresh_queued = false
	if is_inside_tree() and is_visible_in_tree() and _refresh_pending:
		refresh_contracts()


func _on_storage_changed(_changes: Dictionary) -> void:
	_queue_refresh()


func _emit_unread_notification(target_type: String, target_id: String) -> void:
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus != null and event_bus.has_signal("economy_ui_notification_added"):
		event_bus.emit_signal("economy_ui_notification_added", target_type, target_id)
