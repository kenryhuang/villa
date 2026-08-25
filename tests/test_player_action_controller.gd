extends RefCounted

const MainScript = preload("res://scripts/main.gd")
const FarmStorageSystemScript = preload("res://scripts/systems/farm_storage_system.gd")


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

	func world_to_grid(_world_x: float, _world_z: float) -> Vector2i:
		return Vector2i(1, 1)


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
	var preview_reason := ""
	var preview_plant_calls: Array[Dictionary] = []
	var prepared_harvest_token: RefCounted
	var prepared_harvest: Dictionary = {}
	var harvest_publications: Dictionary = {}

	func preview_plant(cell: GridCell, plant_item_id: String) -> Dictionary:
		preview_plant_calls.append({"cell": cell, "plant_item_id": plant_item_id})
		if not preview_reason.is_empty():
			return {"ok": false, "reason": preview_reason, "crop_data": crop_data}
		if crop_data == null or plant_item_id != crop_data.plant_item_id:
			return {"ok": false, "reason": "invalid_seed_mapping", "crop_data": null}
		if not allow_plant or cell == null or cell.state != GridCell.State.FARMLAND:
			return {"ok": false, "reason": "plot_unavailable", "crop_data": crop_data}
		return {"ok": true, "reason": "", "crop_data": crop_data}

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

	func commit_plant(
		cell: GridCell,
		plant_item_id: String,
		expected_preview: Dictionary
	) -> CropInstance:
		if preview_plant(cell, plant_item_id) != expected_preview:
			return null
		return plant(cell, expected_preview.get("crop_data") as CropData)

	func harvest(cell: GridCell, expected_preview: Dictionary = {}) -> Dictionary:
		return commit_harvest(cell, expected_preview if not expected_preview.is_empty() else preview_harvest(cell))

	func commit_harvest(cell: GridCell, expected_preview: Dictionary) -> Dictionary:
		if cell.crop_instance == null or not cell.crop_instance.is_mature():
			return {}
		if preview_harvest(cell) != expected_preview:
			return {}
		harvest_calls += 1
		cell.crop_instance = null
		cell.state = GridCell.State.FARMLAND
		return {"items": ["grain"], "exp": 5}

	func prepare_harvest(cell: GridCell, expected_preview: Dictionary) -> RefCounted:
		if prepared_harvest_token != null or preview_harvest(cell) != expected_preview:
			return null
		prepared_harvest_token = RefCounted.new()
		prepared_harvest = {
			"cell": cell,
			"preview": expected_preview.duplicate(true),
			"instance": cell.crop_instance,
			"applied": false,
		}
		return prepared_harvest_token

	func apply_prepared_harvest(token: Variant) -> bool:
		if token != prepared_harvest_token or bool(prepared_harvest.applied):
			return false
		harvest_calls += 1
		var cell: GridCell = prepared_harvest.cell
		cell.crop_instance = null
		cell.state = GridCell.State.FARMLAND
		prepared_harvest.applied = true
		return true

	func rollback_prepared_harvest(token: Variant) -> bool:
		if token != prepared_harvest_token:
			return false
		if bool(prepared_harvest.applied):
			var cell: GridCell = prepared_harvest.cell
			cell.crop_instance = prepared_harvest.instance
			cell.state = GridCell.State.PLANTED
		prepared_harvest_token = null
		prepared_harvest.clear()
		return true

	func seal_prepared_harvest(token: Variant) -> RefCounted:
		if token != prepared_harvest_token or not bool(prepared_harvest.applied):
			return null
		var publication := RefCounted.new()
		harvest_publications[publication.get_instance_id()] = {
			"token": publication,
			"preview": prepared_harvest.preview.duplicate(true),
			"cell": prepared_harvest.cell,
			"instance": prepared_harvest.instance,
			"staged": false,
		}
		prepared_harvest_token = null
		prepared_harvest.clear()
		return publication

	func owns_harvest_publication(publication: Variant) -> bool:
		if not publication is RefCounted:
			return false
		var publication_id := (publication as RefCounted).get_instance_id()
		var pending: Dictionary = harvest_publications.get(publication_id, {})
		return not pending.is_empty() and pending.token == publication

	func can_arm_harvest_publication(publication: Variant) -> bool:
		return owns_harvest_publication(publication)

	func arm_harvest_publication(publication: Variant) -> void:
		if owns_harvest_publication(publication):
			harvest_publications[(publication as RefCounted).get_instance_id()].staged = true

	func cancel_harvest_publication(publication: Variant) -> bool:
		if not owns_harvest_publication(publication):
			return false
		var publication_id := (publication as RefCounted).get_instance_id()
		var pending: Dictionary = harvest_publications[publication_id]
		var cell: GridCell = pending.cell
		cell.crop_instance = pending.instance
		cell.state = GridCell.State.PLANTED
		harvest_publications.erase(publication_id)
		return true

	func stage_harvest_publication(publication: Variant) -> void:
		arm_harvest_publication(publication)

	func publish_harvest_publication(publication: Variant) -> void:
		if owns_harvest_publication(publication):
			harvest_publications.erase((publication as RefCounted).get_instance_id())

	func finalize_prepared_harvest(token: Variant) -> RefCounted:
		var publication := seal_prepared_harvest(token)
		if publication != null:
			stage_harvest_publication(publication)
		return publication

	func publish_prepared_harvest(publication: Variant) -> Dictionary:
		if not owns_harvest_publication(publication):
			return {}
		var pending: Dictionary = harvest_publications[(publication as RefCounted).get_instance_id()]
		var preview: Dictionary = pending.preview.duplicate(true)
		publish_harvest_publication(publication)
		return preview

	func preview_harvest(cell: GridCell) -> Dictionary:
		if cell.crop_instance == null or not cell.crop_instance.is_mature():
			return {}
		return {"items": {"grain": 1}, "exp": 5}


class FalseReturningPublishStorage:
	extends RefCounted
	var items: Dictionary = {}
	var transaction_token: RefCounted
	var transaction_before: Dictionary = {}
	var publication_token: RefCounted
	var publish_calls := 0

	func get_missing_capacity(_items: Dictionary) -> int:
		return 0

	func get_total_capacity() -> int:
		return 200

	func get_used_capacity() -> int:
		var used := 0
		for quantity in items.values():
			used += int(quantity)
		return used

	func begin_atomic_transaction() -> RefCounted:
		if transaction_token != null or publication_token != null:
			return null
		transaction_token = RefCounted.new()
		transaction_before = items.duplicate(true)
		return transaction_token

	func stage_add_items(token: Variant, requested: Dictionary) -> bool:
		if token != transaction_token:
			return false
		for item_id in requested:
			items[item_id] = int(items.get(item_id, 0)) + int(requested[item_id])
		return true

	func rollback_atomic_transaction(token: Variant) -> bool:
		if token != transaction_token:
			return false
		items = transaction_before.duplicate(true)
		transaction_token = null
		return true

	func seal_atomic_transaction(token: Variant) -> RefCounted:
		if token != transaction_token:
			return null
		publication_token = RefCounted.new()
		transaction_token = null
		return publication_token

	func owns_sealed_transaction(publication: Variant) -> bool:
		return publication != null and publication == publication_token

	func can_arm_sealed_transaction(publication: Variant) -> bool:
		return owns_sealed_transaction(publication)

	func arm_sealed_transaction(_publication: Variant) -> void:
		pass

	func cancel_sealed_transaction(publication: Variant) -> bool:
		if not owns_sealed_transaction(publication):
			return false
		items = transaction_before.duplicate(true)
		publication_token = null
		return true

	func publish_sealed_transaction(publication: Variant) -> bool:
		if not owns_sealed_transaction(publication):
			return false
		publish_calls += 1
		publication_token = null
		return false


class InvalidCapacityStorage:
	extends RefCounted

	func get_missing_capacity(_items: Dictionary) -> int:
		return -1

	func get_total_capacity() -> int:
		return 200

	func get_used_capacity() -> int:
		return 0


class BeginFailureStorage:
	extends InvalidCapacityStorage

	func get_missing_capacity(_items: Dictionary) -> int:
		return 0

	func begin_atomic_transaction() -> Variant:
		return null


class BuildingDouble:
	extends RefCounted

	var build_mode := false
	var entered_ids: Array[String] = []
	var exit_calls := 0
	var resource_allowed := true
	var placement_allowed := true
	var exhaust_after_place := false
	var placement_attempts := 0

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

	func update_preview_position(_world_x: float, _world_z: float) -> void:
		pass

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

	func diagnose_availability(building: Variant) -> Dictionary:
		return diagnose_resources(building)

	func try_place_selected_building(gx: int, gz: int) -> Dictionary:
		placement_attempts += 1
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


class OreTargetDouble:
	extends Node3D

	var required_tool := "pickaxe"
	var allowed := true

	func can_gather(tool_id: String) -> bool:
		return allowed and tool_id == required_tool


class OutputPileDouble:
	extends Node3D

	var hovered := false
	var interactions := 0
	var rejected_reason := ""

	func _ready() -> void:
		add_to_group("building_output_pile")

	func set_pointer_hovered(value: bool) -> void:
		hovered = value

	func show_interaction_rejected(reason: String) -> void:
		rejected_reason = reason

	func interact(_player: Node) -> void:
		interactions += 1


class InteractionPlayerDouble:
	extends Node3D

	var interaction_range := 3.0


class EconomyBuildingDouble:
	extends Node3D

	var interactions := 0
	var openable := true

	func can_open_economy_panel() -> bool:
		return openable

	func interact(_player: Node) -> void:
		interactions += 1


class PointerControllerDouble:
	extends PlayerActionController

	var interaction_target: Node

	func _pointer_over_ui() -> bool:
		return false

	func _raycast_to_ground(_pointer_position: Variant = null) -> Variant:
		return Vector3(1.0, 0.0, 1.0)

	func _raycast_to_interaction(_pointer_position: Variant = null) -> Dictionary:
		return {
			"target": interaction_target,
			"position": Vector3(1.0, 0.0, 0.0),
		}


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
	_test_harvest_failure_feedback(assertions, tree, controller_script)
	_test_post_commit_false_is_not_reported_as_failure(assertions, tree, controller_script)
	_test_action_modes(assertions, tree, controller_script)
	_test_build_feedback_and_exhaustion(assertions, tree, controller_script)
	_test_farming_plant_rules(assertions)
	_test_plant_preview_failure_reasons(assertions, tree, controller_script)
	_test_pointer_contract(assertions, tree, controller_script)
	_test_gathering_command_routing(assertions, tree, controller_script)
	_test_output_pile_interaction(assertions, tree, controller_script)
	_test_completed_building_click_in_build_mode(assertions, tree)


func _test_harvest_failure_feedback(
	assertions: TestAssert,
	tree: SceneTree,
	controller_script: Script
) -> void:
	var crop := CropData.new()
	crop.crop_id = "grain"
	crop.growth_days = 2
	var cell := GridCell.new()
	cell.state = GridCell.State.PLANTED
	cell.crop_instance = CropInstance.new()
	cell.crop_instance.crop_data = crop
	cell.crop_instance.set_growth_state(2.0, CropInstance.LifecycleState.MATURE)
	var farming := FarmingDouble.new()
	farming.crop_data = crop
	var controller = controller_script.new()
	tree.root.add_child(controller)
	controller.configure(
		null,
		null,
		farming,
		null,
		null,
		InventoryDouble.new(),
		InvalidCapacityStorage.new()
	)
	var feedback: Array[Dictionary] = []
	controller.action_feedback_requested.connect(
		func(text: String, severity: String, details: Dictionary) -> void:
			feedback.append({"text": text, "severity": severity, "details": details})
	)

	assertions.truthy(not controller._harvest(cell), "invalid storage preflight rejects harvest")
	assertions.equal(cell.state, GridCell.State.PLANTED, "failed preflight preserves mature crop")
	assertions.equal(feedback.size(), 1, "transaction failure emits one feedback")
	if not feedback.is_empty():
		assertions.equal(feedback[0].severity, "error", "transaction failure uses error severity")
		assertions.equal(feedback[0].text, "收割失败，请重试", "transaction failure has actionable text")
		assertions.truthy(
			not str(feedback[0].text).contains("已入仓"),
			"failed transaction never claims storage success"
		)
	controller.queue_free()

	var begin_failure_controller = controller_script.new()
	tree.root.add_child(begin_failure_controller)
	begin_failure_controller.configure(
		null,
		null,
		farming,
		null,
		null,
		InventoryDouble.new(),
		BeginFailureStorage.new()
	)
	var begin_feedback: Array[Dictionary] = []
	begin_failure_controller.action_feedback_requested.connect(
		func(text: String, severity: String, details: Dictionary) -> void:
			begin_feedback.append({"text": text, "severity": severity, "details": details})
	)
	assertions.truthy(
		not begin_failure_controller._harvest(cell),
		"storage transaction startup failure rejects harvest"
	)
	assertions.equal(cell.state, GridCell.State.PLANTED, "startup failure preserves mature crop")
	assertions.equal(begin_feedback.size(), 1, "startup failure emits one feedback")
	if not begin_feedback.is_empty():
		assertions.equal(begin_feedback[0].severity, "error", "startup failure uses error severity")
		assertions.equal(begin_feedback[0].text, "收割失败，请重试", "startup failure is actionable")
	begin_failure_controller.queue_free()


func _test_post_commit_false_is_not_reported_as_failure(
	assertions: TestAssert,
	tree: SceneTree,
	controller_script: Script
) -> void:
	var crop := CropData.new()
	crop.crop_id = "grain"
	crop.growth_days = 2
	var cell := GridCell.new()
	cell.gx = 4
	cell.gz = 5
	cell.state = GridCell.State.PLANTED
	cell.crop_instance = CropInstance.new()
	cell.crop_instance.crop_data = crop
	cell.crop_instance.set_growth_state(2.0, CropInstance.LifecycleState.MATURE)
	var farming := FarmingDouble.new()
	farming.crop_data = crop
	var storage := FalseReturningPublishStorage.new()
	var controller = controller_script.new()
	tree.root.add_child(controller)
	controller.configure(null, null, farming, null, null, InventoryDouble.new(), storage)

	assertions.truthy(controller._harvest(cell), "post-commit false return cannot turn success into failure")
	assertions.equal(storage.publish_calls, 1, "storage publication executes exactly once")
	assertions.equal(storage.items, {"grain": 1}, "post-commit storage state remains committed")
	assertions.equal(cell.state, GridCell.State.FARMLAND, "post-commit crop state remains committed")
	assertions.equal(controller.get_last_action_failure_details(), {}, "no failure is reported after irreversible commit")
	controller.queue_free()


func _test_completed_building_click_in_build_mode(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var player := InteractionPlayerDouble.new()
	var building_system := BuildingDouble.new()
	var economy_building := EconomyBuildingDouble.new()
	var controller := PointerControllerDouble.new()
	controller.interaction_target = economy_building
	tree.root.add_child(player)
	tree.root.add_child(economy_building)
	tree.root.add_child(controller)
	controller.configure(
		player,
		GridDouble.new(),
		null,
		building_system,
		ToolDouble.new(),
		InventoryDouble.new(),
		null
	)
	assertions.truthy(
		controller.switch_mode(PlayerActionController.ActionMode.BUILDING),
		"fixture enters building mode with an active placement preview"
	)
	assertions.truthy(
		controller.call("_perform_pointer_action", Vector2.ZERO),
		"completed production building consumes click while build mode remains active"
	)
	assertions.equal(
		economy_building.interactions,
		1,
		"completed production building click dispatches interaction"
	)
	assertions.equal(
		building_system.placement_attempts,
		0,
		"completed production building interaction precedes placement"
	)
	economy_building.openable = false
	assertions.truthy(
		controller.call("_perform_pointer_action", Vector2.ZERO),
		"non-economic building click falls through to placement"
	)
	assertions.equal(economy_building.interactions, 1, "non-economic building is not opened")
	assertions.equal(building_system.placement_attempts, 1, "placement priority remains for other targets")
	controller.queue_free()
	economy_building.queue_free()
	player.queue_free()


func _test_output_pile_interaction(
	assertions: TestAssert,
	tree: SceneTree,
	controller_script: Script
) -> void:
	var controller = controller_script.new()
	var player := InteractionPlayerDouble.new()
	var pile := OutputPileDouble.new()
	tree.root.add_child(player)
	tree.root.add_child(pile)
	tree.root.add_child(controller)
	controller.configure(
		player,
		GridDouble.new(),
		null,
		BuildingDouble.new(),
		ToolDouble.new(),
		InventoryDouble.new(),
		null
	)
	controller.switch_mode(PlayerActionController.ActionMode.FARMING)
	assertions.truthy(
		not controller.perform_target_interaction(pile),
		"controller leaves farming-mode output clicks to the pile itself"
	)
	assertions.truthy(
		controller.has_method("_try_interaction_hit"),
		"controller still exposes generic interaction hit routing"
	)
	if controller.has_method("_try_interaction_hit"):
		assertions.truthy(
			not controller.call("_try_interaction_hit", pile, Vector3(1.0, 0.0, 0.0)),
			"controller does not route nearby output clicks"
		)
	assertions.equal(pile.interactions, 0, "controller never dispatches output collection")
	controller.switch_mode(PlayerActionController.ActionMode.BUILDING)
	assertions.truthy(
		not controller.perform_target_interaction(pile),
		"controller leaves building-mode output clicks to the pile itself"
	)
	pile.rejected_reason = ""
	assertions.truthy(
		not controller.call("_try_interaction_hit", pile, Vector3(20.0, 0.0, 0.0)),
		"controller does not own distant output clicks in building mode"
	)
	assertions.equal(pile.rejected_reason, "", "controller does not mutate direct-pile feedback")
	pile.queue_free()
	player.queue_free()
	controller.queue_free()


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
		InventoryDouble.new(),
		null
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
	var crop: CropData
	for definition in MainScript.default_crop_definitions():
		if definition.crop_id == "grain":
			crop = definition
			break
	assertions.truthy(crop != null, "controller fixture resolves authoritative grain definition")
	if crop == null:
		return
	var game_data = tree.root.get_node_or_null("GameData")
	assertions.truthy(game_data != null, "controller fixture has authoritative GameData")
	if game_data == null:
		return
	if game_data.get_crop_for_plant_item(crop.plant_item_id) == null:
		assertions.truthy(game_data.register_crop(crop), "controller fixture crop registers")

	var inventory := InventoryDouble.new()
	var farming := FarmingDouble.new()
	farming.crop_data = crop
	var tools := ToolDouble.new()
	var grid := GridDouble.new()
	var controller = controller_script.new()
	tree.root.add_child(controller)
	var farm_storage = FarmStorageSystemScript.new()
	tree.root.add_child(farm_storage)
	controller.crop_data_override = crop
	controller.configure(
		null,
		grid,
		farming,
		BuildingDouble.new(),
		tools,
		inventory,
		farm_storage
	)
	var action_feedback: Array[Dictionary] = []
	var has_action_feedback: bool = controller.has_signal("action_feedback_requested")
	assertions.truthy(
		has_action_feedback,
		"controller exposes structured action feedback"
	)
	if has_action_feedback:
		controller.connect(
			"action_feedback_requested",
			func(text: String, severity: String, details: Dictionary) -> void:
				action_feedback.append({
					"text": text,
					"severity": severity,
					"details": details.duplicate(true),
				})
		)
	var selector_requests: Array = []
	controller.seed_selection_requested.connect(
		func(cell: GridCell) -> void: selector_requests.append(cell)
	)
	assertions.equal(controller.get_action_mode(), -1, "controller starts without an action mode")
	assertions.equal(controller.get_selected_slot(), -1, "controller starts without a selected slot")
	assertions.truthy(controller.has_method("set_selected_plant_item_id"), "controller exposes explicit planting selection setter")
	assertions.truthy(controller.has_method("get_last_action_failure_details"), "controller exposes general action failure details")
	if controller.has_method("set_selected_plant_item_id"):
		assertions.truthy(controller.set_selected_plant_item_id("grain_seed"), "authoritative seed mapping can be selected")
		assertions.equal(controller.get_action_mode(), -1, "restoring a seed does not enter farming mode")
		assertions.equal(controller.get_selected_slot(), -1, "restoring a seed does not select slot 6")
		assertions.equal(selector_requests.size(), 0, "restoring a seed does not request the selector")
		inventory.active_quick_item = "unknown_seed"
		inventory.counts["grain_seed"] = 0
		assertions.equal(controller.get_selected_plant_item_id(), "grain_seed", "explicit selection persists at zero quantity")
		assertions.truthy(not controller.set_selected_plant_item_id("grain"), "crop category cannot be selected for planting")
		assertions.truthy(not controller.set_selected_plant_item_id("unknown_seed"), "unmapped seed id cannot be selected")
		assertions.equal(controller.get_selected_plant_item_id(), "grain_seed", "rejected selection preserves prior explicit seed")
		assertions.truthy(controller.set_selected_plant_item_id(""), "empty selection clears explicit seed")
		assertions.equal(controller.get_selected_plant_item_id(), "", "cleared selection stays independent of quick-slot mappings")
		inventory.active_quick_item = "grain_seed"
		inventory.counts["grain_seed"] = 2
		assertions.truthy(controller.set_selected_plant_item_id("grain_seed"), "explicit grain selection restores for planting")
	var unregistered_grain := CropData.new()
	unregistered_grain.crop_id = "unregistered_grain"
	unregistered_grain.plant_item_id = "unregistered_grain_seed"
	unregistered_grain.growth_days = 3
	controller.crop_data_override = unregistered_grain
	assertions.truthy(
		controller._get_crop_data("unregistered_grain_seed") == null,
		"matching but unregistered override is rejected"
	)
	var wrong_plant_item := CropData.new()
	wrong_plant_item.crop_id = "grain"
	wrong_plant_item.plant_item_id = "carrot_seed"
	wrong_plant_item.growth_days = 3
	controller.crop_data_override = wrong_plant_item
	assertions.truthy(
		controller._get_crop_data("grain_seed") == null,
		"registered crop id cannot authorize a mismatched planting item override"
	)
	controller.crop_data_override = crop
	assertions.truthy(
		controller._get_crop_data("carrot_seed") == null,
		"carrot seed cannot resolve an explicit grain override"
	)
	var unmapped_grain := CropData.new()
	unmapped_grain.crop_id = "grain"
	controller.crop_data_override = unmapped_grain
	assertions.truthy(
		controller._get_crop_data("carrot_seed") == null,
		"carrot seed cannot resolve a grain override without planting metadata"
	)
	controller.crop_data_override = crop

	assertions.truthy(controller.select_slot(5), "seed slot can be selected")
	assertions.equal(controller.get_selected_slot(), 5, "seed selection is retained")
	selector_requests.clear()
	assertions.truthy(controller.set_selected_plant_item_id(""), "seed selection can be cleared while slot six stays active")
	var empty_seed_farmland := GridCell.new()
	empty_seed_farmland.state = GridCell.State.FARMLAND
	assertions.truthy(
		not controller.perform_cell_action(empty_seed_farmland),
		"planting without a selected seed fails"
	)
	assertions.equal(
		selector_requests.size(),
		0,
		"clicking farmland without a seed does not reopen the selector"
	)
	assertions.truthy(controller.set_selected_plant_item_id("grain_seed"), "seed selection restores after empty-seed regression")

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
	mature.crop_instance.set_growth_state(3.0, CropInstance.LifecycleState.MATURE)
	assertions.truthy(farm_storage.restore_items_unchecked({"grain": 200}), "harvest fixture fills central storage")
	assertions.truthy(not controller.perform_cell_action(mature), "full storage blocks harvest")
	assertions.equal(farming.harvest_calls, 0, "blocked harvest preserves crop")
	if controller.has_method("get_last_action_failure_details"):
		var capacity_failure: Dictionary = controller.get_last_action_failure_details()
		assertions.equal(capacity_failure.get("reason"), "storage_capacity", "full storage has stable failure reason")
		assertions.equal(capacity_failure.get("storage_capacity"), 200, "failure reports total storage capacity")
		assertions.equal(capacity_failure.get("storage_used"), 200, "failure reports used storage capacity")
		assertions.equal(capacity_failure.get("missing_capacity"), 1, "failure reports exact missing capacity")
	assertions.equal(action_feedback.size(), 1, "full storage emits one harvest feedback")
	if not action_feedback.is_empty():
		assertions.equal(
			action_feedback[-1].text,
			"仓库容量不足，还需 1 容量",
			"capacity feedback reports exact shortage"
		)
		assertions.equal(
			action_feedback[-1].severity,
			"warning",
			"capacity feedback is a warning"
		)

	assertions.truthy(farm_storage.restore_items_unchecked({}), "harvest fixture clears central storage")
	var inventory_changed_calls := 0
	controller.inventory_changed.connect(func() -> void: inventory_changed_calls += 1)
	assertions.truthy(controller.perform_cell_action(mature), "mature crop can be harvested")
	assertions.equal(inventory.get_item_count("grain"), 0, "harvest never adds crops to backpack")
	assertions.equal(farm_storage.get_count("grain"), 1, "harvest adds crops to central storage")
	assertions.equal(inventory_changed_calls, 0, "storage-only harvest emits no controller inventory change")
	assertions.equal(mature.state, GridCell.State.FARMLAND, "harvest restores farmland")
	assertions.equal(action_feedback.size(), 2, "successful harvest emits one additional feedback")
	if action_feedback.size() >= 2:
		assertions.equal(
			action_feedback[-1].text,
			"收获谷物 ×1，已入仓",
			"success feedback uses localized committed quantity"
		)
		assertions.equal(
			action_feedback[-1].severity,
			"success",
			"committed harvest uses success severity"
		)
	if controller.has_method("get_last_action_failure_details"):
		assertions.equal(controller.get_last_action_failure_details(), {}, "successful harvest clears prior failure")

	controller.free()
	farm_storage.free()


func _test_plant_preview_failure_reasons(
	assertions: TestAssert,
	tree: SceneTree,
	controller_script: Script
) -> void:
	var game_data := tree.root.get_node_or_null("GameData")
	assertions.truthy(game_data != null, "plant action preview fixture has GameData")
	if game_data == null:
		return
	var crop: CropData = game_data.get_crop_for_plant_item("grain_seed")
	assertions.truthy(crop != null, "plant action preview fixture resolves grain seed")
	if crop == null:
		return
	var inventory := InventoryDouble.new()
	var farming := FarmingDouble.new()
	farming.crop_data = crop
	var controller = controller_script.new()
	tree.root.add_child(controller)
	controller.configure(
		null,
		GridDouble.new(),
		farming,
		BuildingDouble.new(),
		ToolDouble.new(),
		inventory,
		null
	)
	assertions.truthy(controller.set_selected_plant_item_id("grain_seed"), "preview fixture selects the authoritative seed")
	var cell := GridCell.new()
	cell.state = GridCell.State.FARMLAND
	assertions.truthy(controller.has_method("preview_plant_action"), "controller exposes planting action preview")
	if not controller.has_method("preview_plant_action"):
		controller.free()
		return

	inventory.counts["grain_seed"] = 0
	var no_seed: Dictionary = controller.call("preview_plant_action", cell)
	assertions.equal(no_seed.get("reason"), "no_seed", "valid planting item with zero quantity has stable no_seed reason")
	assertions.equal(farming.preview_plant_calls[-1].plant_item_id, "grain_seed", "controller asks FarmingSystem before quantity rejection")

	inventory.counts["grain_seed"] = 1
	for reason in ["invalid_seed_mapping", "plot_unavailable", "wrong_season", "greenhouse_required"]:
		farming.preview_reason = reason
		var rejected: Dictionary = controller.call("preview_plant_action", cell)
		assertions.equal(rejected.get("reason"), reason, "controller preserves farming reason %s" % reason)

	farming.preview_reason = "invalid_seed_mapping"
	inventory.active_quick_item = "unknown_seed"
	var invalid_mapping: Dictionary = controller.call("preview_plant_action", cell)
	assertions.equal(invalid_mapping.get("reason"), "invalid_seed_mapping", "authoritative preview reason remains stable")
	assertions.equal(farming.preview_plant_calls[-1].plant_item_id, "grain_seed", "quick-slot content cannot replace independent seed selection")
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
		InventoryDouble.new(),
		null
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

	assertions.equal(controller.get_action_mode(), -1, "controller starts without an action mode")
	assertions.equal(controller.get_selected_slot(), -1, "controller starts without a selected slot")
	assertions.equal(controller.slot_from_key(KEY_1), -1, "numeric shortcuts stay inactive before P or B")
	for method_name in [
		"get_building_category", "get_current_building_ids", "get_building_id_at",
		"cycle_building_category", "set_building_category",
		"get_building_availability_diagnostic",
	]:
		assertions.truthy(controller.has_method(method_name), "controller exposes %s" % method_name)
	if not controller.has_method("get_building_category"):
		controller.free()
		return
	assertions.equal(controller.get_building_category(), "basic", "building catalog starts in basic category")
	assertions.equal(
		controller.get_current_building_ids(),
		["workbench", "stone_kiln", "barn", "well"],
		"basic category exposes four ordered buildings"
	)
	assertions.truthy(controller.switch_mode(PlayerActionController.ActionMode.BUILDING), "controller switches to building mode")
	assertions.equal(
		controller.get_mode_selected_slot(PlayerActionController.ActionMode.BUILDING),
		0,
		"building mode defaults to first basic building"
	)
	assertions.equal(building.entered_ids, ["workbench"], "building mode enters workbench preview")
	assertions.truthy(controller.select_mode_slot(3), "building mode accepts slot four")
	assertions.equal(building.entered_ids[-1], "well", "slot four selects well")
	assertions.truthy(not controller.select_mode_slot(4), "building mode rejects slot five")
	assertions.equal(controller.slot_from_key(KEY_4), 3, "building maps key four")
	assertions.equal(controller.slot_from_key(KEY_5), -1, "building rejects key five")
	var exits_before_category := building.exit_calls
	assertions.truthy(controller.cycle_building_category(1), "building mode cycles to the next category")
	assertions.equal(controller.get_building_category(), "production", "next building category is production")
	assertions.equal(
		controller.get_current_building_ids(),
		["windmill", "furnace", "food_workshop", "textile_machine"],
		"production category uses catalog order"
	)
	assertions.equal(controller.get_selected_slot(), -1, "category change clears building selection")
	assertions.equal(building.exit_calls, exits_before_category + 1, "category change exits active preview")
	var category_event := InputEventKey.new()
	category_event.pressed = true
	category_event.keycode = KEY_E
	controller._unhandled_input(category_event)
	assertions.equal(controller.get_building_category(), "farming", "E cycles building category forward")
	category_event.keycode = KEY_Q
	controller._unhandled_input(category_event)
	assertions.equal(controller.get_building_category(), "production", "Q cycles building category backward")
	assertions.truthy(controller.set_building_category("basic"), "category can be selected directly")
	assertions.truthy(controller.select_mode_slot(3), "basic selection can be restored after category change")

	var selector_requests: Array = []
	controller.seed_selection_requested.connect(
		func(cell: GridCell) -> void: selector_requests.append(cell)
	)
	assertions.truthy(controller.switch_mode(PlayerActionController.ActionMode.FARMING), "controller switches back to farming")
	assertions.equal(selector_requests.size(), 0, "entering farming mode does not request the selector")
	assertions.truthy(controller.select_mode_slot(5), "farming mode accepts slot six")
	assertions.equal(selector_requests.size(), 1, "explicit slot six requests the selector exactly once")
	assertions.truthy(not controller.select_mode_slot(6), "farming mode rejects slot seven")
	assertions.equal(controller.slot_from_key(KEY_7), -1, "farming rejects key seven")
	assertions.truthy(
		controller.cancel_current_selection(),
		"current contextual selection can be cancelled"
	)
	assertions.equal(controller.get_selected_slot(), -1, "cancel clears active selection")

	assertions.truthy(controller.switch_mode(PlayerActionController.ActionMode.BUILDING), "controller restores building mode")
	assertions.equal(
		controller.get_mode_selected_slot(PlayerActionController.ActionMode.BUILDING),
		3,
		"building mode remembers the last well selection"
	)
	assertions.equal(building.entered_ids[-1], "well", "restored building re-enters preview")
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
		InventoryDouble.new(),
		null
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
	assertions.equal(controller.get_selected_slot(), 0, "failed placement keeps building selected")
	assertions.truthy(building.build_mode, "failed placement keeps preview available for retry")

	building.placement_allowed = true
	building.exhaust_after_place = false
	var placed: BuildingInstance = controller.perform_build_action(8, 9)
	assertions.truthy(placed != null, "successful placement returns an instance")
	assertions.equal(
		controller.get_action_mode(),
		PlayerActionController.ActionMode.BUILDING,
		"successful placement keeps building mode"
	)
	assertions.truthy(not building.build_mode, "successful placement removes preview shadow")
	assertions.equal(controller.get_selected_slot(), -1, "successful placement clears selection")
	assertions.equal(
		controller.get_mode_selected_slot(PlayerActionController.ActionMode.BUILDING),
		-1,
		"successful placement does not restore the building on mode changes"
	)
	placed.free()
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
	var grid := GridDouble.new()
	controller.grid_system = grid
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
		assertions.truthy(
			controller.switch_mode(PlayerActionController.ActionMode.FARMING),
			"pointer fixture explicitly enters farming mode"
		)
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
		var clears_before_axe := grid.clear_highlights_calls
		controller.call("select_slot", 2)
		assertions.equal(
			grid.clear_highlights_calls,
			clears_before_axe + 1,
			"selecting the axe immediately clears the farming cell shadow"
		)
		assertions.truthy(
			controller.has_method("should_show_cell_highlight"),
			"controller exposes cell-highlight eligibility"
		)
		if controller.has_method("should_show_cell_highlight"):
			assertions.truthy(
				not bool(controller.call("should_show_cell_highlight")),
				"axe selection keeps the farming cell shadow hidden"
			)
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
		var clears_before_pickaxe := grid.clear_highlights_calls
		controller.call("select_slot", 3)
		assertions.equal(
			grid.clear_highlights_calls,
			clears_before_pickaxe + 1,
			"selecting the pickaxe immediately clears the farming cell shadow"
		)
		assertions.truthy(
			not bool(controller.call("should_show_cell_highlight")),
			"pickaxe selection keeps the farming cell shadow hidden"
		)
		assertions.truthy(
			controller.has_signal("gather_hover_changed"),
			"controller exposes a generalized gather hover signal"
		)
		assertions.truthy(
			controller.has_method("_update_gather_hover"),
			"controller exposes tool-aware gather hover qualification"
		)
		if (
			controller.has_signal("gather_hover_changed")
			and controller.has_method("_update_gather_hover")
		):
			var ore_target := OreTargetDouble.new()
			tree.root.add_child(ore_target)
			var ore_hover_events: Array = []
			controller.connect(
				"gather_hover_changed",
				func(hover_target: Node, allowed: bool) -> void:
					ore_hover_events.append([hover_target, allowed])
			)
			controller.call("_update_gather_hover", ore_target)
			assertions.equal(ore_hover_events[-1], [ore_target, true], "mineable ore hover reports green")
			ore_target.allowed = false
			controller.call("_update_gather_hover", ore_target)
			assertions.equal(ore_hover_events[-1], [ore_target, false], "unavailable ore hover reports red")
			var non_mineral := GatherTargetDouble.new()
			tree.root.add_child(non_mineral)
			controller.call("_update_gather_hover", non_mineral)
			assertions.equal(ore_hover_events[-1][0], null, "pickaxe hover ignores non-mineral targets")
			non_mineral.free()
			ore_target.free()
	controller.free()
