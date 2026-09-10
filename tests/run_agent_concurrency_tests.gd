extends SceneTree

const Scheduler = preload("res://scripts/ai_agent/agent_scheduler.gd")
var checks := 0
var failures: Array[String] = []
var received: Array = []

class Registry extends RefCounted:
	func get_agent_ids() -> Array: return ["a", "b", "c", "d", "e", "f"]
	func is_agent_managed(id: String) -> bool: return id in get_agent_ids()
	func get_agent(_id: String) -> Dictionary: return {"decision_interval_hours": [1, 1]}

class Gateway extends RefCounted:
	var callbacks := {}
	var sent := []
	var cancelled := []
	func request_decision(actor: String, request: Dictionary, done: Callable, _event: Callable) -> bool:
		if callbacks.has(actor): return false
		callbacks[actor] = done
		sent.append(request.duplicate(true))
		return true
	func complete(actor: String, ok := true) -> void:
		var callback: Callable = callbacks[actor]
		callbacks.erase(actor)
		callback.call(ok, {"actor": actor}, "" if ok else "provider_timeout")
	func cancel_agent(actor: String, reason: String) -> bool:
		cancelled.append(actor)
		var callback: Callable = callbacks[actor]
		callbacks.erase(actor)
		callback.call(false, {}, reason)
		return true

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Concurrency tests timed out"); quit(1))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func make_scheduler(gateway: Gateway):
	var scheduler := Scheduler.new()
	scheduler.configure(Registry.new(), gateway,
		func(actor, trigger, minute, dialogue): return {"request_id": "%s-%d" % [actor, gateway.sent.size()], "trigger": trigger, "minute": minute, "dialogue": dialogue},
		func(actor, _response): received.append(actor))
	scheduler.max_concurrent_requests = 3
	scheduler.max_daily_requests = 16
	for actor in Registry.new().get_agent_ids(): scheduler.set_decision_interval_hours(actor, 0)
	return scheduler

func run() -> void:
	var gateway := Gateway.new()
	var scheduler = make_scheduler(gateway)
	for actor in ["a", "b", "c"]:
		check(scheduler.notify_event(actor, 2, 60), "Three background slots accept " + actor)
	check(not scheduler.notify_event("d", 2, 60) and scheduler._pending.has("d"), "Fourth background request waits")
	check(scheduler.trigger_dialogue("d", "hello", 60), "Dialogue bypasses full background pool")
	check(scheduler.background_in_flight_count() == 3 and scheduler.dialogue_in_flight_count() == 1 and scheduler._in_flight.size() == 4, "Three background requests and one dialogue run together")
	check(scheduler.budget_calls == 3 and scheduler.dialogue_budget_calls == 1, "Dialogue has a separate daily counter")
	check(not scheduler.trigger_dialogue("e", "hello", 60), "A second simultaneous dialogue is bounded")
	check(not scheduler.trigger_dialogue("b", "hello", 60) and gateway.cancelled.is_empty(), "Busy dialogue slot does not cancel another actor's ongoing work")
	var stale: Callable = gateway.callbacks.d
	check(scheduler.trigger_dialogue("d", "replacement", 60), "Same actor can replace its ongoing dialogue")
	stale.call(true, {}, "")
	check(scheduler.is_in_flight("d") and received.is_empty(), "Stale completion cannot free replacement slot or commit commands")
	gateway.complete("d")
	check(scheduler.dialogue_in_flight_count() == 0 and scheduler._pending.has("d"), "Dialogue completion frees only its own slot and preserves pending background event")
	gateway.complete("a")
	scheduler.advance_to(61)
	check(scheduler.is_in_flight("d") and scheduler.background_in_flight_count() == 3, "Pending event starts when a background slot becomes available")
	check(scheduler.trigger_dialogue("b", "interrupt", 61), "Dialogue can replace that actor's background request")
	check(scheduler.background_in_flight_count() == 2 and scheduler.dialogue_in_flight_count() == 1, "Replacing background releases its slot without double counting")
	gateway.complete("b", false)
	check(scheduler.dialogue_in_flight_count() == 0 and not scheduler.is_in_flight("b"), "Dialogue failure releases its slot")
	for actor in ["c", "d"]: gateway.complete(actor)
	scheduler.restore_budget({"day": 0, "calls": 16, "dialogue_calls": 3})
	check(not scheduler.notify_event("a", 2, 62), "Autonomous daily cap still applies")
	check(scheduler.trigger_dialogue("e", "still available", 62), "Exhausted autonomous quota does not block dialogue")
	gateway.complete("e")
	check(scheduler.budget_calls == 16 and scheduler.dialogue_budget_calls == 4, "Dialogue does not consume additional autonomous allowance")
	var saved: Dictionary = scheduler.budget_state()
	var restored = make_scheduler(Gateway.new())
	restored.restore_budget(saved)
	check(restored.budget_state() == saved, "Both daily counters round-trip")
	restored.advance_to(0)
	check(restored.budget_state() == saved, "Clock rewind does not reset either counter")
	restored.max_daily_dialogue_requests = 4
	check(not restored.trigger_dialogue("a", "limited", 62), "Optional dialogue budget is independent")
	restored.advance_to(1080)
	check(restored.budget_calls == 0 and restored.dialogue_budget_calls == 0, "Next game day resets both counters")
	restored.restore_budget({"day": 2, "calls": 11})
	check(restored.budget_calls == 11 and restored.dialogue_budget_calls == 0, "Old save conservatively retains prior usage and initializes dialogue count")
	# A conversation must not postpone an otherwise due autonomous decision.
	var timing_gateway := Gateway.new()
	var timing = make_scheduler(timing_gateway)
	timing.set_decision_interval_hours("a", 1)
	check(timing.trigger_dialogue("a", "hello", 50), "Conversation before scheduled turn starts")
	timing_gateway.complete("a")
	check(timing.advance_to(60) == 1, "Dialogue does not reset the background planning interval")

	# Use the actual expanded scene and real save validator without player save IO.
	var farm: Node3D = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var session: Farm3DSession = farm.get_node("FarmSession")
	session.season.set_process(false)
	var world: Node = session.living_world
	check(session.agent_runtime.scheduler.max_concurrent_requests == 3 and session.agent_runtime.scheduler.max_concurrent_dialogue_requests == 1, "Formal expanded game configures 3 background and 1 dialogue")
	check(world.public_plans.scheduler.max_concurrent_requests == 1, "Public coordinator keeps its independent slot")
	var state: Dictionary = world.to_dict()
	check(world.validate(state), "New planning counter format passes real world validation")
	var old := state.duplicate(true)
	for key in ["private", "public"]: old.planning[key].erase("dialogue_calls")
	check(world.validate(old), "Existing version 7 save with old counters remains valid")
	var invalid := state.duplicate(true)
	invalid.planning.private.dialogue_calls = -1
	check(not world.validate(invalid), "Corrupt dialogue counter is rejected")
	invalid = state.duplicate(true)
	invalid.planning.private.erase("dialogue_calls")
	invalid.planning.private.unexpected_counter = 1
	check(not world.validate(invalid), "Unknown counter is not accepted as the optional field")
	check("对话" in world.debug_text(), "Debug summary reports conversations separately")
	farm.queue_free()
	await process_frame
	print("Agent concurrency: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
