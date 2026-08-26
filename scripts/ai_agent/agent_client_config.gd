extends RefCounted

const DEFAULT_PATH := "res://config/agent-client.local.json"
const DEFAULT_SESSION_DIRECTORY := "user://agent_sessions"
const REQUIRED_FIELDS := ["enabled", "service_url", "token", "timeout_seconds"]
const ALLOWED_FIELDS := [
	"enabled",
	"service_url",
	"token",
	"timeout_seconds",
	"store_agent_session",
	"agent_session_directory",
]


static func load_file(path: String = DEFAULT_PATH) -> Dictionary:
	if path.strip_edges().is_empty() or not FileAccess.file_exists(path):
		return _failure("missing_config_file")
	var source := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return _failure("invalid_json")
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return _failure("invalid_json")
	var data := parsed as Dictionary
	for field in REQUIRED_FIELDS:
		if not data.has(field):
			return _failure("missing_" + field)
	for field in data:
		if not str(field) in ALLOWED_FIELDS:
			return _failure("unknown_" + str(field))
	if typeof(data.enabled) != TYPE_BOOL:
		return _failure("invalid_enabled")
	if typeof(data.service_url) != TYPE_STRING or typeof(data.token) != TYPE_STRING:
		return _failure("invalid_connection_fields")
	if typeof(data.timeout_seconds) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure("invalid_timeout_seconds")
	if data.has("store_agent_session") and typeof(data.store_agent_session) != TYPE_BOOL:
		return _failure("invalid_store_agent_session")
	if data.has("agent_session_directory") and (
		typeof(data.agent_session_directory) != TYPE_STRING
		or str(data.agent_session_directory).strip_edges().is_empty()
	):
		return _failure("invalid_agent_session_directory")
	var timeout_seconds := float(data.timeout_seconds)
	if not is_finite(timeout_seconds) or timeout_seconds < 0.1 or timeout_seconds > 120.0:
		return _failure("invalid_timeout_seconds")
	var enabled := bool(data.enabled)
	var service_url := str(data.service_url).strip_edges().trim_suffix("/")
	if enabled and not _valid_http_url(service_url):
		return _failure("invalid_service_url")
	if not enabled and not service_url.is_empty() and not _valid_http_url(service_url):
		return _failure("invalid_service_url")
	return {
		"ok": true,
		"value": {
			"enabled": enabled,
			"service_url": service_url,
			"token": str(data.token),
			"timeout_seconds": timeout_seconds,
			"store_agent_session": bool(data.get("store_agent_session", false)),
			"agent_session_directory": str(
				data.get("agent_session_directory", DEFAULT_SESSION_DIRECTORY)
			).strip_edges(),
		},
	}


static func _valid_http_url(value: String) -> bool:
	if not (value.begins_with("http://") or value.begins_with("https://")):
		return false
	var authority_start := value.find("://") + 3
	var authority_end := value.find("/", authority_start)
	var authority := value.substr(authority_start) if authority_end < 0 else value.substr(authority_start, authority_end - authority_start)
	return not authority.is_empty() and not authority.contains(" ")


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
