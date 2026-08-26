extends RefCounted

const PROTOCOL_VERSION := 2


static func parse_action_intent(value: Variant, allowed_tools: Array) -> Dictionary:
	if not value is Dictionary:
		return _failure("invalid_envelope")
	var data := value as Dictionary
	if data.get("protocol_version") != PROTOCOL_VERSION:
		return _failure("invalid_protocol_version")
	for field in ["decision_id", "request_id", "agent_id"]:
		if typeof(data.get(field)) != TYPE_STRING or str(data.get(field)).strip_edges().is_empty():
			return _failure("invalid_" + field)
	if not _is_non_negative_integer(data.get("expected_revision")):
		return _failure("invalid_expected_revision")
	if not data.get("actions") is Array or data.actions.size() > 3:
		return _failure("invalid_actions")
	var action_ids := {}
	var idempotency_keys := {}
	var actions: Array[Dictionary] = []
	for action_value in data.actions:
		if not action_value is Dictionary:
			return _failure("invalid_action")
		var action := action_value as Dictionary
		for field in ["action_id", "idempotency_key", "tool_name"]:
			if typeof(action.get(field)) != TYPE_STRING or str(action.get(field)).strip_edges().is_empty():
				return _failure("invalid_" + field)
		var action_id := str(action.action_id)
		var idempotency_key := str(action.idempotency_key)
		if action_ids.has(action_id):
			return _failure("duplicate_action_id")
		if idempotency_keys.has(idempotency_key):
			return _failure("duplicate_idempotency_key")
		action_ids[action_id] = true
		idempotency_keys[idempotency_key] = true
		if action.get("tool_version") != 1:
			return _failure("invalid_tool_version")
		if not allowed_tools.has(str(action.tool_name)):
			return _failure("unauthorized_tool")
		if not action.get("arguments") is Dictionary:
			return _failure("invalid_arguments")
		actions.append(action.duplicate(true))
	if actions.size() > 1:
		for action in actions:
			if str(action.tool_name) == "wait":
				return _failure("wait_must_be_exclusive")
	if typeof(data.get("decision_summary")) != TYPE_STRING or str(data.decision_summary).length() > 500:
		return _failure("invalid_decision_summary")
	if data.has("speech") and (typeof(data.speech) != TYPE_STRING or str(data.speech).length() > 500):
		return _failure("invalid_speech")
	var normalized := data.duplicate(true)
	normalized.actions = actions
	return {"ok": true, "value": normalized}


static func make_decision_request(
	request_id: String,
	session_id: String,
	session_epoch: int,
	agent_id: String,
	trigger: String,
	game_minute: int,
	world_revision: int,
	snapshot: Dictionary,
	event_delta: Array,
	dialogue_input: String = ""
) -> Dictionary:
	var request := {
		"protocol_version": PROTOCOL_VERSION,
		"request_id": request_id,
		"session_id": session_id,
		"session_epoch": session_epoch,
		"agent_id": agent_id,
		"trigger": trigger,
		"game_minute": game_minute,
		"world_revision": world_revision,
		"snapshot": snapshot.duplicate(true),
		"event_delta": event_delta.duplicate(true),
	}
	if not dialogue_input.is_empty():
		request["dialogue_input"] = dialogue_input
	return request


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}


static func _is_non_negative_integer(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and value == floor(value))) and int(value) >= 0
