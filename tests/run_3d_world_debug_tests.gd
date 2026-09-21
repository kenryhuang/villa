extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("World debug timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	if "--living-world-scenario=P12" not in OS.get_cmdline_user_args(): quit(1); return
	var farm: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var session: Node = farm.farm_session
	session.season.set_process(false)
	session.save_path = "res://tmp/living-world/world-debug-test.json"
	var hub: RuntimeDebugPanel = farm.get_node("FarmInteraction").hud.debug_panel
	var page: VBoxContainer = hub.world_state_panel
	hub.open()
	check(not paused, "NPC overview continues to run normally")
	check(not hub.tabs.is_tab_hidden(0), "World settings tab is visible in the real 3D debug hub")
	hub.tabs.current_tab = 0
	check(paused, "Editing time and level pauses the simulation")
	var state: Node = root.get_node("GameState")
	page.level_input.value = 6
	page.apply_level_button.pressed.emit()
	check(state.player_state.level == 6 and state.player_state.exp == 1300, "Level button synchronizes the actual player level and experience")
	page.hour_input.value = 8
	page.minute_input.value = 25
	await page.apply_time()
	check(session.season.hour == 8 and session.season.minute == 25, "Time selection reaches the exact hour and minute")
	check(paused and not page.busy, "Time editing preserves pause and releases controls")
	page.hour_input.value = 7
	check(page.target_minute() == 1080 + 85, "An earlier clock time on the same date advances to tomorrow")
	session.agent_runtime.scheduler.restore_budget({"day": 0, "calls": 16, "dialogue_calls": 3})
	await page.next_day()
	check(session.season.total_days == 2 and session.season.hour == 6, "Next day button crosses the real day boundary")
	check(session.agent_runtime.scheduler.budget_calls == 0 and session.agent_runtime.scheduler.budget_day == 1, "Crossing a day resets the exhausted NPC planning budget")
	check(session.market.last_settled_day == 2 and session.living_world.society.caught_up(1080), "Market and resident daily settlement complete before returning")
	page.season_input.select(1)
	page.day_input.value = 1
	page.hour_input.value = 6
	page.minute_input.value = 0
	await page.apply_time()
	check(session.season.current_season == 1 and session.season.total_days == 8 and session.season.current_day == 1, "Season selection advances into summer with consistent date fields")
	check(session._valid_save(session.snapshot_save_data()), "Advanced world remains valid under the real save validators")
	var saved_level: int = state.player_state.level
	var saved_exp: int = state.player_state.exp
	check(session.save_game() and session.load_game(), "Time and level persist through an isolated save and reload")
	check(state.player_state.level == saved_level and state.player_state.exp == saved_exp and session.season.current_season == 1, "Reload preserves level, earned simulation experience, and season")
	page.refresh()
	page.season_input.select(0)
	check(page.target_minute() == 28 * 1080, "An earlier season targets next year instead of rewinding economic state")
	page.season_input.select(2)
	page.apply_time_button.pressed.emit()
	check(page.busy and hub.close_button.disabled and hub.tabs.is_tab_disabled(3), "Fast-forward locks competing tabs and close actions")
	page.stop_button.pressed.emit()
	while page.busy: await process_frame
	check(paused and session._valid_save(session.snapshot_save_data()), "Stop completes the current settlement and leaves a valid paused world")
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		for frame in 6: await process_frame
		var bounds := root.get_visible_rect()
		check(bounds.encloses(page.next_day_button.get_global_rect()) and bounds.encloses(hub.close_button.get_global_rect()), "Time controls fit viewport " + str(resolution))
	hub.tabs.current_tab = 3
	check(not paused, "Switching back to NPC overview resumes simulation")
	hub.tabs.current_tab = 0
	hub.close()
	check(not paused, "Closing settings restores previous pause state")
	if "--capture-world-debug" in OS.get_cmdline_user_args():
		hub.open()
		for frame in 6: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/world-debug-panel.png")
		hub.close()
	farm.queue_free()
	await process_frame
	print("3D WORLD DEBUG: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
