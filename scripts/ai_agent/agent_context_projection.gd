class_name AgentContextProjection
extends RefCounted

const GLOBAL_CONTEXT_EVENT_LIMIT := 24
const OWN_EVENT_DETAIL_LIMIT := 15

var _projector: Variant
var _inbox: Variant


func configure(projector: Variant, inbox: Variant) -> bool:
	if (
		projector == null
		or inbox == null
		or not projector.has_method("public_world_state")
		or not projector.has_method("known_actors")
		or not inbox.has_method("freeze_delta")
	):
		return false
	_projector = projector
	_inbox = inbox
	return true


func build(agent_id: String, request_id: String) -> Dictionary:
	if _projector == null or _inbox == null:
		return {}
	var public_world_state: Dictionary = _projector.call("public_world_state")
	public_world_state.erase("market_summary")
	var frozen_delta: Array[Dictionary] = _inbox.call("freeze_delta", agent_id, request_id)
	return {
		"public_world_state": public_world_state,
		"global_public_events": _projector.call("global_public_events", GLOBAL_CONTEXT_EVENT_LIMIT),
		"known_actors": _projector.call("known_actors", agent_id),
		"own_event_delta": _compact_event_delta(agent_id, frozen_delta),
		"market_view": _projector.call("market_view"),
	}


func acknowledge(agent_id: String, request_id: String) -> bool:
	return _inbox != null and bool(_inbox.call("acknowledge_delta", agent_id, request_id))


func release(agent_id: String, request_id: String) -> bool:
	return _inbox != null and bool(_inbox.call("release_delta", agent_id, request_id))


func _compact_event_delta(agent_id: String, events: Array[Dictionary]) -> Array[Dictionary]:
	if events.size() <= OWN_EVENT_DETAIL_LIMIT + 1:
		return events.duplicate(true)
	var omitted_count := events.size() - OWN_EVENT_DETAIL_LIMIT
	var omitted: Array[Dictionary] = []
	omitted.assign(events.slice(0, omitted_count))
	var latest_game_minute := 0
	var event_type_counts := {}
	var aggregate_type_counts := {}
	for event in omitted:
		latest_game_minute = maxi(latest_game_minute, int(event.get("game_minute", 0)))
		_increment_count(event_type_counts, str(event.get("event_type", "unknown")))
		_increment_count(aggregate_type_counts, str(event.get("aggregate_type", "unknown")))
	var first_sequence := int(omitted[0].get("global_sequence", 0))
	var last_sequence := int(omitted[-1].get("global_sequence", first_sequence))
	var result: Array[Dictionary] = [{
		"event_id": "event-delta-summary:%s:%d:%d" % [agent_id, first_sequence, last_sequence],
		"event_type": "EventDeltaSummary",
		"aggregate_type": "event_delta",
		"aggregate_id": agent_id,
		"actor_id": "system",
		"game_minute": latest_game_minute,
		"global_sequence": last_sequence,
		"command_id": "",
		"correlation_id": agent_id,
		"causation_event_id": "",
		"visibility": {"scope": "private", "actor_ids": [agent_id]},
		"payload": {
			"schema_version": 1,
			"omitted_count": omitted_count,
			"first_global_sequence": first_sequence,
			"last_global_sequence": last_sequence,
			"latest_game_minute": latest_game_minute,
			"event_type_counts": _sorted_counts(event_type_counts, "event_type"),
			"aggregate_type_counts": _sorted_counts(aggregate_type_counts, "aggregate_type"),
		},
	}]
	for index in range(omitted_count, events.size()):
		result.append(events[index].duplicate(true))
	return result


func _increment_count(counts: Dictionary, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1


func _sorted_counts(counts: Dictionary, field: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var keys := counts.keys()
	keys.sort()
	for key_value in keys:
		result.append({field: str(key_value), "count": int(counts[key_value])})
	return result
