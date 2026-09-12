class_name AgentWorldEventStore
extends RefCounted

const AgentWorldEventScript = preload("res://scripts/data/agent_world_event.gd")
const STORE_VERSION := 1

var _events: Array[Dictionary] = []
var _aggregate_versions: Dictionary = {}
var _idempotency_results: Dictionary = {}
var _next_global_sequence := 1
var transient_history_limit := 0


func start_from_snapshot(sequence: int, history_limit := 128) -> void:
	_events.clear()
	_aggregate_versions.clear()
	_idempotency_results.clear()
	_next_global_sequence = sequence + 1
	transient_history_limit = history_limit


func _trim_transient_history() -> void:
	if transient_history_limit <= 0: return
	if _events.size() > transient_history_limit:
		_events = _events.slice(_events.size() - transient_history_limit)
	# Business-level settlement receipts remain in the executor/trade systems.
	# This cache only deduplicates recent event publications within this session.
	while _idempotency_results.size() > transient_history_limit:
		_idempotency_results.erase(_idempotency_results.keys()[0])


func append_batch(events: Array[Dictionary], idempotency_key: String) -> Dictionary:
	var normalized_key := idempotency_key.strip_edges()
	if normalized_key.is_empty():
		return _failure("invalid_idempotency_key")
	if _idempotency_results.has(normalized_key):
		return (_idempotency_results[normalized_key] as Dictionary).duplicate(true)
	if events.is_empty():
		return _failure("invalid_events")

	var normalized_events: Array[Dictionary] = []
	for value in events:
		var normalized := AgentWorldEventScript.normalize_candidate(value)
		if not bool(normalized.get("ok", false)):
			return normalized
		normalized_events.append((normalized.value as Dictionary).duplicate(true))

	var candidate_versions := _aggregate_versions.duplicate(true)
	var committed: Array[Dictionary] = []
	for index in range(normalized_events.size()):
		var event := normalized_events[index].duplicate(true)
		var aggregate_key := _aggregate_key(str(event.aggregate_type), str(event.aggregate_id))
		var aggregate_version := int(candidate_versions.get(aggregate_key, 0)) + 1
		candidate_versions[aggregate_key] = aggregate_version
		var sequence := _next_global_sequence + index
		event["event_schema_version"] = AgentWorldEventScript.EVENT_SCHEMA_VERSION
		event["event_id"] = _event_id(sequence)
		event["global_sequence"] = sequence
		event["aggregate_version"] = aggregate_version
		event["idempotency_key"] = normalized_key
		committed.append(event)

	var result := {
		"ok": true,
		"events": committed.duplicate(true),
		"last_sequence": _next_global_sequence + committed.size() - 1,
	}
	_events.append_array(committed)
	_aggregate_versions = candidate_versions
	_next_global_sequence += committed.size()
	_idempotency_results[normalized_key] = result.duplicate(true)
	return result.duplicate(true)


func append_projected_batch(events: Array[Dictionary], idempotency_key: String, projector: Variant) -> Dictionary:
	if projector == null or not projector.has_method("get_last_sequence") or not projector.has_method("apply_batch"):
		return _failure("invalid_projector")
	var store_sequence := get_last_sequence()
	if int(projector.call("get_last_sequence")) != store_sequence:
		return _failure("event_projection_out_of_sync")
	var normalized_key := idempotency_key.strip_edges()
	var cached := get_idempotent_result(normalized_key)
	if not cached.is_empty():
		return cached
	# append_batch only appends events/new keys and replaces the version table.
	# Keep a rollback cursor instead of copying the entire event history per trade.
	var before_count := _events.size()
	var before_versions := _aggregate_versions
	var before_sequence := _next_global_sequence
	var before_keys := _idempotency_results.size()
	var projector_before: Dictionary = projector.call("to_dict") if projector.has_method("to_dict") else {}
	var committed := append_batch(events, idempotency_key)
	if not bool(committed.get("ok", false)):
		return committed
	var committed_events: Array[Dictionary] = []
	committed_events.assign(committed.events)
	if bool(projector.call("apply_batch", committed_events)):
		_trim_transient_history()
		return committed
	_events.resize(before_count)
	_aggregate_versions = before_versions
	_next_global_sequence = before_sequence
	for key in _idempotency_results.keys().slice(before_keys): _idempotency_results.erase(key)
	if not projector_before.is_empty() and projector.has_method("from_dict"):
		projector.call("from_dict", projector_before)
	return _failure("event_projection_failed")


func get_events_after(sequence: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in _events:
		if int(event.global_sequence) > sequence:
			result.append(event.duplicate(true))
	return result


func get_last_sequence() -> int:
	return _next_global_sequence - 1


func get_aggregate_version(aggregate_type: String, aggregate_id: String) -> int:
	return int(_aggregate_versions.get(_aggregate_key(aggregate_type, aggregate_id), 0))


func get_idempotent_result(idempotency_key: String) -> Dictionary:
	return (_idempotency_results.get(idempotency_key, {}) as Dictionary).duplicate(true)


func to_dict() -> Dictionary:
	var aggregate_records: Array[Dictionary] = []
	var aggregate_keys := _aggregate_versions.keys()
	aggregate_keys.sort()
	for key_value in aggregate_keys:
		var parts := str(key_value).split("\n", true, 1)
		aggregate_records.append({
			"aggregate_type": parts[0],
			"aggregate_id": parts[1],
			"version": int(_aggregate_versions[key_value]),
		})
	var idempotency_records: Array[Dictionary] = []
	var idempotency_keys := _idempotency_results.keys()
	idempotency_keys.sort()
	for key_value in idempotency_keys:
		idempotency_records.append({
			"idempotency_key": str(key_value),
			"result": (_idempotency_results[key_value] as Dictionary).duplicate(true),
		})
	return {
		"version": STORE_VERSION,
		"next_global_sequence": _next_global_sequence,
		"events": _events.duplicate(true),
		"aggregate_versions": aggregate_records,
		"idempotency_results": idempotency_records,
	}


func validate_dict(value: Dictionary) -> bool:
	return _normalize_store(value) != null


func from_dict(value: Dictionary) -> bool:
	var normalized: Variant = _normalize_store(value)
	if normalized == null:
		return false
	_events.assign(normalized.events)
	_aggregate_versions = normalized.aggregate_versions
	_idempotency_results = normalized.idempotency_results
	_next_global_sequence = int(normalized.next_global_sequence)
	return true


func _normalize_store(value: Dictionary) -> Variant:
	var fields := ["version", "next_global_sequence", "events", "aggregate_versions", "idempotency_results"]
	if value.size() != fields.size():
		return null
	for field in fields:
		if not value.has(field):
			return null
	if value.version != STORE_VERSION or not _is_positive_integer(value.next_global_sequence):
		return null
	if not value.events is Array or not value.aggregate_versions is Array or not value.idempotency_results is Array:
		return null

	var normalized_events: Array[Dictionary] = []
	var computed_versions: Dictionary = {}
	var events_by_idempotency: Dictionary = {}
	var expected_sequence := 1
	for event_value in value.events:
		if not event_value is Dictionary:
			return null
		var event := event_value as Dictionary
		if (
			event.get("event_schema_version") != AgentWorldEventScript.EVENT_SCHEMA_VERSION
			or not _is_positive_integer(event.get("global_sequence"))
			or int(event.global_sequence) != expected_sequence
			or str(event.get("event_id", "")) != _event_id(expected_sequence)
			or not _is_positive_integer(event.get("aggregate_version"))
			or typeof(event.get("idempotency_key")) != TYPE_STRING
			or str(event.idempotency_key).strip_edges().is_empty()
		):
			return null
		var candidate := event.duplicate(true)
		for assigned_field in ["event_schema_version", "event_id", "global_sequence", "aggregate_version", "idempotency_key"]:
			candidate.erase(assigned_field)
		var normalized := AgentWorldEventScript.normalize_candidate(candidate)
		if not bool(normalized.get("ok", false)):
			return null
		var canonical := (normalized.value as Dictionary).duplicate(true)
		canonical["event_schema_version"] = AgentWorldEventScript.EVENT_SCHEMA_VERSION
		canonical["event_id"] = str(event.event_id)
		canonical["global_sequence"] = int(event.global_sequence)
		canonical["aggregate_version"] = int(event.aggregate_version)
		canonical["idempotency_key"] = str(event.idempotency_key)
		canonical["payload"] = _canonical_json_value(canonical.payload)
		var aggregate_key := _aggregate_key(str(canonical.aggregate_type), str(canonical.aggregate_id))
		var expected_version := int(computed_versions.get(aggregate_key, 0)) + 1
		if int(canonical.aggregate_version) != expected_version:
			return null
		computed_versions[aggregate_key] = expected_version
		var key := str(canonical.idempotency_key)
		if not events_by_idempotency.has(key):
			events_by_idempotency[key] = []
		(events_by_idempotency[key] as Array).append(canonical.duplicate(true))
		normalized_events.append(canonical)
		expected_sequence += 1
	if int(value.next_global_sequence) != expected_sequence:
		return null

	var normalized_versions: Dictionary = {}
	var last_aggregate_key := ""
	for record_value in value.aggregate_versions:
		if not record_value is Dictionary:
			return null
		var record := record_value as Dictionary
		if record.size() != 3 or not record.has("aggregate_type") or not record.has("aggregate_id") or not record.has("version"):
			return null
		if typeof(record.aggregate_type) != TYPE_STRING or typeof(record.aggregate_id) != TYPE_STRING or not _is_positive_integer(record.version):
			return null
		var aggregate_key := _aggregate_key(str(record.aggregate_type), str(record.aggregate_id))
		if aggregate_key <= last_aggregate_key or normalized_versions.has(aggregate_key):
			return null
		last_aggregate_key = aggregate_key
		normalized_versions[aggregate_key] = int(record.version)
	if normalized_versions != computed_versions:
		return null

	var normalized_results: Dictionary = {}
	var last_idempotency_key := ""
	for record_value in value.idempotency_results:
		if not record_value is Dictionary:
			return null
		var record := record_value as Dictionary
		if record.size() != 2 or typeof(record.get("idempotency_key")) != TYPE_STRING or not record.get("result") is Dictionary:
			return null
		var idempotency_key := str(record.idempotency_key)
		if idempotency_key.strip_edges().is_empty() or idempotency_key <= last_idempotency_key or normalized_results.has(idempotency_key):
			return null
		last_idempotency_key = idempotency_key
		if not events_by_idempotency.has(idempotency_key):
			return null
		var expected_result := {
			"ok": true,
			"events": (events_by_idempotency[idempotency_key] as Array).duplicate(true),
			"last_sequence": int((events_by_idempotency[idempotency_key] as Array)[-1].global_sequence),
		}
		var result := record.result as Dictionary
		if result.size() != 3 or result.get("ok") != true or not result.get("events") is Array or not _is_positive_integer(result.get("last_sequence")):
			return null
		if (result.events as Array).size() != (expected_result.events as Array).size():
			return null
		for event_index in range((expected_result.events as Array).size()):
			var result_event := (result.events as Array)[event_index] as Dictionary
			var expected_event := (expected_result.events as Array)[event_index] as Dictionary
			if not _events_equivalent(result_event, expected_event):
				return null
		if int(result.last_sequence) != int(expected_result.last_sequence):
			return null
		normalized_results[idempotency_key] = expected_result
	if normalized_results.size() != events_by_idempotency.size():
		return null

	return {
		"events": normalized_events,
		"aggregate_versions": normalized_versions,
		"idempotency_results": normalized_results,
		"next_global_sequence": expected_sequence,
	}


func _aggregate_key(aggregate_type: String, aggregate_id: String) -> String:
	return "%s\n%s" % [aggregate_type, aggregate_id]


func _event_id(sequence: int) -> String:
	return "evt-%08d" % sequence


func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}


func _events_equivalent(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for field in right:
		if not left.has(field):
			return false
		if field in ["event_schema_version", "global_sequence", "aggregate_version"]:
			if not _is_positive_integer(left[field]) or int(left[field]) != int(right[field]):
				return false
		elif field == "game_minute":
			if not _is_nonnegative_integer(left[field]) or int(left[field]) != int(right[field]):
				return false
		elif _canonical_json_value(left[field]) != _canonical_json_value(right[field]):
			return false
	return true


func _canonical_json_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)) and floorf(float(value)) == float(value):
		return int(value)
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonical_json_value(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = _canonical_json_value(value[key])
		return result
	return value


func _is_positive_integer(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
		and int(value) > 0
	)


func _is_nonnegative_integer(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
		and int(value) >= 0
	)
