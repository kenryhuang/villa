class_name SeedSelectorPanel
extends CanvasLayer

const GameDataScript := preload("res://scripts/core/game_data.gd")
const EconomyModalCoordinatorScript := preload("res://scripts/ui/economy_modal_coordinator.gd")
const SEASON_NAMES := ["春", "夏", "秋", "冬"]
const REASON_LABELS := {
	"no_seed": "库存不足",
	"invalid_seed_mapping": "种植资料无效",
	"plot_unavailable": "地块不可播种",
	"wrong_season": "当前季节不适宜",
	"greenhouse_required": "仅限温室",
}

@onready var overlay: ColorRect = $Overlay
@onready var shell: PanelContainer = $Overlay/Center/Shell
@onready var close_button: Button = $Overlay/Center/Shell/Layout/Header/CloseButton
@onready var seed_scroll: ScrollContainer = $Overlay/Center/Shell/Layout/SeedScroll
@onready var seed_rows: VBoxContainer = $Overlay/Center/Shell/Layout/SeedScroll/SeedRows
@onready var empty_label: Label = $Overlay/Center/Shell/Layout/SeedScroll/SeedRows/EmptyLabel
@onready var selection_status: Label = $Overlay/Center/Shell/Layout/Footer/SelectionStatus
@onready var footer_close_button: Button = $Overlay/Center/Shell/Layout/Footer/FooterCloseButton

var inventory_ref: InventorySystem
var farming_ref: FarmingSystem
var action_controller_ref: PlayerActionController
var target_cell: GridCell
var _event_bus: Node
var _fallback_icons: Dictionary = {}
var _modal_coordinator = EconomyModalCoordinatorScript.new()


func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	footer_close_button.pressed.connect(close)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_responsive_layout):
		viewport.size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()


func configure(
	inventory: InventorySystem,
	farming: FarmingSystem,
	action_controller: PlayerActionController
) -> bool:
	if (
		inventory == null
		or farming == null
		or action_controller == null
		or not farming.has_method("preview_plant")
		or not action_controller.has_method("set_selected_plant_item_id")
	):
		return false
	_disconnect_authoritative_signals()
	inventory_ref = inventory
	farming_ref = farming
	action_controller_ref = action_controller
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	_connect_authoritative_signals()
	_refresh()
	return true


func open_for_cell(cell: GridCell = null) -> void:
	if not _modal_coordinator.is_owned_by(self) and not _modal_coordinator.acquire(self):
		return
	target_cell = cell
	_refresh()
	visible = true
	_apply_responsive_layout()
	_focus_first_command.call_deferred()


func close() -> void:
	visible = false
	target_cell = null
	if _modal_coordinator.is_owned_by(self):
		_modal_coordinator.release(self)


func select_seed(plant_item_id: String) -> bool:
	if inventory_ref == null or action_controller_ref == null:
		return false
	var entry := _entry_for(plant_item_id)
	if entry.is_empty() or int(entry.get("quantity", 0)) <= 0:
		return false
	var reason := _disabled_reason(plant_item_id)
	if not reason.is_empty():
		selection_status.text = REASON_LABELS.get(reason, reason)
		return false
	if not action_controller_ref.set_selected_plant_item_id(plant_item_id):
		return false
	_refresh_selection_status()
	close()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if (
		visible
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if seed_rows == null:
		return
	for child in seed_rows.get_children():
		if child != empty_label:
			child.free()
	var entries := _entries()
	empty_label.visible = entries.is_empty()
	for entry in entries:
		seed_rows.add_child(_create_seed_row(entry))
	_refresh_selection_status()


func _entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if inventory_ref == null:
		return result
	var seen := {}
	for slot_value in inventory_ref.slots:
		var slot := slot_value as Dictionary
		var item_id := str(slot.get("item_id", ""))
		if item_id.is_empty() or seen.has(item_id):
			continue
		seen[item_id] = true
		var quantity := inventory_ref.get_item_count(item_id)
		var item_data: Variant = GameDataScript.get_item(item_id)
		var crop := _crop_for(item_id)
		if (
			quantity <= 0
			or not item_data is Dictionary
			or str((item_data as Dictionary).get("category", "")) != "seed"
			or crop == null
		):
			continue
		result.append({
			"plant_item_id": item_id,
			"quantity": quantity,
			"item_data": item_data,
			"crop": crop,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.plant_item_id) < str(b.plant_item_id)
	)
	return result


func _entry_for(plant_item_id: String) -> Dictionary:
	for entry in _entries():
		if str(entry.get("plant_item_id", "")) == plant_item_id:
			return entry
	return {}


func _create_seed_row(entry: Dictionary) -> HBoxContainer:
	var item_id := str(entry.plant_item_id)
	var crop := entry.crop as CropData
	var reason := _disabled_reason(item_id)
	var row := HBoxContainer.new()
	row.name = "Seed_%s" % item_id
	row.custom_minimum_size = Vector2(0, 56)
	row.add_theme_constant_override("separation", 8)
	row.set_meta("plant_item_id", item_id)
	row.set_meta("disabled_reason", reason)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(32, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _seed_icon(crop, item_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	row.add_child(_metadata_label("Name", str(entry.item_data.get("name", crop.name)), 90, true))
	row.add_child(_metadata_label("Quantity", "×%d" % int(entry.quantity), 34))
	row.add_child(_metadata_label("Growth", "%d天" % crop.growth_days, 40))
	row.add_child(_metadata_label("Seasons", _season_text(crop.seasons), 52))
	row.add_child(_metadata_label("Environment", _environment_text(crop.environment), 64))
	var reason_label := _metadata_label(
		"Reason",
		REASON_LABELS.get(reason, reason) if not reason.is_empty() else "可播种",
		90,
		true
	)
	reason_label.add_theme_color_override(
		"font_color",
		Color("#B65C4B") if not reason.is_empty() else Color("#39705A")
	)
	row.add_child(reason_label)

	var select_button := Button.new()
	select_button.name = "SelectButton"
	select_button.custom_minimum_size = Vector2(64, 40)
	select_button.text = "选择"
	select_button.tooltip_text = REASON_LABELS.get(reason, reason) if not reason.is_empty() else "选择此种子"
	select_button.disabled = not reason.is_empty()
	select_button.pressed.connect(select_seed.bind(item_id))
	row.add_child(select_button)
	return row


func _metadata_label(
	label_name: String,
	text_value: String,
	minimum_width: float,
	expand: bool = false
) -> Label:
	var label := Label.new()
	label.name = label_name
	label.custom_minimum_size = Vector2(minimum_width, 40)
	label.text = text_value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = text_value
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _disabled_reason(plant_item_id: String) -> String:
	if inventory_ref == null or inventory_ref.get_item_count(plant_item_id) <= 0:
		return "no_seed"
	if _crop_for(plant_item_id) == null:
		return "invalid_seed_mapping"
	if target_cell == null:
		return ""
	var preview: Variant = farming_ref.preview_plant(target_cell, plant_item_id)
	if not preview is Dictionary:
		return "invalid_seed_mapping"
	return "" if bool((preview as Dictionary).get("ok", false)) else str((preview as Dictionary).get("reason", "invalid_seed_mapping"))


func _crop_for(plant_item_id: String) -> CropData:
	var game_data := get_node_or_null("/root/GameData") if is_inside_tree() else null
	return (
		game_data.get_crop_for_plant_item(plant_item_id)
		if game_data != null and game_data.has_method("get_crop_for_plant_item")
		else null
	)


func _refresh_selection_status() -> void:
	if selection_status == null:
		return
	var selected := (
		action_controller_ref.get_selected_plant_item_id()
		if action_controller_ref != null
		else ""
	)
	if selected.is_empty():
		selection_status.text = "尚未选择种子"
		return
	var item_data: Variant = GameDataScript.get_item(selected)
	var display_name := str((item_data as Dictionary).get("name", selected)) if item_data is Dictionary else selected
	var quantity := inventory_ref.get_item_count(selected) if inventory_ref != null else 0
	selection_status.text = "已选：%s ×%d%s" % [
		display_name,
		quantity,
		"（库存不足）" if quantity <= 0 else "",
	]


func _season_text(seasons: Array[int]) -> String:
	if seasons.is_empty():
		return "温室"
	var names: Array[String] = []
	for season in seasons:
		if season >= 0 and season < SEASON_NAMES.size():
			names.append(SEASON_NAMES[season])
	return "/".join(names)


func _environment_text(environment: String) -> String:
	return "仅温室" if environment == "greenhouse_only" else "户外/温室"


func _seed_icon(crop: CropData, item_id: String) -> Texture2D:
	if crop != null:
		for texture_path in crop.stage_textures:
			if ResourceLoader.exists(texture_path):
				return load(texture_path) as Texture2D
		var conventional := "res://assets/crops/%s/painted/stage_0/variant_0_front.png" % crop.crop_id
		if ResourceLoader.exists(conventional):
			return load(conventional) as Texture2D
	if _fallback_icons.has(item_id):
		return _fallback_icons[item_id] as Texture2D
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var hue := float(absi(item_id.hash()) % 1000) / 1000.0
	var color := Color.from_hsv(hue, 0.46, 0.7, 1.0)
	image.fill_rect(Rect2i(7, 10, 18, 14), color)
	image.fill_rect(Rect2i(11, 6, 10, 20), color.lightened(0.16))
	var texture := ImageTexture.create_from_image(image)
	_fallback_icons[item_id] = texture
	return texture


func _connect_authoritative_signals() -> void:
	if _event_bus != null:
		for signal_name in [&"item_added", &"item_removed"]:
			var callback := Callable(self, "_on_inventory_item_changed")
			if _event_bus.has_signal(signal_name) and not _event_bus.is_connected(signal_name, callback):
				_event_bus.connect(signal_name, callback)
	if action_controller_ref != null:
		var callback := Callable(self, "_on_plant_selection_changed")
		if not action_controller_ref.plant_selection_changed.is_connected(callback):
			action_controller_ref.plant_selection_changed.connect(callback)


func _disconnect_authoritative_signals() -> void:
	if _event_bus != null:
		for signal_name in [&"item_added", &"item_removed"]:
			var callback := Callable(self, "_on_inventory_item_changed")
			if _event_bus.has_signal(signal_name) and _event_bus.is_connected(signal_name, callback):
				_event_bus.disconnect(signal_name, callback)
	if action_controller_ref != null:
		var callback := Callable(self, "_on_plant_selection_changed")
		if action_controller_ref.plant_selection_changed.is_connected(callback):
			action_controller_ref.plant_selection_changed.disconnect(callback)


func _on_inventory_item_changed(item_id: String, _quantity: int) -> void:
	var item_data: Variant = GameDataScript.get_item(item_id)
	if item_data is Dictionary and str((item_data as Dictionary).get("category", "")) == "seed":
		_refresh()


func _on_plant_selection_changed(_plant_item_id: String) -> void:
	_refresh_selection_status()


func _focus_first_command() -> void:
	for row_value in seed_rows.get_children():
		var button := (row_value as Node).get_node_or_null("SelectButton") as Button
		if button != null and not button.disabled:
			button.grab_focus()
			return
	close_button.grab_focus()


func _apply_responsive_layout() -> void:
	if shell == null or get_viewport() == null:
		return
	var viewport_size := Vector2(get_viewport().get_visible_rect().size)
	shell.custom_minimum_size = Vector2(
		minf(820.0, maxf(320.0, viewport_size.x - 32.0)),
		minf(700.0, maxf(420.0, viewport_size.y - 32.0))
	)
