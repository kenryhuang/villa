extends SceneTree

const CropTimingTest = preload("res://tests/test_crop_timing.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	CropTimingTest.new().run(assertions)
	if assertions.failures.is_empty():
		print("PASS: %d visible farmer checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d visible farmer checks failed" % [
		assertions.failures.size(),
		assertions.checks,
	])
	quit(1)
