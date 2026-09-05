extends SceneTree

const PlayerDialogueInputTest = preload("res://tests/test_player_dialogue_input.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	await PlayerDialogueInputTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d player dialogue input checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d player dialogue input checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
