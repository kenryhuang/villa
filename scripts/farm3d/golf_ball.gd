class_name Farm3DGolfBall
extends RefCounted

const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const Course = preload("res://scripts/farm3d/golf_course_data.gd")
const RADIUS := .065
const CUP_DROP_TIME := .4
const CLUBS := [
	{"name":"开球杆","speed":20.0,"angle":28.0},
	{"name":"挖起杆","speed":13.0,"angle":55.0},
	{"name":"推杆","speed":3.5,"angle":0.0},
]
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var moving := false
var elapsed := 0.0
var result := ""
var bounced := false
var side_spin := 0.0
var obstacle_hits := 0
var _drop_seconds := -1.0
var _drop_from := Vector3.ZERO
var _drop_target := Vector3.ZERO

func place(point: Vector2) -> void:
	position = Vector3(point.x,Profile.surface_height(point.x,point.y)+RADIUS,point.y)
	velocity = Vector3.ZERO
	moving = false
	elapsed = 0
	result = ""
	bounced = false
	side_spin = 0
	obstacle_hits = 0
	_drop_seconds = -1

func strike(direction: Vector3, power: float, club: int, contact_height := -2.0, contact_side := 0.0) -> void:
	velocity = launch_velocity(direction,power,club,Course.surface(Vector2(position.x,position.z)),contact_height)
	side_spin = clampf(contact_side,-1,1)*.55 if velocity.y > .01 else 0.0
	obstacle_hits = 0
	if absf(velocity.y) < .01:
		var speed := velocity.length()
		velocity = velocity.slide(Profile.surface_normal(position.x,position.z)).normalized()*speed
	moving = true
	elapsed = 0
	result = ""
	bounced = false
	_drop_seconds = -1

static func launch_velocity(direction: Vector3, power: float, club: int, surface_name := "fairway", contact_height := -2.0) -> Vector3:
	var data: Dictionary = CLUBS[clampi(club,0,2)]
	var penalty := .65 if surface_name == "sand" and club != 1 else .85 if surface_name == "rough" and club == 0 else 1.0
	var speed := float(data.speed) * sqrt(clampf(power,.01,1)) * penalty
	var angle := deg_to_rad(float(data.angle))
	if contact_height >= -1.0:
		var below := clampf(-contact_height,0,1)
		var lift := smoothstep(.04,.45,power)
		angle = deg_to_rad(minf(65,maxf(18,float(data.angle))*below/.6))*lift
		var ground_speed := minf(float(data.speed),5.0)
		speed = lerpf(ground_speed,float(data.speed),smoothstep(0,.25,below)*lift)*sqrt(clampf(power,.01,1))*penalty
	return direction.normalized()*cos(angle)*speed + Vector3.UP*sin(angle)*speed

## A partial guide, using the same slope, friction and bounce integration as play.
## Stop at the first landing or 1.2 seconds of rolling; never predict a made putt.
static func preview_path(origin: Vector3, direction: Vector3, power: float, club: int, contact_height: float, contact_side := 0.0, space: PhysicsDirectSpaceState3D = null) -> PackedVector3Array:
	var preview := Farm3DGolfBall.new()
	preview.place(Vector2(origin.x,origin.z))
	preview.strike(direction,power,club,contact_height,contact_side)
	var airborne := preview.velocity.dot(Profile.surface_normal(origin.x,origin.z)) > .3
	var points := PackedVector3Array([preview.position])
	for frame in (300 if airborne else 72):
		preview.advance(1.0/60,Vector2.ZERO,space)
		points.append(preview.position)
		if not preview.moving or (airborne and preview.bounced):
			break
	return points

func advance(delta: float, cup: Vector2, space: PhysicsDirectSpaceState3D = null) -> void:
	if not moving or delta <= 0 or not is_finite(delta):
		return
	var remaining := minf(delta,.1)
	while remaining > .00001 and moving:
		var dt := minf(remaining,1.0/180.0)
		remaining -= dt
		_step(dt,cup,space)

func _step(dt: float, cup: Vector2, space: PhysicsDirectSpaceState3D) -> void:
	if _drop_seconds >= 0:
		_drop_seconds += dt
		var t := clampf(_drop_seconds/CUP_DROP_TIME,0,1)
		position = _drop_from.lerp(_drop_target,smoothstep(0,1,t))
		if t >= 1:
			_stop("holed")
		return
	elapsed += dt
	var point := Vector2(position.x,position.z)
	if not Course.BOUNDS.grow(3).has_point(point) or (Profile.is_water(point.x,point.y) and position.y <= Profile.WATER_HEIGHT+RADIUS):
		_stop("penalty")
		return
	var ground := Profile.surface_height(point.x,point.y)+RADIUS
	var normal := Profile.surface_normal(point.x,point.y)
	var old := position
	# Test speed away from the slope, not vertical speed: uphill rolling has
	# a positive Y velocity and must remain attached to the ground.
	var rolling := position.y <= ground+.012 and absf(velocity.dot(normal)) <= .3
	if rolling:
		velocity = velocity.slide(normal)
		var gravity := Vector3.DOWN.slide(normal)*9.8
		velocity += gravity*dt
		var friction: float = Course.ROLLING_RESISTANCE[Course.surface(point)]*normal.y
		velocity = velocity.move_toward(Vector3.ZERO,friction*dt)
		position += velocity*dt
		position.y = Profile.surface_height(position.x,position.z)+RADIUS
		# Low speed on a steep slope is a turning point, not a resting ball.
		if velocity.length() < .055 and gravity.length() <= friction:
			_stop("rest")
	else:
		# Gameplay approximation of spin-axis lift: curve only while airborne.
		velocity = velocity.rotated(Vector3.UP,-side_spin*dt)
		side_spin *= exp(-.22*dt)
		velocity.y -= 9.8*dt
		position += velocity*dt
		var floor_height := Profile.surface_height(position.x,position.z)+RADIUS
		if position.y < floor_height:
			position.y = floor_height
			var softness := .12 if Course.surface(Vector2(position.x,position.z)) == "sand" else .30
			velocity.y = -velocity.y*softness if velocity.y < -.7 else 0.0
			velocity.x *= .78
			velocity.z *= .78
			bounced = true
			side_spin *= .35
	if space != null and position.distance_squared_to(old) > .000001:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(old,position,1|4|16))
		if not hit.is_empty() and (hit.normal.y < .55 or hit.collider.has_meta("golf_obstacle")) and velocity.dot(hit.normal) < 0:
			position = hit.position+hit.normal*RADIUS
			velocity = velocity.bounce(hit.normal)*.4
			side_spin *= .25
			obstacle_hits += 1
	if rolling and _capture_cup(old,position,cup):
		return
	if elapsed > 30:
		_stop("rest")

func _capture_cup(from: Vector3, to: Vector3, cup: Vector2) -> bool:
	# Any grounded crossing counts, regardless of speed. Sweep the whole path
	# so a fast ball cannot skip the cup between two simulation samples.
	var a := Vector2(from.x,from.z)
	var b := Vector2(to.x,to.z)
	var segment := b-a
	var t := clampf((cup-a).dot(segment)/segment.length_squared(),0,1) if segment.length_squared() > .00000001 else 0.0
	var nearest := a.lerp(b,t)
	if nearest.distance_to(cup) > Course.CUP_RADIUS:
		return false
	var gap := from.lerp(to,t).y-Profile.surface_height(nearest.x,nearest.y)-RADIUS
	if absf(gap) > .035:
		return false
	# Show the ball entering the cup before reporting completion to the round.
	_drop_from = from.lerp(to,t)
	_drop_target = Vector3(cup.x,Profile.surface_height(cup.x,cup.y)-.20,cup.y)
	position = _drop_from
	_drop_seconds = 0
	velocity = Vector3.ZERO
	moving = true
	result = ""
	return true

func _stop(reason: String) -> void:
	moving = false
	velocity = Vector3.ZERO
	result = reason
