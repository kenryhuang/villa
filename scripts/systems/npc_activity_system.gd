extends RefCounted

const VERSION := 1
var _activities: Dictionary = {}
var completion_guard: Callable
var action_completion_guard: Callable


func start(agent_id: String, kind: String, activity_id: String, started_minute: int, complete_at_minute: int, payload: Dictionary) -> bool:
	if agent_id.is_empty() or kind.is_empty() or activity_id.is_empty() or started_minute < 0 or complete_at_minute <= started_minute or _activities.has(activity_id) or is_busy(agent_id):
		return false
	_activities[activity_id] = {"activity_id": activity_id, "agent_id": agent_id, "kind": kind, "started_minute": started_minute, "complete_at_minute": complete_at_minute, "status": "in_progress", "payload": payload.duplicate(true)}
	return true


func is_busy(agent_id: String) -> bool:
	for record_value in _activities.values():
		var record := record_value as Dictionary
		if record.agent_id == agent_id and record.status == "in_progress":
			return true
	return false


func complete_due(game_minute: int) -> Array[Dictionary]:
	var completed: Array[Dictionary] = []
	var ids := _activities.keys()
	ids.sort()
	for activity_id in ids:
		var record: Dictionary = _activities[activity_id]
		if record.status != "in_progress" or int(record.complete_at_minute) > game_minute:
			continue
		var result := {"ready": true, "ok": true}
		if record.payload.get("physical_action", false):
			if not action_completion_guard.is_valid(): continue
			result = action_completion_guard.call(record, game_minute)
			if not result.get("ready", false): continue
			record.execution_result = result.get("execution_result", {"ok": false, "error": "action_failed"}).duplicate(true)
		elif record.payload.get("physical", false):
			if not completion_guard.is_valid(): continue
			result = completion_guard.call(record, game_minute)
			if not result.get("ready", false): continue
		record.status = "completed" if result.get("ok", false) else "failed"
		if not result.get("ok", false): record.payload.error = str(result.get("error", "activity_failed"))
		record["completed_minute"] = game_minute
		completed.append(record.duplicate(true))
	return completed


func to_dict() -> Dictionary:
	return {"version": VERSION, "activities": _activities.duplicate(true)}


func from_dict(value: Dictionary) -> bool:
	if value.get("version") != VERSION or not value.get("activities") is Dictionary:
		return false
	var candidate: Dictionary = {}
	var occupied := {}
	for id_value in (value.activities as Dictionary).keys():
		var record_value: Variant = value.activities[id_value]
		if not record_value is Dictionary:
			return false
		var record := record_value as Dictionary
		var activity_id := str(id_value)
		if activity_id.is_empty() or str(record.get("activity_id", "")) != activity_id or str(record.get("agent_id", "")).is_empty() or not ["in_progress", "completed", "failed"].has(str(record.get("status", ""))):
			return false
		if record.status == "in_progress":
			if occupied.has(record.agent_id): return false
			occupied[record.agent_id] = true
		if not record.get("payload") is Dictionary: return false
		if record.payload.get("physical_action", false):
			var p: Dictionary = record.payload
			var rules = preload("res://scripts/systems/npc_project_system.gd")
			if record.get("kind") not in ["move", "buy", "sell", "prepare_supplies", "rent_production"] or not p.get("intent") is Dictionary or not p.get("movement") is Dictionary: return false
			if p.intent.get("agent_id") != record.agent_id or p.intent.get("tool_name") != record.kind or p.intent.get("idempotency_key") != activity_id: return false
			if not p.intent.get("arguments") is Dictionary or not preload("res://scripts/ai_agent/agent_action_validator.gd").new()._valid_arguments(record.kind, p.intent.arguments): return false
			if not rules._count(record.get("started_minute"), 0, 9007199254740991) or not rules._count(record.get("complete_at_minute"), int(record.started_minute), 9007199254740991) or not rules._count(p.get("deadline"), int(record.complete_at_minute), 9007199254740991): return false
			if p.movement.has("target") and (not p.movement.target is Dictionary or not rules.valid_step("move", p.movement.target)): return false
			if record.status != "in_progress" and not record.get("execution_result") is Dictionary: return false
		if record.payload.get("physical", false):
			var rules = preload("res://scripts/systems/npc_project_system.gd")
			var p: Dictionary = record.payload
			if record.get("kind") not in ["travel", "survey"] or not rules._count(record.get("started_minute"), 0, 9007199254740991) or not rules._count(record.get("complete_at_minute"), int(record.started_minute), 9007199254740991): return false
			if not p.get("target") is Dictionary or p.target.size() != 2 or not rules._number(p.target.get("x"), -176, 80) or not rules._number(p.target.get("z"), -80, 144) or not p.get("region_id") is String: return false
			for field in ["worked", "last_minute", "deadline"]:
				if not rules._count(p.get(field), 0, 9007199254740991): return false
			if record.status == "completed":
				if not rules._count(record.get("completed_minute"), int(record.complete_at_minute), 9007199254740991): return false
				if record.kind == "survey" and (int(p.worked) < 20 or not rules._id(p.get("discovery_id"))): return false
		candidate[activity_id] = record.duplicate(true)
	_activities = candidate
	return true
