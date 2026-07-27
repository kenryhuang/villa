extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for _frame in 3:
		await process_frame

	var player: Node = main.get_node("Actors/Player")
	if not _has_property(player, "grid_system"):
		push_error("PlayerController must expose an injected grid_system")
		quit(1)
		return
	if player.grid_system != main.grid_system:
		push_error("PlayerController must use Main's GridSystem instance")
		quit(1)
		return
	if not main.grid_system.has_node("GridOverlay") or not main.grid_system.has_node("GridCells/CellHighlight"):
		push_error("Main must use the reusable GridSystem scene with visual nodes")
		quit(1)
		return
	if main.grid_system._cells.size() != 1008:
		push_error("Main GridSystem must initialize all 1008 cells")
		quit(1)
		return
	if get_first_node_in_group("grid_system") != main.grid_system:
		push_error("runtime GridSystem must be discoverable through the grid_system group")
		quit(1)
		return
	var save_data: Dictionary = main.save_manager.call("_gather_save_data")
	if not save_data.has("grid") or not save_data.grid.has("cells"):
		push_error("SaveManager must serialize GridSystem through its public contract")
		quit(1)
		return
	if not main.farming_system.has_node("CropVisuals"):
		push_error("Main must use the reusable FarmingSystem scene")
		quit(1)
		return
	if main.farming_system.grid_system != main.grid_system:
		push_error("FarmingSystem must use Main's GridSystem instance")
		quit(1)
		return
	if get_first_node_in_group("farming_system") != main.farming_system:
		push_error("runtime FarmingSystem must be discoverable through the farming_system group")
		quit(1)
		return

	player.call("_raycast_to_grid_cell")
	player.call("_use_current_tool")
	print("PASS: player grid binding")
	quit(0)
