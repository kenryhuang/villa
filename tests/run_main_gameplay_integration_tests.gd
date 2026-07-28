extends SceneTree

const InventoryCapacityTest = preload("res://tests/test_inventory_capacity.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	InventoryCapacityTest.new().run(assertions)
	if assertions.failures.is_empty():
		print("PASS: %d main gameplay integration checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d main gameplay integration checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
