extends RefCounted

const CROP_BY_SEED := {
	"tomato_seed": {"item_id": "tomato", "minutes": 60, "yield": 4},
	"carrot_seed": {"item_id": "carrot", "minutes": 60, "yield": 4},
	"potato_seed": {"item_id": "potato", "minutes": 75, "yield": 4},
	"grain_seed": {"item_id": "grain", "minutes": 90, "yield": 4},
	"lavender_seed": {"item_id": "lavender", "minutes": 90, "yield": 3},
	"grape_seed": {"item_id": "grape", "minutes": 120, "yield": 3},
	"lemon_sapling": {"item_id": "lemon", "minutes": 180, "yield": 3},
}
const SURVEY_RESULTS := {"creek": "crop:moonflower", "hills": "terrain:cliff", "forest": "crop:stardust_fruit"}
const SAMPLE_ITEMS := {"crop:moonflower": "moonflower", "crop:stardust_fruit": "stardust_fruit"}

var world_revision := 0
var farm3d_session: Node
var _registry: Variant
var _farm: Variant
var _buildings: Variant
var _activities: Variant
var _knowledge: Variant
var _economy: Variant
var _roles: Variant
var _interactions: Variant
var _agreements: Variant
var _publish_hud: Callable
var _outcomes: Dictionary = {}
var _continuations: Dictionary = {}
const PHYSICAL_ACTIONS := ["move", "buy", "sell", "prepare_supplies", "rent_production"]


func to_dict() -> Dictionary:
	return {"world_revision": world_revision, "outcomes": _outcomes.duplicate(true), "continuations": _continuations.duplicate(true)}


func current_state() -> Dictionary:
	return compact_state({"world_revision": world_revision, "outcomes": _outcomes, "continuations": _continuations})


static func compact_state(value: Dictionary) -> Dictionary:
	# Pending commands need their full arguments to resume. Finished commands
	# retain settlement receipts for idempotency, not their narration/intent.
	if not value.get("outcomes") is Dictionary or not value.get("continuations", {}) is Dictionary: return {}
	var outcomes := {}
	for key in value.get("outcomes", {}):
		var outcome: Variant = value.outcomes[key]
		if not outcome is Dictionary: return {}
		if outcome.get("status") in ["accepted", "in_progress"] or value.get("continuations", {}).has(key):
			outcomes[key] = outcome.duplicate(true)
		else:
			var receipt := {}
			for field in ["protocol_version", "agent_id", "decision_id", "action_id", "idempotency_key", "tool_name", "status", "committed_revision", "resource_delta", "changed_entities", "failure_code", "game_minute", "agreement_id"]:
				if outcome.has(field): receipt[field] = outcome[field]
			outcomes[key] = receipt.duplicate(true)
	return {"world_revision": value.get("world_revision", -1), "outcomes": outcomes, "continuations": value.get("continuations", {}).duplicate(true)}


func validate_dict(value: Dictionary) -> bool:
	if int(value.get("world_revision", -1)) < 0 or not value.get("outcomes") is Dictionary:
		return false
	if not value.get("continuations", {}) is Dictionary: return false
	for key in value.get("continuations", {}):
		var batch: Variant = value.continuations[key]
		if not value.outcomes.has(key) or not batch is Dictionary or not batch.get("agent_id") is String or not batch.get("actions") is Array: return false
		for action in batch.actions:
			if not action is Dictionary or not action.get("arguments") is Dictionary or not action.get("tool_name") is String or not action.get("idempotency_key") is String: return false
			if not preload("res://scripts/ai_agent/agent_action_validator.gd").new()._valid_arguments(action.tool_name, action.arguments): return false
	for key in (value.outcomes as Dictionary):
		var outcome_value: Variant = value.outcomes[key]
		if (
			typeof(key) != TYPE_STRING
			or str(key).is_empty()
			or not outcome_value is Dictionary
		):
			return false
		var outcome := outcome_value as Dictionary
		if (
			str(outcome.get("idempotency_key", "")) != str(key)
			or not str(outcome.get("status", "")) in ["accepted", "in_progress", "completed", "rejected", "failed"]
			or int(outcome.get("committed_revision", -1)) < 0
			or int(outcome.get("committed_revision", -1)) > int(value.world_revision)
			or not outcome.get("changed_entities") is Array
			or not outcome.get("resource_delta") is Dictionary
		):
			return false
	return true


func from_dict(value: Dictionary) -> bool:
	if not validate_dict(value):
		return false
	world_revision = int(value.world_revision)
	_outcomes = (value.outcomes as Dictionary).duplicate(true)
	_continuations = value.get("continuations", {}).duplicate(true)
	return true


func configure(
	registry: Variant,
	farm: Variant,
	buildings: Variant,
	activities: Variant,
	knowledge: Variant,
	economy: Variant,
	publish_hud: Callable = Callable(),
	roles: Variant = null,
	interactions: Variant = null,
	agreements: Variant = null
) -> bool:
	if registry == null or farm == null or buildings == null or activities == null or knowledge == null or economy == null:
		return false
	_registry = registry
	_farm = farm
	_buildings = buildings
	_activities = activities
	_knowledge = knowledge
	_economy = economy
	_roles = roles
	_interactions = interactions
	_agreements = agreements
	_publish_hud = publish_hud
	return true


func execute_batch(intent: Dictionary, game_minute: int) -> Array[Dictionary]:
	var outcomes: Array[Dictionary] = []
	var actions: Array = intent.get("actions", [])
	var index := 0
	while index < actions.size():
		var source_action: Dictionary = actions[index]
		if _uses_visible_farm(source_action):
			var farm_actions: Array[Dictionary] = []
			while index < actions.size() and _uses_visible_farm(actions[index]):
				farm_actions.append((actions[index] as Dictionary).duplicate(true))
				index += 1
			var queued := _queue_visible_farm(intent, farm_actions, game_minute)
			outcomes.append_array(queued)
			if not queued.is_empty() and str(queued[-1].get("status", "")) in ["rejected", "failed"]:
				break
			if not queued.is_empty() and str(queued[-1].get("status", "")) == "in_progress":
				_remember_continuation(intent, index, str(queued[-1].idempotency_key))
				break
			continue
		var action_value = actions[index]
		index += 1
		var action := (action_value as Dictionary).duplicate(true)
		action.agent_id = str(intent.get("agent_id", ""))
		action.decision_id = str(intent.get("decision_id", ""))
		action.request_id = str(intent.get("request_id", action.decision_id))
		action.expected_revision = int(intent.get("expected_revision", 0))
		var outcome := execute(action, game_minute)
		outcomes.append(outcome)
		if str(outcome.get("status", "")) == "in_progress":
			_remember_continuation(intent, index, str(outcome.idempotency_key))
		if str(outcome.get("status", "")) in ["rejected", "failed", "in_progress"]:
			break
	return outcomes


func _remember_continuation(batch: Dictionary, index: int, key: String) -> void:
	if index >= batch.actions.size() or _continuations.has(key): return
	var remaining := batch.duplicate(true)
	remaining.actions = batch.actions.slice(index).duplicate(true)
	_continuations[key] = remaining

func resume_batch_after(outcome: Dictionary, game_minute: int) -> Array[Dictionary]:
	if outcome.get("status") in ["failed", "rejected"]:
		for pending in _continuations.keys():
			if _continuations[pending].get("decision_id") == outcome.get("decision_id"):
				_continuations.erase(pending)
		return []
	var key := str(outcome.get("idempotency_key", ""))
	if not _continuations.has(key) or outcome.get("status") == "in_progress": return []
	var batch: Dictionary = _continuations[key]
	_continuations.erase(key)
	if outcome.get("status") != "completed": return []
	return execute_batch(batch, game_minute)

func has_pending_continuation(agent_id: String) -> bool:
	return _continuations.values().any(func(batch): return batch.get("agent_id") == agent_id)


func finalize_queued_action(intent: Dictionary, result: Dictionary, game_minute: int) -> Dictionary:
	var key := str(intent.get("idempotency_key", ""))
	var outcome: Dictionary
	if bool(result.get("ok", false)):
		world_revision += 1
		outcome = {
			"protocol_version": 2,
			"decision_id": str(intent.get("decision_id", "")),
			"action_id": str(intent.get("action_id", "")),
			"idempotency_key": key,
			"status": "completed",
			"committed_revision": world_revision,
			"changed_entities": result.get("changed_entities", []),
			"resource_delta": result.get("resource_delta", {}),
			"hud_message": str(result.get("message", "")),
			"game_minute": game_minute,
			"agent_id": str(intent.get("agent_id", "")),
			"tool_name": str(intent.get("tool_name", "")),
			"arguments": (intent.get("arguments", {}) as Dictionary).duplicate(true),
			"agreement_id": str((intent.get("arguments", {}) as Dictionary).get("agreement_id", "")),
		}
		if bool(result.get("cleared_withered", false)):
			outcome.cleared_withered = true
	else:
		outcome = _failure(intent, game_minute, str(result.get("error", "work_failed")))
	_outcomes[key] = outcome.duplicate(true)
	if not str(outcome.hud_message).is_empty() and _publish_hud.is_valid():
		_publish_hud.call(str(outcome.hud_message))
	return outcome


func _uses_visible_farm(action: Dictionary) -> bool:
	return (
		_farm != null
		and _farm.has_method("queue_batch")
		and str(action.get("tool_name", "")) in ["till", "plant", "harvest"]
	)


func _queue_visible_farm(
	intent: Dictionary,
	actions: Array[Dictionary],
	game_minute: int
) -> Array[Dictionary]:
	var pending_actions: Array[Dictionary] = []
	var outcomes: Array[Dictionary] = []
	for source in actions:
		var action := source.duplicate(true)
		action.agent_id = str(intent.get("agent_id", ""))
		action.decision_id = str(intent.get("decision_id", ""))
		action.expected_revision = int(intent.get("expected_revision", 0))
		var key := str(action.get("idempotency_key", ""))
		if _outcomes.has(key):
			outcomes.append((_outcomes[key] as Dictionary).duplicate(true))
		else:
			pending_actions.append(action)
	if pending_actions.is_empty():
		return outcomes
	if is_instance_valid(farm3d_session) and farm3d_session.living_world.work.owns_schedule(str(intent.agent_id)):
		outcomes.append(_failure(pending_actions[0], game_minute, "actor_schedule_busy"))
		return outcomes
	var queued_intent := intent.duplicate(true)
	queued_intent.actions = pending_actions
	var results: Array = _farm.call("queue_batch", queued_intent, game_minute)
	for result_index in range(results.size()):
		var action := pending_actions[result_index]
		var result: Dictionary = results[result_index]
		if not bool(result.get("ok", false)):
			var failure := _failure(action, game_minute, str(result.get("error", "queue_rejected")))
			_outcomes[str(action.idempotency_key)] = failure.duplicate(true)
			outcomes.append(failure)
			break
		var outcome := {
			"protocol_version": 2,
			"decision_id": str(action.decision_id),
			"action_id": str(action.get("action_id", "")),
			"idempotency_key": str(action.idempotency_key),
			"status": "in_progress",
			"committed_revision": world_revision,
			"changed_entities": [],
			"resource_delta": {},
			"hud_message": "",
			"game_minute": game_minute,
		}
		_outcomes[str(action.idempotency_key)] = outcome.duplicate(true)
		outcomes.append(outcome)
	return outcomes


func execute(intent: Dictionary, game_minute: int) -> Dictionary:
	var idempotency_key := str(intent.get("idempotency_key", ""))
	if _outcomes.has(idempotency_key):
		return (_outcomes[idempotency_key] as Dictionary).duplicate(true)
	var agent_id := str(intent.get("agent_id", ""))
	var tool_name := str(intent.get("tool_name", ""))
	var tool_allowed := bool(_registry.call("is_tool_allowed", agent_id, tool_name))
	if _roles != null and _roles.has_method("get_capabilities"):
		tool_allowed = tool_name in ((_roles.call("get_capabilities", agent_id) as Dictionary).get("tools", []) as Array)
	if not tool_allowed:
		return _failure(intent, game_minute, "unauthorized_tool")
	var arguments: Dictionary = intent.get("arguments", {})
	var result := _begin_physical_action(intent, game_minute) if is_instance_valid(farm3d_session) and tool_name in PHYSICAL_ACTIONS else _execute_tool(
		agent_id,
		tool_name,
		arguments,
		game_minute,
		idempotency_key,
		str(intent.get("decision_id", "")),
		str(intent.get("action_id", "")),
		str(intent.get("request_id", intent.get("decision_id", "")))
	)
	return _record_result(intent, result, game_minute)

func _record_result(intent: Dictionary, result: Dictionary, game_minute: int) -> Dictionary:
	var idempotency_key := str(intent.get("idempotency_key", ""))
	var agent_id := str(intent.get("agent_id", ""))
	var tool_name := str(intent.get("tool_name", ""))
	var arguments: Dictionary = intent.get("arguments", {})
	if not result.ok:
		var failed := _failure(intent, game_minute, str(result.error))
		if _outcomes.get(idempotency_key, {}).get("status") == "in_progress": failed.status = "failed"
		failed.merge({"agent_id": agent_id, "tool_name": tool_name, "arguments": arguments.duplicate(true)})
		_outcomes[idempotency_key] = failed.duplicate(true)
		return failed
	if bool(result.get("mutated", false)):
		world_revision += 1
	var status := str(result.get("status", "completed"))
	var outcome := {
		"protocol_version": 2,
		"decision_id": str(intent.get("decision_id", "")),
		"action_id": str(intent.get("action_id", "")),
		"idempotency_key": idempotency_key,
		"status": status,
		"committed_revision": world_revision,
		"changed_entities": result.get("changed_entities", []),
		"resource_delta": result.get("resource_delta", {}),
		"hud_message": str(result.get("message", "")),
		"game_minute": game_minute,
		"agent_id": agent_id,
		"tool_name": tool_name,
		"arguments": arguments.duplicate(true),
		"agreement_id": str(arguments.get("agreement_id", "")),
	}
	_outcomes[idempotency_key] = outcome.duplicate(true)
	if not outcome.hud_message.is_empty() and _publish_hud.is_valid():
		_publish_hud.call(outcome.hud_message)
	return outcome


func _begin_physical_action(intent: Dictionary, game_minute: int) -> Dictionary:
	var world: Node = farm3d_session.living_world
	var agent_id := str(intent.agent_id)
	if world.work.occupied(agent_id): return _error("actor_schedule_busy")
	var movement := {}
	var approach: Dictionary = world.work.approach_action(agent_id, str(intent.tool_name), intent.arguments, movement)
	if not approach.get("ok", false) and not approach.get("waiting", false): return approach
	var payload := {"physical_action": true, "intent": intent.duplicate(true), "movement": movement, "deadline": game_minute + 720}
	if not _activities.start(agent_id, str(intent.tool_name), str(intent.idempotency_key), game_minute, game_minute + 1, payload):
		world.actor(agent_id).stop_agent_work()
		return _error("actor_schedule_busy")
	return {"ok": true, "status": "in_progress", "mutated": false, "message": "%s正前往目标，抵达后执行操作。" % _display_name(agent_id), "changed_entities": [], "resource_delta": {}}

func complete_physical_action(record: Dictionary, game_minute: int) -> Dictionary:
	var p: Dictionary = record.payload
	var intent: Dictionary = p.intent
	var actor: Node3D = farm3d_session.living_world.actor(record.agent_id)
	var result := _error("action_deadline")
	if game_minute < int(p.deadline):
		result = farm3d_session.living_world.work.approach_action(record.agent_id, record.kind, intent.arguments, p.movement)
		if result.get("waiting", false): return {"ready": false}
		if result.get("ok", false):
			result = _execute_tool(record.agent_id, record.kind, intent.arguments, game_minute, record.activity_id, str(intent.get("decision_id", "")), str(intent.get("action_id", "")), str(intent.get("request_id", "")), true)
	if actor != null: actor.stop_agent_work()
	return {"ready": true, "ok": result.get("ok", false), "error": result.get("error", ""), "execution_result": result}


func complete_due(game_minute: int) -> Array[Dictionary]:
	var outcomes: Array[Dictionary] = []
	for activity in _activities.call("complete_due", game_minute):
		var record := activity as Dictionary
		if record.payload.get("physical_action", false):
			var outcome := _record_result(record.payload.intent, record.execution_result, game_minute)
			outcomes.append(outcome)
			outcomes.append_array(resume_batch_after(outcome, game_minute))
			continue
		var message := "%s完成了%s" % [str(record.agent_id), str(record.kind)]
		var changed: Array[String] = ["npc_activity:" + str(record.activity_id)]
		if record.kind == "build":
			var payload: Dictionary = record.payload
			if _buildings.call("add_building", str(record.agent_id), str(payload.building_type), str(payload.building_id), game_minute):
				changed.append("npc_building:" + str(payload.building_id))
		world_revision += 1
		var completed_arguments := (record.payload as Dictionary).duplicate(true)
		for internal_field in ["decision_id", "action_id", "tool_name"]:
			completed_arguments.erase(internal_field)
		var outcome := {"protocol_version": 2, "decision_id": str(record.payload.get("decision_id", "")), "action_id": str(record.payload.get("action_id", record.activity_id)), "idempotency_key": str(record.activity_id), "agent_id": str(record.agent_id), "tool_name": str(record.payload.get("tool_name", record.kind)), "arguments": completed_arguments, "agreement_id": str(record.payload.get("agreement_id", "")), "status": "completed", "committed_revision": world_revision, "changed_entities": changed, "resource_delta": {}, "hud_message": message, "game_minute": game_minute}
		if record.status == "failed":
			outcome.status = "failed"
			outcome.error_code = str(record.payload.get("error", "activity_failed"))
			outcome.hud_message = "%s的%s未完成：%s" % [_display_name(record.agent_id), record.kind, outcome.error_code]
		_outcomes[str(record.activity_id)] = outcome.duplicate(true)
		outcomes.append(outcome)
		outcomes.append_array(resume_batch_after(outcome, game_minute))
		if _publish_hud.is_valid():
			_publish_hud.call(outcome.hud_message)
	return outcomes


func _execute_tool(agent_id: String, tool_name: String, arguments: Dictionary, game_minute: int, key: String, decision_id: String, action_id: String, request_id := "", at_destination := false) -> Dictionary:
	if not at_destination and is_instance_valid(farm3d_session) and not farm3d_session.living_world.interruptions.running(agent_id).is_empty() and tool_name in ["travel", "move", "till", "plant", "water", "harvest", "build", "survey", "gather_sample", "deliver_commission"]: return _error("delivery_in_progress")
	if not at_destination and is_instance_valid(farm3d_session) and farm3d_session.living_world.work.owns_schedule(agent_id) and tool_name in ["travel", "move", "till", "plant", "water", "harvest", "build", "survey", "collect_sample", "rent_production"]: return _error("work_schedule_conflict")
	match tool_name:
		"move":
			return _success("%s已到达目的地。" % _display_name(agent_id), ["actor:" + agent_id]) if at_destination else _error("requires_3d_world")
		"propose_activity", "enroll_activity", "leave_activity", "cancel_activity":
			return farm3d_session.living_world.social.command(agent_id, tool_name, arguments, key) if is_instance_valid(farm3d_session) else _error("requires_3d_world")
		"contribute_route_repair":
			return farm3d_session.living_world.environment.command(agent_id, tool_name, arguments, key) if is_instance_valid(farm3d_session) else _error("requires_3d_world")
		"offer_intelligence", "buy_intelligence", "share_intelligence", "propose_investigation", "accept_investigation", "cancel_investigation":
			if not is_instance_valid(farm3d_session): return _error("farm3d_only")
			return _knowledge.command(agent_id, tool_name, arguments, key)
		"propose_joint_project", "accept_joint_project", "exit_joint_project", "propose_work", "counter_work", "accept_work", "cancel_work", "start_learning", "start_leisure", "manage_building", "propose_delivery", "cancel_delivery", "revise_project", "submit_project", "retry_project", "cancel_project", "publish_commission", "propose_player_commission", "claim_commission", "deliver_commission", "suggest_behavior":
			if not is_instance_valid(farm3d_session): return {"ok": false, "error": "farm3d_only"}
			return farm3d_session.living_world.command(agent_id, tool_name, arguments, key)
		"rent_production":
			if not is_instance_valid(farm3d_session):
				return _error("rental_unavailable")
			for building in farm3d_session.buildings.get_all_buildings():
				if str(arguments.get("building_id", "")) in [EconomyProgressionSystem.building_key(building), building.instance_id]:
					return farm3d_session.production.start_rented_recipe(building, agent_id, str(arguments.get("recipe_id", "")), int(arguments.get("batches", 0)), int(arguments.get("max_fee", 0)), key, request_id)
			return _error("building_not_found")
		"till":
			var plot := int(arguments.get("plot", -1))
			if not _farm.call("till", agent_id, plot):
				return _error("invalid_plot")
			return _success("%s开垦了地块 %d。" % [_display_name(agent_id), plot], ["npc_farm:%s:%d" % [agent_id, plot]])
		"plant":
			return _plant(agent_id, arguments, game_minute)
		"harvest":
			return _harvest(agent_id, arguments, game_minute)
		"buy", "sell":
			return _trade(agent_id, tool_name, arguments)
		"travel":
			var region_id := str(arguments.get("region_id", ""))
			var duration := clampi(int(arguments.get("duration_minutes", 60)), 10, 240)
			if is_instance_valid(farm3d_session): return _knowledge.begin_fieldwork(agent_id, "travel", region_id, key, {"decision_id": decision_id, "action_id": action_id}, duration)
			if region_id.is_empty() or not _activities.call("start", agent_id, "travel", key, game_minute, game_minute + duration, {"region_id": region_id, "decision_id": decision_id, "action_id": action_id, "tool_name": "travel", "agreement_id": str(arguments.get("agreement_id", ""))}):
				return _error("travel_unavailable")
			return {"ok": true, "mutated": true, "status": "in_progress", "message": "%s出发前往%s。" % [_display_name(agent_id), region_id], "changed_entities": ["npc_activity:" + key], "resource_delta": {}}
		"build":
			if is_instance_valid(farm3d_session): return {"ok": false, "error": "use_project_physical_construction"}
			var building_type := str(arguments.get("building_type", ""))
			var building_id := str(arguments.get("building_id", key))
			if building_type.is_empty() or not _activities.call("start", agent_id, "build", key, game_minute, game_minute + 120, {"building_type": building_type, "building_id": building_id, "decision_id": decision_id, "action_id": action_id, "tool_name": "build", "agreement_id": str(arguments.get("agreement_id", ""))}):
				return _error("build_unavailable")
			return {"ok": true, "mutated": true, "status": "in_progress", "message": "%s开始建造%s。" % [_display_name(agent_id), building_type], "changed_entities": ["npc_activity:" + key], "resource_delta": {}}
		"survey":
			var region_id := str(arguments.get("region_id", ""))
			if is_instance_valid(farm3d_session): return _knowledge.begin_fieldwork(agent_id, "survey", region_id, key, {"decision_id": decision_id, "action_id": action_id})
			var discovery_id := str(SURVEY_RESULTS.get(region_id, ""))
			if discovery_id.is_empty() or not _knowledge.call("discover", agent_id, discovery_id, region_id, game_minute):
				return _error("nothing_new_found")
			return _success("%s在%s发现了新线索。" % [_display_name(agent_id), region_id], ["private_knowledge:%s:%s" % [agent_id, discovery_id]])
		"register_discovery":
			var discovery_id := str(arguments.get("discovery_id", ""))
			if not _knowledge.call("publish", agent_id, discovery_id, game_minute):
				return _error("discovery_not_verified")
			return _success("%s登记了发现%s。" % [_display_name(agent_id), discovery_id], ["public_knowledge:" + discovery_id])
		"collect_sample":
			var discovery_id := str(arguments.get("discovery_id", ""))
			if is_instance_valid(farm3d_session): return _knowledge.collect(agent_id, discovery_id, key)
			var item_id := str(SAMPLE_ITEMS.get(discovery_id, ""))
			if item_id.is_empty() or not _economy.call("receive_item", agent_id, item_id, 1):
				return _error("sample_unavailable")
			return _success("%s采集了%s。" % [_display_name(agent_id), item_id], ["npc_inventory:" + agent_id], {item_id: 1})
		"prepare_supplies":
			return _trade(agent_id, "buy", arguments)
		"send_message", "propose_trade", "counter_trade", "accept_trade", "reject_trade", "cancel_trade", "speak":
			if _interactions == null:
				return _error("interaction_system_unavailable")
			var interaction_result: Dictionary = _interactions.call("execute", {
				"agent_id": agent_id,
				"tool_name": tool_name,
				"arguments": arguments,
				"idempotency_key": key,
				"decision_id": decision_id,
				"action_id": action_id,
			}, game_minute)
			if not bool(interaction_result.get("ok", false)):
				return _error(str(interaction_result.get("error", "interaction_failed")))
			return {
				"ok": true,
				"mutated": true,
				"message": str(interaction_result.get("message", "")),
				"changed_entities": interaction_result.get("changed_entities", []),
				"resource_delta": interaction_result.get("resource_delta", {}),
			}
		"propose_cooperation", "counter_cooperation", "accept_cooperation", "reject_cooperation", "commit_contribution", "cancel_cooperation":
			if _agreements == null:
				return _error("agreement_system_unavailable")
			var agreement_result: Dictionary = _agreements.call("execute", {
				"agent_id": agent_id, "tool_name": tool_name, "arguments": arguments,
				"idempotency_key": key, "decision_id": decision_id, "action_id": action_id,
			}, game_minute)
			if not bool(agreement_result.get("ok", false)):
				return _error(str(agreement_result.get("error", "agreement_failed")))
			return {"ok": true, "mutated": true, "message": "", "changed_entities": ["agreement:" + str(agreement_result.get("agreement_id", ""))], "resource_delta": {}}
		"propose_role_change":
			if _roles == null:
				return _error("role_system_unavailable")
			var role_result: Dictionary = _roles.call("propose_change", agent_id, str(arguments.get("target_role_id", "")), str(arguments.get("motivation", "")), game_minute, key)
			if not bool(role_result.get("ok", false)):
				return _error(str(role_result.get("error", "role_change_failed")))
			if not bool(role_result.get("approved", false)):
				return _success("%s的身份转换未通过：%s。" % [_display_name(agent_id), str(role_result.get("error", "条件不足"))], ["agent_role:" + agent_id])
			return _success("%s现在成为%s。" % [_display_name(agent_id), str(role_result.get("role_id", ""))], ["agent_role:" + agent_id], {"gold": -int(role_result.get("cost_gold", 0))})
		"wait":
			return {"ok": true, "mutated": false, "message": "", "changed_entities": [], "resource_delta": {}}
	return _error("unsupported_tool")


func _plant(agent_id: String, arguments: Dictionary, game_minute: int) -> Dictionary:
	var plot := int(arguments.get("plot", -1))
	var seed_item_id := str(arguments.get("seed_item_id", ""))
	var crop: Dictionary = CROP_BY_SEED.get(seed_item_id, {})
	var state = _economy.call("get_npc_state", agent_id)
	if crop.is_empty() or state == null or int(state.inventory.get(seed_item_id, 0)) <= 0 or (_interactions != null and int(_interactions.call("available_item", agent_id, seed_item_id)) <= 0):
		return _error("seed_unavailable")
	var state_before: Dictionary = state.to_dict()
	state.inventory[seed_item_id] = int(state.inventory.get(seed_item_id, 0)) - 1
	if not _farm.call("plant", agent_id, plot, crop.item_id, game_minute, game_minute + int(crop.minutes), int(crop.yield)):
		state.from_dict(state_before)
		return _error("plot_not_plantable")
	return _success("%s播种了%s。" % [_display_name(agent_id), str(crop.item_id)], ["npc_farm:%s:%d" % [agent_id, plot], "npc_inventory:" + agent_id], {seed_item_id: -1})


func _harvest(agent_id: String, arguments: Dictionary, game_minute: int) -> Dictionary:
	var plot := int(arguments.get("plot", -1))
	var farm_before: Dictionary = _farm.call("to_dict")
	var harvested: Dictionary = _farm.call("harvest", agent_id, plot, game_minute)
	if harvested.is_empty():
		return _error("crop_not_mature")
	if not _economy.call("receive_item", agent_id, str(harvested.item_id), int(harvested.quantity)):
		_farm.call("from_dict", farm_before)
		return _error("inventory_rejected")
	return _success("%s收获了%s ×%d，已进入库存。" % [_display_name(agent_id), str(harvested.item_id), int(harvested.quantity)], ["npc_farm:%s:%d" % [agent_id, plot], "npc_inventory:" + agent_id], {str(harvested.item_id): int(harvested.quantity)})


func _trade(agent_id: String, tool_name: String, arguments: Dictionary) -> Dictionary:
	var item_id := str(arguments.get("item_id", ""))
	var quantity := int(arguments.get("quantity", 0))
	if _interactions != null:
		if tool_name == "sell" and int(_interactions.call("available_item", agent_id, item_id)) < quantity:
			return _error("assets_reserved")
		if tool_name == "buy":
			var quoted := int(_economy.call("quote_agent_buy", item_id, quantity))
			if quoted <= 0 or int(_interactions.call("available_gold", agent_id)) < quoted:
				return _error("assets_reserved")
	var succeeded := bool(_economy.call("agent_buy" if tool_name == "buy" else "agent_sell", agent_id, item_id, quantity))
	if not succeeded:
		return _error("trade_rejected")
	var delta := quantity if tool_name == "buy" else -quantity
	return _success("%s%s了%s ×%d。" % [_display_name(agent_id), "购买" if tool_name == "buy" else "出售", item_id, quantity], ["npc_inventory:" + agent_id, "market:" + item_id], {item_id: delta})


func _display_name(agent_id: String) -> String:
	return str((_registry.call("get_agent", agent_id) as Dictionary).get("display_name", agent_id))


func _success(message: String, changed: Array, delta: Dictionary = {}) -> Dictionary:
	return {"ok": true, "mutated": true, "message": message, "changed_entities": changed, "resource_delta": delta}


func _error(error: String) -> Dictionary:
	return {"ok": false, "error": error}


func _failure(intent: Dictionary, game_minute: int, error: String) -> Dictionary:
	return {"protocol_version": 2, "decision_id": str(intent.get("decision_id", "")), "action_id": str(intent.get("action_id", "")), "idempotency_key": str(intent.get("idempotency_key", "")), "status": "rejected", "failure_code": error, "committed_revision": world_revision, "changed_entities": [], "resource_delta": {}, "hud_message": "", "game_minute": game_minute}
