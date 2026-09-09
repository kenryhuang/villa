extends RefCounted

const VERSION := 1

var _events_by_agent: Dictionary = {}
var _world_events_by_agent: Dictionary = {}
var _world_event_ids_by_agent: Dictionary = {}
var _consumed_sequence_by_agent: Dictionary = {}
var _frozen_by_agent: Dictionary = {}


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


func configure_agents(agent_ids: Array) -> bool:
	var seen: Dictionary = {}
	for agent_id_value in agent_ids:
		if typeof(agent_id_value) != TYPE_STRING or str(agent_id_value).strip_edges().is_empty():
			return false
		var agent_id := str(agent_id_value)
		if seen.has(agent_id):
			return false
		seen[agent_id] = true
	for agent_id_value in agent_ids:
		var agent_id := str(agent_id_value)
		if not _world_events_by_agent.has(agent_id):
			_world_events_by_agent[agent_id] = []
			_world_event_ids_by_agent[agent_id] = {}
		if not _consumed_sequence_by_agent.has(agent_id):
			_consumed_sequence_by_agent[agent_id] = 0
		if not _frozen_by_agent.has(agent_id):
			_frozen_by_agent[agent_id] = {}
	return true


func push_world_event(agent_id: String, event: Dictionary) -> bool:
	if (
		not _world_events_by_agent.has(agent_id)
		or typeof(event.get("event_id")) != TYPE_STRING
		or str(event.event_id).is_empty()
		or not _is_positive_integer(event.get("global_sequence"))
	):
		return false
	if int(event.global_sequence) <= int(_consumed_sequence_by_agent.get(agent_id, 0)): return true
	var events: Array = _world_events_by_agent[agent_id]
	var ids: Dictionary = _world_event_ids_by_agent[agent_id]
	if ids.has(event.event_id): return true
	ids[event.event_id] = true
	var ordered := events.is_empty() or int(events[-1].global_sequence) < int(event.global_sequence)
	events.append(event.duplicate(true))
	if not ordered:
		events.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left.global_sequence) < int(right.global_sequence))
	return true


func freeze_delta(agent_id: String, request_id: String) -> Array[Dictionary]:
	if not _world_events_by_agent.has(agent_id) or request_id.strip_edges().is_empty():
		return []
	var frozen: Dictionary = _frozen_by_agent[agent_id]
	if frozen.has(request_id):
		return (frozen[request_id] as Array).duplicate(true)
	var result: Array[Dictionary] = []
	var consumed := int(_consumed_sequence_by_agent.get(agent_id, 0))
	for event_value in _world_events_by_agent[agent_id] as Array:
		var event := event_value as Dictionary
		if int(event.global_sequence) > consumed:
			result.append(event.duplicate(true))
	frozen[request_id] = result.duplicate(true)
	return result


func acknowledge_delta(agent_id: String, request_id: String) -> bool:
	if not _frozen_by_agent.has(agent_id):
		return false
	var frozen: Dictionary = _frozen_by_agent[agent_id]
	if not frozen.has(request_id):
		return false
	var events: Array = frozen[request_id]
	var consumed := int(_consumed_sequence_by_agent.get(agent_id, 0))
	for event_value in events:
		consumed = maxi(consumed, int((event_value as Dictionary).global_sequence))
	_consumed_sequence_by_agent[agent_id] = consumed
	frozen.erase(request_id)
	var retained: Array[Dictionary] = []
	for event_value in _world_events_by_agent[agent_id] as Array:
		if int((event_value as Dictionary).global_sequence) > consumed:
			retained.append((event_value as Dictionary).duplicate(true))
	_world_events_by_agent[agent_id] = retained
	_world_event_ids_by_agent[agent_id] = {}
	for event in retained: _world_event_ids_by_agent[agent_id][event.event_id] = true
	return true


func release_delta(agent_id: String, request_id: String) -> bool:
	if not _frozen_by_agent.has(agent_id):
		return false
	var frozen: Dictionary = _frozen_by_agent[agent_id]
	if not frozen.has(request_id):
		return false
	frozen.erase(request_id)
	return true


func get_consumed_sequence(agent_id: String) -> int:
	return int(_consumed_sequence_by_agent.get(agent_id, 0))


func to_dict() -> Dictionary:
	var cursors: Array[Dictionary] = []
	var agent_ids := _consumed_sequence_by_agent.keys()
	agent_ids.sort()
	for agent_id_value in agent_ids:
		cursors.append({
			"agent_id": str(agent_id_value),
			"consumed_sequence": int(_consumed_sequence_by_agent[agent_id_value]),
		})
	return {"version": VERSION, "consumption_cursors": cursors}


func validate_dict(value: Dictionary, maximum_sequence: int = 9223372036854775807) -> bool:
	return _normalize_state(value, maximum_sequence) != null


func from_dict(value: Dictionary, maximum_sequence: int = 9223372036854775807) -> bool:
	var normalized: Variant = _normalize_state(value, maximum_sequence)
	if normalized == null:
		return false
	_consumed_sequence_by_agent = normalized
	_frozen_by_agent.clear()
	for agent_id in _world_events_by_agent:
		_frozen_by_agent[agent_id] = {}
		var retained: Array[Dictionary] = []
		var consumed := int(_consumed_sequence_by_agent.get(agent_id, 0))
		for event_value in _world_events_by_agent[agent_id] as Array:
			if int((event_value as Dictionary).global_sequence) > consumed:
				retained.append((event_value as Dictionary).duplicate(true))
		_world_events_by_agent[agent_id] = retained
		_world_event_ids_by_agent[agent_id] = {}
		for event in retained: _world_event_ids_by_agent[agent_id][event.event_id] = true
	return true


func _normalize_state(value: Dictionary, maximum_sequence: int) -> Variant:
	if value.size() != 2 or value.get("version") != VERSION or not value.get("consumption_cursors") is Array or maximum_sequence < 0:
		return null
	var normalized: Dictionary = {}
	var last_agent_id := ""
	for record_value in value.consumption_cursors:
		if not record_value is Dictionary:
			return null
		var record := record_value as Dictionary
		if record.size() != 2 or typeof(record.get("agent_id")) != TYPE_STRING or not _is_nonnegative_integer(record.get("consumed_sequence")):
			return null
		var agent_id := str(record.agent_id)
		if agent_id.is_empty() or agent_id <= last_agent_id or not _world_events_by_agent.has(agent_id) or int(record.consumed_sequence) > maximum_sequence:
			return null
		last_agent_id = agent_id
		normalized[agent_id] = int(record.consumed_sequence)
	if normalized.size() != _world_events_by_agent.size():
		return null
	return normalized


func _is_positive_integer(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
		and int(value) > 0
	)


func _is_nonnegative_integer(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
		and int(value) >= 0
	)
