extends SceneTree

const TestScript = preload("res://tests/test_non_grain_seed_planting.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	TestScript.new().run(assertions)
	if assertions.failures.is_empty():
		print("PASS: %d non-grain seed planting checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d non-grain seed planting checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
