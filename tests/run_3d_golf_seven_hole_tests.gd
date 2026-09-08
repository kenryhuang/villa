extends SceneTree
const C = preload("res://scripts/farm3d/golf_course_data.gd")
const B = preload("res://scripts/farm3d/golf_ball.gd")
const P = preload("res://scripts/farm3d/terrain_profile.gd")
const R = preload("res://scripts/farm3d/golf_round.gd")
var checks := 0
var failures := 0
func _initialize():
	create_timer(90).timeout.connect(func(): push_error("Seven hole timeout"); quit(1))
	run.call_deferred()
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func advance_ball(ball: Farm3DGolfBall, seconds: float, cup := Vector2.ZERO, space: PhysicsDirectSpaceState3D = null):
	for frame in ceili(seconds*60):
		ball.advance(1.0/60,cup,space)
		if not ball.moving: break
func run():
	check(C.HOLES.size() == 7 and C.total_par() == 28 and C.BOUNDS.position.y == -72,"Seven winding holes use the northwestern land and sum to par 28")
	for hole in C.HOLES:
		var dry_route := true
		var points := C.route(hole)
		for i in points.size()-1:
			for step in 21:
				var p: Vector2 = points[i].lerp(points[i+1],step/20.0)
				dry_route = dry_route and not P.is_water(p.x,p.y) and P.slope_at(p.x,p.y) < .9
		check(dry_route,"Safe multi-stroke route stays dry and walkable: "+hole.name)
	var right := B.new()
	var left := B.new()
	var straight := B.new()
	for pair in [[right,1.0],[left,-1.0],[straight,0.0]]:
		pair[0].place(C.HOLES[0].tee)
		pair[0].strike(Vector3.BACK,.9,0,-.6,pair[1])
		advance_ball(pair[0],.8)
	var axis := Vector3.BACK.cross(Vector3.UP)
	check((right.position-straight.position).dot(axis) > 1 and (left.position-straight.position).dot(axis) < -1,"Opposite selected spin bends flight to opposite sides")
	check(absf(right.position.y-left.position.y) < .001,"Side spin does not inject vertical lift or change the chosen loft")
	var sampled: Array[Vector3] = []
	for dt in [1.0/30,1.0/144]:
		var sample := B.new()
		sample.place(C.HOLES[0].tee)
		sample.strike(Vector3.BACK,.9,0,-.6,.6)
		for i in roundi(1.0/dt): sample.advance(dt,Vector2.ZERO)
		sampled.append(sample.position)
	check(sampled[0].distance_to(sampled[1]) < .03,"Spin trajectory stays consistent at different frame rates")
	var guide_ball := B.new()
	guide_ball.place(C.HOLES[0].tee)
	var guide := B.preview_path(guide_ball.position,Vector3.BACK,.9,0,-.6,.6)
	guide_ball.strike(Vector3.BACK,.9,0,-.6,.6)
	for i in guide.size()-1: guide_ball.advance(1.0/60,Vector2.ZERO)
	check(guide_ball.position.distance_to(guide[-1]) < .001,"Curved preview and real flight share spin integration")
	for pair in [[right,1.0],[left,-1.0]]:
		pair[0].place(C.HOLES[0].cup+Vector2(0,-2))
		pair[0].strike(Vector3.RIGHT,.3,2,0,pair[1])
		advance_ball(pair[0],.5)
	check(right.position.distance_to(left.position) < .001,"Ground putts follow terrain rather than receiving artificial air curvature")
	for pond in C.PONDS:
		var water_ball := B.new()
		water_ball.place(pond.center)
		water_ball.position.y = 5
		water_ball.velocity = Vector3.RIGHT*3
		water_ball.moving = true
		water_ball.advance(.1,Vector2.ZERO)
		check(water_ball.result != "penalty" and water_ball.moving,"Flying above a pond is legal")
		water_ball.place(pond.center)
		water_ball.position.y = P.WATER_HEIGHT
		water_ball.moving = true
		water_ball.advance(.01,Vector2.ZERO)
		check(water_ball.result == "penalty","Actual contact with pond water produces a penalty")
	var legacy := {"active":true,"hole":1,"strokes":2,"scores":[3],"ball":{"x":-140,"z":120},"best":9}
	var migrated := R.new()
	check(migrated.restore(legacy) and migrated.active and migrated.hole == 0 and migrated.scores.is_empty() and migrated.best == 0,"Old three-hole progress migrates to a fresh seven-hole round without invalidating the farm")
	check(R.valid(migrated.to_dict()) and migrated.layout_changed,"Migration saves the new course version and exposes a layout change notice")
	var invalid := migrated.to_dict()
	invalid.course_version = 999
	check(not R.valid(invalid),"Unknown course versions are rejected")
	var farm = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.farm_session.season.set_process(false)
	farm.farm_session.player.set_physics_process(false)
	for i in 3: await physics_frame
	var space: PhysicsDirectSpaceState3D = farm.get_world_3d().direct_space_state
	for example in [{"hole":2,"yaw":-20.0,"spin":-.6},{"hole":5,"yaw":40.0,"spin":1.0}]:
		var hole: Dictionary = C.HOLES[example.hole]
		var aim := Vector3(hole.cup.x-hole.tee.x,0,hole.cup.y-hole.tee.y).normalized()
		var direct := B.new()
		direct.place(hole.tee)
		direct.strike(aim,1,0,-.6)
		advance_ball(direct,4,hole.cup,space)
		var curve := B.new()
		curve.place(hole.tee)
		curve.strike(aim.rotated(Vector3.UP,deg_to_rad(example.yaw)),1,0,-.6,example.spin)
		advance_ball(curve,4,hole.cup,space)
		check(direct.obstacle_hits > 0,"Direct attack is blocked by actual tree geometry: "+hole.name)
		check(curve.obstacle_hits == 0 and curve.result != "penalty" and Vector2(curve.position.x,curve.position.z).distance_to(hole.cup) < 10,"A playable curved attack bypasses the grove and reaches the green approach: "+hole.name)
	var golf = farm.farm_session.golf
	golf.player.global_position = golf.Art.ground(C.ENTRANCE)+Vector3.BACK*2
	golf.start_round()
	golf.player.global_position = golf.ball.position+Vector3.RIGHT
	golf.enter_address()
	var event := InputEventKey.new()
	event.physical_keycode = KEY_C
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	golf._process(.25)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	check(golf.contact_side > .1,"C adjusts the horizontal contact point in the formal stance")
	golf.gesture.begin(0)
	event = InputEventKey.new()
	event.keycode = KEY_X
	event.pressed = true
	golf.handle_input(event)
	check(golf.contact_side == 0 and not golf.gesture.dragging,"X centers side spin and cancels an uncommitted backswing")
	golf.contact_side = .6
	golf.toggle_handedness()
	check(golf.left_handed and golf.contact_side == .6,"Switching hands preserves the chosen world-relative curve direction")
	golf.begin_swing({"power":.9,"deviation":0.0})
	var spin: float = golf.shot.contact_side
	golf.contact_side = -1
	golf._impact()
	check(spin > 0 and golf.ball.side_spin > 0,"Committed shot snapshots contact spin independently of later UI changes")
	golf.release_control()
	var session = farm.farm_session
	session.save_path = "res://tmp/golf-feel/seven-holes-save.json"
	DirAccess.make_dir_recursive_absolute("res://tmp/golf-feel")
	check(session.save_game() and session.load_game(),"Formal farm save restores the new seven-hole schema")
	var legacy_save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.save_path))
	legacy_save.golf = legacy
	var gold: int = session._game_state().gold
	var file := FileAccess.open(session.save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy_save,"\t"))
	file.close()
	check(session.load_game() and session.golf_round.hole == 0 and session._game_state().gold == gold,"Three-hole farm save migrates only golf and preserves player assets")
	farm.free()
	print("SEVEN HOLE GOLF: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
