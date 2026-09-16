extends SceneTree

var checks := 0
var failures := 0
var s: Node
var r: Node
var w: Node
var k: RefCounted
const ACTOR := "xuezhe_lin"

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Survey test timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func intent(key: String, region: String) -> Dictionary:
	return {"protocol_version": 2, "request_id": key, "decision_id": key, "agent_id": ACTOR, "expected_revision": r.executor.world_revision,
		"decision_summary": "勘察", "actions": [{"action_id": key, "idempotency_key": key, "tool_version": 1, "tool_name": "survey", "arguments": {"region_id": region}}]}

func reload_save() -> bool:
	var ok: bool = s.save_game() and s.load_game()
	w.actor(ACTOR).move_speed = 40
	return ok

func step_time(minutes: int) -> void:
	s.season.advance_game_minutes(minutes)
	r.executor.complete_due(w.minute())

func arrive(key: String) -> void:
	for frame in 900:
		k.advance()
		if frame % 6 == 0: step_time(1)
		await physics_frame
		var activity: Dictionary = r.activity_system._activities[key]
		if int(activity.payload.get("survey_started_minute", -1)) >= 0 or activity.status != "in_progress": return
	check(false, "Physical survey arrival timed out")

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	s = scene.farm_session; r = s.agent_runtime; w = s.living_world; k = w.knowledge
	scene.set_process(false); s.season.set_process(false); w.set_process(false); r.set_process(false); r.service_enabled = false
	check(not s.auto_save and not s.auto_restore, "Isolated survey world cannot touch player save")
	s.save_path = "res://tmp/agent-refactor/survey-save.json"
	var npc: NpcEconomyState = s.npc_economy.get_npc_state(ACTOR)
	npc.inventory.bread = 5
	var body: Node3D = w.actor(ACTOR)
	body.position = k.site("forest"); body.move_speed = 40
	var start := body.position
	var batch := intent("auto-survey", "creek")
	batch.actions.append({"action_id": "after-survey", "idempotency_key": "after-survey", "tool_version": 1, "tool_name": "speak", "arguments": {"text": "现场调查完成。", "target_actor_id": "player"}})
	var valid: Dictionary = r.validator.validate(batch, r.registry, r.executor.world_revision, r.role_system)
	check(valid.ok, "Survey arguments still pass existing contract")
	if not valid.ok: quit(1); return
	var result: Dictionary = r.executor.execute_batch(valid.value, w.minute())[0]
	check(result.status == "in_progress", "Distant survey starts movement instead of rejecting arrival")
	check(int(npc.inventory.bread) == 5 and k.reports.is_empty(), "Departure neither consumes bread nor creates evidence")
	r.executor.execute_batch(valid.value, w.minute())
	check(int(npc.inventory.bread) == 5, "Replay during travel cannot charge bread")
	check(reload_save(), "Unpaid survey travel and batch continuation survive save/load")
	await arrive("auto-survey")
	npc = s.npc_economy.get_npc_state(ACTOR); body = w.actor(ACTOR)
	var a: Dictionary = r.activity_system._activities["auto-survey"]
	check(body.position.distance_to(start) > 10 and k.field_status(ACTOR, "creek").arrived, "Survey physically walks from forest to creek")
	check(int(npc.inventory.bread) == 4 and int(a.payload.worked) == 0, "Arrival consumes exactly one bread and starts on-site clock")
	check(k.reports.is_empty() and not r.executor._outcomes.has("after-survey"), "Travel alone creates no report or follow-up action")
	step_time(9)
	check(k.reports.is_empty(), "Nine on-site minutes cannot finish survey")
	check(reload_save(), "Paid partial survey survives save/load")
	step_time(11)
	a = r.activity_system._activities["auto-survey"]
	check(a.status == "completed" and k.reports.has(a.payload.get("discovery_id", "")), "Twenty on-site minutes produce durable report")
	check(r.executor._outcomes.get("after-survey", {}).get("status") == "completed", "Follow-up action waits for actual survey completion")
	check(int(s.npc_economy.get_npc_state(ACTOR).inventory.bread) == 4, "Reload does not charge a second bread")
	check(reload_save() and r.validate_dict(r.to_dict()), "Completed survey proof and report validate after reload")
	var duplicate: Dictionary = r.executor.execute_batch(intent("same-day", "creek"), w.minute())[0]
	check(duplicate.get("failure_code") == "already_surveyed_today", "Repeated same-day survey is rejected without payment")
	check(int(s.npc_economy.get_npc_state(ACTOR).inventory.bread) == 4, "Same-day rejection cannot charge")
	# Supplies are authoritative at arrival, including changes during travel.
	npc = s.npc_economy.get_npc_state(ACTOR)
	check(r.executor.execute_batch(intent("lost-bread", "forest"), w.minute())[0].status == "in_progress", "Second distant survey can start")
	npc.inventory.bread = 0
	await arrive("lost-bread")
	check(r.executor._outcomes["lost-bread"].get("error_code") == "survey_supplies_missing", "Supplies lost en route fail on arrival")
	check(k.reports.size() == 1 and int(npc.inventory.bread) == 0, "Missing supplies create neither evidence nor negative inventory")
	# Old saves lack the new marker because the old executor already paid at start.
	npc.inventory.bread = 3
	check(k.begin_fieldwork(ACTOR, "survey", "forest", "legacy-survey", {}).ok, "At-site survey still checks supplies immediately")
	a = r.activity_system._activities["legacy-survey"]
	a.payload.erase("survey_started_minute")
	check(reload_save(), "Legacy prepaid survey remains loadable")
	step_time(20)
	check(r.activity_system._activities["legacy-survey"].status == "completed" and int(s.npc_economy.get_npc_state(ACTOR).inventory.bread) == 2, "Legacy prepaid survey completes without a second charge")
	# Crossing midnight while walking uses the arrival day for evidence.
	var departure_day: int = w.minute() / 1080
	check(r.executor.execute_batch(intent("cross-day", "hills"), w.minute())[0].status == "in_progress", "Cross-day survey starts")
	step_time(1080 - w.minute() % 1080)
	await arrive("cross-day")
	step_time(20)
	a = r.activity_system._activities["cross-day"]
	check(a.status == "completed" and a.payload.discovery_id == "survey-hills-%d" % (departure_day + 1), "Evidence uses on-site start day, not departure day")
	check(reload_save(), "Cross-day evidence passes save proof validation")
	print("Agent survey: %d checks, %d failures" % [checks, failures])
	scene.queue_free(); await process_frame; quit(0 if failures == 0 else 1)
