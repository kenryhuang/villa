extends SceneTree

var scene: Node
var s: Farm3DSession
var w: Node
var observations := []
var ended := false

func _initialize() -> void:
	create_timer(600).timeout.connect(func(): finish(false, "P9 live timeout"))
	run.call_deferred()

func finish(ok: bool, reason: String) -> void:
	if ended: return
	ended = true
	if w != null:
		var f := FileAccess.open("res://tmp/living-world/P9-live.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"ok": ok, "reason": reason, "observations": observations, "knowledge": w.knowledge.to_dict(), "trace": s.agent_runtime.session_trace.get_requests()}, "  "))
		f.close()
	print("P9 real AI: %s · %s" % ["PASS" if ok else "FAIL", reason])
	quit(0 if ok else 1)

func say(message: String) -> void:
	var ui: Control = scene.get_node("FarmInteraction").hud.dialogue_ui
	ui.open_agent_dialogue("xuezhe_lin", w.actor_name("xuezhe_lin"))
	ui.message_input.text = message
	ui.send_button.pressed.emit()
	while s.agent_runtime.scheduler.is_in_flight("xuezhe_lin"): await create_timer(.1).timeout
	observations.append({"message": message, "history": ui._histories.get("xuezhe_lin", []).duplicate(true)})
	ui.close()
	await process_frame
	var board: Control = scene.get_node("FarmInteraction").hud.commission_view
	if board.visible: board.close_panel()

func run() -> void:
	if "--living-world-live-agents" not in OS.get_cmdline_user_args() or "--living-world-scenario=P9" not in OS.get_cmdline_user_args(): finish(false, "Explicit isolated live flags required"); return
	scene = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	s = scene.farm_session; w = s.living_world
	scene.set_process(false); w.set_process(false); s.season.set_process(false); s.player.set_physics_process(false)
	s.save_path = "res://tmp/living-world/P9-live-save.json"
	if s.auto_save or s.auto_restore or not s.agent_runtime.service_enabled: finish(false, "Isolation unavailable"); return
	for actor in s.agent_runtime.registry.get_agent_ids(): s.agent_runtime.scheduler.set_decision_interval_hours(actor, 0)
	s.player.position = Vector3(-12.5, 0, 22.5)
	w.actor("xuezhe_lin").position = w.knowledge.site("creek") + Vector3(-2, 0, 0)
	w.actor("xuezhe_lin").move_speed = 10
	s.inventory.add_item("bread", 6)
	await say("我想资助一次河岸调查，愿意提供两份面包和最多80金币，期限500游戏分钟。要求本次实地重新调查（allow_old_report=false），回来交报告，不强求发现样本（require_sample=false）。你愿意吗？如愿意请提出调查协议，报酬你自己考虑，由我确认付款；可以拒绝，不能代我同意。")
	var proposal := {}
	for c in w.knowledge.assignments.values():
		if c.status == "proposed" and c.terms.funder_id == "player": proposal = c; break
	if proposal.is_empty(): finish(false, "NPC declined or did not propose funded research"); return
	if proposal.terms.allow_old_report or proposal.terms.require_sample or int(proposal.terms.reward) > 80 or not w.knowledge.accept_investigation("player", proposal.id, int(proposal.version)).ok: finish(false, "Player cannot accept proposed terms"); return
	var id: String = proposal.id
	if not s.save_game() or not s.load_game(): finish(false, "Accepted research reload failed"); return
	w.actor("xuezhe_lin").move_speed = 10
	for frame in 2400:
		w.knowledge.advance()
		if frame % 4 == 0: s.season.advance_game_minutes(1)
		await physics_frame
		if w.knowledge.assignments[id].status in ["completed", "expired", "cancelled", "no_sample"]: break
	if w.knowledge.assignments[id].status != "completed": finish(false, "Physical research did not return completed report"); return
	# A separate private investigation is physically executed; its sale is a new model choice.
	w.actor("xuezhe_lin").position = w.knowledge.site("hills")
	w.assets.apply("xuezhe_lin", {"bread": 1}, 0)
	if not w.knowledge.begin_fieldwork("xuezhe_lin", "survey", "hills", "live-private-survey", {}).ok: finish(false, "Private fieldwork could not start"); return
	s.season.advance_game_minutes(20)
	await say("你另外一份私人丘陵调查报告，如果对我有用，可以先给我一个只含价值概要的报价，不要提前告诉我具体坐标或内容。我愿意考虑最多30金币，这次希望购买私人情报，请自行确定不超过30金币的价格并提出情报报价；也可以拒绝交易。")
	var offer := {}
	for o in w.knowledge.offers.values():
		if o.buyer == "player" and o.status == "proposed": offer = o; break
	if offer.is_empty(): finish(false, "No private paid offer; inspect actual free/declined outcome"); return
	if w.knowledge.known("player", offer.discovery_id) or w.knowledge.cards("player", true).reports.any(func(r): return r.id == offer.discovery_id): finish(false, "Private report leaked before purchase"); return
	if int(offer.price) > 30 or not w.knowledge.purchase("player", offer.id, int(offer.version)).ok: finish(false, "Private purchase failed"); return
	var report: Dictionary = w.knowledge.reports[offer.discovery_id]
	observations.append({"purchased": report, "assignment": w.knowledge.assignments[id]})
	# The purchased coordinate is usable in the actual map and grants no sample remotely.
	if not s.grid.is_navigation_cell_walkable(s.grid.world_to_grid(report.position.x, report.position.z)): finish(false, "Purchased position unusable"); return
	if not s.save_game() or not s.load_game(): finish(false, "Final research/intelligence persistence failed"); return
	finish(true, "Real model proposed funded fieldwork; physical return paid once after reload. Separate private observation was quoted and bought, unlocking its actual map position.")
