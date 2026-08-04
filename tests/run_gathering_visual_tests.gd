extends SceneTree

const GatheringVisualsTest = preload("res://tests/test_gathering_visuals.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	GatheringVisualsTest.new().run(assertions)
	if assertions.failures.is_empty():
		print("PASS: %d gathering visual checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d gathering visual checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
