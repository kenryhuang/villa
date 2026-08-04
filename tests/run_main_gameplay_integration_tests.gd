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
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	InventoryCapacityTest.new().run(assertions)
	ToolActionTransactionTest.new().run(assertions, self)
	PlayerActionControllerTest.new().run(assertions, self)
	ActionPaletteButtonTest.new().run(assertions, self)
	HudActionBarTest.new().run(assertions, self)
	GatheringControllerTest.new().run(assertions, self)
	MainFarmingBuildingIntegrationTest.new().run(assertions, self)
	await BuildingEconomyUITest.new().run(assertions, self)
	await EconomyUIIntegrationTest.new().run(assertions, self)
	await MainPointerFarmingTest.new().run(assertions, self)
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
