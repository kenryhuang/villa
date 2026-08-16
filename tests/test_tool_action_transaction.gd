extends RefCounted

const ToolSystemScript = preload("res://scripts/systems/tool_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const ResourceNodeScript = preload("res://scripts/world/resource_node.gd")
const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")


class GridDouble:
	extends RefCounted

	func set_cell_state(gx: int, gz: int, next_state: int) -> bool:
		if gx < 0 or gz < 0 or next_state != GridCell.State.FARMLAND:
			return false
		return true

	func water_cell(_gx: int, _gz: int) -> bool:
		return false


class ReentrantTarget:
	extends Node3D

	var resource_id := "reentrant-stone"
	var resource_type := "stone"
	var item_id := "stone"
	var required_tool := "pickaxe"
	var max_units := 2
	var remaining_units := 2
	var tool_system
	var nested_result: Dictionary = {}

	func can_gather(tool_id: String) -> bool:
		return tool_id == required_tool and remaining_units > 0

	func preview_reward(tool_id: String) -> Dictionary:
		return {item_id: 1} if can_gather(tool_id) else {}

	func commit_gather(tool_id: String, _day: int = 0) -> Dictionary:
		if not can_gather(tool_id):
			return {}
		nested_result = tool_system.commit_gather_unit(self)
		remaining_units -= 1
		return {item_id: 1}

	func to_dict() -> Dictionary:
		return {"remaining_units": remaining_units}

	func from_dict(data: Dictionary) -> bool:
		remaining_units = int(data.remaining_units)
		return true


class FaultyCommitTarget:
	extends ResourceNode

	func commit_gather(tool_id: String, total_day: int = 0) -> Dictionary:
		var reward := super(tool_id, total_day)
		if reward.is_empty():
			return reward
		return {"coal": 1}


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var game_state = tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "tool transaction test has GameState")
	if game_state == null:
		return
	var original_stamina: int = game_state.player_state.stamina
	game_state.player_state.stamina = 100

	var tool = ToolSystemScript.new()
	tree.root.add_child(tool)
	tool.configure(GridDouble.new(), null, null)
	tool.switch_tool(ToolSystem.ToolType.HOE)

	var invalid := GridCell.new()
	invalid.gx = 1
	invalid.gz = 1
	invalid.state = GridCell.State.FARMLAND
	assertions.truthy(not tool.use_tool_on(invalid), "hoe rejects existing farmland")
	assertions.equal(
		game_state.player_state.stamina,
		100,
		"invalid hoe action consumes no stamina"
	)

	var valid := GridCell.new()
	valid.gx = 2
	valid.gz = 2
	valid.state = GridCell.State.WASTELAND
	assertions.truthy(tool.use_tool_on(valid), "hoe accepts wasteland")
	assertions.equal(
		game_state.player_state.stamina,
		95,
		"successful hoe action consumes stamina"
	)

	var crop_grid := GridSystemScript.new()
	var farming := FarmingSystemScript.new()
	farming.configure(crop_grid, null, null)
	crop_grid.set_cell_state(4, 4, GridCell.State.FARMLAND)
	var withered_crop := CropDataScript.new()
	withered_crop.crop_id = "withered_tool_crop"
	withered_crop.growth_days = 3
	var withered_cell := crop_grid.get_cell(4, 4)
	var withered_instance: CropInstance = farming.plant(withered_cell, withered_crop)
	withered_instance.set_lifecycle_state(CropInstance.LifecycleState.WITHERED)
	tool.configure(crop_grid, null, null, farming)
	tool.switch_tool(ToolSystem.ToolType.HOE)
	game_state.player_state.stamina = 100
	var hoe_durability_before := int(tool.get_durability("hoe").current)
	assertions.truthy(tool.use_tool_on(withered_cell), "hoe clears a withered planted crop")
	assertions.equal(withered_cell.state, GridCell.State.FARMLAND, "hoe clearing restores farmland")
	assertions.truthy(withered_cell.crop_instance == null, "hoe clearing removes withered crop")
	assertions.equal(game_state.player_state.stamina, 95, "successful withered clearing consumes normal hoe stamina")
	assertions.equal(int(tool.get_durability("hoe").current), hoe_durability_before - 1, "successful withered clearing consumes one hoe durability")
	farming.free()
	crop_grid.free()

	var inventory := InventorySystemScript.new()
	tree.root.add_child(inventory)
	tool.configure(GridDouble.new(), inventory, null)
	tool.switch_tool(ToolSystem.ToolType.HOE)
	game_state.player_state.stamina = 100
	var copper := ResourceNodeScript.new()
	assertions.truthy(copper.configure_resource({
		"resource_id": "transaction-copper",
		"resource_type": "copper_ore",
		"position": Vector3.ZERO,
	}), "transaction fixture configures a copper node")
	var preview: Dictionary = tool.preview_gather_unit(copper)
	assertions.equal(preview.get("allowed"), true, "gather preview allows a valid target")
	assertions.equal(preview.get("reason"), "", "valid gather preview has no error")
	assertions.equal(preview.get("tool_id"), "pickaxe", "preview automatically selects the required tool")
	assertions.equal(preview.get("item_id"), "copper_ore", "preview reports visible ore item")
	assertions.equal(preview.get("quantity"), 3, "preview reports the whole copper vein")
	assertions.equal(preview.get("stamina_cost"), 8, "pickaxe preview reports stamina cost")
	assertions.equal(preview.get("durability_cost"), 1, "preview reports one durability")
	assertions.equal(preview.get("remaining_before"), 3, "preview reports capacity before action")
	assertions.equal(preview.get("remaining_after"), 0, "preview reports full depletion after action")
	assertions.equal(tool.current_tool, ToolSystem.ToolType.HOE, "preview does not switch the active tool")
	assertions.equal(game_state.player_state.stamina, 100, "preview does not spend stamina")
	assertions.equal(tool.get_durability("pickaxe").current, 100, "preview does not spend durability")
	assertions.equal(inventory.get_item_count("copper_ore"), 0, "preview does not add inventory")

	var committed: Dictionary = tool.commit_gather_unit(copper)
	assertions.equal(committed.get("allowed"), true, "valid gather transaction commits")
	assertions.equal(tool.current_tool, ToolSystem.ToolType.PICKAXE, "commit automatically equips pickaxe")
	assertions.equal(inventory.get_item_count("copper_ore"), 3, "commit adds the full copper vein")
	assertions.equal(copper.remaining_units, 0, "commit depletes the full copper vein")
	assertions.equal(game_state.player_state.stamina, 92, "commit spends stamina exactly once")
	assertions.equal(tool.get_durability("pickaxe").current, 99, "commit spends one durability")

	var tree_image := Image.create_empty(16, 24, false, Image.FORMAT_RGBA8)
	var tree_texture := ImageTexture.create_from_image(tree_image)
	var atlas_image := Image.create_empty(64, 24, false, Image.FORMAT_RGBA8)
	var atlas_texture := ImageTexture.create_from_image(atlas_image)
	var fresh_tree := TreeInstanceScript.new()
	fresh_tree.configure({
		"id": "transaction-tree",
		"variant": "pine-small",
		"x": 0.0,
		"z": 0.0,
		"width": 2.0,
		"height": 3.0,
		"clearance": 1.0,
	}, tree_texture, 0.0, atlas_texture)
	for slot_index in range(inventory.slots.size()):
		inventory.slots[slot_index] = {"item_id": "grain_seed", "quantity": 99}
	inventory.slots[0] = {"item_id": "wood", "quantity": 95}
	var capacity_rejection := tool.preview_gather_unit(fresh_tree)
	assertions.equal(capacity_rejection.get("reason"), "inventory_full", "tree needs room for all five wood")
	assertions.equal(fresh_tree.remaining_units, 5, "batch preflight never damages the tree")
	inventory.clear()
	var tree_preview := tool.preview_gather_unit(fresh_tree)
	assertions.equal(tree_preview.get("quantity"), 5, "fresh tree preview reports its full five wood")
	assertions.equal(tree_preview.get("remaining_after"), 0, "fresh tree preview reports full depletion")
	assertions.equal(tree_preview.get("stamina_cost"), 8, "one tree costs eight stamina")
	var tree_result := tool.commit_gather_unit(fresh_tree)
	assertions.equal(tree_result.get("allowed"), true, "fresh tree commits as one transaction")
	assertions.equal(inventory.get_item_count("wood"), 5, "fresh tree grants five wood at once")
	assertions.equal(fresh_tree.remaining_units, 0, "fresh tree is fully depleted by one click")
	assertions.equal(tool.get_durability("axe").current, 99, "one tree costs one axe durability")

	var partial_tree := TreeInstanceScript.new()
	partial_tree.configure({
		"id": "transaction-partial-tree",
		"variant": "pine-small",
		"x": 0.0,
		"z": 0.0,
		"width": 2.0,
		"height": 3.0,
		"clearance": 1.0,
	}, tree_texture, 0.0, atlas_texture)
	partial_tree.remaining_units = 3
	partial_tree.call("_update_visual_stage")
	var partial_preview := tool.preview_gather_unit(partial_tree)
	assertions.equal(partial_preview.get("quantity"), 3, "legacy partial tree previews only remaining wood")
	assertions.truthy(tool.commit_gather_unit(partial_tree).get("allowed"), "legacy partial tree commits once")
	assertions.equal(inventory.get_item_count("wood"), 8, "partial tree grants only three remaining wood")

	var faulty := FaultyCommitTarget.new()
	assertions.truthy(faulty.configure_resource({
		"resource_id": "faulty-final-stone",
		"resource_type": "stone",
		"position": Vector3.ZERO,
		"max_units": 1,
	}), "faulty final-unit target configures")
	var active_events: Array[bool] = []
	faulty.gathering_active_changed.connect(
		func(_id: String, active: bool) -> void: active_events.append(active)
	)
	var stone_before_fault: int = inventory.get_item_count("stone")
	var stamina_before_fault: int = game_state.player_state.stamina
	var durability_before_fault: int = int(tool.get_durability("pickaxe").current)
	var faulty_result: Dictionary = tool.commit_gather_unit(faulty)
	assertions.equal(faulty_result.get("reason"), "target_changed", "invalid target commit rolls back")
	assertions.equal(faulty.remaining_units, 1, "rollback restores the final resource unit")
	assertions.equal(active_events.size(), 0, "rollback publishes no transient depletion event")
	assertions.equal(inventory.get_item_count("stone"), stone_before_fault, "rollback restores inventory")
	assertions.equal(game_state.player_state.stamina, stamina_before_fault, "rollback restores stamina")
	assertions.equal(int(tool.get_durability("pickaxe").current), durability_before_fault, "rollback restores durability")

	inventory.clear()
	copper.remaining_units = 2
	copper.call("_update_visual_stage")
	copper.call("_set_gather_active", true)
	for slot_index in range(inventory.slots.size()):
		inventory.slots[slot_index] = {"item_id": "grain_seed", "quantity": 99}
	var full_preview: Dictionary = tool.preview_gather_unit(copper)
	assertions.equal(full_preview.get("allowed"), false, "full inventory rejects the whole remaining ore batch")
	assertions.equal(full_preview.get("reason"), "inventory_full", "whole-batch capacity failure reports a stable reason")
	assertions.equal(copper.remaining_units, 2, "rejected whole-batch preview leaves target unchanged")
	assertions.equal(game_state.player_state.stamina, 76, "rejected preview leaves stamina unchanged")
	inventory.clear()

	var reentrant := ReentrantTarget.new()
	reentrant.tool_system = tool
	game_state.player_state.stamina = 100
	var reentrant_result: Dictionary = tool.commit_gather_unit(reentrant)
	assertions.equal(reentrant_result.get("allowed"), true, "outer reentrant transaction commits")
	assertions.equal(reentrant.nested_result.get("reason"), "transaction_busy", "nested commit is rejected")
	assertions.equal(reentrant.remaining_units, 1, "reentrant target loses only one unit")
	assertions.equal(inventory.get_item_count("stone"), 1, "reentrant transaction adds only one item")
	assertions.equal(game_state.player_state.stamina, 92, "reentrant transaction spends stamina once")
	assertions.equal(tool.get_durability("pickaxe").current, 98, "reentrant transaction spends durability once")
	game_state.player_state.stamina = 7
	assertions.equal(
		tool.preview_gather_unit(reentrant).get("reason"),
		"insufficient_stamina",
		"preview reports insufficient stamina before movement"
	)
	game_state.player_state.stamina = 100
	tool.tool_durability["pickaxe"]["current"] = 0
	assertions.equal(
		tool.preview_gather_unit(reentrant).get("reason"),
		"tool_broken",
		"preview reports a broken required tool before movement"
	)
	assertions.equal(reentrant.remaining_units, 1, "failed preflight leaves target state untouched")
	assertions.equal(inventory.get_item_count("stone"), 1, "failed preflight leaves inventory untouched")

	reentrant.free()
	partial_tree.free()
	fresh_tree.free()
	faulty.free()
	copper.free()
	inventory.free()
	tool.free()
	game_state.player_state.stamina = original_stamina
