class_name EconomyNotificationUI
extends Control

const MAX_VISIBLE_TOASTS := 3
const ORDINARY_TIMEOUT := 3.0
const URGENT_TIMEOUT := 6.0

@onready var toast_stack: VBoxContainer = $ToastStack
@onready var notification_center: PanelContainer = $NotificationCenter
@onready var unread_label: Label = $NotificationCenter/Margin/VBox/Header/UnreadLabel
@onready var close_button: Button = $NotificationCenter/Margin/VBox/Header/CloseButton
@onready var record_list: VBoxContainer = $NotificationCenter/Margin/VBox/Scroll/RecordList
@onready var mark_all_button: Button = $NotificationCenter/Margin/VBox/MarkAllReadButton

var _system: EconomyNotificationSystem
var _router: Variant
var _toasts: Dictionary = {}
var _toast_order: Array[String] = []
var _activating_notification_ids: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notification_center.visible = false
	if not close_button.pressed.is_connected(hide_center):
		close_button.pressed.connect(hide_center)
	if not mark_all_button.pressed.is_connected(mark_all_read):
		mark_all_button.pressed.connect(mark_all_read)
	if _system != null:
		_refresh_center()


func configure(system: EconomyNotificationSystem, router: Variant = null) -> bool:
	if system == null or not is_instance_valid(system):
		return false
	_disconnect_system()
	_clear_toasts()
	_activating_notification_ids.clear()
	_system = system
	_router = router
	var pushed_callback := Callable(self, "_on_notification_pushed")
	var changed_callback := Callable(self, "_on_notifications_changed")
	if not _system.notification_pushed.is_connected(pushed_callback):
		_system.notification_pushed.connect(pushed_callback)
	if not _system.notifications_changed.is_connected(changed_callback):
		_system.notifications_changed.connect(changed_callback)
	_refresh_center()
	return true


func show_center() -> void:
	_refresh_center()
	notification_center.visible = true


func hide_center() -> void:
	notification_center.visible = false


func toggle_center() -> void:
	if notification_center.visible:
		hide_center()
	else:
		show_center()


func mark_all_read() -> void:
	if _system != null:
		_system.mark_all_read()


func activate_notification(notification_id: String) -> bool:
	if _system == null or _activating_notification_ids.has(notification_id):
		return false
	var record := _record_for_id(notification_id)
	if record.is_empty() or not bool(record.get("unread", false)):
		return false
	var target_type := str(record.get("target_type", ""))
	var target_id := str(record.get("target_id", ""))
	var route_method := ""
	if not target_type.is_empty():
		if _router != null and _router.has_method("navigate_economy_target"):
			route_method = "navigate_economy_target"
		elif _router != null and _router.has_method("navigate_notification_target"):
			route_method = "navigate_notification_target"
		else:
			return false
	_activating_notification_ids[notification_id] = true
	var activated := false
	if target_type.is_empty():
		activated = _system.mark_read(notification_id)
	elif bool(_router.call(route_method, target_type, target_id)):
		hide_center()
		activated = _system.mark_read(notification_id)
	_activating_notification_ids.erase(notification_id)
	return activated


func advance_toasts(delta: float) -> void:
	if delta <= 0.0:
		return
	for notification_id in _toast_order.duplicate():
		if not _toasts.has(notification_id):
			continue
		var toast: Dictionary = _toasts[notification_id]
		if bool(toast.get("hovered", false)):
			continue
		toast["remaining"] = float(toast.get("remaining", 0.0)) - delta
		_toasts[notification_id] = toast
		if float(toast.remaining) <= 0.000001:
			_remove_toast(notification_id)


func set_toast_hovered(notification_id: String, hovered: bool) -> void:
	if not _toasts.has(notification_id):
		return
	var toast: Dictionary = _toasts[notification_id]
	toast["hovered"] = hovered
	_toasts[notification_id] = toast


func has_toast(notification_id: String) -> bool:
	return _toasts.has(notification_id)


func get_visible_toast_count() -> int:
	return _toasts.size()


func get_center_record_count() -> int:
	var result := 0
	if record_list != null:
		for child in record_list.get_children():
			if child is PanelContainer:
				result += 1
	return result


func get_center_day_group_count() -> int:
	var result := 0
	if record_list != null:
		for child in record_list.get_children():
			if child is Label and child.has_meta("day_header"):
				result += 1
	return result


func _process(delta: float) -> void:
	advance_toasts(delta)


func _on_notification_pushed(record: Dictionary, merged: bool) -> void:
	var notification_id := str(record.get("notification_id", ""))
	if notification_id.is_empty():
		return
	if merged and _toasts.has(notification_id):
		var toast: Dictionary = _toasts[notification_id]
		var card := toast.get("card") as PanelContainer
		if card != null:
			_update_card(card, record)
		toast["remaining"] = _timeout_for(record)
		_toasts[notification_id] = toast
	else:
		_add_toast(record)
	_refresh_center()


func _on_notifications_changed() -> void:
	_refresh_center()
	for notification_id in _toast_order.duplicate():
		var record := _record_for_id(notification_id)
		if record.is_empty():
			_remove_toast(notification_id)
		elif _toasts.has(notification_id):
			var card := (_toasts[notification_id] as Dictionary).get("card") as PanelContainer
			if card != null:
				_update_card(card, record)


func _add_toast(record: Dictionary) -> void:
	while _toast_order.size() >= MAX_VISIBLE_TOASTS:
		_remove_toast(_toast_order[0])
	var notification_id := str(record.notification_id)
	var card := _create_card(record, true)
	toast_stack.add_child(card)
	_toast_order.append(notification_id)
	_toasts[notification_id] = {
		"card": card,
		"remaining": _timeout_for(record),
		"hovered": false,
	}


func _create_card(record: Dictionary, toast: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"EconomyCard"
	card.custom_minimum_size = Vector2(330.0, 72.0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS if toast else Control.MOUSE_FILTER_STOP
	card.set_meta("notification_id", str(record.notification_id))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(content)
	var title := Label.new()
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 18)
	content.add_child(title)
	var body := Label.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(body)
	_update_card(card, record)
	card.gui_input.connect(_on_card_gui_input.bind(str(record.notification_id)))
	if toast:
		card.mouse_entered.connect(set_toast_hovered.bind(str(record.notification_id), true))
		card.mouse_exited.connect(set_toast_hovered.bind(str(record.notification_id), false))
	return card


func _update_card(card: PanelContainer, record: Dictionary) -> void:
	var title := card.get_node_or_null("MarginContainer/VBoxContainer/Title") as Label
	var body := card.get_node_or_null("MarginContainer/VBoxContainer/Body") as Label
	# Programmatically-created nodes keep automatic class names.
	if title == null or body == null:
		var margin := card.get_child(0) as MarginContainer
		var content := margin.get_child(0) as VBoxContainer if margin != null else null
		if content != null and content.get_child_count() >= 2:
			title = content.get_child(0) as Label
			body = content.get_child(1) as Label
	if title != null:
		title.text = "%s%s" % ["● " if bool(record.get("unread", false)) else "", str(record.get("title", ""))]
	if body != null:
		var count := int(record.get("count", 1))
		body.text = "%s%s" % [str(record.get("body", "")), "　×%d" % count if count > 1 else ""]


func _remove_toast(notification_id: String) -> void:
	if not _toasts.has(notification_id):
		return
	var card := (_toasts[notification_id] as Dictionary).get("card") as PanelContainer
	_toasts.erase(notification_id)
	_toast_order.erase(notification_id)
	if card != null and is_instance_valid(card):
		card.free()


func _clear_toasts() -> void:
	for notification_id in _toast_order.duplicate():
		_remove_toast(notification_id)


func _refresh_center() -> void:
	if record_list == null:
		return
	for child in record_list.get_children():
		record_list.remove_child(child)
		child.queue_free()
	var records: Array[Dictionary] = _system.get_recent() if _system != null else []
	if unread_label != null:
		unread_label.text = "未读 %d" % (_system.get_unread_count() if _system != null else 0)
	var previous_day := -1
	for record in records:
		var day := int(record.get("total_day", 0))
		if day != previous_day:
			var header := Label.new()
			header.set_meta("day_header", true)
			header.text = "第 %d 天" % day
			header.add_theme_font_size_override("font_size", 18)
			record_list.add_child(header)
			previous_day = day
		record_list.add_child(_create_card(record, false))


func _record_for_id(notification_id: String) -> Dictionary:
	if _system == null:
		return {}
	for record in _system.get_recent():
		if str(record.notification_id) == notification_id:
			return record
	return {}


func _timeout_for(record: Dictionary) -> float:
	return URGENT_TIMEOUT if EconomyNotificationSystem.is_urgent_kind(str(record.get("kind", ""))) else ORDINARY_TIMEOUT


func _on_card_gui_input(event: InputEvent, notification_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activate_notification(notification_id)


func _disconnect_system() -> void:
	if _system == null or not is_instance_valid(_system):
		_system = null
		return
	var pushed_callback := Callable(self, "_on_notification_pushed")
	var changed_callback := Callable(self, "_on_notifications_changed")
	if _system.notification_pushed.is_connected(pushed_callback):
		_system.notification_pushed.disconnect(pushed_callback)
	if _system.notifications_changed.is_connected(changed_callback):
		_system.notifications_changed.disconnect(changed_callback)
	_system = null


func _exit_tree() -> void:
	_disconnect_system()
