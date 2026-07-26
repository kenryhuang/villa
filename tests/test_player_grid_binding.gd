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

	player.call("_raycast_to_grid_cell")
	player.call("_use_current_tool")
	print("PASS: player grid binding")
	quit(0)
