extends SceneTree

var checks := 0
var failures := 0
var scene: Node
var session: Farm3DSession
var runtime: Node
var world: Node

class RecordingGateway extends Node:
	var session_epoch := 1
	var requests: Array[Dictionary] = []
	var callbacks := {}
	func request_decision(actor: String, request: Dictionary, done: Callable, _event: Callable) -> bool:
		if actor == "village_public": return false
		requests.append(request.duplicate(true))
		callbacks[actor] = done
		return true
	func complete() -> void:
		var pending := callbacks.duplicate()
		callbacks.clear()
		for done in pending.values(): done.call(false, {}, "cancelled")
	func report_outcome(_actor: String, _session: String, _outcome: Dictionary) -> bool:
		return true

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Agent scheduling timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func settle() -> void:
	while not world.society.caught_up(world.minute()):
		await process_frame
		world.advance()

func run() -> void:
	scene = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	session = scene.farm_session
	runtime = session.agent_runtime
	world = session.living_world
	check(not session.auto_save and not session.auto_restore and not runtime.service_enabled, "Test scene is isolated from saves and remote providers")
	scene.set_process(false)
	session.season.set_process(false)
	session.player.set_physics_process(false)
	runtime.set_process(false)
	world.set_process(false)
	var gateway := RecordingGateway.new()
	runtime.add_child(gateway)
	runtime.gateway = gateway
	runtime.scheduler._gateway = gateway
	world.public_plans.bind_runtime()
	world.public_plans.scheduler._gateway = gateway
	for id in runtime.registry.get_agent_ids(): runtime.scheduler.set_decision_interval_hours(id, 0)
	runtime.scheduler.set_decision_interval_hours("lao_li", 1)
	runtime.scheduler.max_daily_requests = 2
	runtime.scheduler.max_concurrent_requests = 1
	runtime.service_enabled = true
	# Exhaust this frame's settlement slice to exercise a multi-frame catch-up.
	world._society_frame = Engine.get_process_frames()
	world._society_frame_us = 3000
	session.season.advance_game_minutes(60)
	check(gateway.requests.is_empty(), "Time signal does not plan against unsettled society data")
	if not world.society.caught_up(world.minute()):
		runtime._process(0.0)
		check(gateway.requests.is_empty(), "Scheduler keeps waiting across frames while settlement is incomplete")
	await settle()
	paused = true
	runtime._process(0.0)
	check(gateway.requests.is_empty(), "Modal pause prevents the deferred scheduling pass")
	paused = false
	runtime._process(0.0)
	check(gateway.requests.size() == 1, "After settlement and resume, the due NPC receives its scheduled decision without another time signal")
	if not gateway.requests.is_empty():
		check(gateway.requests[0].agent_id == "lao_li" and gateway.requests[0].trigger == "schedule" and int(gateway.requests[0].game_minute) == 60, "Recovered decision uses the eligible actor and current authoritative minute")
	var rotation: int = runtime.scheduler._rotation
	for frame in 8: runtime._process(0.0)
	check(gateway.requests.size() == 1 and runtime.scheduler._rotation == rotation, "Idle frames neither repeat requests nor rerun the entire scheduling pass")
	gateway.complete()
	# Now exercise the actual engine process callbacks, not a direct retry call.
	runtime.set_process(true)
	world.set_process(true)
	session.season.advance_game_minutes(60)
	await settle()
	for frame in 3: await process_frame
	check(gateway.requests.size() == 2, "The next interval dispatches through normal frame processing")
	gateway.complete()
	session.season.advance_game_minutes(60)
	await settle()
	for frame in 3: await process_frame
	check(gateway.requests.size() == 2 and runtime.scheduler.budget_calls == 2, "Recovery still respects the shared daily request limit")
	# Leave a tick pending, then disable the service before settlement finishes.
	runtime.scheduler.max_daily_requests = 16
	runtime.set_process(false)
	world.set_process(false)
	session.season.advance_game_minutes(60)
	runtime.service_enabled = false
	await settle()
	runtime._process(0.0)
	check(gateway.requests.size() == 2, "Disabling the service cancels pending automatic dispatch")
	runtime.service_enabled = true
	runtime._process(0.0)
	check(gateway.requests.size() == 2, "Re-enabling the service does not resurrect the cancelled tick")
	session.season.advance_game_minutes(1)
	await settle()
	runtime._process(0.0)
	check(gateway.requests.size() == 3, "A fresh game-time tick resumes scheduling after re-enable")
	gateway.complete()
	session.season.advance_game_minutes(119)
	session.season.advance_game_minutes(1)
	session.season.advance_game_minutes(1)
	await settle()
	runtime._process(0.0)
	check(gateway.requests.size() == 4, "Several pending time signals coalesce into one current decision")
	if gateway.requests.size() == 4:
		check(int(gateway.requests[-1].game_minute) == world.minute() and gateway.requests[-1].trigger == "catch_up", "Coalesced scheduling uses the latest time instead of replaying stale ticks")
	gateway.complete()
	runtime.service_enabled = false
	print("3D Agent scheduling: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
