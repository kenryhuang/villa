extends CanvasLayer

signal mode_requested(mode: String)
signal rest_requested
signal save_requested

const MODES := ["hoe", "seed", "water", "harvest"]
const NAMES := ["锄头", "谷物种子", "浇水壶", "收获"]
const ICONS := ["res://assets/ui/action_icons/hoe.png", "res://assets/crops/grain/painted/stage_0/variant_0_front.png", "res://assets/ui/action_icons/watering_can.png", "res://assets/ui/action_icons/harvest_basket.svg"]
const INK := Color("f8edcf")
var buttons: Array[Button] = []
var clock_label: Label
var stock_label: Label
var target_label: Label
var message_label: Label
var stamina_bar: ProgressBar
var _message_seconds := 0.0
var _session: Node
var _mode := "hoe"

func configure(session: Node) -> void:
	_session = session
	var ui := Control.new()
	ui.name = "HUD"
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	var title := _label("暖阳农庄", 30)
	title.position = Vector2(32, 26)
	ui.add_child(title)
	var subtitle := _label("耕一方田，等一季收成", 16)
	subtitle.position = Vector2(34, 67)
	subtitle.modulate.a = 0.78
	ui.add_child(subtitle)
	var status := PanelContainer.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	status.position = Vector2(-352, 26)
	status.custom_minimum_size = Vector2(320, 156)
	status.add_theme_stylebox_override("panel", _panel(Color("273925e8")))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(status)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_child(rows)
	clock_label = _label("", 21)
	stock_label = _label("", 17)
	rows.add_child(clock_label)
	rows.add_child(stock_label)
	stamina_bar = ProgressBar.new()
	stamina_bar.custom_minimum_size = Vector2(280, 7)
	stamina_bar.show_percentage = false
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamina_bar.add_theme_stylebox_override("background", _panel(Color("152a1a"), 0))
	stamina_bar.add_theme_stylebox_override("fill", _panel(Color("afc577"), 0))
	rows.add_child(stamina_bar)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	rows.add_child(controls)
	for entry in [["休息到次日", rest_requested], ["保存", save_requested]]:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_stylebox_override("normal", _panel(Color("3c5037"), 5))
		button.add_theme_color_override("font_color", INK)
		button.pressed.connect(entry[1].emit)
		controls.add_child(button)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.position = Vector2(-330, -210)
	bottom.custom_minimum_size = Vector2(660, 180)
	bottom.add_theme_constant_override("separation", 9)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bottom)
	message_label = _label("", 18)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(message_label)
	target_label = _label("靠近草地，用锄头开垦第一块田", 18)
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(target_label)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bar)
	for index in MODES.size():
		var button := Button.new()
		button.name = MODES[index].capitalize()
		button.custom_minimum_size = Vector2(140, 88)
		button.text = "%d  %s" % [index + 1, NAMES[index]]
		button.icon = load(ICONS[index]) as Texture2D
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 34)
		button.add_theme_font_size_override("font_size", 17)
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", INK)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func(): mode_requested.emit(MODES[index]))
		bar.add_child(button)
		buttons.append(button)
	var help := _label("1–4 选择工具  ·  左键耕作 / E 操作前方  ·  WASD 移动  ·  右键转镜头  ·  Tab 总览", 15)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(help)
	set_mode("hoe")
	refresh()

func _process(delta: float) -> void:
	if _session == null:
		return
	refresh()
	_message_seconds = maxf(0.0, _message_seconds - delta)
	message_label.visible = _message_seconds > 0.0

func refresh() -> void:
	var season = _session.season
	clock_label.text = "%s · 第 %d 天    %02d:%02d" % [["春", "夏", "秋", "冬"][int(season.current_season)], season.current_day, season.hour, season.minute]
	var state = get_node("/root/GameState").player_state
	stock_label.text = "种子 %d    谷物 %d    体力 %d/%d" % [_session.inventory.get_item_count("grain_seed"), _session.inventory.get_item_count("grain"), state.stamina, state.max_stamina]
	stamina_bar.max_value = state.max_stamina
	stamina_bar.value = state.stamina

func set_mode(mode: String) -> void:
	_mode = mode
	for index in buttons.size():
		var selected: bool = MODES[index] == mode
		var style := _panel(Color("586e36f5") if selected else Color("283923ed"), 10)
		style.border_color = Color("ddcc87") if selected else Color("647452")
		style.set_border_width_all(2 if selected else 1)
		buttons[index].add_theme_stylebox_override("normal", style)
		buttons[index].add_theme_stylebox_override("hover", _panel(Color("677c45"), 10))
		buttons[index].add_theme_stylebox_override("pressed", style)

func show_target(text: String, allowed: bool) -> void:
	target_label.text = text
	target_label.modulate = INK if allowed else Color("e9c4a3")

func notify_message(text: String, success: bool = true) -> void:
	message_label.text = text
	message_label.modulate = Color("f6dfa1") if success else Color("f0b29c")
	_message_seconds = 3.2
	message_label.show()

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_shadow_color", Color("182515cf"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label

func _panel(color: Color, padding: int = 14) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(9)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box
