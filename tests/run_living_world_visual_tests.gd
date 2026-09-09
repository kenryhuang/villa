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
	var stage := "P5"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--living-world-visual-stage="): stage = arg.trim_prefix("--living-world-visual-stage=")
	if not preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, stage, true): quit(1); return
	var interaction: Node = scene.get_node("FarmInteraction")
	var point: Vector3 = interaction.commission_board.global_position
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = point + Vector3(6, 5, 9)
	camera.look_at(point + Vector3.UP)
	camera.current = true
	if stage in ["P6", "P7"]:
		await capture_new_stage(scene, stage)
		scene.free()
		quit()
		return
	await capture("P5-world-board")
	var ui: Node = interaction.hud.commission_view
	ui.open_panel()
	await capture("P5-commissions")
	ui.tabs.current_tab = ui.tabs.get_tab_count() - 1
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


func capture_new_stage(scene: Node, stage: String) -> void:
	var s: Node = scene.farm_session
	var w: Node = s.living_world
	var ui: Node = scene.get_node("FarmInteraction").hud.commission_view
	if stage == "P6":
		var a := {"task_id": "", "version": 0, "recipient_id": "village_inn", "item_id": "grain", "quantity": 2, "reward": 5, "deadline_minutes": 180, "schedule": "now", "note": "送完后继续原计划"}
		if not w.command("lao_li", "propose_delivery", a, "visual-delivery").ok: quit(1); return
		ui.offer_delivery_draft("lao_li")
		await capture("P6-delivery-confirm")
		ui.confirm.confirmed.emit()
		await capture("P6-task-progress")
		ui.close_panel()
	else:
		for resident in w.society.residents.values():
			var npc: NpcEconomyState = s.npc_economy.get_npc_state(resident.id)
			npc.inventory = {}
			npc.gold = 0
		var result: Dictionary = w.public_plans.command("village_public", "public_food_plan", {"expected_version": w.public_plans.revision, "quantity": 2, "unit_reward": 150, "deadline_minutes": 600, "reason": "基础食品购买力不足，先采购两份面包帮助急需居民。"}, "visual-public")
		if not result.ok: quit(1); return
		ui.open_panel()
		ui.tabs.current_tab = 4
		await capture("P7-public-affairs")
		ui.tabs.current_tab = 0
		await capture("P7-public-order")
		ui.close_panel()
	print("PASS: %s two formal UI captures" % stage)
