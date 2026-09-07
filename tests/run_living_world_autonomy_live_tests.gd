extends SceneTree

var scene: Node
var stage := "P3"
var negative := false
var draft_check := false

func _initialize() -> void:
	create_timer(480).timeout.connect(func(): finish(false, "Real provider timeout"))
	run.call_deferred()

func finish(ok: bool, reason: String) -> void:
	if scene != null:
		var s: Node = scene.farm_session
		var file := FileAccess.open("res://tmp/living-world/%s-autonomy-live%s.json" % [stage, "-draft" if draft_check else ("-negative" if negative else "")], FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok": ok, "reason": reason, "trace": s.agent_runtime.session_trace.get_requests(), "world": s.living_world.to_dict(), "outcomes": s.agent_runtime.executor.to_dict()}, "  "))
		file.close()
	print("%s real AI: %s · %s" % [stage, "PASS" if ok else "FAIL", reason])
	quit(0 if ok else 1)

func run() -> void:
	if "--living-world-live-agents" not in OS.get_cmdline_user_args(): finish(false, "Explicit live flag required"); return
	negative = "--living-world-counterexample" in OS.get_cmdline_user_args()
	draft_check = "--living-world-draft-check" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--living-world-scenario="): stage = arg.trim_prefix("--living-world-scenario=")
	scene = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var s: Farm3DSession = scene.farm_session
	s.season.set_process(false)
	s.save_path = "res://tmp/living-world/%s-autonomy-save.json" % stage
	var w: Node = s.living_world
	w.set_process(false)
	var runtime: Node = s.agent_runtime
	if not runtime.service_enabled or s.auto_save or s.auto_restore: finish(false, "Fixture isolation/service unavailable"); return
	for id in runtime.registry.get_agent_ids(): runtime.scheduler.set_decision_interval_hours(id, 0)
	for id in w.board.commissions.keys(): w.board.cancel(w.board.commissions[id].actor_id, id)
	if draft_check:
		s.save_path = "res://tmp/living-world/P5-draft-save.json"
		var wallet: Node = root.get_node("GameState")
		var gold: int = wallet.gold
		var dialogue: Node = scene.get_node("FarmInteraction").hud.dialogue_ui
		dialogue.open_agent_dialogue("lao_li", runtime.get_agent_display_name("lao_li"))
		dialogue.message_input.text = "请帮我拟一份由我支付报酬的采购委托：2份面粉，每份100金币，有效期600游戏分钟，最多1人接单，允许现货。先给确认草稿，等我确认再发布。"
		dialogue.send_button.pressed.emit()
		while runtime.scheduler.is_in_flight("lao_li"): await create_timer(.1).timeout
		if w.pending_player_terms.is_empty() or wallet.gold != gold: finish(false, "Model did not create an unfunded player draft"); return
		dialogue.close()
		await process_frame
		await process_frame
		var ui: Node = scene.get_node("FarmInteraction").hud.commission_view
		if not ui.confirm.visible or wallet.gold != gold: finish(false, "Draft did not await UI confirmation"); return
		ui.confirm.confirmed.emit()
		ui.close_panel()
		if wallet.gold != gold - 200 or paused: finish(false, "Confirmed draft failed debit/resume"); return
		if not s.save_game() or not s.load_game(): finish(false, "Dialogue commission failed persistence"); return
		finish(true, "Real dialogue produced player terms; only explicit UI confirmation prepaid and published the commission")
		return
	var npc: NpcEconomyState = s.npc_economy.get_npc_state("lao_li")
	npc.inventory = {"grain": 20, "bread": 3}
	npc.gold = 1000
	var mill: BuildingInstance = s.buildings.get_all_buildings()[0]
	if stage == "P4":
		npc.inventory = {"plank": 10, "stone_brick": 8, "rope": 2, "grain": 20, "bread": 3}
		npc.gold = 8000
		mill.service_policy.open = false
		s.npc_economy.get_npc_state("village_inn").gold = 100000
		w.board.demand("long-flour", "village_inn", "flour", 100)
		w.board.publish("village_inn", "long-flour", {"demand_id": "long-flour", "item_id": "flour", "quantity": 100, "unit_reward": 500, "max_claims": 3, "deadline_minutes": 10080, "kind": "processing"})
	elif stage == "P5":
		w.board.demand("fresh-flour", "player", "flour", 2)
		if not w.board.publish("player", "fresh-flour", {"demand_id": "fresh-flour", "item_id": "flour", "quantity": 2, "unit_reward": 300, "max_claims": 1, "deadline_minutes": 1080, "kind": "processing"}).ok: finish(false, "Commission fixture failed"); return
	if negative:
		for id in w.board.commissions.keys(): w.board.cancel(w.board.commissions[id].actor_id, id)
		npc.inventory = {"bread": 1}
		npc.gold = 0
		mill.service_policy.open = false
	# Schedule-triggered decision with actual world data, no player instruction and no supplied plan.
	if not runtime.scheduler._dispatch("lao_li", "schedule", w.minute(), ""): finish(false, "Autonomous request was not dispatched"); return
	while runtime.scheduler.is_in_flight("lao_li"): await create_timer(.1).timeout
	var project: Dictionary = w.projects.active("lao_li")
	if negative:
		var investment: bool = not project.is_empty() and project.plan.steps.any(func(step): return step.capability in ["rent", "build"])
		for index in 12: w.projects.advance()
		finish(not investment and npc.gold >= 0, "Without funded demand/capital, model declined production/construction or chose a smaller liquidity/reserve goal; no negative wallet")
		return
	if project.is_empty(): finish(false, "Model did not submit an autonomous executable project"); return
	var capabilities: Array = project.plan.steps.map(func(step): return step.capability)
	if stage == "P3" and ("rent" not in capabilities or "sell" not in capabilities): finish(false, "Autonomous project lacks production/sale chain"); return
	if stage == "P4" and ("buy" not in capabilities or "move" not in capabilities or "build" not in capabilities or "set_policy" not in capabilities): finish(false, "Autonomous project lacks procurement/physical construction/opening"); return
	if stage == "P5" and ("claim" not in capabilities or "rent" not in capabilities or "deliver" not in capabilities): finish(false, "Autonomous project lacks processing commission lifecycle"); return
	var replans := 0
	var deadline := Time.get_ticks_msec() + 240000
	while project.status == "active" and Time.get_ticks_msec() < deadline:
		w.projects.advance()
		s.production.advance_minutes(5)
		w.construction.advance()
		if project.steps.values().any(func(step): return step.status == "blocked"):
			if replans >= 2: finish(false, "Model could not resolve blocked work: " + str(project.reason)); return
			replans += 1
			if not runtime.scheduler._dispatch("lao_li", "event", w.minute(), ""): finish(false, "Replan could not dispatch"); return
			while runtime.scheduler.is_in_flight("lao_li"): await create_timer(.1).timeout
			var revised: Dictionary = w.projects.active("lao_li")
			if revised.is_empty(): finish(false, "Model declined further work after blockage"); return
			project = revised
		await create_timer(.1).timeout
	if project.status != "completed": finish(false, "Project did not complete"); return
	if not s.save_game() or not s.load_game(): finish(false, "Completed real AI project failed persistence"); return
	finish(true, "Scheduled model chose and completed its own project with real assets and durable receipts")
