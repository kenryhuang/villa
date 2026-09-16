extends SceneTree

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Loop wire timeout"); quit(1))
	run.call_deferred()

func run() -> void:
	var address := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--loop-service="): address = arg.trim_prefix("--loop-service=")
	if address.is_empty(): quit(2); return
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var session: Node = scene.farm_session
	session.season.set_process(false)
	var r: Node = session.agent_runtime
	r.set_process(false)
	r.gateway.process_mode = Node.PROCESS_MODE_ALWAYS
	if not r.gateway.configure(address, "", 42, 10): quit(3); return
	var request: Dictionary = r._build_loop_request("farmer_ahe", "godot-wire", "dialogue", r._absolute_game_minute(), "我有哪些空地？")
	var done := [false]
	var success := [false]
	var read_count := [0]
	var on_event := func(event: Dictionary):
		var data: Dictionary = event.data.payload
		if event.event == "read.request":
			read_count[0] += 1
			var result: Dictionary = r.world_queries.read(r, "farmer_ahe", str(data.name), data.arguments)
			r.gateway.submit_read_result(data.merged({"result": result}, true))
		elif event.event == "context.ack": r.loop_state.acknowledge("farmer_ahe", data.event_ids)
	var on_done := func(ok: bool, reply: Dictionary, error: String):
		print("WIRE_REPLY:", JSON.stringify({"ok": ok, "reply": reply, "error": error, "reads": read_count[0]}))
		success[0] = ok and reply.get("speech", "") == "我查到了自己的农田。" and read_count[0] == 1
		done[0] = true
	paused = true
	if not r.gateway.request_decision("farmer_ahe", request, on_done, on_event): quit(4); return
	while not done[0]: await process_frame
	paused = false
	scene.queue_free()
	await process_frame
	quit(0 if success[0] else 1)
