class_name VillaNpc
extends CharacterBody3D

signal defeated(npc: Node)

const CombatMathScript = preload("res://scripts/shared/combat_math.gd")

@export var speed := 1.4
@export var max_health := 3
@export var contact_damage := 1

var health := 3
var target: Node3D
var knockback_velocity := Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _is_defeated := false
var _hit_flash_remaining := 0.0
var _contact_cooldown := 0.0

@onready var mesh: MeshInstance3D = get_node_or_null("Mesh")

func _ready() -> void:
	health = max_health
	if mesh and mesh.mesh and mesh.mesh.get_surface_count() > 0:
		var base_material := mesh.mesh.surface_get_material(0) as StandardMaterial3D
		if base_material:
			mesh.material_override = base_material.duplicate()

func configure(new_target: Node3D) -> void:
	target = new_target

func _physics_process(delta: float) -> void:
	if _is_defeated:
		return
	_contact_cooldown = maxf(0.0, _contact_cooldown - delta)
	_hit_flash_remaining = maxf(0.0, _hit_flash_remaining - delta)
	_update_hit_flash()
	if not is_on_floor():
		velocity.y -= gravity * delta
	var chase_direction := Vector3.ZERO
	if is_instance_valid(target):
		chase_direction = target.global_position - global_position
		chase_direction.y = 0.0
		if chase_direction.length_squared() > 0.01:
			chase_direction = chase_direction.normalized()
	velocity.x = chase_direction.x * speed + knockback_velocity.x
	velocity.z = chase_direction.z * speed + knockback_velocity.z
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 10.0 * delta)
	if chase_direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(chase_direction.x, chase_direction.z), 1.0 - exp(-8.0 * delta))
	move_and_slide()
	_try_contact_damage()

func take_hit(amount: int, impact_direction := Vector3.ZERO) -> void:
	if _is_defeated:
		return
	health = CombatMathScript.apply_damage(health, amount)
	knockback_velocity += impact_direction.normalized() * 3.6
	_hit_flash_remaining = 0.12
	if health == 0:
		_is_defeated = true
		defeated.emit(self)
		if is_inside_tree():
			queue_free()

func _try_contact_damage() -> void:
	if _contact_cooldown > 0.0 or not is_instance_valid(target):
		return
	var horizontal_distance := Vector2(global_position.x - target.global_position.x, global_position.z - target.global_position.z).length()
	if horizontal_distance < 0.85 and target.has_method("take_damage"):
		target.take_damage(contact_damage)
		_contact_cooldown = 0.8

func _update_hit_flash() -> void:
	if mesh == null or not mesh.material_override is StandardMaterial3D:
		return
	var material := mesh.material_override as StandardMaterial3D
	material.albedo_color = Color.WHITE if _hit_flash_remaining > 0.0 else Color(1.0, 0.16, 0.08)
