extends SceneTree

const EconomyUIResponsiveTest := preload("res://tests/test_economy_ui_responsive.gd")
const TestAssertScript := preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	var suite := EconomyUIResponsiveTest.new()
	await suite.run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d responsive economy UI checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d responsive economy UI checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
