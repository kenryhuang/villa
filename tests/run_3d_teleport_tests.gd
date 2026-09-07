extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Teleport tests timed out"); quit(1))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func click(control: Control, point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_transform_with_canvas() * point
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)

func _run() -> void:
	root.size = Vector2i(1440, 960)
	var farm = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	var interaction = farm.get_node("FarmInteraction")
	var player: Farm3DPlayer = farm.player
	player.set_physics_process(false)
	var hud = interaction.hud
	var panel = hud.debug_panel
	var map = panel.teleport_map
	panel.open()
	panel.tabs.current_tab = map.get_parent().get_parent().get_index()
	await process_frame
	await physics_frame
	await process_frame
	check(map.is_visible_in_tree(), "Teleport map is accessible in debug tab")
	check(not hud.minimap.teleport_enabled, "HUD minimap remains read-only")
	for point in [Vector3.ZERO, Vector3(-129, 0, 96), Vector3(60, 0, -50)]:
		check(map.map_to_world(map.world_to_map(point)).is_equal_approx(Vector2(point.x, point.z)), "Map coordinates round trip across world regions")
	player.velocity = Vector3(4, -6, 3)
	Input.action_press("move_right")
	player.fishing_locked = true
	player.golf_locked = true
	farm.set_overview(true)
	click(map, map.world_to_map(Vector3(-129, 0, 96)))
	check(Vector2(player.position.x, player.position.z).is_equal_approx(Vector2(-129, 96)), "Actual GUI click teleports to selected golf course location")
	check(player.velocity == Vector3.ZERO and not Input.is_action_pressed("move_right"), "Teleport clears velocity and held movement")
	check(not player.fishing_locked and not player.golf_locked, "Teleport releases fishing and golf locks")
	check(panel.visible and player.ui_blocked, "Panel stays open and movement stays blocked")
	check(not farm.overview_enabled and farm.camera_rig.global_position.is_equal_approx(player.position + Vector3.UP * 1.2), "Follow camera immediately tracks destination")
	var before := player.position
	click(map, Vector2(124, 21))
	click(map, map.world_to_map(Vector3.ZERO), MOUSE_BUTTON_RIGHT)
	check(player.position == before, "Map title and right-click never teleport")
	for point in [Vector2(-31, -57), Vector2(-6, 108), Vector2(45, 70)]:
		click(map, map.world_to_map(Vector3(point.x, 0, point.y)))
		check(Vector2(player.position.x, player.position.z).is_equal_approx(point), "Repeated map clicks reach mountain, lake and plain")
		check(player.position.y >= Farm3DTerrainProfile.surface_height(point.x, point.y), "Destination stays above actual terrain")
	# A raised collision surface must win over the mathematical terrain height.
	var platform := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 1, 6)
	shape.shape = box
	platform.add_child(shape)
	farm.add_child(platform)
	platform.position = Vector3(10, 5, 10)
	await physics_frame
	await process_frame
	interaction.debug_teleport(Vector2(10, 10))
	check(is_equal_approx(player.position.y, 5.65), "Raised collision surface prevents teleporting inside structures")
	interaction.debug_teleport(Vector2(-1000, 1000))
	check(player.position.x == -175 and player.position.z == 143, "World borders leave room for player capsule")
	before = player.position
	interaction.debug_teleport(Vector2(NAN, 0))
	check(player.position == before, "Invalid coordinates leave player unchanged")
	click(map, map.world_to_map(Vector3(0, 0, 8)))
	if "--capture-teleport-ui" in OS.get_cmdline_user_args():
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://tmp")
		root.get_texture().get_image().save_png("res://tmp/farm3d-teleport-debug.png")
	panel.close()
	check(not player.ui_blocked, "Closing panel restores player controls")
	before = player.position
	click(hud.minimap, hud.minimap.world_to_map(Vector3(-129, 0, 96)))
	check(player.position == before, "Regular minimap clicks do not move the player")
	farm.queue_free()
	await process_frame
	print("3D TELEPORT: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
