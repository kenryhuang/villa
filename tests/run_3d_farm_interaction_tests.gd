extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Menu test timed out"); quit(1))
	_run.call_deferred()

func _check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		push_error(text)

func _run() -> void:
	root.size = Vector2i(1440, 960)
	var preview := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	await process_frame
	var session = preview.get_node("FarmSession")
	var interaction = preview.get_node("FarmInteraction")
	var hud = interaction.hud
	var player = preview.get_node("Player")
	session.season.set_process(false)
	_check(interaction.target_id.is_empty() and not interaction._marker.visible, "Start in walking state without a target or tool")
	_check(player.get_node_or_null("FarmTool") == null, "No held tool is shown")
	_check(hud.category_buttons.size() == 3, "Three target categories replace all tool buttons")
	hud.category_buttons.farmland.pressed.emit()
	_check(hud.buttons.size() == 2 and hud.secondary.visible, "Farmland opens dry and paddy choices")
	_check(interaction.target_id.is_empty(), "Choosing a category does not select a leaf")
	var cell: GridCell = session.grid.get_cell(19, 16)
	player.global_position = Vector3(0.2, 0, 3.3)
	_check(not interaction.perform(cell).ok and cell.state == GridCell.State.WASTELAND, "A category alone cannot change the ground")
	hud.buttons[0].pressed.emit()
	_check(interaction.target_id == "dry", "Leaf button selects dry farmland")
	_check(not hud.secondary.visible, "Leaf selection folds the secondary menu to expose the ground")
	await _frames(12)
	var camera: Camera3D = preview.get_viewport().get_camera_3d()
	var pointer := camera.unproject_position(cell.world_position_3d())
	_check(interaction.cell_at_pointer(pointer) == cell, "Mouse ray targets the actual one-meter ground cell")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = pointer
	root.push_input(click, true)
	await _frames(24)
	_check(cell.state == GridCell.State.FARMLAND, "Real mouse click creates selected farmland")
	hud.category_buttons.seed.pressed.emit()
	_check(hud.buttons.size() == 15, "All original seeds and saplings appear in the second level")
	var carrot_button: Button
	for button in hud.buttons:
		if button.get_meta("target_id") == "carrot_seed":
			carrot_button = button
	carrot_button.pressed.emit()
	var seeds: int = session.inventory.get_item_count("carrot_seed")
	_check(interaction.perform(cell).ok, "Selected carrot plants without a seed tool")
	_check(cell.crop_instance.crop_data.crop_id == "carrot", "Selection plants carrot, not hardcoded grain")
	_check(session.inventory.get_item_count("carrot_seed") == seeds - 1, "Planting deducts the correct seed")
	await _frames(2)
	var key := GridSystem.cell_key(cell.gx, cell.gz)
	_check(session.visuals._visuals[key].has_node("Crop_carrot"), "Carrot uses its original crop visual")
	_press(KEY_ESCAPE)
	_check(interaction.target_id.is_empty() and not hud.secondary.visible, "Esc clears all selection levels")
	_check(not interaction._marker.visible and player._farm_action_seconds == 0, "Esc removes grid and releases the action lock")
	_check(interaction.perform(cell).ok and cell.watered, "Empty-hand click waters growing crops")
	interaction._cooldown = 0
	var before: int = session.inventory.get_item_count("carrot")
	session.season.advance_game_minutes(108)
	_check(cell.crop_instance.is_mature(), "Original clock ripens the selected non-grain crop")
	_check(interaction.perform(cell).ok, "Empty-hand click harvests mature crop")
	_check(session.inventory.get_item_count("carrot") > before, "Harvested carrots are visible inventory items")
	_press(KEY_I)
	_check(hud.inventory_ui.visible and player.ui_blocked, "I opens the original inventory and blocks movement")
	_check(hud.inventory_ui.grid_container.get_child_count() == 60, "Scrollable backpack covers the enlarged inventory")
	_check(not hud.inventory_ui.quick_bar.visible, "Inventory does not expose obsolete tool quick slots")
	_check(not interaction.perform(cell).ok, "Inventory blocks world operations")
	var first_slot: PanelContainer = hud.inventory_ui.grid_container.get_child(0)
	var texts: Array[String] = []
	for label in first_slot.find_children("*", "Label", true, false):
		texts.append(label.text)
	_check("胡萝卜" in texts, "Backpack places harvested items before planting supplies")
	await _frames(3)
	var item_scroll: ScrollContainer = hud.inventory_ui.grid_container.get_parent()
	item_scroll.scroll_vertical = 450
	_check(item_scroll.scroll_vertical > 0, "Backpack can scroll down to building materials")
	_press(KEY_ESCAPE)
	_check(not hud.inventory_ui.visible and not player.ui_blocked, "Esc closes inventory and restores movement")
	# Harvest after browsing materials: reopening must reveal crops rather than
	# preserving a scroll offset that clips every harvested item above the panel.
	_check(session.apply_target(cell, "seed", "carrot_seed").ok, "Plant another crop after browsing the backpack")
	cell.crop_instance.set_growth_state(cell.crop_instance.crop_data.growth_days, CropInstance.LifecycleState.MATURE)
	interaction._cooldown = 0
	var previous_carrots: int = session.inventory.get_item_count("carrot")
	_check(interaction.perform(cell).ok, "Harvest after closing a scrolled backpack succeeds")
	var carrot_total: int = session.inventory.get_item_count("carrot")
	_check(carrot_total > previous_carrots, "Second harvest adds to the existing inventory stack")
	_press(KEY_I)
	await _frames(3)
	_check(item_scroll.scroll_vertical == 0, "Reopened backpack starts with harvested items in view")
	first_slot = hud.inventory_ui.grid_container.get_child(0)
	_check(item_scroll.get_global_rect().encloses(first_slot.get_global_rect()), "Harvested slot is actually inside the visible scroll area")
	texts.clear()
	for label in first_slot.find_children("*", "Label", true, false):
		texts.append(label.text)
	_check("胡萝卜" in texts and "x%d" % carrot_total in texts, "Visible crop slot shows the updated harvest total")
	_press(KEY_ESCAPE)
	# Reproduce ripe strawberries saved after an out-of-season transition.
	session.season.current_season = SeasonSystem.Season.SPRING
	_check(session.apply_target(cell, "seed", "strawberry_seed").ok, "Plant strawberry regression fixture")
	cell.crop_instance.set_growth_state(4.0, CropInstance.LifecycleState.DORMANT)
	session.season.current_season = SeasonSystem.Season.AUTUMN
	var strawberry_before: int = session.inventory.get_item_count("strawberry")
	interaction.select_target("seed", "carrot_seed")
	interaction._cooldown = 0
	_check(interaction.perform(cell).ok, "Ripe dormant strawberry harvest overrides seed selection")
	_check(session.inventory.get_item_count("strawberry") > strawberry_before, "Ripe dormant fruit enters inventory instead of watering")
	interaction.cancel_selection()
	# Incomplete dormant growth must not be promoted into a harvest.
	session.season.current_season = SeasonSystem.Season.SPRING
	session.apply_target(cell, "seed", "strawberry_seed")
	cell.crop_instance.set_growth_state(2.0, CropInstance.LifecycleState.DORMANT)
	strawberry_before = session.inventory.get_item_count("strawberry")
	_check(session.farming.preview_harvest(cell).is_empty(), "Immature dormant fruit remains unharvestable")
	interaction._cooldown = 0
	_check(interaction.perform(cell).reason == "crop_dormant", "Immature dormant plants are not watered")
	_check(session.inventory.get_item_count("strawberry") == strawberry_before, "Dormant unripe plant creates no fruit")
	interaction.cancel_selection()
	cell.crop_instance.set_growth_state(4.0, CropInstance.LifecycleState.DORMANT)
	session.visuals.sync_cell(cell)
	await _frames(3)
	click.position = camera.unproject_position(cell.world_position_3d())
	_check(interaction.cell_at_pointer(click.position) == cell, "Mouse ray picks the ripe strawberry plot")
	root.push_input(click, true)
	await _frames(24)
	_check(session.inventory.get_item_count("strawberry") > strawberry_before and cell.crop_instance == null, "Real mouse click harvests dormant ripe strawberries")
	interaction.cancel_selection()
	var notices: int = hud.bus.get_recent().size()
	var stamina: int = root.get_node("GameState").player_state.stamina
	_check(interaction.perform(null).reason == "no_target", "Click outside grid is ignored")
	var distant_ground: GridCell
	for candidate in session.grid._cells.values():
		if candidate.state == GridCell.State.WASTELAND and not session._in_range(candidate):
			distant_ground = candidate
			break
	_check(distant_ground != null and interaction.perform(distant_ground).reason == "no_target", "Distant ordinary ground is ignored before range validation")
	_check(hud.bus.get_recent().size() == notices, "Non-plot clicks publish no notifications")
	_check(player._farm_action_seconds == 0 and root.get_node("GameState").player_state.stamina == stamina, "Non-plot clicks trigger no animation or stamina cost")
	var bare_ground: GridCell = session.grid.get_cell(20, 16)
	_check(bare_ground.state == GridCell.State.WASTELAND, "Bare-ground mouse fixture has no plot")
	click.position = camera.unproject_position(bare_ground.world_position_3d())
	_check(interaction.cell_at_pointer(click.position) == bare_ground, "Mouse ray picks ordinary ground")
	root.push_input(click, true)
	await _frames(3)
	_check(hud.bus.get_recent().size() == notices and player._farm_action_seconds == 0, "Real bare-ground click stays silent and idle")
	player.global_position += Vector3(10, 0, 0)
	_check(interaction.perform(cell).reason == "out_of_range", "Actual distant crop still requires walking closer")
	player.global_position -= Vector3(10, 0, 0)
	hud.category_buttons.building.pressed.emit()
	_check(hud.buttons.size() == 17, "All original buildings are listed")
	var fence_button: Button
	for button in hud.buttons:
		if button.get_meta("target_id") == "fence":
			fence_button = button
	await _frames(3)
	hud.secondary_grid.get_parent().ensure_control_visible(fence_button)
	await _frames(3)
	var menu_click := InputEventMouseButton.new()
	menu_click.button_index = MOUSE_BUTTON_LEFT
	menu_click.pressed = true
	menu_click.position = fence_button.get_global_rect().get_center()
	root.push_input(menu_click, true)
	menu_click = menu_click.duplicate()
	menu_click.pressed = false
	root.push_input(menu_click, true)
	_check(interaction.target_id == "fence", "Scrolled building leaf receives real GUI clicks")
	_check(session.buildings.get_building_count() == 0, "Menu clicks never leak through to place a building")
	_check(session.buildings.is_in_build_mode(), "Building choice activates the original footprint preview")
	interaction.cancel_selection()
	_check(not session.buildings.is_in_build_mode(), "Esc clears building preview")
	_check(hud.bus.get_recent().size() > 5 and hud.message_stream.get_message_card_count() > 5, "All operation feedback enters the original message stream")
	hud.message_stream.return_to_latest()
	for index in 5:
		hud.notify_message("滚动验证：带换行的较长提示消息，应在布局完成后自动显示最新记录 %d" % index)
	await _frames(6)
	var scroll_bar: VScrollBar = hud.message_stream.message_scroll.get_v_scroll_bar()
	_check(scroll_bar.value >= scroll_bar.max_value - scroll_bar.page - 2, "New wrapped messages remain visible at the end of the message panel")
	hud.message_stream.history_requested.emit()
	_check(hud.history_panel.visible and not hud.history_text.get_parsed_text().is_empty(), "History opens real message records")
	_press(KEY_ESCAPE)
	_check(not hud.history_panel.visible, "Esc closes history")
	var position: Vector3 = player.global_position
	Input.action_press("move_forward")
	await _frames(12)
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(position) > 0.2, "Walking remains available after cancelling targets")
	preview.queue_free()
	await process_frame
	print("3D TARGET INTERACTION: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func _press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame
