class_name OrderPanel
extends Control

const GameDataScript = preload("res://scripts/core/game_data.gd")
const VALID_FILTERS := ["all", "daily", "urgent", "event", "construction", "completed"]
const STATUS_TEXT := {
	"accepted": "已接取",
	"deliverable": "可交付",
	"completed": "已完成",
	"expired": "已失效",
}
const KIND_TEXT := {
	"daily": "日常",
	"urgent": "紧急",
	"event": "节日",
	"construction": "建设",
}

signal delivery_succeeded(order_id: String)

@onready var filter_buttons := {
	"all": $Columns/Filters/All,
	"daily": $Columns/Filters/Daily,
	"urgent": $Columns/Filters/Urgent,
	"event": $Columns/Filters/Event,
	"construction": $Columns/Filters/Construction,
	"completed": $Columns/Filters/Completed,
}
@onready var order_scroll: ScrollContainer = $Columns/Orders/OrderScroll
@onready var order_rows: VBoxContainer = $Columns/Orders/OrderScroll/OrderRows
@onready var empty_state: Label = $Columns/Orders/EmptyState
@onready var npc_label: Label = $Columns/Details/NpcLabel
@onready var title_label: Label = $Columns/Details/TitleLabel
@onready var item_label: Label = $Columns/Details/ItemLabel
@onready var owned_label: Label = $Columns/Details/OwnedLabel
@onready var deadline_label: Label = $Columns/Details/DeadlineLabel
@onready var premium_label: Label = $Columns/Details/PremiumLabel
@onready var detail_label: Label = $Columns/Details/DetailLabel
@onready var error_label: Label = $Columns/Details/ErrorLabel
@onready var deliver_button: Button = $Columns/Details/DeliverButton

var selected_filter := "all"
var selected_order_id := ""
var _economy: EconomySystem
var _npc_economy: NpcEconomySystem
var _orders: Array[Dictionary] = []
var _visible_orders: Array[Dictionary] = []
var _refresh_queued := false


static func status_for(order: Dictionary, owned: int, total_day: int) -> String:
	if bool(order.get("completed", false)):
		return "completed"
	var expires_day := int(order.get("expires_day", -1))
	if bool(order.get("expired", false)) or total_day > expires_day:
		return "expired"
	if owned >= int(order.get("quantity", 0)) and total_day <= expires_day:
		return "deliverable"
	return "accepted"


func _ready() -> void:
	for filter_id in filter_buttons:
		var callback := Callable(self, "set_filter").bind(filter_id)
		var button: Button = filter_buttons[filter_id]
		if not button.pressed.is_connected(callback):
			button.pressed.connect(callback)
	if not deliver_button.pressed.is_connected(_on_deliver_pressed):
		deliver_button.pressed.connect(_on_deliver_pressed)
	_connect_runtime_signals()
	refresh_orders()


func _exit_tree() -> void:
	_disconnect_runtime_signals()


func configure(
	economy: EconomySystem,
	npc_economy: NpcEconomySystem,
	_inventory: InventorySystem = null
) -> bool:
	if economy == null or npc_economy == null:
		return false
	for method_name in ["get_orders", "complete_order", "get_owned_quantity", "to_dict"]:
		if not economy.has_method(method_name):
			return false
	for method_name in ["get_shortages", "has_npc"]:
		if not npc_economy.has_method(method_name):
			return false
	_economy = economy
	_npc_economy = npc_economy
	_connect_runtime_signals()
	refresh_orders()
	return true


func set_filter(filter_id: String) -> void:
	if filter_id not in VALID_FILTERS:
		return
	selected_filter = filter_id
	refresh_orders()


func select_order(order_id: String) -> void:
	if _visible_order_for_id(order_id).is_empty():
		return
	selected_order_id = order_id
	_update_rows_selection()
	_update_detail()


func request_delivery(order_id: String) -> void:
	if _economy == null:
		_set_error("订单系统未连接")
		return
	var order := _visible_order_for_id(order_id)
	if order.is_empty():
		refresh_orders()
		_set_error("订单不在当前筛选")
		return
	selected_order_id = order_id
	var reason := _delivery_disabled_reason(order)
	if not reason.is_empty():
		refresh_orders()
		_set_error(reason)
		return
	if not _economy.complete_order(order_id):
		refresh_orders()
		_set_error(_delivery_disabled_reason(_visible_order_for_id(order_id), true))
		return
	refresh_orders()
	_set_error("")
	delivery_succeeded.emit(order_id)
	_emit_unread_notification("order", order_id)


func refresh_orders() -> void:
	if not is_node_ready():
		return
	var scroll_position := order_scroll.scroll_vertical
	_orders.clear()
	_visible_orders.clear()
	if _economy != null:
		_orders = _economy.get_orders().duplicate(true)
	for order in _orders:
		if _matches_filter(order):
			_visible_orders.append(order.duplicate(true))
	for child in order_rows.get_children():
		order_rows.remove_child(child)
		child.queue_free()
	for order in _visible_orders:
		order_rows.add_child(_build_order_row(order))
	empty_state.visible = _visible_orders.is_empty()
	if _orders.is_empty():
		empty_state.text = "暂时没有居民发布需求"
	elif _visible_orders.is_empty():
		empty_state.text = "当前筛选没有订单"
	if not selected_order_id.is_empty() and _visible_order_for_id(selected_order_id).is_empty():
		selected_order_id = ""
	if selected_order_id.is_empty() and not _visible_orders.is_empty():
		selected_order_id = str(_visible_orders[0].get("order_id", ""))
	for filter_id in filter_buttons:
		filter_buttons[filter_id].button_pressed = filter_id == selected_filter
	_update_rows_selection()
	_update_detail()
	order_scroll.scroll_vertical = scroll_position


func get_visible_orders() -> Array[Dictionary]:
	return _visible_orders.duplicate(true)


func get_selected_order() -> Dictionary:
	return _visible_order_for_id(selected_order_id).duplicate(true)


func _matches_filter(order: Dictionary) -> bool:
	if selected_filter == "all":
		return true
	var status := status_for(order, _owned(order), _total_day())
	if selected_filter == "completed":
		return status == "completed" or status == "expired"
	return str(order.get("kind", "daily")) == selected_filter


func _build_order_row(order: Dictionary) -> Button:
	var row := Button.new()
	row.name = "OrderRow"
	row.custom_minimum_size = Vector2(0.0, 108.0)
	row.toggle_mode = true
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var order_id := str(order.get("order_id", ""))
	var quantity := int(order.get("quantity", 0))
	var owned := _owned(order)
	var total_day := _total_day()
	var status := status_for(order, owned, total_day)
	row.text = "%s｜%s\n%s ×%d　持有 %d/%d\n剩余 %d 天　%s　%s　%s" % [
		_npc_name(str(order.get("npc_id", ""))),
		_npc_role(str(order.get("npc_id", ""))),
		_item_name(str(order.get("item_id", ""))),
		quantity,
		owned,
		quantity,
		maxi(int(order.get("expires_day", 0)) - total_day, 0),
		KIND_TEXT.get(str(order.get("kind", "daily")), str(order.get("kind", "daily"))),
		_premium_text(order),
		STATUS_TEXT.get(status, status),
	]
	row.tooltip_text = row.text
	row.set_meta("order_id", order_id)
	row.set_meta("status", status)
	row.pressed.connect(select_order.bind(order_id))
	return row


func _update_rows_selection() -> void:
	if order_rows == null:
		return
	for child in order_rows.get_children():
		if child is Button:
			child.button_pressed = str(child.get_meta("order_id", "")) == selected_order_id


func _update_detail() -> void:
	var order := _visible_order_for_id(selected_order_id)
	if order.is_empty():
		npc_label.text = "NPC：—"
		title_label.text = "选择订单查看详情"
		item_label.text = "商品：—"
		owned_label.text = "持有：0/0"
		deadline_label.text = "期限：—"
		premium_label.text = "溢价：—"
		detail_label.text = "居民的真实缺货原因会显示在这里"
		deliver_button.disabled = true
		deliver_button.tooltip_text = "请先选择订单"
		return
	var npc_id := str(order.get("npc_id", ""))
	var item_id := str(order.get("item_id", ""))
	var owned := _owned(order)
	var quantity := int(order.get("quantity", 0))
	var total_day := _total_day()
	var status := status_for(order, owned, total_day)
	npc_label.text = "NPC：%s（%s）" % [_npc_name(npc_id), _npc_role(npc_id)]
	title_label.text = "%s订单｜%s" % [KIND_TEXT.get(str(order.get("kind", "daily")), "居民"), STATUS_TEXT.get(status, status)]
	item_label.text = "商品：%s ×%d" % [_item_name(item_id), quantity]
	owned_label.text = "持有：%d/%d" % [owned, quantity]
	deadline_label.text = "期限：第 %d 天（剩余 %d 天）" % [
		int(order.get("expires_day", 0)), maxi(int(order.get("expires_day", 0)) - total_day, 0),
	]
	premium_label.text = "%s｜奖励 %d 金币" % [_premium_text(order), int(order.get("reward_gold", 0))]
	detail_label.text = _shortage_reason(order)
	var reason := _delivery_disabled_reason(order)
	deliver_button.disabled = not reason.is_empty()
	deliver_button.text = "交付 %s ×%d" % [_item_name(item_id), quantity]
	deliver_button.tooltip_text = reason


func _delivery_disabled_reason(order: Dictionary, after_failure: bool = false) -> String:
	if order.is_empty():
		return "订单状态已变化"
	var status := status_for(order, _owned(order), _total_day())
	if status == "completed":
		return "订单已完成"
	if status == "expired":
		return "订单已失效"
	var missing := int(order.get("quantity", 0)) - _owned(order)
	if missing > 0:
		return "缺少%s ×%d" % [_item_name(str(order.get("item_id", ""))), missing]
	return "订单状态已变化" if after_failure else ""


func _shortage_reason(order: Dictionary) -> String:
	var npc_id := str(order.get("npc_id", ""))
	var item_id := str(order.get("item_id", ""))
	var shortage_quantity := 0
	if _npc_economy != null:
		for shortage in _npc_economy.get_shortages():
			if str(shortage.get("npc_id", "")) == npc_id and str(shortage.get("item_id", "")) == item_id:
				shortage_quantity = int(shortage.get("quantity", 0))
				break
	if shortage_quantity <= 0:
		return "%s的缺货状态已缓解，订单仍按原期限有效" % _npc_name(npc_id)
	var consequence := "居民储备不足"
	if _npc_role(npc_id) == "工匠" and item_id in ["iron_ore", "coal", "iron_ingot"]:
		consequence = "工具生产已暂停"
	return "%s缺少%s ×%d，%s" % [
		_npc_name(npc_id), _item_name(item_id), shortage_quantity, consequence,
	]


func _premium_text(order: Dictionary) -> String:
	var item: Variant = GameDataScript.get_item(str(order.get("item_id", "")))
	var reference := int(item.get("sell_price", item.get("base_price", 0))) if item is Dictionary else 0
	var unit_price := int(order.get("unit_price", 0))
	if reference <= 0:
		return "溢价奖励"
	var percent := roundi((float(unit_price) / float(reference) - 1.0) * 100.0)
	return "溢价 %+d%%" % percent


func _visible_order_for_id(order_id: String) -> Dictionary:
	for order in _visible_orders:
		if str(order.get("order_id", "")) == order_id:
			return order
	return {}


func _owned(order: Dictionary) -> int:
	return _economy.get_owned_quantity(str(order.get("item_id", ""))) if _economy != null else 0


func _total_day() -> int:
	if _economy == null:
		return 0
	return int((_economy.to_dict() as Dictionary).get("last_processed_day", 0))


func _npc_name(npc_id: String) -> String:
	var villager := GameDataScript.get_villager(npc_id)
	return str(villager.get("name", npc_id))


func _npc_role(npc_id: String) -> String:
	var villager := GameDataScript.get_villager(npc_id)
	return str(villager.get("role", "居民"))


func _item_name(item_id: String) -> String:
	var item: Variant = GameDataScript.get_item(item_id)
	return str(item.get("name", item_id)) if item is Dictionary else item_id


func _set_error(message: String) -> void:
	if error_label != null:
		error_label.text = message


func _on_deliver_pressed() -> void:
	request_delivery(selected_order_id)


func _connect_runtime_signals() -> void:
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus == null:
		return
	var callback := Callable(self, "_on_order_updated")
	if event_bus.has_signal("order_updated") and not event_bus.is_connected("order_updated", callback):
		event_bus.connect("order_updated", callback)
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
		"order_updated": Callable(self, "_on_order_updated"),
		"item_added": Callable(self, "_on_inventory_changed"),
		"item_removed": Callable(self, "_on_inventory_changed"),
		"farm_storage_changed": Callable(self, "_on_storage_changed"),
	}
	for signal_name in connections:
		var callback: Callable = connections[signal_name]
		if event_bus.has_signal(signal_name) and event_bus.is_connected(signal_name, callback):
			event_bus.disconnect(signal_name, callback)


func _on_order_updated(_order_id: String) -> void:
	_queue_refresh()


func _on_inventory_changed(_item_id: String, _quantity: int) -> void:
	_queue_refresh()


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_do_queued_refresh")


func _do_queued_refresh() -> void:
	_refresh_queued = false
	refresh_orders()


func _on_storage_changed(_changes: Dictionary) -> void:
	refresh_orders()


func _emit_unread_notification(target_type: String, target_id: String) -> void:
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus != null and event_bus.has_signal("economy_ui_notification_added"):
		event_bus.emit_signal("economy_ui_notification_added", target_type, target_id)
