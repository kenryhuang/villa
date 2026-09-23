extends RefCounted

# FIFO messages. Clock ticks and ambient state updates coalesce by actor/source;
# directed system/dialogue obligations remain separate messages.
var messages: Array = []
var seen: Array = []
var sequence := 0

func enqueue(actor: String, kind: String, minute: int, source: String, event_id := "", priority := 2, trigger := "event") -> bool:
	sequence += 1
	var id := event_id if not event_id.is_empty() else "event-%d-%d" % [Time.get_ticks_usec(),sequence]
	if id in seen or messages.any(func(e): return e.event_id == id): return true
	seen.append(id)
	if seen.size() > 4096: seen.pop_front()
	var message := {"event_id":id,"agent_id":actor,"kind":kind,"game_minute":minute,"source":source,"priority":priority,"trigger":trigger}
	if kind == "clock" or source.begins_with("ambient:"):
		for index in messages.size():
			if messages[index].agent_id == actor and messages[index].kind == kind and messages[index].source == source:
				messages[index] = message
				return true
	messages.append(message)
	return true

func remove(event_id: String) -> void:
	messages = messages.filter(func(e): return e.event_id != event_id)

func requeue(message: Dictionary) -> void:
	if not messages.any(func(e): return e.event_id == message.event_id): messages.push_front(message.duplicate(true))

func has_actor(actor: String) -> bool:
	return messages.any(func(e): return e.agent_id == actor)

func snapshot(active: Dictionary = {}) -> Dictionary:
	var waiting := messages.duplicate(true)
	for event in active.values():
		if not waiting.any(func(e): return e.event_id == event.event_id): waiting.push_front(event.duplicate(true))
	return {"version":1,"messages":waiting,"seen":seen.duplicate(),"sequence":sequence}

func restore(value: Dictionary) -> void:
	messages = value.get("messages", []).duplicate(true)
	seen = value.get("seen", []).duplicate()
	sequence = int(value.get("sequence", 0))

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.get("version") != 1 or not value.get("messages") is Array or not value.get("seen") is Array or not value.get("sequence") is int: return false
	if value.sequence < 0 or value.seen.size() > 4096 or not value.seen.all(func(id): return id is String): return false
	if not value.get("last_dispatched", {}) is Dictionary: return false
	for minute in value.get("last_dispatched", {}).values():
		if not minute is int or minute < 0: return false
	var ids := {}
	for e in value.messages:
		if not e is Dictionary or e.size() != 7 or not e.get("event_id") is String or e.event_id.is_empty() or e.event_id.length() > 256 or ids.has(e.event_id): return false
		if not e.get("agent_id") is String or not e.get("source") is String or not e.get("priority") is int or not e.get("game_minute") is int or e.game_minute < 0: return false
		if e.agent_id.is_empty() or e.source.is_empty() or e.priority < 0: return false
		if e.get("kind") not in ["system","dialogue","clock"] or e.get("trigger") not in ["event","schedule","catch_up"]: return false
		ids[e.event_id] = true
	return true
