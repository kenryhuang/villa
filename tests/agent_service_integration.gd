extends SceneTree

const AgentProtocolScript = preload("res://scripts/ai_agent/agent_protocol.gd")
const AgentClientConfigScript = preload("res://scripts/ai_agent/agent_client_config.gd")

var _base_url := ""
var _token := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var client_config := AgentClientConfigScript.load_file()
	if not client_config.ok or not bool(client_config.value.enabled):
		print("SKIP: role agent service integration requires config/agent-client.local.json with enabled=true")
		quit(0)
		return
	_base_url = str(client_config.value.service_url)
	_token = str(client_config.value.token)
	var health := await _send("GET", "/health", {})
	if not _expect_success(health, "health"):
		return
	var suffix := str(Time.get_ticks_msec())
	var session_id := "acceptance-" + suffix
	var request_id := "request-" + suffix
	var synced := await _send("POST", "/v1/sessions/sync", {
		"session_id": session_id, "session_epoch": 1,
	})
	if not _expect_success(synced, "session sync"):
		return
	var decision_request := AgentProtocolScript.make_decision_request(
		request_id,
		session_id,
		1,
		"farmer_ahe",
		"schedule",
		480,
		7,
		{
			"game_time": {"day": 1, "hour": 14, "minute": 0, "season": 0},
			"self": {"gold": 500, "inventory": {"carrot_seed": 6}},
			"farm": [{"plot_index": 0, "tilled": false, "crop": {}}],
			"market": {},
		},
		[],
	)
	var decision := await _send(
		"POST", "/v1/agents/farmer_ahe/decide", decision_request, session_id
	)
	if not _expect_success(decision, "decision"):
		return
	var parsed := AgentProtocolScript.parse_action_intent(
		decision.body,
		["till", "plant", "harvest", "build", "buy", "sell", "speak", "wait"]
	)
	if not parsed.ok:
		_fail("Provider returned invalid intent: " + str(parsed.error))
		return
	var intent := parsed.value as Dictionary
	var outcome := {
		"protocol_version": 1,
		"decision_id": intent.decision_id,
		"idempotency_key": intent.idempotency_key,
		"status": "completed",
		"committed_revision": 8,
		"changed_entities": ["acceptance:farmer_ahe"],
		"resource_delta": {},
		"hud_message": "Connected Provider acceptance outcome",
		"game_minute": 480,
	}
	if not _expect_success(
		await _send("POST", "/v1/agents/farmer_ahe/outcomes", outcome, session_id),
		"outcome"
	):
		return
	var checkpoint := await _send("POST", "/v1/checkpoints/export", {
		"session_id": session_id, "checkpoint_id": "acceptance-" + suffix,
	})
	if not _expect_success(checkpoint, "checkpoint export"):
		return
	if typeof(checkpoint.body.get("sha256")) != TYPE_STRING or str(checkpoint.body.sha256).length() != 64:
		_fail("checkpoint export returned no checksum")
		return
	print("PASS: role agent service integration")
	quit(0)


func _send(method: String, path: String, body: Dictionary, session_id: String = "") -> Dictionary:
	var request := HTTPRequest.new()
	root.add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not _token.is_empty():
		headers.append("Authorization: Bearer " + _token)
	if not session_id.is_empty():
		headers.append("X-Session-Id: " + session_id)
	var http_method := HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_POST
	var error := request.request(
		_base_url + path, headers, http_method, "" if method == "GET" else JSON.stringify(body)
	)
	if error != OK:
		request.free()
		return {"ok": false, "code": 0, "body": {}, "error": error_string(error)}
	var completed: Array = await request.request_completed
	request.free()
	var response_body: Variant = JSON.parse_string((completed[3] as PackedByteArray).get_string_from_utf8())
	return {
		"ok": int(completed[0]) == HTTPRequest.RESULT_SUCCESS and int(completed[1]) >= 200 and int(completed[1]) < 300,
		"code": int(completed[1]),
		"body": response_body if response_body is Dictionary else {},
		"error": "",
	}


func _expect_success(result: Dictionary, operation: String) -> bool:
	if result.ok:
		return true
	_fail("%s failed (HTTP %d): %s" % [operation, int(result.code), JSON.stringify(result.body)])
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
