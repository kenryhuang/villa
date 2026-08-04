extends RefCounted

const ToolSystemScript = preload("res://scripts/systems/tool_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const ResourceNodeScript = preload("res://scripts/world/resource_node.gd")


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
	assertions.equal(preview.get("quantity"), 1, "preview reports exactly one unit")
	assertions.equal(preview.get("stamina_cost"), 8, "pickaxe preview reports stamina cost")
	assertions.equal(preview.get("durability_cost"), 1, "preview reports one durability")
	assertions.equal(preview.get("remaining_before"), 3, "preview reports capacity before action")
	assertions.equal(preview.get("remaining_after"), 2, "preview reports capacity after action")
	assertions.equal(tool.current_tool, ToolSystem.ToolType.HOE, "preview does not switch the active tool")
	assertions.equal(game_state.player_state.stamina, 100, "preview does not spend stamina")
	assertions.equal(tool.get_durability("pickaxe").current, 100, "preview does not spend durability")
	assertions.equal(inventory.get_item_count("copper_ore"), 0, "preview does not add inventory")

	var committed: Dictionary = tool.commit_gather_unit(copper)
	assertions.equal(committed.get("allowed"), true, "valid gather transaction commits")
	assertions.equal(tool.current_tool, ToolSystem.ToolType.PICKAXE, "commit automatically equips pickaxe")
	assertions.equal(inventory.get_item_count("copper_ore"), 1, "commit adds exactly one ore")
	assertions.equal(copper.remaining_units, 2, "commit removes exactly one target unit")
	assertions.equal(game_state.player_state.stamina, 92, "commit spends stamina exactly once")
	assertions.equal(tool.get_durability("pickaxe").current, 99, "commit spends one durability")

	inventory.clear()
	for slot_index in range(inventory.slots.size()):
		inventory.slots[slot_index] = {"item_id": "grain_seed", "quantity": 99}
	var full_preview: Dictionary = tool.preview_gather_unit(copper)
	assertions.equal(full_preview.get("allowed"), false, "full inventory rejects gather preview")
	assertions.equal(full_preview.get("reason"), "inventory_full", "full inventory reports a stable reason")
	assertions.equal(copper.remaining_units, 2, "rejected preview leaves target unchanged")
	assertions.equal(game_state.player_state.stamina, 92, "rejected preview leaves stamina unchanged")
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
	copper.free()
	inventory.free()
	tool.free()
	game_state.player_state.stamina = original_stamina
