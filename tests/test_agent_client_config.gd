extends RefCounted

const AgentClientConfigScript = preload("res://scripts/ai_agent/agent_client_config.gd")


func run(assertions: TestAssert) -> void:
	var valid_path := _write_json("valid", {
		"enabled": true,
		"service_url": "http://127.0.0.1:8787/",
		"token": "local-token",
		"timeout_seconds": 12.5,
	})
	var loaded := AgentClientConfigScript.load_file(valid_path)
	assertions.truthy(loaded.ok, "valid Agent client configuration loads")
	assertions.equal(loaded.value.service_url, "http://127.0.0.1:8787", "service URL normalizes")
	assertions.equal(loaded.value.token, "local-token", "service token loads")
	assertions.near(loaded.value.timeout_seconds, 12.5, 0.001, "service timeout loads")

	var disabled_path := _write_json("disabled", {
		"enabled": false, "service_url": "", "token": "", "timeout_seconds": 10,
	})
	var disabled := AgentClientConfigScript.load_file(disabled_path)
	assertions.truthy(disabled.ok, "disabled Agent client configuration loads")
	assertions.truthy(not disabled.value.enabled, "explicit disablement is preserved")

	assertions.truthy(
		not AgentClientConfigScript.load_file("user://missing-agent-client-config.json").ok,
		"missing Agent client configuration rejects",
	)
	var malformed_path := _write_text("malformed", "{bad-json")
	assertions.truthy(not AgentClientConfigScript.load_file(malformed_path).ok, "malformed Agent client JSON rejects")

	for fixture in [
		{"enabled": true, "service_url": "ftp://localhost", "token": "", "timeout_seconds": 10},
		{"enabled": true, "service_url": "", "token": "", "timeout_seconds": 10},
		{"enabled": true, "service_url": "http://localhost:8787", "token": "", "timeout_seconds": 0.01},
		{"enabled": "yes", "service_url": "http://localhost:8787", "token": "", "timeout_seconds": 10},
		{"enabled": false, "service_url": "", "token": "", "timeout_seconds": 10, "extra": true},
	]:
		var invalid_path := _write_json("invalid-%d" % assertions.checks, fixture)
		assertions.truthy(not AgentClientConfigScript.load_file(invalid_path).ok, "invalid Agent client configuration rejects")
		_remove(invalid_path)

	for path in [valid_path, disabled_path, malformed_path]:
		_remove(path)


func _write_json(label: String, value: Dictionary) -> String:
	return _write_text(label, JSON.stringify(value))


func _write_text(label: String, value: String) -> String:
	var path := "user://agent-client-%s-%d.json" % [label, Time.get_ticks_usec()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()
	return path


func _remove(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute)
