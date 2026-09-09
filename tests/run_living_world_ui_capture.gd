extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--farm-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": quit(1); return
	var stage := "P12"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--living-world-scenario="): stage = arg.trim_prefix("--living-world-scenario=")
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate(); root.add_child(scene)
	var s: Farm3DSession = scene.farm_session
	if s.auto_save or s.auto_restore or s.agent_runtime.service_enabled: quit(1); return
	s.season.set_process(false)
	if stage in ["P9", "P11"]:
		s.save_path = "res://tmp/living-world/%s.json" % stage
		if not s.load_game(): quit(1); return
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1440, 960)
	var hud: CanvasLayer = scene.get_node("FarmInteraction/FarmHUD")
	var view: Control = hud.commission_view
	view.open_panel(); view.tabs.current_tab = 3
	for page in ["top", "bottom"]:
		if page == "bottom": view.tabs.get_child(3).scroll_vertical = 100000
		await create_timer(.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/living-world/%s-ui-%s.png" % [stage, page])
	view.close_panel()
	if paused or s.player.ui_blocked: push_error("Panel did not restore play controls"); quit(1); return
	if stage == "P12":
		hud.debug_panel.open()
		await create_timer(.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/living-world/P12-ui-debug.png")
	print(stage, " UI captures complete; modal open/close restored controls")
	quit(0)
