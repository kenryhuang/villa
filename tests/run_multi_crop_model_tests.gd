extends SceneTree

const TestScript = preload("res://tests/test_multi_crop_models.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	TestScript.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d multi-crop model checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d multi-crop model checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
