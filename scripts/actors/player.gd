class_name PlayerController
extends CharacterBody3D

signal fire_requested(origin: Vector3, direction: Vector3)
signal health_changed(value: int)

const CombatMathScript = preload("res://scripts/shared/combat_math.gd")

@export var speed := 4.5
@export var jump_velocity := 5.2
@export var fire_cooldown := 0.28

var health := 5
var camera_rig
var game_world
var cooldown_remaining := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

static func movement_from_input(input_vector: Vector2, camera_forward: Vector3, camera_right: Vector3) -> Vector3:
	var direction := camera_right * input_vector.x + camera_forward * -input_vector.y
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 1.0 else direction

func configure(new_camera_rig: Node, new_world: Node) -> void:
	camera_rig = new_camera_rig
	game_world = new_world

func _physics_process(delta: float) -> void:
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3.ZERO
	if camera_rig:
		direction = movement_from_input(input_vector, camera_rig.get_planar_forward(), camera_rig.get_planar_right())
	velocity.x = move_toward(velocity.x, direction.x * speed, speed * 8.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, speed * 8.0 * delta)
	if direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 1.0 - exp(-12.0 * delta))
	move_and_slide()
	_clamp_to_world()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_request_fire()

func take_damage(amount: int) -> void:
	var next_health := CombatMathScript.apply_damage(health, amount)
	if next_health == health:
		return
	health = next_health
	health_changed.emit(health)

func _request_fire() -> void:
	if cooldown_remaining > 0.0 or not is_inside_tree():
		return
	var active_camera := get_viewport().get_camera_3d()
	if active_camera == null:
		return
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := active_camera.project_ray_origin(mouse_position)
	var ray_direction := active_camera.project_ray_normal(mouse_position)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 200.0, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target_point: Variant = hit.get("position") if not hit.is_empty() else Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_direction)
	if target_point == null:
		return
	var origin := global_position + Vector3.UP * 0.65
	var direction := Vector3(target_point.x - origin.x, 0.0, target_point.z - origin.z).normalized()
	if direction.length_squared() < 0.001:
		return
	cooldown_remaining = fire_cooldown
	fire_requested.emit(origin, direction)

func _clamp_to_world() -> void:
	if game_world == null:
		return
	var bounds: Rect2 = game_world.get_bounds()
	global_position.x = clampf(global_position.x, bounds.position.x, bounds.end.x)
	global_position.z = clampf(global_position.z, bounds.position.y, bounds.end.y)
