extends Node

const AgentSseParserScript = preload("res://scripts/ai_agent/agent_sse_parser.gd")

var session_epoch := 0
var _base_url := ""
var _token := ""
var _timeout_seconds := 10.0
var _scheme := ""
var _host := ""
var _port := 0
var _base_path := ""
var _streams: Dictionary = {}


func configure(base_url: String, token: String, epoch: int, timeout_seconds: float = 10.0) -> bool:
	var parsed := _parse_url(base_url.strip_edges().trim_suffix("/"))
	if not parsed.ok or epoch < 0 or timeout_seconds <= 0.0:
		return false
	cancel_all()
	_base_url = base_url.strip_edges().trim_suffix("/")
	_token = token
	session_epoch = epoch
	_timeout_seconds = timeout_seconds
	_scheme = str(parsed.scheme)
	_host = str(parsed.host)
	_port = int(parsed.port)
	_base_path = str(parsed.path)
	return true


func request_decision(
	agent_id: String,
	request_body: Dictionary,
	event_callback: Callable,
	final_callback: Callable
) -> bool:
	if (
		_base_url.is_empty()
		or agent_id.is_empty()
		or not event_callback.is_valid()
		or not final_callback.is_valid()
	):
		return false
	if _streams.has(agent_id):
		cancel_agent(agent_id, "replaced")
	var client := HTTPClient.new()
	var tls_options: TLSOptions = TLSOptions.client() if _scheme == "https" else null
	var error := client.connect_to_host(_host, _port, tls_options)
	if error != OK:
		return false
	_streams[agent_id] = {
		"client": client,
		"parser": AgentSseParserScript.new(),
		"request": request_body.duplicate(true),
		"event_callback": event_callback,
		"final_callback": final_callback,
		"epoch": session_epoch,
		"request_sent": false,
		"response_started": false,
		"final": {},
		"last_activity_msec": Time.get_ticks_msec(),
	}
	set_process(true)
	return true


func cancel_agent(agent_id: String, reason: String = "cancelled") -> bool:
	if not _streams.has(agent_id):
		return false
	_finish(agent_id, false, {}, reason)
	return true


func cancel_all() -> void:
	for agent_id_value in _streams.keys().duplicate():
		cancel_agent(str(agent_id_value))


func set_epoch(epoch: int) -> bool:
	if epoch < 0:
		return false
	session_epoch = epoch
	cancel_all()
	return true


func get_active_agent_ids() -> Array[String]:
	var result: Array[String] = []
	for agent_id_value in _streams:
		result.append(str(agent_id_value))
	result.sort()
	return result


func _process(_delta: float) -> void:
	for agent_id_value in _streams.keys().duplicate():
		var agent_id := str(agent_id_value)
		if _streams.has(agent_id):
			_poll_stream(agent_id)
	if _streams.is_empty():
		set_process(false)


func _poll_stream(agent_id: String) -> void:
	var state := _streams[agent_id] as Dictionary
	if int(state.epoch) != session_epoch:
		_finish(agent_id, false, {}, "stale_session_epoch")
		return
	if Time.get_ticks_msec() - int(state.last_activity_msec) > int(_timeout_seconds * 1000.0):
		_finish(agent_id, false, {}, "stream_idle_timeout")
		return
	var client := state.client as HTTPClient
	var poll_error := client.poll()
	if poll_error != OK:
		_finish(agent_id, false, {}, "http_poll_%s" % error_string(poll_error))
		return
	var status := client.get_status()
	if status in [
		HTTPClient.STATUS_CANT_RESOLVE,
		HTTPClient.STATUS_CANT_CONNECT,
		HTTPClient.STATUS_CONNECTION_ERROR,
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR,
	]:
		_finish(agent_id, false, {}, "http_status_%d" % status)
		return
	if status == HTTPClient.STATUS_CONNECTED and not bool(state.request_sent):
		var headers := PackedStringArray([
			"Content-Type: application/json",
			"Accept: text/event-stream",
			"X-Session-Id: " + str((state.request as Dictionary).get("session_id", "")),
		])
		if not _token.is_empty():
			headers.append("Authorization: Bearer " + _token)
		var path := _base_path + "/v1/agents/" + agent_id.uri_encode() + "/decide/stream"
		var request_error := client.request(
			HTTPClient.METHOD_POST,
			path,
			headers,
			JSON.stringify(state.request)
		)
		if request_error != OK:
			_finish(agent_id, false, {}, "http_request_%s" % error_string(request_error))
			return
		state.request_sent = true
		state.last_activity_msec = Time.get_ticks_msec()
		_streams[agent_id] = state
		return
	if status == HTTPClient.STATUS_BODY:
		if not bool(state.response_started):
			var response_code := client.get_response_code()
			if response_code < 200 or response_code >= 300:
				_finish(agent_id, false, {}, "http_%d" % response_code)
				return
			state.response_started = true
		while client.get_status() == HTTPClient.STATUS_BODY:
			var chunk := client.read_response_body_chunk()
			if chunk.is_empty():
				break
			state.last_activity_msec = Time.get_ticks_msec()
			var parsed: Dictionary = (state.parser as RefCounted).call("feed", chunk)
			if not parsed.ok:
				_finish(agent_id, false, {}, str(parsed.error))
				return
			for event_value in parsed.events:
				var event := event_value as Dictionary
				var event_callback := state.event_callback as Callable
				event_callback.call(event.duplicate(true))
				var event_name := str(event.event)
				if event_name == "decision.final":
					state.final = (event.data as Dictionary).payload.duplicate(true)
				elif event_name == "stream.error":
					_finish(agent_id, false, {}, str((event.data as Dictionary).payload.get("code", "stream_error")))
					return
				elif event_name == "stream.completed":
					if (state.final as Dictionary).is_empty():
						_finish(agent_id, false, {}, "completed_without_final")
					else:
						_finish(agent_id, true, state.final, "")
					return
		_streams[agent_id] = state
		return
	if (
		bool(state.request_sent)
		and bool(state.response_started)
		and status in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]
	):
		_finish(agent_id, false, {}, "incomplete_stream")


func _finish(agent_id: String, ok: bool, response: Dictionary, error: String) -> void:
	if not _streams.has(agent_id):
		return
	var state := _streams[agent_id] as Dictionary
	_streams.erase(agent_id)
	var client := state.client as HTTPClient
	client.close()
	var callback := state.final_callback as Callable
	callback.call(ok, response.duplicate(true), error)


func _parse_url(value: String) -> Dictionary:
	var regex := RegEx.new()
	if regex.compile("^(https?)://([^/:]+)(?::([0-9]+))?(.*)$") != OK:
		return {"ok": false}
	var match := regex.search(value)
	if match == null:
		return {"ok": false}
	var scheme := match.get_string(1)
	var port_text := match.get_string(3)
	var port := int(port_text) if not port_text.is_empty() else (443 if scheme == "https" else 80)
	if port < 1 or port > 65535:
		return {"ok": false}
	var path := match.get_string(4).trim_suffix("/")
	if path.is_empty():
		path = ""
	elif not path.begins_with("/"):
		return {"ok": false}
	return {"ok": true, "scheme": scheme, "host": match.get_string(2), "port": port, "path": path}
