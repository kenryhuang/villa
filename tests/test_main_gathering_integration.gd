extends RefCounted

const ResourceNodeScript = preload("res://scripts/world/resource_node.gd")
const ORE_MINING_ATLAS_PATH := "res://assets/resources/mining/ore-mining-sheet.png"


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
	assertions.near(main.player.global_position.x, 0.0, 0.05, "late-instantiated main keeps the player at the authored spawn x")
	assertions.near(main.player.global_position.z, 0.0, 0.05, "late-instantiated main keeps the player at the authored spawn z")

	assertions.truthy(main.gathering_controller != null, "main owns gathering controller")
	assertions.truthy(main.grid_pathfinder != null, "main owns gathering pathfinder")
	assertions.truthy(
		main.action_controller.gathering_controller == main.gathering_controller,
		"player click routing shares main gathering controller"
	)
	assertions.truthy(main.gathering_feedback != null, "main authors gathering feedback")
	assertions.truthy(main.tool_swing_visual != null, "player authors tool swing visual")
	assertions.truthy(
		main.action_controller.is_connected(
			"gather_hover_changed", Callable(main.gathering_feedback, "show_tree_hover")
		),
		"main binds generalized resource hover to the eligibility ring"
	)

	var resources: Array[Node] = main.world.get_gatherable_nodes()
	assertions.truthy(resources.size() >= 20, "main exposes authored trees and mineral nodes")
	var obstacles: Array[Node] = main.world.get_navigation_obstacle_nodes()
	var decorative_tree_cells := {}
	for obstacle in obstacles:
		if bool(obstacle.get("gathering_enabled")):
			continue
		var obstacle_position: Vector3 = (obstacle as Node3D).global_position
		var obstacle_cell: Vector2i = main.grid_system.world_to_grid(
			obstacle_position.x, obstacle_position.z
		)
		decorative_tree_cells[obstacle_cell] = true
		assertions.truthy(
			not main.grid_system.is_navigation_cell_walkable(obstacle_cell),
			"decorative tree cell participates in A* blocking"
		)
	assertions.truthy(decorative_tree_cells.size() >= 10, "main registers unchoppable decorative tree obstacles")
	var target: Node3D
	for resource in resources:
		if str(resource.get("resource_type")) == "stone":
			target = resource as Node3D
			break
	assertions.truthy(target != null, "main has a stone gathering target")
	if target != null:
		target.remaining_units = target.max_units
		target.call("_update_visual_stage")
		target.call("_set_gather_active", true)
		var hover_focus := Marker3D.new()
		main.add_child(hover_focus)
		hover_focus.global_position = target.global_position
		main.camera_rig.orthographic_size = 5.0
		main.camera_rig.set_target(hover_focus)
		main.camera_rig.call("_process", 0.0)
		main.action_controller.select_slot(3)
		await tree.physics_frame
		var hover_camera := main.get_viewport().get_camera_3d() as Camera3D
		main.action_controller._pointer_position = hover_camera.unproject_position(
			target.global_position + Vector3(0.0, 0.2, 0.0)
		)
		main.action_controller.call("_update_gather_hover_from_pointer")
		var hover_ring := main.gathering_feedback.get_node("TreeHoverRing") as Node3D
		var hover_material := (hover_ring.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
		assertions.truthy(hover_ring.visible, "mineable ore shows its hover ring")
		assertions.near(hover_material.albedo_color.g, 0.9, 0.01, "mineable ore hover ring is green")
		target.gathering_enabled = false
		target.call("_set_gather_active", false)
		await tree.physics_frame
		main.action_controller.call("_update_gather_hover_from_pointer")
		assertions.truthy(hover_ring.visible, "unavailable ore remains pointer-interactive for red hover")
		assertions.near(hover_material.albedo_color.r, 0.95, 0.01, "unavailable ore hover ring is red")
		target.gathering_enabled = true
		target.call("_set_gather_active", true)
		main.action_controller.call("_clear_gather_hover")
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
		var held_stone: int = main.inventory_system.get_item_count("stone")
		if held_stone > 0:
			main.inventory_system.remove_item("stone", held_stone)
		var stone_before: int = main.inventory_system.get_item_count("stone")
		var stone_units_before: int = int(target.remaining_units)
		var stamina_before: int = game_state.player_state.stamina
		var durability_before: int = int(main.tool_system.get_durability("pickaxe").current)
		var stone_missing_before := _missing_resource(
			main.building_system.diagnose_resources("workbench"), "stone"
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
		assertions.equal(
			main.action_controller.get_selected_slot(),
			3,
			"auto-equipped pickaxe is highlighted in the action palette"
		)
		assertions.truthy(
			not main.action_controller.should_show_cell_highlight(),
			"auto-equipped pickaxe keeps the farming cell shadow hidden"
		)
		assertions.truthy(main.player.has_auto_movement(), "main player begins automatic movement")
		var physical_path: Array[Vector3] = main.player._auto_path.duplicate()
		var physical_move_failures: Array[String] = []
		main.gathering_controller.gather_failed.connect(
			func(_failed_target: Node, reason: String) -> void: physical_move_failures.append(reason),
			CONNECT_ONE_SHOT
		)
		for point in main.player._auto_path:
			assertions.truthy(
				not decorative_tree_cells.has(main.grid_system.world_to_grid(point.x, point.z)),
				"automatic path does not cross a decorative tree cell"
			)
		var movement_frames := 0
		var physical_path_length := 0.0
		var previous_path_point: Vector3 = main.player.global_position
		for path_point in physical_path:
			physical_path_length += previous_path_point.distance_to(path_point)
			previous_path_point = path_point
		var minimum_auto_speed: float = (
			main.player.speed * main.player.LATERAL_MOVEMENT_SPEED_SCALE
		)
		var movement_frame_limit := ceili(
			(physical_path_length / minimum_auto_speed + 2.0) * 60.0
		)
		while (
			main.gathering_controller.get_state_name() == "MOVING"
			and movement_frames < movement_frame_limit
		):
			await tree.physics_frame
			movement_frames += 1
		assertions.truthy(movement_frames > 1, "integration exercises physical auto movement instead of teleporting")
		assertions.truthy(
			physical_move_failures.is_empty(),
			"physical auto movement reaches the target without failure: %s at %s waypoint %d/%d, end %s, target %s" % [
				str(physical_move_failures), str(main.player.global_position),
				main.player._auto_path_index, physical_path.size(), str(physical_path[-1]), str(target.global_position),
			]
		)
		assertions.equal(
			main.gathering_controller.get_state_name(),
			"ACTING",
			"arrival begins the timed gathering animation"
		)
		assertions.equal(target.get_mining_frame(), 0, "real ore begins on the intact mining frame")
		assertions.equal(main.tool_swing_visual.get_tool_id(), "pickaxe", "real ore action shows the pickaxe")
		var expected_pickaxe_anchor: Vector3 = main.gathering_feedback.ore_pickaxe_anchor(
			target.global_position, main.player.global_position
		)
		assertions.near(
			main.tool_swing_visual.global_position.x,
			expected_pickaxe_anchor.x,
			0.002,
			"real pickaxe is anchored to the ore shoulder horizontally"
		)
		assertions.near(
			main.tool_swing_visual.global_position.y,
			expected_pickaxe_anchor.y,
			0.002,
			"real pickaxe is anchored above the ore base"
		)
		main.tool_swing_visual.set_action_progress(0.14)
		var camera := main.get_viewport().get_camera_3d() as Camera3D
		var ore_visual := target.get_node("Visual") as Sprite3D
		var ore_atlas := load(ORE_MINING_ATLAS_PATH) as Texture2D
		var used_rect := ResourceNodeScript.mining_frame_used_rect(ore_atlas, 0)
		var visual_center := camera.unproject_position(ore_visual.global_position)
		var pixels_per_world := float(main.get_viewport().get_visible_rect().size.y) / camera.size
		var cell_width := float(ore_atlas.get_width()) / 4.0
		var painted_left := visual_center.x + (
			float(used_rect.position.x) - cell_width * 0.5
		) * ore_visual.pixel_size * ore_visual.scale.x * pixels_per_world
		var painted_right := visual_center.x + (
			float(used_rect.end.x) - cell_width * 0.5
		) * ore_visual.pixel_size * ore_visual.scale.x * pixels_per_world
		var pickaxe_contact_screen := camera.unproject_position(main.tool_swing_visual.global_position)
		assertions.truthy(
			pickaxe_contact_screen.x >= lerpf(painted_left, painted_right, 0.40)
			and pickaxe_contact_screen.x <= lerpf(painted_left, painted_right, 0.58),
			"projected pickaxe head lands inside the painted ore's left shoulder (%0.2f in %0.2f..%0.2f)" % [
				pickaxe_contact_screen.x,
				lerpf(painted_left, painted_right, 0.40),
				lerpf(painted_left, painted_right, 0.58),
			]
		)
		main.season_system.hour = 8
		main.season_system.minute = 0
		main.season_system._accumulator = 0.0
		main.gathering_controller._process(1.5)
		assertions.equal(target.get_mining_frame(), 1, "halfway mining progress shows the cracked frame")
		assertions.equal(
			main.inventory_system.get_item_count("stone"),
			stone_before,
			"half-finished mining commits no partial stone"
		)
		main.gathering_controller._process(1.4)
		assertions.equal(
			main.inventory_system.get_item_count("stone"),
			stone_before,
			"mining remains atomic at 2.9 seconds"
		)
		assertions.equal(main.gathering_controller.get_state_name(), "ACTING", "mining remains active before three seconds")
		main.gathering_controller._process(0.1)
		assertions.equal(
			main.inventory_system.get_item_count("stone"),
			stone_before + stone_units_before,
			"one completed action adds the whole stone node"
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
		assertions.equal(target.remaining_units, 0, "single mining action depletes the whole node")
		assertions.equal(
			_missing_resource(main.building_system.diagnose_resources("workbench"), "stone"),
			stone_missing_before - stone_units_before,
			"whole-node stone immediately reduces a building material shortage"
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
			"whole-node gathering stops after completion"
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
			var held_wood: int = main.inventory_system.get_item_count("wood")
			if held_wood > 0:
				main.inventory_system.remove_item("wood", held_wood)
			var wood_before: int = main.inventory_system.get_item_count("wood")
			var fiber_before: int = main.inventory_system.get_item_count("fiber")
			var tree_stamina_before: int = game_state.player_state.stamina
			var axe_durability_before: int = int(main.tool_system.get_durability("axe").current)
			var wood_missing_before := _missing_resource(
				main.building_system.diagnose_resources("workbench"), "wood"
			)
			var wood_market_before: int = main.market_system.get_stock("wood")
			var tree_cell: Vector2i = main.grid_system.world_to_grid(tree_target.global_position.x, tree_target.global_position.z)
			main.season_system.hour = 8
			main.season_system.minute = 0
			main.season_system._accumulator = 0.0
			assertions.truthy(main.gathering_controller.request_gather(tree_target), "real tree starts one action")
			assertions.truthy(_arrive_gather(main), "real tree reaches its root interaction point")
			main.gathering_controller._process(1.2)
			assertions.equal(main.gathering_controller.get_state_name(), "ACTING", "tree remains active at ore duration")
			assertions.equal(main.inventory_system.get_item_count("wood"), wood_before, "tree commits nothing at ore duration")
			main.gathering_controller._process(0.8)
			assertions.equal(main.gathering_controller.get_state_name(), "ACTING", "tree remains active at two seconds")
			assertions.equal(main.inventory_system.get_item_count("wood"), wood_before, "tree commits nothing before three seconds")
			main.gathering_controller._process(1.0)
			assertions.equal(main.gathering_controller.get_state_name(), "IDLE", "real tree completes at three seconds")
			assertions.equal(main.inventory_system.get_item_count("wood"), wood_before + 5, "tree adds five wood")
			assertions.equal(main.inventory_system.get_item_count("fiber"), fiber_before + 1, "tree adds one renewable fiber")
			assertions.equal(int(tree_target.get("remaining_units")), 0, "tree is fully depleted")
			assertions.equal(game_state.player_state.stamina, tree_stamina_before - 8, "tree spends eight stamina once")
			assertions.equal(int(main.tool_system.get_durability("axe").current), axe_durability_before - 1, "tree spends one axe durability")
			assertions.equal(main.season_system.minute, 10, "tree advances ten game minutes")
			assertions.equal(tree_target.get_felling_frame(), 3, "tree completion leaves painted stump art")
			assertions.truthy(main.grid_system.is_navigation_cell_walkable(tree_cell), "painted stump releases navigation")
			assertions.equal(
				_missing_resource(main.building_system.diagnose_resources("workbench"), "wood"),
				wood_missing_before - 5,
				"gathered wood immediately reduces the workbench shortage"
			)
			assertions.equal(main.market_system.get_stock("wood"), wood_market_before, "tree gathering leaves market stock unchanged")

		var copper_target := _first_resource_of_type(resources, "copper_ore", target)
		assertions.truthy(copper_target != null, "economy chain finds a visible copper vein")
		if copper_target != null:
			var copper_before: int = main.inventory_system.get_item_count("copper_ore")
			var copper_units_before: int = int(copper_target.get("remaining_units"))
			var copper_market_before: int = main.market_system.get_stock("copper_ore")
			assertions.truthy(_complete_gather(main, copper_target), "real copper vein completes one action")
			assertions.equal(main.inventory_system.get_item_count("copper_ore"), copper_before + copper_units_before, "ore vein adds all remaining copper ore")
			assertions.equal(int(copper_target.get("remaining_units")), 0, "ore vein is fully depleted")
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
	var duration := float(target.call("get_gather_duration")) if target.has_method("get_gather_duration") else 1.2
	main.gathering_controller._process(duration)
	return main.gathering_controller.get_state_name() == "IDLE"


func _arrive_gather(main: Node) -> bool:
	if main.player._auto_path.is_empty():
		return false
	var endpoint: Vector3 = main.player._auto_path[-1]
	main.player._auto_path_index = main.player._auto_path.size() - 1
	main.player.global_position = endpoint
	main.player._update_auto_movement(0.0)
	return main.gathering_controller.get_state_name() == "ACTING"


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
