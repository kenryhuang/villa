extends SceneTree

const SeedSelectorPanelTest := preload("res://tests/test_seed_selector_panel.gd")
const SeedCardTest := preload("res://tests/test_seed_card.gd")
const TestAssertScript := preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	SeedCardTest.new().run(assertions, self)
	var suite := SeedSelectorPanelTest.new()
	await suite.run(assertions, self)
	await suite.run_responsive(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d seed selector checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d seed selector checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
