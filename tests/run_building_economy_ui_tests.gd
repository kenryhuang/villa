extends SceneTree

const BuildingEconomyUITest = preload("res://tests/test_building_economy_ui.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	await BuildingEconomyUITest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d building economy UI checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d building economy UI checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
