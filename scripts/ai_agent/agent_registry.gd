extends RefCounted

const ROLES_PATH := "res://data/agents/roles.json"
const PROFILES_PATH := "res://data/agents/profiles.json"

var _agents: Dictionary = {}
var _roles: Dictionary = {}


func load_defaults() -> bool:
	var roles_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROLES_PATH))
	var profiles_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILES_PATH))
	if not roles_value is Array or not profiles_value is Array:
		return false
	var roles: Dictionary = {}
	for role_value in roles_value:
		if not role_value is Dictionary:
			return false
		var role := role_value as Dictionary
		var role_id := str(role.get("role_id", ""))
		if role_id.is_empty() or roles.has(role_id) or not role.get("tools") is Array:
			return false
		roles[role_id] = role.duplicate(true)
	var candidates: Dictionary = {}
	for profile_value in profiles_value:
		if not profile_value is Dictionary:
			return false
		var profile := profile_value as Dictionary
		var agent_id := str(profile.get("agent_id", ""))
		var role_id := str(profile.get("role_id", ""))
		if agent_id.is_empty() or candidates.has(agent_id) or not roles.has(role_id):
			return false
		var merged := profile.duplicate(true)
		merged["tools"] = (roles[role_id] as Dictionary).tools.duplicate()
		merged["goals"] = (roles[role_id] as Dictionary).goals.duplicate()
		merged["decision_interval_hours"] = (roles[role_id] as Dictionary).decision_interval_hours.duplicate()
		candidates[agent_id] = merged
	_agents = candidates
	_roles = roles
	return true


func get_agent_ids() -> Array:
	var result := _agents.keys()
	result.sort()
	return result


func get_agent(agent_id: String) -> Dictionary:
	return (_agents.get(agent_id, {}) as Dictionary).duplicate(true)


func get_role(role_id: String) -> Dictionary:
	return (_roles.get(role_id, {}) as Dictionary).duplicate(true)


func get_role_ids() -> Array:
	var result := _roles.keys()
	result.sort()
	return result


func set_active_role(agent_id: String, role_id: String) -> bool:
	if not _agents.has(agent_id) or not _roles.has(role_id):
		return false
	var agent := (_agents[agent_id] as Dictionary).duplicate(true)
	var role: Dictionary = _roles[role_id]
	agent.role_id = role_id
	agent.tools = (role.tools as Array).duplicate()
	agent.goals = (role.goals as Array).duplicate()
	agent.decision_interval_hours = (role.decision_interval_hours as Array).duplicate()
	_agents[agent_id] = agent
	return true


func is_agent_managed(agent_id: String) -> bool:
	return _agents.has(agent_id)


func is_tool_allowed(agent_id: String, tool_name: String) -> bool:
	return _agents.has(agent_id) and ((_agents[agent_id] as Dictionary).tools as Array).has(tool_name)


func load_public_coordinator() -> bool:
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/agents/public_coordinator.json"))
	if not config is Dictionary: return false
	_roles = {config.role.role_id: config.role.duplicate(true)}
	var profile: Dictionary = config.profile.duplicate(true)
	profile.tools = config.role.tools.duplicate()
	profile.goals = config.role.goals.duplicate()
	profile.decision_interval_hours = config.role.decision_interval_hours.duplicate()
	_agents = {profile.agent_id: profile}
	return true
