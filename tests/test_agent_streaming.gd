extends RefCounted

const AgentSseParserScript = preload("res://scripts/ai_agent/agent_sse_parser.gd")
const AgentSessionTraceScript = preload("res://scripts/ai_agent/agent_session_trace.gd")


func run(assertions: TestAssert) -> void:
	_test_fragmented_utf8_and_sequence(assertions)
	_test_terminal_validation(assertions)
	_test_memory_trace(assertions)
	_test_ndjson_and_retention(assertions)


func _test_fragmented_utf8_and_sequence(assertions: TestAssert) -> void:
	var parser = AgentSseParserScript.new()
	var source := (
		": heartbeat\n\n"
		+ _event("stream.started", 1, {"trigger": "dialogue"})
		+ _event("reasoning.delta", 2, {"delta": "地块未开垦。"})
		+ _event("content.delta", 3, {"delta": "我来整理土地。"})
	)
	var events: Array = []
	for byte in source.to_utf8_buffer():
		var result: Dictionary = parser.feed(PackedByteArray([byte]))
		assertions.truthy(result.ok, "fragmented SSE byte remains valid")
		if not result.ok:
			return
		events.append_array(result.events)
	assertions.equal(events.size(), 3, "fragmented SSE yields all non-heartbeat events")
	assertions.equal(events[1].data.payload.delta, "地块未开垦。", "fragmented UTF-8 remains intact")
	assertions.equal(events[2].data.sequence, 3, "SSE sequence remains monotonic")


func _test_terminal_validation(assertions: TestAssert) -> void:
	var duplicate = AgentSseParserScript.new()
	var first: Dictionary = duplicate.feed(_event("stream.started", 1, {}).to_utf8_buffer())
	assertions.truthy(first.ok, "first stream sequence is valid")
	var repeated: Dictionary = duplicate.feed(_event("content.delta", 1, {"delta": "重复"}).to_utf8_buffer())
	assertions.truthy(not repeated.ok, "repeated SSE sequence rejects")

	var parser = AgentSseParserScript.new()
	assertions.truthy(parser.feed(_event("decision.final", 1, {"tool_name": "wait"}).to_utf8_buffer()).ok, "first final is valid")
	assertions.truthy(parser.feed(_event("stream.completed", 2, {"status": "completed"}).to_utf8_buffer()).ok, "completed follows final")
	assertions.truthy(not parser.feed(_event("content.delta", 3, {"delta": "late"}).to_utf8_buffer()).ok, "events after completion reject")
	var legacy = AgentSseParserScript.new()
	var legacy_event := _event_value("stream.started", 1, {"trigger": "schedule"})
	legacy_event.data.protocol_version = 1
	assertions.truthy(not legacy.feed(("event: stream.started\ndata: %s\n\n" % JSON.stringify(legacy_event.data)).to_utf8_buffer()).ok, "v1 SSE envelope rejects")


func _test_memory_trace(assertions: TestAssert) -> void:
	var trace = AgentSessionTraceScript.new()
	assertions.truthy(trace.configure(false, "slot-0"), "memory-only Agent trace configures")
	for event in [
		_event_value("stream.started", 1, {"trigger": "dialogue"}),
		_event_value("provider.input", 2, {"model": "test-model", "messages": []}),
		_event_value("reasoning.delta", 3, {"delta": "地块未开垦。"}),
		_event_value("content.delta", 4, {"delta": "我来整理土地。"}),
		_event_value("provider.output", 5, {"message": {"content": "我来整理土地。"}}),
		_event_value("decision.final", 6, {"tool_name": "till", "arguments": {"plot_index": 0}}),
		_event_value("stream.completed", 7, {"status": "completed"}),
	]:
		assertions.truthy(trace.accept_event(event), "Agent trace accepts ordered stream event")
	var requests: Array[Dictionary] = trace.get_requests()
	assertions.equal(requests.size(), 1, "one stream becomes one trace request")
	assertions.equal(requests[0].reasoning, "地块未开垦。", "reasoning accumulates verbatim")
	assertions.equal(requests[0].content, "我来整理土地。", "content accumulates verbatim")
	assertions.equal(requests[0].final.tool_name, "till", "final intent is retained")
	assertions.equal(trace.get_log_path(), "", "memory-only trace creates no file")
	trace.free()


func _test_ndjson_and_retention(assertions: TestAssert) -> void:
	var directory := "user://agent-session-test-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for index in range(21):
		var old_path := directory.path_join("old-%02d.ndjson" % index)
		var old_file := FileAccess.open(old_path, FileAccess.WRITE)
		old_file.store_line("{}")
		old_file.close()
	var trace = AgentSessionTraceScript.new()
	assertions.truthy(trace.configure(true, "slot:/unsafe", directory), "disk Agent trace configures")
	var log_path: String = trace.get_log_path()
	assertions.truthy(FileAccess.file_exists(log_path), "enabled trace creates NDJSON file")
	for event in [
		_event_value_for("request-completed", "stream.started", 1, {"trigger": "schedule"}),
		_event_value_for("request-completed", "provider.input", 2, {"model": "test-model", "messages": [{"role": "user", "content": "经营农场"}]}),
		_event_value_for("request-completed", "reasoning.delta", 3, {"delta": "先检查"}),
		_event_value_for("request-completed", "reasoning.delta", 4, {"delta": "库存。"}),
		_event_value_for("request-completed", "content.delta", 5, {"delta": "今天"}),
		_event_value_for("request-completed", "content.delta", 6, {"delta": "先等待。"}),
		_event_value_for("request-completed", "tool_call.delta", 7, {"index": 0, "delta": "wait"}),
		_event_value_for("request-completed", "provider.output", 8, {"message": {"content": "今天先等待。"}}),
		_event_value_for("request-completed", "decision.final", 9, {"actions": []}),
	]:
		assertions.truthy(trace.accept_event(event), "disk trace accepts non-terminal stream event")
	assertions.equal(FileAccess.get_file_as_string(log_path), "", "non-terminal deltas remain memory-only")
	assertions.truthy(trace.accept_event(_event_value_for("request-completed", "stream.completed", 10, {"status": "completed"})), "disk trace accepts completion")
	var lines := _read_nonempty_lines(log_path)
	assertions.equal(lines.size(), 1, "completed request writes exactly one NDJSON record")
	var completed: Dictionary = JSON.parse_string(lines[0]) if lines.size() == 1 else {}
	assertions.equal(completed.get("schema_version"), 2, "aggregated trace uses schema version two")
	assertions.equal(completed.get("request_id"), "request-completed", "aggregated trace retains request ID")
	assertions.equal(completed.get("status"), "completed", "aggregated trace retains completion status")
	assertions.equal((completed.get("input", {}) as Dictionary).get("model"), "test-model", "aggregated trace retains provider input")
	var completed_response := completed.get("response", {}) as Dictionary
	assertions.equal(completed_response.get("reasoning_content"), "先检查库存。", "aggregated trace joins reasoning deltas")
	assertions.equal(completed_response.get("content"), "今天先等待。", "aggregated trace joins content deltas")
	assertions.equal((completed_response.get("tool_call_deltas", []) as Array).size(), 1, "aggregated trace retains tool-call deltas")
	assertions.equal((completed_response.get("decision", {}) as Dictionary).get("actions"), [], "aggregated trace retains final decision")
	assertions.equal(completed_response.get("error"), {}, "completed trace has no error")
	assertions.truthy(trace.accept_event(_event_value_for("request-completed", "stream.completed", 11, {"status": "completed"})), "duplicate completion remains accepted")
	assertions.equal(_read_nonempty_lines(log_path).size(), 1, "duplicate terminal event does not write twice")

	assertions.truthy(trace.accept_event(_event_value_for("request-stream-error", "stream.started", 1, {"trigger": "schedule"})), "error trace accepts start")
	assertions.truthy(trace.accept_event(_event_value_for("request-stream-error", "reasoning.delta", 2, {"delta": "服务异常"})), "error trace accepts partial reasoning")
	assertions.truthy(trace.accept_event(_event_value_for("request-stream-error", "stream.error", 3, {"code": "provider_error", "message": "upstream failed"})), "error trace accepts terminal error")
	lines = _read_nonempty_lines(log_path)
	assertions.equal(lines.size(), 2, "stream error writes one aggregated record")
	var stream_error: Dictionary = JSON.parse_string(lines[1]) if lines.size() == 2 else {}
	assertions.equal(stream_error.get("status"), "error", "stream error record has error status")
	assertions.equal(((stream_error.get("response", {}) as Dictionary).get("error", {}) as Dictionary).get("code"), "provider_error", "stream error payload is retained")
	assertions.truthy(trace.finish_error("farmer_ahe", "request-stream-error", "transport_closed", "schedule", 2000), "failure callback after stream error is idempotent")
	assertions.equal(_read_nonempty_lines(log_path).size(), 2, "stream error callback does not write a duplicate")

	assertions.truthy(trace.finish_error("farmer_ahe", "request-cancelled", "dialogue_closed", "dialogue", 3000), "local cancellation finalizes a trace")
	lines = _read_nonempty_lines(log_path)
	assertions.equal(lines.size(), 3, "local cancellation writes one aggregated record")
	var cancelled: Dictionary = JSON.parse_string(lines[2]) if lines.size() == 3 else {}
	assertions.equal(cancelled.get("trigger"), "dialogue", "local cancellation retains trigger")
	assertions.equal((((cancelled.get("response", {}) as Dictionary).get("error", {}) as Dictionary).get("code")), "dialogue_closed", "local cancellation retains failure code")
	assertions.truthy(trace.finish_error("farmer_ahe", "request-cancelled", "dialogue_closed", "dialogue", 3001), "duplicate local cancellation remains accepted")
	assertions.equal(_read_nonempty_lines(log_path).size(), 3, "duplicate local cancellation does not write twice")

	assertions.truthy(trace.accept_event(_event_value_for("request-unfinished", "stream.started", 1, {"trigger": "schedule"})), "unfinished trace accepts start")
	assertions.truthy(not log_path.get_file().contains(":"), "trace filename sanitizes session ID")
	trace.close()
	assertions.equal(_read_nonempty_lines(log_path).size(), 3, "closing trace does not persist unfinished request")
	trace.free()
	var files := Array(DirAccess.get_files_at(directory)).filter(func(path): return str(path).ends_with(".ndjson"))
	assertions.truthy(files.size() <= 20, "Agent trace retains at most twenty session files")
	_remove_directory(directory)


func _event(name: String, sequence: int, payload: Dictionary) -> String:
	return "event: %s\ndata: %s\n\n" % [name, JSON.stringify(_envelope(sequence, payload))]


func _event_value(name: String, sequence: int, payload: Dictionary) -> Dictionary:
	return {"event": name, "data": _envelope(sequence, payload)}


func _event_value_for(request_id: String, name: String, sequence: int, payload: Dictionary) -> Dictionary:
	var data := _envelope(sequence, payload)
	data.request_id = request_id
	data.stream_id = request_id + ":stream"
	return {"event": name, "data": data}


func _envelope(sequence: int, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": 2,
		"stream_id": "request-1:stream",
		"request_id": "request-1",
		"agent_id": "farmer_ahe",
		"sequence": sequence,
		"timestamp_msec": 1000 + sequence,
		"payload": payload,
	}


func _read_nonempty_lines(path: String) -> Array[String]:
	var result: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if not line.strip_edges().is_empty():
			result.append(line)
	return result


func _remove_directory(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(absolute.path_join(file_name))
	DirAccess.remove_absolute(absolute)
