extends RefCounted

const AgentProtocolScript = preload("res://scripts/ai_agent/agent_protocol.gd")
const SEED_IDS := ["tomato_seed", "carrot_seed", "potato_seed", "grain_seed", "lavender_seed", "grape_seed", "lemon_sapling"]
const BUILDING_TYPES := ["barn", "greenhouse", "workshop"]
const REGION_IDS := ["creek", "hills", "forest"]
const DISCOVERY_IDS := ["crop:moonflower", "terrain:cliff", "crop:stardust_fruit"]
const COOPERATION_IDS := ["joint_crop_supply", "exploration_sample", "material_procurement", "shared_construction"]


func validate(intent: Variant, registry: Variant, _current_revision: int, role_system: Variant = null) -> Dictionary:
	if not intent is Dictionary:
		return {"ok": false, "error": "invalid_envelope"}
	var agent_id := str((intent as Dictionary).get("agent_id", ""))
	if registry == null or not registry.has_method("get_agent"):
		return {"ok": false, "error": "missing_registry"}
	var agent: Dictionary = registry.call("get_agent", agent_id)
	if agent.is_empty():
		return {"ok": false, "error": "unknown_agent"}
	var allowed_tools: Array = agent.get("tools", [])
	if role_system != null and role_system.has_method("get_capabilities"):
		allowed_tools = (role_system.call("get_capabilities", agent_id) as Dictionary).get("tools", [])
	var parsed := AgentProtocolScript.parse_action_intent(intent, allowed_tools)
	if not parsed.ok:
		if role_system != null and str(parsed.get("error", "")) == "unauthorized_tool":
			return {"ok": false, "error": "role_capability_changed"}
		return parsed
	for action in parsed.value.actions:
		if not _valid_arguments(str(action.tool_name), action.arguments):
			return {"ok": false, "error": "invalid_arguments"}
	return parsed


func _valid_arguments(tool_name: String, arguments: Dictionary) -> bool:
	match tool_name:
		"public_food_plan", "public_wait": return preload("res://scripts/systems/public_plan_system.gd").valid_command(tool_name, arguments)
		"propose_delivery": return preload("res://scripts/systems/npc_interruption_system.gd").valid_terms(arguments)
		"cancel_delivery": return _exact_keys(arguments, ["task_id", "version"]) and _bounded_id(arguments.task_id) and _integer_in_range(arguments.version, 1, 1000000)
		"revise_project": return _exact_keys(arguments, ["project_id", "version", "plan", "source"]) and _bounded_id(arguments.project_id) and _integer_in_range(arguments.version, 1, 1000000) and arguments.source in ["dialogue", "self_review"] and preload("res://scripts/systems/npc_project_system.gd").valid_plan(arguments.plan)
		"submit_project": return preload("res://scripts/systems/npc_project_system.gd").valid_plan(arguments)
		"retry_project", "cancel_project": return _exact_keys(arguments, ["project_id"]) and _bounded_id(arguments.project_id)
		"suggest_behavior": return _exact_keys(arguments, ["text", "ttl"]) and _text(arguments.text, 500) and _integer_in_range(arguments.ttl, 1, 1080)
		"publish_commission", "propose_player_commission": return preload("res://scripts/systems/commission_system.gd").valid_terms(arguments)
		"claim_commission": return _exact_keys(arguments, ["commission_id", "quantity"]) and _bounded_id(arguments.commission_id) and _integer_in_range(arguments.quantity, 1, 100)
		"deliver_commission": return _exact_keys(arguments, ["claim_id", "quantity", "version", "order_id"]) and _bounded_id(arguments.claim_id) and _integer_in_range(arguments.quantity, 1, 100) and _integer_in_range(arguments.version, 1, 1000000) and _text(arguments.order_id, 100, true)
		"rent_production":
			return _exact_keys(arguments, ["building_id", "recipe_id", "batches", "max_fee"]) and _bounded_id(arguments.building_id) and _bounded_id(arguments.recipe_id) and _integer_in_range(arguments.batches, 1, 100) and _integer_in_range(arguments.max_fee, 0, 1000000)
		"till":
			return _exact_keys(arguments, ["plot"]) and _integer_in_range(arguments.plot, 0, 255)
		"harvest":
			return _keys_with_optional_agreement(arguments, ["plot"]) and _integer_in_range(arguments.plot, 0, 255)
		"plant":
			return _exact_keys(arguments, ["plot", "seed_item_id"]) and _integer_in_range(arguments.plot, 0, 255) and str(arguments.seed_item_id) in SEED_IDS
		"buy", "sell":
			return _keys_with_optional_agreement(arguments, ["item_id", "quantity"]) and _bounded_id(arguments.item_id) and _integer_in_range(arguments.quantity, 1, 100)
		"prepare_supplies":
			return _exact_keys(arguments, ["item_id", "quantity"]) and _bounded_id(arguments.item_id) and _integer_in_range(arguments.quantity, 1, 100)
		"send_message":
			return _exact_keys(arguments, ["target_actor_id", "text", "urgency"]) and _bounded_id(arguments.target_actor_id) and _text(arguments.text, 1000) and str(arguments.urgency) in ["normal", "urgent"]
		"propose_trade":
			return _valid_offer_terms(arguments, "target_actor_id")
		"counter_trade":
			return _valid_offer_terms(arguments, "offer_id")
		"accept_trade", "cancel_trade":
			return _exact_keys(arguments, ["offer_id"]) and _bounded_id(arguments.offer_id)
		"reject_trade":
			return _exact_keys(arguments, ["offer_id", "reason_code"]) and _bounded_id(arguments.offer_id) and _bounded_id(arguments.reason_code)
		"propose_cooperation":
			return (
				_exact_keys(arguments, ["objective_id", "participants", "commitments", "reward_split", "deadline_minutes", "note"])
				and str(arguments.objective_id) in COOPERATION_IDS
				and _unique_bounded_ids(arguments.participants, 1, 2)
				and _text(arguments.note, 500, true)
				and _valid_cooperation_terms({
					"commitments": arguments.commitments,
					"reward_split": arguments.reward_split,
					"deadline_minutes": arguments.deadline_minutes,
				})
			)
		"counter_cooperation":
			return _exact_keys(arguments, ["agreement_id", "revised_terms", "note"]) and _bounded_id(arguments.agreement_id) and _valid_cooperation_terms(arguments.revised_terms) and _text(arguments.note, 500, true)
		"accept_cooperation":
			return _exact_keys(arguments, ["agreement_id", "terms_version"]) and _bounded_id(arguments.agreement_id) and _integer_in_range(arguments.terms_version, 1, 1000)
		"reject_cooperation", "cancel_cooperation":
			return _exact_keys(arguments, ["agreement_id", "reason_code"]) and _bounded_id(arguments.agreement_id) and _bounded_id(arguments.reason_code)
		"commit_contribution":
			return _exact_keys(arguments, ["agreement_id", "contribution_id"]) and _bounded_id(arguments.agreement_id) and _bounded_id(arguments.contribution_id)
		"build":
			return _keys_with_optional_agreement(arguments, ["building_type", "building_id"]) and str(arguments.building_type) in BUILDING_TYPES and _bounded_id(arguments.building_id)
		"travel":
			return _exact_keys(arguments, ["region_id", "duration_minutes"]) and str(arguments.region_id) in REGION_IDS and _integer_in_range(arguments.duration_minutes, 10, 240)
		"survey":
			return _keys_with_optional_agreement(arguments, ["region_id"]) and str(arguments.region_id) in REGION_IDS
		"collect_sample":
			return _keys_with_optional_agreement(arguments, ["discovery_id"]) and str(arguments.discovery_id) in DISCOVERY_IDS
		"register_discovery":
			return _exact_keys(arguments, ["discovery_id"]) and str(arguments.discovery_id) in DISCOVERY_IDS
		"propose_role_change":
			return _exact_keys(arguments, ["target_role_id", "motivation"]) and str(arguments.target_role_id) in ["farmer", "merchant", "explorer"] and _text(arguments.motivation, 300)
		"speak":
			return _exact_keys(arguments, ["target_actor_id", "text"]) and _bounded_id(arguments.target_actor_id) and _text(arguments.text, 1000)
		"wait":
			return _exact_keys(arguments, ["reason"]) and _text(arguments.reason, 300)
	return false


func _valid_offer_terms(arguments: Dictionary, id_field: String) -> bool:
	if not _exact_keys(arguments, [id_field, "give", "receive", "expires_in_minutes", "note"]):
		return false
	if not _bounded_id(arguments[id_field]) or not _valid_asset_bundle(arguments.give) or not _valid_asset_bundle(arguments.receive) or not _integer_in_range(arguments.expires_in_minutes, 1, 10080) or not _text(arguments.note, 500, true):
		return false
	var give := arguments.give as Dictionary
	var receive := arguments.receive as Dictionary
	if _bundle_empty(give) or _bundle_empty(receive):
		return false
	for item_id in (give.items as Dictionary):
		if (receive.items as Dictionary).has(item_id):
			return false
	return true


func _valid_asset_bundle(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var bundle := value as Dictionary
	if not _exact_keys(bundle, ["items", "gold"]) or not bundle.items is Dictionary or not _integer_in_range(bundle.gold, 0, 1000000000):
		return false
	for item_id in (bundle.items as Dictionary):
		if not _bounded_id(item_id) or not _integer_in_range(bundle.items[item_id], 1, 1000000):
			return false
	return true


func _valid_commitment(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var commitment := value as Dictionary
	if not _exact_keys(commitment, ["participant_id", "items", "gold"]) or not _bounded_id(commitment.participant_id) or not commitment.items is Dictionary or not _integer_in_range(commitment.gold, 0, 1000000000):
		return false
	for item_id in (commitment.items as Dictionary):
		if not _bounded_id(item_id) or not _integer_in_range(commitment.items[item_id], 1, 1000000):
			return false
	return true


func _valid_cooperation_terms(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var terms := value as Dictionary
	if not _exact_keys(terms, ["commitments", "reward_split", "deadline_minutes"]) or not terms.commitments is Array or not terms.reward_split is Dictionary:
		return false
	if (terms.commitments as Array).size() < 2 or (terms.commitments as Array).size() > 3 or not _integer_in_range(terms.deadline_minutes, 60, 5760):
		return false
	for commitment in (terms.commitments as Array):
		if not _valid_commitment(commitment):
			return false
	for participant_id in (terms.reward_split as Dictionary):
		if not _bounded_id(participant_id) or not _integer_in_range(terms.reward_split[participant_id], 1, 1000):
			return false
	return true


func _unique_bounded_ids(value: Variant, minimum: int, maximum: int) -> bool:
	if not value is Array or value.size() < minimum or value.size() > maximum:
		return false
	var seen: Dictionary = {}
	for id_value in value:
		if not _bounded_id(id_value) or seen.has(str(id_value)):
			return false
		seen[str(id_value)] = true
	return true


func _bundle_empty(bundle: Dictionary) -> bool:
	return int(bundle.gold) == 0 and (bundle.items as Dictionary).is_empty()


func _exact_keys(arguments: Dictionary, expected: Array) -> bool:
	if arguments.size() != expected.size():
		return false
	for key in expected:
		if not arguments.has(key):
			return false
	return true


func _keys_with_optional_agreement(arguments: Dictionary, expected: Array) -> bool:
	if _exact_keys(arguments, expected):
		return true
	var linked := expected.duplicate()
	linked.append("agreement_id")
	return _exact_keys(arguments, linked) and _bounded_id(arguments.agreement_id)


func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == floor(numeric) and numeric >= minimum and numeric <= maximum


func _bounded_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not str(value).strip_edges().is_empty() and str(value).length() <= 80


func _text(value: Variant, maximum: int, allow_empty := false) -> bool:
	return typeof(value) == TYPE_STRING and str(value).length() <= maximum and (allow_empty or not str(value).strip_edges().is_empty())
