class_name VillaProjectile
extends Area3D

@export var speed := 10.0
@export var damage := 1
@export var lifetime := 2.0

var direction := Vector3.FORWARD
var age := 0.0

static func is_expired(current_age: float, max_lifetime: float) -> bool:
	return current_age >= max_lifetime

static func safe_direction(value: Vector3) -> Vector3:
	return value.normalized() if value.length_squared() > 0.0001 else Vector3.FORWARD

func configure(origin: Vector3, travel_direction: Vector3) -> void:
	global_position = origin
	direction = safe_direction(travel_direction)

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	age += delta
	if is_expired(age, lifetime):
		queue_free()
		return
	global_position += direction * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.has_method("take_hit"):
		body.take_hit(damage, direction)
	queue_free()
