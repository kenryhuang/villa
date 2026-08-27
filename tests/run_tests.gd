extends SceneTree

const CombatMathTest = preload("res://tests/test_combat_math.gd")
const RoadMathTest = preload("res://tests/test_road_math.gd")
const TreeScatterTest = preload("res://tests/test_tree_scatter.gd")
const TerrainBuilderTest = preload("res://tests/test_terrain_builder.gd")
const CameraMathTest = preload("res://tests/test_camera_math.gd")
const PlayerLogicTest = preload("res://tests/test_player_logic.gd")
const PlayerVisualTest = preload("res://tests/test_player_visual.gd")
const NpcLogicTest = preload("res://tests/test_npc_logic.gd")
const ProjectileLogicTest = preload("res://tests/test_projectile_logic.gd")
const SmokeTest = preload("res://tests/smoke_test.gd")
const VegetationBuilderTest = preload("res://tests/test_vegetation_builder.gd")
const TreeInstanceTest = preload("res://tests/test_tree_instance.gd")
const CoreFoundationTest = preload("res://tests/test_core_foundation.gd")
const CoreAutoloadsTest = preload("res://tests/test_core_autoloads.gd")
const SeasonSystemTest = preload("res://tests/test_season_system.gd")
const GridSystemTest = preload("res://tests/test_grid_system.gd")
const GridMutationTest = preload("res://tests/test_grid_mutation.gd")
const FarmingSystemTest = preload("res://tests/test_farming_system.gd")
const CropVisualTest = preload("res://tests/test_crop_visual.gd")
const Phase1SystemsTest = preload("res://tests/test_phase1_systems.gd")
const MainItemContainerWiringTest = preload("res://tests/test_main_item_container_wiring.gd")
const EconomyOrdersTest = preload("res://tests/test_economy_orders.gd")
const ProductionSystemTest = preload("res://tests/test_production_system.gd")
const EconomyUIIntegrationTest = preload("res://tests/test_economy_ui_integration.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var assertions = TestAssertScript.new()
	var main_wiring_script: Variant = MainItemContainerWiringTest
	assertions.truthy(
		main_wiring_script != null and main_wiring_script.can_instantiate(),
		"aggregate Main Router script compiles"
	)
	if not assertions.failures.is_empty():
		_finish(assertions)
		return
	CombatMathTest.new().run(assertions)
	RoadMathTest.new().run(assertions)
	TreeScatterTest.new().run(assertions)
	TerrainBuilderTest.new().run(assertions)
	CameraMathTest.new().run(assertions)
	PlayerLogicTest.new().run(assertions)
	PlayerVisualTest.new().run(assertions)
	NpcLogicTest.new().run(assertions, self)
	ProjectileLogicTest.new().run(assertions)
	SmokeTest.new().run(assertions)
	VegetationBuilderTest.new().run(assertions)
	TreeInstanceTest.new().run(assertions)
	CoreFoundationTest.new().run(assertions)
	CoreAutoloadsTest.new().run(assertions)
	var task2_main_checks_before: int = assertions.checks
	print("[task2-main-router] start")
	await MainItemContainerWiringTest.new().run(assertions, self)
	print(
		"[task2-main-router] complete: %d checks"
		% (assertions.checks - task2_main_checks_before)
	)
	var task3_checks_before: int = assertions.checks
	print("[task3-seed-crop-routing] start")
	var task3_orders_test := EconomyOrdersTest.new()
	await task3_orders_test.run(assertions, self)
	task3_orders_test = null
	var task3_production_test := ProductionSystemTest.new()
	await task3_production_test.run(assertions, self)
	task3_production_test = null
	var task3_ui_test := EconomyUIIntegrationTest.new()
	await task3_ui_test.run(assertions, self)
	task3_ui_test = null
	print(
		"[task3-seed-crop-routing] complete: %d checks"
		% (assertions.checks - task3_checks_before)
	)
	SeasonSystemTest.new().run(assertions)
	GridSystemTest.new().run(assertions)
	GridMutationTest.new().run(assertions)
	FarmingSystemTest.new().run(assertions)
	CropVisualTest.new().run(assertions)
	Phase1SystemsTest.new().run(assertions)
	_finish(assertions)


func _finish(assertions: TestAssert) -> void:
	if assertions.failures.is_empty():
		print("PASS: %d checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
