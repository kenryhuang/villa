extends SceneTree
var scene: Node
var s: Farm3DSession
var w: Node
var observations := []
var ended := false
func _initialize() -> void:
	create_timer(600).timeout.connect(func(): finish(false, "P11 live timeout"))
	run.call_deferred()
func finish(ok: bool, reason: String) -> void:
	if ended: return
	ended = true
	if w != null:
		var f := FileAccess.open("res://tmp/living-world/P11-live.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"ok": ok, "reason": reason, "observations": observations, "social": w.social.to_dict(), "trace": s.agent_runtime.session_trace.get_requests()}, "  ")); f.close()
	print("P11 real AI: %s · %s" % ["PASS" if ok else "FAIL", reason]); quit(0 if ok else 1)
func say(actor: String, text: String) -> void:
	var ui: Control = scene.get_node("FarmInteraction").hud.dialogue_ui
	ui.open_agent_dialogue(actor, w.actor_name(actor)); ui.message_input.text = text; ui.send_button.pressed.emit()
	while s.agent_runtime.scheduler.is_in_flight(actor): await create_timer(.1).timeout
	observations.append({"actor": actor, "request": text, "history": ui._histories.get(actor, []).duplicate(true)})
	ui.close(); await process_frame
	var board: Control = scene.get_node("FarmInteraction").hud.commission_view
	if board.visible: board.close_panel()
func run() -> void:
	if "--living-world-scenario=P11" not in OS.get_cmdline_user_args() or "--living-world-live-agents" not in OS.get_cmdline_user_args(): finish(false, "Explicit isolated live flags required"); return
	scene = load("res://scenes/farm3d/main.tscn").instantiate(); root.add_child(scene)
	s = scene.farm_session; w = s.living_world
	scene.set_process(false); w.set_process(false); s.season.set_process(false); s.player.set_physics_process(false)
	s.save_path = "res://tmp/living-world/P11-live-save.json"
	for actor in s.agent_runtime.registry.get_agent_ids(): s.agent_runtime.scheduler.set_decision_interval_hours(actor, 0)
	await say("lao_li", "愿意在湖西岸组织一个小钓鱼聚会吗？我可以按你发布的采购委托提供面包，也会报名参加。你决定愿不愿意出资，建议两小时后开始、持续540分钟，最多4人、至少1人，采购2份面包，预算不超过150金币，玩家实际钓到鱼可给10金币参与奖。NPC只观赛；不要替我或其他人报名。")
	var e := {}
	for candidate in w.social.events.values():
		if candidate.owner == "lao_li" and candidate.terms.kind == "fishing": e = candidate; break
	if e.is_empty():
		await say("lao_li", "澄清分工：你出金币赞助并发布食品采购，我从自己的库存供应面包，你不需要预先拥有面包。活动提案会自动托管采购款并发布公告板订单；我确认愿意按约报名并供货。你仍可以拒绝，但若愿意请直接提交有预算的活动提案，不能代我交货。")
		for candidate in w.social.events.values():
			if candidate.owner == "lao_li" and candidate.terms.kind == "fishing": e = candidate; break
	if e.is_empty(): finish(false, "NPC declined/no executable funded activity"); return
	if not w.social.enroll("player", e).ok: finish(false, "Player enrollment failed"); return
	var needed := int(e.terms.food_quantity)
	s.inventory.add_item("bread", needed)
	if not w.board.claim("player", "live-food", e.id, needed).ok or not w.board.deliver("player", "live-food-delivered", "live-food", needed, int(w.board.commissions[e.id].version)).ok: finish(false, "Actual supplier delivery failed"); return
	await say("farmer_ahe", "湖西岸有老李新组织的钓鱼聚会，你可以查看实际时间、门票和日程，自己决定是否报名观赛；也可以拒绝，不能编造成绩。")
	for p in e.participants.values():
		var body: Node3D = w.actor(p.actor)
		if body != null:
			body.position = Vector3(-40, Farm3DTerrainProfile.surface_height(-40, 108), 108)
			if p.actor != "player": body.move_speed = 8
	s.season.advance_game_minutes(int(e.start) - w.minute()); w.social.advance()
	if e.status != "live" or e.participants.player.state != "attended": finish(false, "Funded activity failed to open with actual attendance"); return
	s.player.position.y += .2; s.player.set_physics_process(true)
	for frame in 35: await physics_frame
	s.player.set_physics_process(false); s.fishing.refresh_location()
	if not s.fishing.equip() or not s.fishing.act().ok: finish(false, "Player cannot fish at activity venue"); return
	s.fishing._will_bite = true
	s.fishing.advance(2); s.fishing.advance(10)
	if not s.fishing.act().ok: finish(false, "Player failed to reel actual bite"); return
	s.fishing.advance(2); s.fishing.advance(2); s.fishing.cancel()
	if int(e.paid_reward) != int(e.terms.reward): finish(false, "Real catch was not rewarded"); return
	if not s.save_game() or not s.load_game(): finish(false, "Activity receipt persistence failed"); return
	e = w.social.events[e.id]
	s.season.advance_game_minutes(int(e.end) - w.minute()); w.social.advance()
	if e.status != "finished": finish(false, "Normal activity failed to settle"); return
	# Another independently chosen activity is deliberately undersubscribed.
	await say("lao_li", "上次聚会已经结束。如果你还愿意办一次小活动，这次可以尝试高尔夫观赛，但需要至少4人报名才开场；我这次不参加。预算和票价你自己考虑，建议只少量采购。报名不足应该取消退票，不要编造参与人数。也可以拒绝再办。")
	var next := {}
	for candidate in w.social.events.values():
		if candidate.status == "enrolling" and candidate.owner == "lao_li": next = candidate; break
	if next.is_empty():
		observations.append({"low_enrollment_path": "Organizer declined a second risky activity; no funds committed."})
	else:
		# Existing ordinary residents/independent NPCs may still enroll; no fake attendance.
		s.season.advance_game_minutes(int(next.start) - w.minute()); w.social.advance()
		if next.status != "cancelled": finish(false, "Low-supply/enrollment activity did not cancel"); return
	if not s.save_game() or not s.load_game(): finish(false, "Final event persistence failed"); return
	finish(true, "Private organizer chose funded activity, supplier actually delivered, independent NPC reviewed invitation, player landed fish and received one proof-bound award; follow-up risk/cancellation retained.")
