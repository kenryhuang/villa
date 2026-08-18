extends SceneTree

const ItemContainerRouterTest = preload("res://tests/test_item_container_router.gd")
const MarketMathTest = preload("res://tests/test_market_math.gd")
const MarketSystemTest = preload("res://tests/test_market_system.gd")
const EconomyTransactionsTest = preload("res://tests/test_economy_transactions.gd")
const NpcEconomySystemTest = preload("res://tests/test_npc_economy_system.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	for script_value in [
		ItemContainerRouterTest, MarketMathTest, MarketSystemTest, EconomyTransactionsTest,
		NpcEconomySystemTest,
	]:
		assertions.truthy(
			script_value != null and script_value.can_instantiate(),
			"Task2 test script compiles: " + str(script_value.resource_path)
		)
	if not assertions.failures.is_empty():
		_finish(assertions)
		return
	print("[task2-trade] router start")
	var router_checks_before: int = assertions.checks
	await ItemContainerRouterTest.new().run(assertions, self)
	print("[task2-trade] router complete: %d checks" % (assertions.checks - router_checks_before))
	print("[task2-trade] economy start")
	MarketMathTest.new().run(assertions)
	await MarketSystemTest.new().run(assertions, self)
	EconomyTransactionsTest.new().run(assertions)
	print("[task2-trade] npc start")
	NpcEconomySystemTest.new().run(assertions, self)
	print("[task2-trade] complete: %d checks" % assertions.checks)
	_finish(assertions)


func _finish(assertions: TestAssert) -> void:
	if assertions.failures.is_empty():
		print("PASS: %d Task2 trade checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d Task2 trade checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
