extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(45).timeout.connect(func(): push_error("Debug layout test timed out"); quit(1))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for frame in 8: await process_frame

func click_at(point: Vector2) -> void:
	if not root.get_visible_rect().has_point(point): return
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var farm: Node3D = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	var panel: RuntimeDebugPanel = farm.get_node("FarmInteraction").hud.debug_panel
	var settings: Array = []
	for i in 80:
		settings.append({"agent_id": "layout_npc_%d" % i, "display_name": "测试居民 %d" % i, "decision_interval_hours": 2})
	check(panel.configure_agent_settings(settings), "Accept a large resident list")
	panel.open()
	var outer: Control = panel.get_node("Overlay/Center/Panel")
	var bar := panel.tabs.get_tab_bar()
	for viewport_size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport_size
		panel.tabs.current_tab = 3
		await settle()
		var before := outer.size.y
		click_at(bar.global_position + bar.get_tab_rect(2).get_center())
		await settle()
		check(panel.tabs.current_tab == 2, "Mouse opens intervals at %s" % viewport_size)
		check(outer.size.y <= before + 1, "Resident list does not grow the panel at %s" % viewport_size)
		var viewport := Rect2(Vector2.ZERO, Vector2(viewport_size))
		check(viewport.encloses(bar.get_global_rect()), "Tab bar remains on screen at %s" % viewport_size)
		check(viewport.encloses(panel.close_button.get_global_rect()), "Close button remains on screen")
		check(viewport.encloses(panel.apply_agent_settings_button.get_global_rect()), "Apply intervals remains on screen")
		click_at(bar.global_position + bar.get_tab_rect(3).get_center())
		await settle()
		check(panel.tabs.current_tab == 3, "Mouse can switch back to NPC overview")
	panel.tabs.current_tab = 2
	await settle()
	var scroll := panel.agent_interval_rows.get_parent() as ScrollContainer
	check(scroll != null, "Long list provides scrolling")
	if scroll != null:
		var last: Control = panel.agent_interval_rows.get_child(79)
		scroll.ensure_control_visible(last)
		await settle()
		check(scroll.scroll_vertical > 0 and scroll.get_global_rect().intersects(last.get_global_rect()), "Last resident is reachable by scrolling")
		(last.get_node("Interval") as SpinBox).value = 5
		var applied: Array = []
		panel.agent_settings_apply_requested.connect(func(values: Dictionary): applied.append(values))
		click_at(panel.apply_agent_settings_button.get_global_rect().get_center())
		check(applied.size() == 1 and applied[0].get("layout_npc_79") == 5, "Bottom row edit is included when applying")
	if "--capture-debug-layout" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/debug-interval-layout.png")
	panel.close()
	farm.queue_free()
	await process_frame
	print("3D DEBUG LAYOUT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
