extends SceneTree

const DebugStateEditorTest := preload("res://tests/test_debug_state_editor.gd")
const DebugPanelTest := preload("res://tests/test_debug_panel.gd")
const DebugPanelZeroFilterTest := preload("res://tests/test_debug_panel_zero_filter.gd")
const TestAssertScript := preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	DebugStateEditorTest.new().run(assertions)
	await DebugPanelTest.new().run(assertions, self)
	await DebugPanelZeroFilterTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d runtime debug panel checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d runtime debug panel checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
