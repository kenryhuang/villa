extends RefCounted

const AgentProtocolScript = preload("res://scripts/ai_agent/agent_protocol.gd")


func validate(intent: Variant, registry: Variant, current_revision: int) -> Dictionary:
	if not intent is Dictionary:
		return {"ok": false, "error": "invalid_envelope"}
	var agent_id := str((intent as Dictionary).get("agent_id", ""))
	if registry == null or not registry.has_method("get_agent"):
		return {"ok": false, "error": "missing_registry"}
	var agent: Dictionary = registry.call("get_agent", agent_id)
	if agent.is_empty():
		return {"ok": false, "error": "unknown_agent"}
	var parsed := AgentProtocolScript.parse_action_intent(intent, agent.get("tools", []))
	if not parsed.ok:
		return parsed
	if int(parsed.value.expected_revision) != current_revision:
		return {"ok": false, "error": "stale_world_revision"}
	return parsed
