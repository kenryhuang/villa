class_name VillaHud
extends CanvasLayer

## 农庄 HUD - 体力、金币、等级、季节/日期、时间、快捷栏

signal quick_slot_selected(index: int)
signal debug_reset_requested

const GameDataScript = preload("res://scripts/core/game_data.gd")
const ActionPaletteButtonScene = preload(
	"res://scenes/ui/action_palette_button.tscn"
)
const ActionPaletteButtonScript = preload(
	"res://scripts/ui/action_palette_button.gd"
)
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
const MODE_MENU_CLOSE_DELAY := 0.15
const COST_AVAILABLE_COLOR := Color(1.0, 0.945, 0.816, 1.0)
const COST_MISSING_COLOR := Color(1.0, 0.48, 0.38, 1.0)

@onready var stamina_bar: ProgressBar = $TopBar/StatusRow/StaminaBar
@onready var gold_label: Label = $TopBar/StatusRow/GoldLabel
@onready var level_label: Label = $TopBar/StatusRow/LevelLabel
@onready var exp_bar: ProgressBar = $TopBar/StatusRow/ExpBar
@onready var season_label: Label = $TopBar/StatusRow/SeasonLabel
@onready var time_label: Label = $TopBar/StatusRow/TimeLabel
@onready var debug_reset_button: Button = $DebugResetButton
@onready var mode_menu: PopupPanel = $BottomBar/ModeMenu
@onready var mode_menu_content: VBoxContainer = $BottomBar/ModeMenu/VBox
@onready var farming_mode_button: Button = $BottomBar/ModeMenu/VBox/FarmingModeButton
@onready var building_mode_button: Button = $BottomBar/ModeMenu/VBox/BuildingModeButton
@onready var mode_button: Button = $BottomBar/ActionRow/ModeButton
@onready var quick_bar: HBoxContainer = $BottomBar/ActionRow/QuickBar
@onready var tool_label: Label = $BottomBar/ToolLabel
@onready var build_cost_bar: PanelContainer = $BottomBar/BuildCostBar
@onready var building_cost_label: Label = $BottomBar/BuildCostBar/CostRow/BuildingLabel
@onready var building_costs: HBoxContainer = $BottomBar/BuildCostBar/CostRow/Costs
@onready var build_feedback_toast: PanelContainer = $BottomBar/BuildFeedbackToast
@onready var build_feedback_label: Label = $BottomBar/BuildFeedbackToast/Message
@onready var build_feedback_timer: Timer = $BuildFeedbackTimer
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
var _mode_menu_hover_token := 0


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")
	if _event_bus:
		_event_bus.stamina_changed.connect(_on_stamina_changed)
		_event_bus.gold_changed.connect(_on_gold_changed)
		_event_bus.level_changed.connect(_on_level_changed)
		_event_bus.exp_gained.connect(_on_exp_gained)
		_event_bus.season_changed.connect(_on_season_changed)
		_event_bus.time_changed.connect(_on_time_changed)
		_event_bus.day_changed.connect(_on_day_changed)
		_event_bus.item_added.connect(_on_inventory_item_changed)
		_event_bus.item_removed.connect(_on_inventory_item_changed)
	if not debug_reset_button.pressed.is_connected(_on_debug_reset_pressed):
		debug_reset_button.pressed.connect(_on_debug_reset_pressed)

	# 初始化显示
	_init_display()
	farming_mode_button.pressed.connect(
		_on_mode_requested.bind(PlayerActionController.ActionMode.FARMING)
	)
	building_mode_button.pressed.connect(
		_on_mode_requested.bind(PlayerActionController.ActionMode.BUILDING)
	)
	mode_button.pressed.connect(_on_mode_button_pressed)
	mode_button.mouse_entered.connect(_on_mode_menu_mouse_entered)
	mode_button.mouse_exited.connect(_on_mode_menu_mouse_exited)
	mode_menu_content.mouse_entered.connect(_on_mode_menu_mouse_entered)
	mode_menu_content.mouse_exited.connect(_on_mode_menu_mouse_exited)
	build_feedback_timer.timeout.connect(_on_build_feedback_timeout)


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
	debug_reset_button.visible = available


func _on_debug_reset_pressed() -> void:
	if debug_reset_button.visible:
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
	if (
		action_controller
		and not action_controller.selection_changed.is_connected(
			_on_action_selection_changed
		)
	):
		action_controller.selection_changed.connect(_on_action_selection_changed)
	if (
		action_controller
		and not action_controller.inventory_changed.is_connected(refresh_action_bar)
	):
		action_controller.inventory_changed.connect(refresh_action_bar)
	if (
		action_controller
		and action_controller.has_signal("mode_changed")
		and not action_controller.mode_changed.is_connected(_on_action_mode_changed)
	):
		action_controller.mode_changed.connect(_on_action_mode_changed)
	if (
		action_controller
		and action_controller.has_signal("palette_changed")
		and not action_controller.palette_changed.is_connected(_on_action_palette_changed)
	):
		action_controller.palette_changed.connect(_on_action_palette_changed)
	if (
		action_controller
		and action_controller.has_signal("build_feedback_requested")
		and not action_controller.build_feedback_requested.is_connected(
			show_build_feedback
		)
	):
		action_controller.build_feedback_requested.connect(show_build_feedback)
	rebuild_action_palette()
	if action_controller:
		var selected: int = action_controller.get_selected_slot()
		var selected_label := _selection_label(selected)
		_on_action_selection_changed(selected, selected_label)


func rebuild_action_palette() -> void:
	if quick_bar == null:
		return
	for child in quick_bar.get_children():
		child.free()
	var building_mode := _is_building_mode()
	var labels: Array = BUILDING_NAMES if building_mode else ACTION_NAMES
	quick_bar.add_theme_constant_override("separation", 4 if building_mode else 8)
	var mode_name := "建造" if building_mode else "种植"
	mode_button.configure(
		0,
		mode_name,
		_load_palette_icon(
			_building_icon_path("barn")
			if building_mode
			else FARMING_ICON_PATHS[PlayerActionController.SEED_SLOT]
		)
	)
	mode_button.set_shortcut_visible(false)
	mode_button.tooltip_text = "当前：%s模式\n悬停选择模式（P / B）" % mode_name
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
		var available := true
		if building_mode:
			available = _building_resources_available(index)
		button.set_available(available)
	_refresh_build_cost_bar(selected)


func _on_quick_slot_pressed(index: int) -> void:
	quick_slot_selected.emit(index)
	if action_controller:
		action_controller.select_mode_slot(index)


func _on_action_selection_changed(index: int, label: String) -> void:
	if tool_label:
		tool_label.text = label
	refresh_action_bar()


func _on_action_mode_changed(_mode: int) -> void:
	rebuild_action_palette()
	set_mode_menu_open(false)


func _on_action_palette_changed(_mode: int, _selected_index: int) -> void:
	refresh_action_bar()


func _on_inventory_item_changed(item_id: String, _quantity: int) -> void:
	var item_data = GameDataScript.get_item(item_id)
	if item_id in MATERIAL_IDS or (item_data and item_data.get("category", "") == "seed"):
		refresh_action_bar()


func _on_quick_slot_mapping_changed(quick_index: int, _item_id: String) -> void:
	refresh_action_bar()
	if (
		quick_index == PlayerActionController.SEED_SLOT
		and action_controller
		and not _is_building_mode()
		and action_controller.get_selected_slot() == PlayerActionController.SEED_SLOT
	):
		set_tool_name(_active_plant_item_name())


func _active_plant_item_display() -> String:
	if inventory_ref == null:
		return "种苗 ×0"
	var item_id := str(inventory_ref.get_quick_item(PlayerActionController.SEED_SLOT))
	var item_data = GameDataScript.get_item(item_id)
	if item_data == null:
		return "种苗 ×0"
	return "%s ×%d" % [
		str(item_data.get("name", "种苗")),
		inventory_ref.get_item_count(item_id),
	]


func _active_plant_item_name() -> String:
	if inventory_ref == null:
		return "种苗"
	var item_id := str(inventory_ref.get_quick_item(PlayerActionController.SEED_SLOT))
	var item_data = GameDataScript.get_item(item_id)
	return str(item_data.get("name", "种苗")) if item_data else "种苗"


func _on_mode_requested(mode: int) -> void:
	if action_controller:
		action_controller.switch_mode(mode)
	set_mode_menu_open(false)


func _on_mode_button_pressed() -> void:
	set_mode_menu_open(not mode_menu.visible)


func _on_mode_menu_mouse_entered() -> void:
	_mode_menu_hover_token += 1
	set_mode_menu_open(true)


func _on_mode_menu_mouse_exited() -> void:
	_mode_menu_hover_token += 1
	var expected_token := _mode_menu_hover_token
	await get_tree().create_timer(MODE_MENU_CLOSE_DELAY).timeout
	if expected_token == _mode_menu_hover_token:
		set_mode_menu_open(false)


func set_mode_menu_open(open: bool) -> void:
	if mode_menu == null:
		return
	if not open:
		mode_menu.hide()
		return
	var button_position := mode_button.get_screen_position()
	var popup_size := Vector2i(260, 140)
	var popup_position := Vector2i(
		roundi(button_position.x),
		roundi(button_position.y - popup_size.y - 6.0)
	)
	mode_menu.popup(Rect2i(popup_position, popup_size))


func get_palette_button_count() -> int:
	return quick_bar.get_child_count() if quick_bar else 0


func _is_building_mode() -> bool:
	return (
		action_controller != null
		and action_controller.get_action_mode() == PlayerActionController.ActionMode.BUILDING
	)


func _selection_label(index: int) -> String:
	if index < 0:
		return "未选择建筑" if _is_building_mode() else "未选择工具"
	var labels: Array = BUILDING_NAMES if _is_building_mode() else ACTION_NAMES
	return str(labels[index]) if index < labels.size() else ""


func _configure_building_button(button: Button, index: int) -> void:
	if index < 0 or index >= PlayerActionController.BUILDING_IDS.size():
		return
	var building_id: String = PlayerActionController.BUILDING_IDS[index]
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
			MATERIAL_NAMES.get(item_id, item_id),
			required,
			available,
		]
		if available < required:
			part += "（缺 %d）" % (required - available)
		cost_parts.append(part)
	button.tooltip_text = "%s\n占地 %d × %d\n%s" % [
		str(source.get("name", BUILDING_NAMES[index])),
		footprint.x,
		footprint.y,
		"、".join(cost_parts),
	]


func _palette_texture(index: int, building_mode: bool) -> Texture2D:
	var path := ""
	if building_mode and index >= 0 and index < PlayerActionController.BUILDING_IDS.size():
		path = _building_icon_path(PlayerActionController.BUILDING_IDS[index])
	elif not building_mode and index >= 0 and index < FARMING_ICON_PATHS.size():
		path = FARMING_ICON_PATHS[index]
	return _load_palette_icon(path)


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
	if index < 0 or index >= PlayerActionController.BUILDING_IDS.size():
		return false
	var source: Dictionary = GameDataScript.get_building(
		PlayerActionController.BUILDING_IDS[index]
	)
	return bool(economy_ref.has_resources(source.get("cost", {})))


func get_material_count_text(item_id: String) -> String:
	var label = _material_count_labels.get(item_id)
	return label.text if label is Label else ""


func show_build_feedback(message: String, _details: Dictionary = {}) -> void:
	build_feedback_label.text = message
	build_feedback_toast.visible = true
	build_feedback_timer.start()


func _on_build_feedback_timeout() -> void:
	build_feedback_toast.visible = false


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
		or selected_index >= PlayerActionController.BUILDING_IDS.size()
	):
		build_cost_bar.visible = false
		return
	var building_id: String = PlayerActionController.BUILDING_IDS[selected_index]
	var source: Dictionary = GameDataScript.get_building(building_id)
	if source.is_empty():
		build_cost_bar.visible = false
		return
	building_cost_label.text = "%s　占地 %d×%d" % [
		str(source.get("name", BUILDING_NAMES[selected_index])),
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
	entry.tooltip_text = str(MATERIAL_NAMES.get(item_id, item_id))
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_palette_icon(str(MATERIAL_ICON_PATHS.get(item_id, "")))
	entry.add_child(icon)
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
