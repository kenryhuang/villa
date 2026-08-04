extends RefCounted


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	assertions.truthy(packed != null, "gathering integration loads main scene")
	if packed == null:
		return
	var main = packed.instantiate()
	main.load_save_on_start = false
	tree.root.add_child(main)
	for _frame in 4:
		await tree.process_frame
		await tree.physics_frame

	assertions.truthy(main.gathering_controller != null, "main owns gathering controller")
	assertions.truthy(main.grid_pathfinder != null, "main owns gathering pathfinder")
	assertions.truthy(
		main.action_controller.gathering_controller == main.gathering_controller,
		"player click routing shares main gathering controller"
	)
	assertions.truthy(main.gathering_feedback != null, "main authors gathering feedback")
	assertions.truthy(main.tool_swing_visual != null, "player authors tool swing visual")

	var resources: Array[Node] = main.world.get_gatherable_nodes()
	assertions.truthy(resources.size() >= 20, "main exposes authored trees and mineral nodes")
	var target: Node3D
	for resource in resources:
		if str(resource.get("resource_type")) == "stone":
			target = resource as Node3D
			break
	assertions.truthy(target != null, "main has a stone gathering target")
	if target != null:
		target.remaining_units = 1
		target.call("_update_visual_stage")
		target.call("_set_gather_active", true)
		var target_cell: Vector2i = main.grid_system.world_to_grid(
			target.global_position.x,
			target.global_position.z
		)
		assertions.truthy(
			not main.grid_system.is_navigation_cell_walkable(target_cell),
			"active resource cell blocks player pathfinding"
		)
		var game_state := tree.root.get_node("GameState")
		game_state.player_state.stamina = 100
		main.season_system.hour = 8
		main.season_system.minute = 0
		main.season_system._accumulator = 0.0
		var stone_before: int = main.inventory_system.get_item_count("stone")
		var stamina_before: int = game_state.player_state.stamina
		var durability_before: int = int(main.tool_system.get_durability("pickaxe").current)
		var stone_missing_before := _missing_resource(
			main.building_system.diagnose_resources("barn"), "stone"
		)
		var stone_market_before: int = main.market_system.get_stock("stone")
		main.action_controller.select_slot(0)
		assertions.truthy(
			main.action_controller.perform_target_interaction(target),
			"main resource click starts auto gathering"
		)
		assertions.equal(
			main.tool_system.get_current_tool_id(),
			"pickaxe",
			"main resource click automatically equips pickaxe"
		)
		assertions.truthy(main.player.has_auto_movement(), "main player begins automatic movement")
		var endpoint: Vector3 = main.player._auto_path[-1]
		main.player._auto_path_index = main.player._auto_path.size() - 1
		main.player.global_position = endpoint
		main.player._update_auto_movement(0.0)
		assertions.equal(
			main.gathering_controller.get_state_name(),
			"ACTING",
			"arrival begins the timed gathering animation"
		)
		main.gathering_controller._process(1.2)
		assertions.equal(
			main.inventory_system.get_item_count("stone"),
			stone_before + 1,
			"one completed action adds exactly one stone"
		)
		assertions.equal(
			game_state.player_state.stamina,
			stamina_before - 8,
			"one completed action spends pickaxe stamina once"
		)
		assertions.equal(
			int(main.tool_system.get_durability("pickaxe").current),
			durability_before - 1,
			"one completed action spends one durability"
		)
		assertions.equal(main.season_system.hour, 8, "gathering keeps the current hour")
		assertions.equal(main.season_system.minute, 10, "gathering advances ten game minutes")
		assertions.equal(target.remaining_units, 0, "single-unit action depletes final unit")
		assertions.equal(
			_missing_resource(main.building_system.diagnose_resources("barn"), "stone"),
			stone_missing_before - 1,
			"gathered stone immediately reduces a building material shortage"
		)
		assertions.equal(
			main.market_system.get_stock("stone"),
			stone_market_before,
			"gathering does not inject stock into the market"
		)
		assertions.truthy(
			main.grid_system.is_navigation_cell_walkable(target_cell),
			"depleted resource releases its navigation blocker"
		)
		assertions.equal(
			main.gathering_controller.get_state_name(),
			"IDLE",
			"single-unit gathering stops after completion"
		)
		var sale_quote: int = main.market_system.quote_sell("stone", 1)
		var gold_before_sale: int = game_state.gold
		assertions.truthy(main.economy_system.sell_item("stone", 1), "player can actively sell gathered stone")
		assertions.equal(game_state.gold, gold_before_sale + sale_quote, "sale credits the quoted gold")
		assertions.equal(
			main.market_system.get_stock("stone"),
			stone_market_before + 1,
			"only the active sale adds gathered material to market stock"
		)

		var tree_target := _first_resource_of_type(resources, "tree", target)
		assertions.truthy(tree_target != null, "economy chain finds a designated resource tree")
		if tree_target != null:
			var wood_before: int = main.inventory_system.get_item_count("wood")
			var tree_units_before: int = int(tree_target.get("remaining_units"))
			var wood_missing_before := _missing_resource(
				main.building_system.diagnose_resources("barn"), "wood"
			)
			var wood_market_before: int = main.market_system.get_stock("wood")
			assertions.truthy(_complete_gather(main, tree_target), "real tree completes one action")
			assertions.equal(main.inventory_system.get_item_count("wood"), wood_before + 1, "tree adds one wood")
			assertions.equal(int(tree_target.get("remaining_units")), tree_units_before - 1, "tree loses one unit")
			assertions.equal(
				_missing_resource(main.building_system.diagnose_resources("barn"), "wood"),
				wood_missing_before - 1,
				"gathered wood immediately reduces the barn shortage"
			)
			assertions.equal(main.market_system.get_stock("wood"), wood_market_before, "tree gathering leaves market stock unchanged")

		var copper_target := _first_resource_of_type(resources, "copper_ore", target)
		assertions.truthy(copper_target != null, "economy chain finds a visible copper vein")
		if copper_target != null:
			var copper_before: int = main.inventory_system.get_item_count("copper_ore")
			var copper_units_before: int = int(copper_target.get("remaining_units"))
			var copper_market_before: int = main.market_system.get_stock("copper_ore")
			assertions.truthy(_complete_gather(main, copper_target), "real copper vein completes one action")
			assertions.equal(main.inventory_system.get_item_count("copper_ore"), copper_before + 1, "ore vein adds one copper ore")
			assertions.equal(int(copper_target.get("remaining_units")), copper_units_before - 1, "ore vein loses one unit")
			assertions.equal(main.market_system.get_stock("copper_ore"), copper_market_before, "ore gathering leaves market stock unchanged")

		var cancel_target: Node3D
		for resource in resources:
			if resource != target and str(resource.get("resource_type")) == "stone":
				cancel_target = resource as Node3D
				break
		assertions.truthy(cancel_target != null, "load-cancel fixture finds another resource")
		if cancel_target != null:
			assertions.truthy(
				main.gathering_controller.request_gather(cancel_target),
				"load-cancel fixture starts another command"
			)
			var cancel_endpoint: Vector3 = main.player._auto_path[-1]
			main.player._auto_path_index = main.player._auto_path.size() - 1
			main.player.global_position = cancel_endpoint
			main.player._update_auto_movement(0.0)
			assertions.equal(
				main.gathering_controller.get_state_name(),
				"ACTING",
				"load-cancel fixture owns the action clock"
			)
			var inventory_before_load: Array = main.inventory_system.slots.duplicate(true)
			var valid_save: Dictionary = main.save_manager._gather_save_data().duplicate(true)
			assertions.truthy(
				main.save_manager._apply_save_data(valid_save),
				"valid restore cancels transient action before applying"
			)
			assertions.equal(
				main.gathering_controller.get_state_name(),
				"IDLE",
				"load leaves gathering idle"
			)
			assertions.truthy(
				main.season_system._action_clock_locks.is_empty(),
				"load cancellation releases the gathering clock lock"
			)
			assertions.equal(
				main.inventory_system.slots,
				inventory_before_load,
				"cancelled pre-commit action adds no resource"
			)

	main.free()


func _complete_gather(main: Node, target: Node3D) -> bool:
	if not main.gathering_controller.request_gather(target):
		return false
	if main.player._auto_path.is_empty():
		return false
	var endpoint: Vector3 = main.player._auto_path[-1]
	main.player._auto_path_index = main.player._auto_path.size() - 1
	main.player.global_position = endpoint
	main.player._update_auto_movement(0.0)
	if main.gathering_controller.get_state_name() != "ACTING":
		return false
	main.gathering_controller._process(1.2)
	return main.gathering_controller.get_state_name() == "IDLE"


func _first_resource_of_type(
	resources: Array[Node],
	resource_type: String,
	excluded: Node = null
) -> Node3D:
	for resource in resources:
		if resource != excluded and str(resource.get("resource_type")) == resource_type:
			return resource as Node3D
	return null


func _missing_resource(diagnostic: Dictionary, item_id: String) -> int:
	var missing: Dictionary = diagnostic.get("missing_resources", {})
	var entry: Dictionary = missing.get(item_id, {})
	return int(entry.get("missing", 0))
