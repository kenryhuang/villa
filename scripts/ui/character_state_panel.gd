extends VBoxContainer

var editor: RefCounted
var selector: OptionButton
var record_selector: OptionButton
var text: CodeEdit
var status: Label
var record_help: Label
var apply_button: Button
var views := {}
var drafts := {}
var _loading := false

func configure(session: Node) -> void:
	name = "角色存档"
	editor = preload("res://scripts/debug/character_state_editor.gd").new()
	editor.configure(session)
	var row := HBoxContainer.new()
	add_child(row)
	selector = OptionButton.new(); selector.name = "Character"
	selector.fit_to_longest_item = false; selector.clip_text = true
	selector.custom_minimum_size.x = 220
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(selector)
	for actor in editor.actors():
		selector.add_item(str(actor.name) + " · " + str(actor.id))
		selector.set_item_metadata(selector.item_count-1,actor.id)
	var refresh := Button.new(); refresh.text = "重新读取（丢弃本角色草稿）"
	row.add_child(refresh)
	refresh.pressed.connect(func(): refresh_actor(true))
	selector.item_selected.connect(func(_index): refresh_actor())
	var hint := Label.new()
	hint.text = "编辑时暂停模拟。按记录查看全部关联存档；属性、资源、需求、好感均可修改。共享合同修改会影响参与者。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color",Color("513b2f"))
	add_child(hint)
	record_selector = OptionButton.new(); record_selector.name = "Record"
	record_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record_selector.fit_to_longest_item = false
	record_selector.clip_text = true
	record_selector.get_popup().max_size = Vector2i(1100,420)
	add_child(record_selector)
	record_selector.item_selected.connect(func(_index): _show_record())
	record_help = Label.new(); record_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record_help.add_theme_color_override("font_color",Color("513b2f"))
	add_child(record_help)
	text = CodeEdit.new(); text.name = "StateJson"; text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(0,180)
	text.gutters_draw_line_numbers = true
	text.add_theme_color_override("font_color",Color("513b2f"))
	text.add_theme_color_override("line_number_color",Color("978575"))
	var paper := StyleBoxFlat.new(); paper.bg_color = Color("fffaf0")
	paper.content_margin_left = 8; paper.content_margin_top = 8
	text.add_theme_stylebox_override("normal",paper)
	var colors := CodeHighlighter.new()
	colors.number_color = Color("9a5228"); colors.symbol_color = Color("6d5741")
	colors.add_color_region("\"","\"",Color("35635d"))
	text.syntax_highlighter = colors
	add_child(text)
	text.text_changed.connect(func():
		if not _loading and record_selector.selected >= 0:
			drafts[_actor()][_key()] = text.text
			status.text = "有未应用的草稿；切换记录和角色会保留草稿。")
	var footer := HBoxContainer.new(); add_child(footer)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_theme_color_override("font_color",Color("513b2f"))
	footer.add_child(status)
	apply_button = Button.new(); apply_button.name = "ApplyCharacter"; apply_button.text = "校验、应用并保存"
	footer.add_child(apply_button); apply_button.pressed.connect(apply_changes)
	get_viewport().size_changed.connect(_fit_height)
	_fit_height()

func _fit_height() -> void:
	text.custom_minimum_size.y = 260 if get_viewport().get_visible_rect().size.y >= 900 else 180

func _actor() -> String:
	return str(selector.get_item_metadata(selector.selected))

func _key() -> String:
	return str(record_selector.get_item_metadata(record_selector.selected))

func refresh_actor(discard := false) -> void:
	var actor := _actor()
	for i in selector.item_count:
		var id := str(selector.get_item_metadata(i))
		selector.set_item_text(i,editor.session.living_world.actor_name(id)+" · "+id)
	if discard or not views.has(actor):
		views[actor] = editor.snapshot(actor)
		drafts[actor] = {}
	record_selector.clear()
	var records: Dictionary = views[actor].get("records",{})
	for key in records:
		record_selector.add_item(records[key].label)
		record_selector.set_item_metadata(record_selector.item_count-1,key)
	status.text = "%d 条关联记录 · %s · 服务端长期记忆不属于此存档，未在此编辑。" % [records.size(),editor.session.save_path]
	if not records.is_empty(): record_selector.select(0); _show_record()

func _show_record() -> void:
	_loading = true
	text.text = drafts[_actor()].get(_key(),JSON.stringify(views[_actor()].records[_key()].value,"  "))
	var path: Array = views[_actor()].records[_key()].path
	record_help.text = "修改 JSON 值后应用；ID、版本、回执和关联对象必须保持存档规则一致。"
	if "pairs" in path: record_help.text = "affinity 中的角色 ID 表示该角色对另一人的好感（0–100）。status：none 未确定、dating 恋人、former_partners 曾经交往。调试修改会同步影响双方。"
	elif "character_overrides" in path: record_help.text = "仅覆盖当前存档：traits 性格、values 价值观、speech_style 说话风格、risk_tolerance 风险偏好（0–1）；social_profile 含年龄、性别、恋爱兴趣和交往风格。"
	elif "npc_states" in path: record_help.text = "gold 金币；inventory 背包；reserve_targets 储备目标；production_recipes 配方；sale_targets 出售目标；last_simulated_day 上次模拟日期。"
	_loading = false

func apply_changes() -> void:
	var changes := {}
	for key in drafts.get(_actor(),{}):
		var parsed := JSON.new()
		if parsed.parse(drafts[_actor()][key]) != OK:
			status.text = "JSON 错误：%s，第 %d 行：%s" % [views[_actor()].records[key].label,parsed.get_error_line()+1,parsed.get_error_message()]
			return
		changes[key] = parsed.data
	var result: Dictionary = editor.apply(views[_actor()],changes)
	if result.ok: refresh_actor(true)
	status.text = result.message
