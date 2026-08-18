extends SceneTree

const ProductionSystemTest = preload("res://tests/test_production_system.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	await ProductionSystemTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d production system checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d production system checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
