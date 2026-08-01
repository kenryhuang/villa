extends SceneTree

const EconomyWalletTest = preload("res://tests/test_economy_wallet.gd")
const MarketCatalogTest = preload("res://tests/test_market_catalog.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	EconomyWalletTest.new().run(assertions)
	MarketCatalogTest.new().run(assertions)
	if assertions.failures.is_empty():
		print("PASS: %d economy checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d economy checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
