extends SceneTree

const GridSystemTest = preload("res://tests/test_grid_system.gd")
const GridMutationTest = preload("res://tests/test_grid_mutation.gd")
const GridSystemCompleteTest = preload("res://tests/test_grid_system_complete.gd")
const FarmlandTileTest = preload("res://tests/test_farmland_tile.gd")
const GridPathfinderTest = preload("res://tests/test_grid_pathfinder.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	GridSystemTest.new().run(assertions)
	GridMutationTest.new().run(assertions)
	GridSystemCompleteTest.new().run(assertions)
	FarmlandTileTest.new().run(assertions)
	GridPathfinderTest.new().run(assertions)
	if assertions.failures.is_empty():
		print("PASS: %d grid system checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d grid system checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
