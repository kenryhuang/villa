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
	for title_text in ["可接委托", "我的接单", "我发布的", "配送与计划", "公共事务"]:
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
		confirm.hide()
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

	_delivery_cards()
	_work_cards()
	var public_text := Label.new()
	public_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	public_text.text = session.living_world.public_plans.summary()
	lists[4].add_child(public_text)
	for index in lists.size():
		if lists[index].get_child_count() == 0:
			var empty := Label.new()
			empty.text = ["目前没有可接的委托。", "还没有接单，先去看看村民需要什么。", "还没有发布委托，可以在右侧填写需求。", "可与 NPC 对话协商配送，或询问其当前计划。", "暂无公共计划。"][index]
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
	return str({"task_changed": "配送条款或进度已变化，请重新协商确认。", "task_capacity": "这位 NPC 已达到承接容量，请等已有任务结束。", "draft_expired": "条款草稿已过期，请重新与 NPC 协商。", "delivery_deadline_unreachable": "当前距离无法在期限内送达，请协商更长的期限。", "not_task_party": "只有配送双方可以取消这项约定。", "escrow_unaffordable": "金币不足，未发布委托。", "active_claims": "已经有人接单，请等约定期限结束后再取消。", "claim_slots_full": "接单名额已满。", "claim_quota": "可接数量已变化，请重新选择。", "demand_share_unavailable": "这部分需求已有安排，请重新核对数量。", "terms_changed_reconfirm": "进度已变化，请重新核对交货条款。", "deadline_passed": "委托已到期，未扣除你的货物。", "delivery_over_quota": "交货数量超过剩余接单数量。", "new_production_proof_required": "请选择接单后完成的新加工订单；已有库存不能单独作为加工凭证。", "delivery_assets_or_capacity": "货物不足或收货方仓储不足，本次未交付。", "commission_unavailable": "委托已不可接取，请刷新查看。", "not_publisher": "只有发布者可以取消委托。"}.get(code, "操作未完成，请检查货物、金币和委托状态后重试。"))


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


func offer_delivery_draft(actor_id: String) -> void:
	for draft in session.living_world.interruptions.drafts.values():
		if draft.actor_id != actor_id: continue
		open_panel()
		tabs.current_tab = 3
		var a: Dictionary = draft.terms
		var detail := "%s 愿意配送：%s ×%d → %s（市场收货处）\n报酬 %d 金币，期限 %d 游戏分钟，%s。\n确认后托管你的货物与报酬，实际送达才支付。取消取货后的配送需等 NPC 返回退货。" % [session.living_world.actor_name(actor_id), session.item_name(a.item_id), int(a.quantity), session.living_world.actor_name(a.recipient_id), int(a.reward), int(a.deadline_minutes), {"now": "安全时立即出发", "after_step": "当前步骤后出发", "queue": "原项目完成后出发"}[a.schedule]]
		var id := str(draft.id)
		_confirm(detail, func(): _show_result(session.living_world.interruptions.accept(id)))
		return

func _delivery_cards() -> void:
	for t in session.living_world.interruptions.tasks.values():
		var box := VBoxContainer.new()
		lists[3].add_child(box)
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s：%s ×%d → %s · %s\n剩余 %d 分钟 · 报酬 %d 金币 · %s" % [session.living_world.actor_name(t.actor_id), session.item_name(t.terms.item_id), int(t.terms.quantity), session.living_world.actor_name(t.terms.recipient_id), {"queued": "等待约定出发时机", "pickup": "前来取货", "delivering": "送货途中", "returning": "返回退货", "refund_pending": "等待退还托管", "completed": "已送达并支付", "cancelled": "已取消并退款", "expired": "已到期并退款"}.get(t.status, t.status), maxi(0, int(t.deadline) - session.living_world.minute()), int(t.terms.reward), {"no_route": "通路受阻", "refund_capacity": "背包空间不足，请腾出位置", "recipient_capacity": "收货方容量不足", "walking": "正在行走"}.get(t.reason, "")]
		box.add_child(label)
		if t.status in ["queued", "pickup", "delivering"]:
			var id := str(t.id)
			var version := int(t.version)
			_button(box, "取消这项配送", func(): _confirm("取消配送并退还未付报酬；已取货时需先返回退货。原生产项目继续有效。", func(): _show_result(session.living_world.interruptions.cancel("player", id, version))))
			_button(box, "与 NPC 协商改约", func():
				close_panel()
				session.get_parent().get_node("FarmInteraction").hud.dialogue_ui.open_agent_dialogue(t.actor_id, session.living_world.actor_name(t.actor_id)))
	for p in session.living_world.projects.projects.values():
		if p.status not in ["active", "suspended"]: continue
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s · %s · %s\n可通过对话询问进度、建议调整未来计划；NPC 自主决定是否接受。" % [session.living_world.actor_name(p.actor_id), p.plan.goal, "临时挂起，配送后恢复" if p.status == "suspended" else "正在执行"]
		lists[3].add_child(label)

func _work_cards() -> void:
	_social_cards()
	_environment_card()
	_research_cards()
	var work: RefCounted = session.living_world.work
	for venture in work.context("player").ventures:
		var card := VBoxContainer.new()
		lists[3].add_child(card)
		var detail := Label.new()
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.text = "合作经营：%s\n经营者及新建筑产权：%s · 合作方：%s\n项目总投入 %d 金币、%s\n合作方投入 %d 金币、%s；分享实际盈余 %d%%\n未用本金按出资比例退回，消耗材料有亏损风险。\n状态：%s" % [venture.terms.plan.goal, session.living_world.actor_name(venture.owner), session.living_world.actor_name(venture.terms.partner_id), int(venture.terms.plan.budget), _goods_text(venture.terms.plan.materials), int(venture.terms.partner_gold), _goods_text(venture.terms.partner_materials), int(venture.terms.partner_profit_percent), "等待合作方确认" if venture.status == "proposed" else _status(venture.status)]
		if venture.terms.has("equipment_id"):
			var b: BuildingInstance = session.living_world.building(venture.terms.equipment_id)
			detail.text += "\n合作方提供 %s 的本项目加工使用权，产权保留；项目结束后恢复收费。" % (b.data.display_name if b != null else "约定设备")
		if not venture.settlement.is_empty(): detail.text += "\n实际收回 %d 金币；经营者所得 %d，合作方所得 %d。合作方退料：%s" % [int(venture.settlement.cash), int(venture.settlement.owner_gold), int(venture.settlement.partner_gold), _goods_text(venture.settlement.partner_items)]
		card.add_child(detail)
		var id := str(venture.id)
		var version := int(venture.version)
		if venture.status == "proposed" and venture.terms.partner_id == "player":
			_button(card, "核对合作投入", func(): _confirm(detail.text, func(): _show_result(work.accept_venture("player", id, version))))
		if venture.status in ["proposed", "active"]:
			_button(card, "退出并结算未完成部分", func(): _confirm("将停止后续投入，已开始的生产仍需结算。已消耗的材料和费用不退还。", func(): _show_result(work.exit_venture("player", id, version))))
	for c in work.context("player").contracts:
		var box := VBoxContainer.new()
		lists[3].add_child(box)
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s → %s · %s\n%s ×%d → %s，每次报酬 %d 金币 · 完成 %d/%d 次\n托管余款 %d 金币 · %s" % [session.living_world.actor_name(c.employer), session.living_world.actor_name(c.terms.worker_id), {"delivery": "雇用配送", "processing": "委托加工", "supply": "定期供货"}[c.terms.kind], session.item_name(c.terms.item_id), int(c.terms.quantity), session.living_world.actor_name(c.terms.recipient_id), int(c.terms.wage), int(c.cycle), int(c.terms.cycles), int(c.gold), {"proposed": "等待双方确认", "queued": "准备出发", "pickup": "前往取货", "working": "加工中", "delivery": "运送交货", "between": "等待下一期", "refund_pending": "正在结算余款", "completed": "已履约", "cancelled": "已取消", "expired": "已到期"}.get(c.status, c.status)]
		box.add_child(label)
		if "player" not in [c.employer, c.terms.worker_id]: continue
		var id := str(c.id)
		var version := int(c.version)
		if c.status == "proposed" and "player" not in c.accepted_by:
			_button(box, "核对并接受新报价", func(): _confirm(label.text + "\n确认后托管报酬和约定原料，按实际交付付款。", func(): _show_result(work.accept("player", id, version))))
		if c.status in work.ACTIVE + ["proposed"]:
			_button(box, "取消后续工作", func(): _confirm("停止未完成周期，退还未花费资金和原料；已经完成的交付不追回。", func(): _show_result(work.cancel("player", id, version))))
	for activity in work.activities.values():
		var label := Label.new()
		label.text = "%s · %s · 已投入 %d 分钟 · %s" % [session.living_world.actor_name(activity.actor_id), {"learning": "原料选配培训", "visit": "拜访朋友", "rest": "休息"}[activity.kind], int(activity.worked), {"traveling": "前往现场", "working": "进行中", "completed": "已完成", "cancelled": "已取消"}[activity.status]]
		lists[3].add_child(label)
	var form := VBoxContainer.new()
	lists[3].add_child(form)
	var worker := OptionButton.new()
	for id in ["lao_li", "farmer_ahe", "xuezhe_lin"]:
		worker.add_item(session.living_world.actor_name(id))
		worker.set_item_metadata(worker.item_count - 1, id)
	_field(form, "向村民询价：送粮到旅店", worker)
	var amount := _spin(1, 100, 2)
	_field(form, "每次谷物数量", amount)
	var wage := _spin(1, 100000, 20)
	_field(form, "每次配送报酬", wage)
	var cycles := _spin(1, 7, 1)
	_field(form, "配送次数（多次按每天一期）", cycles)
	_button(form, "发送分工提案，等待 NPC 决定", func():
		var a := {"worker_id": str(worker.get_selected_metadata()), "recipient_id": "village_inn", "kind": "delivery", "item_id": "grain", "quantity": int(amount.value), "wage": int(wage.value), "building_id": "", "recipe_id": "", "max_fee": 0, "deadline_minutes": mini(10080, int(cycles.value) * 1080 + 500), "cycles": int(cycles.value), "interval_minutes": 1080 if cycles.value > 1 else 0, "parent_contract": "", "note": "请考虑这份配送工作，可以还价或拒绝。"}
		_show_result(work.propose("player", _id(), a)))

func offer_work_terms() -> void:
	open_panel()
	tabs.current_tab = 3

func _goods_text(goods: Dictionary) -> String:
	var parts: Array[String] = []
	for id in goods:
		if int(goods[id]) > 0: parts.append("%s ×%d" % [session.item_name(id), int(goods[id])])
	return "无材料" if parts.is_empty() else "、".join(parts)

func _research_cards() -> void:
	var k: RefCounted = session.living_world.knowledge
	if k == null: return
	var view: Dictionary = k.cards("player", true)
	for report in view.reports:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "调查报告 · %s · %s\n%s\n地点：东向 %.1f／南向 %.1f 米 · %s" % [k.SITES[report.region_id].name, session.living_world.actor_name(report.source), report.text, float(report.position.x), float(report.position.z), "报告仍有效" if k.fresh(report.id) else "报告已过期，请重新调查"]
		lists[3].add_child(label)
	for offer in view.offers:
		var card := VBoxContainer.new()
		lists[3].add_child(card)
		var label := Label.new()
		label.text = "%s 的情报：%s · %d 金币\n%s" % [session.living_world.actor_name(offer.seller), offer.summary, int(offer.price), "已经知道，无需重复购买" if offer.known else "确认购买后获得报告和地图标记；购买前不展示具体内容"]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(label)
		if offer.buyer == "player" and offer.status == "proposed" and not offer.known:
			var id := str(offer.id)
			var version := int(offer.version)
			_button(card, "购买这份情报", func(): _confirm(label.text, func(): _show_result(k.purchase("player", id, version))))
	for c in view.assignments:
		var card := VBoxContainer.new()
		lists[3].add_child(card)
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s 调查 %s · %s\n资助方 %s：2份面包补给，交付报酬 %d 金币。%s；%s。\n已付报酬 %d，退回金币 %d，实际消耗面包 %d。%s" % [session.living_world.actor_name(c.terms.worker_id), k.SITES[c.terms.region_id].name, {"proposed": "等待确认", "queued": "准备出发", "traveling": "前往调查", "surveying": "现场调查", "returning": "返回交付", "refund_pending": "等待退款", "completed": "已交付", "no_sample": "未找到样本", "cancelled": "已取消", "expired": "已到期"}[c.status], session.living_world.actor_name(c.terms.funder_id), int(c.terms.reward), "允许未领奖的旧报告" if c.terms.allow_old_report else "需要本次新调查", "需交付样本才支付报酬" if c.terms.require_sample else "如实交付报告即可，无发现也付报酬", int(c.paid), int(c.refunded_gold), int(c.consumed_bread), c.reason]
		card.add_child(label)
		var id := str(c.id)
		var version := int(c.version)
		if c.status == "proposed" and "player" not in c.accepted_by:
			_button(card, "确认资助条款", func(): _confirm(label.text, func(): _show_result(k.accept_investigation("player", id, version))))
		if c.status in ["proposed", "queued", "traveling", "surveying", "returning"]:
			_button(card, "取消未完成调查", func(): _confirm("停止调查；已消耗补给不返还，剩余补给与未付报酬退回。", func(): _show_result(k.cancel_investigation("player", id, version))))
	var form := VBoxContainer.new()
	lists[3].add_child(form)
	var region := OptionButton.new()
	for id in k.SITES:
		region.add_item(k.SITES[id].name)
		region.set_item_metadata(region.item_count - 1, id)
	_field(form, "资助学者林进行实地调查", region)
	var pay := _spin(0, 100000, 80)
	_field(form, "交付报酬（另外准备2份面包）", pay)
	var require_sample := CheckBox.new()
	require_sample.text = "必须实地采样才支付报酬（购买的样本不适用；无样本退还报酬）"
	form.add_child(require_sample)
	_button(form, "提出调查资助，等待 NPC 决定", func(): _show_result(k.propose_investigation("player", _id(), {"worker_id": "xuezhe_lin", "funder_id": "player", "region_id": str(region.get_selected_metadata()), "reward": int(pay.value), "deadline_minutes": 1080, "allow_old_report": false, "require_sample": require_sample.button_pressed})))

func _environment_card() -> void:
	var env: RefCounted = session.living_world.environment
	var box := VBoxContainer.new()
	lists[3].add_child(box)
	var view: Dictionary = env.context()
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "天气：%s · 明日预报：%s\n场外商道：%s；每日最多运输24份，货到才补充库存。\n雨天可湿润露天谷物、胡萝卜和土豆地，咬钩概率从72%%提高到82%%。" % ["降雨" if view.weather == "rain" else "晴", "9:00—17:00有雨" if view.forecast.rain else "晴", "通行" if view.route_open else "降雨受阻"]
	box.add_child(label)
	if not view.route_open:
		label.text += "\n修复点：西向18.5／南向22.5米；已投入木材%d/6、石料%d/4、工时%d/60。也可等待自然恢复，剩余%d分钟。" % [view.route.materials.wood, view.route.materials.stone, view.route.labor, maxi(0, int(view.route.natural_recovery) - session.living_world.minute())]
		var id := str(view.route.id)
		_button(box, "在修复点投入剩余材料", func():
			var goods := {}
			for item in env.REPAIR:
				var amount := int(env.REPAIR[item]) - int(env.event.materials[item])
				if amount > 0: goods[item] = amount
			_confirm("投入自有材料：%s。只有走到修复点才能交付。" % _goods_text(goods), func(): _show_result(env.command("player", "contribute_route_repair", {"event_id": id, "materials": goods, "labor_minutes": 0}, _id()))))
		_button(box, "在修复点劳动60分钟", func():
			var result: Dictionary = env.command("player", "contribute_route_repair", {"event_id": id, "materials": {}, "labor_minutes": 60}, _id())
			_show_result(result)
			if result.ok: close_panel())
	for t in view.transports:
		var row := Label.new()
		row.text = "%s ×%d · %s" % [session.item_name(t.item_id), t.quantity, "已经入市" if t.status == "arrived" else "在途，预计%d分钟后到达" % maxi(0, int(t.arrival) - session.living_world.minute())]
		box.add_child(row)

func _social_cards() -> void:
	var social: RefCounted = session.living_world.social
	for e in social.events.values():
		var box := VBoxContainer.new()
		lists[3].add_child(box)
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s · %s · %s\n第%d天 %02d:%02d开始，持续%d分钟；报名%d/%d，门票%d金币。\n食品收到%d份、已消费%d份；活动期内首次%s奖励%d金币。NPC只观赛。\n%s" % ["湖畔钓鱼聚会" if e.terms.kind == "fishing" else "七洞高尔夫活动", session.living_world.actor_name(e.owner), {"enrolling": "报名中", "live": "进行中", "finished": "已结束", "cancelled": "已取消"}[e.status], int(e.start) / 1080 + 1, (int(e.start) % 1080) / 60 + 6, int(e.start) % 60, e.terms.duration, e.participants.size(), e.terms.capacity, e.terms.ticket, e.received, e.served, "成功收鱼" if e.terms.kind == "fishing" else "完成七洞", e.terms.reward, e.reason]
		box.add_child(label)
		var id := str(e.id); var version := int(e.version)
		if e.status == "enrolling" and not e.participants.has("player"):
			_button(box, "报名参加", func(): _confirm(label.text + "\n取消活动或未到场退票；比赛必须在活动开始后开局。", func(): _show_result(social.command("player", "enroll_activity", {"event_id": id, "version": version}, _id()))))
		if e.status == "enrolling" and e.participants.get("player", {}).get("state") == "enrolled":
			_button(box, "退出并退票", func(): _show_result(social.command("player", "leave_activity", {"event_id": id, "version": version}, _id())))
		if e.owner == "player" and e.status in ["enrolling", "live"]:
			_button(box, "取消活动", func(): _confirm("已完成的供应交付不追回；退还门票，剩余款项与食品返还。", func(): _show_result(social.command("player", "cancel_activity", {"event_id": id, "version": version}, _id()))))
	var form := VBoxContainer.new(); lists[3].add_child(form)
	var kind := OptionButton.new(); kind.add_item("湖畔钓鱼聚会"); kind.add_item("七洞高尔夫活动")
	_field(form, "发起活动（需实际赞助150金币）", kind)
	_button(form, "预约场地并发布食品采购", func(): _confirm("赞助150金币，其中80金币采购4份面包、20金币留作首个有效玩家成绩的参与奖。120分钟后开始、持续540分钟，最多8人、至少2人；门票5金币。报名或食品不足时取消并结算。", func(): _show_result(social.command("player", "propose_activity", {"kind": "fishing" if kind.selected == 0 else "golf", "starts_in": 120, "duration": 540, "capacity": 8, "minimum": 2, "ticket": 5, "sponsor": 150, "reward": 20, "food_quantity": 4, "food_price": 20}, _id()))))
