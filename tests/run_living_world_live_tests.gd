extends SceneTree

var replies: Array[Dictionary] = []
var errors: Array[String] = []
var runtime: Node
var dialogue: Node
var session: Farm3DSession

func _initialize() -> void:
	create_timer(480).timeout.connect(func(): fail("Live acceptance timed out"))
	run.call_deferred()

func fail(reason: String) -> void:
	if runtime != null:
		var file := FileAccess.open("res://tmp/living-world/live-failure.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"reason": reason, "trace": runtime.session_trace.get_requests(), "replies": replies, "history": dialogue.get_agent_history("lao_li")}, "  "))
	push_error(reason)
	quit(1)

func ask(actor: String, message: String) -> bool:
	dialogue.close()
	dialogue.open_agent_dialogue(actor, runtime.get_agent_display_name(actor))
	dialogue.set_agent_interactions(actor, runtime.get_player_interactions(actor))
	var before := replies.size()
	var failed := errors.size()
	dialogue.message_input.text = message
	dialogue.send_button.pressed.emit()
	var deadline := Time.get_ticks_msec() + 180000
	while replies.size() == before and errors.size() == failed and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	return replies.size() > before and errors.size() == failed

func open_offer() -> Dictionary:
	for record in runtime.get_player_interactions("lao_li"):
		if record.has("offer_id") and record.status == "open" and record.recipient_id == "player": return record
	return {}

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/living-world/" + name + ".png")

func run() -> void:
	if not "--living-world-live-agents" in OS.get_cmdline_user_args():
		fail("Explicit --living-world-live-agents is required")
		return
	root.size = Vector2i(1440, 960)
	var scene := load("res://scenes/farm3d/main.tscn").instantiate() as Node
	root.add_child(scene)
	session = scene.farm_session
	session.season.set_process(false)
	runtime = session.agent_runtime
	dialogue = scene.get_node("FarmInteraction").hud.dialogue_ui
	if DisplayServer.get_name() != "headless":
		for frame in 4: await physics_frame
	if session.auto_save or session.auto_restore or not runtime.service_enabled:
		fail("Live fixture must use isolated save and configured real service")
		return
	runtime.dialogue_ready.connect(func(actor: String, request: String, _speech: String): replies.append({"actor": actor, "request_id": request}))
	runtime.dialogue_stream_failed.connect(func(_actor: String, _request: String, error: String): errors.append(error))
	if not await ask("lao_li", "请查看我们实际持有的物品，向我提出一份正式交易报价：你给我1份盐，我给你2根胡萝卜，有效期120分钟。请使用交易工具生成报价卡，我会亲自确认，不要仅口头答应。"):
		fail("Real provider did not finish trade proposal: " + str(errors))
		return
	var offer := open_offer()
	if offer.is_empty():
		await ask("lao_li", "我确实持有10根胡萝卜。你给出的是你库存中的1份盐，要收到的是我的2根胡萝卜；你自己不需要拥有胡萝卜。请用 propose_trade 向 player 发出报价，give 放盐1，receive 放胡萝卜2，双方gold为0。")
		offer = open_offer()
	if offer.is_empty():
		fail("Real provider finished speech but created no actionable trade offer")
		return
	await capture("P0-live-offer")
	var result: Dictionary = runtime.respond_to_player_interaction("lao_li", str(offer.offer_id), "counter", {"give": offer.proposer_receives, "receive": offer.proposer_gives, "expires_in_minutes": 180, "counter_note": "物品和数量不变，请把有效期改为180分钟。"})
	if not result.ok or not await ask("lao_li", "我已在报价面板正式还价，只把有效期延长到180分钟，物品数量不变。请查看我的新报价，并使用工具接受它。"):
		fail("Real counteroffer acceptance failed")
		return
	var settled := false
	for record in runtime.get_player_interactions("lao_li"):
		if record.has("offer_id") and record.status == "settled": settled = true
	if not settled:
		fail("Real provider did not settle counteroffer")
		return
	await capture("P0-live-settled")
	if not await ask("lao_li", "再向我发起一份同样的正式交易：你给1份盐，我给2根胡萝卜，有效期120分钟，等待我在报价卡确认。"):
		fail("Second real quote failed")
		return
	offer = open_offer()
	if offer.is_empty():
		fail("No second offer to verify rejection")
		return
	# Explicit fault injection only in the isolated fixture: receiver assets disappear.
	for id in offer.proposer_receives.items:
		session.inventory.remove_item(id, session.inventory.get_item_count(id))
	var inventory_before := session.inventory.slots.duplicate(true)
	var gold_before: int = root.get_node("GameState").gold
	dialogue.set_agent_interactions("lao_li", runtime.get_player_interactions("lao_li"))
	for card in dialogue.interaction_cards.get_children():
		var button: Button = card.find_child("AcceptButton", true, false)
		if not button.disabled:
			button.pressed.emit()
			break
	if not dialogue.status_label.text.contains("未能完成") or inventory_before != session.inventory.slots or gold_before != root.get_node("GameState").gold:
		fail("Actual trade UI failed to reject missing assets atomically")
		return
	await capture("P0-live-rejected")
	var building: BuildingInstance = session.buildings.get_all_buildings()[0]
	var rental_ok: bool = await ask("farmer_ahe", "请先查询实际建筑和你自己的库存，用你自己的粮食租用风车 %s 制作1批面粉，总加工费不超过100金币。使用 rent_production 下单，说明订单阶段，不要把下单说成成品已完成。参数 batches=1 和 max_fee=100 都必须是整数。" % building.instance_id)
	if not rental_ok:
		rental_ok = await ask("farmer_ahe", "刚才的请求未执行。请重新下单，rent_production 必须包含4个字段：building_id=windmill:32:31，recipe_id=flour，batches=1，max_fee=100；后两项必须是整数，不是字符串。不要使用其他工具。")
	if not rental_ok:
		fail("Real rental decision failed")
		return
	dialogue.close()
	for frame in 4: await process_frame
	if building.producer_state.jobs.is_empty():
		await ask("farmer_ahe", "你刚才只口头答应，没有下单。请现在调用 rent_production，参数为 building_id=windmill:32:31, recipe_id=flour, batches=1, max_fee=100；后两项为整数。请实际调用工具。")
		dialogue.close()
		for frame in 4: await process_frame
	if building.producer_state.jobs.is_empty():
		fail("Real provider did not place rental after resume")
		return
	var job: Dictionary = building.producer_state.jobs[0]
	var order_id := str(job.get("order_id", ""))
	session.production.advance_minutes(90)
	if order_id.is_empty() or building.producer_state.service_records[order_id].stage != "delivered":
		fail("Real rental failed to deliver")
		return
	var report := {"provider": "configured_real", "trade_counter_settled": true, "missing_assets_rejected": true, "rental_delivered": true, "requests": replies, "order_id": order_id}
	var file := FileAccess.open("res://tmp/living-world/live-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("PASS: Real provider trade, counteroffer, rejection and rental delivery (%d responses)" % replies.size())
	quit(0)
