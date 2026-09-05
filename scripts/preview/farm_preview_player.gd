class_name FarmPreviewPlayer
extends CharacterBody3D

@export var walk_speed := 4.2
@export var sprint_speed := 7.0
@export var jump_velocity := 6.0
@export var start_position := Vector3(-2.0, 0.0, 4.0)

var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var camera_yaw := 0.0
var _animation_player: AnimationPlayer
var _farm_action_seconds := 0.0
var ui_blocked := false

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 16
	_animation_player = _find_animation_player(self)
	if _animation_player != null:
		for animation_name in _animation_player.get_animation_list():
			if String(animation_name).get_file().to_lower() in ["idle", "walk"]:
				_animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	play_motion_animation(false)

func _physics_process(delta: float) -> void:
	_farm_action_seconds = maxf(0.0, _farm_action_seconds - delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	if not ui_blocked and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if ui_blocked or _farm_action_seconds > 0.0:
		input_vector = Vector2.ZERO
	var direction := Vector3(input_vector.x, 0.0, input_vector.y).rotated(Vector3.UP, camera_yaw)
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if direction.length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP, true)
	play_motion_animation(direction.length_squared() > 0.001)
	move_and_slide()
	if global_position.y < -8.0:
		reset_position()

func reset_position() -> void:
	global_position = start_position
	velocity = Vector3.ZERO
	_farm_action_seconds = 0.0

func begin_farm_action(point: Vector3) -> void:
	_farm_action_seconds = 0.5
	var target := Vector3(point.x, global_position.y, point.z)
	if global_position.distance_squared_to(target) > 0.01:
		look_at(target, Vector3.UP, true)
	velocity.x = 0.0
	velocity.z = 0.0

func cancel_farm_action() -> void:
	_farm_action_seconds = 0.0
	var moving := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length_squared() > 0.001
	play_motion_animation(moving)

func play_motion_animation(is_walking: bool) -> void:
	if _animation_player == null:
		return
	var preferred := "Walk" if is_walking else "Idle"
	for animation_name in _animation_player.get_animation_list():
		if String(animation_name).get_file().to_lower() == preferred.to_lower():
			if _animation_player.current_animation != animation_name:
				_animation_player.play(animation_name, 0.16)
			return

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
