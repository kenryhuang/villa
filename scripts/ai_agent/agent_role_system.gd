class_name AgentRoleSystem
extends RefCounted

const DEFAULT_RULES_PATH := "res://data/agents/role_transitions.json"
const VERSION := 1
const GENERAL_TOOLS := [
	"send_message", "propose_trade", "counter_trade", "accept_trade",
	"reject_trade", "cancel_trade", "propose_cooperation", "counter_cooperation",
	"accept_cooperation", "reject_cooperation", "commit_contribution",
	"cancel_cooperation", "speak", "wait", "propose_role_change",
]
const GENERAL_READ_TOOLS := [
	"inspect_market_item", "compare_market_items", "inspect_known_actor",
	"inspect_relationship", "inspect_trade_offer", "inspect_agreement",
	"inspect_role_option", "inspect_self_resources",
]

var _registry: Variant
var _economy: Variant
var _store: Variant
var _projector: Variant
var _buildings: Variant
var _knowledge: Variant
var _rules: Dictionary = {}
var _states: Dictionary = {}


func configure(
	registry: Variant,
	economy: Variant,
	store: Variant,
	projector: Variant,
	buildings: Variant,
	knowledge: Variant,
	rules_path: String = DEFAULT_RULES_PATH
) -> bool:
	if registry == null or economy == null or store == null or projector == null or buildings == null or knowledge == null:
		return false
	var rules_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(rules_path))
	var normalized_rules: Variant = _normalize_rules(rules_value, registry)
	if normalized_rules == null:
		return false
	_registry = registry
	_economy = economy
	_store = store
	_projector = projector
	_buildings = buildings
	_knowledge = knowledge
	_rules = normalized_rules
	_states.clear()
	for agent_id_value in _registry.call("get_agent_ids"):
		var agent_id := str(agent_id_value)
		var agent: Dictionary = _registry.call("get_agent", agent_id)
		_states[agent_id] = {
			"agent_id": agent_id,
			"active_role_id": str(agent.role_id),
			"last_changed_minute": -1,
			"history": [str(agent.role_id)],
		}
	return true


func get_active_role(agent_id: String) -> String:
	return str((_states.get(agent_id, {}) as Dictionary).get("active_role_id", ""))


func get_capabilities(agent_id: String) -> Dictionary:
	var role_id := get_active_role(agent_id)
	var role: Dictionary = _registry.call("get_role", role_id) if _registry != null else {}
	if role.is_empty():
		return {}
	var tools: Array = (role.get("tools", []) as Array).duplicate()
	for tool_name in GENERAL_TOOLS:
		if not tool_name in tools:
			tools.append(tool_name)
	var read_tools: Array = (role.get("read_tools", []) as Array).duplicate()
	for tool_name in GENERAL_READ_TOOLS:
		if not tool_name in read_tools:
			read_tools.append(tool_name)
	return {
		"role_id": role_id,
		"goals": (role.get("goals", []) as Array).duplicate(),
		"tools": tools,
		"read_tools": read_tools,
		"decision_interval_hours": (role.get("decision_interval_hours", [1, 1]) as Array).duplicate(),
	}


func propose_change(
	agent_id: String,
	target_role_id: String,
	motivation: String,
	game_minute: int,
	idempotency_key: String
) -> Dictionary:
	if not _states.has(agent_id) or not _rules.has(target_role_id) or motivation.strip_edges().is_empty() or game_minute < 0 or idempotency_key.strip_edges().is_empty():
		return {"ok": false, "error": "invalid_role_change"}
	var cached: Dictionary = _store.call("get_idempotent_result", idempotency_key)
	if not cached.is_empty():
		return _result_from_committed(cached.get("events", []), target_role_id)
	if get_active_role(agent_id) == target_role_id:
		return _commit_rejection(agent_id, target_role_id, motivation, game_minute, idempotency_key, "already_in_role")
	var state: Dictionary = _states[agent_id]
	var rule: Dictionary = _rules[target_role_id]
	var last_changed := int(state.last_changed_minute)
	if last_changed >= 0 and game_minute - last_changed < int(rule.cooldown_hours) * 60:
		return _commit_rejection(agent_id, target_role_id, motivation, game_minute, idempotency_key, "role_change_cooldown")
	var eligibility_error := _eligibility_error(agent_id, rule)
	if not eligibility_error.is_empty():
		return _commit_rejection(agent_id, target_role_id, motivation, game_minute, idempotency_key, eligibility_error)

	var economy_state = _economy.call("get_npc_state", agent_id)
	if economy_state == null:
		return {"ok": false, "error": "missing_economy_state"}
	var cost := int(rule.cost_gold)
	var gold_before := int(economy_state.gold)
	economy_state.gold = gold_before - cost
	var events := _success_events(agent_id, target_role_id, motivation, game_minute, cost)
	var committed: Dictionary = _store.call("append_projected_batch", events, idempotency_key, _projector)
	var committed_events: Array[Dictionary] = []
	committed_events.assign(committed.get("events", []))
	if not bool(committed.get("ok", false)):
		economy_state.gold = gold_before
		return {"ok": false, "error": "role_event_commit_failed"}
	if not bool(_registry.call("set_active_role", agent_id, target_role_id)):
		economy_state.gold = gold_before
		return {"ok": false, "error": "role_projection_failed"}
	state.active_role_id = target_role_id
	state.last_changed_minute = game_minute
	(state.history as Array).append(target_role_id)
	_states[agent_id] = state
	return {"ok": true, "approved": true, "role_id": target_role_id, "cost_gold": cost, "events": committed.events}


func to_dict() -> Dictionary:
	var records: Array[Dictionary] = []
	var agent_ids := _states.keys()
	agent_ids.sort()
	for agent_id in agent_ids:
		records.append((_states[agent_id] as Dictionary).duplicate(true))
	return {"version": VERSION, "roles": records}


func validate_dict(value: Dictionary) -> bool:
	return _normalize_state(value) != null


func from_dict(value: Dictionary) -> bool:
	var normalized: Variant = _normalize_state(value)
	if normalized == null:
		return false
	for agent_id in normalized:
		if not bool(_registry.call("set_active_role", agent_id, str((normalized[agent_id] as Dictionary).active_role_id))):
			return false
	_states = normalized
	return true


func _eligibility_error(agent_id: String, rule: Dictionary) -> String:
	var economy_state = _economy.call("get_npc_state", agent_id)
	if economy_state == null:
		return "missing_economy_state"
	if int(economy_state.gold) < int(rule.minimum_gold) or int(economy_state.gold) < int(rule.cost_gold):
		return "insufficient_role_gold"
	for item_id in rule.required_items:
		if int(economy_state.inventory.get(item_id, 0)) < int(rule.required_items[item_id]):
			return "missing_role_item"
	var event_counts: Dictionary = {}
	for event_value in _store.call("get_events_after", 0):
		var event := event_value as Dictionary
		if str(event.actor_id) == agent_id:
			event_counts[str(event.event_type)] = int(event_counts.get(str(event.event_type), 0)) + 1
	for event_type in rule.minimum_event_counts:
		if int(event_counts.get(event_type, 0)) < int(rule.minimum_event_counts[event_type]):
			return "missing_event_experience"
	for discovery_id in rule.required_public_discoveries:
		if not bool(_knowledge.call("is_public", str(discovery_id))):
			return "missing_public_discovery"
	var actor: Dictionary = _projector.call("get_actor", agent_id)
	for region_id in rule.required_regions:
		if str(actor.get("region_id", "")) != str(region_id):
			return "missing_role_region"
	var owned_types: Array[String] = []
	for building_value in (_buildings.call("to_dict").buildings as Dictionary).values():
		var building := building_value as Dictionary
		if str(building.agent_id) == agent_id:
			owned_types.append(str(building.building_type))
	for building_type in rule.required_building_types:
		if not str(building_type) in owned_types:
			return "missing_role_building"
	return ""


func _commit_rejection(agent_id: String, target_role_id: String, motivation: String, game_minute: int, idempotency_key: String, error: String) -> Dictionary:
	var events: Array[Dictionary] = [
		_event("RoleChangeProposed", agent_id, target_role_id, game_minute, {"target_role_id": target_role_id, "motivation": motivation}, "private"),
		_event("RoleChangeRejected", agent_id, target_role_id, game_minute, {"target_role_id": target_role_id, "reason": error}, "private"),
	]
	var committed: Dictionary = _store.call("append_projected_batch", events, idempotency_key, _projector)
	var committed_events: Array[Dictionary] = []
	committed_events.assign(committed.get("events", []))
	if not bool(committed.get("ok", false)):
		return {"ok": false, "error": "role_event_commit_failed"}
	return {"ok": true, "approved": false, "error": error, "events": committed.events}


func _success_events(agent_id: String, target_role_id: String, motivation: String, game_minute: int, cost: int) -> Array[Dictionary]:
	return [
		_event("RoleChangeProposed", agent_id, target_role_id, game_minute, {"target_role_id": target_role_id, "motivation": motivation}, "private"),
		_event("RoleChangeApproved", agent_id, target_role_id, game_minute, {"target_role_id": target_role_id, "cost_gold": cost}, "private"),
		_event("RoleChanged", agent_id, target_role_id, game_minute, {"role_id": target_role_id, "cost_gold": cost}, "public"),
	]


func _event(event_type: String, agent_id: String, target_role_id: String, game_minute: int, payload: Dictionary, scope: String) -> Dictionary:
	return {
		"event_type": event_type,
		"aggregate_type": "agent_role",
		"aggregate_id": agent_id,
		"actor_id": agent_id,
		"game_minute": game_minute,
		"command_id": "role:%s:%s:%d" % [agent_id, target_role_id, game_minute],
		"correlation_id": "role:%s" % agent_id,
		"causation_event_id": "",
		"visibility": {"scope": scope, "actor_ids": [agent_id] if scope == "private" else []},
		"payload": payload,
	}


func _result_from_committed(events: Array, target_role_id: String) -> Dictionary:
	for event_value in events:
		var event := event_value as Dictionary
		if str(event.event_type) == "RoleChanged":
			return {"ok": true, "approved": true, "role_id": target_role_id, "events": events.duplicate(true)}
		if str(event.event_type) == "RoleChangeRejected":
			return {"ok": true, "approved": false, "error": str((event.payload as Dictionary).get("reason", "role_change_rejected")), "events": events.duplicate(true)}
	return {"ok": false, "error": "invalid_cached_role_result"}


func _normalize_rules(value: Variant, registry: Variant) -> Variant:
	if not value is Dictionary or value.get("version") != VERSION or not value.get("roles") is Array:
		return null
	var result: Dictionary = {}
	for rule_value in value.roles:
		if not rule_value is Dictionary:
			return null
		var rule := rule_value as Dictionary
		for field in ["role_id", "minimum_gold", "required_items", "required_building_types", "required_public_discoveries", "required_regions", "minimum_event_counts", "cost_gold", "cooldown_hours"]:
			if not rule.has(field):
				return null
		var role_id := str(rule.role_id)
		if role_id.is_empty() or (registry.call("get_role", role_id) as Dictionary).is_empty() or result.has(role_id):
			return null
		if not _is_nonnegative_integer(rule.minimum_gold) or not _is_nonnegative_integer(rule.cost_gold) or not _is_nonnegative_integer(rule.cooldown_hours):
			return null
		for collection_field in ["required_building_types", "required_public_discoveries", "required_regions"]:
			if not rule[collection_field] is Array:
				return null
		for map_field in ["required_items", "minimum_event_counts"]:
			if not rule[map_field] is Dictionary:
				return null
			for key in rule[map_field]:
				if typeof(key) != TYPE_STRING or str(key).is_empty() or not _is_positive_integer(rule[map_field][key]):
					return null
		result[role_id] = rule.duplicate(true)
	return result


func _normalize_state(value: Dictionary) -> Variant:
	if value.size() != 2 or value.get("version") != VERSION or not value.get("roles") is Array:
		return null
	var result: Dictionary = {}
	for record_value in value.roles:
		if not record_value is Dictionary:
			return null
		var record := record_value as Dictionary
		if record.size() != 4 or typeof(record.get("agent_id")) != TYPE_STRING or typeof(record.get("active_role_id")) != TYPE_STRING or not record.get("history") is Array:
			return null
		var agent_id := str(record.agent_id)
		var role_id := str(record.active_role_id)
		if not _states.has(agent_id) or result.has(agent_id) or (_registry.call("get_role", role_id) as Dictionary).is_empty():
			return null
		if not _is_integer(record.last_changed_minute) or int(record.last_changed_minute) < -1:
			return null
		var history: Array = record.history
		if history.is_empty() or history[-1] != role_id:
			return null
		for history_role in history:
			if typeof(history_role) != TYPE_STRING or (_registry.call("get_role", str(history_role)) as Dictionary).is_empty():
				return null
		var canonical := record.duplicate(true)
		canonical.last_changed_minute = int(record.last_changed_minute)
		result[agent_id] = canonical
	if result.size() != _states.size():
		return null
	return result


func _is_nonnegative_integer(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and floorf(float(value)) == float(value) and int(value) >= 0


func _is_positive_integer(value: Variant) -> bool:
	return _is_nonnegative_integer(value) and int(value) > 0


func _is_integer(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and floorf(float(value)) == float(value)
