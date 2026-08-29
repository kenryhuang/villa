extends RefCounted

const GameWorldScript = preload("res://scripts/world/world.gd")
const FishingSpotScene = preload("res://scenes/world/fishing_spot.tscn")
const FishingSpotDataScript = preload("res://scripts/data/fishing_spot_data.gd")
const PlayerActionControllerScript = preload("res://scripts/actors/player_action_controller.gd")
const ToolSystemScript = preload("res://scripts/systems/tool_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const MainScript = preload("res://scripts/main.gd")
const InventoryUIScript = preload("res://scripts/ui/inventory_ui.gd")
const MapUIScene = preload("res://scenes/ui/map_ui.tscn")

class FishingRecorder:
	extends Node
	var active := false
	var reel_calls := 0
	var cancel_calls := 0
	var session_id := 41

	func is_session_active() -> bool:
		return active

	func get_session_snapshot() -> Dictionary:
		return {"session_id": session_id}

	func reel(requested_session_id: int) -> Dictionary:
		reel_calls += 1
		return {"ok": requested_session_id == session_id, "reason": ""}

	func cancel(_reason: String) -> bool:
		cancel_calls += 1
		active = false
		return true


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_authored_world_spots(assertions)
	_test_spot_node_and_controller_routing(assertions, tree)
	_test_reel_owns_active_click(assertions, tree)
	_test_interact_reels_and_blocking_ui_cancels(assertions, tree)
	_test_session_feedback_text(assertions)
	_test_tool_cost_has_no_placeholder_reward(assertions, tree)


func _test_authored_world_spots(assertions: TestAssert) -> void:
	var definitions: Array[Dictionary] = GameWorldScript.fishing_spot_definitions()
	assertions.equal(definitions.size(), 4, "world authors four stable creek fishing spots")
	var ids: Array[String] = []
	for definition in definitions:
		ids.append(str(definition.get("spot_id", "")))
		assertions.equal(definition.get("fish_table_id"), "creek", "%s uses creek catch table" % definition.get("spot_id", ""))
		assertions.truthy(definition.get("stand_cell") is Vector2i, "%s has a stand cell" % definition.get("spot_id", ""))
		assertions.truthy(definition.get("water_cell") is Vector2i, "%s has a water target" % definition.get("spot_id", ""))
	assertions.equal(ids, ["east-creek-01", "east-creek-02", "west-creek-01", "west-creek-02"], "fishing spot ids and order are stable")


func _test_spot_node_and_controller_routing(assertions: TestAssert, tree: SceneTree) -> void:
	var node := FishingSpotScene.instantiate()
	tree.root.add_child(node)
	var data := _spot_data()
	assertions.truthy(node.configure(data), "fishing spot node accepts authored data")
	assertions.truthy(node.is_in_group("fishing_spot"), "fishing spot is an interaction target")
	assertions.equal(node.find_children("*", "Label3D", true, false).size(), 0, "initial spot marker has no permanent text")
	var interactions := {"count": 0}
	node.interaction_requested.connect(func(_spot: Node, _player: Variant) -> void: interactions.count += 1)
	var controller := PlayerActionControllerScript.new()
	tree.root.add_child(controller)
	controller.set("_action_mode", PlayerActionControllerScript.ActionMode.FARMING)
	controller.set("_selected_slot", 4)
	assertions.truthy(controller.perform_target_interaction(node), "selected fishing rod routes fishing-spot interaction")
	assertions.equal(interactions.count, 1, "spot interaction is forwarded exactly once")
	controller.set("_selected_slot", 0)
	assertions.truthy(not controller.perform_target_interaction(node), "non-rod tool cannot activate fishing spot")
	controller.free()
	node.free()


func _test_reel_owns_active_click(assertions: TestAssert, tree: SceneTree) -> void:
	var controller := PlayerActionControllerScript.new()
	var fishing := FishingRecorder.new()
	tree.root.add_child(controller)
	tree.root.add_child(fishing)
	assertions.truthy(controller.configure_fishing(fishing), "controller accepts fishing session authority")
	fishing.active = true
	assertions.truthy(controller.try_reel_active_fishing(), "active fishing session consumes reel input")
	assertions.equal(fishing.reel_calls, 1, "active click invokes reel once")
	controller.set("_action_mode", PlayerActionControllerScript.ActionMode.FARMING)
	controller.set("_selected_slot", 4)
	controller.select_mode_slot(0)
	assertions.equal(fishing.cancel_calls, 1, "changing tools cancels active fishing")
	controller.free()
	fishing.free()


func _test_interact_reels_and_blocking_ui_cancels(assertions: TestAssert, tree: SceneTree) -> void:
	var controller := PlayerActionControllerScript.new()
	var fishing := FishingRecorder.new()
	tree.root.add_child(controller)
	tree.root.add_child(fishing)
	controller.configure_fishing(fishing)
	fishing.active = true
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	controller.call("_unhandled_input", event)
	assertions.equal(fishing.reel_calls, 1, "interact action reels the active fishing session")
	var main := MainScript.new()
	main.fishing_system = fishing
	main.call("_cancel_fishing_for_blocking_ui")
	assertions.equal(fishing.cancel_calls, 1, "opening blocking UI cancels the fishing session")
	var inventory_ui := InventoryUIScript.new()
	var map_ui := MapUIScene.instantiate()
	tree.root.add_child(inventory_ui)
	tree.root.add_child(map_ui)
	main.inventory_ui = inventory_ui
	main.map_ui = map_ui
	main.call("_connect_blocking_ui_fishing_cancellation")
	fishing.active = true
	var inventory_key := InputEventKey.new()
	inventory_key.keycode = KEY_I
	inventory_key.pressed = true
	inventory_ui.call("_unhandled_input", inventory_key)
	assertions.equal(fishing.cancel_calls, 2, "I shortcut cancels fishing through the real inventory open path")
	fishing.active = true
	var map_key := InputEventKey.new()
	map_key.keycode = KEY_M
	map_key.pressed = true
	map_ui.call("_unhandled_input", map_key)
	assertions.equal(fishing.cancel_calls, 3, "M shortcut cancels fishing through the real map open path")
	controller.free()
	inventory_ui.free()
	map_ui.free()
	fishing.free()
	main.free()


func _test_session_feedback_text(assertions: TestAssert) -> void:
	assertions.truthy(
		"收杆" in MainScript.fishing_state_message(3),
		"bite window exposes an explicit reel prompt"
	)


func _test_tool_cost_has_no_placeholder_reward(assertions: TestAssert, tree: SceneTree) -> void:
	var inventory := InventorySystemScript.new()
	var tools := ToolSystemScript.new()
	tree.root.add_child(inventory)
	tree.root.add_child(tools)
	tools.configure(null, inventory, null, null)
	tools.switch_tool(ToolSystemScript.ToolType.FISHING_ROD)
	assertions.truthy(not tools.call("_use_fishing_rod", null), "legacy fishing tool path cannot award placeholder loot")
	assertions.equal(inventory.get_item_count("fiber"), 0, "fishing rod never creates fiber")
	var game_state := tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "fishing cost test has GameState")
	if game_state != null:
		var stamina_before := int(game_state.player_state.stamina)
		var durability_before := int(tools.get_durability("fishing_rod").current)
		assertions.truthy(tools.can_commit_fishing_cast_cost(), "tool exposes side-effect-free fishing cost preflight")
		assertions.truthy(tools.commit_fishing_cast_cost(), "fishing system can atomically commit rod cost")
		assertions.equal(game_state.player_state.stamina, stamina_before - 5, "cast cost spends fishing stamina once")
		assertions.equal(tools.get_durability("fishing_rod").current, durability_before - 1, "cast cost spends one rod durability")
		game_state.player_state.stamina = stamina_before
	tools.free()
	inventory.free()


func _spot_data() -> Resource:
	var data := FishingSpotDataScript.new()
	data.spot_id = "test-creek"
	data.water_body_id = "test-water"
	data.fish_table_id = "creek"
	data.stand_cell = Vector2i(3, 10)
	data.water_cell = Vector2i(2, 10)
	return data
