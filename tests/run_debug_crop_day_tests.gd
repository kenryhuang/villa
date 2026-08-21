extends SceneTree

const TestAssertScript = preload("res://tests/test_assert.gd")
const DebugCropDayTest = preload("res://tests/test_debug_crop_day.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	DebugCropDayTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d debug crop day checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d debug crop day checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
