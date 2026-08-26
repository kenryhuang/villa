extends RefCounted

const VERSION := 1
var _private: Dictionary = {}
var _public: Dictionary = {}


func discover(agent_id: String, discovery_id: String, region_id: String, game_minute: int) -> bool:
	if agent_id.is_empty() or discovery_id.is_empty() or region_id.is_empty() or game_minute < 0:
		return false
	if not _private.has(agent_id):
		_private[agent_id] = {}
	var memories: Dictionary = _private[agent_id]
	if memories.has(discovery_id):
		return false
	memories[discovery_id] = {"discovery_id": discovery_id, "region_id": region_id, "discovered_minute": game_minute, "published": false}
	return true


func publish(agent_id: String, discovery_id: String, game_minute: int) -> bool:
	if not _private.has(agent_id):
		return false
	var memories: Dictionary = _private[agent_id]
	if not memories.has(discovery_id) or _public.has(discovery_id):
		return false
	var record: Dictionary = memories[discovery_id]
	record.published = true
	record["published_minute"] = game_minute
	_public[discovery_id] = record.duplicate(true)
	return true


func is_public(discovery_id: String) -> bool:
	return _public.has(discovery_id)


func get_private(agent_id: String) -> Dictionary:
	return (_private.get(agent_id, {}) as Dictionary).duplicate(true)


func to_dict() -> Dictionary:
	return {"version": VERSION, "private": _private.duplicate(true), "public": _public.duplicate(true)}


func from_dict(value: Dictionary) -> bool:
	if value.get("version") != VERSION or not value.get("private") is Dictionary or not value.get("public") is Dictionary:
		return false
	_private = (value.private as Dictionary).duplicate(true)
	_public = (value.public as Dictionary).duplicate(true)
	return true
