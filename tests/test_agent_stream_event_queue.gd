extends RefCounted

const AgentStreamEventQueueScript = preload("res://scripts/ai_agent/agent_stream_event_queue.gd")


func run(assertions: TestAssert) -> void:
	var queue = AgentStreamEventQueueScript.new()
	var events: Array[Dictionary] = []
	for index in range(40):
		events.append({"event": "content.delta", "data": {"sequence": index + 1}})
	assertions.truthy(queue.push_many(events), "stream event queue accepts dictionary events")
	assertions.equal(queue.size(), 40, "stream event queue reports pending count")
	assertions.equal(queue.drain(0), [], "non-positive event budget drains nothing")
	var first: Array[Dictionary] = queue.drain(32)
	assertions.equal(first.size(), 32, "stream event queue respects per-frame event budget")
	assertions.equal(first[0].data.sequence, 1, "stream event queue preserves first event")
	assertions.equal(first[-1].data.sequence, 32, "stream event queue preserves batch order")
	assertions.equal(queue.size(), 8, "stream event queue retains overflow for next frame")
	var second: Array[Dictionary] = queue.drain(32)
	assertions.equal(second.map(func(event): return event.data.sequence), [33, 34, 35, 36, 37, 38, 39, 40], "second frame receives remaining events in order")
	assertions.truthy(queue.is_empty(), "stream event queue becomes empty after drain")
	assertions.truthy(not queue.push_many([{"event": "valid"}, "invalid"]), "stream event queue rejects mixed invalid input atomically")
	assertions.truthy(queue.is_empty(), "rejected batch changes no queue state")
