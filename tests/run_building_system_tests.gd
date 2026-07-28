extends SceneTree

const BuildingDataTest = preload("res://tests/test_building_data.gd")
const BuildingInstanceTest = preload("res://tests/test_building_instance.gd")
const BuildingSystemCompleteTest = preload("res://tests/test_building_system_complete.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	BuildingDataTest.new().run(assertions)
	BuildingInstanceTest.new().run(assertions, self)
	BuildingSystemCompleteTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d building system checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d building system checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
