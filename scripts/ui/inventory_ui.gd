class_name InventoryUI
extends Control

## 背包与中央农场仓库界面。

const GameDataScript = preload("res://scripts/core/game_data.gd")
const PLANTING_QUICK_SLOT := 5
const TAB_BACKPACK := &"backpack"
const TAB_FARM_STORAGE := &"farm_storage"
const STORAGE_SORT_NAME := &"name"
const STORAGE_SORT_QUANTITY := &"quantity"
const STORAGE_WARNING_COLOR := Color("#B65C4B")
const PANEL_MAX_SIZE := Vector2(760.0, 560.0)
const VIEWPORT_MARGIN := Vector2(20.0, 20.0)

@export var panel_path: NodePath
@export var grid_container_path: NodePath
@export var quick_bar_path: NodePath
@export var tab_bar_path: NodePath
@export var backpack_content_path: NodePath
@export var storage_content_path: NodePath
@export var storage_capacity_path: NodePath
@export var storage_warning_path: NodePath
@export var storage_sort_path: NodePath
@export var storage_rows_path: NodePath

var grid_container: GridContainer
var panel: PanelContainer
var inventory_grid: GridContainer
var quick_bar: HBoxContainer
var tab_bar: TabBar
var backpack_content: Control
var storage_content: Control
var storage_capacity_label: Label
var storage_warning_label: Label
var storage_sort: OptionButton
var storage_rows: VBoxContainer
var inventory_ref: InventorySystem
var farm_storage_ref: FarmStorageSystem

var _is_open := false
var _selected_tab := TAB_BACKPACK
var _storage_sort_mode := STORAGE_SORT_NAME
var _storage_fallback_icon: Texture2D


func _ready() -> void:
	visible = false
	_resolve_nodes()
	_configure_tabs()
	_configure_storage_sort()
	_connect_backpack_events()
	_connect_storage_events()
	var viewport := get_viewport()
	if viewport != null:
		var viewport_callback := Callable(self, "_on_viewport_size_changed")
		if not viewport.size_changed.is_connected(viewport_callback):
			viewport.size_changed.connect(viewport_callback)
		apply_responsive_layout(Vector2(viewport.size))
	_sync_tab_visibility()
	_refresh_backpack()
	_refresh_storage()


func configure(inv: InventorySystem, farm_storage: FarmStorageSystem = null) -> bool:
	if inv == null:
		return false
	_disconnect_storage_events()
	inventory_ref = inv
	farm_storage_ref = farm_storage
	_connect_storage_events()
	_refresh_backpack()
	_refresh_storage()
	return true


func select_tab(tab_id: StringName) -> bool:
	if tab_id != TAB_BACKPACK and tab_id != TAB_FARM_STORAGE:
		return false
	_selected_tab = tab_id
	if tab_bar != null:
		var next_index := 0 if tab_id == TAB_BACKPACK else 1
		if tab_bar.current_tab != next_index:
			tab_bar.current_tab = next_index
	_sync_tab_visibility()
	return true


func get_selected_tab() -> StringName:
	return _selected_tab


func apply_responsive_layout(viewport_size: Vector2) -> void:
	if panel == null:
		return
	var available := Vector2(
		maxf(1.0, viewport_size.x - VIEWPORT_MARGIN.x * 2.0),
		maxf(1.0, viewport_size.y - VIEWPORT_MARGIN.y * 2.0)
	)
	var panel_size := Vector2(
		minf(PANEL_MAX_SIZE.x, available.x),
		minf(PANEL_MAX_SIZE.y, available.y)
	)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -panel_size.x * 0.5
	panel.offset_top = -panel_size.y * 0.5
	panel.offset_right = panel_size.x * 0.5
	panel.offset_bottom = panel_size.y * 0.5


func _resolve_nodes() -> void:
	panel = _node_at(panel_path) as PanelContainer
	grid_container = _node_at(grid_container_path) as GridContainer
	if grid_container == null:
		grid_container = _find_grid_container()
	quick_bar = _node_at(quick_bar_path) as HBoxContainer
	if quick_bar == null:
		quick_bar = _find_quick_bar()
	tab_bar = _node_at(tab_bar_path) as TabBar
	backpack_content = _node_at(backpack_content_path) as Control
	storage_content = _node_at(storage_content_path) as Control
	storage_capacity_label = _node_at(storage_capacity_path) as Label
	storage_warning_label = _node_at(storage_warning_path) as Label
	storage_sort = _node_at(storage_sort_path) as OptionButton
	storage_rows = _node_at(storage_rows_path) as VBoxContainer
	if grid_container == null:
		grid_container = GridContainer.new()
		grid_container.columns = 5
		add_child(grid_container)
	if quick_bar == null:
		quick_bar = HBoxContainer.new()
		add_child(quick_bar)
	inventory_grid = grid_container


func _node_at(path: NodePath) -> Node:
	return get_node_or_null(path) if not path.is_empty() else null


func _configure_tabs() -> void:
	if tab_bar == null:
		return
	tab_bar.clear_tabs()
	tab_bar.add_tab("背包")
	tab_bar.set_tab_tooltip(0, "背包")
	tab_bar.add_tab("农场仓库")
	tab_bar.set_tab_tooltip(1, "农场仓库")
	var callback := Callable(self, "_on_tab_changed")
	if not tab_bar.tab_changed.is_connected(callback):
		tab_bar.tab_changed.connect(callback)
	tab_bar.current_tab = 0 if _selected_tab == TAB_BACKPACK else 1


func _configure_storage_sort() -> void:
	if storage_sort == null:
		return
	storage_sort.clear()
	storage_sort.add_item("名称", 0)
	storage_sort.set_item_metadata(0, STORAGE_SORT_NAME)
	storage_sort.add_item("数量", 1)
	storage_sort.set_item_metadata(1, STORAGE_SORT_QUANTITY)
	var callback := Callable(self, "_on_storage_sort_selected")
	if not storage_sort.item_selected.is_connected(callback):
		storage_sort.item_selected.connect(callback)
	storage_sort.select(0 if _storage_sort_mode == STORAGE_SORT_NAME else 1)


func _connect_backpack_events() -> void:
	var event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus == null:
		return
	var callback := Callable(self, "_on_inventory_changed")
	if not event_bus.item_added.is_connected(callback):
		event_bus.item_added.connect(callback)
	if not event_bus.item_removed.is_connected(callback):
		event_bus.item_removed.connect(callback)


func _connect_storage_events() -> void:
	if not is_instance_valid(farm_storage_ref):
		return
	var contents_callback := Callable(self, "_on_storage_contents_changed")
	var capacity_callback := Callable(self, "_on_storage_capacity_changed")
	if not farm_storage_ref.contents_changed.is_connected(contents_callback):
		farm_storage_ref.contents_changed.connect(contents_callback)
	if not farm_storage_ref.capacity_changed.is_connected(capacity_callback):
		farm_storage_ref.capacity_changed.connect(capacity_callback)


func _disconnect_storage_events() -> void:
	if not is_instance_valid(farm_storage_ref):
		return
	var contents_callback := Callable(self, "_on_storage_contents_changed")
	var capacity_callback := Callable(self, "_on_storage_capacity_changed")
	if farm_storage_ref.contents_changed.is_connected(contents_callback):
		farm_storage_ref.contents_changed.disconnect(contents_callback)
	if farm_storage_ref.capacity_changed.is_connected(capacity_callback):
		farm_storage_ref.capacity_changed.disconnect(capacity_callback)


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
	_sync_tab_visibility()
	_refresh_backpack()
	_refresh_storage()


func close() -> void:
	_is_open = false
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and _is_open:
		close()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_TAB or event.keycode == KEY_I:
		toggle()
		get_viewport().set_input_as_handled()


func _sync_tab_visibility() -> void:
	if backpack_content != null:
		backpack_content.visible = _selected_tab == TAB_BACKPACK
	if storage_content != null:
		storage_content.visible = _selected_tab == TAB_FARM_STORAGE


func _refresh() -> void:
	_refresh_backpack()
	_refresh_storage()


func _refresh_backpack() -> void:
	if inventory_ref == null:
		return
	if grid_container:
		for child in grid_container.get_children():
			child.free()
		for index in range(inventory_ref.max_slots):
			grid_container.add_child(_create_slot_ui(index))
	_refresh_quick_bar()


func _refresh_quick_bar() -> void:
	if quick_bar == null or inventory_ref == null:
		return
	for child in quick_bar.get_children():
		child.free()
	for index in range(6):
		quick_bar.add_child(_create_quick_slot_ui(index))


func _refresh_storage() -> void:
	_refresh_storage_capacity()
	if storage_rows == null:
		return
	for child in storage_rows.get_children():
		child.free()
	if not is_instance_valid(farm_storage_ref):
		return
	for entry in _storage_entries():
		storage_rows.add_child(_create_storage_row(entry))


func _refresh_storage_capacity() -> void:
	if storage_capacity_label == null or storage_warning_label == null:
		return
	if not is_instance_valid(farm_storage_ref):
		storage_capacity_label.text = "0 / 0"
		storage_warning_label.visible = false
		return
	var used := farm_storage_ref.get_used_capacity()
	var total := farm_storage_ref.get_total_capacity()
	storage_capacity_label.text = "%d / %d" % [used, total]
	storage_warning_label.visible = used > total
	storage_warning_label.text = "仓库超载 %d / %d" % [used, total] if used > total else ""
	storage_warning_label.add_theme_color_override("font_color", STORAGE_WARNING_COLOR)


func _storage_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not is_instance_valid(farm_storage_ref):
		return entries
	for item_id_value in farm_storage_ref.get_items():
		var item_id := str(item_id_value)
		var definition: Variant = GameDataScript.get_item(item_id)
		if not definition is Dictionary:
			continue
		entries.append({
			"item_id": item_id,
			"name": str((definition as Dictionary).get("name", item_id)),
			"quantity": farm_storage_ref.get_count(item_id),
		})
	entries.sort_custom(_compare_storage_entries)
	return entries


func _compare_storage_entries(a: Dictionary, b: Dictionary) -> bool:
	if _storage_sort_mode == STORAGE_SORT_QUANTITY:
		var a_quantity := int(a.get("quantity", 0))
		var b_quantity := int(b.get("quantity", 0))
		if a_quantity != b_quantity:
			return a_quantity > b_quantity
	var a_name := str(a.get("name", a.get("item_id", "")))
	var b_name := str(b.get("name", b.get("item_id", "")))
	if a_name != b_name:
		return a_name < b_name
	return str(a.get("item_id", "")) < str(b.get("item_id", ""))


func _create_storage_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CropRow_%s" % str(entry.get("item_id", ""))
	row.custom_minimum_size = Vector2(0.0, 42.0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_meta("item_id", str(entry.get("item_id", "")))
	row.add_theme_constant_override("separation", 10)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(32.0, 32.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = _storage_icon(str(entry.get("item_id", "")))
	row.add_child(icon)
	var text_label := Label.new()
	text_label.name = "Text"
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.text = "%s    x%d" % [str(entry.get("name", "")), int(entry.get("quantity", 0))]
	text_label.add_theme_color_override("font_color", Color("#513B2F"))
	text_label.add_theme_font_size_override("font_size", 18)
	row.add_child(text_label)
	return row


func _storage_icon(item_id: String) -> Texture2D:
	var path := "res://assets/crops/%s/painted/stage_3/variant_0_front.png" % item_id
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if _storage_fallback_icon == null:
		_storage_fallback_icon = _create_storage_fallback_icon()
	return _storage_fallback_icon


func _create_storage_fallback_icon() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(32):
		for x in range(32):
			var stem := absf(float(x) - 15.5) <= 1.0 and y >= 11 and y <= 27
			var left_leaf := (
				pow((float(x) - 10.5) / 7.5, 2.0)
				+ pow((float(y) - 13.0) / 5.5, 2.0)
				<= 1.0
			)
			var right_leaf := (
				pow((float(x) - 21.0) / 7.5, 2.0)
				+ pow((float(y) - 9.5) / 5.5, 2.0)
				<= 1.0
			)
			if stem:
				image.set_pixel(x, y, Color("#567A43"))
			elif left_leaf or right_leaf:
				image.set_pixel(x, y, Color("#79A85D"))
	return ImageTexture.create_from_image(image)


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
		_refresh_backpack()


func _on_storage_contents_changed(_changes: Dictionary) -> void:
	if _is_open:
		_refresh_storage()


func _on_storage_capacity_changed(_used: int, _total: int) -> void:
	if _is_open:
		_refresh_storage_capacity()


func _on_tab_changed(tab_index: int) -> void:
	select_tab(TAB_BACKPACK if tab_index == 0 else TAB_FARM_STORAGE)


func _on_storage_sort_selected(index: int) -> void:
	if storage_sort == null or index < 0 or index >= storage_sort.item_count:
		return
	_storage_sort_mode = StringName(storage_sort.get_item_metadata(index))
	_refresh_storage()


func _on_viewport_size_changed() -> void:
	apply_responsive_layout(Vector2(get_viewport().size))
