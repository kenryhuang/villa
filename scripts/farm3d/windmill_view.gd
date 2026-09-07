extends Control

signal closed
const LogicScene = preload("res://scenes/ui/economy/building_production_panel.tscn")
const LogicScript = preload("res://scripts/farm3d/windmill_panel_controller.gd")
const Icons = preload("res://scripts/farm3d/target_catalog.gd")
const PAPER := Color("faf7ef")
const INK := Color("354032")
const GREEN := Color("47674c")
const MUTED := Color("787f70")
const LINE := Color("dedfd1")
var controller: BuildingProductionPanel
var station_id := "windmill"
var station_name := "风车"
var session: Farm3DSession
var building: BuildingInstance
var window: PanelContainer
var recipe_buttons: Dictionary = {}
var start_button: Button
var batches_spin: SpinBox
var collect_button: Button
var maintenance_button: Button
var repair_confirm: Button
var repair_modal: Control
var _repair_text: Label
var _sections: HBoxContainer
var _cards: Array[PanelContainer] = []
var _tabs: HBoxContainer
var _tab := 1
var _narrow := false
var _recipe_name: Label
var _recipe_use: Label
var _input: Label
var _output: Label
var _owned: Label
var _input_icon: TextureRect
var _output_icon: TextureRect
var _duration: Label
var _rental_fee: Label
var _waiting: Label
var _prices: Label
var _margin: Label
var _reason: Label
var _status: Label
var _gold: Label
var _maintenance: Label
var _queue_count: Label
var _queue_list: VBoxContainer
var _goods: VBoxContainer
var _capacity: Label
var _collect_reason: Label
var _owns_pause := false
var _previous_pause := false
var _refresh_seconds := 0.0
var _rendering := false
var _goods_snapshot: Dictionary = {}
var _feedback := ""
var _feedback_seconds := 0.0

func configure(farm_session: Farm3DSession, station := "windmill") -> void:
	session = farm_session
	station_id = station
	station_name = str(GameData.get_building(station).name)
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "WindmillView" if station_id == "windmill" else "FoodWorkshopView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Theme.new()
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", INK)
	theme.set_constant("outline_size", "Label", 0)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_stylebox("normal", "LineEdit", _style(Color("fffdf7")))
	var dimmer := ColorRect.new()
	dimmer.color = Color(.06, .12, .08, .63)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)
	window = PanelContainer.new()
	window.add_theme_stylebox_override("panel", _style(PAPER, 20))
	add_child(window)
	var shell := _vbox(window, 14)
	var header := _hbox(shell, 16)
	_label(header, station_name, 28)
	_status = _label(header, "", 17, GREEN)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gold = _label(header, "", 15, MUTED)
	_button(header, "关闭 · Esc", close_panel)
	var notice := _hbox(shell)
	var pause_label := _label(notice, "Ⅱ 游戏时间已暂停 · 关闭面板后继续生产", 15, MUTED)
	pause_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(notice, "自然风驱动 · 无需燃料" if station_id == "windmill" else "农产与鱼获加工 · 使用背包原料", 15, GREEN)
	_tabs = _hbox(shell)
	for index in 3:
		var button := _button(_tabs, ["配方", "加工", "队列与成品"][index], _show_tab.bind(index))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	_sections = _hbox(scroll, 16)
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_make_recipes()
	_make_process()
	_make_queue()
	var footer := _hbox(shell, 12)
	_maintenance = _label(footer, "", 15, MUTED)
	_maintenance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	maintenance_button = _button(footer, "查看维护", _open_repair)
	_make_repair()
	controller = LogicScene.instantiate()
	controller.set_script(LogicScript)
	add_child(controller)
	controller.hide()
	controller.configure_farm(session)
	controller.snapshot_changed.connect(func(_value: String): _render())
	session.state_loaded.connect(close_panel)
	resized.connect(_layout)
	hide()

func _make_recipes() -> void:
	var box := _card(Color("f0f1e6"), 220)
	_label(box, "选择配方", 20)
	var recipes := RecipeDatabase.get_recipes_for_station(station_id)
	_label(box, "%d 种加工方式" % recipes.size(), 14, MUTED)
	var recipe_box := box
	if station_id == "food_workshop":
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size.y = 350
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(scroll)
		recipe_box = _vbox(scroll)
		recipe_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for recipe in recipes:
		var id := str(recipe.id)
		var subtitle := "%s → %d 份" % [_counts(recipe.inputs),int(recipe.outputs[id])] if station_id == "windmill" else "%d 分钟 · %d 份" % [recipe.duration_minutes,recipe.outputs[id]]
		var button := _button(recipe_box, "%s\n%s" % [recipe.display_name,subtitle], _select_recipe.bind(id))
		button.custom_minimum_size.y = 82
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = Icons.item_icon(id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 34)
		recipe_buttons[id] = button
	_label(box, "从田间到餐桌", 17, GREEN)
	var help := _label(box, "面粉供给食品工坊，饲料供给鸡舍。成品也可带到市集出售。" if station_id == "windmill" else "风车面粉、农产和鱼获继续加工。成品收进背包后可在市集出售。", 15, MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _make_process() -> void:
	var box := _card(PAPER, 410)
	_label(box, "RECIPE / 加工配方", 13, Color("a48043"))
	_recipe_name = _label(box, "", 27)
	_recipe_use = _label(box, "", 15, MUTED)
	_recipe_use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var flow := _hbox(box, 12)
	var left := _vbox(flow)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_icon = _icon(left)
	_input = _label(left, "", 19)
	_input.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_owned = _label(left, "", 14, MUTED)
	_owned.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(flow, "→", 28, GREEN)
	var right := _vbox(flow)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output_icon = _icon(right)
	_output = _label(right, "", 19)
	_label(right, "完成后暂存于"+station_name, 14, MUTED)
	_label(box, "生产批量", 18)
	var batch := _hbox(box)
	_button(batch, "−", func(): controller.set_batches(controller.batches - 1))
	batches_spin = SpinBox.new()
	batches_spin.min_value = 1
	batches_spin.max_value = 9999
	batches_spin.step = 1
	batches_spin.custom_minimum_size = Vector2(120, 42)
	batch.add_child(batches_spin)
	batches_spin.value_changed.connect(func(value: float):
		if not _rendering:
			controller.set_batches(int(value))
	)
	_button(batch, "＋", func(): controller.set_batches(controller.batches + 1))
	_label(batch, "批", 16, MUTED)
	_button(batch, "最大", func(): controller.set_batches(maxi(1, controller.max_batches)))
	_duration = _metric(box, "本单加工时间")
	_rental_fee = _metric(box, "NPC 租用费")
	_waiting = _metric(box, "排队等待时间")
	_metric(box, "原料来源").text = "我的背包"
	_prices = _metric(box, "原料 / 成品卖出参考")
	_margin = _metric(box, "加工价差 · 未计维护成本")
	_label(box, "按当前批量行情估算，最终售价随市场变化。", 13, MUTED)
	start_button = _button(box, "投入原料并加入队列", _start)
	start_button.custom_minimum_size.y = 48
	start_button.add_theme_stylebox_override("normal", _style(GREEN))
	start_button.add_theme_stylebox_override("hover", _style(Color("38573d")))
	start_button.add_theme_color_override("font_color", Color.WHITE)
	start_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_reason = _label(box, "", 15, Color("ac5c42"))
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var note := _label(box, "提交时一次扣除本单原料，关闭面板不会取消订单。", 13, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _make_queue() -> void:
	var box := _card(Color("f5f5eb"), 320)
	var header := _hbox(box)
	_label(header, "生产队列", 20).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_count = _label(header, "", 14, MUTED)
	_queue_list = _vbox(box, 10)
	_label(box, "按顺序加工 · 暂停保留进度与原料", 13, MUTED)
	var storage_header := _hbox(box)
	_label(storage_header, "待收成品", 20).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_capacity = _label(storage_header, "", 14, MUTED)
	_goods = _vbox(box, 8)
	collect_button = _button(box, "全部收进背包", _collect.bind(""))
	_collect_reason = _label(box, "", 14, MUTED)
	_collect_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func open_for(target: BuildingInstance) -> bool:
	if target == null or not target.is_construction_complete() or target.building_id != station_id:
		return false
	close_panel()
	building = target
	building.tree_exiting.connect(close_panel, CONNECT_ONE_SHOT)
	_previous_pause = get_tree().paused
	_owns_pause = true
	get_tree().paused = true
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_goods_snapshot = {"refresh": true}
	_feedback_seconds = 0
	controller.show_building(building)
	_layout()
	_refresh_seconds = 0
	return true

func close_panel() -> void:
	if is_instance_valid(building) and building.tree_exiting.is_connected(close_panel):
		building.tree_exiting.disconnect(close_panel)
	building = null
	if _owns_pause:
		_owns_pause = false
		get_tree().paused = _previous_pause
	if repair_modal != null:
		repair_modal.hide()
	hide()
	closed.emit()

func handle_escape() -> void:
	if repair_modal.visible:
		repair_modal.hide()
	else:
		close_panel()

func _exit_tree() -> void:
	if _owns_pause:
		get_tree().paused = _previous_pause

func _process(delta: float) -> void:
	if not visible:
		return
	_feedback_seconds = maxf(0, _feedback_seconds - delta)
	if not is_instance_valid(building):
		close_panel()
		return
	_refresh_seconds -= delta
	if _refresh_seconds <= 0:
		_refresh_seconds = .25
		controller.refresh_snapshot()
		if repair_modal.visible:
			_refresh_repair()

func _select_recipe(id: String) -> void:
	controller.select_recipe(id)
	_show_tab(1)

func _start() -> void:
	controller.request_start()
	_save_action("订单已加入队列，关闭面板后继续生产")

func _collect(id: String) -> void:
	if id.is_empty():
		controller.request_collect_all()
	else:
		controller.request_collect_item(id)
	_save_action("成品已收进背包")

func _save_action(success_text: String) -> void:
	if not controller.failure_reason.is_empty():
		_reason.text = controller.failure_message
		return
	_feedback = success_text
	_feedback_seconds = 3.0
	if session.auto_save and not session.save_game():
		_feedback = "操作已完成，自动保存失败，请手动保存"
	_reason.text = _feedback

func _render() -> void:
	if not visible or not is_instance_valid(building) or controller.recipe_detail.is_empty():
		return
	_rendering = true
	var snapshot := controller.snapshot
	var detail := controller.recipe_detail
	var id := controller.selected_recipe_id
	_recipe_name.text = session.item_name(id)
	_recipe_use.text = {"flour": "可在食品工坊制作面包、蜂蜜蛋糕。", "animal_feed": "供鸡舍日常消耗，继续生产鸡蛋与羽毛。", "sunflower_oil": "装瓶后收取，可带到市集出售。"}.get(id, "")
	if station_id == "food_workshop":
		_recipe_use.text = "使用普通鱼，可混合鱼种；稀有鱼不会被消耗。" if id in ["grilled_fish","pickled_fish"] else "面粉来自风车，鸡蛋来自鸡舍或市集。" if id in ["bread","honey_cake"] else "原料备齐后加工，成品可带到市集出售。"
	_input.text = _counts(detail.inputs)
	_output.text = _counts(detail.outputs)
	var input_id := str(detail.inputs.keys()[0])
	var owned: Array[String] = []
	for item in detail.inputs:
		if not str(item).begins_with("tag:"):
			owned.append("%s %d" % [session.item_name(item),session.inventory.get_item_count(item)])
	_owned.text = "持有："+"、".join(owned)
	_input_icon.texture = Icons.item_icon(input_id)
	_output_icon.texture = Icons.item_icon(id)
	batches_spin.set_value_no_signal(controller.batches)
	_duration.text = "%d 游戏分钟" % int(detail.duration_minutes)
	for fee in session.production.get_rental_fee_table(building):
		if str(fee.recipe_id) == id:
			_rental_fee.text = "%d 金币/批 · 租金归我" % int(fee.fee_per_batch)
		var recipe_button: Button = recipe_buttons.get(str(fee.recipe_id))
		if recipe_button != null:
			recipe_button.tooltip_text = "NPC 自备原料租用：%d 金币/批，成品归租客。" % int(fee.fee_per_batch)
	var waiting := 0
	for job in snapshot.get("jobs", []):
		waiting += int(job.remaining_minutes)
	_waiting.text = "%d 游戏分钟" % waiting if waiting > 0 else "无需等待"
	_prices.text = "%d / %d 金币" % [detail.input_value, detail.output_value]
	_margin.text = "%+d 金币" % int(detail.margin)
	if detail.inputs.has("tag:common_fish"):
		_prices.text = "待补齐鱼获"
		_margin.text = "—"
	_reason.text = controller.failure_message if not controller.failure_message.is_empty() else controller.disabled_reason
	if _reason.text.is_empty() and _feedback_seconds > 0:
		_reason.text = _feedback
	start_button.disabled = not bool(controller.preflight.get("ok", false))
	start_button.tooltip_text = controller.disabled_reason
	_gold.text = "金币 %d" % int(get_node("/root/GameState").gold)
	var state := str(snapshot.get("maintenance_state", "normal"))
	_status.text = "维护中" if state == "repairing" else "维护暂停" if state == "overdue" else "加工中" if not snapshot.jobs.is_empty() else "空闲"
	_maintenance.text = "维护中 · 剩余 %.1f 秒" % float(snapshot.repair_remaining_seconds) if state == "repairing" else "维护已到期 · 生产暂停" if state == "overdue" else "维护正常 · 还有 %d 天" % int(snapshot.maintenance_days_remaining)
	if state == "warning":
		_maintenance.text = "即将需要维护 · 还有 %d 天" % int(snapshot.maintenance_days_remaining)
	maintenance_button.text = "进行维护" if state in ["warning", "overdue"] else "查看维护"
	maintenance_button.disabled = state == "repairing"
	for key in recipe_buttons:
		recipe_buttons[key].add_theme_stylebox_override("normal", _style(Color("e5eddc") if key == id else Color("fffdf6")))
	_render_queue()
	if _goods_snapshot != controller.storage:
		_goods_snapshot = controller.storage.duplicate()
		_rebuild_goods()
	var preflight := session.production.preflight_output_collection(building, session.inventory)
	collect_button.disabled = not bool(preflight.get("ok", false))
	_collect_reason.text = "背包空间不足，请先整理背包" if str(preflight.get("reason", "")) == "inventory_capacity" else "完成后可在此收取，或点击院落内的成品。"
	for row in _goods.get_children():
		if row.has_meta("item_id"):
			row.get_node("Collect").disabled = not bool(session.production.preflight_output_collection(building, session.inventory, row.get_meta("item_id")).get("ok", false))
	_capacity.text = "%d / %d 类" % [controller.storage.size(), int(snapshot.output_capacity)]
	_rendering = false

func _render_queue() -> void:
	_clear(_queue_list)
	_queue_count.text = "%d / %d" % [controller.snapshot.jobs.size(), controller.snapshot.max_queue_slots]
	for slot in controller.queue_slots:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _style(Color("fffdf7"), 12))
		_queue_list.add_child(panel)
		var box := _vbox(panel, 6)
		if slot.state == "idle":
			_label(box, "＋ 空闲队列位置", 16, MUTED)
			_label(box, "选择配方后添加订单", 13, MUTED)
			continue
		_label(box, "%s ×%d" % [slot.display_name, int(slot.batches) * int(RecipeDatabase.get_recipe(slot.recipe_id).outputs.values()[0])], 17)
		if not str(slot.get("tenant_id", "")).is_empty():
			var tenant := str(slot.tenant_id)
			if is_instance_valid(session.agent_runtime):
				tenant = session.agent_runtime.get_agent_display_name(tenant)
			_label(box, "%s租用 · 已付 %d 金币 · 成品归租客" % [tenant, int(slot.rental_fee)], 14, GREEN)
		var progress := ProgressBar.new()
		progress.custom_minimum_size.y = 7
		progress.show_percentage = false
		progress.value = float(slot.progress) * 100
		progress.add_theme_stylebox_override("background", _style(Color("e6e8dc"), 0))
		progress.add_theme_stylebox_override("fill", _style(Color("8aa073"), 0))
		box.add_child(progress)
		_label(box, "%s · 剩余 %d 游戏分钟" % [controller._queue_state_text(slot.state), slot.remaining_minutes], 14, MUTED)
		if slot.state == "output-full":
			_status.text = "等待收取"
			_waiting.text = "待成品收取后恢复"

func _rebuild_goods() -> void:
	_clear(_goods)
	if controller.storage.is_empty():
		_label(_goods, "暂无成品，完成加工后会出现在这里。", 14, MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for id in controller.storage:
		var row := _hbox(_goods)
		row.set_meta("item_id", id)
		var icon := _icon(row, 32)
		icon.texture = Icons.item_icon(id)
		_label(row, "%s ×%d" % [session.item_name(id), controller.storage[id]], 16).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button(row, "收取", _collect.bind(id)).name = "Collect"

func _make_repair() -> void:
	repair_modal = Control.new()
	repair_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(repair_modal)
	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, .5)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	repair_modal.add_child(dimmer)
	var panel := PanelContainer.new()
	panel.name = "Card"
	panel.add_theme_stylebox_override("panel", _style(PAPER, 22))
	repair_modal.add_child(panel)
	var box := _vbox(panel, 14)
	_label(box, station_name+"维护", 24)
	_repair_text = _label(box, "", 17)
	_repair_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := _hbox(box)
	_button(row, "返回", func(): repair_modal.hide())
	repair_confirm = _button(row, "确认维护", _repair)
	repair_modal.hide()

func _open_repair() -> void:
	_refresh_repair()
	repair_modal.show()
	repair_confirm.grab_focus()

func _refresh_repair() -> void:
	if not is_instance_valid(building):
		return
	var quote := session.production.get_maintenance_quote(building)
	var state := session.production.get_maintenance_state(building)
	var enough := int(get_node("/root/GameState").gold) >= int(quote.gold_cost)
	var lines := ["费用：%d 金币（持有 %d）" % [quote.gold_cost, int(get_node("/root/GameState").gold)]]
	for id in quote.materials:
		var owned := session.inventory.get_item_count(id)
		lines.append("%s ×%d（持有 %d）" % [session.item_name(id), quote.materials[id], owned])
		enough = enough and owned >= int(quote.materials[id])
	lines.append("3 秒后完成，原订单进度保留。" if state in ["warning", "overdue"] else "当前无需维护，周期为 14 游戏日。")
	if not enough:
		lines.append("金币或材料不足，请补充后再维护。")
	_repair_text.text = "\n".join(lines)
	repair_confirm.disabled = not enough or state not in ["warning", "overdue"]

func _repair() -> void:
	if not is_instance_valid(building):
		return
	_refresh_repair()
	if repair_confirm.disabled:
		return
	if session.production.maintain(building, get_node("/root/GameState"), session.inventory):
		repair_modal.hide()
		controller.refresh_snapshot()
		if session.auto_save:
			session.save_game()
	else:
		_refresh_repair()

func _show_tab(index: int) -> void:
	_tab = index
	for i in _cards.size():
		_cards[i].visible = not _narrow or i == index
	for i in _tabs.get_child_count():
		_tabs.get_child(i).add_theme_stylebox_override("normal", _style(Color("e5eddc") if i == index else PAPER))

func _layout() -> void:
	if window == null:
		return
	var panel_size := Vector2(minf(1320, size.x - 32), minf(860, size.y - 100))
	_narrow = panel_size.x < 1110
	_tabs.visible = _narrow
	for card in _cards:
		card.custom_minimum_size.x = 0 if _narrow else float(card.get_meta("width"))
	_show_tab(_tab)
	window.size = panel_size
	window.position = (size - panel_size) * .5
	var repair_card := repair_modal.get_node("Card") as Control
	repair_card.size = Vector2(minf(440, size.x - 40), 270)
	repair_card.position = (size - repair_card.size) * .5

func _card(color: Color, width: float) -> VBoxContainer:
	var card := PanelContainer.new()
	card.set_meta("width", width)
	card.custom_minimum_size.x = width
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.7 if width == 410 else 1.0
	card.add_theme_stylebox_override("panel", _style(color, 16))
	_sections.add_child(card)
	_cards.append(card)
	return _vbox(card, 12)

func _metric(parent: Node, title: String) -> Label:
	var row := _hbox(parent)
	_label(row, title, 14, MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _label(row, "", 14)

func _counts(counts: Dictionary) -> String:
	var parts: Array[String] = []
	for id in counts:
		parts.append("%s ×%d" % ["普通鱼" if id == "tag:common_fish" else session.item_name(id), int(counts[id])])
	return "、".join(parts)

func _style(color: Color, margin := 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

func _vbox(parent: Node, spacing := 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	parent.add_child(box)
	return box

func _hbox(parent: Node, spacing := 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	parent.add_child(box)
	return box

func _label(parent: Node, text: String, font_size := 17, color := INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.add_theme_stylebox_override("normal", _style(Color("fffdf6")))
	button.add_theme_stylebox_override("hover", _style(Color("e5eadb")))
	button.add_theme_stylebox_override("pressed", _style(Color("dce6cf")))
	button.add_theme_stylebox_override("disabled", _style(Color("e9eae2")))
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _icon(parent: Node, dimension := 56) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(dimension, dimension)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(icon)
	return icon

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
