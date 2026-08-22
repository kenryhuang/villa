class_name HudMessageBus
extends Node

signal message_added(record: Dictionary)
signal message_updated(record: Dictionary)
signal message_rejected(reason: String)

const VALID_SEVERITIES: Array[String] = ["info", "success", "warning", "error", "debug"]
const MAX_RECORDS := 100
const MERGE_WINDOW_MSEC := 1000

var _records: Array[Dictionary] = []
var _next_id := 1


func publish(source: String, severity: String, text: String, metadata: Dictionary = {}) -> bool:
	source = source.strip_edges()
	text = text.strip_edges()
	if source.is_empty() or text.is_empty() or severity not in VALID_SEVERITIES:
		message_rejected.emit("invalid_message")
		return false
	var timestamp_msec := int(metadata.get("timestamp_msec", Time.get_ticks_msec()))
	var target_type := str(metadata.get("target_type", ""))
	var target_id := str(metadata.get("target_id", ""))
	if not _records.is_empty():
		var previous: Dictionary = _records[-1]
		if (
			str(previous["source"]) == source
			and str(previous["severity"]) == severity
			and str(previous["text"]) == text
			and str(previous["target_type"]) == target_type
			and str(previous["target_id"]) == target_id
			and timestamp_msec - int(previous["timestamp_msec"]) <= MERGE_WINDOW_MSEC
		):
			previous["count"] = int(previous["count"]) + 1
			previous["timestamp_msec"] = timestamp_msec
			_records[-1] = previous
			message_updated.emit(previous.duplicate(true))
			return true
	var record := {
		"message_id": "hud-%d" % _next_id,
		"source": source,
		"severity": severity,
		"text": text,
		"timestamp_msec": timestamp_msec,
		"game_time": str(metadata.get("game_time", "")),
		"target_type": target_type,
		"target_id": target_id,
		"count": 1,
	}
	_next_id += 1
	_records.append(record)
	if _records.size() > MAX_RECORDS:
		_records.pop_front()
	message_added.emit(record.duplicate(true))
	return true


func get_recent() -> Array[Dictionary]:
	return _records.duplicate(true)


func clear() -> void:
	_records.clear()
