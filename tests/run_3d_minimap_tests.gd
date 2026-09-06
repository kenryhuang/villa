extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Minimap test timed out"); quit(1))
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	root.size = Vector2i(1440, 960)
	var farm := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	await process_frame
	await process_frame
	var hud = farm.get_node("FarmInteraction").hud
	var map = hud.minimap
	var player: Node3D = farm.player
	player.set_physics_process(false)
	_check(map.is_visible_in_tree() and map.player == player, "Formal 3D HUD has a visible map bound to the actual player")
	_check(map.world_to_map(Vector3.ZERO).is_equal_approx(Vector2(160.75, 121.5)), "Farm origin retains its world position after westward extension")
	_check(map.world_to_map(Vector3(-176, 0, -80)).is_equal_approx(Vector2(26, 60.25)), "Northwest world corner maps to top left")
	_check(map.world_to_map(Vector3(80, 0, 144)).is_equal_approx(Vector2(222, 231.75)), "Expanded southeast world corner maps to bottom right")
	_check(map.world_to_map(Vector3(-6, 0, 108)).is_equal_approx(Vector2(156.15625, 204.1875)), "Southern lake is visible within the map")
	var east_step: Vector2 = map.world_to_map(Vector3(10,0,0)) - map.world_to_map(Vector3.ZERO)
	var south_step: Vector2 = map.world_to_map(Vector3(0,0,10)) - map.world_to_map(Vector3.ZERO)
	_check(is_equal_approx(east_step.length(), south_step.length()), "Rectangular map preserves equal distance scale on both axes")
	_check(map.world_to_map(Vector3(0, 99, 0)) == map.world_to_map(Vector3.ZERO), "Mountain height and jumps do not shift horizontal location")
	for entry in [[Vector3.FORWARD, Vector2.UP], [Vector3.RIGHT, Vector2.RIGHT], [Vector3.BACK, Vector2.DOWN], [Vector3.LEFT, Vector2.LEFT]]:
		player.look_at(player.position + entry[0], Vector3.UP, true)
		_check(map.player_heading().is_equal_approx(entry[1]), "Arrow follows actual farmer facing %s" % entry[0])
	player.position = Vector3(40, 0, -40)
	_check(map.world_to_map(player.position).is_equal_approx(Vector2(191.375, 90.875)), "Player movement updates map coordinates")
	var before: Vector2 = map.world_to_map(player.position)
	farm.yaw += PI
	farm._apply_camera_rotation()
	farm.set_overview(true)
	_check(map.world_to_map(player.position) == before, "Camera orbit and overview preserve north-up coordinates")
	_check(map.mouse_filter == Control.MOUSE_FILTER_STOP, "Map captures pointer input instead of placing crops through UI")
	_check(map.position.is_equal_approx(hud._ui.size - map.size - Vector2(18, 18)), "Map sits at the bottom right in the standard window")
	_check(not map.get_rect().intersects(hud._menu.get_rect()), "Map leaves the bottom action bar clear")
	_key(true)
	_check(not map.visible, "G closes the map")
	_key(true, true)
	_check(not map.visible, "Holding G does not repeatedly toggle the map")
	_key(false)
	_check(not map.visible, "Releasing G does not toggle the map")
	hud.toggle_inventory()
	_key(true)
	_check(map.visible and hud.inventory_ui.visible, "G reopens the map without closing the inventory")
	_key(false)
	hud.close_panels()
	# Change the logical canvas to exercise the narrow-layout fallback even headless.
	hud._ui.size = Vector2(1000, 960)
	hud.show_category("seed")
	await process_frame
	await process_frame
	_check(not map.get_rect().intersects(hud._menu.get_rect()), "Narrow layout keeps the expanded seed menu clear")
	_check(Rect2(Vector2.ZERO, hud._ui.size).encloses(map.get_rect()), "Narrow layout keeps the map on screen")
	farm.queue_free()
	await process_frame
	print("3D MINIMAP: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func _key(pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_G
	event.pressed = pressed
	event.echo = echo
	root.push_input(event, true)
