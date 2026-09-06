extends SceneTree

const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const Fishing = preload("res://scripts/farm3d/farm_fishing.gd")
var checks := 0
var failures: Array[String] = []
var farm: Node3D
var player: Farm3DPlayer
var fishing: Node3D
var hud: CanvasLayer

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("3D fishing tests timed out"); quit(1))
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame

func _stand(point: Vector2) -> void:
	fishing.cancel()
	player.set_physics_process(true)
	player.position = Vector3(point.x,Profile.surface_height(point.x,point.y)+.2,point.y)
	player.velocity = Vector3.ZERO
	await _frames(35)
	player.set_physics_process(false)
	fishing.refresh_location()

func _press(key: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = key
	root.push_input(event,true)

func _run() -> void:
	farm = (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	player = farm.player
	fishing = farm.get_node("FarmInteraction/Fishing")
	hud = farm.get_node("FarmInteraction").hud
	var session = farm.farm_session
	var inventory: InventorySystem = session.inventory
	session.season.set_process(false)
	fishing.set_process(false)
	await _frames(3)
	fishing.refresh_location()
	_check(hud.fishing_button.disabled and not fishing.equip(),"Rod is unavailable inland, including direct equip calls")
	for spot in Profile.LAKE_FISHING_SPOTS:
		await _stand(spot.shore)
		_check(not hud.fishing_button.disabled and fishing.available_location.get("body") == "lake","Lake shore accepts fishing: %s" % spot.id)
	await _stand(Vector2(Profile.river_x(0)-8,0))
	_check(fishing.available_location.get("body") == "river","River bank accepts fishing")
	hud.fishing_button.pressed.emit()
	_check(fishing.state == Fishing.State.READY and player.fishing_locked and fishing.visual.visible,"Tool button equips rod and locks fishing stance")
	var stand_position := player.position
	player.set_physics_process(true)
	Input.action_press("move_back")
	Input.action_press("sprint")
	Input.action_press("jump")
	await _frames(4)
	Input.action_release("move_back")
	Input.action_release("sprint")
	Input.action_release("jump")
	player.set_physics_process(false)
	_check(player.position.distance_to(stand_position) < .02,"Fishing stance prevents movement, sprint and jump from disrupting the cast")
	_press(KEY_E)
	_check(fishing.state == Fishing.State.CASTING,"E starts a cast instead of farming")
	fishing.visual.update_pose("CASTING",.3,Fishing.CAST_TIME,fishing.location.water,fishing.catch_id)
	_check(fishing.visual._rod_segments.size() == 12 and fishing.visual._line.size() == 28,"Rod and line are actual segmented meshes")
	_check(fishing.visual.tip_world.distance_to(player.position) > 1,"Rod tip follows the casting pose")
	_press(KEY_ESCAPE)
	_check(not fishing.is_equipped() and not player.fishing_locked and inventory._capacity_reservations.is_empty(),"Esc cancels cast, restores movement and releases inventory space")
	await _stand(Vector2(Profile.river_x(0),0))
	_check(not fishing.equip(),"Standing in water cannot equip the rod")
	await _stand(Vector2(Profile.river_x(-50)+6,-50))
	_check(not fishing.equip(),"High canyon ledge cannot fish through a large height difference")
	await _stand(Vector2(Profile.river_x(Profile.BRIDGE_Z),Profile.BRIDGE_Z))
	_check(not fishing.equip(),"Bridge surface is excluded from shoreline fishing")
	await _stand(Vector2(-6,84))
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30,8,.6)
	collision.shape = box
	wall.add_child(collision)
	farm.add_child(wall)
	wall.position = Vector3(-6,1,86)
	await _frames(2)
	_check(not fishing.equip(),"Blocked casting arc cannot equip through an obstacle")
	wall.queue_free()
	await _frames(2)
	_check(fishing.equip(),"Rod becomes available after obstruction clears")
	# Deterministic seeded attempts exercise both random outcomes using real rolls.
	fishing.rng.seed = 128
	var successful_bites := 0
	var empty_casts := 0
	var successful_catches := 0
	for attempt in 16:
		var result: Dictionary = fishing.act()
		_check(result.ok,"Ready rod accepts cast %d" % attempt)
		if not result.ok:
			break
		var item: String = fishing.catch_id
		var before := inventory.get_item_count(item)
		fishing.advance(Fishing.CAST_TIME)
		_check(fishing.state == Fishing.State.WAITING,"Cast completes before waiting for bite")
		fishing.advance(fishing.duration)
		if fishing.state == Fishing.State.BITE:
			successful_bites += 1
			if successful_bites == 1:
				fishing.advance(Fishing.BITE_TIME)
				_check(inventory.get_item_count(item) == before and fishing.state == Fishing.State.RECOVERING,"Missed bite escapes without granting a fish")
				fishing.advance(.8)
				continue
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = Vector2(700,400)
			root.push_input(click,true)
			_check(fishing.state == Fishing.State.REELING,"World left click reels a biting fish")
			_check(not fishing.act().ok and inventory.get_item_count(item) == before,"Repeated reel cannot grant fish early or twice")
			fishing.advance(Fishing.REEL_TIME)
			fishing.visual.update_pose("LANDING",.4,Fishing.LAND_TIME,fishing.location.water,item)
			_check(fishing.visual.fish.visible and inventory.get_item_count(item) == before,"Fish is shown out of water before inventory settlement")
			fishing.advance(Fishing.LAND_TIME)
			_check(inventory.get_item_count(item) == before+1 and fishing.state == Fishing.State.READY,"Landing places exactly one named fish in the backpack")
			successful_catches += 1
		else:
			empty_casts += 1
			_check(fishing.state == Fishing.State.RECOVERING and inventory.get_item_count(item) == before,"Chance can produce an empty cast")
			fishing.advance(.8)
	_check(successful_catches > 0 and empty_casts > 0,"Seeded attempts include both catches and no-bite outcomes")
	_check(inventory._capacity_reservations.is_empty(),"Finished attempts leave no inventory reservations")
	# Early retrieval, modal cancellation, full bag, reset and durable catches.
	fishing.act()
	fishing.advance(Fishing.CAST_TIME)
	_check(fishing.act().reason == "early_reel" and inventory._capacity_reservations.is_empty(),"Reeling before bite loses the attempt and frees capacity")
	fishing.advance(.8)
	fishing.act()
	_press(KEY_I)
	_check(not fishing.is_equipped() and hud.inventory_ui.visible and inventory._capacity_reservations.is_empty(),"Opening backpack safely cancels fishing")
	var fish_labels: Array[String] = []
	for label in hud.inventory_ui.grid_container.find_children("*","Label",true,false):
		fish_labels.append(label.text)
	_check("鲤鱼" in fish_labels or "溪鲫" in fish_labels or "夜鲶" in fish_labels,"Caught fish is named in the backpack UI")
	hud.close_panels()
	var saved_slots := inventory.slots.duplicate(true)
	for index in inventory.slots.size():
		inventory.slots[index] = {"item_id":"wood","quantity":99}
	fishing.equip()
	_check(fishing.act().reason == "inventory_full" and fishing.state == Fishing.State.READY,"Full inventory refuses casting before an attempt begins")
	inventory.slots.assign(saved_slots)
	fishing.act()
	_press(KEY_R)
	_check(not fishing.is_equipped() and not player.fishing_locked and inventory._capacity_reservations.is_empty(),"Return-to-farm cancels fishing and restores controls")
	session.save_path = "user://fishing_3d_integration_test.json"
	_check(session.save_game(),"Fish inventory saves in the 3D farm save")
	inventory.reset_slots()
	_check(session.load_game() and inventory.slots == saved_slots,"Caught fish restores with the original backpack")
	await _stand(Vector2(-6,84))
	fishing.equip()
	fishing.act()
	farm._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(not fishing.is_equipped() and inventory._capacity_reservations.is_empty(),"Losing window focus cancels fishing and releases reserved capacity")
	fishing.equip()
	fishing.act()
	player.position += Vector3.RIGHT*2
	fishing.advance(.1)
	_check(not fishing.is_equipped() and inventory._capacity_reservations.is_empty(),"External displacement cancels an active cast before settlement")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(session.save_path))
	farm.queue_free()
	await process_frame
	print("3D FISHING: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
