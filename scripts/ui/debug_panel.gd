class_name RuntimeDebugPanel
extends CanvasLayer

signal apply_requested(draft: Dictionary)
signal refresh_requested

const EconomyLimitsScript := preload("res://scripts/core/economy_limits.gd")
const PlayerStateScript := preload("res://scripts/data/player_state.gd")
const PANEL_TEXT_COLOR := Color("513b2f")
const CATEGORY_NAMES := {
	"seed": "种子",
	"crop": "作物",
	"material": "原材料",
	"processed_material": "加工材料",
	"output": "建筑产出",
	"container": "容器",
	"product": "制品",
	"crafted_good": "手工品",
	"rare": "稀有物品",
	"legacy": "旧物品",
	"other": "其他",
}

@onready var title_label: Label = $Overlay/Center/Panel/Layout/Header/Title
@onready var close_button: Button = $Overlay/Center/Panel/Layout/Header/CloseButton
@onready var tabs: TabContainer = $Overlay/Center/Panel/Layout/Tabs
@onready var level_input: SpinBox = $Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Level
@onready var elapsed_days_input: SpinBox = $Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/ElapsedDays
@onready var gold_input: SpinBox = $Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Gold
@onready var stamina_input: SpinBox = $Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Stamina
@onready var search_input: LineEdit = $Overlay/Center/Panel/Layout/Tabs/Inventory/Toolbar/Search
@onready var category_input: OptionButton = $Overlay/Center/Panel/Layout/Tabs/Inventory/Toolbar/Category
@onready var item_rows: VBoxContainer = $Overlay/Center/Panel/Layout/Tabs/Inventory/ItemScroll/ItemRows
@onready var status_label: Label = $Overlay/Center/Panel/Layout/Footer/Status
@onready var refresh_button: Button = $Overlay/Center/Panel/Layout/Footer/RefreshButton
@onready var cancel_button: Button = $Overlay/Center/Panel/Layout/Footer/CancelButton
@onready var apply_button: Button = $Overlay/Center/Panel/Layout/Footer/ApplyButton

var _snapshot: Dictionary = {}
var _item_quantities := {}
var _item_records := {}
var _loading := false
var _configured := false


func _ready() -> void:
	tabs.set_tab_title(0, "角色状态")
	tabs.set_tab_title(1, "资源库存")
	close_button.pressed.connect(close)
	cancel_button.pressed.connect(close)
	apply_button.pressed.connect(_on_apply_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	search_input.text_changed.connect(_on_search_changed)
	category_input.item_selected.connect(_on_category_selected)
	for input in [level_input, elapsed_days_input, gold_input, stamina_input]:
		input.value_changed.connect(_on_state_value_changed)
	visible = false


func configure(snapshot_value: Dictionary) -> bool:
	if not _valid_snapshot(snapshot_value):
		return false
	_configured = true
	refresh_from_snapshot(snapshot_value)
	return true


func open(snapshot_value: Dictionary = {}) -> void:
	if not snapshot_value.is_empty():
		if not _configured:
			configure(snapshot_value)
		else:
			refresh_from_snapshot(snapshot_value)
	if not _configured:
		return
	visible = true
	level_input.get_line_edit().grab_focus()


func close() -> void:
	visible = false


func refresh_from_snapshot(snapshot_value: Dictionary) -> void:
	if not _valid_snapshot(snapshot_value):
		return
	_loading = true
	_snapshot = snapshot_value.duplicate(true)
	level_input.min_value = 1
	level_input.max_value = PlayerStateScript.LEVEL_THRESHOLDS.size()
	level_input.value = int(_snapshot.level)
	elapsed_days_input.min_value = 0
	elapsed_days_input.max_value = EconomyLimitsScript.MAX_SAFE_DATE - 1
	elapsed_days_input.value = int(_snapshot.elapsed_days)
	gold_input.min_value = 0
	gold_input.max_value = EconomyLimitsScript.MAX_SAFE_INTEGER
	gold_input.value = int(_snapshot.gold)
	stamina_input.min_value = 0
	stamina_input.max_value = int(_snapshot.max_stamina)
	stamina_input.value = int(_snapshot.stamina)
	_rebuild_item_rows(_snapshot.items as Dictionary)
	_rebuild_category_filter()
	search_input.text = ""
	title_label.text = "调试数据"
	status_label.text = "当前修改只影响运行状态"
	status_label.add_theme_color_override("font_color", PANEL_TEXT_COLOR)
	_loading = false
	_apply_item_filters()


func build_draft() -> Dictionary:
	if not _configured:
		return {}
	var draft := _snapshot.duplicate(true)
	draft["level"] = roundi(level_input.value)
	draft["elapsed_days"] = roundi(elapsed_days_input.value)
	draft["gold"] = roundi(gold_input.value)
	draft["stamina"] = roundi(stamina_input.value)
	for item_id in _item_quantities:
		if draft.items.has(item_id):
			(draft.items[item_id] as Dictionary)["quantity"] = int(_item_quantities[item_id])
	return draft


func show_apply_result(result: Dictionary, refreshed_snapshot: Dictionary = {}) -> void:
	if bool(result.get("ok", false)):
		if not refreshed_snapshot.is_empty():
			refresh_from_snapshot(refreshed_snapshot)
		status_label.text = str(
			result.get("message", "调试数据已应用；尚未写入存档")
		)
		status_label.add_theme_color_override("font_color", PANEL_TEXT_COLOR)
		return
	status_label.text = _failure_message(result)
	status_label.add_theme_color_override("font_color", Color("b65c4b"))


func get_visible_item_ids() -> Array[String]:
	var result: Array[String] = []
	for child in item_rows.get_children():
		if child is Control and child.visible:
			result.append(str(child.get_meta("item_id", "")))
	return result


func _rebuild_item_rows(records: Dictionary) -> void:
	for child in item_rows.get_children():
		child.free()
	_item_quantities.clear()
	_item_records.clear()
	var item_ids: Array[String] = []
	for item_id_value in records:
		item_ids.append(str(item_id_value))
	item_ids.sort_custom(
		func(left: String, right: String) -> bool:
			var left_record := records[left] as Dictionary
			var right_record := records[right] as Dictionary
			return _item_sort_key(left_record) < _item_sort_key(right_record)
	)
	var max_slots := int(_snapshot.get("max_slots", 20))
	for item_id in item_ids:
		var record := (records[item_id] as Dictionary).duplicate(true)
		_item_records[item_id] = record
		_item_quantities[item_id] = int(record.get("quantity", 0))
		item_rows.add_child(_create_item_row(record, max_slots))


func _create_item_row(record: Dictionary, max_slots: int) -> HBoxContainer:
	var item_id := str(record.get("id", ""))
	var row := HBoxContainer.new()
	row.name = _safe_node_name(item_id)
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 12)
	row.set_meta("item_id", item_id)
	row.set_meta("category", str(record.get("category", "other")))
	row.set_meta(
		"search_text",
		("%s %s" % [record.get("name", item_id), item_id]).to_lower()
	)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.custom_minimum_size.x = 210
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = str(record.get("name", item_id))
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", PANEL_TEXT_COLOR)
	row.add_child(name_label)

	var id_label := Label.new()
	id_label.name = "ItemId"
	id_label.custom_minimum_size.x = 220
	id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_label.text = item_id
	id_label.add_theme_font_size_override("font_size", 15)
	id_label.add_theme_color_override("font_color", Color("7b6758"))
	row.add_child(id_label)

	var quantity := SpinBox.new()
	quantity.name = "Quantity"
	quantity.custom_minimum_size.x = 150
	quantity.min_value = 0
	quantity.max_value = int(record.get("max_stack", 99)) * max_slots
	quantity.step = 1
	quantity.value = int(record.get("quantity", 0))
	quantity.allow_greater = false
	quantity.allow_lesser = false
	quantity.update_on_text_changed = true
	quantity.value_changed.connect(_on_item_quantity_changed.bind(item_id))
	row.add_child(quantity)
	return row


func _rebuild_category_filter() -> void:
	category_input.clear()
	category_input.add_item("全部")
	category_input.set_item_metadata(0, "")
	var categories: Array[String] = []
	for record_value in _item_records.values():
		var category := str((record_value as Dictionary).get("category", "other"))
		if not categories.has(category):
			categories.append(category)
	categories.sort()
	for category in categories:
		category_input.add_item(str(CATEGORY_NAMES.get(category, category)))
		category_input.set_item_metadata(category_input.item_count - 1, category)
	category_input.select(0)


func _apply_item_filters() -> void:
	var query := search_input.text.strip_edges().to_lower()
	var selected_category := ""
	if category_input.selected >= 0:
		selected_category = str(
			category_input.get_item_metadata(category_input.selected)
		)
	for child in item_rows.get_children():
		var matches_search := (
			query.is_empty()
			or str(child.get_meta("search_text", "")).contains(query)
		)
		var matches_category := (
			selected_category.is_empty()
			or str(child.get_meta("category", "")) == selected_category
		)
		child.visible = matches_search and matches_category


func _on_item_quantity_changed(value: float, item_id: String) -> void:
	_item_quantities[item_id] = roundi(value)
	_mark_dirty()


func _on_state_value_changed(_value: float) -> void:
	_mark_dirty()


func _on_search_changed(_text: String) -> void:
	_apply_item_filters()


func _on_category_selected(_index: int) -> void:
	_apply_item_filters()


func _on_apply_pressed() -> void:
	if _configured:
		apply_requested.emit(build_draft())


func _on_refresh_pressed() -> void:
	if _configured:
		refresh_requested.emit()


func _mark_dirty() -> void:
	if _loading or not _configured:
		return
	title_label.text = "调试数据 · 未应用"
	status_label.text = "存在尚未应用的修改"
	status_label.add_theme_color_override("font_color", PANEL_TEXT_COLOR)


func _failure_message(result: Dictionary) -> String:
	match str(result.get("reason", "transaction_failed")):
		"inventory_capacity":
			return "资源需要 %d 个背包槽位，当前只有 %d 个" % [
				int(result.get("required_slots", 0)),
				int(result.get("available_slots", 0)),
			]
		"invalid_level":
			return "等级超出允许范围"
		"invalid_elapsed_days":
			return "已过天数超出允许范围"
		"invalid_gold":
			return "金币数量无效"
		"invalid_stamina":
			return "体力数量无效"
		"invalid_item_quantity":
			return "资源数量无效：%s" % result.get("item_id", "")
		_:
			return "无法应用调试数据，状态已保持不变"


func _valid_snapshot(value: Dictionary) -> bool:
	return (
		value.has("level")
		and value.has("elapsed_days")
		and value.has("gold")
		and value.has("stamina")
		and value.has("max_stamina")
		and value.get("items") is Dictionary
	)


func _item_sort_key(record: Dictionary) -> String:
	return "%s|%s|%s" % [
		str(record.get("category", "")),
		str(record.get("name", "")),
		str(record.get("id", "")),
	]


func _safe_node_name(item_id: String) -> String:
	return "Item_%s" % item_id.replace("/", "_").replace(":", "_")


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
