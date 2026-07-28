class_name VillaHud
extends CanvasLayer

## 农庄 HUD - 体力、金币、等级、季节/日期、时间、快捷栏

signal quick_slot_selected(index: int)

const ACTION_NAMES := ["锄头", "浇水壶", "斧头", "镐", "鱼竿", "谷物种子"]

@onready var stamina_bar: ProgressBar = $TopBar/StaminaBar
@onready var gold_label: Label = $TopBar/GoldLabel
@onready var level_label: Label = $TopBar/LevelLabel
@onready var exp_bar: ProgressBar = $TopBar/ExpBar
@onready var season_label: Label = $TopBar/SeasonLabel
@onready var time_label: Label = $TopBar/TimeLabel
@onready var quick_bar: HBoxContainer = $BottomBar/QuickBar
@onready var tool_label: Label = $BottomBar/ToolLabel

var _event_bus
var action_controller: Variant
var inventory_ref: Variant


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


func _init_display() -> void:
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		_on_stamina_changed(game_state.player_state.stamina)
		_on_gold_changed(game_state.gold)
		_on_level_changed(game_state.player_state.level)

	var season_system = get_node_or_null("/root/SeasonSystem")
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
	var season_system = get_node_or_null("/root/SeasonSystem")
	if season_system:
		_update_season_display(season_system)


func _on_day_changed(_total_day: int) -> void:
	var season_system = get_node_or_null("/root/SeasonSystem")
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


func configure_action_bar(
	controller: Variant,
	inventory: Variant
) -> void:
	action_controller = controller
	inventory_ref = inventory
	for index in range(quick_bar.get_child_count()):
		var button := quick_bar.get_child(index) as Button
		if button == null:
			continue
		var callback := _on_quick_slot_pressed.bind(index)
		if not button.pressed.is_connected(callback):
			button.pressed.connect(callback)
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
	refresh_action_bar()
	if action_controller:
		var selected: int = action_controller.get_selected_slot()
		_on_action_selection_changed(selected, ACTION_NAMES[selected])


func refresh_action_bar() -> void:
	if quick_bar == null:
		return
	var selected: int = action_controller.get_selected_slot() if action_controller else 0
	for index in range(quick_bar.get_child_count()):
		var button := quick_bar.get_child(index) as Button
		if button == null:
			continue
		var action_name: String = ACTION_NAMES[index]
		if index == PlayerActionController.SEED_SLOT:
			var quantity: int = (
				inventory_ref.get_item_count(PlayerActionController.SEED_ITEM_ID)
				if inventory_ref
				else 0
			)
			button.text = "%d\n%s x%d" % [index + 1, action_name, quantity]
		else:
			button.text = "%d\n%s" % [index + 1, action_name]
		button.set_pressed_no_signal(index == selected)
		button.modulate = Color(1.0, 0.91, 0.55) if index == selected else Color.WHITE


func _on_quick_slot_pressed(index: int) -> void:
	quick_slot_selected.emit(index)
	if action_controller:
		action_controller.select_slot(index)


func _on_action_selection_changed(index: int, label: String) -> void:
	if tool_label:
		tool_label.text = label
	refresh_action_bar()


func set_quick_slot(index: int, item_name: String, quantity: int) -> void:
	if quick_bar == null or index < 0 or index >= quick_bar.get_child_count():
		return
	var slot := quick_bar.get_child(index) as Button
	if slot:
		slot.text = "%d\n%s x%d" % [index + 1, item_name, quantity]
