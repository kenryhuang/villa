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


func _collect_routers(node: Node, routers: Array[Node]) -> void:
	for child in node.get_children():
		if child.get_script() == ItemContainerRouter:
			routers.append(child)
		_collect_routers(child, routers)
