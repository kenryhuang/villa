extends SceneTree

const EconomyProgressionTest = preload("res://tests/test_economy_progression.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	EconomyProgressionTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d economy progression checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d economy progression checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
