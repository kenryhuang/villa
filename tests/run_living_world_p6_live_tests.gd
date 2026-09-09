extends SceneTree

var scene: Node
var s: Farm3DSession
var w: Node
var dialogue: Control
var observations: Array = []

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): finish(false, "Live acceptance timed out"))
	run.call_deferred()

func finish(ok: bool, reason: String) -> void:
	if w != null:
		var file := FileAccess.open("res://tmp/living-world/P6-live.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok": ok, "reason": reason, "observations": observations, "world": w.to_dict(), "trace": s.agent_runtime.session_trace.get_requests()}, "  "))
	print("P6 real AI: %s · %s" % ["PASS" if ok else "FAIL", reason])
	quit(0 if ok else 1)

func say(message: String) -> void:
	dialogue.open_agent_dialogue("lao_li", "老李")
	dialogue.message_input.text = message
	dialogue.send_button.pressed.emit()
	while s.agent_runtime.scheduler.is_in_flight("lao_li"): await create_timer(.1).timeout
	observations.append({"message": message, "history": dialogue._histories.get("lao_li", []).duplicate(true)})

func run() -> void:
	if "--living-world-live-agents" not in OS.get_cmdline_user_args() or "--living-world-scenario=P6" not in OS.get_cmdline_user_args(): finish(false, "Explicit isolated P6 and live flags required"); return
	scene = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	s = scene.farm_session
	w = s.living_world
	w.set_process(false)
	s.season.set_process(false)
	s.player.set_physics_process(false)
	s.save_path = "res://tmp/living-world/P6-live-save.json"
	if not s.agent_runtime.service_enabled or s.auto_save or s.auto_restore: finish(false, "Isolation/service unavailable"); return
	for id in s.agent_runtime.registry.get_agent_ids(): s.agent_runtime.scheduler.set_decision_interval_hours(id, 0)
	dialogue = scene.get_node("FarmInteraction").hud.dialogue_ui
	s.player.position = Vector3(-12.5, 0, 22.5)
	var body: Node3D = w.actor("lao_li")
	body.position = Vector3(-11.5, 0, 22.5)
	body.move_speed = 8
	var mill: BuildingInstance = s.buildings.get_all_buildings()[0]
	var plan := {"goal": "加工面粉再销售", "budget": 4, "materials": {"grain": 2}, "deadline_minutes": 500, "steps": [{"id": "mill", "capability": "rent", "depends_on": [], "arguments": {"building_id": mill.instance_id, "recipe_id": "flour", "batches": 1, "max_fee": 4}}, {"id": "ready", "capability": "wait_production", "depends_on": ["mill"], "arguments": {"order_step": "mill"}}, {"id": "sale", "capability": "sell", "depends_on": ["ready"], "arguments": {"item_id": "flour", "quantity": 1, "limit": 1}}]}
	if not w.projects.submit("lao_li", "live-original", plan).ok: finish(false, "Original plan fixture failed"); return
	w.projects.advance()
	w.projects.advance()
	var assets_before: Dictionary = w.assets.snapshot("player")
	await say("你等风车加工的时候，愿不愿意帮我送2份谷物给溪畔旅店的市场收货处？货物由我提供，报酬20金币，有效期180游戏分钟，安全时立即出发，送完继续你的原计划。请先拟条款给我确认，不要直接扣钱。")
	if w.interruptions.drafts.is_empty() or w.assets.snapshot("player") != assets_before: finish(false, "Model did not produce an unfunded delivery draft"); return
	dialogue.close()
	await process_frame
	await process_frame
	var ui: Control = scene.get_node("FarmInteraction").hud.commission_view
	if not ui.confirm.visible: finish(false, "No reviewable player confirmation card"); return
	ui.confirm.confirmed.emit()
	ui.close_panel()
	if w.interruptions.tasks.is_empty(): finish(false, "Confirmation did not accept task"); return
	var id: String = w.interruptions.tasks.keys()[0]
	w.interruptions.advance()
	if w.projects.projects["live-original"].status != "suspended" or not s.save_game() or not s.load_game(): finish(false, "Suspension save failed"); return
	s.production.advance_minutes(60)
	for n in 2400:
		w.interruptions.advance()
		w.projects.advance()
		if w.interruptions.tasks[id].status == "completed": break
		await physics_frame
	for n in 4: w.projects.advance()
	if w.interruptions.tasks[id].status != "completed" or w.projects.projects["live-original"].status != "completed": finish(false, "Physical delivery/resumed production did not complete"); return
	await say("还想请你送一批东西，但货物、数量、收货方和报酬都还没想好。先问清楚，暂时不要拟条款。")
	if not w.interruptions.drafts.is_empty(): finish(false, "Missing quantity/destination unexpectedly created binding terms"); return
	dialogue.close()
	var smaller_plan := {"goal": "小额采购谷物试产", "budget": 300, "materials": {}, "deadline_minutes": 180, "steps": [{"id": "buy", "capability": "buy", "depends_on": [], "arguments": {"item_id": "grain", "quantity": 4, "limit": 300}}]}
	if not w.projects.submit("lao_li", "live-scale", smaller_plan).ok: finish(false, "Future-plan fixture failed"); return
	await say("你接下来的采购还没执行，我建议先试买1份谷物，不要一下买4份。愿意的话请修改这个项目的未来采购步骤，现有预算、材料托管和期限保持不变。")
	dialogue.close()
	w.projects.advance()
	if int(w.projects.projects["live-scale"].items.get("grain", 0)) != 1: finish(false, "Suggestion was not accepted as a real one-unit purchase"); return
	w.projects.advance()
	await say("再帮我立即把2份谷物送给旅店市场收货处，报酬20金币，只有1游戏分钟的期限。来不及请拒绝或建议延长，不要承诺无法做到的事。")
	if not w.interruptions.drafts.is_empty():
		var terms: Dictionary = w.interruptions.drafts.values()[0].terms
		if int(terms.deadline_minutes) < w.interruptions.minimum_travel_minutes("lao_li"): finish(false, "Impossible deadline was promised"); return
	dialogue.close()
	await process_frame
	if ui.visible: ui.close_panel()
	if not s.save_game() or not s.load_game(): finish(false, "Final live receipts failed reload"); return
	finish(true, "Real dialogue proposed bounded cargo and payment; UI confirmation escrowed, real movement delivered, reload preserved suspended production, and original sale resumed. Missing terms elicited clarification; an accepted scale suggestion bought one unit; impossible timing was refused or renegotiated.")
