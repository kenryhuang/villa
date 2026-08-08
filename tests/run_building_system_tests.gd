extends SceneTree

const BuildingDataTest = preload("res://tests/test_building_data.gd")
const BuildingCatalogTest = preload("res://tests/test_building_catalog.gd")
const BuildingInstanceTest = preload("res://tests/test_building_instance.gd")
const BuildingActivityVisualTest = preload("res://tests/test_building_activity_visual.gd")
const BuildingSystemCompleteTest = preload("res://tests/test_building_system_complete.gd")
const BuildingArtAssetsTest = preload("res://tests/test_building_art_assets.gd")
const BuildingCameraIntegrationTest = preload("res://tests/test_building_camera_integration.gd")
const BuildUIBuildModeTest = preload("res://tests/test_build_ui_build_mode.gd")
const BuildingSaveIntegrationTest = preload("res://tests/test_building_save_integration.gd")
const ConstructionFeedbackTest = preload("res://tests/test_construction_feedback.gd")
const BuildingConstructionStateTest = preload("res://tests/test_building_construction_state.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	BuildingDataTest.new().run(assertions)
	BuildingCatalogTest.new().run(assertions)
	BuildingInstanceTest.new().run(assertions, self)
	BuildingActivityVisualTest.new().run(assertions)
	BuildingSystemCompleteTest.new().run(assertions, self)
	BuildingArtAssetsTest.new().run(assertions)
	BuildingCameraIntegrationTest.new().run(assertions, self)
	BuildUIBuildModeTest.new().run(assertions, self)
	BuildingSaveIntegrationTest.new().run(assertions, self)
	ConstructionFeedbackTest.new().run(assertions, self)
	BuildingConstructionStateTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d building system checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d building system checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
