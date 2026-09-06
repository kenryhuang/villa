extends "res://scripts/ui/inventory_ui.gd"

signal target_requested(category: String, target_id: String)

const Icons = preload("res://scripts/farm3d/target_catalog.gd")

func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(false)
	tab_bar.hide()
	quick_bar.hide()
	get_node("Panel/VBox/BackpackContent/QuickTitle").hide()
	get_node("Panel/VBox/Title").text = "背包"
	var scroll := ScrollContainer.new()
	scroll.name = "ItemScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	backpack_content.add_child(scroll)
	backpack_content.move_child(scroll, 0)
	grid_container.reparent(scroll)
	grid_container.columns = 6
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_container.add_theme_constant_override("h_separation", 8)
	grid_container.add_theme_constant_override("v_separation", 8)
	var close_button := Button.new()
	close_button.text = "关闭  ·  Esc / I"
	close_button.custom_minimum_size.y = 36
	close_button.pressed.connect(close)
	get_node("Panel/VBox").add_child(close_button)

func _refresh_quick_bar() -> void:
	pass

func open() -> void:
	super.open()
	# Crops are sorted first. A retained materials/empty-slot scroll position
	# otherwise hides newly harvested items when the backpack is reopened.
	var scroll := grid_container.get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0

func _create_slot_ui(index: int) -> PanelContainer:
	var slot := super._create_slot_ui(index)
	slot.tooltip_text = ""
	slot.custom_minimum_size = Vector2(100, 90)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("e7d9bb")
	style.set_corner_radius_all(6)
	slot.add_theme_stylebox_override("panel", style)
	if index < inventory_ref.slots.size() and not inventory_ref.slots[index].is_empty():
		var item_id: String = inventory_ref.slots[index].item_id
		var box := slot.get_child(0)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = Icons.item_icon(item_id)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
		box.move_child(icon, 0)
		for child in box.get_children():
			if child is Label:
				child.add_theme_font_size_override("font_size", 15)
				child.add_theme_constant_override("outline_size", 0)
				child.add_theme_color_override("font_color", Color("514532"))
	return slot

func _on_inventory_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if slot_index >= inventory_ref.slots.size() or inventory_ref.slots[slot_index].is_empty():
		return
	var item_id: String = inventory_ref.slots[slot_index].item_id
	if _is_planting_item(item_id):
		close()
		target_requested.emit("seed", item_id)
	accept_event()


func _refresh_backpack() -> void:
	if inventory_ref == null or grid_container == null:
		return
	for child in grid_container.get_children():
		child.free()
	var indices: Array = range(inventory_ref.max_slots)
	indices.sort_custom(func(a: int, b: int):
		var left := _item_priority(a)
		var right := _item_priority(b)
		return a < b if left == right else left < right
	)
	for index in indices:
		grid_container.add_child(_create_slot_ui(index))

func _item_priority(index: int) -> int:
	if index >= inventory_ref.slots.size() or inventory_ref.slots[index].is_empty():
		return 3
	var item_id: String = inventory_ref.slots[index].item_id
	if _is_planting_item(item_id):
		return 1
	var item: Variant = GameDataScript.get_item(item_id)
	if item != null and str(item.get("category", "")) in ["crop", "fruit", "flower", "fish"]:
		return 0
	return 2
