class_name AgentSessionTrace
extends Node

signal trace_updated(request_id: String)
signal trace_cleared

const MAX_REQUESTS := 100
const MAX_SESSION_FILES := 20
const DEFAULT_DIRECTORY := "user://agent_sessions"
const RECORD_SCHEMA_VERSION := 2

var _requests: Array[Dictionary] = []
var _request_indexes: Dictionary = {}
var _terminal_requests: Dictionary = {}
var _store_to_disk := false
var _directory := DEFAULT_DIRECTORY
var _log_path := ""
var _log_file: FileAccess


func configure(
	store_to_disk: bool,
	session_id: String,
	directory: String = DEFAULT_DIRECTORY
) -> bool:
	close()
	_requests.clear()
	_request_indexes.clear()
	_terminal_requests.clear()
	_store_to_disk = store_to_disk
	_directory = directory
	_log_path = ""
	if not _store_to_disk:
		return true
	if directory.strip_edges().is_empty():
		return false
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK and error != ERR_ALREADY_EXISTS:
		return false
	var safe_session := _safe_file_part(session_id)
	var stamp := "%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	_log_path = directory.path_join("%s-%s.ndjson" % [safe_session, stamp])
	_log_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log_file == null:
		_log_path = ""
		return false
	_prune_session_files()
	return true


func accept_event(event: Dictionary) -> bool:
	if not _valid_event(event):
		return false
	var data := event.data as Dictionary
	var request_id := str(data.request_id)
	if _terminal_requests.has(request_id):
		return true
	var index := int(_request_indexes.get(request_id, -1))
	if index < 0:
		index = _append_record(
			request_id,
			str(data.get("stream_id", "")),
			str(data.get("agent_id", "")),
			"",
			int(data.get("timestamp_msec", 0))
		)
		if index < 0:
			return false
	var record := _requests[index]
	var event_name := str(event.event)
	var payload := data.payload as Dictionary
	record.updated_msec = int(data.timestamp_msec)
	match event_name:
		"stream.started":
			record.trigger = str(payload.get("trigger", ""))
		"provider.input":
			record.input = payload.duplicate(true)
		"reasoning.delta":
			(record.reasoning_parts as Array).append(str(payload.get("delta", "")))
		"content.delta":
			(record.content_parts as Array).append(str(payload.get("delta", "")))
		"tool_call.delta":
			(record.tool_deltas as Array).append(payload.duplicate(true))
		"provider.output":
			record.output = payload.duplicate(true)
		"decision.final":
			record.final = payload.duplicate(true)
		"stream.completed":
			record.status = "completed"
		"stream.error":
			record.status = "error"
			record.error = payload.duplicate(true)
	_requests[index] = record
	if event_name in ["stream.completed", "stream.error"]:
		_persist_terminal(request_id)
	trace_updated.emit(request_id)
	return true


func finish_error(
	agent_id: String,
	request_id: String,
	error: String,
	trigger: String = "",
	timestamp_msec: int = -1
) -> bool:
	if agent_id.strip_edges().is_empty() or request_id.strip_edges().is_empty():
		return false
	if _terminal_requests.has(request_id):
		return true
	var resolved_timestamp := timestamp_msec
	if resolved_timestamp < 0:
		resolved_timestamp = int(Time.get_unix_time_from_system() * 1000.0)
	var index := int(_request_indexes.get(request_id, -1))
	if index < 0:
		index = _append_record(request_id, "", agent_id, trigger, resolved_timestamp)
		if index < 0:
			return false
	var record := _requests[index]
	if str(record.trigger).is_empty():
		record.trigger = trigger
	record.updated_msec = resolved_timestamp
	record.status = "error"
	record.error = {"code": error if not error.is_empty() else "unknown_error"}
	_requests[index] = record
	_persist_terminal(request_id)
	trace_updated.emit(request_id)
	return true


func get_requests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in _requests:
		result.append(_materialize_record(record))
	return result


func get_request(request_id: String) -> Dictionary:
	var index := int(_request_indexes.get(request_id, -1))
	return {} if index < 0 else _materialize_record(_requests[index])


func get_log_path() -> String:
	return _log_path


func clear() -> void:
	_requests.clear()
	_request_indexes.clear()
	trace_cleared.emit()


func close() -> void:
	if _log_file != null:
		_log_file.flush()
		_log_file.close()
		_log_file = null


func _exit_tree() -> void:
	close()


func _append_record(
	request_id: String,
	stream_id: String,
	agent_id: String,
	trigger: String,
	timestamp_msec: int
) -> int:
	var index := _requests.size()
	_request_indexes[request_id] = index
	_requests.append({
		"request_id": request_id,
		"stream_id": stream_id,
		"agent_id": agent_id,
		"trigger": trigger,
		"started_msec": timestamp_msec,
		"updated_msec": timestamp_msec,
		"status": "streaming",
		"input": {},
		"reasoning": "",
		"content": "",
		"reasoning_parts": [],
		"content_parts": [],
		"tool_deltas": [],
		"output": {},
		"final": {},
		"error": {},
	})
	_trim_memory()
	return int(_request_indexes.get(request_id, -1))


func _persist_terminal(request_id: String) -> void:
	if _terminal_requests.has(request_id):
		return
	var index := int(_request_indexes.get(request_id, -1))
	if index < 0:
		return
	_terminal_requests[request_id] = true
	if _log_file == null:
		return
	_log_file.store_line(JSON.stringify(_disk_record(_requests[index])))
	_log_file.flush()


func _disk_record(record: Dictionary) -> Dictionary:
	var materialized := _materialize_record(record)
	return {
		"schema_version": RECORD_SCHEMA_VERSION,
		"request_id": str(materialized.request_id),
		"stream_id": str(materialized.stream_id),
		"agent_id": str(materialized.agent_id),
		"trigger": str(materialized.trigger),
		"status": str(materialized.status),
		"started_msec": int(materialized.started_msec),
		"updated_msec": int(materialized.updated_msec),
		"input": (materialized.input as Dictionary).duplicate(true),
		"response": {
			"reasoning_content": str(materialized.reasoning),
			"content": str(materialized.content),
			"tool_call_deltas": (materialized.tool_deltas as Array).duplicate(true),
			"provider_output": (materialized.output as Dictionary).duplicate(true),
			"decision": (materialized.final as Dictionary).duplicate(true),
			"error": (materialized.error as Dictionary).duplicate(true),
		},
	}


func _materialize_record(record: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	if result.has("reasoning_parts"):
		result.reasoning = "".join(PackedStringArray(result.reasoning_parts))
		result.erase("reasoning_parts")
	if result.has("content_parts"):
		result.content = "".join(PackedStringArray(result.content_parts))
		result.erase("content_parts")
	return result


func _trim_memory() -> void:
	while _requests.size() > MAX_REQUESTS:
		_requests.pop_front()
		_rebuild_indexes()


func _rebuild_indexes() -> void:
	_request_indexes.clear()
	for index in range(_requests.size()):
		_request_indexes[str(_requests[index].request_id)] = index


func _prune_session_files() -> void:
	var files: Array[String] = []
	for file_name in DirAccess.get_files_at(_directory):
		if str(file_name).ends_with(".ndjson"):
			files.append(str(file_name))
	files.sort_custom(func(left: String, right: String) -> bool:
		var left_path := _directory.path_join(left)
		var right_path := _directory.path_join(right)
		var left_time := FileAccess.get_modified_time(left_path)
		var right_time := FileAccess.get_modified_time(right_path)
		return left_time < right_time or (left_time == right_time and left < right)
	)
	while files.size() > MAX_SESSION_FILES:
		var oldest: String = files.pop_front()
		var oldest_path := _directory.path_join(oldest)
		if oldest_path != _log_path:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(oldest_path))


func _safe_file_part(value: String) -> String:
	var result := ""
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789-_":
			result += character
		else:
			result += "_"
	return "session" if result.is_empty() else result


func _valid_event(event: Dictionary) -> bool:
	return (
		typeof(event.get("event")) == TYPE_STRING
		and event.get("data") is Dictionary
		and typeof((event.data as Dictionary).get("request_id")) == TYPE_STRING
		and (event.data as Dictionary).get("payload") is Dictionary
	)
