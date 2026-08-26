extends SceneTree

const AgentWorldStateTest = preload("res://tests/test_agent_world_state.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	var test := AgentWorldStateTest.new()
	test.run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d Agent system checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d Agent system checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
