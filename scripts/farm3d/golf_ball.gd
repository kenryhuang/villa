class_name Farm3DGolfBall
extends RefCounted

const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const Course = preload("res://scripts/farm3d/golf_course_data.gd")
const RADIUS := .065
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

func place(point: Vector2) -> void:
	position = Vector3(point.x,Profile.surface_height(point.x,point.y)+RADIUS,point.y)
	velocity = Vector3.ZERO
	moving = false
	elapsed = 0
	result = ""
	bounced = false

func strike(direction: Vector3, power: float, club: int, contact_height := -2.0) -> void:
	velocity = launch_velocity(direction,power,club,Course.surface(Vector2(position.x,position.z)),contact_height)
	if absf(velocity.y) < .01:
		var speed := velocity.length()
		velocity = velocity.slide(Profile.surface_normal(position.x,position.z)).normalized()*speed
	moving = true
	elapsed = 0
	result = ""
	bounced = false

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

func advance(delta: float, cup: Vector2, space: PhysicsDirectSpaceState3D = null) -> void:
	if not moving or delta <= 0 or not is_finite(delta):
		return
	var remaining := minf(delta,.1)
	while remaining > .00001 and moving:
		var dt := minf(remaining,1.0/180.0)
		remaining -= dt
		_step(dt,cup,space)

func _step(dt: float, cup: Vector2, space: PhysicsDirectSpaceState3D) -> void:
	elapsed += dt
	var point := Vector2(position.x,position.z)
	if not Course.BOUNDS.grow(3).has_point(point) or Profile.is_water(point.x,point.y):
		_stop("penalty")
		return
	var ground := Profile.surface_height(point.x,point.y)+RADIUS
	var normal := Profile.surface_normal(point.x,point.y)
	var old := position
	var old_speed := velocity.length()
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
	if space != null and position.distance_squared_to(old) > .000001:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(old,position,1|16))
		if not hit.is_empty() and hit.normal.y < .55:
			position = hit.position+hit.normal*RADIUS
			velocity = velocity.bounce(hit.normal)*.4
	if rolling and _capture_cup(old,position,cup,maxf(old_speed,velocity.length())):
		return
	if elapsed > 30:
		_stop("rest")

func _capture_cup(from: Vector3, to: Vector3, cup: Vector2, speed: float) -> bool:
	if speed > Course.CUP_CAPTURE_SPEED:
		return false
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
	position = Vector3(cup.x,Profile.surface_height(cup.x,cup.y)-.20,cup.y)
	_stop("holed")
	return true

func _stop(reason: String) -> void:
	moving = false
	velocity = Vector3.ZERO
	result = reason
