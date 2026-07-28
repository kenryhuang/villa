extends SceneTree

const BuildingDataTest = preload("res://tests/test_building_data.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	BuildingDataTest.new().run(assertions)
	if assertions.failures.is_empty():
		print("PASS: %d building system checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d building system checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
