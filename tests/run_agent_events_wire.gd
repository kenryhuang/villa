extends SceneTree

func _initialize() -> void:
	create_timer(25).timeout.connect(func(): push_error("Agent event wire timeout"); quit(1))
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
	var runtime: Node = session.agent_runtime
	runtime.session_id = "event-wire"
	if not runtime.gateway.configure(address, "", 42, 10): quit(3); return
	runtime.service_enabled = true
	runtime.scheduler.max_concurrent_requests = 1
	for actor in runtime.registry.get_agent_ids(): runtime.scheduler.set_decision_interval_hours(actor, 0)
	# The real runtime must collect intents while paused without a debug window.
	paused = true
	while runtime.scheduler.event_queue.messages.size() < 2: await process_frame
	if runtime.scheduler.background_in_flight_count() != 0: quit(4); return
	var snapshot: Dictionary = runtime.to_dict()
	if not runtime.validate_dict(JSON.parse_string(JSON.stringify(snapshot))): quit(5); return
	# Stop time and all periodic producers: only completion can start the second NPC.
	runtime.set_process(false)
	paused = false
	runtime.scheduler.pump(runtime._absolute_game_minute())
	while runtime.scheduler.budget_calls < 2 or runtime.scheduler.background_in_flight_count() > 0:
		if runtime.scheduler.background_in_flight_count() > 1: quit(6); return
		await process_frame
	if not runtime.scheduler.event_queue.messages.is_empty(): quit(7); return
	print("EVENT_WIRE_OK: collected while paused; two NPC loops completed with one slot and no clock ticks")
	scene.queue_free()
	await process_frame
	quit(0)
