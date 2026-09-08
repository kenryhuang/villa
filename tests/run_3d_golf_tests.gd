extends SceneTree

const Course = preload("res://scripts/farm3d/golf_course_data.gd")
const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const Swing = preload("res://scripts/farm3d/golf_swing.gd")
const Ball = preload("res://scripts/farm3d/golf_ball.gd")
const Round = preload("res://scripts/farm3d/golf_round.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(65).timeout.connect(func(): push_error("Golf tests timed out"); quit(1))
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
	root.push_input(event,true)

func _mouse(pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	root.push_input(event,true)

func _held(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	root.push_input(event,true)

func _simulate(ball: Farm3DGolfBall, cup: Vector2) -> void:
	for i in 2100:
		ball.advance(1.0/60,cup)
		if not ball.moving:
			return

func _run() -> void:
	var swing := Swing.new()
	swing.begin(1)
	_check(swing.motion(Vector2(0,-120),1.2).is_empty(),"Forward flick without backswing does not strike")
	swing.begin(2)
	_check(swing.motion(Vector2(0,160),2.2).is_empty(),"Backswing alone never strikes")
	var shot := swing.motion(Vector2(0,-165),2.4)
	_check(not shot.is_empty() and shot.power > .6 and absf(shot.deviation) < .001,"Straight back-and-forward mouse movement generates power and a square strike")
	_check(swing.motion(Vector2(0,-40),2.5).is_empty(),"One gesture can only trigger one strike")
	swing.begin(3)
	swing.motion(Vector2(0,160),3.2)
	var slow := swing.motion(Vector2(40,-165),3.9)
	_check(is_equal_approx(slow.power,shot.power) and slow.deviation > 0 and slow.deviation < deg_to_rad(3.5),"Forward speed preserves selected power and deliberate lateral motion gives bounded deviation")
	for duration in [.01,.08,.3,1.5]:
		swing.begin(0)
		swing.motion(Vector2(3,160),.2)
		var steady := swing.motion(Vector2(8,-200),.2+duration)
		_check(not steady.is_empty() and is_equal_approx(steady.power,shot.power) and steady.deviation == 0,"Natural hand jitter and different forward speeds preserve a square shot: %.2f" % duration)
	swing.begin(0)
	swing.motion(Vector2(0,120),.2)
	var normal_short := swing.power()
	var precise_short := swing.power(true)
	var short_shot := swing.motion(Vector2(75,-140),.4,true)
	_check(precise_short < normal_short and is_equal_approx(short_shot.power,precise_short),"Short-stroke power offers finer distance control and matches the live gauge")
	_check(short_shot.deviation > 0 and short_shot.deviation <= deg_to_rad(1.21),"Putting retains a lateral skill penalty with a tighter angle limit")
	swing.begin(0)
	swing.motion(Vector2(0,900),.2)
	_check(swing.peak == Swing.FULL_PULL and swing.offset.y == Swing.FULL_PULL,"Full backswing has no invisible excess travel")
	_check(not swing.motion(Vector2(0,-190),.4).is_empty(),"Returning from a saturated backswing reliably strikes")
	swing.begin(0)
	swing.motion(Vector2(0,8),.2)
	_check(swing.motion(Vector2(0,-12),.4).is_empty(),"An accidental click or tiny drag does not consume a stroke")
	swing.begin(4)
	swing.motion(Vector2(0,160),4.2)
	swing.cancel()
	_check(swing.motion(Vector2(0,-165),4.4).is_empty(),"Releasing before impact cancels the swing")
	var whole := Swing.new()
	var sampled := Swing.new()
	whole.begin(0)
	sampled.begin(0)
	whole.motion(Vector2(0,160),.2)
	for i in 20:
		sampled.motion(Vector2(0,8),float(i+1)*.01)
	var one := whole.motion(Vector2(0,-145),.4)
	var many := {}
	for i in 20:
		var result := sampled.motion(Vector2(0,-7.25),.2+float(i+1)*.01)
		if not result.is_empty():
			many = result
	_check(not many.is_empty() and absf(one.power-many.power) < .02,"Swing power is stable across mouse event frequencies")
	whole.begin(0)
	sampled.begin(0)
	whole.motion(Vector2(0,160),.2)
	sampled.motion(Vector2(0,160),.2)
	one = whole.motion(Vector2(100,-400),.4)
	many = {}
	for i in 40:
		var result := sampled.motion(Vector2(2.5,-10),.2+float(i+1)*.005)
		if not result.is_empty(): many = result
	_check(not many.is_empty() and is_equal_approx(one.deviation,many.deviation),"Mouse travel after contact cannot change deviation at different event rates")
	var preview_origin: Vector2 = Course.HOLES[0].cup+Vector2(0,-2.5)
	var preview_ball := Ball.new()
	preview_ball.place(preview_origin)
	var guide := Ball.preview_path(preview_ball.position,Vector3.RIGHT,.5,2,0)
	preview_ball.strike(Vector3.RIGHT,.5,2,0)
	for i in guide.size()-1:
		preview_ball.advance(1.0/60,Vector2.ZERO)
	_check(guide.size() == 73 and guide[-1].distance_to(preview_ball.position) < .0001 and preview_ball.moving,"Partial rolling guide uses actual slope and friction without revealing the final stopping point")
	var round_state := Round.new()
	_check(Round.valid(round_state.to_dict()),"Empty round state has a valid save schema")
	round_state.start()
	_check(Round.valid(round_state.to_dict()),"New round checkpoint validates")
	var long_round := Round.new()
	long_round.start()
	for i in Course.HOLES.size():
		long_round.hole = i
		long_round.strokes = 13
		long_round.complete_hole()
	_check(long_round.scores.size() == 7 and long_round.scores.all(func(score): return score == 13) and long_round.best == 91,"Actual completed scores above twelve and totals above thirty-six are retained")
	_check(Round.valid(long_round.to_dict()),"Extended scores remain valid save data")
	var restored_long_round := Round.new()
	_check(restored_long_round.restore(long_round.to_dict()) and restored_long_round.best == 91,"Completed long round survives restoration")
	for field in ["hole","strokes","best"]:
		var malformed := round_state.to_dict()
		malformed[field] = -1
		_check(not Round.valid(malformed),"Invalid saved %s is rejected" % field)
	var malformed := round_state.to_dict()
	malformed.ball.x = NAN
	_check(not Round.valid(malformed),"Non-finite saved ball coordinates are rejected")
	for i in Course.HOLES.size():
		var hole: Dictionary = Course.HOLES[i]
		_check(Course.BOUNDS.has_point(hole.tee) and hole.tee.x < -80 and hole.cup.x < -80,"Each hole stays in newly added land")
		_check(Course.surface(hole.cup) == "green" and Course.surface(hole.tee) == "fairway","Tees and greens have matching surface definitions")
	var moving_ball := Ball.new()
	var lifted := Ball.launch_velocity(Vector3.BACK,.8,0,"fairway",-.8)
	var centered := Ball.launch_velocity(Vector3.BACK,.8,0,"fairway",0)
	var gentle := Ball.launch_velocity(Vector3.BACK,.035,0,"fairway",-.8)
	_check(lifted.y > 5 and centered.y == 0,"Same club can launch or roll according to the contact point")
	_check(gentle.y == 0 and gentle.length() < centered.length(),"Light strokes roll even with a low contact point")
	_check(Ball.launch_velocity(Vector3.BACK,.8,0,"fairway",.8).y == 0,"Top contact does not launch a ball upward")
	_check(Ball.launch_velocity(Vector3.BACK,.2,0,"fairway",-.8).y < lifted.y,"Loft responds to both contact point and power")
	_check(Ball.launch_velocity(Vector3.BACK,.8,2,"fairway",0).y == 0,"Default putter contact remains a ground stroke")
	moving_ball.place(Course.HOLES[0].tee)
	var launch := moving_ball.position
	moving_ball.strike(Vector3.BACK,.6,0)
	moving_ball.advance(.1,Course.HOLES[0].cup)
	_check(moving_ball.position.y > launch.y and moving_ball.position.z > launch.z,"Driver sends the ball into a visible airborne arc")
	_simulate(moving_ball,Course.HOLES[0].cup)
	_check(not moving_ball.moving and moving_ball.position.distance_to(launch) > 15,"Driver ball lands, rolls and eventually stops")
	_check(moving_ball.position.y >= Profile.surface_height(moving_ball.position.x,moving_ball.position.z),"Ball does not sink through the terrain")
	var green_ball := Ball.new()
	var rough_ball := Ball.new()
	green_ball.place(Course.HOLES[0].cup+Vector2(0,-2.5))
	rough_ball.place(Vector2(-158,95))
	green_ball.strike(Vector3.RIGHT,.1,2)
	rough_ball.strike(Vector3.RIGHT,.1,2)
	var green_start := green_ball.position
	var rough_start := rough_ball.position
	_simulate(green_ball,Vector2.ZERO)
	_simulate(rough_ball,Vector2.ZERO)
	_check(green_ball.position.distance_to(green_start) > rough_ball.position.distance_to(rough_start),"Short green grass rolls farther than rough")
	var cup: Vector2 = Course.HOLES[0].cup
	moving_ball.place(cup+Vector2(0,-.23))
	moving_ball.velocity = Vector3.BACK*.4
	moving_ball.moving = true
	_simulate(moving_ball,cup)
	_check(moving_ball.result == "holed" and moving_ball.position.y < Profile.surface_height(cup.x,cup.y),"Slow ball enters and drops into the cup")
	moving_ball.place(cup+Vector2(0,-.23))
	moving_ball.velocity = Vector3.BACK*6
	moving_ball.moving = true
	moving_ball.advance(.1,cup)
	_check(moving_ball._drop_seconds >= 0 and moving_ball.result.is_empty(),"Fast grounded ball starts dropping instead of skipping the cup")
	_simulate(moving_ball,cup)
	_check(moving_ball.result == "holed","Fast grounded ball finishes the same visible drop as a slow putt")
	moving_ball.place(Vector2(-166,90))
	moving_ball.velocity = Vector3.LEFT*12
	moving_ball.moving = true
	_simulate(moving_ball,cup)
	_check(moving_ball.result == "penalty","Out-of-bounds ball produces a single penalty result")
	root.size = Vector2i(1440,960)
	var farm := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var session: Farm3DSession = farm.farm_session
	var interaction = farm.get_node("FarmInteraction")
	var golf = session.golf
	var player = session.player
	var hud = interaction.hud
	player.set_physics_process(false)
	session.season.set_process(false)
	session.save_path = "user://golf_integration_test.json"
	await _frames()
	_check(session.grid._cells.size() == 57344,"West extension produces 256 by 224 metres of terrain")
	_check(golf.course.flags.size() == 7 and golf.visual.club != null,"Native seven-hole course and golf club exist in formal scene")
	for z in [55,72,90,120]:
		_check(absf(Profile.height_at(-80.001,z)-Profile.height_at(-79.999,z)) < .01,"Expanded west terrain meets the existing terrain continuously")
	player.global_position = Vector3(-74,Profile.surface_height(-74,72)+.2,72)
	player.camera_yaw = 0
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await _frames(20)
	Input.action_press("move_left")
	Input.action_press("sprint")
	await _frames(110)
	Input.action_release("move_left")
	Input.action_release("sprint")
	_check(player.global_position.x < -88 and player.is_on_floor(),"Player can walk across the old west boundary to the golf course")
	player.set_physics_process(false)
	var space: PhysicsDirectSpaceState3D = farm.get_world_3d().direct_space_state
	for hole in Course.HOLES:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(hole.tee.x,20,hole.tee.y),Vector3(hole.tee.x,-4,hole.tee.y),1))
		_check(not hit.is_empty() and absf(hit.position.y-Profile.surface_height(hole.tee.x,hole.tee.y)) < .02,"Golf terrain collision agrees with shared height")
		hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(hole.cup.x,8,hole.cup.y),Vector3(hole.cup.x,-2,hole.cup.y),1))
		_check(hit.is_empty(),"Hole is cut through the terrain collider, not painted on top")
		var rolling_ball := Ball.new()
		rolling_ball.place(hole.cup+Vector2(0,-.5))
		rolling_ball.velocity = Vector3.BACK*12
		rolling_ball.moving = true
		for frame in 45:
			rolling_ball.advance(1.0/60,hole.cup,space)
		_check(rolling_ball.result == "holed","Fast rolling shot enters the real scene cup with collision enabled")
		var coords := session.grid.world_to_grid(hole.tee.x,hole.tee.y)
		_check(session.grid.get_cell(coords.x,coords.y).state == GridCell.State.DECORATION,"Golf playing surfaces are protected from farming placement")
	for p in [Vector2(-148.2,84.3),Vector2(-125.2,121.3),Vector2(-94.2,96.3)]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x,20,p.y),Vector3(p.x,-4,p.y),1))
		_check(not hit.is_empty() and absf(hit.position.y-Profile.surface_height(p.x,p.y)) < .01 and hit.normal.dot(Profile.surface_normal(p.x,p.y)) > .999,"Hill mesh height and slope agree with ball physics")
	_check(not golf.start_round(),"Players cannot borrow clubs remotely")
	player.global_position = golf.Art.ground(Course.ENTRANCE)+Vector3.BACK*2
	_key(KEY_E)
	_check(golf.round_state.active and golf.phase == golf.Phase.WALK,"E near the rack starts a free round")
	_check(not golf.enter_address(),"Players must walk to the ball before addressing it")
	player.global_position = golf.ball.position+Vector3.RIGHT
	_key(KEY_E)
	_check(golf.phase == golf.Phase.ADDRESS and player.golf_locked and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED),"E at ball locks a golf stance and captures relative mouse input")
	await _frames(10)
	_check(golf._panel.size.y < 240,"Golf HUD remains compact and leaves the player and ball visible")
	var ball_position: Vector3 = golf.ball.position
	var neutral: Vector3 = player.to_local(golf.visual._head_point)
	var clear_markers := true
	for tee_marker in golf.course.find_children("TeeMarker*","MeshInstance3D",true,false):
		clear_markers = clear_markers and tee_marker.global_position.distance_to(player.global_position) > .5
	_check(clear_markers,"Tee markers leave enough space for the player's feet")
	_check(golf.direction.dot(-player.global_basis.x) > .99,"Golfer faces the ball side-on and swings toward the left")
	_check(golf._camera.unproject_position(player.global_position+Vector3.UP*.8).x > golf._camera.unproject_position(ball_position).x,"Default camera shows the golfer to the right of the ball")
	_check(golf._camera.unproject_position(ball_position+golf.direction*2).x < golf._camera.unproject_position(ball_position).x,"Default camera shows the shot traveling left")
	_check(golf.visual._head_point.distance_to(ball_position) < .08,"Addressed club face meets the selected point on the ball")
	golf.visual.pose(1,0)
	_check(player.to_local(golf.visual._head_point).x > neutral.x+.5,"Backswing lifts the club to the golfer's right")
	golf.visual.pose(-1,0)
	_check(player.to_local(golf.visual._head_point).x < neutral.x-.5,"Follow-through sweeps left past the ball")
	golf.visual.pose(0,0)
	var right_stance: Vector3 = player.global_position
	var hand_aim: Vector3 = golf.direction
	var hand_camera: Vector3 = golf._camera.global_position
	_mouse(true)
	_motion(Vector2(0,80))
	_key(KEY_H)
	_check(golf.left_handed and not golf.gesture.dragging and golf.phase == golf.Phase.ADDRESS,"H switches to left-handed stance and safely cancels the uncommitted pull")
	_check(golf.direction.is_equal_approx(hand_aim) and golf.ball.position == ball_position and golf.round_state.strokes == 0,"Switching hands changes neither shot aim, ball nor score")
	_check(golf._camera.global_position.is_equal_approx(hand_camera),"Switching hands preserves the chosen orbit camera")
	_check(player.global_position.distance_to(right_stance) > 1.5 and golf.direction.dot(player.global_basis.x) > .99,"Left-handed golfer stands across the ball and strikes toward local right")
	_check(golf._camera.unproject_position(player.global_position+Vector3.UP*.8).x < golf._camera.unproject_position(ball_position).x,"Left stance appears on the opposite side of the ball in the default view")
	for club_index in 3:
		golf.visual.pose(0,club_index)
		var left_neutral: Vector3 = player.to_local(golf.visual._head_point)
		_check(golf.visual._head_point.distance_to(ball_position) < .08,"Left-handed club meets the ball: %d" % club_index)
		golf.visual.pose(.7,club_index)
		_check(player.to_local(golf.visual._head_point).x < left_neutral.x-.3,"Left-handed backswing raises the club to local left: %d" % club_index)
		golf.visual.pose(-.7,club_index)
		_check(player.to_local(golf.visual._head_point).x > left_neutral.x+.3,"Left-handed follow-through sweeps to local right: %d" % club_index)
	_key(KEY_H)
	_mouse(false)
	_check(not golf.left_handed and player.global_position.distance_to(right_stance) < .01 and golf.visual._head_point.distance_to(ball_position) < .08,"Switching back restores the right-handed stance and club contact")
	var original_direction: Vector3 = golf.direction
	var original_camera: Vector3 = golf._camera.global_position
	_mouse(true)
	_motion(Vector2(0,80))
	_mouse(true,MOUSE_BUTTON_RIGHT)
	_motion(Vector2(110,-20))
	_check(not golf.gesture.dragging and golf.phase == golf.Phase.ADDRESS,"Right drag cancels a pending backswing without striking")
	_check(golf._camera.global_position.distance_to(original_camera) > 1,"Right mouse drag rotates the stance camera")
	_check(golf.direction.is_equal_approx(original_direction) and golf.ball.position == ball_position,"Camera orbit changes neither aim nor ball position")
	_mouse(false,MOUSE_BUTTON_RIGHT)
	_mouse(false)
	var orbited: Vector3 = golf._camera.global_position
	await _frames()
	_check(golf._camera.global_position.distance_to(orbited) < .01,"Camera retains the chosen view after right drag ends")
	_mouse(true,MOUSE_BUTTON_WHEEL_UP)
	_check(is_equal_approx(golf.contact_height,-.5),"Mouse wheel moves the contact point upward")
	_held(KEY_W,true)
	await _frames(6)
	_held(KEY_W,false)
	_check(golf.contact_height > -.5,"W raises the contact point while in stance")
	var raised: float = golf.contact_height
	_held(KEY_S,true)
	await _frames(6)
	_held(KEY_S,false)
	_check(golf.contact_height < raised,"S lowers the contact point while in stance")
	_held(KEY_Q,true)
	await _frames(6)
	_held(KEY_Q,false)
	_check(golf.stance_distance > .8 and golf.ball.position == ball_position,"Q adjusts standing distance while leaving the ball fixed")
	_check(golf.visual._head_point.distance_to(ball_position) < .08,"Club still addresses the ball after standing distance changes")
	Input.action_press("move_right")
	await _frames(6)
	Input.action_release("move_right")
	_check(golf.direction.distance_to(original_direction) > .01,"A/D changes the shot direction before striking")
	_check(golf._camera.global_position.distance_to(orbited) < .01,"Changing aim does not reset the camera orbit")
	golf.set_process(false)
	var normal_aim: Vector3 = golf.direction
	Input.action_press("move_right")
	golf._process(.1)
	var coarse_angle: float = normal_aim.angle_to(golf.direction)
	normal_aim = golf.direction
	_held(KEY_SHIFT,true)
	Input.flush_buffered_events()
	golf._process(.1)
	var fine_angle: float = normal_aim.angle_to(golf.direction)
	_held(KEY_SHIFT,false)
	Input.flush_buffered_events()
	Input.action_release("move_right")
	golf.set_process(true)
	_check(fine_angle > 0 and fine_angle < coarse_angle*.25,"Holding Shift gives precise aiming without changing the camera or stance mode")
	_key(KEY_3)
	_check(golf.club == 2 and golf.contact_height == 0,"Number keys select the putter and center its contact point")
	golf.gesture.peak = 190
	_check(golf._backswing_angle() <= .75,"Putting uses a compact pendulum stroke")
	_key(KEY_1)
	golf.gesture.peak = 190
	_check(golf._backswing_angle() > 2,"Low contact with the driver allows a full backswing")
	golf.gesture.cancel()
	_mouse(true,MOUSE_BUTTON_WHEEL_DOWN)
	_key(KEY_H)
	_mouse(true)
	_motion(Vector2(0,150))
	var pull_angle: float = golf._backswing_angle()
	_motion(Vector2(0,-60))
	_check(golf.gesture.dragging and golf._backswing_angle() < pull_angle*.7,"Club follows the player's forward movement before committing contact")
	golf._update_hud()
	var displayed_power: float = golf._power.value/100
	await create_timer(.12).timeout
	_motion(Vector2(12,-90))
	_check(golf.phase == golf.Phase.SWING,"Real back-forward mouse events trigger swing animation")
	_check(absf(golf.shot.power-displayed_power) < .01 and golf.shot.impact_delay <= .08,"Impact uses displayed power and responds without a second full backswing")
	_check(is_equal_approx(golf.shot.contact_height,-.7),"Strike snapshots the chosen contact point")
	_key(KEY_H)
	_check(golf.left_handed and golf.phase == golf.Phase.SWING,"Committed left-handed shot cannot change hands during the swing")
	_mouse(true,MOUSE_BUTTON_RIGHT)
	_motion(Vector2(-30,10))
	_mouse(false,MOUSE_BUTTON_RIGHT)
	_check(golf.phase == golf.Phase.SWING and is_equal_approx(golf.shot.contact_height,-.7),"Orbit during a committed swing does not cancel or alter the shot")
	_mouse(false)
	await create_timer(.3).timeout
	_check(golf.phase == golf.Phase.FLIGHT and golf.ball.moving,"Ball launches at the animation's impact frame")
	_check(golf.left_handed and not golf.toggle_handedness(),"Left-handed shot follows the normal ball flight and cannot switch sides in flight")
	var flight_yaw: float = golf._orbit_yaw
	_mouse(true,MOUSE_BUTTON_RIGHT)
	_motion(Vector2(30,0))
	_mouse(false,MOUSE_BUTTON_RIGHT)
	_check(not is_equal_approx(golf._orbit_yaw,flight_yaw),"Right mouse orbit also works while following the flying ball")
	_check(not golf.enter_address(),"Moving balls cannot be struck a second time")
	var checkpoint := session.golf_round.to_dict()
	_check(checkpoint.strokes == 0 and checkpoint.ball.x == Course.HOLES[0].tee.x,"Mid-flight save keeps the preceding settled checkpoint")
	_key(KEY_ESCAPE)
	_check(not player.golf_locked and not golf.watch_camera and golf.ball.moving,"Escape releases camera and player while the struck ball continues")
	golf.set_process(false)
	_simulate(golf.ball,Course.HOLES[0].cup)
	golf._settle()
	_check(golf.round_state.strokes == 1 and golf.phase == golf.Phase.WALK,"Settled shot records exactly one stroke")
	_check(session.save_game(),"Golf checkpoint saves through the main farm save")
	_check(session.load_game() and session.golf_round.strokes == 1,"Golf checkpoint restores with the rest of the farm")
	_check(not player.golf_locked and not golf.watch_camera,"Loading cannot leave a stuck stance or golf camera")
	var file := FileAccess.open(session.save_path,FileAccess.READ)
	var saved: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var legacy := saved.duplicate(true)
	legacy.version = 3
	legacy.erase("golf")
	legacy.erase("agents")
	legacy.erase("living_world")
	_check(session._valid_save(legacy),"Existing v3 saves remain valid without golf data")
	var invalid := saved.duplicate(true)
	invalid.golf.ball.x = 1000
	_check(not session._valid_save(invalid),"Invalid golf data cannot partially restore a farm")
	player.global_position = golf.ball.position+Vector3.RIGHT
	golf.enter_address()
	_key(KEY_I)
	_check(hud.inventory_ui.visible and not player.golf_locked,"Inventory interrupts a pending swing safely")
	_check(not golf._panel.visible,"Golf HUD immediately yields to a modal inventory")
	hud.close_panels()
	# A stroke limit must never masquerade as a holed ball.
	golf.round_state.strokes = 11
	golf.ball.place(Course.HOLES[0].tee)
	golf.ball.result = "rest"
	golf.phase = golf.Phase.FLIGHT
	golf._settle()
	_check(golf.phase == golf.Phase.WALK and golf.round_state.scores.is_empty() and golf.round_state.strokes == 12,"Twelve strokes without entering the cup do not complete the hole")
	golf._settle()
	_check(golf.round_state.strokes == 12,"Repeated settlement cannot add strokes or finish a hole")
	golf.phase = golf.Phase.FLIGHT
	golf._settle()
	_check(golf.round_state.strokes == 13 and golf.round_state.scores.is_empty(),"Player can continue the same hole beyond twelve strokes")
	_check(session.save_game() and session.load_game() and session.golf_round.strokes == 13 and golf.phase == golf.Phase.WALK,"Unfinished hole beyond twelve strokes saves and restores as playable")
	golf.round_state.strokes = 1
	# Complete all holes through the same physics settlement and transition API.
	for i in Course.HOLES.size():
		cup = Course.HOLES[i].cup
		golf.ball.place(cup+Vector2(0,-.23))
		golf.ball.velocity = Vector3.BACK*.4
		golf.ball.moving = true
		golf.phase = golf.Phase.FLIGHT
		while golf.ball._drop_seconds < 0 and golf.ball.moving:
			golf.ball.advance(1.0/180,cup)
		golf.visual.update_ball(golf.ball.position,true,false)
		golf._settle()
		_check(golf.phase == golf.Phase.FLIGHT and golf.round_state.scores.size() == i and golf.visual.ball_mesh.visible,"Visible cup drop must finish before the round records a completed hole")
		_simulate(golf.ball,cup)
		golf._settle()
		_check(golf.round_state.scores.size() == i+1,"A holed ball appends exactly one hole score")
		if i < Course.HOLES.size()-1:
			_check(not golf.next_hole(),"Next tee cannot be started from the previous green")
			player.global_position = golf.Art.ground(Course.HOLES[i+1].tee)+Vector3.RIGHT
			_check(golf.next_hole(),"Walking to the next tee begins the next hole")
	_check(golf.phase == golf.Phase.FINISHED and not golf.round_state.active and golf.round_state.best == 8,"Seven-hole finish records total score and personal best")
	_check(session.save_game() and session.load_game() and session.golf_round.best == 8,"Best score survives save and reload")
	# R restarts only golf in its own context, including interrupted shots.
	player.global_position = golf.Art.ground(Course.HOLES[2].cup)
	_key(KEY_R)
	_check(golf.phase == golf.Phase.ADDRESS and golf.round_state.hole == 0 and golf.round_state.strokes == 0 and golf.round_state.scores.is_empty(),"R after restoring a finished round starts a fresh first hole")
	_check(player.global_position.distance_to(golf.ball.position) < 1.1 and golf.round_state.best == 8,"Reset brings player to the first ball and preserves the best score")
	golf.begin_swing({"power":.7,"deviation":0.0})
	_key(KEY_R)
	_check(golf.phase == golf.Phase.ADDRESS and golf.shot.is_empty() and not golf.ball.moving,"R cancels a committed swing safely")
	golf.begin_swing({"power":.7,"deviation":0.0})
	golf._impact()
	golf.ball.advance(.1,Course.HOLES[0].cup)
	_key(KEY_R)
	_check(golf.phase == golf.Phase.ADDRESS and not golf.ball.moving and golf.round_state.ball == Course.HOLES[0].tee and golf.ball.result.is_empty(),"R cancels flight and resets the ball to the first tee")
	golf._settle()
	_check(golf.round_state.strokes == 0,"Cancelled flight cannot settle into the restarted round")
	golf.release_control()
	golf.ball.place(Course.HOLES[0].cup+Vector2(0,-.23))
	golf.ball.velocity = Vector3.BACK
	golf.ball.moving = true
	golf.phase = golf.Phase.FLIGHT
	while golf.ball._drop_seconds < 0:
		golf.ball.advance(1.0/180,Course.HOLES[0].cup)
	_key(KEY_R)
	_check(golf.ball._drop_seconds < 0 and golf.round_state.scores.is_empty() and golf.phase == golf.Phase.ADDRESS,"R also cancels a pending cup drop")
	_check(session.save_game() and session.load_game() and session.golf_round.hole == 0 and session.golf_round.strokes == 0 and session.golf_round.best == 8,"Restarted round and preserved best score survive save and reload")
	player.global_position = Vector3.ZERO
	_check(not golf.restart_round(),"Golf restart does not hijack the farm's R key outside the course")
	player.global_position = golf.Art.ground(Course.HOLES[0].tee)
	hud.inventory_ui.show()
	_check(not golf.restart_round(),"Open modal prevents an accidental golf reset")
	hud.close_panels()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(session.save_path))
	farm.queue_free()
	await _frames()
	print("3D GOLF: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL " + str(failures),checks])
	quit(0 if failures.is_empty() else 1)
