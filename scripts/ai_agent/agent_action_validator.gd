extends RefCounted

const AgentProtocolScript = preload("res://scripts/ai_agent/agent_protocol.gd")
const SEED_IDS := ["tomato_seed", "carrot_seed", "potato_seed", "grain_seed", "lavender_seed", "grape_seed", "lemon_sapling"]
const BUILDING_TYPES := ["barn", "greenhouse", "workshop"]
const REGION_IDS := ["creek", "hills", "forest"]
const DISCOVERY_IDS := ["crop:moonflower", "terrain:cliff", "crop:stardust_fruit"]


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
	if not _valid_arguments(str(parsed.value.tool_name), parsed.value.arguments):
		return {"ok": false, "error": "invalid_arguments"}
	return parsed


func _valid_arguments(tool_name: String, arguments: Dictionary) -> bool:
	match tool_name:
		"till", "harvest":
			return _exact_keys(arguments, ["plot"]) and _integer_in_range(arguments.plot, 0, 255)
		"plant":
			return _exact_keys(arguments, ["plot", "seed_item_id"]) and _integer_in_range(arguments.plot, 0, 255) and str(arguments.seed_item_id) in SEED_IDS
		"buy", "sell", "prepare_supplies", "propose_trade":
			return _exact_keys(arguments, ["item_id", "quantity"]) and _bounded_id(arguments.item_id) and _integer_in_range(arguments.quantity, 1, 100)
		"build":
			return _exact_keys(arguments, ["building_type", "building_id"]) and str(arguments.building_type) in BUILDING_TYPES and _bounded_id(arguments.building_id)
		"travel":
			return _exact_keys(arguments, ["region_id", "duration_minutes"]) and str(arguments.region_id) in REGION_IDS and _integer_in_range(arguments.duration_minutes, 10, 240)
		"survey":
			return _exact_keys(arguments, ["region_id"]) and str(arguments.region_id) in REGION_IDS
		"collect_sample", "register_discovery":
			return _exact_keys(arguments, ["discovery_id"]) and str(arguments.discovery_id) in DISCOVERY_IDS
		"speak", "wait":
			return arguments.is_empty()
	return false


func _exact_keys(arguments: Dictionary, expected: Array) -> bool:
	if arguments.size() != expected.size():
		return false
	for key in expected:
		if not arguments.has(key):
			return false
	return true


func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == floor(numeric) and numeric >= minimum and numeric <= maximum


func _bounded_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not str(value).strip_edges().is_empty() and str(value).length() <= 80
