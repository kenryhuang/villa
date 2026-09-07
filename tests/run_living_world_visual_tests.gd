extends SceneTree

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): quit(1))
	run.call_deferred()

func capture(name: String) -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/living-world/" + name + ".png")

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	root.size = Vector2i(1440, 960)
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var s: Farm3DSession = scene.farm_session
	s.season.set_process(false)
	s.player.set_physics_process(false)
	if not preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P5"): quit(1); return
	var interaction: Node = scene.get_node("FarmInteraction")
	var point: Vector3 = interaction.commission_board.global_position
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = point + Vector3(6, 5, 9)
	camera.look_at(point + Vector3.UP)
	camera.current = true
	await capture("P5-world-board")
	var ui: Node = interaction.hud.commission_view
	ui.open_panel()
	await capture("P5-commissions")
	ui.tabs.current_tab = 3
	ui._publish()
	await capture("P5-publish-confirm")
	ui.close_panel()
	s.season.advance_game_minutes(120)
	interaction.hud.debug_panel.open()
	var debug: Node = interaction.hud.debug_panel
	debug._refresh_farm3d()
	for i in debug.tabs.get_tab_count():
		if debug.tabs.get_tab_title(i) == "居民社会": debug.tabs.current_tab = i
	await capture("P2-society-ledger")
	print("PASS: Four formal-scene UI captures")
	scene.free()
	quit()
