extends SceneTree

# Explicitly opt in: --farm-test --living-world-scenario=P12 --living-world-live-agents
var errors: Array = []
var replies: Array = []
var deltas := {}
var visible_before_final := {}
var started_msec := 0
var first_token_msec := -1

func _initialize() -> void:
	var flags := OS.get_cmdline_user_args()
	if "--farm-test" not in flags or "--living-world-live-agents" not in flags: quit(2); return
	create_timer(120).timeout.connect(func(): push_error("Live split chat timed out"); quit(1))
	run.call_deferred()

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	var session: Node = scene.farm_session
	var runtime: Node = session.agent_runtime
	if session.auto_save or session.auto_restore or not runtime.service_enabled:
		push_error("An isolated live-agent session is required"); scene.free(); quit(1); return
	session.season.set_process(false)
	var ui: Node = scene.get_node("FarmInteraction").hud.dialogue_ui
	runtime.dialogue_stream_delta.connect(func(_actor: String, request: String, delta: String):
		if first_token_msec < 0: first_token_msec = Time.get_ticks_msec() - started_msec
		deltas[request] = int(deltas.get(request, 0)) + 1
		if not replies.any(func(row): return row.request == request) and ui.history_view.text.contains(delta): visible_before_final[request] = true)
	runtime.dialogue_ready.connect(func(actor: String, request: String, speech: String): replies.append({"actor":actor,"request":request,"speech":speech}))
	runtime.dialogue_stream_failed.connect(func(_actor: String, _request: String, error: String): errors.append(error))
	ui.open_agent_dialogue("farmer_ahe", runtime.get_agent_display_name("farmer_ahe"))
	var group = ui._group
	group.picker.select(0)
	group.add_selected()
	ui.message_input.text = "大家好，请各自简单打个招呼；后发言的也回应前面那位。今天暂时不安排活动。"
	var start := Time.get_ticks_msec()
	started_msec = start
	ui.send_button.pressed.emit()
	while group.active and Time.get_ticks_msec()-start < 100000:
		await create_timer(.05, true).timeout
	var history: Array = ui._current_history()
	var ok: bool = replies.size() == 2 and errors.is_empty() and history.size() == 3 and not ui._agent_stream_pending
	if ok:
		ok = history[1].speaker_id != history[2].speaker_id and not str(history[1].text).is_empty() and not str(history[2].text).is_empty()
	for row in replies:
		var loop: Dictionary = runtime.loop_state.loops.get(row.request, {})
		ok = ok and loop.get("trigger") == "dialogue" and not runtime.loop_state.dialogue_handoffs.get(row.actor, {}).has("dialogue:"+str(row.request))
		ok = ok and int(deltas.get(row.request, 0)) > 1 and visible_before_final.get(row.request, false)
	print("LIVE STREAM: first_token_ms=%d, delta_counts=%s, visible_before_final=%s" % [first_token_msec,deltas,visible_before_final])
	print("LIVE GROUP: replies=%d, rendered=%s, no_action_from_greeting=%s, seconds=%.2f, errors=%s" % [replies.size(),history.size()==3,ok,float(Time.get_ticks_msec()-start)/1000.0,errors])
	ui.close()
	runtime.gateway.cancel_all("game_closed")
	scene.free()
	quit(0 if ok else 1)
