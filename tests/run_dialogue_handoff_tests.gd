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
	check(talk.chat_focus_actors.size() == session.living_world.society.focus.size(), "Chat roster contains only important actors")
	for actor in talk.chat_focus_actors:
		check(actor.actor_id in session.living_world.society.focus and actor.display_name == session.living_world.actor_name(actor.actor_id), "Important actor uses current display name")
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
	# Split-chat extraction is reported after the chat stream has already finished.
	var trace: Node = r.get_session_trace()
	trace.accept_event({"event":"stream.started", "data":{"request_id":"split-debug", "agent_id":"lao_li", "timestamp_msec":1, "payload":{"trigger":"dialogue"}}})
	trace.accept_event({"event":"stream.completed", "data":{"request_id":"split-debug", "agent_id":"lao_li", "timestamp_msec":2, "payload":{}}})
	r.loop_state.record_chat_handoffs("lao_li", "split-debug", minute, [{"kind":"visit","activity":"buy","status":"agreed","target_actor_id":"player","place_id":"market","item_id":"","quantity":0,"gold":0,"delay_minutes":0,"trade_side":"none","building_type":"","plot":-1}])
	var extracted: Array = r.loop_state.dialogue_followups("lao_li")
	check(extracted.size() == 1 and extracted[0].payload.handoffs[0].activity == "buy", "Extracted behavior survives client acceptance")
	var extracted_save: Dictionary = r.loop_state.to_dict()
	check(State.validate(extracted_save), "Structured activity save validates")
	var extracted_restored = State.new()
	extracted_restored.restore(extracted_save)
	check(extracted_restored.dialogue_followups("lao_li") == extracted, "Structured activity survives save and restore")
	var action_request: Dictionary = r._build_loop_request("lao_li", "split-action", "event", minute + 1, "")
	check(action_request.dialogue_followups == extracted, "Action context receives exact destination and activity")
	r.service_enabled = true
	paused = true
	r._trace_pending_handoffs()
	check(trace.get_handoff_report("split-debug").delivery_status.contains("暂停"), "Completed chat trace exposes the actual paused scheduling blocker")
	paused = false
	r.scheduler.restore_budget({"day":minute / 1080,"calls":16})
	r.scheduler.max_daily_requests = 16
	r._trace_pending_handoffs()
	check(trace.get_handoff_report("split-debug").delivery_status.contains("16/16"), "Completed chat trace updates when the daily quota is the blocker")
	var event_count: int = trace.get_request("split-debug").action_events.size()
	r._trace_pending_handoffs()
	check(trace.get_request("split-debug").action_events.size() == event_count, "Repeated frames do not duplicate identical pending diagnostics")
	check(trace.get_handoff_report("split-debug").context_evidence.is_empty(), "Client queue diagnostics never claim model delivery")
	r.service_enabled = false
	var spoken: Array[String] = []
	r.dialogue_ready.connect(func(_actor: String, _request_id: String, speech: String): spoken.append(speech))
	var clean_chat: Dictionary = r._build_loop_request("lao_li", "clean-chat", "dialogue", minute, "你好")
	var clean_reply: Dictionary = reply(r, clean_chat, "你好，我们去散步吧。")
	clean_reply.chat_isolated = true
	clean_reply.chat_extraction_failed = true
	r._handle_response("lao_li", clean_reply)
	check(spoken.size() == 1 and spoken[0] == clean_reply.speech, "Isolated chat displays only model reply, not extraction diagnostics")
	scene.queue_free()
	await process_frame
	print("DIALOGUE HANDOFF: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
