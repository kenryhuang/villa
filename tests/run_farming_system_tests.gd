extends SceneTree

const CoreFoundationTest = preload("res://tests/test_core_foundation.gd")
const FarmingSystemTest = preload("res://tests/test_farming_system.gd")
const CropEconomyTest = preload("res://tests/test_crop_economy.gd")
const CropVisualTest = preload("res://tests/test_crop_visual.gd")
const FarmingSystemCompleteTest = preload("res://tests/test_farming_system_complete.gd")
const GrainCropArtAssetsTest = preload("res://tests/test_grain_crop_art_assets.gd")
const CropSpriteClusterTest = preload("res://tests/test_crop_sprite_cluster.gd")
const GrainCropModelsTest = preload("res://tests/test_grain_crop_models.gd")
const FarmStorageSystemTest = preload("res://tests/test_farm_storage_system.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	CoreFoundationTest.new().run(assertions)
	FarmingSystemTest.new().run(assertions)
	CropEconomyTest.new().run(assertions, self)
	CropVisualTest.new().run(assertions)
	FarmingSystemCompleteTest.new().run(assertions, self)
	GrainCropArtAssetsTest.new().run(assertions)
	CropSpriteClusterTest.new().run(assertions, self)
	GrainCropModelsTest.new().run(assertions, self)
	await FarmStorageSystemTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d farming system checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d farming system checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
