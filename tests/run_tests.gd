extends SceneTree

const CombatMathTest = preload("res://tests/test_combat_math.gd")
const RoadMathTest = preload("res://tests/test_road_math.gd")
const TreeScatterTest = preload("res://tests/test_tree_scatter.gd")
const TerrainBuilderTest = preload("res://tests/test_terrain_builder.gd")
const CameraMathTest = preload("res://tests/test_camera_math.gd")
const PlayerLogicTest = preload("res://tests/test_player_logic.gd")
const NpcLogicTest = preload("res://tests/test_npc_logic.gd")
const ProjectileLogicTest = preload("res://tests/test_projectile_logic.gd")
const SmokeTest = preload("res://tests/smoke_test.gd")
const VegetationBuilderTest = preload("res://tests/test_vegetation_builder.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var assertions = TestAssertScript.new()
	CombatMathTest.new().run(assertions)
	RoadMathTest.new().run(assertions)
	TreeScatterTest.new().run(assertions)
	TerrainBuilderTest.new().run(assertions)
	CameraMathTest.new().run(assertions)
	PlayerLogicTest.new().run(assertions)
	NpcLogicTest.new().run(assertions)
	ProjectileLogicTest.new().run(assertions)
	SmokeTest.new().run(assertions)
	VegetationBuilderTest.new().run(assertions)
	if assertions.failures.is_empty():
		print("PASS: %d checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
