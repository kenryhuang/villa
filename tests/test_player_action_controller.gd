extends RefCounted


class ToolDouble:
	extends RefCounted

	var selected_tool := -1
	var used_targets: Array = []

	func switch_tool(tool_type: int) -> void:
		selected_tool = tool_type

	func use_tool_on(target: Variant) -> bool:
		used_targets.append(target)
		return true


class GridDouble:
	extends RefCounted

	var clear_highlights_calls := 0

	func clear_highlights() -> void:
		clear_highlights_calls += 1


class InventoryDouble:
	extends RefCounted

	var counts := {"grain_seed": 2, "grain": 0}
	var accepts_harvest := true

	func has_item(item_id: String, quantity: int = 1) -> bool:
		return get_item_count(item_id) >= quantity

	func get_item_count(item_id: String) -> int:
		return int(counts.get(item_id, 0))

	func remove_item(item_id: String, quantity: int = 1) -> bool:
		if not has_item(item_id, quantity):
			return false
		counts[item_id] = get_item_count(item_id) - quantity
		return true

	func add_item(item_id: String, quantity: int = 1) -> bool:
		counts[item_id] = get_item_count(item_id) + quantity
		return true

	func can_add_item(item_id: String, _quantity: int = 1) -> bool:
		return accepts_harvest or item_id != "grain"


class FarmingDouble:
	extends RefCounted

	var allow_plant := true
	var crop_data: CropData
	var harvest_calls := 0

	func can_plant(cell: GridCell, data: CropData) -> bool:
		return allow_plant and cell.state == GridCell.State.FARMLAND and data == crop_data

	func plant(cell: GridCell, data: CropData) -> CropInstance:
		if not can_plant(cell, data):
			return null
		var instance := CropInstance.new()
		instance.crop_data = data
		cell.crop_instance = instance
		cell.state = GridCell.State.PLANTED
		return instance

	func harvest(cell: GridCell) -> Dictionary:
		if cell.crop_instance == null or not cell.crop_instance.is_mature():
			return {}
		harvest_calls += 1
		cell.crop_instance = null
		cell.state = GridCell.State.FARMLAND
		return {"items": ["grain"], "exp": 5}


class BuildingDouble:
	extends RefCounted

	var build_mode := false

	func is_in_build_mode() -> bool:
		return build_mode

	func place_selected_building(_gx: int, _gz: int) -> BuildingInstance:
		return null


class SeasonDouble:
	extends RefCounted

	var current_season := 0


class InteractionDouble:
	extends Node

	var interactions := 0

	func interact(_player: Node) -> void:
		interactions += 1


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var controller_path := "res://scripts/actors/player_action_controller.gd"
	assertions.truthy(
		ResourceLoader.exists(controller_path),
		"player action controller script exists"
	)
	if not ResourceLoader.exists(controller_path):
		return
	var controller_script = load(controller_path)
	assertions.truthy(controller_script != null, "player action controller script loads")
	if controller_script == null:
		return

	_test_action_priority(assertions, controller_script)
	_test_selection_and_transactions(assertions, tree, controller_script)
	_test_farming_plant_rules(assertions)
	_test_pointer_contract(assertions, tree, controller_script)


func _test_action_priority(assertions: TestAssert, controller_script: Script) -> void:
	assertions.equal(
		controller_script.resolve_action(true, true, true, true, 5),
		1,
		"build mode has highest priority"
	)
	assertions.equal(
		controller_script.resolve_action(false, true, true, true, 5),
		2,
		"physical interaction precedes grid action"
	)
	assertions.equal(
		controller_script.resolve_action(false, false, true, true, 0),
		3,
		"mature crop precedes selected tool"
	)
	assertions.equal(
		controller_script.resolve_action(false, false, true, false, 5),
		4,
		"seed slot resolves planting"
	)
	assertions.equal(
		controller_script.resolve_action(false, false, true, false, 0),
		5,
		"tool slot resolves tool action"
	)


func _test_selection_and_transactions(
	assertions: TestAssert,
	tree: SceneTree,
	controller_script: Script
) -> void:
	var crop := CropData.new()
	crop.crop_id = "grain"
	crop.growth_days = 3
	crop.seasons.assign([0])

	var inventory := InventoryDouble.new()
	var farming := FarmingDouble.new()
	farming.crop_data = crop
	var tools := ToolDouble.new()
	var grid := GridDouble.new()
	var controller = controller_script.new()
	tree.root.add_child(controller)
	controller.crop_data_override = crop
	controller.configure(
		null,
		grid,
		farming,
		BuildingDouble.new(),
		tools,
		inventory
	)

	assertions.truthy(controller.select_slot(5), "seed slot can be selected")
	assertions.equal(controller.get_selected_slot(), 5, "seed selection is retained")

	assertions.truthy(
		controller.has_method("deselect_slot"),
		"controller exposes tool deselection"
	)
	if controller.has_method("deselect_slot"):
		assertions.truthy(controller.call("deselect_slot"), "selected tool can be cancelled")
		assertions.equal(controller.get_selected_slot(), -1, "cancel leaves no selected tool")
		assertions.equal(grid.clear_highlights_calls, 1, "cancel immediately clears grid highlight")

		var inactive_farmland := GridCell.new()
		inactive_farmland.state = GridCell.State.FARMLAND
		assertions.truthy(
			not controller.perform_cell_action(inactive_farmland),
			"no cell action runs while no tool is selected"
		)
		assertions.truthy(controller.select_slot(5), "slot can be selected again after cancel")

	var farmland := GridCell.new()
	farmland.state = GridCell.State.FARMLAND
	assertions.truthy(controller.perform_cell_action(farmland), "seed plants on farmland")
	assertions.equal(inventory.get_item_count("grain_seed"), 1, "successful planting consumes one seed")
	assertions.equal(farmland.state, GridCell.State.PLANTED, "successful planting changes cell state")

	var rejected := GridCell.new()
	rejected.state = GridCell.State.FARMLAND
	farming.allow_plant = false
	assertions.truthy(not controller.perform_cell_action(rejected), "rejected planting reports failure")
	assertions.equal(inventory.get_item_count("grain_seed"), 1, "rejected planting refunds seed")

	var mature := GridCell.new()
	mature.state = GridCell.State.PLANTED
	mature.crop_instance = CropInstance.new()
	mature.crop_instance.crop_data = crop
	mature.crop_instance.growth_progress = 3.0
	inventory.accepts_harvest = false
	assertions.truthy(not controller.perform_cell_action(mature), "full inventory blocks harvest")
	assertions.equal(farming.harvest_calls, 0, "blocked harvest preserves crop")

	inventory.accepts_harvest = true
	assertions.truthy(controller.perform_cell_action(mature), "mature crop can be harvested")
	assertions.equal(inventory.get_item_count("grain"), 1, "harvest adds grain")
	assertions.equal(mature.state, GridCell.State.FARMLAND, "harvest restores farmland")

	controller.free()


func _test_farming_plant_rules(assertions: TestAssert) -> void:
	var farming := FarmingSystem.new()
	farming.season_system = SeasonDouble.new()
	var crop := CropData.new()
	crop.crop_id = "grain"
	crop.seasons.assign([0])
	var farmland := GridCell.new()
	farmland.gx = 2
	farmland.gz = 3
	farmland.state = GridCell.State.FARMLAND

	var has_rule_api := farming.has_method("can_plant")
	assertions.truthy(has_rule_api, "farming exposes planting rules")
	if not has_rule_api:
		farming.free()
		return
	assertions.truthy(farming.call("can_plant", farmland, crop), "matching season allows planting")
	farming.season_system.current_season = 1
	assertions.truthy(
		not farming.call("can_plant", farmland, crop),
		"wrong season rejects planting"
	)
	farming.set_greenhouse_cells([Vector2i(2, 3)])
	assertions.truthy(
		farming.call("can_plant", farmland, crop),
		"greenhouse permits out-of-season planting"
	)
	farming.free()


func _test_pointer_contract(
	assertions: TestAssert,
	tree: SceneTree,
	controller_script: Script
) -> void:
	var controller = controller_script.new()
	tree.root.add_child(controller)
	assertions.truthy(
		controller.has_method("_unhandled_input"),
		"controller owns unhandled input"
	)
	assertions.truthy(controller.has_method("_process"), "controller owns pointer hover")
	assertions.truthy(
		controller.has_method("slot_from_key"),
		"controller exposes keyboard slot mapping"
	)
	if controller.has_method("slot_from_key"):
		assertions.equal(controller.call("slot_from_key", KEY_1), 0, "key 1 selects first slot")
		assertions.equal(controller.call("slot_from_key", KEY_6), 5, "key 6 selects seed slot")
		assertions.equal(controller.call("slot_from_key", KEY_7), -1, "key 7 is not an action slot")
	assertions.truthy(
		controller.has_method("perform_target_interaction"),
		"controller exposes physical interaction dispatch"
	)
	if controller.has_method("perform_target_interaction"):
		var target := InteractionDouble.new()
		tree.root.add_child(target)
		assertions.truthy(
			controller.call("perform_target_interaction", target),
			"left click dispatches building interaction"
		)
		assertions.equal(target.interactions, 1, "interaction target is called once")
		target.free()
	controller.free()
