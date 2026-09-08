extends SceneTree

const Course = preload("res://scripts/farm3d/golf_course_data.gd")
const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const Ball = preload("res://scripts/farm3d/golf_ball.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _roll(point: Vector2, velocity: Vector3) -> Farm3DGolfBall:
	var ball := Ball.new()
	ball.place(point)
	ball.velocity = velocity
	ball.moving = true
	return ball

func _advance(ball: Farm3DGolfBall, seconds: float, cup := Vector2.ZERO, dt := 1.0/60) -> void:
	for i in ceili(seconds/dt):
		ball.advance(dt,cup)

func _run() -> void:
	for hole in Course.HOLES:
		var low := INF
		var high := -INF
		for i in 41:
			var p: Vector2 = hole.tee.lerp(hole.cup,float(i)/40)
			var h := Profile.surface_height(p.x,p.y)
			low = minf(low,h)
			high = maxf(high,h)
		_check(high-low < .4 if hole == Course.HOLES[0] else high-low > .2,"First hole is gentle while later routes offer elevation and hazards: "+hole.name)
		_check(Profile.slope_at(hole.tee.x,hole.tee.y) < .01,"Tee remains level: "+hole.name)
		_check(Profile.slope_at(hole.cup.x,hole.cup.y) < .01,"Cup has a stable level collar: "+hole.name)
		for heading in 8:
			var direction := Vector3.BACK.rotated(Vector3.UP,heading*TAU/8)
			for speed in [.4,2.5,4.0,6.0,12.0,30.0]:
				for dt in [1.0/10,1.0/30,1.0/144]:
					var start: Vector2 = hole.cup-Vector2(direction.x,direction.z)*(.28 if speed < 1 else .5)
					var ball := _roll(start,direction*speed)
					_advance(ball,1.5,hole.cup,dt)
					_check(ball.result == "holed","Ground-level crossing enters cup %s heading %d speed %.1f dt %.4f" % [hole.name,heading,speed,dt])
		var cup: Vector2 = hole.cup
		var edge := _roll(cup+Vector2(.178,-.5),Vector3.BACK*3)
		_advance(edge,.8,cup)
		_check(edge.result == "holed","Visible inner edge of cup captures a moderate putt")
		var miss := _roll(cup+Vector2(.24,-.5),Vector3.BACK*3)
		_advance(miss,.3,cup)
		_check(miss.result != "holed","Near miss outside cup is not pulled in")
		var fast := _roll(cup+Vector2(0,-.5),Vector3.BACK*6)
		_advance(fast,.2,cup)
		_check(fast._drop_seconds >= 0 and fast.moving,"Fast grounded crossing starts the visible cup drop")
		_advance(fast,.5,cup)
		_check(fast.result == "holed","Fast grounded crossing completes the hole after the drop")
		var fast_edge := _roll(cup+Vector2(.178,-.5),Vector3.BACK*30)
		_advance(fast_edge,.8,cup)
		_check(fast_edge.result == "holed","Fast crossing at the visible inner edge also counts")
		var low_flying := _roll(cup+Vector2(0,-.5),Vector3.BACK*30)
		low_flying.position.y += .04
		_advance(low_flying,.05,cup)
		_check(low_flying._drop_seconds < 0,"Airborne crossing just above the ground is not pulled into the cup")
		var flying := _roll(cup+Vector2(0,-.5),Vector3.BACK*3)
		flying.position.y += .6
		_advance(flying,.25,cup)
		_check(flying.result != "holed","Airborne ball above the cup is not captured")
		var swept := _roll(cup+Vector2(0,-.22),Vector3.BACK*4)
		swept._step(.12,cup,null)
		_check(swept.moving and swept.result.is_empty(),"Cup entry starts a visible drop without reporting a completed hole")
		var entry_y: float = swept.position.y
		swept.advance(.1,cup)
		_check(swept.position.y < entry_y and swept.moving and swept.result.is_empty(),"Ball descends visibly before the hole is completed")
		_advance(swept,.5,cup)
		_check(swept.result == "holed","Swept path detects crossing even when both endpoints lie outside cup")
	for i in 1:
		var cup: Vector2 = Course.HOLES[i].cup
		var approach: Vector2 = (Course.HOLES[i].tee-cup).normalized()
		var approach_slope := 0.0
		for step in 32:
			var p := cup+approach*float(step)*.25
			approach_slope = maxf(approach_slope,Profile.slope_at(p.x,p.y))
		_check(approach_slope < .08,"Approach to the first two greens has no raised platform lip")
	var side_cup: Vector2 = Course.HOLES[1].cup
	_check(Profile.surface_height(side_cup.x,side_cup.y+3)-Profile.surface_height(side_cup.x,side_cup.y-3) > .25,"Second green uses a continuous cross slope")
	var slope := Vector2(-132,17)
	var normal := Profile.surface_normal(slope.x,slope.y)
	var downhill := Vector3.DOWN.slide(normal).normalized()
	var uphill := _roll(slope,-downhill*.4)
	_advance(uphill,1)
	_check(uphill.moving and uphill.velocity.dot(downhill) > .4,"An uphill ball slows, reverses and rolls back instead of freezing at its turning point")
	var descending := _roll(slope,downhill)
	_advance(descending,.5)
	_check(descending.velocity.length() > 1.2,"Gravity accelerates a downhill ball")
	var across := normal.cross(Vector3.UP).normalized()
	var breaking := _roll(slope,across*2)
	_advance(breaking,.6)
	_check(breaking.velocity.dot(downhill) > .5,"A cross-slope shot curves downhill")
	_check(absf(breaking.position.y-Profile.surface_height(breaking.position.x,breaking.position.z)-Ball.RADIUS) < .001,"Rolling ball follows the rendered terrain surface")
	var uphill_fast := _roll(slope,-downhill*3)
	uphill_fast.advance(.05,Vector2.ZERO)
	_check(not uphill_fast.bounced and uphill_fast.velocity.y > .25 and absf(uphill_fast.position.y-Profile.surface_height(uphill_fast.position.x,uphill_fast.position.z)-Ball.RADIUS) < .001,"Fast uphill rolling is not mistaken for airborne motion")
	var putt := Ball.new()
	putt.place(slope)
	putt.strike(Vector3(-downhill.x,0,-downhill.z),.8,2,0)
	putt.advance(.05,Vector2.ZERO)
	_check(not putt.bounced and putt.velocity.y > .25,"Putting from a slope starts tangent to the ground without a false landing bounce")
	var deceleration: Array[float] = []
	var points := [Course.HOLES[0].cup+Vector2(1,0),Course.HOLES[0].tee,Vector2(-159,95),Vector2(Course.BUNKERS[0].x,Course.BUNKERS[0].y)]
	for i in points.size():
		var p: Vector2 = points[i]
		var n := Profile.surface_normal(p.x,p.y)
		var tangent := n.cross(Vector3.UP).normalized() if n.y < .999999 else Vector3.RIGHT
		var ball := _roll(p,tangent*2)
		ball._step(.001,Vector2.ZERO,null)
		deceleration.append((2-ball.velocity.dot(tangent))/.001)
		_check(Course.surface(p) == ["green","fairway","rough","sand"][i],"Material sample lies on the intended surface")
	_check(deceleration[0] < deceleration[1] and deceleration[1] < deceleration[2] and deceleration[2] < deceleration[3],"Measured rolling resistance increases from green to fairway to rough to sand")
	var slope_max := 0.0
	var steepest := Vector2.ZERO
	for x in range(-161,-86,2):
		for z in range(-69,134,2):
			var gradient := Profile.slope_at(x,z)
			if gradient > slope_max:
				slope_max = gradient
				steepest = Vector2(x,z)
	_check(slope_max < 1.25,"Course hills remain walkable and avoid abrupt cliffs")
	print("3D GOLF TERRAIN: %s (%d checks, max slope %.3f at %s)" % ["PASS" if failures.is_empty() else "FAIL "+str(failures),checks,slope_max,steepest])
	quit(0 if failures.is_empty() else 1)
