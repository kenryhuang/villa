extends SceneTree

const TestAssertScript = preload("res://tests/test_assert.gd")
const ControllerTest = preload("res://tests/test_player_action_controller.gd")
const HudTest = preload("res://tests/test_hud_action_bar.gd")
const SeasonTest = preload("res://tests/test_season_system.gd")
const DebugCropDayTest = preload("res://tests/test_debug_crop_day.gd")
const MainWiringTest = preload("res://tests/test_main_item_container_wiring.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	await MainWiringTest.new().run(assertions, self)
	ControllerTest.new().run(assertions, self)
	await HudTest.new().run(assertions, self)
	SeasonTest.new().run(assertions)
	DebugCropDayTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d action-mode/debug-day regression checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d action-mode/debug-day checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
