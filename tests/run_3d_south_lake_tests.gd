extends SceneTree

const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("South lake tests timed out"); quit(1))
	_run.call_deferred()

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func _frames(count: int) -> void:
	for index in count:
		await physics_frame
	await process_frame

func _run() -> void:
	var farm := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	farm.set_process(false)
	farm.get_node("FarmInteraction").set_process(false)
	var player: Farm3DPlayer = farm.player
	var session: Farm3DSession = farm.farm_session
	session.season.set_process(false)
	var grid: Farm3DFlatGrid = session.grid
	await _frames(3)
	_check(grid._cells.size() == 35840, "Southern extension adds 64 metres without changing grid origin")
	_check(Profile.is_in_world(0,143) and not Profile.is_in_world(0,146), "World bounds include the new south and reject outside terrain")
	_check(Profile.sand_weight(0,40) == 0 and Profile.sand_weight(0,95) == 1, "Farm-side grass gradually becomes southern sand")
	_check(Profile.sand_weight(0,65) > .1 and Profile.sand_weight(0,65) < .9, "Transition includes mixed grass and sand")
	_check(Profile.region_at(-48,95) == "沙地", "Southern dry land is identified as sand")
	_check(Profile.region_at(-6,108) == "南湖" and Profile.is_water(-6,108), "New lake is a named body of water")
	_check(Profile.height_at(-6,108) < Profile.WATER_HEIGHT-2, "Lake contains a submerged bowl rather than a painted water patch")
	_check(Profile.region_at(Profile.river_x(108),108) == "河流", "River continues through the new south independently of the lake")
	var space: PhysicsDirectSpaceState3D = farm.get_world_3d().direct_space_state
	for point in [Vector2(-6,79.8),Vector2(-6,80.2),Vector2(-48,95),Vector2(-6,108),Vector2(-40,108),Vector2(-6,132),Vector2(16,96),Vector2(64,128)]:
		var top := Vector3(point.x,60,point.y)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top,top-Vector3.UP*70,1))
		_check(not hit.is_empty(), "Terrain collision covers southern point %s" % point)
		if not hit.is_empty():
			_check(absf(hit.position.y-Profile.surface_height(point.x,point.y)) < .015, "Southern collision matches terrain triangles at %s" % point)
	var old_wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,10,79),Vector3(0,10,81),16))
	var new_wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,10,142),Vector3(0,10,146),16))
	_check(old_wall.is_empty() and not new_wall.is_empty(), "Player boundary moved from Z=80 to Z=144")
	# Walk through the former edge using the actual character controller.
	player.position = Vector3(-6,Profile.surface_height(-6,65)+.3,65)
	player.velocity = Vector3.ZERO
	player.camera_yaw = 0
	await _frames(30)
	Input.action_press("move_back")
	Input.action_press("sprint")
	await _frames(165)
	Input.action_release("move_back")
	Input.action_release("sprint")
	_check(player.position.z > 82 and player.is_on_floor(), "Farmer walks from grass through old southern boundary to the lake approach")
	var shores := farm.get_node("Landscape/LakeFishingShores")
	_check(shores.get_child_count() == 3, "Three discoverable shoreline markers are ready for fishing integration")
	for spot in Profile.LAKE_FISHING_SPOTS:
		var marker: Marker3D = shores.get_node(spot.id)
		var target: Marker3D = marker.get_node("CastTarget")
		_check(marker.is_in_group("farm3d_fishing_shores") and marker.get_meta("water_body_id") == "south_lake", "Fishing shore exposes stable lake identity: %s" % spot.id)
		_check(not Profile.is_water(marker.position.x,marker.position.z) and Profile.slope_at(marker.position.x,marker.position.z) < .25, "Fishing shore has dry, gently sloped footing: %s" % spot.id)
		_check(Profile.is_lake(target.global_position.x,target.global_position.z) and is_equal_approx(target.global_position.y,Profile.WATER_HEIGHT), "Cast target lies on lake water: %s" % spot.id)
		player.position = marker.position + Vector3.UP*.3
		player.velocity = Vector3.ZERO
		await _frames(35)
		_check(player.is_on_floor() and player.position.distance_to(marker.position) < .15, "Farmer stands securely at fishing shore: %s" % spot.id)
		var coords := grid.world_to_grid(marker.position.x,marker.position.z)
		var cell := grid.get_cell(coords.x,coords.y)
		_check(cell.state == GridCell.State.DECORATION and not session.apply_target(cell,"farmland","dry").ok, "Fishing access is reserved against farmland: %s" % spot.id)
		_check(not session.buildings.diagnose_placement("fence",coords.x,coords.y).allowed, "Buildings cannot occupy fishing access: %s" % spot.id)
	var water_coords := grid.world_to_grid(-6,108)
	var water_cell := grid.get_cell(water_coords.x,water_coords.y)
	player.position = water_cell.world_position_3d() + Vector3.UP*.3
	player.velocity = Vector3.ZERO
	await _frames(35)
	_check(water_cell.state == GridCell.State.WATER and not session.apply_target(water_cell,"farmland","dry").ok, "Lake cells reject cultivation")
	Input.action_press("move_right")
	await _frames(4)
	_check(absf(player.velocity.x-player.walk_speed*.6) < .05, "Existing wading movement applies in the lake")
	Input.action_release("move_right")
	player.set_physics_process(false)
	var plot: GridCell
	for candidate: GridCell in grid._cells.values():
		if candidate.world_position().y > 86 and candidate.world_position().y < 100 and candidate.state == GridCell.State.WASTELAND and candidate.slope < .12:
			plot = candidate
			break
	_check(plot != null, "Expanded dry terrain has usable plots")
	if plot != null:
		player.position = plot.world_position_3d()+Vector3.UP*.1
		_check(session.apply_target(plot,"farmland","dry").ok, "New southern coordinates support existing target interaction")
		session.save_path = "user://south_lake_test.json"
		_check(session.save_game(), "Southern coordinates save")
		grid.reset_state()
		_check(session.load_game() and grid.get_cell(plot.gx,plot.gz).state == GridCell.State.FARMLAND, "Southern plot restores at the same coordinate and height")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(session.save_path))
	farm.set_overview(true)
	await _frames(2)
	var point := Vector3(-6,Profile.surface_height(-6,84),84)
	var picked: GridCell = farm.get_node("FarmInteraction").cell_at_pointer(farm.overview_camera.unproject_position(point))
	_check(picked != null and picked.world_position().distance_to(Vector2(-6,84)) < 1, "Overview can pick the new lake shore")
	farm.queue_free()
	await process_frame
	print("3D SOUTH LAKE: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
