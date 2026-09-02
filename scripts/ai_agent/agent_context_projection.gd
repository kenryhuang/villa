class_name AgentContextProjection
extends RefCounted

const GLOBAL_CONTEXT_EVENT_LIMIT := 24

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
	return {
		"public_world_state": _projector.call("public_world_state"),
		"global_public_events": _projector.call("global_public_events", GLOBAL_CONTEXT_EVENT_LIMIT),
		"known_actors": _projector.call("known_actors", agent_id),
		"own_event_delta": _inbox.call("freeze_delta", agent_id, request_id),
		"market_view": _projector.call("market_view"),
	}


func acknowledge(agent_id: String, request_id: String) -> bool:
	return _inbox != null and bool(_inbox.call("acknowledge_delta", agent_id, request_id))


func release(agent_id: String, request_id: String) -> bool:
	return _inbox != null and bool(_inbox.call("release_delta", agent_id, request_id))
