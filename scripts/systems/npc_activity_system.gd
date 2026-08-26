extends RefCounted

const VERSION := 1
var _activities: Dictionary = {}


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
		record.status = "completed"
		record["completed_minute"] = game_minute
		completed.append(record.duplicate(true))
	return completed


func to_dict() -> Dictionary:
	return {"version": VERSION, "activities": _activities.duplicate(true)}


func from_dict(value: Dictionary) -> bool:
	if value.get("version") != VERSION or not value.get("activities") is Dictionary:
		return false
	var candidate: Dictionary = {}
	for id_value in (value.activities as Dictionary).keys():
		var record_value: Variant = value.activities[id_value]
		if not record_value is Dictionary:
			return false
		var record := record_value as Dictionary
		var activity_id := str(id_value)
		if activity_id.is_empty() or str(record.get("activity_id", "")) != activity_id or str(record.get("agent_id", "")).is_empty() or not ["in_progress", "completed", "failed"].has(str(record.get("status", ""))):
			return false
		candidate[activity_id] = record.duplicate(true)
	_activities = candidate
	return true
