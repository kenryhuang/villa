extends SceneTree

const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Landscape tests timed out"); quit(1))
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
	var player: Farm3DPlayer = farm.get_node("Player")
	var session: Farm3DSession = farm.get_node("FarmSession")
	session.season.set_process(false)
	await _frames(3)
	var grid: Farm3DFlatGrid = session.grid
	_check(grid._cells.size() == 25600,"160 x 160 metres of addressable farm cells")
	_check(Profile.region_at(0,0) == "平原","Original farm remains plains")
	_check(Profile.region_at(-43,8) == "丘陵","Western region contains hills")
	_check(Profile.region_at(-4,-66) == "山地","Northern region contains mountains")
	_check(Profile.region_at(Profile.river_x(-50)+6,-50) == "峡谷","Eastern escarpment forms canyon")
	_check(Profile.region_at(Profile.river_x(0),0) == "河流","Continuous river has submerged bed")
	for z in range(-20,21,10):
		for x in range(-20,21,10):
			_check(is_zero_approx(Profile.surface_height(x,z)),"Original farm coordinates retain zero elevation")
	var space: PhysicsDirectSpaceState3D = farm.get_world_3d().direct_space_state
	for point in [Vector2(-42.4,10.3),Vector2(-4.3,-65.7),Vector2(42.3,-50.2),Vector2(60.5,40.5),Vector2(-64,32),Vector2(0,48)]:
		var top := Vector3(point.x,60,point.y)
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(top,top-Vector3.UP*70,1))
		_check(not hit.is_empty(),"Terrain collision exists outside old map: %s" % point)
		if not hit.is_empty():
			_check(absf(hit.position.y-Profile.surface_height(point.x,point.y)) < .015,"Collision matches shared triangulated height: %s" % point)
	_check(grid.get_cell(-63,0) == null and grid.get_cell(98,0) == null,"Expanded bounds reject outside cells")
	_check(grid.is_navigation_cell_walkable(Vector2i(0,15)),"Former 2D boundary no longer blocks 3D navigation")
	# Settle on a hill, then move under real CharacterBody collision.
	player.position = Vector3(-43,Profile.surface_height(-43,10)+.6,10)
	player.velocity = Vector3.ZERO
	player.camera_yaw = 0
	await _frames(60)
	_check(player.is_on_floor() and player.position.y > 4,"Player stands on raised hills")
	var start := player.position
	Input.action_press("move_right")
	await _frames(40)
	Input.action_release("move_right")
	_check(player.position.x-start.x > 1.5 and player.is_on_floor(),"Player walks along the actual hill surface")
	# A full crossing checks both bridge endpoints, plank joints and side rails.
	var bridge_x := Profile.river_x(Profile.BRIDGE_Z)
	player.position = Vector3(bridge_x-9,Profile.surface_height(bridge_x-9,Profile.BRIDGE_Z)+.5,Profile.BRIDGE_Z)
	player.velocity = Vector3.ZERO
	await _frames(50)
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _frames(175)
	Input.action_release("move_right")
	Input.action_release("sprint")
	_check(player.position.x > bridge_x+9,"Player crosses bridge from west bank to east bank without jumping")
	_check(player.position.y > -.1,"Bridge traversal stays above the river")
	var water_point := Vector2(Profile.river_x(0),0)
	player.position = Vector3(water_point.x,Profile.surface_height(water_point.x,0)+.3,0)
	player.velocity = Vector3.ZERO
	await _frames(45)
	Input.action_press("move_back")
	await _frames(5)
	_check(absf(player.velocity.z-player.walk_speed*.6)<.05,"Wading in the river slows movement")
	Input.action_release("move_back")
	var river_coords := grid.world_to_grid(water_point.x,water_point.y)
	var river_cell := grid.get_cell(river_coords.x,river_coords.y)
	_check(river_cell.state == GridCell.State.WATER,"River is unavailable for cultivation")
	_check(not session.apply_target(river_cell,"farmland","dry").ok,"Actual target action rejects river placement")
	var steep: GridCell
	var plot: GridCell
	for candidate: GridCell in grid._cells.values():
		if candidate.gx < 0 and candidate.terrain_height > 2 and candidate.terrain_height < 6:
			if candidate.state == GridCell.State.WASTELAND and candidate.slope > .05 and candidate.slope < .14:
				plot = candidate
		if candidate.slope > 1 and candidate.state == GridCell.State.DECORATION:
			steep = candidate
	_check(plot != null and steep != null,"Expanded terrain contains cultivable slopes and protected cliffs")
	player.set_physics_process(false)
	if steep != null:
		player.position = steep.world_position_3d()
		_check(not session.apply_target(steep,"farmland","dry").ok,"Cliffs reject farmland placement")
	if plot != null:
		player.position = plot.world_position_3d()+Vector3(0,0,1)
		_check(session.apply_target(plot,"farmland","dry").ok,"New elevated plot supports cultivation")
		var holder: Node3D = session.visuals._visuals[GridSystem.cell_key(plot.gx,plot.gz)]
		_check(absf(holder.position.y-plot.terrain_height)<.001,"Soil is positioned at expanded terrain height")
		_check(holder.get_node("Soil").quaternion.angle_to(Quaternion.IDENTITY) > .01,"Soil conforms to gentle slope")
		_check(session.apply_target(plot,"seed","grain_seed").ok,"New elevated plot supports 3D crops")
		var gx := plot.gx
		var gz := plot.gz
		var elevation := plot.terrain_height
		session.save_path = "user://landscape_integration_test.json"
		_check(session.save_game(),"Expanded coordinates save successfully")
		grid.reset_state()
		_check(session.load_game(),"Expanded save restores successfully")
		plot = grid.get_cell(gx,gz)
		_check(plot.crop_instance != null and absf(plot.terrain_height-elevation)<.001,"Negative coordinates retain crop and height on restore")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(session.save_path))
		player.position = plot.world_position_3d()+Vector3.UP*5
		_check(not session._in_range(plot),"A height difference prevents remote farming through cliffs")
	# Multi-cell buildings cannot bridge a height discontinuity.
	var base := grid.get_cell(26,23)
	var adjacent := grid.get_cell(27,23)
	player.position = base.world_position_3d()+Vector3.LEFT*1.2
	adjacent.terrain_height = .5
	var result := session.buildings.diagnose_placement("greenhouse",26,23)
	_check(not result.allowed and result.code == "uneven_terrain","Buildings reject uneven multi-cell footprints")
	adjacent.terrain_height = 0
	# Ray picking still reaches the expanded overview camera's ground distance.
	farm.set_overview(true)
	await _frames(2)
	var camera: Camera3D = farm.get_node("OverviewCamera")
	var cell: GridCell = farm.get_node("FarmInteraction").cell_at_pointer(camera.unproject_position(Vector3(17.5,0,17.5)))
	_check(cell != null and cell.world_position().distance_to(Vector2(17.5,17.5))<1,"Overview camera can ray-pick distant ground")
	farm.queue_free()
	await process_frame
	print("3D LANDSCAPE: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
