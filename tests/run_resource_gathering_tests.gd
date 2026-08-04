extends SceneTree

const ResourceGatheringTest = preload("res://tests/test_resource_gathering.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	ResourceGatheringTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d resource gathering checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d resource gathering checks failed" % [
		assertions.failures.size(), assertions.checks,
	])
	quit(1)
