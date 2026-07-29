class_name VillaHud
extends CanvasLayer

## 农庄 HUD - 体力、金币、等级、季节/日期、时间、快捷栏

signal quick_slot_selected(index: int)

const GameDataScript = preload("res://scripts/core/game_data.gd")
const ACTION_NAMES := ["锄头", "浇水壶", "斧头", "镐", "鱼竿", "谷物种子"]
const BUILDING_NAMES := ["谷仓", "温室", "风车", "鸡舍", "蜂箱", "水井", "工作台", "路灯", "围栏"]
const MODE_MENU_CLOSE_DELAY := 0.15

@onready var stamina_bar: ProgressBar = $TopBar/StaminaBar
@onready var gold_label: Label = $TopBar/GoldLabel
@onready var level_label: Label = $TopBar/LevelLabel
@onready var exp_bar: ProgressBar = $TopBar/ExpBar
@onready var season_label: Label = $TopBar/SeasonLabel
@onready var time_label: Label = $TopBar/TimeLabel
@onready var mode_menu: PopupPanel = $BottomBar/ModeMenu
@onready var mode_menu_content: VBoxContainer = $BottomBar/ModeMenu/VBox
@onready var farming_mode_button: Button = $BottomBar/ModeMenu/VBox/FarmingModeButton
@onready var building_mode_button: Button = $BottomBar/ModeMenu/VBox/BuildingModeButton
@onready var mode_button: Button = $BottomBar/ActionRow/ModeButton
@onready var quick_bar: HBoxContainer = $BottomBar/ActionRow/QuickBar
@onready var tool_label: Label = $BottomBar/ToolLabel

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
	inventory_ref = inventory
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
	mode_button.text = "建造" if building_mode else "种植"
	mode_button.tooltip_text = "当前：%s模式\n悬停选择模式（P / B）" % mode_button.text
	for index in range(labels.size()):
		var button := Button.new()
		button.name = "Slot%d" % (index + 1)
		button.custom_minimum_size = Vector2(56.0 if building_mode else 68.0, 58.0)
		button.toggle_mode = true
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.text = "%d\n%s" % [index + 1, labels[index]]
		if not building_mode and index == PlayerActionController.SEED_SLOT:
			var quantity: int = (
				inventory_ref.get_item_count(PlayerActionController.SEED_ITEM_ID)
				if inventory_ref
				else 0
			)
			button.text = "%d\n%s x%d" % [index + 1, labels[index], quantity]
		if building_mode:
			_configure_building_button(button, index)
		button.pressed.connect(_on_quick_slot_pressed.bind(index))
		quick_bar.add_child(button)
	refresh_action_bar()


func refresh_action_bar() -> void:
	if quick_bar == null:
		return
	var selected: int = action_controller.get_selected_slot() if action_controller else -1
	var building_mode := _is_building_mode()
	for index in range(quick_bar.get_child_count()):
		var button := quick_bar.get_child(index) as Button
		if button == null:
			continue
		if not building_mode and index == PlayerActionController.SEED_SLOT:
			var quantity: int = (
				inventory_ref.get_item_count(PlayerActionController.SEED_ITEM_ID)
				if inventory_ref
				else 0
			)
			button.text = "%d\n%s x%d" % [index + 1, ACTION_NAMES[index], quantity]
		button.set_pressed_no_signal(index == selected)
		var available := true
		if building_mode:
			available = _building_resources_available(index)
		if index == selected:
			button.modulate = Color(1.0, 0.91, 0.55) if available else Color(0.72, 0.56, 0.42)
		else:
			button.modulate = Color.WHITE if available else Color(0.55, 0.55, 0.55)


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
	var popup_size := Vector2i(170, 96)
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
		cost_parts.append("%s × %d" % [item_id, int(source.cost[item_id])])
	button.tooltip_text = "%s\n占地 %d × %d\n%s" % [
		str(source.get("name", BUILDING_NAMES[index])),
		footprint.x,
		footprint.y,
		"、".join(cost_parts),
	]


func _building_resources_available(index: int) -> bool:
	if economy_ref == null or not economy_ref.has_method("has_resources"):
		return true
	if index < 0 or index >= PlayerActionController.BUILDING_IDS.size():
		return false
	var source: Dictionary = GameDataScript.get_building(
		PlayerActionController.BUILDING_IDS[index]
	)
	return bool(economy_ref.has_resources(source.get("cost", {})))


func set_quick_slot(index: int, item_name: String, quantity: int) -> void:
	if quick_bar == null or index < 0 or index >= quick_bar.get_child_count():
		return
	var slot := quick_bar.get_child(index) as Button
	if slot:
		slot.text = "%d\n%s x%d" % [index + 1, item_name, quantity]
