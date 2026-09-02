class_name AgentAgreementSystem
extends RefCounted

const DEFAULT_TEMPLATES_PATH := "res://data/agents/cooperation_templates.json"
const VERSION := 1
const MAX_QUANTITY := 1000000

var _economy: Variant
var _interactions: Variant
var _store: Variant
var _projector: Variant
var _wake_agent: Callable
var _templates: Dictionary = {}
var _agreements: Dictionary = {}
var _results: Dictionary = {}
var _relationships: Dictionary = {}
var _relationship_daily_changes: Dictionary = {}
var _next_agreement_id := 1


func configure(economy: Variant, interactions: Variant, store: Variant, projector: Variant, wake_agent: Callable = Callable(), templates_path: String = DEFAULT_TEMPLATES_PATH) -> bool:
	if economy == null or interactions == null or store == null or projector == null:
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(templates_path))
	var normalized: Variant = _normalize_templates(parsed)
	if normalized == null:
		return false
	_economy = economy
	_interactions = interactions
	_store = store
	_projector = projector
	_wake_agent = wake_agent
	_templates = normalized
	return true


func execute(command: Dictionary, game_minute: int) -> Dictionary:
	var key := str(command.get("idempotency_key", "")).strip_edges()
	if key.is_empty() or game_minute < 0:
		return _failure("invalid_command")
	if _results.has(key):
		return (_results[key] as Dictionary).duplicate(true)
	var actor_id := str(command.get("agent_id", ""))
	var arguments: Variant = command.get("arguments", {})
	if not _actor_exists(actor_id) or not arguments is Dictionary:
		return _remember(key, _failure("invalid_actor_or_arguments"))
	var result: Dictionary
	match str(command.get("tool_name", "")):
		"propose_cooperation": result = _propose(actor_id, arguments, command, game_minute)
		"counter_cooperation": result = _counter(actor_id, arguments, command, game_minute)
		"accept_cooperation": result = _accept(actor_id, arguments, command, game_minute)
		"reject_cooperation": result = _terminate(actor_id, arguments, command, game_minute, "rejected")
		"cancel_cooperation": result = _terminate(actor_id, arguments, command, game_minute, "cancelled")
		"commit_contribution": result = _commit_resource_contribution(actor_id, arguments, command, game_minute)
		_: result = _failure("unsupported_agreement_tool")
	return _remember(key, result)


func record_action_outcome(outcome: Dictionary, game_minute: int) -> Array[Dictionary]:
	var emitted: Array[Dictionary] = []
	if str(outcome.get("status", "")) != "completed":
		return emitted
	var actor_id := str(outcome.get("agent_id", ""))
	var tool_name := str(outcome.get("tool_name", ""))
	var explicit_agreement_id := str(outcome.get("agreement_id", ""))
	var agreement_ids := _agreements.keys()
	agreement_ids.sort()
	for agreement_id_value in agreement_ids:
		var agreement_id := str(agreement_id_value)
		if not explicit_agreement_id.is_empty() and explicit_agreement_id != agreement_id:
			continue
		var agreement: Dictionary = _agreements[agreement_id]
		if str(agreement.status) != "active" or not actor_id in (agreement.participants as Array):
			continue
		var template: Dictionary = _templates[str(agreement.objective_id)]
		var contribution: Dictionary = {}
		for required_value in template.required_actions:
			var required := required_value as Dictionary
			if str(required.tool_name) == tool_name and int((agreement.progress as Dictionary).get(str(required.contribution_id), 0)) < int(required.count):
				contribution = required
				break
		if contribution.is_empty():
			continue
		var progress := (agreement.progress as Dictionary).duplicate(true)
		var contribution_id := str(contribution.contribution_id)
		progress[contribution_id] = int(progress.get(contribution_id, 0)) + 1
		var event := _event("AgreementContributionVerified", agreement_id, actor_id, game_minute, str(outcome.get("action_id", "action")), "agreement:" + agreement_id, {"agreement_id": agreement_id, "contribution_id": contribution_id, "tool_name": tool_name, "count": int(progress[contribution_id])}, agreement.participants)
		var committed := _commit([event], "agreement-contribution:%s:%s" % [agreement_id, str(outcome.get("action_id", "action"))])
		if not bool(committed.get("ok", false)):
			continue
		agreement.progress = progress
		_agreements[agreement_id] = agreement
		emitted.append_array(committed.events)
		if _milestones_complete(agreement, template):
			var completed := _complete(agreement_id, game_minute, str(outcome.get("action_id", "action")))
			if bool(completed.get("ok", false)):
				emitted.append_array(completed.events)
		break
	return emitted


func expire_due(game_minute: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var ids := _agreements.keys()
	ids.sort()
	for agreement_id_value in ids:
		var agreement_id := str(agreement_id_value)
		var agreement: Dictionary = _agreements[agreement_id]
		if not str(agreement.status) in ["proposed", "negotiating", "active"] or int(agreement.deadline) > game_minute:
			continue
		var events: Array[Dictionary] = [_event("AgreementFailed", agreement_id, "system", game_minute, "deadline:" + agreement_id, "agreement:" + agreement_id, {"agreement_id": agreement_id, "reason": "deadline"}, agreement.participants)]
		events.append_array(_relationship_events(agreement.participants, -1, game_minute, "deadline:" + agreement_id))
		var committed := _commit(events, "agreement-deadline:%s:%d" % [agreement_id, game_minute])
		if not bool(committed.get("ok", false)):
			continue
		_release_commitments(agreement)
		agreement.status = "failed"
		_agreements[agreement_id] = agreement
		_adjust_all_relationships(agreement.participants, -1, game_minute)
		_wake_participants(agreement.participants, "", game_minute)
		results.append({"ok": true, "agreement_id": agreement_id, "events": committed.events})
	return results


func get_agreement(agreement_id: String, observer_id: String) -> Dictionary:
	var agreement: Dictionary = _agreements.get(agreement_id, {})
	if agreement.is_empty() or not observer_id in (agreement.participants as Array):
		return {}
	return agreement.duplicate(true)


func list_agreements(observer_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids := _agreements.keys()
	ids.sort()
	for agreement_id in ids:
		var agreement := get_agreement(str(agreement_id), observer_id)
		if not agreement.is_empty():
			result.append(agreement)
	return result


func get_relationship(left_id: String, right_id: String) -> int:
	return int(_relationships.get(_pair_key(left_id, right_id), 0))


func _propose(actor_id: String, arguments: Dictionary, command: Dictionary, game_minute: int) -> Dictionary:
	var terms: Variant = _normalize_proposal(actor_id, arguments, game_minute)
	if terms == null:
		return _failure("invalid_cooperation_terms")
	var agreement_id := "agreement-%06d" % _next_agreement_id
	var template: Dictionary = _templates[str(terms.objective_id)]
	var progress: Dictionary = {}
	for required in template.required_actions:
		progress[str(required.contribution_id)] = 0
	var agreement := {
		"agreement_id": agreement_id,
		"objective_id": str(terms.objective_id),
		"proposer_id": actor_id,
		"participants": (terms.participants as Array).duplicate(),
		"commitments": (terms.commitments as Array).duplicate(true),
		"reward_split": (terms.reward_split as Dictionary).duplicate(true),
		"deadline": int(terms.deadline),
		"status": "proposed",
		"terms_version": 1,
		"accepted_by": [actor_id],
		"progress": progress,
		"note": str(terms.note),
	}
	var event := _event("AgreementProposed", agreement_id, actor_id, game_minute, str(command.action_id), str(command.decision_id), agreement, agreement.participants)
	var committed := _commit([event], str(command.idempotency_key))
	if not bool(committed.get("ok", false)):
		return committed
	_agreements[agreement_id] = agreement
	_next_agreement_id += 1
	_wake_participants(agreement.participants, actor_id, game_minute)
	return {"ok": true, "agreement_id": agreement_id, "events": committed.events}


func _counter(actor_id: String, arguments: Dictionary, command: Dictionary, game_minute: int) -> Dictionary:
	var agreement_id := str(arguments.get("agreement_id", ""))
	var agreement: Dictionary = _agreements.get(agreement_id, {})
	if agreement.is_empty() or not str(agreement.status) in ["proposed", "negotiating"] or not actor_id in (agreement.participants as Array) or not arguments.get("revised_terms") is Dictionary or typeof(arguments.get("note", "")) != TYPE_STRING:
		return _failure("agreement_not_counterable")
	var revised_source := (arguments.revised_terms as Dictionary).duplicate(true)
	revised_source.objective_id = str(agreement.objective_id)
	var others: Array = (agreement.participants as Array).duplicate()
	others.erase(actor_id)
	revised_source.participants = others
	var revised: Variant = _normalize_proposal(actor_id, revised_source, game_minute)
	if revised == null or revised.participants != agreement.participants:
		return _failure("invalid_cooperation_terms")
	agreement.commitments = (revised.commitments as Array).duplicate(true)
	agreement.reward_split = (revised.reward_split as Dictionary).duplicate(true)
	agreement.deadline = int(revised.deadline)
	agreement.note = str(arguments.note)
	agreement.terms_version = int(agreement.terms_version) + 1
	agreement.accepted_by = [actor_id]
	agreement.status = "negotiating"
	var event := _event("AgreementCountered", agreement_id, actor_id, game_minute, str(command.action_id), str(command.decision_id), agreement, agreement.participants)
	var committed := _commit([event], str(command.idempotency_key))
	if not bool(committed.get("ok", false)):
		return committed
	_agreements[agreement_id] = agreement
	_wake_participants(agreement.participants, actor_id, game_minute)
	return {"ok": true, "agreement_id": agreement_id, "events": committed.events}


func _accept(actor_id: String, arguments: Dictionary, command: Dictionary, game_minute: int) -> Dictionary:
	var agreement_id := str(arguments.get("agreement_id", ""))
	var agreement: Dictionary = _agreements.get(agreement_id, {})
	if agreement.is_empty() or not str(agreement.status) in ["proposed", "negotiating"] or not actor_id in (agreement.participants as Array):
		return _failure("agreement_not_acceptable")
	if int(arguments.get("terms_version", -1)) != int(agreement.terms_version):
		return _failure("stale_agreement_version")
	if actor_id == "player" and arguments.get("player_confirmed") != true:
		return _failure("player_confirmation_required")
	if actor_id in (agreement.accepted_by as Array):
		return _failure("already_accepted")
	var accepted: Array = (agreement.accepted_by as Array).duplicate()
	accepted.append(actor_id)
	accepted.sort()
	var activating := accepted.size() == (agreement.participants as Array).size()
	var acquired: Array[String] = []
	if activating:
		for commitment_value in agreement.commitments:
			var commitment := commitment_value as Dictionary
			if str(commitment.participant_id) == "player" or _bundle_empty(commitment):
				continue
			var reservation_id := _reservation_id(agreement_id, str(commitment.participant_id))
			if not bool(_interactions.call("reserve_assets", str(commitment.participant_id), reservation_id, {"items": commitment.items, "gold": commitment.gold})):
				for acquired_id in acquired:
					_interactions.call("release_reservation", acquired_id)
				return _failure("resource_commitment_unavailable")
			acquired.append(reservation_id)
	var events: Array[Dictionary] = [_event("AgreementAccepted", agreement_id, actor_id, game_minute, str(command.action_id), str(command.decision_id), {"agreement_id": agreement_id, "terms_version": int(agreement.terms_version)}, agreement.participants)]
	if activating:
		events.append(_event("AgreementActivated", agreement_id, actor_id, game_minute, str(command.action_id), str(command.decision_id), {"agreement_id": agreement_id, "terms_version": int(agreement.terms_version)}, agreement.participants))
	var committed := _commit(events, str(command.idempotency_key))
	if not bool(committed.get("ok", false)):
		for acquired_id in acquired:
			_interactions.call("release_reservation", acquired_id)
		return committed
	agreement.accepted_by = accepted
	agreement.status = "active" if activating else str(agreement.status)
	_agreements[agreement_id] = agreement
	_wake_participants(agreement.participants, actor_id, game_minute)
	return {"ok": true, "agreement_id": agreement_id, "activated": activating, "events": committed.events}


func _terminate(actor_id: String, arguments: Dictionary, command: Dictionary, game_minute: int, status: String) -> Dictionary:
	var agreement_id := str(arguments.get("agreement_id", ""))
	var agreement: Dictionary = _agreements.get(agreement_id, {})
	if agreement.is_empty() or not str(agreement.status) in ["proposed", "negotiating", "active"] or not actor_id in (agreement.participants as Array):
		return _failure("agreement_not_terminable")
	if status == "cancelled" and actor_id != str(agreement.proposer_id):
		return _failure("only_proposer_can_cancel")
	var type := "AgreementRejected" if status == "rejected" else "AgreementCancelled"
	var events: Array[Dictionary] = [_event(type, agreement_id, actor_id, game_minute, str(command.action_id), str(command.decision_id), {"agreement_id": agreement_id, "reason_code": str(arguments.get("reason_code", ""))}, agreement.participants)]
	events.append_array(_relationship_events(agreement.participants, -1, game_minute, str(command.action_id)))
	var committed := _commit(events, str(command.idempotency_key))
	if not bool(committed.get("ok", false)):
		return committed
	_release_commitments(agreement)
	agreement.status = status
	_agreements[agreement_id] = agreement
	_adjust_all_relationships(agreement.participants, -1, game_minute)
	_wake_participants(agreement.participants, actor_id, game_minute)
	return {"ok": true, "agreement_id": agreement_id, "events": committed.events}


func _commit_resource_contribution(actor_id: String, arguments: Dictionary, command: Dictionary, game_minute: int) -> Dictionary:
	var agreement_id := str(arguments.get("agreement_id", ""))
	var contribution_id := str(arguments.get("contribution_id", ""))
	var agreement: Dictionary = _agreements.get(agreement_id, {})
	if agreement.is_empty() or str(agreement.status) != "active" or not actor_id in (agreement.participants as Array):
		return _failure("agreement_not_active")
	var events := record_action_outcome({"status": "completed", "agent_id": actor_id, "tool_name": "commit_contribution", "action_id": str(command.action_id), "agreement_id": agreement_id, "contribution_id": contribution_id}, game_minute)
	if events.is_empty():
		return _failure("contribution_not_required")
	return {"ok": true, "agreement_id": agreement_id, "events": events}


func _complete(agreement_id: String, game_minute: int, cause_id: String) -> Dictionary:
	var agreement: Dictionary = _agreements[agreement_id]
	var template: Dictionary = _templates[str(agreement.objective_id)]
	var reward_deltas := _reward_deltas(agreement, int(template.reward_gold), str(template.remainder_policy))
	var snapshots: Dictionary = {}
	var deltas: Dictionary = {}
	for participant_value in agreement.participants:
		var participant := str(participant_value)
		if participant == "player":
			continue
		var state = _economy.call("get_npc_state", participant)
		if state == null:
			return _failure("completion_participant_missing")
		snapshots[participant] = state.to_dict()
		var commitment := _commitment_for(agreement, participant)
		var item_delta: Dictionary = {}
		for item_id in commitment.items:
			item_delta[str(item_id)] = -int(commitment.items[item_id])
		deltas[participant] = {"items": item_delta, "gold": int(reward_deltas.get(participant, 0)) - int(commitment.gold)}
		if not bool(_economy.call("can_apply_agent_asset_delta", participant, item_delta, int(deltas[participant].gold))):
			return _fail_active_agreement(agreement_id, game_minute, "committed_assets_changed")
	for participant in deltas:
		if not bool(_economy.call("apply_agent_asset_delta", str(participant), deltas[participant].items, int(deltas[participant].gold))):
			_restore_snapshots(snapshots)
			return _failure("atomic_completion_failed")
	var events: Array[Dictionary] = [_event("AgreementCompleted", agreement_id, "system", game_minute, cause_id, "agreement:" + agreement_id, {"agreement_id": agreement_id, "reward_gold": int(template.reward_gold), "reward_deltas": reward_deltas}, agreement.participants)]
	events.append_array(_relationship_events(agreement.participants, 2, game_minute, cause_id))
	var committed := _commit(events, "agreement-complete:%s:%s" % [agreement_id, cause_id])
	if not bool(committed.get("ok", false)):
		_restore_snapshots(snapshots)
		return committed
	_release_commitments(agreement)
	agreement.status = "completed"
	_agreements[agreement_id] = agreement
	_adjust_all_relationships(agreement.participants, 2, game_minute)
	_wake_participants(agreement.participants, "", game_minute)
	return {"ok": true, "agreement_id": agreement_id, "events": committed.events}


func _fail_active_agreement(agreement_id: String, game_minute: int, reason: String) -> Dictionary:
	var agreement: Dictionary = _agreements[agreement_id]
	var event := _event("AgreementFailed", agreement_id, "system", game_minute, "failure:" + agreement_id, "agreement:" + agreement_id, {"agreement_id": agreement_id, "reason": reason}, agreement.participants)
	var committed := _commit([event], "agreement-failure:%s:%s" % [agreement_id, reason])
	if not bool(committed.get("ok", false)):
		return committed
	_release_commitments(agreement)
	agreement.status = "failed"
	_agreements[agreement_id] = agreement
	return _failure(reason)


func _normalize_proposal(actor_id: String, value: Dictionary, game_minute: int) -> Variant:
	for field in ["objective_id", "participants", "commitments", "reward_split", "deadline_minutes", "note"]:
		if not value.has(field):
			return null
	var objective_id := str(value.objective_id)
	if not _templates.has(objective_id) or not value.participants is Array or not value.commitments is Array or not value.reward_split is Dictionary or typeof(value.deadline_minutes) != TYPE_INT or typeof(value.note) != TYPE_STRING or str(value.note).length() > 500:
		return null
	var participants: Array[String] = [actor_id]
	for participant_value in value.participants:
		var participant := str(participant_value)
		if not _actor_exists(participant) or participant in participants:
			return null
		participants.append(participant)
	participants.sort()
	var template: Dictionary = _templates[objective_id]
	if participants.size() < int(template.minimum_participants) or participants.size() > int(template.maximum_participants) or int(value.deadline_minutes) < int(template.deadline_minutes[0]) or int(value.deadline_minutes) > int(template.deadline_minutes[1]):
		return null
	var commitments: Array[Dictionary] = []
	var commitment_ids: Array[String] = []
	for commitment_value in value.commitments:
		var commitment: Variant = _normalize_commitment(commitment_value)
		if commitment == null or not str(commitment.participant_id) in participants or str(commitment.participant_id) in commitment_ids:
			return null
		commitment_ids.append(str(commitment.participant_id))
		commitments.append(commitment)
	commitment_ids.sort()
	if commitment_ids != participants:
		return null
	var reward_split: Dictionary = {}
	for participant in participants:
		var weight: Variant = value.reward_split.get(participant)
		if typeof(weight) != TYPE_INT or int(weight) <= 0 or int(weight) > 1000:
			return null
		reward_split[participant] = int(weight)
	if (value.reward_split as Dictionary).size() != participants.size():
		return null
	return {"objective_id": objective_id, "participants": participants, "commitments": commitments, "reward_split": reward_split, "deadline": game_minute + int(value.deadline_minutes), "note": str(value.note)}


func _normalize_commitment(value: Variant) -> Variant:
	if not value is Dictionary or value.size() != 3 or typeof(value.get("participant_id")) != TYPE_STRING or not value.get("items") is Dictionary or typeof(value.get("gold")) != TYPE_INT or int(value.gold) < 0:
		return null
	var items: Dictionary = {}
	for item_id_value in value.items:
		var item_id := str(item_id_value)
		if not bool(_economy.call("has_item", item_id)) or typeof(value.items[item_id_value]) != TYPE_INT or int(value.items[item_id_value]) <= 0 or int(value.items[item_id_value]) > MAX_QUANTITY:
			return null
		items[item_id] = int(value.items[item_id_value])
	return {"participant_id": str(value.participant_id), "items": items, "gold": int(value.gold)}


func _normalize_templates(value: Variant) -> Variant:
	if not value is Dictionary or value.get("version") != VERSION or not value.get("templates") is Array:
		return null
	var result: Dictionary = {}
	for template_value in value.templates:
		if not template_value is Dictionary:
			return null
		var template := template_value as Dictionary
		for field in ["objective_id", "display_name", "minimum_participants", "maximum_participants", "deadline_minutes", "required_actions", "reward_gold", "remainder_policy", "refund_policy"]:
			if not template.has(field):
				return null
		var objective_id := str(template.objective_id)
		if objective_id.is_empty() or result.has(objective_id) or not template.deadline_minutes is Array or template.deadline_minutes.size() != 2 or not template.required_actions is Array or template.required_actions.is_empty() or int(template.reward_gold) < 0 or str(template.remainder_policy) != "proposer" or str(template.refund_policy) != "full_before_completion":
			return null
		result[objective_id] = template.duplicate(true)
	return result


func _milestones_complete(agreement: Dictionary, template: Dictionary) -> bool:
	for required in template.required_actions:
		if int((agreement.progress as Dictionary).get(str(required.contribution_id), 0)) < int(required.count):
			return false
	return true


func _reward_deltas(agreement: Dictionary, reward_gold: int, remainder_policy: String) -> Dictionary:
	var total_weight := 0
	for weight in (agreement.reward_split as Dictionary).values():
		total_weight += int(weight)
	var result: Dictionary = {}
	var allocated := 0
	for participant in agreement.participants:
		var share := reward_gold * int(agreement.reward_split[participant]) / total_weight
		result[str(participant)] = share
		allocated += share
	if remainder_policy == "proposer":
		result[str(agreement.proposer_id)] = int(result.get(str(agreement.proposer_id), 0)) + reward_gold - allocated
	return result


func _commitment_for(agreement: Dictionary, participant_id: String) -> Dictionary:
	for value in agreement.commitments:
		if str(value.participant_id) == participant_id:
			return (value as Dictionary).duplicate(true)
	return {"participant_id": participant_id, "items": {}, "gold": 0}


func _bundle_empty(commitment: Dictionary) -> bool:
	return int(commitment.gold) == 0 and (commitment.items as Dictionary).is_empty()


func _release_commitments(agreement: Dictionary) -> void:
	for participant in agreement.participants:
		if str(participant) != "player":
			_interactions.call("release_reservation", _reservation_id(str(agreement.agreement_id), str(participant)))


func _reservation_id(agreement_id: String, participant_id: String) -> String:
	return "agreement:%s:%s" % [agreement_id, participant_id]


func _restore_snapshots(snapshots: Dictionary) -> void:
	for participant in snapshots:
		_economy.call("get_npc_state", str(participant)).from_dict(snapshots[participant])


func _adjust_all_relationships(participants: Array, delta: int, game_minute: int) -> void:
	for left_index in range(participants.size()):
		for right_index in range(left_index + 1, participants.size()):
			var key := _pair_key(str(participants[left_index]), str(participants[right_index]))
			var day := int(game_minute / 1080) + 1
			var daily_key := "%d:%s" % [day, key]
			var used := int(_relationship_daily_changes.get(daily_key, 0))
			var applied := clampi(delta, -3 - used, 3 - used)
			_relationship_daily_changes[daily_key] = used + applied
			_relationships[key] = clampi(int(_relationships.get(key, 0)) + applied, -100, 100)


func _relationship_events(participants: Array, delta: int, game_minute: int, command_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for left_index in range(participants.size()):
		for right_index in range(left_index + 1, participants.size()):
			var left_id := str(participants[left_index])
			var right_id := str(participants[right_index])
			var key := _pair_key(left_id, right_id)
			events.append({"event_type": "RelationshipChanged", "aggregate_type": "relationship", "aggregate_id": key.replace("\n", ":"), "actor_id": "system", "game_minute": game_minute, "command_id": command_id, "correlation_id": "relationship:" + key.replace("\n", ":"), "causation_event_id": "", "visibility": {"scope": "participants", "actor_ids": [left_id, right_id]}, "payload": {"left_id": left_id, "right_id": right_id, "delta": delta, "reason": "cooperation"}})
	return events


func _pair_key(left_id: String, right_id: String) -> String:
	var ids := [left_id, right_id]
	ids.sort()
	return "%s\n%s" % ids


func _wake_participants(participants: Array, exclude_id: String, game_minute: int) -> void:
	if not _wake_agent.is_valid():
		return
	for participant in participants:
		if str(participant) != exclude_id and str(participant) != "player":
			_wake_agent.call(str(participant), 3, game_minute)


func _actor_exists(actor_id: String) -> bool:
	return not actor_id.is_empty() and not (_projector.call("get_actor", actor_id) as Dictionary).is_empty()


func _commit(events: Array[Dictionary], key: String) -> Dictionary:
	var committed: Dictionary = _store.call("append_batch", events, key)
	if not bool(committed.get("ok", false)):
		return _failure(str(committed.get("error", "event_commit_failed")))
	var committed_events: Array[Dictionary] = []
	committed_events.assign(committed.events)
	if not bool(_projector.call("apply_batch", committed_events)):
		return _failure("event_projection_failed")
	return {"ok": true, "events": committed_events}


func _event(event_type: String, agreement_id: String, actor_id: String, game_minute: int, command_id: String, correlation_id: String, payload: Dictionary, participants: Array) -> Dictionary:
	return {"event_type": event_type, "aggregate_type": "agreement", "aggregate_id": agreement_id, "actor_id": actor_id, "game_minute": game_minute, "command_id": command_id, "correlation_id": correlation_id, "causation_event_id": "", "visibility": {"scope": "participants", "actor_ids": participants.duplicate()}, "payload": payload.duplicate(true)}


func _remember(key: String, result: Dictionary) -> Dictionary:
	_results[key] = result.duplicate(true)
	return result


func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
