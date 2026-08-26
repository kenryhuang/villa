extends Node

const AgentStreamClientScript = preload("res://scripts/ai_agent/agent_stream_client.gd")

var session_epoch := 0
var _base_url := ""
var _token := ""
var _timeout_seconds := 10.0
var _stream_client: Node


func configure(base_url: String, token: String, epoch: int, timeout_seconds: float = 10.0) -> bool:
	var normalized := base_url.strip_edges().trim_suffix("/")
	if normalized.is_empty() or epoch < 0 or timeout_seconds <= 0.0:
		return false
	_base_url = normalized
	_token = token
	session_epoch = epoch
	_timeout_seconds = timeout_seconds
	if _stream_client == null:
		_stream_client = AgentStreamClientScript.new()
		_stream_client.name = "AgentStreamClient"
		add_child(_stream_client)
	return bool(_stream_client.call("configure", _base_url, _token, session_epoch, _timeout_seconds))


func request_decision(
	agent_id: String,
	request_body: Dictionary,
	callback: Callable,
	event_callback: Callable = Callable()
) -> bool:
	if _base_url.is_empty() or _stream_client == null or not callback.is_valid():
		return false
	var stream_callback := event_callback if event_callback.is_valid() else func(_event: Dictionary): pass
	return bool(_stream_client.call(
		"request_decision", agent_id, request_body, stream_callback, callback
	))


func report_outcome(agent_id: String, session_id: String, outcome: Dictionary) -> bool:
	if _base_url.is_empty() or agent_id.is_empty():
		return false
	var request := HTTPRequest.new()
	request.timeout = _timeout_seconds
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json", "X-Session-Id: " + session_id])
	if not _token.is_empty():
		headers.append("Authorization: Bearer " + _token)
	request.request_completed.connect(func(_result, _code, _headers, _body): request.queue_free(), CONNECT_ONE_SHOT)
	return request.request(_base_url + "/v1/agents/" + agent_id.uri_encode() + "/outcomes", headers, HTTPClient.METHOD_POST, JSON.stringify(outcome)) == OK


func sync_session(session_id: String, reset: bool, callback: Callable = Callable()) -> bool:
	return _request_json(
		"/v1/sessions/sync",
		{"session_id": session_id, "session_epoch": session_epoch, "reset": reset},
		callback
	)


func export_checkpoint(session_id: String, checkpoint_id: String, callback: Callable) -> bool:
	return _request_json(
		"/v1/checkpoints/export",
		{"session_id": session_id, "checkpoint_id": checkpoint_id},
		callback
	)


func import_checkpoint(record: Dictionary, callback: Callable) -> bool:
	return _request_json("/v1/checkpoints/import", record, callback)


func bump_epoch() -> int:
	session_epoch += 1
	if _stream_client != null:
		_stream_client.call("set_epoch", session_epoch)
	return session_epoch


func cancel_all() -> void:
	if _stream_client != null:
		_stream_client.call("cancel_all")


func cancel_agent(agent_id: String, reason: String = "cancelled") -> bool:
	return (
		_stream_client != null
		and bool(_stream_client.call("cancel_agent", agent_id, reason))
	)


func _request_json(path: String, body: Dictionary, callback: Callable) -> bool:
	if _base_url.is_empty():
		return false
	var request := HTTPRequest.new()
	request.timeout = _timeout_seconds
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not _token.is_empty():
		headers.append("Authorization: Bearer " + _token)
	request.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, response_body: PackedByteArray):
			var value: Variant = JSON.parse_string(response_body.get_string_from_utf8())
			var success := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 and value is Dictionary
			if callback.is_valid():
				callback.call(success, value if value is Dictionary else {}, "" if success else "http_%d_result_%d" % [code, result])
			request.queue_free(),
		CONNECT_ONE_SHOT
	)
	var error := request.request(_base_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		request.queue_free()
		return false
	return true
