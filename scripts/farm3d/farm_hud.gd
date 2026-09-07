extends CanvasLayer

signal target_requested(category: String, target_id: String)
signal category_requested(category: String)
signal rest_requested
signal save_requested
signal fishing_requested
signal fishing_action_requested
signal fishing_cancel_requested

const Catalog = preload("res://scripts/farm3d/target_catalog.gd")
const BusScript = preload("res://scripts/ui/hud_message_bus.gd")
const StreamScene = preload("res://scenes/ui/hud_message_stream.tscn")
const InventoryScene = preload("res://scenes/farm3d/inventory.tscn")
const StatusScene = preload("res://scenes/farm3d/status_bar.tscn")
const MinimapScript = preload("res://scripts/farm3d/farm_minimap.gd")
const INK := Color("f8edcf")
const TOP_MARGIN := 18.0
const TOP_BAR_HEIGHT := 62.0
const MESSAGE_WIDTH := 344.0
var _session: Node
var category := ""
var target_id := ""
var buttons: Array[Button] = []
var category_buttons: Dictionary = {}
var bus: Node
var message_stream: PanelContainer
var inventory_ui: Control
var status_bar: PanelContainer
var minimap: Control
var market_view: Control
var windmill_view: Control
var food_workshop_view: Control
var secondary: PanelContainer
var secondary_grid: GridContainer
var secondary_title: Label
var history_panel: PanelContainer
var history_text: RichTextLabel
var _ui: Control
var _menu: VBoxContainer
var _status_seconds := 0.0
var fishing_button: Button
var fishing_panel: PanelContainer
var fishing_hint: Label
var fishing_action: Button
var fishing_progress: ProgressBar
var debug_panel: CanvasLayer
var dialogue_ui: Control
var _dialogue_pause_active := false
var _dialogue_previous_pause := false
var _dialogue_gateway: Node
var _dialogue_gateway_mode := Node.PROCESS_MODE_INHERIT

func configure(session: Node) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session = session
	_ui = Control.new()
	_ui.name = "HUD"
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = preload("res://assets/ui/hud/hud_theme.tres")
	add_child(_ui)
	bus = session.agent_bus if is_instance_valid(session.agent_bus) else BusScript.new()
	if bus.get_parent() == null:
		add_child(bus)
	status_bar = StatusScene.instantiate()
	_ui.add_child(status_bar)
	status_bar.position = Vector2(TOP_MARGIN, TOP_MARGIN)
	status_bar.size = Vector2(750, TOP_BAR_HEIGHT)
	for child in status_bar.get_node("StatusRow").get_children():
		child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if child is Label:
			child.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			child.add_theme_font_size_override("font_size", 17)
			child.custom_minimum_size.x = 70
	status_bar.get_node("StatusRow/StaminaBar").custom_minimum_size.x = 115
	status_bar.get_node("StatusRow/ExpBar").custom_minimum_size.x = 95
	message_stream = StreamScene.instantiate()
	_ui.add_child(message_stream)
	message_stream.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	message_stream.offset_left = -TOP_MARGIN - MESSAGE_WIDTH
	message_stream.offset_right = -TOP_MARGIN
	message_stream.offset_top = TOP_MARGIN
	message_stream.set_expanded_bottom(TOP_MARGIN + 320.0)
	# Match the status bar's centerline, including the panel's one-pixel border.
	message_stream.get_node("Margin").add_theme_constant_override("margin_top", 9)
	message_stream.get_node("Margin").add_theme_constant_override("margin_bottom", 9)
	message_stream.title_label.text = "消息"
	message_stream.configure(bus)
	message_stream.history_requested.connect(_toggle_history)
	_make_menu()
	minimap = MinimapScript.new()
	minimap.player = session.player
	minimap.session = session
	_ui.add_child(minimap)
	_make_history()
	inventory_ui = InventoryScene.instantiate()
	_ui.add_child(inventory_ui)
	inventory_ui.configure(session.inventory)
	inventory_ui.target_requested.connect(func(next_category: String, id: String): target_requested.emit(next_category, id))
	inventory_ui.blocking_opened.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
	market_view = preload("res://scripts/farm3d/market_view.gd").new()
	_ui.add_child(market_view)
	market_view.configure(session)
	market_view.closed.connect(func(): _session.player.ui_blocked = is_modal_open())
	windmill_view = preload("res://scripts/farm3d/windmill_view.gd").new()
	_ui.add_child(windmill_view)
	windmill_view.configure(session)
	windmill_view.closed.connect(func(): _session.player.ui_blocked = is_modal_open())
	food_workshop_view = preload("res://scripts/farm3d/windmill_view.gd").new()
	_ui.add_child(food_workshop_view)
	food_workshop_view.configure(session,"food_workshop")
	food_workshop_view.closed.connect(func(): _session.player.ui_blocked = is_modal_open())
	if is_instance_valid(session.agent_runtime):
		dialogue_ui = preload("res://scenes/ui/dialogue_ui.tscn").instantiate()
		dialogue_ui.process_mode = Node.PROCESS_MODE_ALWAYS
		dialogue_ui.mouse_filter = Control.MOUSE_FILTER_STOP
		_ui.add_child(dialogue_ui)
		dialogue_ui.configure_agent_runtime(session.agent_runtime)
		dialogue_ui.agent_dialogue_opened.connect(_on_dialogue_opened)
		dialogue_ui.agent_dialogue_closed.connect(_on_dialogue_closed)
		if OS.is_debug_build():
			debug_panel = preload("res://scenes/ui/debug_panel.tscn").instantiate()
			add_child(debug_panel)
			debug_panel.configure_farm3d(session.agent_runtime)
			debug_panel.closed.connect(func(): _session.player.ui_blocked = is_modal_open())
	session.buildings.building_construction_completed.connect(func(building: BuildingInstance): notify_message("%s建造完成" % building.data.display_name, true))
	get_viewport().size_changed.connect(_layout)
	_layout()
	_connect_notifications()
	_refresh_status()
	notify_message("选择农田、种子或建筑后点击地面放置；Esc 收起。", true)
	bus.publish("操作", "info", "空手点击成熟作物收获、枯萎作物清理、生长中的作物浇水。I 打开背包。")

func _on_dialogue_opened(_agent_id: String) -> void:
	if _dialogue_pause_active:
		return
	_dialogue_previous_pause = get_tree().paused
	_dialogue_pause_active = true
	_session.player.set_dialogue_input_blocked(true)
	_session.player.ui_blocked = true
	_dialogue_gateway = _session.agent_runtime.gateway
	_dialogue_gateway_mode = _dialogue_gateway.process_mode
	_dialogue_gateway.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_dialogue_closed(_agent_id: String, _request_id: String) -> void:
	_release_dialogue_pause()
	_session.player.ui_blocked = is_modal_open()

func _release_dialogue_pause() -> void:
	if not _dialogue_pause_active:
		return
	_dialogue_pause_active = false
	_session.player.set_dialogue_input_blocked(false)
	if is_instance_valid(_dialogue_gateway):
		_dialogue_gateway.process_mode = _dialogue_gateway_mode
	get_tree().paused = _dialogue_previous_pause

func _exit_tree() -> void:
	_release_dialogue_pause()

func _make_menu() -> void:
	_menu = VBoxContainer.new()
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_theme_constant_override("separation", 8)
	_ui.add_child(_menu)
	_menu.resized.connect(_position_menu)
	secondary = PanelContainer.new()
	secondary.add_theme_stylebox_override("panel", _style(Color("26372bee"), Color("a89058")))
	_menu.add_child(secondary)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 8)
	secondary.add_child(contents)
	var header := HBoxContainer.new()
	contents.add_child(header)
	secondary_title = Label.new()
	secondary_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	secondary_title.add_theme_font_size_override("font_size", 18)
	header.add_child(secondary_title)
	var close := _button("收起  Esc", Vector2(100, 30))
	close.pressed.connect(func(): category_requested.emit(""))
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 216
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	contents.add_child(scroll)
	secondary_grid = GridContainer.new()
	secondary_grid.columns = 5
	secondary_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	secondary_grid.add_theme_constant_override("h_separation", 6)
	secondary_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(secondary_grid)
	secondary.hide()
	var base := PanelContainer.new()
	base.add_theme_stylebox_override("panel", _style(Color("202e25f2"), Color("a89058")))
	_menu.add_child(base)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	base.add_child(row)
	for entry in [["farmland", "农田"], ["seed", "种子"], ["building", "建筑"]]:
		var button := _button(entry[1], Vector2(122, 48))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): category_requested.emit("" if category == entry[0] and secondary.visible else entry[0]))
		category_buttons[entry[0]] = button
		row.add_child(button)
	for entry in [["背包  I", toggle_inventory], ["休息", func(): rest_requested.emit()], ["保存", func(): save_requested.emit()]]:
		var button := _button(entry[0], Vector2(78, 48))
		button.pressed.connect(entry[1])
		row.add_child(button)
	fishing_button = _button("鱼竿",Vector2(88,48))
	fishing_button.disabled = true
	fishing_button.icon = preload("res://assets/ui/action_icons/fishing_rod.png")
	fishing_button.expand_icon = true
	fishing_button.add_theme_constant_override("icon_max_width",22)
	fishing_button.pressed.connect(func(): fishing_requested.emit())
	row.add_child(fishing_button)
	row.move_child(fishing_button,3)
	if OS.is_debug_build() and is_instance_valid(_session.agent_runtime):
		var debug := _button("调试", Vector2(70, 48))
		debug.name = "DebugEntry"
		debug.pressed.connect(func():
			close_panels()
			debug_panel.open()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_session.player.ui_blocked = true)
		row.add_child(debug)
	fishing_panel = PanelContainer.new()
	fishing_panel.name = "FishingPanel"
	fishing_panel.add_theme_stylebox_override("panel",_style(Color("202e25f2"),Color("c4ab70")))
	_menu.add_child(fishing_panel)
	_menu.move_child(fishing_panel,0)
	var fishing_box := VBoxContainer.new()
	fishing_panel.add_child(fishing_box)
	var fishing_row := HBoxContainer.new()
	fishing_box.add_child(fishing_row)
	fishing_hint = Label.new()
	fishing_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fishing_hint.add_theme_font_size_override("font_size",18)
	fishing_row.add_child(fishing_hint)
	fishing_action = _button("甩竿  E / 左键",Vector2(170,42))
	fishing_action.pressed.connect(func(): fishing_action_requested.emit())
	fishing_row.add_child(fishing_action)
	var stow := _button("收竿 Esc",Vector2(100,42))
	stow.pressed.connect(func(): fishing_cancel_requested.emit())
	fishing_row.add_child(stow)
	fishing_progress = ProgressBar.new()
	fishing_progress.custom_minimum_size.y = 10
	fishing_progress.max_value = 1
	fishing_progress.show_percentage = false
	fishing_box.add_child(fishing_progress)
	fishing_panel.hide()

func set_fishing_status(equipped: bool, hint: String, action: String, can_act: bool, bite_progress: float) -> void:
	var layout_changed := fishing_panel.visible != equipped or fishing_progress.visible != (bite_progress >= 0)
	fishing_panel.visible = equipped
	fishing_hint.text = hint
	fishing_hint.add_theme_color_override("font_color",Color("ffe38e") if bite_progress >= 0 else INK)
	fishing_action.text = action
	fishing_action.disabled = not can_act
	fishing_progress.visible = bite_progress >= 0
	fishing_progress.value = maxf(0,bite_progress)
	fishing_button.text = "收竿" if equipped else "鱼竿"
	if layout_changed:
		_layout.call_deferred()

func show_category(next_category: String) -> void:
	category = next_category
	target_id = ""
	for child in secondary_grid.get_children():
		child.free()
	buttons.clear()
	secondary.visible = not category.is_empty()
	secondary_grid.get_parent().custom_minimum_size.y = 110 if category == "farmland" else 216
	if secondary.visible:
		secondary_title.text = {"farmland": "农田", "seed": "种子与树苗", "building": "建筑"}.get(category, "")
		for entry in Catalog.entries(category):
			var button := _button("", Vector2(126, 96))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.set_meta("target_id", entry.id)
			button.set_meta("entry", entry)
			button.icon = entry.get("icon")
			button.expand_icon = true
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			button.add_theme_constant_override("icon_max_width", 32)
			button.pressed.connect(func(): target_requested.emit(category, entry.id))
			buttons.append(button)
			secondary_grid.add_child(button)
	_refresh_buttons()
	_layout()

func set_target(next_category: String, id: String) -> void:
	if category != next_category:
		show_category(next_category)
	target_id = id
	secondary.hide()
	_refresh_buttons()
	_layout()

func _refresh_buttons() -> void:
	for id in category_buttons:
		category_buttons[id].text = {"farmland": "农田", "seed": "种子", "building": "建筑"}[id]
		category_buttons[id].add_theme_stylebox_override("normal", _style(Color("64744b") if category == id else Color("354438"), Color("c4ab70") if category == id else Color("566449")))
	for button in buttons:
		var entry: Dictionary = button.get_meta("entry")
		if target_id == entry.id:
			category_buttons[category].text = entry.name
		button.text = "%s%s\n%s" % [entry.name, " ×%d" % _session.inventory.get_item_count(entry.id) if category == "seed" else "", entry.detail]
		button.add_theme_stylebox_override("normal", _style(Color("69784c") if target_id == entry.id else Color("354438"), Color("e6c882") if target_id == entry.id else Color("566449")))

func _process(delta: float) -> void:
	if _session == null:
		return
	_status_seconds -= delta
	if _status_seconds <= 0:
		_status_seconds = 0.25
		_refresh_status()
		_refresh_buttons()
	_session.player.ui_blocked = is_modal_open()

func _refresh_status() -> void:
	var state := get_node("/root/GameState")
	var ps = state.player_state
	var row := status_bar.get_node("StatusRow")
	row.get_node("StaminaBar").max_value = ps.max_stamina
	row.get_node("StaminaBar").value = ps.stamina
	row.get_node("StaminaBar/Value").text = "体力 %d" % ps.stamina if row.has_node("StaminaBar/Value") else ""
	row.get_node("GoldLabel").text = "金币 %d" % state.gold
	row.get_node("LevelLabel").text = "Lv.%d" % ps.level
	row.get_node("ExpBar").value = ps.get_exp_progress() * 100
	row.get_node("SeasonLabel").text = "%s %d/%d" % [["春", "夏", "秋", "冬"][_session.season.current_season], _session.season.current_day, SeasonSystem.DAYS_PER_SEASON]
	row.get_node("TimeLabel").text = "%02d:%02d" % [_session.season.hour, _session.season.minute]

func notify_message(text: String, success: bool = true) -> void:
	bus.publish("农庄", "success" if success else "warning", text, {"game_time": "%02d:%02d" % [_session.season.hour, _session.season.minute]})

func toggle_minimap() -> void:
	minimap.visible = not minimap.visible

func toggle_inventory() -> void:
	fishing_cancel_requested.emit()
	food_workshop_view.close_panel()
	windmill_view.close_panel()
	market_view.close_market()
	history_panel.hide()
	inventory_ui.toggle()
	_session.player.ui_blocked = is_modal_open()

func is_modal_open() -> bool:
	if (debug_panel != null and debug_panel.visible) or (dialogue_ui != null and dialogue_ui.visible):
		return true
	return inventory_ui != null and (inventory_ui.visible or history_panel.visible or (market_view != null and market_view.visible) or (windmill_view != null and windmill_view.visible) or (food_workshop_view != null and food_workshop_view.visible))

func open_windmill(building: BuildingInstance) -> bool:
	close_panels()
	var view: Control = food_workshop_view if building.building_id == "food_workshop" else windmill_view
	var opened: bool = view.open_for(building)
	_session.player.ui_blocked = opened
	return opened

func open_market() -> void:
	close_panels()
	market_view.open_market()
	_session.player.ui_blocked = true

func close_panels() -> void:
	if debug_panel != null:
		debug_panel.close()
	if dialogue_ui != null:
		dialogue_ui.close()
	if food_workshop_view != null:
		food_workshop_view.close_panel()
	if windmill_view != null:
		windmill_view.close_panel()
	inventory_ui.close()
	history_panel.hide()
	if market_view != null:
		market_view.close_market()
	_session.player.ui_blocked = false

func _make_history() -> void:
	history_panel = PanelContainer.new()
	history_panel.add_theme_stylebox_override("panel", _style(Color("202e25fa"), Color("b59c63")))
	_ui.add_child(history_panel)
	var box := VBoxContainer.new()
	history_panel.add_child(box)
	var close := _button("消息记录  ·  关闭", Vector2(0, 36))
	close.pressed.connect(func(): history_panel.hide())
	box.add_child(close)
	history_text = RichTextLabel.new()
	history_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_text.add_theme_font_size_override("normal_font_size", 18)
	box.add_child(history_text)
	history_panel.hide()

func _toggle_history() -> void:
	fishing_cancel_requested.emit()
	food_workshop_view.close_panel()
	windmill_view.close_panel()
	market_view.close_market()
	inventory_ui.close()
	history_panel.visible = not history_panel.visible
	history_text.text = ""
	for record in bus.get_recent():
		history_text.add_text("%s  %s%s\n\n" % [record.game_time, record.text, " ×%d" % record.count if record.count > 1 else ""])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_session.player.ui_blocked = is_modal_open()

func _layout() -> void:
	var viewport_size := _ui.size
	var width := minf(840, viewport_size.x - 36)
	_menu.size = Vector2(width, 0)
	_position_menu()
	history_panel.position = (viewport_size - Vector2(720, 480)) * 0.5
	history_panel.size = Vector2(720, 480)

func _position_menu() -> void:
	_menu.position = Vector2((_ui.size.x - _menu.size.x) * 0.5, _ui.size.y - _menu.size.y - 18)
	if minimap != null:
		minimap.position = _ui.size - minimap.size - Vector2(18, 18)
		if minimap.position.x < _menu.position.x + _menu.size.x + 12:
			minimap.position.y = _menu.position.y - minimap.size.y - 12

func _button(text: String, minimum: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_stylebox_override("normal", _style(Color("354438"), Color("566449")))
	button.add_theme_stylebox_override("hover", _style(Color("58684a"), Color("c4ab70")))
	button.add_theme_stylebox_override("pressed", _style(Color("768151"), Color("ead395")))
	return button

func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _connect_notifications() -> void:
	var events := get_node("/root/EventBus")
	events.season_changed.connect(func(value: int): notify_message("季节变为%s" % ["春季", "夏季", "秋季", "冬季"][value]))
	events.crop_matured.connect(func(gx: int, gz: int):
		var cell: GridCell = _session.grid.get_cell(gx, gz)
		if cell != null and cell.crop_instance != null:
			notify_message("%s成熟了，收起目标后点击即可收获" % cell.crop_instance.crop_data.crop_name)
	)
