extends SceneTree
const Data = preload("res://scripts/core/game_data.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(55).timeout.connect(func(): push_error("Windmill tests timed out"); quit(1))
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _frames(count := 3) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)

func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		root.push_input(event, true)

func _run() -> void:
	root.size = Vector2i(1440, 960)
	var farm := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var session: Farm3DSession = farm.get_node("FarmSession")
	var interaction = farm.get_node("FarmInteraction")
	var hud = interaction.hud
	var view = hud.windmill_view
	var player = session.player
	var wallet = root.get_node("GameState")
	player.set_physics_process(false)
	session.season.set_process(false)
	session.save_path = "user://windmill_3d_integration_test.json"
	player.position = session.grid.get_cell(32, 31).world_position_3d() + Vector3.LEFT * 1.2
	_check(not view.visible and not paused, "Windmill UI starts closed without pausing")
	var original := BuildingData.from_dictionary(Data.get_building("windmill"))
	var resolved := session.buildings._resolve_data(original)
	_check(original.scene_path == "res://scenes/buildings/windmill.tscn", "Original game's windmill scene is preserved")
	_check(resolved.scene_path == "res://scenes/farm3d/buildings/windmill.tscn", "3D resolver selects modeled windmill")
	_check(resolved.footprint == Vector2i(3, 3) and resolved.cost == original.cost, "Windmill preserves its yard footprint and construction economy")
	_check(session.buildings.enter_preview_mode("windmill") and session.buildings.update_preview_grid(32, 31), "Windmill placement preview accepts valid terrain")
	var preview: BuildingInstance = session.buildings._visual_proxy.get_child(0)
	_check(preview.has_node("VisualRoot/Model/Rotor"), "Preview contains true rotor geometry")
	_check(preview.get_node("Collision").collision_layer == 0 and preview.get_node("ModelCameraCollision").collision_layer == 0, "Placement preview cannot obstruct the player or camera")
	session.buildings.exit_preview_mode()
	var planks := session.inventory.get_item_count("plank")
	var result := session.buildings.try_place_building("windmill", 32, 31)
	_check(result.placed, "Actual building system places the windmill")
	if not result.placed:
		quit(1)
		return
	var windmill: BuildingInstance = result.instance
	windmill.set_process(false)
	_check(session.inventory.get_item_count("plank") == planks - 12, "Construction deducts original twelve planks")
	_check(not interaction.open_windmill(windmill), "Unfinished windmills cannot be operated")
	var model: Node3D = windmill.get_node("VisualRoot/Model")
	for stage in 4:
		windmill.restore_construction(stage, stage * 3.0)
		_check(model.get_node("Foundation").visible, "Foundation remains visible throughout construction")
		_check(model.get_node("Frame").visible == (stage >= 1), "Timber frame appears at frame stage")
		_check(model.get_node("Walls").visible == (stage >= 2), "Stone walls appear at wall stage")
		_check(model.get_node("Rotor").visible == (stage == 3), "Roof fittings and rotor appear on completion")
	for sprite in windmill.find_children("*", "Sprite3D", true, false):
		_check(not sprite.is_visible_in_tree(), "Original flat building and damage sprites never overlap the native model")
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (model.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			_check(material != null and material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED, "Every modeled surface uses physical 3D materials")
	_check(bounds.size.x > 2.4 and bounds.size.z > 2.0 and bounds.size.y > 4.0, "Model has a full tower, deep roof and wide sails")
	_check(bounds.position.y < 0 and bounds.position.y > -.3, "Foundation slightly enters the ground")
	var rotor: Node3D = model.get_node("Rotor")
	_check(rotor.position.is_equal_approx(Vector3(0, 2.64, 1.095)), "Rotor pivot lies at the shaft rather than the world origin")
	var rotor_mesh := rotor.get_child(0) as MeshInstance3D
	var rotor_box: AABB = rotor_mesh.transform * rotor_mesh.get_aabb()
	_check(rotor_box.get_center().length() < .15, "Sail geometry is centered around its movable shaft")
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.position = windmill.position + Vector3(4, 4, 8)
	camera.look_at(windmill.position + Vector3.UP * 1.8)
	camera.make_current()
	await _frames(5)
	var center := windmill.position + Vector3.UP
	var space: PhysicsDirectSpaceState3D = farm.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3.BACK * 4, center, 16))
	_check(hit.get("collider") == windmill.get_node("Collision"), "Windmill yard blocks player movement")
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3.UP * 5, center, 32))
	_check(hit.get("collider") == windmill.get_node("ModelCameraCollision"), "Camera collision covers the roof and rotor")
	player.position = windmill.position + Vector3.BACK * 9
	_check(not interaction.open_windmill(windmill), "Windmill cannot be operated remotely")
	player.position = windmill.position + Vector3.FORWARD * 2.5
	_check(not interaction.open_windmill(windmill), "Windmill cannot be operated through its rear wall")
	player.position = windmill.position + Vector3.BACK * 2.6
	var pointer := camera.unproject_position(windmill.position + Vector3(0, 2, .6))
	_check(interaction.windmill_at_pointer(pointer).get("building") == windmill, "World ray identifies the native windmill")
	session.inventory.add_item("grain", 30)
	session.inventory.add_item("sunflower", 18)
	interaction.select_target("farmland", "dry")
	_click(pointer)
	await _frames()
	_check(view.visible and paused and player.ui_blocked, "Real mouse click opens panel, pauses clock and blocks movement")
	_check(interaction.target_id.is_empty(), "Opening the panel cancels placement")
	_check(view.controller is BuildingProductionPanel and view.controller._production == session.production, "Panel reuses original production controller and authority")
	_check(view.recipe_buttons.size() == 3, "Windmill exposes the original three recipes")
	for id in view.recipe_buttons:
		_check(view.recipe_buttons[id].icon != null, "All processed goods have icons")
	_click(view.recipe_buttons.flour.get_global_rect().get_center())
	view.batches_spin.value = 2
	await _frames()
	_check(view.controller.batches == 2 and view.controller.recipe_detail.duration_minutes == 54, "Batch input updates quantities and original 27-minute recipe duration")
	_check(view.controller.recipe_detail.output_value == session.market.quote_sell("flour", 2), "Panel estimates with current shared batch market pricing")
	var grain := session.inventory.get_item_count("grain")
	_click(view.start_button.get_global_rect().get_center())
	await _frames()
	_check(windmill.producer_state.jobs.size() == 1 and session.inventory.get_item_count("grain") == grain - 4, "Real submit click queues two flour batches and charges once")
	var before_rotation := rotor.rotation.z
	await create_timer(.3).timeout
	_check(windmill.producer_state.jobs[0].remaining_minutes == 54 and rotor.rotation.z == before_rotation, "Production and sails remain paused while panel is open")
	view.controller.select_recipe("animal_feed")
	view.start_button.pressed.emit()
	_check(windmill.producer_state.jobs.size() == 2, "Second recipe occupies the remaining queue slot")
	grain = session.inventory.get_item_count("grain")
	view._start()
	_check(windmill.producer_state.jobs.size() == 2 and session.inventory.get_item_count("grain") == grain, "Full-queue retries cannot charge materials")
	_check(view.start_button.disabled and view.controller.disabled_reason.contains("已满"), "Full queue displays an actionable reason")
	_key(KEY_ESCAPE)
	_check(not paused and not view.visible and not player.ui_blocked, "Escape closes the panel and restores player and clock")
	windmill._process(1.0)
	_check(rotor.rotation.z != before_rotation and windmill.should_play_activity(), "Running production turns the independent sails")
	session.production.advance_minutes(54)
	_check(windmill.producer_state.outputs.get("flour", 0) == 2 and windmill.producer_state.jobs.size() == 1, "First order completes into windmill storage")
	_check(windmill.producer_state.jobs[0].remaining_minutes == 27, "Queued order consumes only time remaining after the first order")
	session.production.advance_minutes(27)
	_check(windmill.producer_state.outputs.get("animal_feed", 0) == 2 and windmill.producer_state.jobs.is_empty(), "Feed recipe yields two items per batch")
	windmill._process(2.0)
	_check(is_zero_approx(windmill.rotor_speed), "Sails settle when production is idle")
	var outputs := windmill.get_node("BuildingOutputDisplay")
	_check(outputs.get_pile_count() == 2, "Finished products appear as separate native yard piles")
	await _frames()
	var pile: Area3D = outputs.get_node("Output_flour")
	camera.position = windmill.position + Vector3(0, 1.5, 7)
	camera.look_at(windmill.position + Vector3(0, .4, 1.38))
	await _frames()
	pointer = camera.unproject_position(pile.global_position + Vector3.UP * .3)
	_check(interaction.windmill_at_pointer(pointer).get("item_id") == "flour", "Front-facing click reaches the goods before the building collider")
	var flour := session.inventory.get_item_count("flour")
	_click(pointer)
	await _frames()
	_check(session.inventory.get_item_count("flour") == flour + 2 and not windmill.producer_state.outputs.has("flour"), "Clicking a yard sack collects only its item into backpack")
	interaction.collect_windmill(windmill, "flour")
	_check(session.inventory.get_item_count("flour") == flour + 2, "Repeated collection cannot duplicate goods")
	interaction.open_windmill(windmill)
	view.collect_button.pressed.emit()
	_check(windmill.producer_state.outputs.is_empty(), "Panel can collect all remaining goods")
	view.controller.select_recipe("sunflower_oil")
	view.controller.set_batches(2)
	view.start_button.pressed.emit()
	view.close_panel()
	session.production.advance_minutes(54)
	_check(windmill.producer_state.outputs.get("sunflower_oil", 0) == 2, "Sunflowers are processed by the original oil recipe")
	var slots := session.inventory.slots.duplicate(true)
	for index in session.inventory.slots.size():
		session.inventory.slots[index] = {"item_id": "stone", "quantity": 999}
	interaction.open_windmill(windmill)
	_check(view.collect_button.disabled, "Full backpack disables collection")
	view._collect("")
	_check(windmill.producer_state.outputs.get("sunflower_oil") == 2, "Failed collection preserves all goods")
	session.inventory.slots = slots
	view.controller.refresh_snapshot()
	view._collect("")
	_check(session.inventory.get_item_count("sunflower_oil") == 2, "Freeing backpack space allows collection")
	# Exercise the generic blocked-storage path with occupied test storage.
	# The current three recipes normally fit all three output types together.
	view.close_panel()
	windmill.producer_state.add_outputs({"wood": 1, "stone": 1, "grain": 1})
	session.production.start_recipe(windmill, "flour", 1, session.inventory)
	session.production.advance_minutes(27)
	windmill._process(2.0)
	interaction.open_windmill(windmill)
	_check(view.controller.queue_slots[0].state == "output-full" and is_zero_approx(windmill.rotor_speed), "Blocked outputs stop the sails and display the authoritative queue state")
	view._collect("wood")
	view.close_panel()
	session.production.advance_minutes(1)
	_check(windmill.producer_state.outputs.get("flour", 0) == 1, "Collecting blocked storage releases the completed job without losing its goods")
	session.production.collect_outputs(windmill, session.inventory)
	interaction.open_windmill(windmill)
	view.controller.select_recipe("flour")
	view.controller.set_batches(9999)
	grain = session.inventory.get_item_count("grain")
	_check(view.start_button.disabled and view.controller.disabled_reason.contains("缺少"), "Insufficient materials are explained without silently changing requested batches")
	view._start()
	_check(session.inventory.get_item_count("grain") == grain, "Insufficient-material retry is atomic")
	view.controller.set_batches(1)
	_check(view.controller.failure_message.is_empty() and not view.start_button.disabled, "Correcting a failed batch removes stale failure feedback")
	view._start()
	view.close_panel()
	session.production.advance_minutes(7)
	var remaining: int = windmill.producer_state.jobs[0].remaining_minutes
	session.production.set_maintenance_due_day(windmill, session.season.total_days)
	session.production.advance_minutes(60)
	windmill._process(2.0)
	_check(windmill.producer_state.jobs[0].remaining_minutes == remaining and is_zero_approx(windmill.rotor_speed), "Overdue maintenance stops production and sails without discarding progress")
	interaction.open_windmill(windmill)
	view.maintenance_button.pressed.emit()
	_check(view.repair_modal.visible and not view.repair_confirm.disabled, "Due maintenance opens cost confirmation")
	_key(KEY_ESCAPE)
	_check(not view.repair_modal.visible and view.visible and paused, "First Escape dismisses maintenance confirmation only")
	view.maintenance_button.pressed.emit()
	var saved_gold: int = wallet.gold
	wallet.gold = 0
	view._refresh_repair()
	_check(view.repair_confirm.disabled, "Insufficient maintenance funds disable payment")
	wallet.gold = saved_gold
	view._refresh_repair()
	var gold: int = wallet.gold
	var wood := session.inventory.get_item_count("wood")
	view.repair_confirm.pressed.emit()
	_check(wallet.gold == gold - 25 and session.inventory.get_item_count("wood") == wood - 1, "Maintenance charges shared wallet and material inventory")
	_check(session.production.get_maintenance_state(windmill) == "repairing", "Maintenance begins a real repair timer")
	view._repair()
	_check(wallet.gold == gold - 25, "Repeated maintenance cannot double-charge")
	await create_timer(3.2).timeout
	_check(paused and session.production.get_maintenance_state(windmill) == "normal", "Three-second maintenance completes while game clock remains paused")
	_check(windmill.producer_state.jobs[0].remaining_minutes == remaining, "Maintenance preserves the exact queued production progress")
	_check(session.production.get_maintenance_days_remaining(windmill) == 14, "Maintenance renews the original fourteen-day interval")
	_check(session.save_game() and session.load_game(), "Queued production and maintenance serialize through the existing 3D save")
	_check(not paused and not view.visible, "Loading a save safely closes the panel and releases pause")
	windmill = session.buildings.get_building_at(32, 31)
	windmill.set_process(false)
	_check(windmill.has_node("VisualRoot/Model/Rotor") and windmill.producer_state.jobs[0].remaining_minutes == remaining, "Reload restores the native model and exact job progress")
	session.production.advance_minutes(remaining)
	_check(windmill.producer_state.outputs.get("flour", 0) == 1, "Restored production can finish")
	_check(session.save_game() and session.load_game(), "Finished goods survive another save and reload")
	windmill = session.buildings.get_building_at(32, 31)
	_check(windmill.get_node("BuildingOutputDisplay").get_pile_count() == 1, "Saved goods restore their native pickup geometry")
	paused = true
	view.open_for(windmill)
	view.close_panel()
	_check(paused, "Closing a panel respects an independently paused game")
	paused = false
	view.open_for(windmill)
	_key(KEY_I)
	_check(hud.inventory_ui.visible and not view.visible and not paused, "Inventory shortcut switches panels and releases the windmill pause")
	hud.close_panels()
	root.content_scale_size = Vector2i(900, 720)
	root.size = Vector2i(900, 720)
	view.open_for(windmill)
	await _frames(5)
	_check(view._narrow and view._cards[1].visible and not view._cards[0].visible, "Narrow viewport presents one production tab at a time")
	_check(view.window.get_global_rect().end.x <= 900 and view.window.get_global_rect().end.y <= 720, "Narrow panel stays within viewport bounds")
	view._tabs.get_child(2).pressed.emit()
	_check(view._cards[2].visible and not view._cards[1].visible, "Queue remains accessible through the narrow layout tab")
	view.close_panel()
	view.open_for(windmill)
	session.buildings.remove_building(windmill)
	await _frames()
	_check(not view.visible and not paused, "Removing the active building closes its panel without trapping pause")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(session.save_path))
	farm.queue_free()
	await _frames()
	print("3D WINDMILL: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL " + str(failures), checks])
	quit(0 if failures.is_empty() else 1)
