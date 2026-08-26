extends RefCounted

const EVENT_NAMES := [
	"stream.started",
	"provider.input",
	"reasoning.delta",
	"content.delta",
	"tool_call.delta",
	"provider.output",
	"decision.final",
	"stream.completed",
	"stream.error",
]

var _buffer := PackedByteArray()
var _last_sequence := 0
var _received_final := false
var _terminal := false


func feed(bytes: PackedByteArray) -> Dictionary:
	if _terminal and not bytes.is_empty():
		return _failure("event_after_terminal")
	_buffer.append_array(bytes)
	var events: Array[Dictionary] = []
	while true:
		var boundary := _find_boundary()
		if boundary.x < 0:
			break
		var record_bytes := _buffer.slice(0, boundary.x)
		_buffer = _buffer.slice(boundary.x + boundary.y)
		var parsed := _parse_record(record_bytes.get_string_from_utf8())
		if not parsed.ok:
			return parsed
		if not parsed.event.is_empty():
			events.append(parsed.event)
	return {"ok": true, "events": events}


func reset() -> void:
	_buffer.clear()
	_last_sequence = 0
	_received_final = false
	_terminal = false


func _find_boundary() -> Vector2i:
	for index in range(_buffer.size() - 1):
		if _buffer[index] == 10 and _buffer[index + 1] == 10:
			return Vector2i(index, 2)
		if (
			index + 3 < _buffer.size()
			and _buffer[index] == 13
			and _buffer[index + 1] == 10
			and _buffer[index + 2] == 13
			and _buffer[index + 3] == 10
		):
			return Vector2i(index, 4)
	return Vector2i(-1, 0)


func _parse_record(source: String) -> Dictionary:
	var event_name := ""
	var data_lines: Array[String] = []
	for raw_line in source.split("\n"):
		var line := raw_line.trim_suffix("\r")
		if line.begins_with(":") or line.is_empty():
			continue
		if line.begins_with("event:"):
			event_name = line.substr(6).strip_edges()
		elif line.begins_with("data:"):
			data_lines.append(line.substr(5).trim_prefix(" "))
	if data_lines.is_empty():
		return {"ok": true, "event": {}}
	if event_name not in EVENT_NAMES:
		return _failure("unknown_event")
	var parser := JSON.new()
	if parser.parse("\n".join(data_lines)) != OK or not parser.data is Dictionary:
		return _failure("invalid_event_json")
	var data := parser.data as Dictionary
	var error := _validate_envelope(data)
	if not error.is_empty():
		return _failure(error)
	if event_name == "decision.final":
		if _received_final:
			return _failure("duplicate_final")
		_received_final = true
	elif event_name == "stream.completed":
		if not _received_final:
			return _failure("completed_without_final")
		_terminal = true
	elif event_name == "stream.error":
		_terminal = true
	_last_sequence = int(data.sequence)
	return {"ok": true, "event": {"event": event_name, "data": data}}


func _validate_envelope(data: Dictionary) -> String:
	if data.get("protocol_version") != 1:
		return "invalid_protocol_version"
	for field in ["stream_id", "request_id", "agent_id"]:
		if typeof(data.get(field)) != TYPE_STRING or str(data.get(field)).is_empty():
			return "invalid_" + field
	if (
		typeof(data.get("sequence")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(data.sequence))
		or float(data.sequence) != floor(float(data.sequence))
		or int(data.sequence) != _last_sequence + 1
	):
		return "invalid_sequence"
	if (
		typeof(data.get("timestamp_msec")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(data.timestamp_msec))
		or float(data.timestamp_msec) != floor(float(data.timestamp_msec))
		or int(data.timestamp_msec) < 0
	):
		return "invalid_timestamp"
	if not data.get("payload") is Dictionary:
		return "invalid_payload"
	return ""


func _failure(error: String) -> Dictionary:
	return {"ok": false, "events": [], "error": error}
