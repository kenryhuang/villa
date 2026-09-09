extends SceneTree

var scene: Node
var s: Farm3DSession
var w: Node
var window := 1
var rows := []
var ended := false

func _initialize() -> void:
	create_timer(1800).timeout.connect(func(): finish(false, "Live observation timeout"))
	run.call_deferred()

func run() -> void:
	if "--living-world-live-agents" not in OS.get_cmdline_user_args() or "--living-world-scenario=P12" not in OS.get_cmdline_user_args(): finish(false, "Explicit isolation/live flags required"); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--window="): window = int(arg.trim_prefix("--window="))
	scene = load("res://scenes/farm3d/main.tscn").instantiate(); root.add_child(scene)
	s = scene.farm_session; w = s.living_world
	scene.set_process(false); w.set_process(false); s.season.set_process(false); s.player.set_physics_process(false)
	if s.auto_save or s.auto_restore or not s.agent_runtime.service_enabled: finish(false, "Isolation/service unavailable"); return
	s.save_path = "res://tmp/living-world/P12-live-%d-save.json" % window
	w.environment.seed = [42, 93][(window - 1) % 2]; w.environment.days.clear(); w.environment.ensure_day(0)
	for id in s.agent_runtime.registry.get_agent_ids(): s.agent_runtime.scheduler.set_decision_interval_hours(id, 0)
	w.public_plans.bind_runtime()
	w.public_plans.scheduler.set_decision_interval_hours("village_public", 0)
	s.agent_runtime.service_enabled = false
	for id in w.society.focus: w.actor(id).move_speed = 40
	for day in 14:
		# One private planner daily, rotating all six identities, plus the public
		# coordinator every other day. No proposed plan or action is supplied.
		var actor: String = w.society.focus[(day + window - 1) % w.society.focus.size()]
		s.agent_runtime.service_enabled = true
		var sent: bool = s.agent_runtime.scheduler._dispatch(actor, "schedule", w.minute(), "")
		while s.agent_runtime.scheduler.is_in_flight(actor): await create_timer(.1).timeout
		if day % 2 == 0:
			w.public_plans.scheduler._dispatch("village_public", "schedule", w.minute(), "")
			while w.public_plans.scheduler.is_in_flight("village_public"): await create_timer(.1).timeout
		# Freeze new requests while accelerating time; accepted domain work continues.
		s.agent_runtime.service_enabled = false
		for step in 216:
			s.season.advance_game_minutes(5)
			while not w.society.caught_up(w.minute()): w.advance(); await process_frame
			w.advance(); await physics_frame
		var valid := s.save_game() and s.load_game()
		rows.append({"day": day + 1, "actor": actor, "sent": sent, "saved": valid, "food": w.society.day_reports.get(str(day + 1), {}).duplicate(true), "private_budget": s.agent_runtime.scheduler.budget_state(), "public_budget": w.public_plans.scheduler.budget_state(), "projects": w.projects.to_dict()})
		print("P12 live window %d day %d saved=%s" % [window, day + 1, valid])
		if not valid: finish(false, "Daily save validation failed"); return
		for id in w.society.focus: w.actor(id).move_speed = 40
	finish(true, "14-day actual provider observation completed; refusals, failed actions and shortages retained, not scored as forced investment successes")

func finish(ok: bool, reason: String) -> void:
	if ended: return
	ended = true
	if w != null:
		var f := FileAccess.open("res://tmp/living-world/P12-live-%d.json" % window, FileAccess.WRITE)
		f.store_string(JSON.stringify({"ok": ok, "reason": reason, "rows": rows, "trace": s.agent_runtime.session_trace.get_requests(), "world": w.to_dict(), "outcomes": s.agent_runtime.executor.to_dict()}, "  ")); f.close()
	print("P12 live: %s · %s" % [ok, reason]); quit(0 if ok else 1)
