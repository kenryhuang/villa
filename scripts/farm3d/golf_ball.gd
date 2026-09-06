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

func strike(direction: Vector3, power: float, club: int, contact_height := -2.0) -> void:
	velocity = launch_velocity(direction,power,club,Course.surface(Vector2(position.x,position.z)),contact_height)
	moving = true
	elapsed = 0
	result = ""

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
	if point.distance_to(cup) < Course.CUP_RADIUS-RADIUS*.4 and position.y < ground+.10 and velocity.length() < 2.3:
		position = Vector3(cup.x,Profile.surface_height(cup.x,cup.y)-.20,cup.y)
		_stop("holed")
		return
	var old := position
	if position.y <= ground+.012 and velocity.y <= .25:
		var normal := Vector3(Profile.surface_height(point.x-.15,point.y)-Profile.surface_height(point.x+.15,point.y),.30,Profile.surface_height(point.x,point.y-.15)-Profile.surface_height(point.x,point.y+.15)).normalized()
		velocity = velocity.slide(normal)
		velocity += Vector3.DOWN.slide(normal)*9.8*dt
		var friction: float = {"green":.30,"fairway":.8,"rough":2.2,"sand":4.5}[Course.surface(point)]
		velocity = velocity.move_toward(Vector3.ZERO,friction*dt)
		position += velocity*dt
		position.y = Profile.surface_height(position.x,position.z)+RADIUS
		if velocity.length() < .055:
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
	if elapsed > 30:
		_stop("rest")

func _stop(reason: String) -> void:
	moving = false
	velocity = Vector3.ZERO
	result = reason
