extends SceneTree

const GeographicQueryServiceTest = preload(
	"res://tests/test_geographic_query_service.gd"
)
const BuildingEconomyEffectsTest = preload(
	"res://tests/test_building_economy_effects.gd"
)
const FishingDataTest = preload("res://tests/test_fishing_data.gd")
const FishingSystemTest = preload("res://tests/test_fishing_system.gd")
const FishingMainIntegrationTest = preload("res://tests/test_fishing_main_integration.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	GeographicQueryServiceTest.new().run(assertions)
	BuildingEconomyEffectsTest.new().run(assertions, self)
	FishingDataTest.new().run(assertions)
	FishingSystemTest.new().run(assertions)
	FishingMainIntegrationTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d geography and fishing checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d geography and fishing checks failed" % [
		assertions.failures.size(),
		assertions.checks,
	])
	quit(1)
