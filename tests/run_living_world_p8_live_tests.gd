extends SceneTree

var scene: Node
var s: Farm3DSession
var w: Node
var observations: Array = []
var ended := false

func _initialize() -> void:
	create_timer(420).timeout.connect(func(): finish(false, "Live P8 timeout"))
	run.call_deferred()

func finish(ok: bool, reason: String) -> void:
	if ended: return
	ended = true
	if w != null:
		var f := FileAccess.open("res://tmp/living-world/P8-live.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"ok": ok, "reason": reason, "observations": observations, "world": w.to_dict(), "trace": s.agent_runtime.session_trace.get_requests()}, "  "))
		f.close()
	print("P8 real AI: %s · %s" % ["PASS" if ok else "FAIL", reason])
	quit(0 if ok else 1)

func say(actor: String, message: String) -> void:
	var ui: Control = scene.get_node("FarmInteraction").hud.dialogue_ui
	ui.open_agent_dialogue(actor, w.actor_name(actor))
	ui.message_input.text = message
	ui.send_button.pressed.emit()
	while s.agent_runtime.scheduler.is_in_flight(actor): await create_timer(.1).timeout
	observations.append({"actor": actor, "message": message, "history": ui._histories.get(actor, []).duplicate(true)})
	ui.close()
	await process_frame
	var board: Control = scene.get_node("FarmInteraction").hud.commission_view
	if board.visible: board.close_panel()

func run() -> void:
	if "--living-world-live-agents" not in OS.get_cmdline_user_args() or "--living-world-scenario=P8" not in OS.get_cmdline_user_args(): finish(false, "Explicit isolated P8/live flags required"); return
	scene = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	s = scene.farm_session
	w = s.living_world
	w.set_process(false)
	s.season.set_process(false)
	s.player.set_physics_process(false)
	s.save_path = "res://tmp/living-world/P8-live-save.json"
	if s.auto_save or s.auto_restore or not s.agent_runtime.service_enabled: finish(false, "Isolation/service unavailable"); return
	for actor in s.agent_runtime.registry.get_agent_ids(): s.agent_runtime.scheduler.set_decision_interval_hours(actor, 0)
	for id in w.board.commissions.keys(): w.board.cancel(w.board.commissions[id].actor_id, id)
	s.player.position = Vector3(-12.5, 0, 22.5)
	w.actor("lao_li").position = Vector3(-11.5, 0, 22.5)
	w.actor("farmer_ahe").position = Vector3(-10.5, 0, 22.5)
	w.actor("farmer_ahe").move_speed = 8
	await say("lao_li", "旅店需要2份谷物。你有自己的谷物和金币，愿意从自己的库存拿2份送给旅店，并雇阿禾帮忙运输吗？先考虑一份有报酬的分工提案，有效期500游戏分钟，完成一次实际交货后付款。报酬由你考虑，阿禾可以还价或拒绝，不要替他接受，也不要用我的资产。")
	var contract: Dictionary = {}
	for c in w.work.contracts.values():
		if c.employer == "lao_li" and c.terms.worker_id == "farmer_ahe": contract = c; break
	if contract.is_empty(): finish(false, "Private NPC declined or did not propose executable work; see trace"); return
	for review in 3:
		if contract.status != "proposed": break
		var actor := "farmer_ahe" if "lao_li" in contract.accepted_by else "lao_li"
		if not s.agent_runtime.scheduler.is_in_flight(actor): s.agent_runtime.scheduler._dispatch(actor, "event", w.minute(), "")
		while s.agent_runtime.scheduler.is_in_flight(actor): await create_timer(.1).timeout
		observations.append({"review": review, "contract": contract.duplicate(true)})
	if contract.status not in w.work.ACTIVE: finish(false, "Private negotiation did not reach acceptance; not treated as success"); return
	var id := str(contract.id)
	if not s.save_game() or not s.load_game(): finish(false, "Accepted live job failed persistence"); return
	w.actor("farmer_ahe").move_speed = 8
	for frame in 2400:
		w.work.advance()
		if w.work.contracts[id].status == "completed": break
		await physics_frame
	if w.work.contracts[id].status != "completed": finish(false, "Real transport did not complete"); return
	await say("lao_li", "如果再送一次同样的2份谷物给旅店，阿禾现在报价提高到每次80金币。这比上一笔贵了，你可以拒绝、提出更低报酬或选择其他人。请根据自己的钱包和其他目标决定，不要保证接受。")
	var latest: Dictionary = s.agent_runtime.session_trace.get_requests().back()
	for action in latest.get("final", {}).get("actions", []):
		var outcome: Dictionary = s.agent_runtime.executor._outcomes.get(action.idempotency_key, {})
		if outcome.get("status") in ["rejected", "failed"]: finish(false, "Price follow-up produced rejected action: " + str(outcome)); return
	if not s.save_game() or not s.load_game(): finish(false, "Final live negotiation failed persistence"); return
	finish(true, "Private NPC proposed work; counterpart independently reviewed accepted terms; real movement and funded delivery completed after reload. Increased-price follow-up retained in observations for review.")
