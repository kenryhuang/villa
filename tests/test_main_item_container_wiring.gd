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
	main.free()


func _collect_routers(node: Node, routers: Array[Node]) -> void:
	for child in node.get_children():
		if child.get_script() == ItemContainerRouter:
			routers.append(child)
		_collect_routers(child, routers)
