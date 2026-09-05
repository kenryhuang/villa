extends SceneTree

const PlayerLogicTest = preload("res://tests/test_player_logic.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	var assertions = TestAssertScript.new()
	PlayerLogicTest.new().run(assertions)
	if assertions.failures.is_empty():
		print("PASS: %d player logic checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d player logic checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
