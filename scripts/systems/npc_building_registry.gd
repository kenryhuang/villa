extends RefCounted

const VERSION := 1
var _buildings: Dictionary = {}


func add_building(agent_id: String, building_type: String, building_id: String, completed_minute: int) -> bool:
	if agent_id.is_empty() or building_type.is_empty() or building_id.is_empty() or completed_minute < 0 or _buildings.has(building_id):
		return false
	_buildings[building_id] = {"building_id": building_id, "agent_id": agent_id, "building_type": building_type, "completed_minute": completed_minute}
	return true


func get_building(building_id: String) -> Dictionary:
	return (_buildings.get(building_id, {}) as Dictionary).duplicate(true)


func to_dict() -> Dictionary:
	return {"version": VERSION, "buildings": _buildings.duplicate(true)}


func from_dict(value: Dictionary) -> bool:
	if value.get("version") != VERSION or not value.get("buildings") is Dictionary:
		return false
	var candidate: Dictionary = {}
	for building_id_value in (value.buildings as Dictionary).keys():
		var record_value: Variant = value.buildings[building_id_value]
		if not record_value is Dictionary:
			return false
		var record := record_value as Dictionary
		var building_id := str(building_id_value)
		if building_id.is_empty() or str(record.get("building_id", "")) != building_id or str(record.get("agent_id", "")).is_empty() or str(record.get("building_type", "")).is_empty() or int(record.get("completed_minute", -1)) < 0:
			return false
		candidate[building_id] = record.duplicate(true)
	_buildings = candidate
	return true
