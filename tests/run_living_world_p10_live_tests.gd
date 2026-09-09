extends SceneTree
var scene: Node
var s: Farm3DSession
var w: Node
var evidence := []
var ended := false
func _initialize() -> void:
	create_timer(600).timeout.connect(func(): finish(false, "P10 live timeout"))
	run.call_deferred()
func finish(ok: bool, reason: String) -> void:
	if ended: return
	ended = true
	if w != null:
		var f := FileAccess.open("res://tmp/living-world/P10-live.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"ok": ok, "reason": reason, "evidence": evidence, "environment": w.environment.to_dict(), "public": w.public_plans.to_dict(), "public_observations": w.public_plans.observations, "trace": s.agent_runtime.session_trace.get_requests()}, "  ")); f.close()
	print("P10 real AI: %s · %s" % ["PASS" if ok else "FAIL", reason]); quit(0 if ok else 1)
func run() -> void:
	if "--living-world-scenario=P10" not in OS.get_cmdline_user_args() or "--living-world-live-agents" not in OS.get_cmdline_user_args(): finish(false, "Isolated live flags required"); return
	scene = load("res://scenes/farm3d/main.tscn").instantiate(); root.add_child(scene)
	s = scene.farm_session; w = s.living_world
	scene.set_process(false); w.set_process(false); s.season.set_process(false); s.player.set_physics_process(false)
	s.save_path = "res://tmp/living-world/P10-live-save.json"
	for actor in s.agent_runtime.registry.get_agent_ids(): s.agent_runtime.scheduler.set_decision_interval_hours(actor, 0)
	for seed in range(1, 100):
		if absi(hash("weather:%d:0" % seed)) % 4 == 0: w.environment.seed = seed; w.environment.days.clear(); break
	w.environment.dispatch_import("lao_li", "bread", 4, 40, 1)
	s.season.advance_game_minutes(180)
	w.public_plans.bind_runtime()
	w.public_plans.scheduler._dispatch("village_public", "event", w.minute(), "")
	while w.public_plans.scheduler.is_in_flight("village_public"): await create_timer(.1).timeout
	evidence.append({"public_decision": w.public_plans.observations.duplicate(true)})
	if w.public_plans.receipts.is_empty(): finish(false, "No valid public decision (including waiting)"); return
	# A private actor decides whether to contribute actual materials and on-site work.
	w.actor("lao_li").position = w.environment.SITE
	w.assets.apply("lao_li", {"wood": 6, "stone": 4}, 0)
	var ui: Control = scene.get_node("FarmInteraction").hud.dialogue_ui
	ui.open_agent_dialogue("lao_li", w.actor_name("lao_li"))
	ui.message_input.text = "你的商队正因降雨堵在场外商道，我会提供缺少的木材石料，但你可以考虑帮忙劳动60分钟。你已经在修复点，公共预算安排请以环境信息为准，不保证一定有补贴。愿意就提交实际劳动，否则可以拒绝等待自然恢复，不要替我扣材料。"
	ui.send_button.pressed.emit()
	while s.agent_runtime.scheduler.is_in_flight("lao_li"): await create_timer(.1).timeout
	evidence.append({"npc_response": ui._histories.get("lao_li", []).duplicate(true)})
	ui.close(); await process_frame
	var board: Control = scene.get_node("FarmInteraction").hud.commission_view
	if board.visible: board.close_panel()
	s.player.position = w.environment.SITE
	s.inventory.add_item("wood", 6); s.inventory.add_item("stone", 4)
	var materials := {}
	for item in w.environment.REPAIR:
		var amount := int(w.environment.REPAIR[item]) - int(w.environment.event.materials[item])
		if amount > 0: materials[item] = amount
	if not materials.is_empty(): w.environment.command("player", "contribute_route_repair", {"event_id": w.environment.event.id, "materials": materials, "labor_minutes": 0}, "live-player-materials")
	if not w.environment.busy("lao_li"):
		# Refusal is retained as a valid autonomous choice; the player can finish locally.
		w.environment.command("player", "contribute_route_repair", {"event_id": w.environment.event.id, "materials": {}, "labor_minutes": 60}, "live-player-labor")
	s.season.advance_game_minutes(60)
	if not w.environment.route_open(): finish(false, "Actual local contributions failed to restore route"); return
	s.season.advance_game_minutes(2)
	if not s.save_game() or not s.load_game(): finish(false, "Live environment save failed"); return
	evidence.append({"participation_path": w.environment.to_dict()})
	# Second path: no player materials/labor; public AI may choose support or waiting.
	w.environment.event = {"id": "live-natural", "status": "blocked", "started": w.minute(), "natural_recovery": w.minute() + 1080, "materials": {"wood": 0, "stone": 0}, "labor": 0, "recovered": -1, "cause": "independent isolated rain obstruction"}
	w.public_plans.last_review = w.minute() - 180; w.public_plans.last_plan = w.minute() - 180
	w.public_plans.scheduler._dispatch("village_public", "event", w.minute(), "")
	while w.public_plans.scheduler.is_in_flight("village_public"): await create_timer(.1).timeout
	s.season.advance_game_minutes(1080)
	if not w.environment.route_open() or w.environment.event.resolution != "natural_drainage": finish(false, "Non-participation path stalled"); return
	finish(true, "Real public/private decisions retained, including refusal/wait if chosen. Actual player/NPC contributions restored first route; second recovered naturally with no required player participation.")
