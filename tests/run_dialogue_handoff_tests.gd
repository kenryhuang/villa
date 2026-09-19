extends SceneTree

const State = preload("res://scripts/ai_agent/agent_loop_state.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	if "--farm-test" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(35).timeout.connect(func(): push_error("Dialogue handoff tests timed out"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func reply(r: Node, request: Dictionary, speech: String) -> Dictionary:
	return {"protocol_version": 2, "request_id": request.request_id, "decision_id": request.request_id + "-decision", "agent_id": request.agent_id,
		"expected_revision": r.executor.world_revision, "decision_summary": "对话", "speech": speech, "actions": []}

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var session: Node = scene.farm_session
	session.season.set_process(false)
	var r: Node = session.agent_runtime
	r.set_process(false)
	var minute: int = r._absolute_game_minute()
	var talk: Dictionary = r._build_loop_request("farmer_ahe", "agreed-trip", "dialogue", minute, "聊完去溪边看看？")
	paused = true
	r._handle_response("farmer_ahe", reply(r, talk, "好，聊完我就去溪边。"))
	var handoffs: Array = r.loop_state.dialogue_followups("farmer_ahe")
	check(handoffs.size() == 1, "Spoken-only acceptance becomes a durable review handoff")
	if handoffs.is_empty(): paused = false; quit(1); return
	check(handoffs[0].payload.player_text == "聊完去溪边看看？" and handoffs[0].payload.agent_speech == "好，聊完我就去溪边。", "Exact two-sided conversation is retained")
	check(r.loop_state.goals.is_empty(), "A transcript is not automatically treated as consent or an invented goal")
	check(r.loop_state.feedback.farmer_ahe.pending, "Dialogue schedules a follow-up")
	check(r._build_request("farmer_ahe", "event", minute, "").is_empty(), "Paused dialogue cannot start background travel")
	check(r.loop_state.dialogue_followups("lao_li").is_empty(), "Handoffs are private to the NPC")
	r.loop_state.acknowledge("farmer_ahe", handoffs.map(func(e): return e.event_id))
	check(r.loop_state.dialogue_followups("farmer_ahe").size() == 1, "Experience sync does not consume pending action review")
	var saved: Dictionary = r.loop_state.to_dict()
	check(State.validate(saved), "Pending handoff save validates")
	var restored = State.new()
	restored.restore(saved)
	check(restored.dialogue_followups("farmer_ahe") == handoffs, "Save reload retains unreviewed dialogue")
	saved.erase("dialogue_handoffs")
	check(State.validate(saved), "Old saves without handoffs remain valid")
	paused = false
	session.npc_economy.get_npc_state("farmer_ahe").gold += 7
	var next: Dictionary = r._build_loop_request("farmer_ahe", "follow-trip", "event", minute + 1, "")
	check(next.dialogue_followups == handoffs, "Next Loop receives the accepted conversation")
	check(next.resources.gold == session.npc_economy.get_npc_state("farmer_ahe").gold, "Next Loop refreshes authoritative resources")
	# A newer conversation can arrive while this background request is running.
	r.loop_state.record_dialogue("farmer_ahe", "new-talk", minute + 1, "先等一下。", "好，先不去了。", [], [])
	var loop: Dictionary = r.loop_state.loops["follow-trip"]
	loop.state = "executing"
	loop.action_ids = ["walk"]
	loop.receipts = {"walk": {"action_id": "walk", "tool_name": "move", "status": "in_progress"}}
	r.loop_state.finish_batches(r, minute + 2)
	check(r.loop_state.dialogue_followups("farmer_ahe").size() == 2, "An in-progress move does not consume its handoff")
	loop.receipts.walk.status = "failed"
	r.loop_state.finish_batches(r, minute + 3)
	check(r.loop_state.dialogue_followups("farmer_ahe").size() == 2 and r.loop_state.feedback.farmer_ahe.pending, "Failed movement retains intent and schedules a fresh review")
	loop.state = "executing"
	loop.receipts.walk.status = "completed"
	r.loop_state.finish_batches(r, minute + 4)
	check(r.loop_state.dialogue_followups("farmer_ahe").size() == 1 and r.loop_state.dialogue_followups("farmer_ahe")[0].event_id == "dialogue:new-talk", "Successful batch consumes only its own snapshot, never a newer conversation")
	var state = State.new()
	for i in 9: state.record_dialogue("a", str(i), i, "建议%d" % i, "待核实", [], [])
	check(state.dialogue_followups("a").size() == 5 and state.dialogue_followups("a").back().event_id == "dialogue:8", "Backlog is bounded and includes newest correction")
	state.acknowledge_dialogues("a", state.dialogue_followups("a").slice(0, 4).map(func(e): return e.event_id))
	check(state.dialogue_followups("a")[0].event_id == "dialogue:4" and state.dialogue_handoffs.a.size() == 5, "Bounded prompt never deletes older unreviewed records")
	state.record_dialogue("b", "trade", 10, "买粮", "我提交了报价。", [], [{"action_id": "trade", "status": "in_progress"}])
	state.update_dialogue_outcome("b", {"action_id": "trade", "status": "completed"})
	check(state.dialogue_followups("b")[0].payload.outcomes[0].status == "completed", "Handoff tracks latest receipts to prevent duplicate actions")
	scene.queue_free()
	await process_frame
	print("DIALOGUE HANDOFF: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
