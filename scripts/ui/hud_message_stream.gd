class_name HudMessageStream
extends PanelContainer

signal history_requested

const HudMessageBusScript := preload("res://scripts/ui/hud_message_bus.gd")
const COLLAPSED_HEIGHT := 62.0
const CARD_BACKGROUND := Color(0.055, 0.075, 0.06, 0.60)
const SEVERITY_COLORS := {
	"info": Color(0.49, 0.76, 0.93, 1.0),
	"success": Color(0.45, 0.86, 0.55, 1.0),
	"warning": Color(0.96, 0.72, 0.30, 1.0),
	"error": Color(0.96, 0.38, 0.34, 1.0),
	"debug": Color(0.76, 0.64, 0.94, 1.0),
}

@onready var title_label: Label = $Margin/Content/Header/TitleLabel
@onready var unread_label: Label = $Margin/Content/Header/UnreadLabel
@onready var toggle_button: Button = $Margin/Content/Header/ToggleButton
@onready var message_scroll: ScrollContainer = $Margin/Content/MessageScroll
@onready var message_list: VBoxContainer = $Margin/Content/MessageScroll/MessageList
@onready var footer: HBoxContainer = $Margin/Content/Footer
@onready var history_button: Button = $Margin/Content/Footer/HistoryButton
@onready var return_latest_button: Button = $Margin/Content/Footer/ReturnLatestButton

var _bus: Node
var _collapsed := false
var _following_latest := true
var _unread_count := 0
var _cards_by_id: Dictionary = {}
var _expanded_bottom := 632.0
var _adjusting_scroll := false


func _ready() -> void:
	if not toggle_button.pressed.is_connected(_on_toggle_pressed):
		toggle_button.pressed.connect(_on_toggle_pressed)
	if not history_button.pressed.is_connected(_on_history_pressed):
		history_button.pressed.connect(_on_history_pressed)
	if not return_latest_button.pressed.is_connected(return_to_latest):
		return_latest_button.pressed.connect(return_to_latest)
	var scroll_bar := message_scroll.get_v_scroll_bar()
	if not scroll_bar.value_changed.is_connected(_on_scroll_value_changed):
		scroll_bar.value_changed.connect(_on_scroll_value_changed)
	_refresh_state()


func configure(bus: Node) -> bool:
	if bus == null or not is_instance_valid(bus) or bus.get_script() != HudMessageBusScript:
		return false
	_disconnect_bus()
	_bus = bus
	var added := Callable(self, "_on_message_added")
	var updated := Callable(self, "_on_message_updated")
	if not _bus.message_added.is_connected(added):
		_bus.message_added.connect(added)
	if not _bus.message_updated.is_connected(updated):
		_bus.message_updated.connect(updated)
	_rebuild_cards(_bus.get_recent())
	return true


func set_collapsed(value: bool) -> void:
	if _collapsed == value:
		_refresh_state()
		return
	if value:
		_expanded_bottom = offset_bottom
	_collapsed = value
	if not _collapsed:
		_unread_count = 0
		_following_latest = true
		_scroll_to_latest_deferred()
	_refresh_state()


func is_collapsed() -> bool:
	return _collapsed


func set_following_latest(value: bool) -> void:
	_following_latest = value
	if value:
		return_to_latest()
	else:
		_refresh_state()


func return_to_latest() -> void:
	_following_latest = true
	_unread_count = 0
	_scroll_to_latest_deferred()
	_refresh_state()


func get_unread_count() -> int:
	return _unread_count


func get_message_card_count() -> int:
	return _cards_by_id.size()


func get_collapsed_header_height() -> float:
	return COLLAPSED_HEIGHT


func set_expanded_bottom(value: float) -> void:
	_expanded_bottom = maxf(value, offset_top + 260.0)
	_refresh_state()


func get_message_ids() -> Array[String]:
	var result: Array[String] = []
	for child in message_list.get_children():
		if child.has_meta("message_id"):
			result.append(str(child.get_meta("message_id")))
	return result


func get_last_card_count() -> int:
	if message_list.get_child_count() == 0:
		return 0
	return int(message_list.get_child(-1).get_meta("message_count", 1))


func is_return_latest_visible() -> bool:
	return return_latest_button.visible


func _on_message_added(record: Dictionary) -> void:
	_add_card(record)
	if _collapsed or not _following_latest:
		_unread_count += 1
	else:
		_scroll_to_latest_deferred()
	_refresh_state()


func _on_message_updated(record: Dictionary) -> void:
	var message_id := str(record.get("message_id", ""))
	var card := _cards_by_id.get(message_id) as PanelContainer
	if card == null:
		_add_card(record)
		return
	_update_card(card, record)


func _rebuild_cards(records: Array[Dictionary]) -> void:
	for child in message_list.get_children():
		message_list.remove_child(child)
		child.queue_free()
	_cards_by_id.clear()
	for record in records:
		_add_card(record)
	_scroll_to_latest_deferred()


func _add_card(record: Dictionary) -> void:
	var message_id := str(record.get("message_id", ""))
	if message_id.is_empty() or _cards_by_id.has(message_id):
		return
	var card := PanelContainer.new()
	card.set_meta("message_id", message_id)
	card.custom_minimum_size = Vector2(0.0, 58.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = CARD_BACKGROUND
	background.corner_radius_top_left = 6
	background.corner_radius_top_right = 6
	background.corner_radius_bottom_left = 6
	background.corner_radius_bottom_right = 6
	card.add_theme_stylebox_override("panel", background)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var strip := ColorRect.new()
	strip.name = "SeverityStrip"
	strip.custom_minimum_size = Vector2(4.0, 0.0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(strip)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_bottom", 7)
	row.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	margin.add_child(content)
	var text_label := Label.new()
	text_label.name = "MessageText"
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 16)
	text_label.add_theme_color_override("font_color", Color(0.96, 0.97, 0.91, 1.0))
	text_label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.02, 0.9))
	text_label.add_theme_constant_override("outline_size", 3)
	content.add_child(text_label)
	var meta_label := Label.new()
	meta_label.name = "MessageMeta"
	meta_label.add_theme_font_size_override("font_size", 13)
	meta_label.add_theme_color_override("font_color", Color(0.72, 0.77, 0.68, 1.0))
	content.add_child(meta_label)
	message_list.add_child(card)
	_cards_by_id[message_id] = card
	_update_card(card, record)


func _update_card(card: PanelContainer, record: Dictionary) -> void:
	var row := card.get_child(0) as HBoxContainer
	var strip := row.get_child(0) as ColorRect
	var margin := row.get_child(1) as MarginContainer
	var content := margin.get_child(0) as VBoxContainer
	var text_label := content.get_child(0) as Label
	var meta_label := content.get_child(1) as Label
	var count := int(record.get("count", 1))
	text_label.text = "%s%s" % [str(record.get("text", "")), "  ×%d" % count if count > 1 else ""]
	var game_time := str(record.get("game_time", ""))
	meta_label.text = "%s%s" % [str(record.get("source", "")).to_upper(), " · %s" % game_time if not game_time.is_empty() else ""]
	strip.color = SEVERITY_COLORS.get(str(record.get("severity", "info")), SEVERITY_COLORS["info"])
	card.set_meta("message_count", count)


func _refresh_state() -> void:
	if not is_node_ready():
		return
	message_scroll.visible = not _collapsed
	footer.visible = not _collapsed
	return_latest_button.visible = not _following_latest or _unread_count > 0
	unread_label.visible = _unread_count > 0
	unread_label.text = "%d 条新消息" % _unread_count
	toggle_button.text = "▼" if _collapsed else "▲"
	toggle_button.tooltip_text = "展开消息" if _collapsed else "向上收起"
	if _collapsed:
		offset_bottom = offset_top + COLLAPSED_HEIGHT
	else:
		offset_bottom = maxf(_expanded_bottom, offset_top + 320.0)


func _scroll_to_latest_deferred() -> void:
	if not is_node_ready():
		return
	_adjusting_scroll = true
	call_deferred("_scroll_to_latest")


func _scroll_to_latest() -> void:
	if not is_node_ready():
		return
	var scroll_bar := message_scroll.get_v_scroll_bar()
	message_scroll.scroll_vertical = int(scroll_bar.max_value)
	_adjusting_scroll = false


func _on_scroll_value_changed(value: float) -> void:
	if _adjusting_scroll or _collapsed:
		return
	var scroll_bar := message_scroll.get_v_scroll_bar()
	var at_latest := value >= scroll_bar.max_value - scroll_bar.page - 2.0
	if at_latest:
		_following_latest = true
		_unread_count = 0
	elif message_list.size.y > message_scroll.size.y:
		_following_latest = false
	_refresh_state()


func _on_toggle_pressed() -> void:
	set_collapsed(not _collapsed)


func _on_history_pressed() -> void:
	history_requested.emit()


func _disconnect_bus() -> void:
	if _bus == null or not is_instance_valid(_bus):
		_bus = null
		return
	var added := Callable(self, "_on_message_added")
	var updated := Callable(self, "_on_message_updated")
	if _bus.message_added.is_connected(added):
		_bus.message_added.disconnect(added)
	if _bus.message_updated.is_connected(updated):
		_bus.message_updated.disconnect(updated)
	_bus = null


func _exit_tree() -> void:
	_disconnect_bus()
