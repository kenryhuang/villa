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
		assertions.truthy(
			main.grid_system.is_navigation_cell_walkable(target_cell),
			"depleted resource releases its navigation blocker"
		)
		assertions.equal(
			main.gathering_controller.get_state_name(),
			"IDLE",
			"single-unit gathering stops after completion"
		)

	main.free()
