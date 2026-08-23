class_name VillaHud
extends CanvasLayer

## 农庄 HUD - 体力、金币、等级、季节/日期、时间、快捷栏

signal quick_slot_selected(index: int)
signal debug_panel_requested
signal debug_reset_requested
signal market_requested
signal notifications_requested
signal inventory_requested
signal building_unlock_requested(service_id: String)

const GameDataScript = preload("res://scripts/core/game_data.gd")
const ActionPaletteButtonScene = preload(
	"res://scenes/ui/action_palette_button.tscn"
)
const ActionPaletteButtonScript = preload(
	"res://scripts/ui/action_palette_button.gd"
)
const HudMessageBusScript = preload("res://scripts/ui/hud_message_bus.gd")
const ACTION_NAMES := ["锄头", "浇水壶", "斧头", "镐", "鱼竿", "种苗"]
const BUILDING_NAMES := ["谷仓", "温室", "风车", "鸡舍", "蜂箱", "水井", "工作台", "路灯", "围栏"]
const FARMING_ICON_PATHS: Array[String] = [
	"res://assets/ui/action_icons/hoe.png",
	"res://assets/ui/action_icons/watering_can.png",
	"res://assets/ui/action_icons/axe.png",
	"res://assets/ui/action_icons/pickaxe.png",
	"res://assets/ui/action_icons/fishing_rod.png",
	"res://assets/crops/grain/painted/stage_0/variant_0_front.png",
]
const MATERIAL_IDS: Array[String] = ["wood", "stone", "iron", "glass"]
const MATERIAL_NAMES := {
	"wood": "木材",
	"stone": "石头",
	"iron": "铁",
	"glass": "玻璃",
}
const MATERIAL_ICON_PATHS := {
	"wood": "res://assets/ui/material_icons/wood.svg",
	"stone": "res://assets/ui/material_icons/stone.svg",
	"iron": "res://assets/ui/material_icons/iron.svg",
	"glass": "res://assets/ui/material_icons/glass.svg",
}
const COST_AVAILABLE_COLOR := Color(1.0, 0.945, 0.816, 1.0)
const COST_MISSING_COLOR := Color(1.0, 0.48, 0.38, 1.0)

@onready var stamina_bar: ProgressBar = $TopBar/StatusRow/StaminaBar
@onready var gold_label: Label = $TopBar/StatusRow/GoldLabel
@onready var level_label: Label = $TopBar/StatusRow/LevelLabel
@onready var exp_bar: ProgressBar = $TopBar/StatusRow/ExpBar
@onready var season_label: Label = $TopBar/StatusRow/SeasonLabel
@onready var time_label: Label = $TopBar/StatusRow/TimeLabel
@onready var debug_actions: HBoxContainer = $DebugActions
@onready var debug_panel_button: Button = $DebugActions/DebugPanelButton
@onready var debug_reset_button: Button = $DebugActions/DebugResetButton
@onready var market_button: Button = $EconomyActions/MarketButton
@onready var notification_button: Button = $EconomyActions/NotificationButton
@onready var inventory_button: Button = $EconomyActions/InventoryButton
@onready var message_stream: PanelContainer = $MessageStream
@onready var farming_mode_button: Button = $BottomBar/ActionRow/ModeSwitch/FarmingModeButton
@onready var building_mode_button: Button = $BottomBar/ActionRow/ModeSwitch/BuildingModeButton
@onready var quick_bar: HBoxContainer = $BottomBar/ActionRow/QuickBar
@onready var tool_label: Label = $BottomBar/ToolLabel
@onready var build_cost_bar: PanelContainer = $BottomBar/BuildCostBar
@onready var building_cost_label: Label = $BottomBar/BuildCostBar/CostRow/BuildingLabel
@onready var building_costs: HBoxContainer = $BottomBar/BuildCostBar/CostRow/Costs
@onready var build_category_bar: HBoxContainer = $BottomBar/BuildCategoryBar
@onready var build_category_buttons := {
	"basic": $BottomBar/BuildCategoryBar/Basic,
	"production": $BottomBar/BuildCategoryBar/Production,
	"farming": $BottomBar/BuildCategoryBar/Farming,
	"resource": $BottomBar/BuildCategoryBar/Resource,
	"decoration": $BottomBar/BuildCategoryBar/Decoration,
}
@onready var build_lock_panel: PanelContainer = $BuildLockPanel
@onready var build_lock_title: Label = $BuildLockPanel/Content/Title
@onready var build_lock_reason: Label = $BuildLockPanel/Content/Reason
@onready var build_lock_cost: Label = $BuildLockPanel/Content/Cost
@onready var build_lock_unlock_button: Button = $BuildLockPanel/Content/UnlockButton
@onready var build_lock_close_button: Button = $BuildLockPanel/Content/CloseButton
@onready var _material_count_labels := {
	"wood": $MaterialsPanel/MaterialsRow/Wood/Count,
	"stone": $MaterialsPanel/MaterialsRow/Stone/Count,
	"iron": $MaterialsPanel/MaterialsRow/Iron/Count,
	"glass": $MaterialsPanel/MaterialsRow/Glass/Count,
}

var _event_bus
var action_controller: Variant
var inventory_ref: Variant
var economy_ref: Variant
var season_system_ref: Variant
var _economy_ui_unread_count := 0
var notification_ref: EconomyNotificationSystem
var message_bus: Node
var _build_lock_service_id := ""
var _seed_fallback_icons: Dictionary = {}


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")
	if _event_bus:
		_event_bus.stamina_changed.connect(_on_stamina_changed)
		_event_bus.gold_changed.connect(_on_gold_changed)
		if _event_bus.has_signal("economy_ui_notification_added"):
			_event_bus.economy_ui_notification_added.connect(_on_economy_ui_notification_added)
		_event_bus.level_changed.connect(_on_level_changed)
		_event_bus.exp_gained.connect(_on_exp_gained)
		_event_bus.season_changed.connect(_on_season_changed)
		_event_bus.time_changed.connect(_on_time_changed)
		_event_bus.day_changed.connect(_on_day_changed)
		_event_bus.item_added.connect(_on_inventory_item_changed)
		_event_bus.item_removed.connect(_on_inventory_item_changed)
		if _event_bus.has_signal("service_unlocked"):
			_event_bus.service_unlocked.connect(_on_service_unlocked)
	if not debug_reset_button.pressed.is_connected(_on_debug_reset_pressed):
		debug_reset_button.pressed.connect(_on_debug_reset_pressed)
	if not debug_panel_button.pressed.is_connected(_on_debug_panel_pressed):
		debug_panel_button.pressed.connect(_on_debug_panel_pressed)
	if not market_button.pressed.is_connected(_on_market_pressed):
		market_button.pressed.connect(_on_market_pressed)
	if not notification_button.pressed.is_connected(_on_notification_pressed):
		notification_button.pressed.connect(_on_notification_pressed)
	if not inventory_button.pressed.is_connected(_on_inventory_pressed):
		inventory_button.pressed.connect(_on_inventory_pressed)

	# 初始化显示
	_init_display()
	farming_mode_button.gui_input.connect(
		_on_mode_pointer_input.bind(PlayerActionController.ActionMode.FARMING)
	)
	building_mode_button.gui_input.connect(
		_on_mode_pointer_input.bind(PlayerActionController.ActionMode.BUILDING)
	)
	if message_stream.has_signal("history_requested") and not message_stream.is_connected("history_requested", _on_notification_pressed):
		message_stream.connect("history_requested", _on_notification_pressed)
	for category_id in build_category_buttons:
		build_category_buttons[category_id].pressed.connect(
			_on_build_category_pressed.bind(category_id)
		)
	build_lock_unlock_button.pressed.connect(_on_build_unlock_pressed)
	build_lock_close_button.pressed.connect(_hide_build_lock_detail)
	set_notification_count(0)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_responsive_layout):
		viewport.size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")


func _on_market_pressed() -> void:
	market_requested.emit()


func _on_inventory_pressed() -> void:
	inventory_requested.emit()


func _apply_responsive_layout() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var right_margin := 18.0
	var rail_width := clampf(viewport_size.x * 0.27, 280.0, 360.0)
	message_stream.offset_left = -right_margin - rail_width
	message_stream.offset_right = -right_margin
	message_stream.offset_top = 18.0
	var stream_left := viewport_size.x - right_margin - rail_width
	var top_bar := $TopBar as Control
	top_bar.offset_left = 20.0
	top_bar.offset_top = 18.0
	top_bar.offset_right = stream_left - 12.0
	top_bar.offset_bottom = 80.0
	var bottom_bar := $BottomBar as Control
	var bottom_top := viewport_size.y + bottom_bar.offset_top
	message_stream.call("set_expanded_bottom", bottom_top - 12.0)


func _on_notification_pressed() -> void:
	notifications_requested.emit()


func set_notification_count(unread_count: int) -> void:
	_economy_ui_unread_count = maxi(0, unread_count)
	if notification_button == null:
		return
	var count_text := "9+" if _economy_ui_unread_count > 9 else str(_economy_ui_unread_count)
	notification_button.text = "通知 %s" % count_text


func _on_economy_ui_notification_added(_target_type: String, _target_id: String) -> void:
	if notification_ref != null:
		return
	set_notification_count(_economy_ui_unread_count + 1)


func configure_notifications(system: EconomyNotificationSystem) -> bool:
	if system == null or not is_instance_valid(system):
		return false
	if notification_ref != null and is_instance_valid(notification_ref):
		var old_callback := Callable(self, "_refresh_notification_display")
		if notification_ref.notifications_changed.is_connected(old_callback):
			notification_ref.notifications_changed.disconnect(old_callback)
	notification_ref = system
	var callback := Callable(self, "_refresh_notification_display")
	if not notification_ref.notifications_changed.is_connected(callback):
		notification_ref.notifications_changed.connect(callback)
	_refresh_notification_display()
	return true


func configure_message_bus(bus: Node) -> bool:
	if bus == null or not is_instance_valid(bus) or bus.get_script() != HudMessageBusScript:
		return false
	if not bool(message_stream.call("configure", bus)):
		return false
	message_bus = bus
	return true


func _refresh_notification_display() -> void:
	if notification_ref == null:
		return
	_economy_ui_unread_count = notification_ref.get_unread_count()
	var count_text := "9+" if _economy_ui_unread_count > 9 else str(_economy_ui_unread_count)
	notification_button.text = "[通知 %s]" % count_text


func get_urgent_summary_count() -> int:
	return 0


func get_urgent_summary_text(index: int) -> String:
	return "" if index >= 0 else ""


func _init_display() -> void:
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		_on_stamina_changed(game_state.player_state.stamina)
		_on_gold_changed(game_state.gold)
		_on_level_changed(game_state.player_state.level)

	var season_system = _get_season_system()
	if season_system:
		_update_season_display(season_system)
		_update_time_display(season_system.hour, season_system.minute)


# ============================================================
# 信号回调
# ============================================================

func _on_stamina_changed(value: int) -> void:
	if stamina_bar:
		stamina_bar.value = value
		# 低体力时变红
		if stamina_bar.has_theme_color_override("fill_color"):
			pass
		elif value < 20:
			stamina_bar.add_theme_color_override("fill_color", Color(1.0, 0.2, 0.2))
		else:
			stamina_bar.add_theme_color_override("fill_color", Color(0.2, 0.8, 0.2))


func _on_gold_changed(value: int) -> void:
	if gold_label:
		gold_label.text = "💰 %d" % value


func _on_level_changed(value: int) -> void:
	if level_label:
		level_label.text = "Lv.%d" % value


func _on_exp_gained(_amount: int) -> void:
	var game_state = get_node_or_null("/root/GameState")
	if game_state and exp_bar:
		var ps = game_state.player_state
		var exp_needed = ps.get_exp_for_next_level()
		if exp_needed > 0:
			exp_bar.value = (float(ps.exp) / exp_needed) * 100.0


func _on_season_changed(_new_season: int) -> void:
	var season_system = _get_season_system()
	if season_system:
		_update_season_display(season_system)


func _on_day_changed(_total_day: int) -> void:
	var season_system = _get_season_system()
	if season_system:
		_update_season_display(season_system)


func _on_time_changed(hour: int, minute: int) -> void:
	_update_time_display(hour, minute)


# ============================================================
# 显示更新
# ============================================================

func _update_season_display(season_system: Node) -> void:
	if season_label == null:
		return

	var season_names = ["春", "夏", "秋", "冬"]
	var season_name = season_names[season_system.current_season]
	season_label.text = "%s %d/%d" % [season_name, season_system.current_day, season_system.DAYS_PER_SEASON]


func _update_time_display(hour: int, minute: int) -> void:
	if time_label == null:
		return
	time_label.text = "%02d:%02d" % [hour, minute]


func set_tool_name(name: String) -> void:
	if tool_label:
		tool_label.text = name


func configure_season_system(system: Variant) -> void:
	season_system_ref = system
	if season_system_ref:
		_update_season_display(season_system_ref)
		_update_time_display(season_system_ref.hour, season_system_ref.minute)


func configure_debug_reset(available: bool) -> void:
	configure_debug_tools(available)


func configure_debug_tools(available: bool) -> void:
	debug_actions.visible = available


func _on_debug_panel_pressed() -> void:
	if debug_actions.visible:
		debug_panel_requested.emit()


func _on_debug_reset_pressed() -> void:
	if debug_actions.visible:
		debug_reset_requested.emit()


func _get_season_system() -> Variant:
	if season_system_ref:
		return season_system_ref
	return get_node_or_null("/root/SeasonSystem")


func configure_action_bar(
	controller: Variant,
	inventory: Variant,
	economy: Variant = null
) -> void:
	if action_controller != controller:
		_disconnect_action_controller(action_controller)
	action_controller = controller
	var mapping_handler := Callable(self, "_on_quick_slot_mapping_changed")
	if (
		inventory_ref != null
		and inventory_ref != inventory
		and inventory_ref.has_signal("quick_slot_mapping_changed")
		and inventory_ref.is_connected("quick_slot_mapping_changed", mapping_handler)
	):
		inventory_ref.disconnect("quick_slot_mapping_changed", mapping_handler)
	inventory_ref = inventory
	if (
		inventory_ref != null
		and inventory_ref.has_signal("quick_slot_mapping_changed")
		and not inventory_ref.is_connected("quick_slot_mapping_changed", mapping_handler)
	):
		inventory_ref.connect("quick_slot_mapping_changed", mapping_handler)
	economy_ref = economy
	_connect_action_controller(action_controller)
	rebuild_action_palette()
	if action_controller:
		var selected: int = action_controller.get_selected_slot()
		var selected_label := _selection_label(selected)
		_on_action_selection_changed(selected, selected_label)


func _connect_action_controller(controller: Variant) -> void:
	_connect_controller_signal(
		controller,
		"selection_changed",
		Callable(self, "_on_action_selection_changed")
	)
	_connect_controller_signal(
		controller,
		"inventory_changed",
		Callable(self, "refresh_action_bar")
	)
	_connect_controller_signal(
		controller,
		"mode_changed",
		Callable(self, "_on_action_mode_changed")
	)
	_connect_controller_signal(
		controller,
		"palette_changed",
		Callable(self, "_on_action_palette_changed")
	)
	_connect_controller_signal(
		controller,
		"build_feedback_requested",
		Callable(self, "show_build_feedback")
	)
	_connect_controller_signal(
		controller,
		"building_category_changed",
		Callable(self, "_on_building_category_changed")
	)
	_connect_controller_signal(
		controller,
		"plant_selection_changed",
		Callable(self, "_on_plant_selection_changed")
	)


func _disconnect_action_controller(controller: Variant) -> void:
	_disconnect_controller_signal(
		controller,
		"selection_changed",
		Callable(self, "_on_action_selection_changed")
	)
	_disconnect_controller_signal(
		controller,
		"inventory_changed",
		Callable(self, "refresh_action_bar")
	)
	_disconnect_controller_signal(
		controller,
		"mode_changed",
		Callable(self, "_on_action_mode_changed")
	)
	_disconnect_controller_signal(
		controller,
		"palette_changed",
		Callable(self, "_on_action_palette_changed")
	)
	_disconnect_controller_signal(
		controller,
		"build_feedback_requested",
		Callable(self, "show_build_feedback")
	)
	_disconnect_controller_signal(
		controller,
		"building_category_changed",
		Callable(self, "_on_building_category_changed")
	)
	_disconnect_controller_signal(
		controller,
		"plant_selection_changed",
		Callable(self, "_on_plant_selection_changed")
	)


func _connect_controller_signal(
	controller: Variant,
	signal_name: StringName,
	callback: Callable
) -> void:
	if (
		controller != null
		and controller.has_signal(signal_name)
		and not controller.is_connected(signal_name, callback)
	):
		controller.connect(signal_name, callback)


func _disconnect_controller_signal(
	controller: Variant,
	signal_name: StringName,
	callback: Callable
) -> void:
	if (
		controller != null
		and controller.has_signal(signal_name)
		and controller.is_connected(signal_name, callback)
	):
		controller.disconnect(signal_name, callback)


func rebuild_action_palette() -> void:
	if quick_bar == null:
		return
	for child in quick_bar.get_children():
		child.free()
	var has_active_mode := _has_active_action_mode()
	quick_bar.visible = has_active_mode
	if not has_active_mode:
		build_category_bar.visible = false
		_sync_mode_buttons(PlayerActionController.ActionMode.NONE)
		_refresh_build_cost_bar(-1)
		return
	var building_mode := _is_building_mode()
	var building_ids: Array = (
		action_controller.get_current_building_ids()
		if building_mode and action_controller.has_method("get_current_building_ids")
		else []
	)
	var labels: Array = []
	if building_mode:
		for building_id in building_ids:
			var source := GameDataScript.get_building(building_id)
			labels.append(str(source.get("name", building_id)))
	else:
		labels = ACTION_NAMES
	build_category_bar.visible = building_mode
	_refresh_build_category_buttons()
	quick_bar.add_theme_constant_override("separation", 4 if building_mode else 8)
	_sync_mode_buttons(action_controller.get_action_mode())
	for index in range(labels.size()):
		var button = ActionPaletteButtonScene.instantiate()
		button.name = "Slot%d" % (index + 1)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		quick_bar.add_child(button)
		var display_name := str(labels[index])
		if not building_mode and index == PlayerActionController.SEED_SLOT:
			display_name = _active_plant_item_display()
		button.configure(
			index + 1,
			display_name,
			_palette_texture(index, building_mode)
		)
		if building_mode:
			_configure_building_button(button, index)
		button.pressed.connect(_on_quick_slot_pressed.bind(index))
	refresh_action_bar()


func refresh_action_bar() -> void:
	_refresh_material_counts()
	if quick_bar == null:
		return
	var selected: int = action_controller.get_selected_slot() if action_controller else -1
	var building_mode := _is_building_mode()
	for index in range(quick_bar.get_child_count()):
		var button = quick_bar.get_child(index)
		if not button is ActionPaletteButtonScript:
			continue
		if not building_mode and index == PlayerActionController.SEED_SLOT:
			button.configure(
				index + 1,
				_active_plant_item_display(),
				_palette_texture(index, false)
			)
		elif building_mode:
			_configure_building_button(button, index)
		button.set_selected(index == selected)
		if building_mode:
			var diagnostic := _building_diagnostic(index)
			button.set_build_state(_build_state_for_diagnostic(diagnostic))
		else:
			button.set_available(true)
	_refresh_build_cost_bar(selected)


func _on_quick_slot_pressed(index: int) -> void:
	quick_slot_selected.emit(index)
	if not action_controller:
		return
	if _is_building_mode():
		_on_building_button_pressed(index)
	else:
		action_controller.select_mode_slot(index)


func _on_action_selection_changed(index: int, label: String) -> void:
	if tool_label:
		tool_label.text = label
	refresh_action_bar()


func _on_action_mode_changed(mode: int) -> void:
	_sync_mode_buttons(mode)
	rebuild_action_palette()


func _on_action_palette_changed(_mode: int, _selected_index: int) -> void:
	refresh_action_bar()


func _on_inventory_item_changed(item_id: String, _quantity: int) -> void:
	var item_data = GameDataScript.get_item(item_id)
	if _is_building_mode() or item_id in MATERIAL_IDS or (item_data and item_data.get("category", "") == "seed"):
		refresh_action_bar()


func _on_quick_slot_mapping_changed(quick_index: int, _item_id: String) -> void:
	refresh_action_bar()
	if quick_index == PlayerActionController.SEED_SLOT:
		return


func _on_plant_selection_changed(_plant_item_id: String) -> void:
	refresh_action_bar()
	if (
		action_controller
		and not _is_building_mode()
		and action_controller.get_selected_slot() == PlayerActionController.SEED_SLOT
	):
		set_tool_name(_active_plant_item_name())


func _active_plant_item_display() -> String:
	if inventory_ref == null:
		return "种苗 ×0"
	var item_id := _active_plant_item_id()
	var item_data = GameDataScript.get_item(item_id)
	if item_data == null:
		return "种苗 ×0"
	return "%s ×%d" % [
		str(item_data.get("name", "种苗")),
		inventory_ref.get_item_count(item_id) if inventory_ref != null else 0,
	]


func _active_plant_item_name() -> String:
	var item_id := _active_plant_item_id()
	var item_data = GameDataScript.get_item(item_id)
	return str(item_data.get("name", "种苗")) if item_data else "种苗"


func get_active_plant_item_display() -> String:
	return _active_plant_item_display()


func _active_plant_item_id() -> String:
	if action_controller == null or not action_controller.has_method("get_selected_plant_item_id"):
		return ""
	var selected := str(action_controller.call("get_selected_plant_item_id"))
	if not selected.is_empty():
		return selected
	# Fall back to first seed/sapling in inventory
	if action_controller and action_controller.has_method("_get_active_plant_item_id"):
		return str(action_controller._get_active_plant_item_id())
	return ""


func _active_plant_texture() -> Texture2D:
	var item_id := _active_plant_item_id()
	if item_id.is_empty():
		return _load_palette_icon(FARMING_ICON_PATHS[PlayerActionController.SEED_SLOT])
	var game_data := get_node_or_null("/root/GameData") if is_inside_tree() else null
	var crop: CropData = (
		game_data.get_crop_for_plant_item(item_id)
		if game_data != null and game_data.has_method("get_crop_for_plant_item")
		else null
	)
	if crop != null:
		for texture_path in crop.stage_textures:
			var texture := _load_palette_icon(texture_path)
			if texture != null:
				return texture
		var painted_path := "res://assets/crops/%s/painted/stage_0/variant_0_front.png" % crop.crop_id
		var painted := _load_palette_icon(painted_path)
		if painted != null:
			return painted
	return _seed_fallback_icon(item_id)


func _seed_fallback_icon(item_id: String) -> Texture2D:
	if _seed_fallback_icons.has(item_id):
		return _seed_fallback_icons[item_id] as Texture2D
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var hue := float(absi(item_id.hash()) % 1000) / 1000.0
	var seed_color := Color.from_hsv(hue, 0.48, 0.68, 1.0)
	image.fill_rect(Rect2i(7, 10, 18, 14), seed_color)
	image.fill_rect(Rect2i(11, 6, 10, 20), seed_color.lightened(0.15))
	var texture := ImageTexture.create_from_image(image)
	_seed_fallback_icons[item_id] = texture
	return texture


func _on_mode_requested(mode: int) -> void:
	if action_controller:
		action_controller.switch_mode(mode)
	_sync_mode_buttons(action_controller.get_action_mode() if action_controller else PlayerActionController.ActionMode.NONE)


func _on_mode_pointer_input(event: InputEvent, mode: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_mode_requested(mode)


func _sync_mode_buttons(mode: int) -> void:
	if farming_mode_button != null:
		farming_mode_button.set_pressed_no_signal(mode == PlayerActionController.ActionMode.FARMING)
	if building_mode_button != null:
		building_mode_button.set_pressed_no_signal(mode == PlayerActionController.ActionMode.BUILDING)


func get_palette_button_count() -> int:
	return quick_bar.get_child_count() if quick_bar else 0


func _is_building_mode() -> bool:
	return (
		action_controller != null
		and action_controller.get_action_mode() == PlayerActionController.ActionMode.BUILDING
	)


func _has_active_action_mode() -> bool:
	return (
		action_controller != null
		and action_controller.get_action_mode() in [
			PlayerActionController.ActionMode.FARMING,
			PlayerActionController.ActionMode.BUILDING,
		]
	)


func _selection_label(index: int) -> String:
	if index < 0:
		return "未选择建筑" if _is_building_mode() else "未选择工具"
	if _is_building_mode() and action_controller.has_method("get_building_id_at"):
		var building_id := str(action_controller.get_building_id_at(index))
		var source := GameDataScript.get_building(building_id)
		return str(source.get("name", building_id))
	return str(ACTION_NAMES[index]) if index < ACTION_NAMES.size() else ""


func _configure_building_button(button: Button, index: int) -> void:
	var building_id := _building_id_at(index)
	if building_id.is_empty():
		return
	var source: Dictionary = GameDataScript.get_building(building_id)
	var footprint := Vector2i(
		int(source.get("footprint_x", 0)),
		int(source.get("footprint_z", 0))
	)
	var cost_parts: Array[String] = []
	for item_id in source.get("cost", {}):
		var required := int(source.cost[item_id])
		var available: int = (
			inventory_ref.get_item_count(str(item_id))
			if inventory_ref != null
			else 0
		)
		var part := "%s %d/%d" % [
			_item_display_name(str(item_id)),
			required,
			available,
		]
		if available < required:
			part += "（缺 %d）" % (required - available)
		cost_parts.append(part)
	button.tooltip_text = "%s\n占地 %d × %d\n%s" % [
		str(source.get("name", building_id)),
		footprint.x,
		footprint.y,
		"、".join(cost_parts),
	]


func _palette_texture(index: int, building_mode: bool) -> Texture2D:
	var path := ""
	if building_mode:
		path = _building_icon_path(_building_id_at(index))
	elif index == PlayerActionController.SEED_SLOT:
		return _active_plant_texture()
	elif not building_mode and index >= 0 and index < FARMING_ICON_PATHS.size():
		path = FARMING_ICON_PATHS[index]
	var texture := _load_palette_icon(path)
	if texture == null and building_mode:
		texture = _load_palette_icon(_building_icon_path("workbench"))
	return texture


func _building_icon_path(building_id: String) -> String:
	return "res://assets/buildings/painted/%s/%s_back.png" % [
		building_id,
		building_id,
	]


func _load_palette_icon(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _building_resources_available(index: int) -> bool:
	if action_controller != null and action_controller.has_method(
		"get_building_resource_diagnostic"
	):
		return bool(
			action_controller.get_building_resource_diagnostic(index).get(
				"allowed",
				false
			)
		)
	if economy_ref == null or not economy_ref.has_method("has_resources"):
		return true
	var building_id := _building_id_at(index)
	if building_id.is_empty():
		return false
	var source: Dictionary = GameDataScript.get_building(building_id)
	return bool(economy_ref.has_resources(source.get("cost", {})))


func _building_id_at(index: int) -> String:
	if action_controller == null or not action_controller.has_method("get_building_id_at"):
		return ""
	return str(action_controller.get_building_id_at(index))


func _building_diagnostic(index: int) -> Dictionary:
	if action_controller != null and action_controller.has_method("get_building_availability_diagnostic"):
		return action_controller.get_building_availability_diagnostic(index)
	if action_controller != null and action_controller.has_method("get_building_resource_diagnostic"):
		return action_controller.get_building_resource_diagnostic(index)
	return {
		"allowed": false,
		"code": "invalid_building",
		"message": "建筑数据不可用",
		"building_id": _building_id_at(index),
	}


func _build_state_for_diagnostic(diagnostic: Dictionary) -> String:
	if bool(diagnostic.get("allowed", false)):
		return "ready"
	match str(diagnostic.get("code", "")):
		"blueprint_locked":
			return "locked"
		"insufficient_resources":
			return "missing_resources"
	return "invalid"


func _on_building_button_pressed(index: int) -> void:
	var diagnostic := _building_diagnostic(index)
	if str(diagnostic.get("code", "")) == "blueprint_locked":
		_show_build_lock_detail(diagnostic)
		return
	if not bool(diagnostic.get("allowed", false)):
		show_build_feedback(str(diagnostic.get("message", "建筑不可用")), diagnostic)
		return
	action_controller.select_mode_slot(index)


func _on_build_category_pressed(category_id: String) -> void:
	if action_controller != null and action_controller.has_method("set_building_category"):
		action_controller.set_building_category(category_id)


func _on_building_category_changed(_category_id: String, _category_index: int) -> void:
	rebuild_action_palette()


func _refresh_build_category_buttons() -> void:
	var selected := (
		str(action_controller.get_building_category())
		if action_controller != null and action_controller.has_method("get_building_category")
		else ""
	)
	for category_id in build_category_buttons:
		build_category_buttons[category_id].button_pressed = category_id == selected


func _show_build_lock_detail(diagnostic: Dictionary) -> void:
	var building_id := str(diagnostic.get("building_id", ""))
	var source := GameDataScript.get_building(building_id)
	build_lock_title.text = "%s蓝图未解锁" % str(source.get("name", building_id))
	build_lock_reason.text = str(diagnostic.get("message", "尚未解锁"))
	var cost_parts: Array[String] = []
	for item_id in source.get("cost", {}):
		cost_parts.append("%s ×%d" % [_item_display_name(str(item_id)), int(source.cost[item_id])])
	build_lock_cost.text = "最终造价：%s" % "、".join(cost_parts)
	_build_lock_service_id = str(diagnostic.get("unlock_service_id", ""))
	build_lock_unlock_button.disabled = _build_lock_service_id.is_empty()
	build_lock_panel.visible = true


func _hide_build_lock_detail() -> void:
	build_lock_panel.visible = false
	_build_lock_service_id = ""


func _on_build_unlock_pressed() -> void:
	if _build_lock_service_id.is_empty():
		return
	var service_id := _build_lock_service_id
	_hide_build_lock_detail()
	building_unlock_requested.emit(service_id)


func _on_service_unlocked(_kind: String = "", _target_id: String = "") -> void:
	refresh_action_bar()


func _item_display_name(item_id: String) -> String:
	var item_data = GameDataScript.get_item(item_id)
	return str(item_data.get("name", MATERIAL_NAMES.get(item_id, item_id))) if item_data else str(MATERIAL_NAMES.get(item_id, item_id))


func get_material_count_text(item_id: String) -> String:
	var label = _material_count_labels.get(item_id)
	return label.text if label is Label else ""


func show_build_feedback(message: String, _details: Dictionary = {}) -> void:
	if message_bus != null:
		message_bus.call("publish", "building", "error", message, _details)


func show_action_hint(text: String, _duration := 2.5) -> void:
	if message_bus != null:
		message_bus.call("publish", "action", "info", text)


func _refresh_material_counts() -> void:
	for item_id in MATERIAL_IDS:
		var count: int = inventory_ref.get_item_count(item_id) if inventory_ref else 0
		var label = _material_count_labels.get(item_id)
		if label is Label:
			label.text = str(count)


func _refresh_build_cost_bar(selected_index: int) -> void:
	if (
		not _is_building_mode()
		or selected_index < 0
		or _building_id_at(selected_index).is_empty()
	):
		build_cost_bar.visible = false
		return
	var building_id := _building_id_at(selected_index)
	var source: Dictionary = GameDataScript.get_building(building_id)
	if source.is_empty():
		build_cost_bar.visible = false
		return
	building_cost_label.text = "%s　占地 %d×%d" % [
		str(source.get("name", building_id)),
		int(source.get("footprint_x", 0)),
		int(source.get("footprint_z", 0)),
	]
	for child in building_costs.get_children():
		child.free()
	for item_id in source.get("cost", {}):
		building_costs.add_child(
			_create_cost_entry(
				str(item_id),
				int(source.cost[item_id]),
				inventory_ref.get_item_count(str(item_id)) if inventory_ref else 0
			)
		)
	build_cost_bar.visible = true


func _create_cost_entry(item_id: String, required: int, available: int) -> HBoxContainer:
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 4)
	entry.tooltip_text = _item_display_name(item_id)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_palette_icon(str(MATERIAL_ICON_PATHS.get(item_id, "")))
	if icon.texture != null:
		entry.add_child(icon)
	else:
		var fallback := Label.new()
		fallback.custom_minimum_size = Vector2(28, 28)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.text = _item_display_name(item_id).left(1)
		fallback.tooltip_text = _item_display_name(item_id)
		entry.add_child(fallback)
	var amount := Label.new()
	amount.add_theme_font_size_override("font_size", 22)
	amount.add_theme_color_override(
		"font_color",
		COST_AVAILABLE_COLOR if available >= required else COST_MISSING_COLOR
	)
	amount.add_theme_color_override("font_outline_color", Color(0.09, 0.125, 0.098, 1))
	amount.add_theme_constant_override("outline_size", 3)
	amount.text = "%d/%d" % [required, available]
	entry.add_child(amount)
	return entry


func set_quick_slot(index: int, item_name: String, quantity: int) -> void:
	if quick_bar == null or index < 0 or index >= quick_bar.get_child_count():
		return
	var slot = quick_bar.get_child(index)
	if slot is ActionPaletteButtonScript:
		slot.configure(
			index + 1,
			"%s ×%d" % [item_name, quantity],
			slot.icon_rect.texture
		)
