extends Control

signal closed
var session: Farm3DSession
var building: BuildingInstance
var details: Label
var feedback: Label
var collect_button: Button
var maintenance_button: Button
var _body_scroll: ScrollContainer
var _owns_pause := false
var _previous_pause := false
var _previous_input_blocked := false

func configure(farm_session: Farm3DSession) -> void:
	session = farm_session
	name = "BeehiveView"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(.06,.1,.06,.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("faf3dd")
	style.set_corner_radius_all(14)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel",style)
	panel.theme = Theme.new()
	panel.theme.default_font_size = 18
	panel.theme.set_color("font_color","Label",Color("493e2b"))
	panel.theme.set_constant("outline_size","Label",0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",16)
	panel.add_child(box)
	var title := Label.new()
	title.text = "蜂箱 · 花蜜工坊"
	title.add_theme_font_size_override("font_size",28)
	box.add_child(title)
	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_body_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",16)
	_body_scroll.add_child(body)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(details)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(feedback)
	collect_button = _button(box,"收取我的蜂蜜",_collect)
	maintenance_button = _button(box,"维护蜂箱",_maintain)
	_button(box,"关闭 · Esc",close_panel)
	session.state_loaded.connect(close_panel)
	resized.connect(_layout)
	_layout()
	hide()

func _layout() -> void:
	_body_scroll.custom_minimum_size = Vector2(clampf(size.x-100,220,420),clampf(size.y-340,100,490))

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func open_for(target: BuildingInstance) -> bool:
	if target == null or target.building_id != "beehive" or not target.is_construction_complete(): return false
	close_panel()
	building = target
	building.tree_exiting.connect(close_panel, CONNECT_ONE_SHOT)
	_previous_pause = get_tree().paused
	_previous_input_blocked = session.player._dialogue_input_blocked
	session.player.set_dialogue_input_blocked(true)
	_owns_pause = true
	get_tree().paused = true
	feedback.text = "时间已暂停。关闭后蜜蜂继续采蜜。"
	refresh()
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true

func close_panel() -> void:
	if is_instance_valid(building) and building.tree_exiting.is_connected(close_panel):
		building.tree_exiting.disconnect(close_panel)
	building = null
	if _owns_pause:
		_owns_pause = false
		get_tree().paused = _previous_pause
		session.player.set_dialogue_input_blocked(_previous_input_blocked)
	hide()
	closed.emit()

func handle_escape() -> void:
	close_panel()

func _exit_tree() -> void:
	if _owns_pause:
		get_tree().paused = _previous_pause
		if is_instance_valid(session.player): session.player.set_dialogue_input_blocked(_previous_input_blocked)

func refresh() -> void:
	if not is_instance_valid(building): return
	var snapshot := session.production.get_beehive_snapshot(building)
	var states := {"working":"蜜蜂正在采蜜", "no_flowers":"等待附近花朵成熟", "full":"储蜜空间不足，请先收取", "maintenance":"需要维护，暂时停产", "construction":"建造中"}
	var lines: Array[String] = [str(states.get(snapshot.status,"")),
		"采蜜半径：%d 格（不受 3×3 建筑占地限制）" % snapshot.radius,
		"可采花朵：%d 株（采蜜不会消耗花朵）" % snapshot.flower_count]
	for owner in snapshot.owners:
		lines.append("  %s的花：%d 株" % [_owner_name(owner),snapshot.owners[owner]])
	lines.append("\n花朵平均距离：%.1f 格 · 最多采集 4 株" % snapshot.average_distance)
	lines.append("本批：%s · 剩余：%s（游戏时间）" % [_duration(snapshot.duration_minutes), _duration(snapshot.remaining_minutes)])
	lines.append("距离越远，往返采蜜与酿蜜耗时越长。")
	for owner in snapshot.next_owners:
		lines.append("  预计归%s：%s" % [_owner_name(owner),_counts(snapshot.next_owners[owner])])
	lines.append("混合花田按花朵轮流分配完整产物。NPC 的份额自动送入其库存。")
	var available: Dictionary = building.producer_state.outputs if building.owner_id == "player" else building.producer_state.customer_outputs.get("player",{})
	lines.append("\n我的待收取：%s" % _counts(available))
	for owner in snapshot.pending:
		if owner != "player": lines.append("代管%s：%s（等待接收）" % [_owner_name(owner),_counts(snapshot.pending[owner])])
	details.text = "\n".join(lines)
	collect_button.disabled = available.is_empty()
	var quote := session.production.get_maintenance_quote(building)
	maintenance_button.text = "维护：%s · %d 金币" % [_counts(quote.get("materials",{})),int(quote.get("gold_cost",0))]
	maintenance_button.disabled = building.owner_id != "player" or session.production.get_maintenance_state(building) not in ["warning","overdue"]

func _duration(minutes: int) -> String:
	return "%d 小时 %d 分" % [minutes / 60, minutes % 60]

func _owner_name(actor: String) -> String:
	return "我" if actor == "player" else session.agent_runtime.get_agent_display_name(actor)

func _counts(goods: Dictionary) -> String:
	var parts: Array[String] = []
	for id in goods:
		parts.append("%s ×%d" % [str(GameData.get_item(id).get("name",id)),goods[id]])
	return "暂无" if parts.is_empty() else "、".join(parts)

func _collect() -> void:
	var result := session.production.collect_outputs(building,session.inventory)
	feedback.text = "已收取：%s" % _counts(result.get("requested",{})) if result.get("ok",false) else "背包空间不足或没有可收取产物，蜂蜜仍保存在蜂箱。"
	_save_action(result.get("ok",false))
	refresh()

func _maintain() -> void:
	if session.production.building_service == null: return
	var result: Dictionary = session.production.building_service.maintain(building,"player")
	feedback.text = "维护已开始，关闭面板后继续。" if result.get("ok",false) else "维护材料或金币不足。"
	_save_action(result.get("ok",false))
	refresh()

func _save_action(success: bool) -> void:
	if success and session.auto_save and not session.save_game():
		feedback.text += " 存档失败，请稍后手动保存。"
