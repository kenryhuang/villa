extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var farm = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	var golf = farm.farm_session.golf
	var player: Farm3DPlayer = farm.player
	player.set_physics_process(false)
	farm.farm_session.season.set_process(false)
	golf.set_process(false)
	player.global_position = golf.Art.ground(golf.Course.ENTRANCE)+Vector3.BACK*2
	golf.start_round()
	player.global_position = golf.ball.position+Vector3.RIGHT
	golf.enter_address()
	var skeleton: Skeleton3D = golf.visual._skeleton
	check(skeleton != null, "Player has the actual animated skeleton")
	for handed in [false,true]:
		golf.left_handed = handed
		golf._stance()
		golf.visual.set_contact(golf.ball.position,golf.direction,golf.contact_height)
		golf.visual.pose(0,0)
		var hand := skeleton.find_bone("hand.R" if handed else "hand.L")
		var neutral := skeleton.get_bone_global_pose(hand).origin
		var shaft_length: float = golf.visual.shaft.scale.y
		check(golf.visual._head_point.distance_to(golf.ball.position) < .08,"Club contacts ball at impact in either stance")
		golf.visual.pose(.3,0)
		var small := skeleton.get_bone_global_pose(hand).origin
		golf.visual.pose(2.6,0)
		var full := skeleton.get_bone_global_pose(hand).origin
		check(full.distance_to(neutral) > small.distance_to(neutral)+.2,"Full power visibly raises arms further than a tap")
		check(absf(golf.visual.shaft.scale.y-shaft_length) < .001,"Shaft stays rigid through backswing")
		golf.visual.pose(-2.1,0)
		var finish := skeleton.get_bone_global_pose(hand).origin
		check(finish.distance_to(full) > .35,"Hands move through the ball to the opposite side")
		golf.visual.pose(2.6,0)
		check(skeleton.get_bone_global_pose(hand).origin.distance_to(full) < .001,"Repeated poses do not accumulate skeleton rotation")
		golf.visual.pose(0,0)
		check(skeleton.get_bone_global_pose(hand).origin.distance_to(neutral) < .001,"Recover restores the address pose")
	for club_index in [0,2]:
		var previous_follow := 0.0
		for strength in [.15,.5,1.0]:
			golf.phase = golf.Phase.ADDRESS
			golf.club = club_index
			golf.contact_height = 0 if club_index == 2 else -.6
			golf.visual.set_equipped(true)
			check(golf.begin_swing({"power":strength,"deviation":0.0}),"Shot starts")
			check(golf.shot.followthrough > previous_follow,"Follow-through increases with power")
			previous_follow = golf.shot.followthrough
			if club_index == 2:
				check(golf.shot.followthrough <= .65,"Putter retains compact pendulum motion")
			golf._process(float(golf.shot.impact_delay)*.5)
			check(not golf.ball.moving and golf.phase == golf.Phase.SWING,"Ball waits for club impact")
			golf._process(float(golf.shot.impact_delay)*.5+.001)
			check(golf.ball.moving and golf.phase == golf.Phase.FLIGHT,"Impact launches the ball")
			# A very short shot must still finish its follow-through before unlocking.
			golf.ball.moving = false
			golf.ball.result = "rest"
			golf._process(.01)
			check(golf.phase == golf.Phase.FLIGHT and player.golf_locked,"Early landing does not cut off follow-through")
			golf._process(2)
			check(golf.phase == golf.Phase.WALK and not player.golf_locked and not golf.visual._equipped,"Completed shot restores locomotion and removes club")
			check(player._animation_player.is_playing(),"Idle animation resumes after golf")
			player.global_position = golf.ball.position+Vector3.RIGHT
			golf.enter_address()
	golf.release_control()
	farm.free()
	print("GOLF ANIMATION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
