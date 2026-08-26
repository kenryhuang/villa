class_name AgentSessionTrace
extends Node

signal trace_updated(request_id: String)
signal trace_cleared

const MAX_REQUESTS := 100
const MAX_SESSION_FILES := 20
const DEFAULT_DIRECTORY := "user://agent_sessions"

var _requests: Array[Dictionary] = []
var _request_indexes: Dictionary = {}
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
	var index := int(_request_indexes.get(request_id, -1))
	if index < 0:
		index = _requests.size()
		_request_indexes[request_id] = index
		_requests.append({
			"request_id": request_id,
			"stream_id": str(data.stream_id),
			"agent_id": str(data.agent_id),
			"trigger": "",
			"started_msec": int(data.timestamp_msec),
			"updated_msec": int(data.timestamp_msec),
			"status": "streaming",
			"input": {},
			"reasoning": "",
			"content": "",
			"tool_deltas": [],
			"output": {},
			"final": {},
		})
		_trim_memory()
		index = int(_request_indexes.get(request_id, -1))
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
			record.reasoning = str(record.reasoning) + str(payload.get("delta", ""))
		"content.delta":
			record.content = str(record.content) + str(payload.get("delta", ""))
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
			record.output = payload.duplicate(true)
	_requests[index] = record
	if _log_file != null:
		_log_file.store_line(JSON.stringify(event))
		_log_file.flush()
	trace_updated.emit(request_id)
	return true


func get_requests() -> Array[Dictionary]:
	return _requests.duplicate(true)


func get_request(request_id: String) -> Dictionary:
	var index := int(_request_indexes.get(request_id, -1))
	return {} if index < 0 else (_requests[index] as Dictionary).duplicate(true)


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
