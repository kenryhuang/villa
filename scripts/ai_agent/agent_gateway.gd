extends Node

var session_epoch := 0
var _base_url := ""
var _token := ""
var _timeout_seconds := 10.0
var _requests: Dictionary = {}


func configure(base_url: String, token: String, epoch: int, timeout_seconds: float = 10.0) -> bool:
	var normalized := base_url.strip_edges().trim_suffix("/")
	if normalized.is_empty() or epoch < 0 or timeout_seconds <= 0.0:
		return false
	_base_url = normalized
	_token = token
	session_epoch = epoch
	_timeout_seconds = timeout_seconds
	return true


func request_decision(agent_id: String, request_body: Dictionary, callback: Callable) -> bool:
	if _base_url.is_empty() or agent_id.is_empty() or not callback.is_valid() or _requests.has(agent_id):
		return false
	var request := HTTPRequest.new()
	request.timeout = _timeout_seconds
	add_child(request)
	_requests[agent_id] = request
	var headers := PackedStringArray(["Content-Type: application/json", "X-Session-Id: " + str(request_body.get("session_id", ""))])
	if not _token.is_empty():
		headers.append("Authorization: Bearer " + _token)
	request.request_completed.connect(_on_request_completed.bind(agent_id, session_epoch, callback, request), CONNECT_ONE_SHOT)
	var error := request.request(_base_url + "/v1/agents/" + agent_id.uri_encode() + "/decide", headers, HTTPClient.METHOD_POST, JSON.stringify(request_body))
	if error != OK:
		_requests.erase(agent_id)
		request.queue_free()
		return false
	return true


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


func bump_epoch() -> int:
	session_epoch += 1
	cancel_all()
	return session_epoch


func cancel_all() -> void:
	for request_value in _requests.values():
		var request := request_value as HTTPRequest
		request.cancel_request()
		request.queue_free()
	_requests.clear()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	agent_id: String,
	epoch: int,
	callback: Callable,
	request: HTTPRequest
) -> void:
	_requests.erase(agent_id)
	request.queue_free()
	if epoch != session_epoch:
		callback.call(false, {}, "stale_session_epoch")
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		callback.call(false, {}, "http_%d_result_%d" % [response_code, result])
		return
	var value: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not value is Dictionary:
		callback.call(false, {}, "invalid_json_response")
		return
	callback.call(true, (value as Dictionary).duplicate(true), "")
