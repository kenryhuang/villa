extends SceneTree

const ServicePanelTest = preload("res://tests/test_service_panel.gd")
const EconomyNotificationsTest = preload("res://tests/test_economy_notifications.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	ServicePanelTest.new().run(assertions, self)
	var notifications_test := EconomyNotificationsTest.new()
	await notifications_test.run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d maintenance integration checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d maintenance integration checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
