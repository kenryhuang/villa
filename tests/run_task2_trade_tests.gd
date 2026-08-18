extends SceneTree

const ItemContainerRouterTest = preload("res://tests/test_item_container_router.gd")
const MarketSystemTest = preload("res://tests/test_market_system.gd")
const EconomyTransactionsTest = preload("res://tests/test_economy_transactions.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	print("[task2-trade] router start")
	var router_checks_before: int = assertions.checks
	await ItemContainerRouterTest.new().run(assertions, self)
	print("[task2-trade] router complete: %d checks" % (assertions.checks - router_checks_before))
	print("[task2-trade] economy start")
	MarketSystemTest.new().run(assertions)
	EconomyTransactionsTest.new().run(assertions)
	print("[task2-trade] complete: %d checks" % assertions.checks)
	if assertions.failures.is_empty():
		print("PASS: %d Task2 trade checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d Task2 trade checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
