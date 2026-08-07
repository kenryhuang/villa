extends SceneTree

const PlayerActionControllerTest = preload("res://tests/test_player_action_controller.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	PlayerActionControllerTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d player action controller checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d player action controller checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
