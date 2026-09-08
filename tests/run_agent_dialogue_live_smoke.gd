extends SceneTree

var replies: Dictionary = {}
var errors: Array[String] = []
var samples: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("Live dialogue smoke timed out"); quit(1))
	run.call_deferred()

func run() -> void:
	if not "--living-world-live-agents" in OS.get_cmdline_user_args():
		push_error("Explicit isolated live-agent flags required")
		quit(1)
		return
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	var session: Farm3DSession = scene.farm_session
	var runtime: Node = session.agent_runtime
	var dialogue: Node = scene.get_node("FarmInteraction").hud.dialogue_ui
	if session.auto_save or session.auto_restore or not runtime.service_enabled:
		push_error("Live dialogue smoke requires an isolated configured service session")
		quit(1)
		return
	session.season.set_process(false)
	runtime.dialogue_ready.connect(func(actor: String, request: String, speech: String): replies[actor] = {"request_id": request, "speech": speech})
	runtime.dialogue_stream_failed.connect(func(_actor: String, _request: String, error: String): errors.append(error))
	for actor in ["farmer_ahe", "lao_li", "xuezhe_lin"]:
		dialogue.open_agent_dialogue(actor, runtime.get_agent_display_name(actor))
		dialogue.set_agent_interactions(actor, runtime.get_player_interactions(actor))
		var start := Time.get_ticks_msec()
		dialogue.message_input.text = "你在做什么呢？简单聊两句就好。"
		dialogue.send_button.pressed.emit()
		while not replies.has(actor) and errors.is_empty() and Time.get_ticks_msec() - start < 45000:
			await create_timer(.05, true).timeout
		var elapsed := float(Time.get_ticks_msec() - start) / 1000.0
		var history: Array = dialogue.get_agent_history(actor)
		var ok: bool = replies.has(actor) and not str(replies[actor].speech).is_empty() and not dialogue._agent_stream_pending and history.any(func(entry): return entry.get("role") == "agent" and entry.get("text") == replies[actor].speech)
		samples.append({"actor": actor, "seconds": elapsed, "rendered_in_dialogue": ok, "errors": errors.duplicate(), "reply": replies.get(actor, {})})
		print("LIVE DIALOGUE %s: %.2fs, rendered=%s" % [actor, elapsed, ok])
		dialogue.close()
		if not ok: break
	runtime.gateway.cancel_all("game_closed")
	DirAccess.make_dir_recursive_absolute("res://tmp/dialogue-latency")
	var output := FileAccess.open("res://tmp/dialogue-latency/results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"samples": samples, "trace": runtime.session_trace.get_requests()}, "  "))
	output.close()
	var passed := samples.size() == 3 and samples.all(func(sample): return sample.rendered_in_dialogue) and errors.is_empty()
	scene.free()
	quit(0 if passed else 1)
