extends SceneTree

const ProductionChainIntegrationTest = preload("res://tests/test_production_chain_integration.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	await ProductionChainIntegrationTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d production chain integration checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d production chain integration checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
