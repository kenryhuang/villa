extends SceneTree

const InventoryCapacityTest = preload("res://tests/test_inventory_capacity.gd")
const ToolActionTransactionTest = preload("res://tests/test_tool_action_transaction.gd")
const PlayerActionControllerTest = preload("res://tests/test_player_action_controller.gd")
const ActionPaletteButtonTest = preload("res://tests/test_action_palette_button.gd")
const HudActionBarTest = preload("res://tests/test_hud_action_bar.gd")
const MainFarmingBuildingIntegrationTest = preload(
	"res://tests/test_main_farming_building_integration.gd"
)
const MainPointerFarmingTest = preload("res://tests/test_main_pointer_farming.gd")
const BuildingEconomyUITest = preload("res://tests/test_building_economy_ui.gd")
const EconomyUIIntegrationTest = preload("res://tests/test_economy_ui_integration.gd")
const GatheringControllerTest = preload("res://tests/test_gathering_controller.gd")
const GatheringVisualsTest = preload("res://tests/test_gathering_visuals.gd")
const MainGatheringIntegrationTest = preload("res://tests/test_main_gathering_integration.gd")
const MainItemContainerWiringTest = preload("res://tests/test_main_item_container_wiring.gd")
const InventoryStorageUITest = preload("res://tests/test_inventory_storage_ui.gd")
const SeedSelectorPanelTest = preload("res://tests/test_seed_selector_panel.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	for script_value in [MainItemContainerWiringTest, MainGatheringIntegrationTest]:
		assertions.truthy(
			script_value != null and script_value.can_instantiate(),
			"Main integration script compiles: " + str(script_value.resource_path)
		)
	if not assertions.failures.is_empty():
		_finish(assertions)
		return
	var task2_main_checks_before: int = assertions.checks
	print("[task2-main-router] start")
	await MainItemContainerWiringTest.new().run(assertions, self)
	print(
		"[task2-main-router] complete: %d checks"
		% (assertions.checks - task2_main_checks_before)
	)
	var task4_inventory_checks_before: int = assertions.checks
	print("[task4-inventory-storage] start")
	await InventoryStorageUITest.new().run(assertions, self)
	print(
		"[task4-inventory-storage] complete: %d checks"
		% (assertions.checks - task4_inventory_checks_before)
	)
	var task5_seed_selector_checks_before: int = assertions.checks
	print("[task5-seed-selector] start")
	await SeedSelectorPanelTest.new().run(assertions, self)
	print(
		"[task5-seed-selector] complete: %d checks"
		% (assertions.checks - task5_seed_selector_checks_before)
	)
	InventoryCapacityTest.new().run(assertions)
	ToolActionTransactionTest.new().run(assertions, self)
	PlayerActionControllerTest.new().run(assertions, self)
	ActionPaletteButtonTest.new().run(assertions, self)
	await HudActionBarTest.new().run(assertions, self)
	GatheringControllerTest.new().run(assertions, self)
	await GatheringVisualsTest.new().run(assertions, self)
	await MainGatheringIntegrationTest.new().run(assertions, self)
	await MainFarmingBuildingIntegrationTest.new().run(assertions, self)
	await BuildingEconomyUITest.new().run(assertions, self)
	await EconomyUIIntegrationTest.new().run(assertions, self)
	await MainPointerFarmingTest.new().run(assertions, self)
	_finish(assertions)


func _finish(assertions: TestAssert) -> void:
	if assertions.failures.is_empty():
		print("PASS: %d main gameplay integration checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d main gameplay integration checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
