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
	assertions.truthy(trace.accept_event(_event_value("stream.started", 1, {"trigger": "schedule"})), "disk trace accepts event")
	var log_path: String = trace.get_log_path()
	assertions.truthy(FileAccess.file_exists(log_path), "enabled trace creates NDJSON file")
	assertions.truthy(FileAccess.get_file_as_string(log_path).contains("stream.started"), "NDJSON flushes event immediately")
	assertions.truthy(not log_path.get_file().contains(":"), "trace filename sanitizes session ID")
	trace.close()
	trace.free()
	var files := Array(DirAccess.get_files_at(directory)).filter(func(path): return str(path).ends_with(".ndjson"))
	assertions.truthy(files.size() <= 20, "Agent trace retains at most twenty session files")
	_remove_directory(directory)


func _event(name: String, sequence: int, payload: Dictionary) -> String:
	return "event: %s\ndata: %s\n\n" % [name, JSON.stringify(_envelope(sequence, payload))]


func _event_value(name: String, sequence: int, payload: Dictionary) -> Dictionary:
	return {"event": name, "data": _envelope(sequence, payload)}


func _envelope(sequence: int, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": 1,
		"stream_id": "request-1:stream",
		"request_id": "request-1",
		"agent_id": "farmer_ahe",
		"sequence": sequence,
		"timestamp_msec": 1000 + sequence,
		"payload": payload,
	}


func _remove_directory(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(absolute.path_join(file_name))
	DirAccess.remove_absolute(absolute)
