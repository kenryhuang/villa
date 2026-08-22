extends SceneTree

const TestAssertScript = preload("res://tests/test_assert.gd")
const HudMessageBusTest = preload("res://tests/test_hud_message_bus.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	HudMessageBusTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d HUD shell checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d HUD shell checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
