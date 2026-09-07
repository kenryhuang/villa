extends Control

signal closed
var session: Node
var board: RefCounted
var tabs: TabContainer
var lists: Array[VBoxContainer] = []
var feedback: Label
var confirm: ConfirmationDialog
var pending: Callable
var item: OptionButton
var quantity: SpinBox
var reward: SpinBox
var duration: SpinBox
var kind: OptionButton
var _paused := false

func configure(farm: Node) -> void:
	session = farm
	board = session.living_world.board
	name = "CommissionView"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, .04, .03, .7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(850, 680)
	panel.add_theme_stylebox_override("panel", _style(Color("202e25"), 22))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "村庄委托 · 交付实物，领取报酬"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_button(header, "关闭 · Esc", close_panel)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	for title_text in ["可接委托", "我的接单", "我发布的"]:
		var scroll := ScrollContainer.new()
		scroll.name = title_text
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_theme_constant_override("separation", 12)
		scroll.add_child(rows)
		lists.append(rows)
	var form := VBoxContainer.new()
	form.name = "发布委托"
	form.add_theme_constant_override("separation", 14)
	tabs.add_child(form)
	item = OptionButton.new()
	for id in ["bread", "flour", "grain", "carrot", "plank", "stone_brick", "rope"]:
		item.add_item(session.item_name(id))
		item.set_item_metadata(item.item_count - 1, id)
	_field(form, "需要的货物", item)
	quantity = _spin(1, 100, 5)
	_field(form, "总数量", quantity)
	reward = _spin(1, 1000000, 100)
	_field(form, "每份报酬（金币）", reward)
	duration = _spin(1, 168, 24)
	_field(form, "有效时间（游戏小时）", duration)
	kind = OptionButton.new()
	kind.add_item("采购：允许交付已有库存")
	kind.add_item("加工：接单后完成的新加工订单")
	_field(form, "委托类型", kind)
	_button(form, "核对条款并托管报酬", _publish)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feedback)
	confirm = ConfirmationDialog.new()
	confirm.title = "确认委托条款"
	confirm.ok_button_text = "确认"
	confirm.cancel_button_text = "返回修改"
	add_child(confirm)
	confirm.confirmed.connect(func():
		if pending.is_valid(): pending.call()
		pending = Callable()
		refresh())
	session.state_loaded.connect(close_panel)
	hide()

func open_panel() -> void:
	if visible: return
	_paused = get_tree().paused
	get_tree().paused = true
	session.production.dialogue_paused = true
	session.player.set_dialogue_input_blocked(true)
	session.player.ui_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	refresh()

func close_panel() -> void:
	if not visible: return
	confirm.hide()
	pending = Callable()
	hide()
	get_tree().paused = _paused
	session.production.dialogue_paused = false
	session.player.set_dialogue_input_blocked(false)
	closed.emit()

func refresh() -> void:
	for rows in lists:
		for child in rows.get_children(): rows.remove_child(child); child.queue_free()
	for c in board.commissions.values():
		if c.status == "open" and c.actor_id != "player": _available_card(c)
		if c.actor_id == "player":
			var row := _card(lists[2], c)
			_button(row, "取消未接单委托", func(): _show_result(board.cancel("player", c.id)))
	for task in board.claims.values():
		if task.actor_id != "player": continue
		var c: Dictionary = board.commissions[task.commission_id]
		var row := _card(lists[1], c)
		var progress := Label.new()
		progress.text = "我的进度 %d / %d · %s" % [int(task.delivered), int(task.quantity), _status(task.status)]
		row.add_child(progress)
		if task.status == "active":
			var amount := _spin(1, maxi(1, int(task.quantity) - int(task.delivered)), 1)
			row.add_child(amount)
			var proof := OptionButton.new()
			proof.add_item("采购委托无需加工凭证")
			proof.set_item_metadata(0, "")
			for id in board.proofs:
				var p: Dictionary = board.proofs[id]
				if p.actor_id == "player" and p.complete and int(p.sequence) > int(task.sequence):
					proof.add_item("加工订单 " + id)
					proof.set_item_metadata(proof.item_count - 1, id)
			row.add_child(proof)
			_button(row, "核对交货与报酬", func():
				var n := int(amount.value)
				var version := int(c.version)
				var order := str(proof.get_selected_metadata())
				_confirm("交付 %s ×%d，领取 %d 金币。" % [session.item_name(c.terms.item_id), n, n * int(c.terms.unit_reward)], func(): _show_result(board.deliver("player", _id(), task.id, n, version, order))))
			_button(row, "放弃剩余接单", func(): _show_result(board.abandon("player", task.id)))

	for index in lists.size():
		if lists[index].get_child_count() == 0:
			var empty := Label.new()
			empty.text = ["目前没有可接的委托。", "还没有接单，先去看看村民需要什么。", "还没有发布委托，可以在右侧填写需求。"][index]
			lists[index].add_child(empty)

func _available_card(c: Dictionary) -> void:
	var row := _card(lists[0], c)
	var remaining := int(c.terms.quantity) - int(c.delivered) - int(c.claimed)
	if remaining <= 0: return
	var amount := _spin(1, remaining, 1)
	row.add_child(amount)
	_button(row, "接取所选数量", func(): _show_result(board.claim("player", _id(), c.id, int(amount.value))))

func _card(rows: VBoxContainer, c: Dictionary) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("2c3d30"), 14))
	rows.add_child(panel)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "%s ×%d · 每份 %d 金币 · %s\n发布者 %s · 已交 %d，接单中 %d · 剩余 %d 分钟 · %s" % [session.item_name(c.terms.item_id), int(c.terms.quantity), int(c.terms.unit_reward), "接单后新加工" if c.terms.kind == "processing" else "采购", session.living_world.actor_name(c.actor_id), int(c.delivered), int(c.claimed), maxi(0, int(c.deadline) - session.living_world.minute()), _status(c.status)]
	row.add_child(label)
	return row

func _publish() -> void:
	var id := _id()
	var terms := {"demand_id": id, "item_id": str(item.get_selected_metadata()), "quantity": int(quantity.value), "unit_reward": int(reward.value), "deadline_minutes": int(duration.value) * 60, "kind": "purchase" if kind.selected == 0 else "processing", "max_claims": 3}
	_confirm("需要 %s ×%d，每份 %d 金币。\n有效期 %d 小时；%s。\n确认后从你的钱包托管 %d 金币。" % [session.item_name(terms.item_id), terms.quantity, terms.unit_reward, int(duration.value), kind.get_item_text(kind.selected), terms.quantity * terms.unit_reward], func():
		if not board.demand(id, "player", terms.item_id, terms.quantity): return
		_show_result(board.publish("player", id, terms)))

func _confirm(text: String, action: Callable) -> void:
	pending = action
	confirm.dialog_text = text
	confirm.popup_centered(Vector2i(560, 220))

func _show_result(result: Dictionary) -> void:
	feedback.text = str(result.get("message", "操作已完成")) if result.ok else _error_text(str(result.get("error", "")))
	if result.ok and session.auto_save: session.save_game()
	refresh()

func _field(parent: Node, text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	parent.add_child(control)

func _spin(lo: int, hi: int, initial: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.value = initial
	return spin

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _id() -> String: return "board-" + Crypto.new().generate_random_bytes(12).hex_encode()


func _style(color: Color, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("8e825b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

func _status(value: String) -> String:
	return str({"open": "招募中", "active": "进行中", "completed": "已完成", "expired": "已到期", "cancelled": "已取消", "abandoned": "已放弃"}.get(value, value))

func _error_text(code: String) -> String:
	return str({"escrow_unaffordable": "金币不足，未发布委托。", "active_claims": "已经有人接单，请等约定期限结束后再取消。", "claim_slots_full": "接单名额已满。", "claim_quota": "可接数量已变化，请重新选择。", "demand_share_unavailable": "这部分需求已有安排，请重新核对数量。", "terms_changed_reconfirm": "进度已变化，请重新核对交货条款。", "deadline_passed": "委托已到期，未扣除你的货物。", "delivery_over_quota": "交货数量超过剩余接单数量。", "new_production_proof_required": "请选择接单后完成的新加工订单；已有库存不能单独作为加工凭证。", "delivery_assets_or_capacity": "货物不足或收货方仓储不足，本次未交付。", "commission_unavailable": "委托已不可接取，请刷新查看。", "not_publisher": "只有发布者可以取消委托。"}.get(code, "操作未完成，请检查货物、金币和委托状态后重试。"))


func offer_draft() -> void:
	var draft: Dictionary = session.living_world.pending_player_terms.duplicate(true)
	session.living_world.pending_player_terms.clear()
	if draft.is_empty() or int(draft.expires) <= session.living_world.minute(): return
	open_panel()
	var terms: Dictionary = draft.terms.duplicate(true)
	terms.demand_id = "player-" + str(draft.id).sha256_text().substr(0, 24)
	var title := "%s 拟定的委托（尚未发布）" % session.living_world.actor_name(draft.actor_id)
	var detail := "%s\n需要 %s ×%d，每份 %d 金币，共托管 %d 金币。\n有效期 %d 分钟，最多 %d 人接单，%s。" % [title, session.item_name(terms.item_id), int(terms.quantity), int(terms.unit_reward), int(terms.quantity) * int(terms.unit_reward), int(terms.deadline_minutes), int(terms.max_claims), "接单后新加工" if terms.kind == "processing" else "允许已有库存"]
	_confirm(detail, func():
		if board.demand(terms.demand_id, "player", terms.item_id, int(terms.quantity)):
			_show_result(board.publish("player", terms.demand_id, terms)))
