extends SceneTree

const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketPriceChartTest = preload("res://tests/test_market_price_chart.gd")
const MarketUITest = preload("res://tests/test_market_ui.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _check_scene(path: String, required_nodes: Array[String]) -> void:
	_check(ResourceLoader.exists(path), "missing scene: %s" % path)
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	_check(packed != null, "cannot load scene: %s" % path)
	if packed == null:
		return
	var instance := packed.instantiate()
	for node_path in required_nodes:
		_check(instance.has_node(node_path), "%s missing node %s" % [path, node_path])
	instance.free()


func _run() -> void:
	var market_assertions = TestAssertScript.new()
	await MarketPriceChartTest.new().run(market_assertions, self)
	await MarketUITest.new().run(market_assertions, self)
	for failure in market_assertions.failures:
		failures.append(failure)
	_check_scene("res://scenes/ui/hud.tscn", [
		"TopBar/StatusRow/StaminaBar",
		"TopBar/StatusRow/GoldLabel",
		"TopBar/StatusRow/LevelLabel",
		"TopBar/StatusRow/ExpBar",
		"TopBar/StatusRow/SeasonLabel",
		"TopBar/StatusRow/TimeLabel",
		"BottomBar/ToolLabel",
		"BottomBar/ModeMenu",
		"BottomBar/ActionRow/ModeButton",
		"BottomBar/ActionRow/QuickBar",
	])
	_check_scene("res://scenes/ui/inventory_ui.tscn", [
		"Panel/VBox/Tabs",
		"Panel/VBox/BackpackContent/GridContainer",
		"Panel/VBox/BackpackContent/QuickBar",
		"Panel/VBox/StorageContent/Header/Capacity",
		"Panel/VBox/StorageContent/Scroll/Rows",
	])
	_check_scene("res://scenes/ui/dialogue_ui.tscn", [
		"DialoguePanel/Margin/VBox/NameLabel",
		"DialoguePanel/Margin/VBox/TextContainer/TextLabel",
		"DialoguePanel/Margin/VBox/Choices",
	])
	_check_scene("res://scenes/ui/build_ui.tscn", ["ScrollContainer/GridContainer", "CloseButton"])
	_check_scene("res://scenes/ui/map_ui.tscn", ["MapTexture", "MapTexture/PlayerMarker"])
	_check_scene("res://scenes/ui/shop_ui.tscn", ["TopBar/GoldLabel", "ScrollContainer/GridContainer", "CloseButton"])
	_check_scene("res://scenes/main.tscn", ["InventoryUI", "DialogueUI", "BuildUI", "MapUI", "ShopUI"])
	_check_scene("res://scenes/ui/economy/market_panel.tscn", ["Columns/TradePanel"])
	_check_scene("res://scenes/ui/economy/order_panel.tscn", ["Columns/Orders/OrderScroll/OrderRows"])
	_check_scene("res://scenes/ui/economy/contract_panel.tscn", ["Content/Details/DeliverButton"])
	_check_scene("res://scenes/ui/economy/service_panel.tscn", ["ServiceScroll/ServiceCards"])
	_check_scene("res://scenes/ui/economy/building_economy_ui.tscn", ["ScreenLayer/ModalLayer/BuildingPanel", "WorldRangeOverlay"])
	_check_scene("res://scenes/ui/economy/economy_notification_ui.tscn", ["ToastStack", "NotificationCenter"])
	_check_scene("res://scenes/ui/debug_panel.tscn", [
		"Overlay/Center/Panel/Layout/Tabs/PlayerState",
		"Overlay/Center/Panel/Layout/Tabs/Inventory",
		"Overlay/Center/Panel/Layout/Footer/ApplyButton",
	])
	_check(ResourceLoader.exists("res://tests/run_economy_ui_tests.gd"), "economy UI integration runner exists")
	_check(ResourceLoader.exists("res://tests/capture_economy_ui.gd"), "economy UI capture runner exists")
	await _check_inventory_planting_selection()
	await _check_map_resizes_with_window()

	if failures.is_empty():
		print("PASS: runtime UI scene contract")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FAIL: %d runtime UI scene contract errors" % failures.size())
	quit(1)


func _check_map_resizes_with_window() -> void:
	var packed := load("res://scenes/ui/map_ui.tscn") as PackedScene
	if packed == null:
		return

	var window := Control.new()
	window.size = Vector2(1280.0, 720.0)
	get_root().add_child(window)
	var map_ui := packed.instantiate() as Control
	window.add_child(map_ui)
	await process_frame
	var map_texture := map_ui.get_node("MapTexture") as TextureRect
	var initial_size := map_texture.size

	window.size = Vector2(1920.0, 1080.0)
	await process_frame
	var enlarged_size := map_texture.size
	_check(
		enlarged_size.x > initial_size.x and enlarged_size.y > initial_size.y,
		"map canvas must grow with its window: %s -> %s" % [initial_size, enlarged_size]
	)
	window.free()


func _check_inventory_planting_selection() -> void:
	var inventory = InventorySystemScript.new()
	get_root().add_child(inventory)
	for item_id in ["carrot_seed", "rose_seed", "apple_sapling", "lemon_sapling", "wood"]:
		_check(inventory.add_item(item_id, 1), "runtime inventory adds %s fixture" % item_id)
	var packed := load("res://scenes/ui/inventory_ui.tscn") as PackedScene
	if packed == null:
		inventory.free()
		return
	var ui := packed.instantiate() as InventoryUI
	get_root().add_child(ui)
	ui.configure(inventory)
	ui.open()
	await process_frame
	_check(ui.has_method("assign_planting_slot"), "inventory UI exposes planting-slot assignment")
	if not ui.has_method("assign_planting_slot"):
		ui.free()
		inventory.free()
		return

	var slot_by_item := {}
	var empty_slot := -1
	for slot_index in range(inventory.slots.size()):
		var item_id := str(inventory.slots[slot_index].get("item_id", ""))
		if item_id.is_empty() and empty_slot < 0:
			empty_slot = slot_index
		elif not item_id.is_empty():
			slot_by_item[item_id] = slot_index
	for item_id in ["carrot_seed", "rose_seed", "apple_sapling", "lemon_sapling"]:
		_check(bool(ui.call("assign_planting_slot", int(slot_by_item[item_id]))), "%s assigns to planting slot" % item_id)
		_check(inventory.get_quick_item(5) == item_id, "%s becomes active planting item" % item_id)
		_check(ui.quick_bar.get_child_count() == 6, "assignment refreshes exactly six quick slots immediately")
		_check(
			_combined_label_text(ui.quick_bar.get_child(5)).contains(str(GameDataScript.get_item(item_id).name)),
			"planting quick slot immediately displays %s" % item_id
		)

	var mapping_before: Array[int] = inventory.quick_slot_mappings.duplicate()
	_check(not bool(ui.call("assign_planting_slot", int(slot_by_item.wood))), "wood cannot become planting item")
	_check(not bool(ui.call("assign_planting_slot", empty_slot)), "empty slot cannot become planting item")
	_check(not bool(ui.call("assign_planting_slot", -1)), "negative inventory index is rejected")
	_check(not bool(ui.call("assign_planting_slot", inventory.slots.size())), "out-of-range inventory index is rejected")
	_check(inventory.quick_slot_mappings == mapping_before, "invalid assignments preserve every quick mapping")

	var rose_slot := int(slot_by_item.rose_seed)
	var rose_panel := ui.inventory_grid.get_child(rose_slot) as PanelContainer
	_check(rose_panel.tooltip_text.contains("左键") and rose_panel.tooltip_text.contains("种植栏"), "seed slot explains left-click planting assignment")
	_check(rose_panel.mouse_filter == Control.MOUSE_FILTER_STOP, "inventory slot panel receives pointer input")
	for child in rose_panel.get_children():
		if child is Control:
			_check(child.mouse_filter == Control.MOUSE_FILTER_IGNORE, "slot content does not intercept panel clicks")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	rose_panel.gui_input.emit(click)
	_check(inventory.get_quick_item(5) == "rose_seed", "left-clicking owned seed assigns planting slot")

	ui.free()
	inventory.free()


func _combined_label_text(node: Node) -> String:
	var result: String = node.text if node is Label else ""
	for child in node.get_children():
		result += _combined_label_text(child)
	return result
