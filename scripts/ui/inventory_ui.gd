class_name InventoryUI
extends Control

## 背包界面 - 网格布局显示背包物品和快捷栏

const GameDataScript = preload("res://scripts/core/game_data.gd")
const PLANTING_QUICK_SLOT := 5

@export var grid_container_path: NodePath
@export var quick_bar_path: NodePath

var grid_container: GridContainer
var inventory_grid: GridContainer
var quick_bar: HBoxContainer
var inventory_ref: InventorySystem

var _is_open := false


func _ready() -> void:
	visible = false
	grid_container = get_node_or_null(grid_container_path) if grid_container_path else _find_grid_container()
	quick_bar = get_node_or_null(quick_bar_path) if quick_bar_path else _find_quick_bar()
	if grid_container == null:
		grid_container = GridContainer.new()
		grid_container.columns = 5
		add_child(grid_container)
	if quick_bar == null:
		quick_bar = HBoxContainer.new()
		add_child(quick_bar)
	inventory_grid = grid_container

	# 连接 EventBus
	var event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus:
		event_bus.item_added.connect(_on_inventory_changed)
		event_bus.item_removed.connect(_on_inventory_changed)
	_refresh()


func configure(inv: InventorySystem) -> void:
	inventory_ref = inv
	_refresh()


func _find_grid_container() -> GridContainer:
	for child in _get_all_children(self):
		if child is GridContainer:
			return child
	return null


func _find_quick_bar() -> HBoxContainer:
	for child in _get_all_children(self):
		if child is HBoxContainer:
			return child
	return null


func _get_all_children(node: Node) -> Array:
	var result := []
	for child in node.get_children():
		result.append(child)
		result.append_array(_get_all_children(child))
	return result


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	_is_open = true
	visible = true
	_refresh()


func close() -> void:
	_is_open = false
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB or event.keycode == KEY_I:
			toggle()
			get_viewport().set_input_as_handled()


func _refresh() -> void:
	if inventory_ref == null:
		return

	# 刷新背包格子
	if grid_container:
		# 清除旧格子
		for child in grid_container.get_children():
			child.free()

		# 创建格子
		for i in range(inventory_ref.max_slots):
			var slot_ui = _create_slot_ui(i)
			grid_container.add_child(slot_ui)

	_refresh_quick_bar()


func _refresh_quick_bar() -> void:
	if quick_bar:
		for child in quick_bar.get_children():
			child.free()

		for i in range(6):
			var slot_ui = _create_quick_slot_ui(i)
			quick_bar.add_child(slot_ui)


func assign_planting_slot(slot_index: int) -> bool:
	if inventory_ref == null or slot_index < 0 or slot_index >= inventory_ref.slots.size():
		return false
	var slot: Dictionary = inventory_ref.slots[slot_index]
	if slot.is_empty() or int(slot.get("quantity", 0)) <= 0:
		return false
	var item_id := str(slot.get("item_id", ""))
	if not _is_planting_item(item_id):
		return false
	if not inventory_ref.set_quick_slot(slot_index, PLANTING_QUICK_SLOT):
		return false
	_refresh_quick_bar()
	return true


func _is_planting_item(item_id: String) -> bool:
	var item_data = GameDataScript.get_item(item_id)
	return (
		item_data != null
		and str(item_data.get("id", "")) == item_id
		and str(item_data.get("category", "")) == "seed"
		and (item_id.ends_with("_seed") or item_id.ends_with("_sapling"))
	)


func _create_slot_ui(index: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(64, 64)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if index < inventory_ref.slots.size() and not inventory_ref.slots[index].is_empty():
		var slot = inventory_ref.slots[index]
		var item_data = GameDataScript.get_item(slot.item_id)
		if _is_planting_item(str(slot.item_id)):
			panel.tooltip_text = "左键：设为种植栏（快捷栏 6）"
		var name_label = Label.new()
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.text = item_data.name if item_data else slot.item_id
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 10)

		var qty_label = Label.new()
		qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		qty_label.text = "x%d" % slot.quantity
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qty_label.add_theme_font_size_override("font_size", 12)

		vbox.add_child(name_label)
		vbox.add_child(qty_label)
	else:
		var empty_label = Label.new()
		empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_label.text = ""
		vbox.add_child(empty_label)

	panel.add_child(vbox)
	panel.gui_input.connect(_on_inventory_slot_gui_input.bind(index))
	return panel


func _on_inventory_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and assign_planting_slot(slot_index)
	):
		accept_event()


func _create_quick_slot_ui(index: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(64, 64)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var num_label = Label.new()
	num_label.text = str(index + 1)
	num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(num_label)

	var item_id = inventory_ref.get_quick_item(index)
	if not item_id.is_empty():
		var item_data = GameDataScript.get_item(item_id)
		var name_label = Label.new()
		name_label.text = item_data.name if item_data else item_id
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 10)
		vbox.add_child(name_label)

	panel.add_child(vbox)
	return panel


func _on_inventory_changed(_item_id: String, _quantity: int) -> void:
	if _is_open:
		_refresh()
