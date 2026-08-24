extends SceneTree

const EconomySaveIntegrationTest := preload("res://tests/test_economy_save_integration.gd")
const TestAssertScript := preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	EconomySaveIntegrationTest.new()._test_inventory_capacity_round_trip(
		assertions,
		self
	)
	if assertions.failures.is_empty():
		print("PASS: %d inventory capacity save checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d inventory capacity save checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
