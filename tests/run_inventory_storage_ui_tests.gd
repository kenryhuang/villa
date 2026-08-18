extends SceneTree

const InventoryStorageUITest := preload("res://tests/test_inventory_storage_ui.gd")
const TestAssertScript := preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	await InventoryStorageUITest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d inventory storage UI checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d inventory storage UI checks failed" % [
		assertions.failures.size(), assertions.checks,
	])
	quit(1)
