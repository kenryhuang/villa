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
var intent_debug_fetcher: Callable
var _intent_fetching := {}
var _intent_fetch_times := {}
var _intent_generation := 0


func configure(
	store_to_disk: bool,
	session_id: String,
	directory: String = DEFAULT_DIRECTORY
) -> bool:
	close()
	_requests.clear()
	_request_indexes.clear()
	_terminal_requests.clear()
	_intent_generation += 1
	_intent_fetching.clear()
	_intent_fetch_times.clear()
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
		"loop.trace":
			var timed_event := payload.duplicate(true)
			timed_event["timestamp_msec"] = int(data.timestamp_msec)
			record.loop_events.append(timed_event)
			if payload.get("event") == "provider.route":
				record.provider_route = payload.duplicate(true)
			elif payload.get("event") == "provider.response_model" and not record.provider_calls.is_empty():
				record.provider_calls[-1]["response_model"] = str(payload.get("model", ""))
			elif payload.get("event") == "chat.handoff_prepared":
				for event_id in payload.get("accepted_event_ids", []) + payload.get("rejected_event_ids", []):
					var source := str(event_id).trim_prefix("dialogue:")
					var source_record := get_request(source)
					if source_record.get("agent_id") == record.agent_id:
						record_action_event(source, "chat.handoff_boundary", {"action_request_id": request_id, "source_event_id": event_id, "accepted": event_id in payload.get("accepted_event_ids", [])})
		"provider.input":
			record.input = payload.duplicate(true)
			record.provider_calls.append({"input": payload.duplicate(true), "route": record.provider_route.duplicate(true), "timestamp_msec": int(data.timestamp_msec), "output": {}})
			_link_handoff_context(record, payload)
		"reasoning.delta":
			(record.reasoning_parts as Array).append(str(payload.get("delta", "")))
		"content.delta":
			(record.content_parts as Array).append(str(payload.get("delta", "")))
			if not str(payload.get("delta", "")).is_empty():
				var timing: Dictionary = record.content_timing
				var received := Time.get_ticks_msec()
				var sent := int(data.timestamp_msec)
				if int(timing.chunks) == 0:
					timing.first_delta_ms = maxi(0, sent - int(record.started_msec))
					timing.first_received_ms = maxi(0, received - int(record.received_start_ticks))
				else:
					timing.max_server_gap_ms = maxi(int(timing.max_server_gap_ms), sent - int(record.last_content_sent))
					timing.max_received_gap_ms = maxi(int(timing.max_received_gap_ms), received - int(record.last_content_received))
				timing.chunks += 1
				record.last_content_sent = sent
				record.last_content_received = received
		"tool_call.delta":
			(record.tool_deltas as Array).append(payload.duplicate(true))
		"provider.output":
			record.output = payload.duplicate(true)
			if not record.provider_calls.is_empty():
				record.provider_calls[-1]["output"] = payload.duplicate(true)
			record.provider_rounds.append({"usage": payload.get("usage", {}).duplicate(true), "metrics": payload.get("metrics", {}).duplicate(true), "input": record.input.duplicate(true), "output": payload.duplicate(true)})
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


func finish_cancelled(
	agent_id: String,
	request_id: String,
	reason: String,
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
	record.status = "cancelled"
	record.error = {}
	record.cancellation = {"code": reason if not reason.is_empty() else "cancelled"}
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


func refresh_intent_debug(request_id: String) -> void:
	if not intent_debug_fetcher.is_valid() or _intent_fetching.has(request_id): return
	var record := get_request(request_id)
	if record.is_empty() or record.get("trigger") != "dialogue": return
	var now := Time.get_ticks_msec()
	if now - int(_intent_fetch_times.get(request_id, -2000)) < 2000: return
	_intent_fetch_times[request_id] = now
	_intent_fetching[request_id] = true
	var generation := _intent_generation
	var callback := func(ok: bool, body: Dictionary, error: String):
		if generation != _intent_generation: return
		_intent_fetching.erase(request_id)
		if ok: accept_intent_debug(request_id, body)
		else:
			var index := int(_request_indexes.get(request_id, -1))
			if index >= 0:
				_requests[index]["intent_debug_error"] = error
				trace_updated.emit(request_id)
	if not bool(intent_debug_fetcher.call(str(record.agent_id), request_id, callback)):
		callback.call(false, {}, "debug_service_unavailable")


func accept_intent_debug(request_id: String, snapshot: Dictionary) -> bool:
	var index := int(_request_indexes.get(request_id, -1))
	if index < 0 or snapshot.get("request_id") != request_id or snapshot.get("agent_id") != _requests[index].agent_id: return false
	if _requests[index].get("intent_diagnostics", {}) == snapshot:
		if _requests[index].has("intent_debug_error"):
			_requests[index].erase("intent_debug_error")
			trace_updated.emit(request_id)
		return true
	_requests[index]["intent_diagnostics"] = snapshot.duplicate(true)
	_requests[index].erase("intent_debug_error")
	# Async extraction completes after stream.completed; store it as a linked update.
	record_action_event(request_id, "chat.intent_diagnostics", snapshot)
	return true


func record_action_event(request_id: String, event_name: String, metadata: Dictionary) -> bool:
	var index := int(_request_indexes.get(request_id, -1))
	if index < 0 or event_name.strip_edges().is_empty():
		return false
	var record := _requests[index]
	if not record.has("action_events"):
		record.action_events = []
	var action_event := {
		"event": event_name,
		"timestamp_msec": int(Time.get_unix_time_from_system() * 1000.0),
		"metadata": metadata.duplicate(true),
	}
	(record.action_events as Array).append(action_event)
	_requests[index] = record
	# Physical actions usually finish after the Provider stream has been persisted.
	# Append a compact receipt, linked by request_id, without repeating the prompt.
	if _terminal_requests.has(request_id) and _log_file != null:
		_log_file.store_line(JSON.stringify({
			"schema_version": RECORD_SCHEMA_VERSION, "record_type": "action_event",
			"request_id": request_id, "agent_id": record.agent_id,
			"action_event": action_event,
		}))
		_log_file.flush()
	trace_updated.emit(request_id)
	return true


func _handoffs_in_input(body: Dictionary) -> Array:
	var result: Array = []
	for index in body.get("messages", []).size():
		var message: Dictionary = body.messages[index]
		if message.get("role") != "user" or not message.get("content") is String: continue
		var parser := JSON.new()
		if parser.parse(message.content) != OK or not parser.data is Dictionary: continue
		var turn: Variant = parser.data.get("turn")
		if not turn is Dictionary or turn.get("trigger") == "dialogue": continue
		for field in ["dialogue_followups", "confirmed_dialogue"]:
			for entry in turn.get(field, []):
				if not entry is Dictionary: continue
				var source := str(entry.get("event_id", ""))
				if not source.begins_with("dialogue:") and not source.begins_with("chat-intents:"): continue
				result.append({"source_event_id":source,"context_path":"messages[%d].content → turn.%s" % [index,field],"context_entry":entry.duplicate(true)})
	return result


func _link_handoff_context(record: Dictionary, body: Dictionary) -> void:
	# This is derived from provider.input, not a queued request or a review marker.
	for evidence in _handoffs_in_input(body):
		evidence.merge({"action_request_id": record.request_id, "call_index": record.provider_calls.size() - 1, "model": body.get("model", ""), "agent_id": record.agent_id})
		var source := str(evidence.source_event_id).trim_prefix("dialogue:").trim_prefix("chat-intents:")
		var source_index := int(_request_indexes.get(source, -1))
		if source_index >= 0 and _requests[source_index].agent_id == record.agent_id:
			record_action_event(source, "chat.handoff_context", evidence)


func get_handoff_report(request_id: String) -> Dictionary:
	var record := get_request(request_id)
	if record.is_empty(): return {}
	var report := {"source_event_id": "dialogue:" + request_id, "extraction_status": "未记录提取结果", "raw_extractions": [], "accepted": [], "rejected": [], "archived": false, "delivery_status": "尚无实际行动模型请求证据", "pending": {}, "context_evidence": [], "boundary_checks": []}
	for call in record.get("provider_calls", []):
		if call.get("route", {}).get("phase") in ["extract_actions", "extract_intents"]:
			report.raw_extractions.append({"model":call.get("input",{}).get("model",""),"input":call.get("input",{}),"output":call.get("output",{})})
		for evidence in _handoffs_in_input(call.get("input", {})):
			evidence.merge({"action_request_id": request_id, "call_index": record.provider_calls.find(call), "model": call.get("input", {}).get("model", "")})
			report.context_evidence.append(evidence)
	for event in record.get("loop_events", []):
		match str(event.get("event", "")):
			"chat.intent_queued": report.extraction_status = "已排队：异步提取尚未返回"
			"chat.extraction_result":
				report["candidates"] = event.get("candidates", [])
				report.accepted = event.get("accepted", [])
				report.rejected = event.get("rejected", [])
				report["relationship_candidate"] = event.get("relationship_candidate")
				report.extraction_status = "已提取并通过校验" if not report.accepted.is_empty() else "模型返回空数组：未提取到行动指示"
				if not report.rejected.is_empty(): report.extraction_status = "部分或全部候选未通过校验"
			"chat.handoffs_extracted":
				if not report.has("candidates"):
					report.accepted = event.get("handoffs", [])
					report.extraction_status = "已提取并通过校验" if not report.accepted.is_empty() else "模型返回空数组：未提取到行动指示"
			"chat.extraction_failed":
				report["extraction_error"] = event
				report.extraction_status = "提取失败或候选校验失败"
			"chat.handoff_archived": report.archived = true
			"chat.handoff_prepared": report.boundary_checks.append(event)
	var final: Dictionary = record.get("final", {})
	if final.get("chat_isolated", false):
		if final.has("chat_handoffs"): report.accepted = final.chat_handoffs
		if report.extraction_status == "未记录提取结果":
			if final.get("chat_extraction_failed", false): report.extraction_status = "提取失败"
			elif final.has("chat_handoffs") and report.accepted.is_empty(): report.extraction_status = "模型返回空数组：未提取到行动指示"
			else: report.extraction_status = "尚未取得异步提取记录" if report.accepted.is_empty() else "已提取（缓存或旧记录，无本次原始提取调用）"
	var diagnostics: Dictionary = record.get("intent_diagnostics", {})
	if not diagnostics.is_empty():
		report["async_extraction"] = diagnostics
		report.accepted = diagnostics.get("accepted", [])
		report.archived = diagnostics.get("archived", false)
		report.extraction_status = str({"queued":"已排队，等待模型", "running":"正在提取", "retry_wait":"提取失败，等待重试", "failed":"提取失败，自动重试已停止", "empty":"模型确实返回空数组", "completed":"已提取并通过校验", "cancelled":"上下文已失效，提取已取消", "not_recorded":"未找到提取任务（旧版本记录或尚未入队）"}.get(diagnostics.get("status", ""), "未知状态"))
		if not str(diagnostics.get("error", "")).is_empty(): report.extraction_status += "：" + str(diagnostics.error)
	if record.has("intent_debug_error"): report["debug_fetch_error"] = record.intent_debug_error
	for event in record.get("action_events", []):
		if event.event == "chat.handoff_pending": report.pending = event.metadata
		elif event.event == "chat.handoff_context": report.context_evidence.append(event.metadata)
		elif event.event == "chat.handoff_boundary": report.boundary_checks.append(event.metadata)
	if not report.context_evidence.is_empty(): report.delivery_status = "已写入实际行动模型请求 context（不代表行动已执行）"
	elif report.boundary_checks.any(func(check): return check.get("accepted") == false): report.delivery_status = "服务端未找到可信交接记录，已拒绝进入行动 context"
	elif not report.pending.is_empty(): report.delivery_status = str(report.pending.get("reason", "等待行动调度"))
	elif diagnostics.get("consumed", false): report.delivery_status = "服务端已消费本轮意图；具体模型请求见 context_evidence"
	elif report.archived: report.delivery_status = "已暂存，等待下一次行动 loop"
	elif diagnostics.get("status") == "empty": report.delivery_status = "没有可交接的行动指示"
	if record.get("trigger") != "dialogue" and not final.get("chat_isolated", false): report.extraction_status = "行动 loop：查看实际收到的 context_evidence"
	return report


func clear() -> void:
	_intent_generation += 1
	_intent_fetching.clear()
	_intent_fetch_times.clear()
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
		"received_start_ticks": Time.get_ticks_msec(),
		"last_content_sent": 0,
		"last_content_received": 0,
		"content_timing": {"first_delta_ms": -1, "first_received_ms": -1, "chunks": 0, "max_server_gap_ms": 0, "max_received_gap_ms": 0},
		"tool_deltas": [],
		"output": {},
		"provider_rounds": [],
		"provider_calls": [],
		"provider_route": {},
		"loop_events": [],
		"final": {},
		"error": {},
		"cancellation": {},
		"action_events": [],
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
			"content_timing": materialized.content_timing.duplicate(true),
			"tool_call_deltas": (materialized.tool_deltas as Array).duplicate(true),
			"provider_output": (materialized.output as Dictionary).duplicate(true),
			"provider_rounds": materialized.get("provider_rounds", []).duplicate(true),
			"provider_calls": materialized.get("provider_calls", []).duplicate(true),
			"loop_events": materialized.get("loop_events", []).duplicate(true),
			"decision": (materialized.final as Dictionary).duplicate(true),
			"error": (materialized.error as Dictionary).duplicate(true),
			"cancellation": (materialized.cancellation as Dictionary).duplicate(true),
			"action_events": (materialized.get("action_events", []) as Array).duplicate(true),
		},
	}


func _materialize_record(record: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	result.provider_calls = (result.provider_calls as Array).filter(func(call: Dictionary): return not call.get("async_intent", false))
	for call in result.get("intent_diagnostics", {}).get("calls", []):
		var copied: Dictionary = call.duplicate(true)
		copied["async_intent"] = true
		result.provider_calls.append(copied)
	for key in ["received_start_ticks", "last_content_sent", "last_content_received"]:
		result.erase(key)
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
