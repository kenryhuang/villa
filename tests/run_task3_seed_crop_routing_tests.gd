extends SceneTree

const EconomyOrdersTest := preload("res://tests/test_economy_orders.gd")
const ProductionSystemTest := preload("res://tests/test_production_system.gd")
const EconomyUIIntegrationTest := preload("res://tests/test_economy_ui_integration.gd")
const TestAssertScript := preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	print("[task3] orders")
	var orders_test := EconomyOrdersTest.new()
	await orders_test.run(assertions, self)
	orders_test = null
	await process_frame
	print("[task3] production")
	var production_test := ProductionSystemTest.new()
	await production_test.run(assertions, self)
	production_test = null
	print("[task3] economy UI")
	var ui_test := EconomyUIIntegrationTest.new()
	await ui_test.run(assertions, self)
	ui_test = null
	await process_frame
	if assertions.failures.is_empty():
		print("PASS: %d Task3 seed/crop routing checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d Task3 seed/crop routing checks failed" % [
		assertions.failures.size(), assertions.checks,
	])
	quit(1)
