extends RefCounted

var _events_by_agent: Dictionary = {}


func push_event(
	agent_id: String,
	kind: String,
	entity_id: String,
	payload: Dictionary,
	game_minute: int,
	priority: int = 0
) -> bool:
	if agent_id.is_empty() or kind.is_empty() or entity_id.is_empty() or game_minute < 0:
		return false
	if not _events_by_agent.has(agent_id):
		_events_by_agent[agent_id] = {}
	var events: Dictionary = _events_by_agent[agent_id]
	var key := kind + ":" + entity_id
	var previous: Dictionary = events.get(key, {})
	events[key] = {
		"kind": kind,
		"entity_id": entity_id,
		"payload": payload.duplicate(true),
		"game_minute": game_minute,
		"priority": maxi(priority, int(previous.get("priority", priority))),
		"merged_count": int(previous.get("merged_count", 0)) + 1,
	}
	return true


func drain(agent_id: String) -> Array[Dictionary]:
	if not _events_by_agent.has(agent_id):
		return []
	var events: Dictionary = _events_by_agent[agent_id]
	var result: Array[Dictionary] = []
	for value in events.values():
		result.append((value as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.priority) != int(b.priority):
			return int(a.priority) > int(b.priority)
		if int(a.game_minute) != int(b.game_minute):
			return int(a.game_minute) > int(b.game_minute)
		return str(a.entity_id) < str(b.entity_id)
	)
	_events_by_agent.erase(agent_id)
	return result


func peek(agent_id: String) -> Array[Dictionary]:
	if not _events_by_agent.has(agent_id):
		return []
	var result: Array[Dictionary] = []
	for value in (_events_by_agent[agent_id] as Dictionary).values():
		result.append((value as Dictionary).duplicate(true))
	return result
