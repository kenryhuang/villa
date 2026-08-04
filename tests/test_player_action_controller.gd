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
	var active_quick_item := "grain_seed"
	var slots: Array[Dictionary] = [{"item_id": "grain_seed", "quantity": 2}]
	var quick_slot_mappings: Array[int] = [-1, -1, -1, -1, -1, 0]

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

	func get_quick_item(quick_index: int) -> String:
		return active_quick_item if quick_index == PlayerActionController.SEED_SLOT else ""

	func restore_state(saved_slots: Variant, saved_quick_mappings: Variant) -> void:
		slots.assign(saved_slots)
		quick_slot_mappings.assign(saved_quick_mappings)


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
	var entered_ids: Array[String] = []
	var exit_calls := 0
	var resource_allowed := true
	var placement_allowed := true
	var exhaust_after_place := false

	func enter_preview_mode(building: Variant) -> bool:
		var building_id: String = str(building)
		if building is BuildingData:
			building_id = building.building_id
		entered_ids.append(building_id)
		build_mode = true
		return true

	func exit_preview_mode() -> void:
		exit_calls += 1
		build_mode = false

	func is_in_build_mode() -> bool:
		return build_mode

	func place_selected_building(_gx: int, _gz: int) -> BuildingInstance:
		return null

	func diagnose_resources(building: Variant) -> Dictionary:
		var building_id := str(building)
		return {
			"allowed": resource_allowed,
			"code": "ok" if resource_allowed else "insufficient_resources",
			"message": "" if resource_allowed else "无法建造谷仓：木材还缺 58",
			"building_id": building_id,
			"grid": Vector2i(-1, -1),
			"missing_resources": (
				{}
				if resource_allowed
				else {
					"wood": {
						"required": 100,
						"available": 42,
						"missing": 58,
					},
				}
			),
			"blocked_cell": {},
		}

	func try_place_selected_building(gx: int, gz: int) -> Dictionary:
		if not placement_allowed:
			return {
				"placed": false,
				"instance": null,
				"diagnostic": {
					"allowed": false,
					"code": "road",
					"message": "无法建造谷仓：目标区域包含道路",
					"building_id": "barn",
					"grid": Vector2i(gx, gz),
					"missing_resources": {},
					"blocked_cell": {
						"grid": Vector2i(gx, gz),
						"state": GridCell.State.ROAD,
					},
				},
			}
		var instance := BuildingInstance.new()
		build_mode = false
		if exhaust_after_place:
			resource_allowed = false
		return {
			"placed": true,
			"instance": instance,
			"diagnostic": {
				"allowed": true,
				"code": "ok",
				"message": "",
				"building_id": "barn",
				"grid": Vector2i(gx, gz),
				"missing_resources": {},
				"blocked_cell": {},
			},
		}


class SeasonDouble:
	extends RefCounted

	var current_season := 0


class InteractionDouble:
	extends Node

	var interactions := 0

	func interact(_player: Node) -> void:
		interactions += 1


class GatheringDouble:
	extends RefCounted

	var requests: Array[Node] = []
	var cancellations: Array[String] = []
	var active := false

	func request_gather(target: Node) -> bool:
		requests.append(target)
		active = true
		return true

	func cancel_current(reason: String) -> void:
		if active:
			cancellations.append(reason)
		active = false

	func has_active_command() -> bool:
		return active


class GatherTargetDouble:
	extends Node3D

	var gathering_enabled := true
	var eligible := true

	func can_gather(_tool_id: String) -> bool:
		return true

	func is_chop_eligible() -> bool:
		return eligible


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
	_test_action_modes(assertions, tree, controller_script)
	_test_build_feedback_and_exhaustion(assertions, tree, controller_script)
	_test_farming_plant_rules(assertions)
	_test_pointer_contract(assertions, tree, controller_script)
	_test_gathering_command_routing(assertions, tree, controller_script)


func _test_gathering_command_routing(
	assertions: TestAssert,
	tree: SceneTree,
	controller_script: Script
) -> void:
	var controller = controller_script.new()
	var gathering := GatheringDouble.new()
	var target := GatherTargetDouble.new()
	tree.root.add_child(controller)
	tree.root.add_child(target)
	controller.configure(
		null,
		GridDouble.new(),
		null,
		BuildingDouble.new(),
		ToolDouble.new(),
		InventoryDouble.new()
	)
	assertions.truthy(
		controller.has_method("configure_gathering"),
		"action controller exposes gathering command injection"
	)
	if not controller.has_method("configure_gathering"):
		target.free()
		controller.free()
		return
	controller.configure_gathering(gathering)
	controller.select_slot(0)
	assertions.truthy(
		controller.perform_target_interaction(target),
		"gatherable click starts auto gathering regardless of selected tool"
	)
	assertions.equal(gathering.requests, [target], "gatherable target is routed once")
	controller.select_slot(1)
	assertions.equal(
		gathering.cancellations[-1],
		"tool_changed",
		"manual tool selection cancels active gathering"
	)
	gathering.active = true
	controller.switch_mode(PlayerActionController.ActionMode.BUILDING)
	assertions.equal(
		gathering.cancellations[-1],
		"mode_changed",
		"mode switch cancels active gathering"
	)
	gathering.active = true
	assertions.truthy(
		controller.cancel_current_selection(),
		"escape-style selection cancel is handled during gathering"
	)
	assertions.equal(
		gathering.cancellations[-1],
		"selection_cancelled",
		"escape-style cancellation stops gathering before commit"
	)
	target.free()
	controller.free()


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


func _test_action_modes(
	assertions: TestAssert,
	tree: SceneTree,
	controller_script: Script
) -> void:
	var building := BuildingDouble.new()
	var tools := ToolDouble.new()
	var grid := GridDouble.new()
	var controller = controller_script.new()
	tree.root.add_child(controller)
	controller.configure(
		null,
		grid,
		null,
		building,
		tools,
		InventoryDouble.new()
	)

	var has_mode_api: bool = (
		controller.has_method("get_action_mode")
		and controller.has_method("switch_mode")
		and controller.has_method("select_mode_slot")
		and controller.has_method("get_mode_selected_slot")
		and controller.has_method("cancel_current_selection")
	)
	assertions.truthy(has_mode_api, "controller exposes contextual action-mode API")
	if not has_mode_api:
		controller.free()
		return

	assertions.equal(controller.get_action_mode(), 0, "controller starts in farming mode")
	assertions.truthy(controller.switch_mode(1), "controller switches to building mode")
	assertions.equal(
		controller.get_mode_selected_slot(1),
		0,
		"building mode defaults to barn"
	)
	assertions.equal(building.entered_ids, ["barn"], "building mode enters barn preview")
	assertions.truthy(controller.select_mode_slot(8), "building mode accepts slot nine")
	assertions.equal(building.entered_ids[-1], "fence", "slot nine selects fence")
	assertions.truthy(not controller.select_mode_slot(9), "building mode rejects slot ten")
	assertions.equal(controller.slot_from_key(KEY_9), 8, "building maps key nine")

	assertions.truthy(controller.switch_mode(0), "controller switches back to farming")
	assertions.truthy(controller.select_mode_slot(5), "farming mode accepts slot six")
	assertions.truthy(not controller.select_mode_slot(6), "farming mode rejects slot seven")
	assertions.equal(controller.slot_from_key(KEY_7), -1, "farming rejects key seven")
	assertions.truthy(
		controller.cancel_current_selection(),
		"current contextual selection can be cancelled"
	)
	assertions.equal(controller.get_selected_slot(), -1, "cancel clears active selection")

	assertions.truthy(controller.switch_mode(1), "controller restores building mode")
	assertions.equal(
		controller.get_mode_selected_slot(1),
		8,
		"building mode remembers the last fence selection"
	)
	assertions.equal(building.entered_ids[-1], "fence", "restored building re-enters preview")
	controller.free()


func _test_build_feedback_and_exhaustion(
	assertions: TestAssert,
	tree: SceneTree,
	controller_script: Script
) -> void:
	var building := BuildingDouble.new()
	var controller = controller_script.new()
	tree.root.add_child(controller)
	controller.configure(
		null,
		GridDouble.new(),
		null,
		building,
		ToolDouble.new(),
		InventoryDouble.new()
	)
	var feedback_events: Array[Dictionary] = []
	controller.build_feedback_requested.connect(
		func(_message: String, details: Dictionary) -> void:
			feedback_events.append(details)
	)
	assertions.truthy(controller.switch_mode(1), "feedback fixture enters building mode")
	assertions.truthy(controller.cancel_current_selection(), "feedback fixture clears default building")
	building.resource_allowed = false
	assertions.truthy(
		not controller.select_mode_slot(0),
		"unaffordable building cannot be selected"
	)
	assertions.equal(controller.get_selected_slot(), -1, "rejected selection stays unselected")
	assertions.equal(
		feedback_events[-1].code,
		"insufficient_resources",
		"selection emits material feedback"
	)

	building.resource_allowed = true
	assertions.truthy(controller.select_mode_slot(0), "affordable building can be selected")
	building.placement_allowed = false
	assertions.equal(
		controller.perform_build_action(6, 7),
		null,
		"rejected placement returns no instance"
	)
	assertions.equal(feedback_events[-1].code, "road", "placement emits specific feedback")
	assertions.equal(feedback_events[-1].grid, Vector2i(6, 7), "placement feedback keeps grid")

	building.placement_allowed = true
	building.exhaust_after_place = false
	var continued: BuildingInstance = controller.perform_build_action(8, 9)
	assertions.truthy(continued != null, "successful placement returns an instance")
	assertions.truthy(building.build_mode, "sufficient materials continue building preview")
	assertions.equal(controller.get_selected_slot(), 0, "continuous build keeps selection")
	continued.free()

	building.exhaust_after_place = true
	var exhausted: BuildingInstance = controller.perform_build_action(10, 11)
	assertions.truthy(exhausted != null, "exhausting placement still succeeds")
	assertions.truthy(not building.build_mode, "exhausted materials stop preview")
	assertions.equal(controller.get_selected_slot(), -1, "exhausted materials clear selection")
	assertions.equal(
		feedback_events[-1].code,
		"continuous_build_exhausted",
		"exhausted continuous build emits feedback"
	)
	exhausted.free()
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
		var gathering := GatheringDouble.new()
		controller.gathering_controller = gathering
		controller.call("select_slot", 2)
		var tree_target := GatherTargetDouble.new()
		tree.root.add_child(tree_target)
		var hover_events: Array = []
		controller.tree_hover_changed.connect(
			func(hover_target: Node, allowed: bool) -> void: hover_events.append([hover_target, allowed])
		)
		controller.call("_update_tree_hover", tree_target)
		assertions.equal(hover_events[-1][1], true, "eligible axe hover reports green")
		tree_target.eligible = false
		controller.call("_update_tree_hover", tree_target)
		assertions.equal(hover_events[-1][1], false, "ineligible axe hover reports red")
		var rejected: Array[String] = []
		controller.gather_rejected.connect(
			func(_target: Node, reason: String) -> void: rejected.append(reason)
		)
		assertions.truthy(not controller.perform_target_interaction(tree_target), "red tree click starts no command")
		assertions.equal(rejected[-1], "tree_not_choppable", "red tree click reports a stable reason")
		assertions.equal(gathering.requests.size(), 0, "red tree click causes no movement request")
		controller.call("_clear_tree_hover")
		assertions.equal(hover_events[-1][0], null, "tool or pointer exit clears tree hover")
		tree_target.free()
	controller.free()
