extends SceneTree

const EconomyWalletTest = preload("res://tests/test_economy_wallet.gd")
const MarketCatalogTest = preload("res://tests/test_market_catalog.gd")
const MarketMathTest = preload("res://tests/test_market_math.gd")
const MarketSystemTest = preload("res://tests/test_market_system.gd")
const EconomyTransactionsTest = preload("res://tests/test_economy_transactions.gd")
const ItemContainerRouterTest = preload("res://tests/test_item_container_router.gd")
const DailySimulationSystemTest = preload("res://tests/test_daily_simulation_system.gd")
const EconomySaveIntegrationTest = preload("res://tests/test_economy_save_integration.gd")
const RecipeDatabaseTest = preload("res://tests/test_recipe_database.gd")
const ProductionSystemTest = preload("res://tests/test_production_system.gd")
const BuildingEconomyEffectsTest = preload("res://tests/test_building_economy_effects.gd")
const ResourceGatheringTest = preload("res://tests/test_resource_gathering.gd")
const NpcEconomySystemTest = preload("res://tests/test_npc_economy_system.gd")
const EconomyOrdersTest = preload("res://tests/test_economy_orders.gd")
const EconomyProgressionTest = preload("res://tests/test_economy_progression.gd")
const ServicePanelTest = preload("res://tests/test_service_panel.gd")
const OrderContractUITest = preload("res://tests/test_order_contract_ui.gd")
const EconomyNotificationsTest = preload("res://tests/test_economy_notifications.gd")
const EconomyUIResponsiveTest = preload("res://tests/test_economy_ui_responsive.gd")
const EconomySimulationTest = preload("res://tests/test_economy_simulation.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions = TestAssertScript.new()
	for script_value in [
		ItemContainerRouterTest, MarketMathTest, MarketSystemTest,
		EconomyTransactionsTest, NpcEconomySystemTest,
	]:
		assertions.truthy(
			script_value != null and script_value.can_instantiate(),
			"Task2 economy script compiles: " + str(script_value.resource_path)
		)
	if not assertions.failures.is_empty():
		_finish(assertions)
		return
	var task2_checks_before: int = assertions.checks
	print("[task2-trade] router start")
	var router_checks_before: int = assertions.checks
	await ItemContainerRouterTest.new().run(assertions, self)
	print(
		"[economy-suite] authoritative item containers complete: %d checks"
		% (assertions.checks - router_checks_before)
	)
	print("[task2-trade] economy start")
	EconomyWalletTest.new().run(assertions)
	MarketCatalogTest.new().run(assertions)
	MarketMathTest.new().run(assertions)
	await MarketSystemTest.new().run(assertions, self)
	EconomyTransactionsTest.new().run(assertions)
	print("[task2-trade] complete: %d checks" % (assertions.checks - task2_checks_before))
	print("[economy-suite] simulation and save")
	DailySimulationSystemTest.new().run(assertions, self)
	EconomySaveIntegrationTest.new().run(assertions, self)
	RecipeDatabaseTest.new().run(assertions)
	await ProductionSystemTest.new().run(assertions, self)
	print("[economy-suite] building and gathering")
	BuildingEconomyEffectsTest.new().run(assertions, self)
	ResourceGatheringTest.new().run(assertions, self)
	NpcEconomySystemTest.new().run(assertions, self)
	print("[economy-suite] progression and services")
	await EconomyOrdersTest.new().run(assertions, self)
	EconomyProgressionTest.new().run(assertions, self)
	ServicePanelTest.new().run(assertions, self)
	print("[economy-suite] async UI")
	var order_contract_ui_test := OrderContractUITest.new()
	await order_contract_ui_test.run(assertions, self)
	var economy_notifications_test := EconomyNotificationsTest.new()
	await economy_notifications_test.run(assertions, self)
	var economy_ui_responsive_test := EconomyUIResponsiveTest.new()
	await economy_ui_responsive_test.run(assertions, self)
	print("[economy-suite] deterministic economy simulation")
	EconomySimulationTest.new().run(assertions)
	_finish(assertions)


func _finish(assertions: TestAssert) -> void:
	if assertions.failures.is_empty():
		print("PASS: %d economy checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d economy checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
