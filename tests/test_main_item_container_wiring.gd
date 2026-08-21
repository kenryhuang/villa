extends RefCounted

const ItemContainerRouter = preload("res://scripts/systems/item_container_router.gd")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	assertions.truthy(packed != null, "Main Router contract loads main scene")
	if packed == null:
		return
	var main = packed.instantiate()
	main.load_save_on_start = false
	tree.root.add_child(main)
	for _frame in 4:
		await tree.process_frame
		await tree.physics_frame
	assertions.equal(
		main.action_controller.get_action_mode(),
		PlayerActionController.ActionMode.NONE,
		"real Main starts without an action mode"
	)
	assertions.truthy(
		not main.seed_selector_panel.visible,
		"real Main does not open the seed selector at startup"
	)
	assertions.equal(
		main.hud.get_palette_button_count(),
		0,
		"real Main hides shortcuts until P or B"
	)
	assertions.truthy(
		main.action_controller.switch_mode(PlayerActionController.ActionMode.FARMING),
		"real Main enters farming mode"
	)
	assertions.truthy(
		main.action_controller.select_mode_slot(0),
		"real Main selects the hoe"
	)
	var camera: Camera3D = tree.root.get_camera_3d()
	var target_cell := _visible_reachable_farm_cell(main, camera)
	assertions.truthy(target_cell != null, "real Main has a visible reachable farm cell")
	if target_cell != null:
		var motion := InputEventMouseMotion.new()
		motion.position = camera.unproject_position(target_cell.world_position_3d())
		motion.global_position = motion.position
		main.action_controller._input(motion)
		main.action_controller._process(0.0)
		var highlight := main.grid_system.get_node_or_null(
			"GridCells/CellHighlight"
		) as MeshInstance3D
		assertions.truthy(
			highlight != null and highlight.visible,
			"hoe shows a cell shadow"
		)
		assertions.equal(
			int(highlight.get_meta("gx", -1)),
			target_cell.gx,
			"hoe shadow aligns on x"
		)
		assertions.equal(
			int(highlight.get_meta("gz", -1)),
			target_cell.gz,
			"hoe shadow aligns on z"
		)

	var routers: Array[Node] = []
	_collect_routers(main, routers)
	assertions.equal(routers.size(), 1, "Main owns exactly one ItemContainerRouter")
	if routers.size() == 1:
		var router := routers[0]
		assertions.truthy(router == main.item_container_router, "Main exposes its unique Router")
		assertions.truthy(
			router.has_method("is_configured_with")
			and router.call("is_configured_with", main.inventory_system, main.farm_storage_system),
			"Main Router manages the authoritative inventory and storage"
		)
		assertions.truthy(
			main.economy_system.has_method("uses_item_container_router")
			and main.economy_system.call("uses_item_container_router", router),
			"Main Economy uses the same Router instance"
		)
	assertions.truthy(
		main.inventory_ui.inventory_ref == main.inventory_system,
		"Main InventoryUI receives the authoritative InventorySystem"
	)
	assertions.truthy(
		main.inventory_ui.farm_storage_ref == main.farm_storage_system,
		"Main InventoryUI receives the authoritative FarmStorageSystem"
	)
	assertions.truthy(
		main.seed_selector_panel.inventory_ref == main.inventory_system
		and main.seed_selector_panel.farming_ref == main.farming_system
		and main.seed_selector_panel.action_controller_ref == main.action_controller,
		"Main SeedSelectorPanel receives authoritative planting dependencies"
	)
	assertions.truthy(
		main.action_controller.seed_selection_requested.is_connected(
			Callable(main, "_on_seed_selection_requested")
		),
		"Main connects the planting command to the seed selector"
	)
	var nested_parent := Node.new()
	var nested_router := ItemContainerRouter.new()
	main.add_child(nested_parent)
	nested_parent.add_child(nested_router)
	var nested_routers: Array[Node] = []
	_collect_routers(main, nested_routers)
	assertions.equal(nested_routers.size(), 2, "nested ordinary Node Router is counted")
	nested_parent.free()
	main.free()


func _visible_reachable_farm_cell(main: Node, camera: Camera3D) -> GridCell:
	if camera == null:
		return null
	for cell_value in main.grid_system._cells.values():
		var cell := cell_value as GridCell
		if not main.grid_system.can_farm_at(cell.gx, cell.gz):
			continue
		var point := cell.world_position_3d()
		if camera.is_position_behind(point):
			continue
		var distance := Vector2(
			main.player.global_position.x - point.x,
			main.player.global_position.z - point.z
		).length()
		if distance <= main.player.interaction_range:
			return cell
	return null


func _collect_routers(node: Node, routers: Array[Node]) -> void:
	for child in node.get_children():
		if child.get_script() == ItemContainerRouter:
			routers.append(child)
		_collect_routers(child, routers)
