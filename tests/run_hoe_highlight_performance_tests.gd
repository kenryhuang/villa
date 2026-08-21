extends SceneTree

const TestAssertScript = preload("res://tests/test_assert.gd")
const ToolTest = preload("res://tests/test_tool_action_transaction.gd")
const GridTest = preload("res://tests/test_grid_system_complete.gd")
const MainTest = preload("res://tests/test_main_item_container_wiring.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	ToolTest.new().run(assertions, self)
	GridTest.new().run(assertions)
	await MainTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d hoe/highlight performance checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d hoe/highlight performance checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
