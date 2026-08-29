class_name SeedSelectorPanel
extends CanvasLayer

const GameDataScript := preload("res://scripts/core/game_data.gd")
const EconomyModalCoordinatorScript := preload("res://scripts/ui/economy_modal_coordinator.gd")
const SeedCardScene := preload("res://scenes/ui/seed_card.tscn")
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
@onready var seed_rows: GridContainer = $Overlay/Center/Shell/Layout/SeedScroll/SeedRows
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
var _refresh_pending := false
var _refresh_scheduled := false


func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	footer_close_button.pressed.connect(close)
	_event_bus = get_node_or_null("/root/EventBus")
	if is_instance_valid(inventory_ref):
		_connect_authoritative_signals()
		_refresh()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_responsive_layout):
		viewport.size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()


func _enter_tree() -> void:
	_event_bus = get_node_or_null("/root/EventBus")
	_connect_authoritative_signals()


func _exit_tree() -> void:
	_refresh_scheduled = false
	_disconnect_authoritative_signals()


func configure(
	inventory: InventorySystem,
	farming: FarmingSystem,
	action_controller: PlayerActionController
) -> bool:
	if (
		not is_instance_valid(inventory)
		or not is_instance_valid(farming)
		or not is_instance_valid(action_controller)
		or not farming.has_method("preview_plant")
		or not farming.has_method("preview_seed_selection")
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
	_refresh_pending = false
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


func _create_seed_row(entry: Dictionary) -> Control:
	var item_id := str(entry.plant_item_id)
	var crop := entry.crop as CropData
	var reason := _disabled_reason(item_id)
	var available_status := (
		"请选择温室周围的专用种植格"
		if crop.environment == "greenhouse_only"
		else "当前可播种"
	)
	var card := SeedCardScene.instantiate()
	card.name = "Seed_%s" % item_id
	card.configure({
		"plant_item_id": item_id,
		"display_name": str(entry.item_data.get("name", crop.name)),
		"quantity": int(entry.quantity),
		"growth_text": "成熟约 30 秒 · 浇水约 20 秒",
		"season_text": _season_text(crop.seasons),
		"environment_text": _environment_text(crop.environment),
		"status_text": REASON_LABELS.get(reason, reason) if not reason.is_empty() else available_status,
		"disabled": not reason.is_empty(),
		"disabled_reason": reason,
		"icon": _seed_icon(crop, item_id),
	})
	card.set_selected(
		action_controller_ref != null
		and action_controller_ref.get_selected_plant_item_id() == item_id
	)
	card.seed_selected.connect(select_seed)
	return card


func _disabled_reason(plant_item_id: String) -> String:
	if inventory_ref == null or inventory_ref.get_item_count(plant_item_id) <= 0:
		return "no_seed"
	if _crop_for(plant_item_id) == null:
		return "invalid_seed_mapping"
	if target_cell == null:
		var selection_preview: Variant = farming_ref.preview_seed_selection(plant_item_id)
		if not selection_preview is Dictionary:
			return "invalid_seed_mapping"
		return (
			""
			if bool((selection_preview as Dictionary).get("ok", false))
			else str((selection_preview as Dictionary).get("reason", "invalid_seed_mapping"))
		)
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
	return " / ".join(names)


func _environment_text(environment: String) -> String:
	return "仅温室" if environment == "greenhouse_only" else "露天与温室"


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
	if is_instance_valid(_event_bus):
		for signal_name in [&"item_added", &"item_removed"]:
			var callback := Callable(self, "_on_inventory_item_changed")
			if _event_bus.has_signal(signal_name) and not _event_bus.is_connected(signal_name, callback):
				_event_bus.connect(signal_name, callback)
	if is_instance_valid(action_controller_ref):
		var callback := Callable(self, "_on_plant_selection_changed")
		if not action_controller_ref.plant_selection_changed.is_connected(callback):
			action_controller_ref.plant_selection_changed.connect(callback)


func _disconnect_authoritative_signals() -> void:
	if is_instance_valid(_event_bus):
		for signal_name in [&"item_added", &"item_removed"]:
			var callback := Callable(self, "_on_inventory_item_changed")
			if _event_bus.has_signal(signal_name) and _event_bus.is_connected(signal_name, callback):
				_event_bus.disconnect(signal_name, callback)
	if is_instance_valid(action_controller_ref):
		var callback := Callable(self, "_on_plant_selection_changed")
		if action_controller_ref.plant_selection_changed.is_connected(callback):
			action_controller_ref.plant_selection_changed.disconnect(callback)


func _on_inventory_item_changed(item_id: String, _quantity: int) -> void:
	var item_data: Variant = GameDataScript.get_item(item_id)
	if item_data is Dictionary and str((item_data as Dictionary).get("category", "")) == "seed":
		_refresh_pending = true
		if not visible or _refresh_scheduled:
			return
		_refresh_scheduled = true
		_flush_deferred_refresh.call_deferred()


func _flush_deferred_refresh() -> void:
	_refresh_scheduled = false
	if visible and is_inside_tree() and _refresh_pending:
		_refresh()


func _on_plant_selection_changed(_plant_item_id: String) -> void:
	_refresh_selection_status()


func _focus_first_command() -> void:
	for row_value in seed_rows.get_children():
		var button := (row_value as Node).get_node_or_null("Content/SelectButton") as Button
		if button != null and not button.disabled:
			button.grab_focus()
			return
	close_button.grab_focus()


func _apply_responsive_layout() -> void:
	if shell == null or get_viewport() == null:
		return
	var viewport_size := Vector2(get_viewport().get_visible_rect().size)
	seed_rows.columns = 2 if viewport_size.x >= 900.0 else 1
	shell.custom_minimum_size = Vector2(
		minf(900.0, maxf(320.0, viewport_size.x - 32.0)),
		minf(720.0, maxf(420.0, viewport_size.y - 32.0))
	)
