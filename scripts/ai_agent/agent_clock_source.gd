extends RefCounted

# The clock publishes messages; it never executes an NPC decision directly.
func publish(engine: RefCounted, minute: int) -> void:
	for id in engine._registry.call("get_agent_ids"):
		var actor := str(id)
		if not engine.can_enqueue_event(actor, "clock", "periodic_clock"): continue
		var hours: int = engine.get_decision_interval_hours(actor)
		if hours <= 0 or engine.is_in_flight(actor) or engine.event_queue.has_actor(actor): continue
		var elapsed: int = minute - int(engine._last_dispatched.get(actor, 0))
		if elapsed < hours * 60: continue
		engine.event_queue.enqueue(actor,"clock",minute,"periodic_clock","clock:%s:%d" % [actor,minute],1,"catch_up" if elapsed > hours*60 else "schedule")
