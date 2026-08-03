extends SceneTree

const EconomyUIIntegrationTest := preload("res://tests/test_economy_ui_integration.gd")
const TestAssertScript := preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	await EconomyUIIntegrationTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d economy UI integration checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d economy UI integration checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
