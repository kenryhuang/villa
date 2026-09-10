class_name Farm3DPlayer
extends CharacterBody3D

const SPRINT_MULTIPLIER := 2.5

@export var walk_speed := 4.2
@export var jump_velocity := 6.0
@export var start_position := Vector3(-2.0, 0.0, 4.0)

var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var camera_yaw := 0.0
var _animation_player: AnimationPlayer
var _farm_action_seconds := 0.0
var ui_blocked := false
var fishing_locked := false
var golf_locked := false
var _dialogue_input_blocked := false
var _input_rearm_actions: Dictionary = {}
const MOVEMENT_ACTIONS := [&"move_left", &"move_right", &"move_forward", &"move_back", &"jump", &"sprint"]

func set_dialogue_input_blocked(blocked: bool) -> void:
	_dialogue_input_blocked = blocked
	velocity = Vector3.ZERO
	_farm_action_seconds = 0
	play_motion_animation(false)
	for action in MOVEMENT_ACTIONS:
		Input.action_release(action)
		_input_rearm_actions[action] = true

func filter_dialogue_input(event: InputEvent) -> void:
	# Releasing gameplay actions must not consume TextEdit's event.
	for action in MOVEMENT_ACTIONS:
		if not event.is_action(action):
			continue
		if not _dialogue_input_blocked and event.is_pressed() and not (event is InputEventKey and event.echo):
			_input_rearm_actions.erase(action)
		elif _dialogue_input_blocked or _input_rearm_actions.has(action):
			Input.action_release(action)

func _input(event: InputEvent) -> void:
	filter_dialogue_input(event)

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
	if not ui_blocked and not _dialogue_input_blocked and not fishing_locked and not golf_locked and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if ui_blocked or _dialogue_input_blocked or fishing_locked or golf_locked or _farm_action_seconds > 0.0:
		input_vector = Vector2.ZERO
	var direction := Vector3(input_vector.x, 0.0, input_vector.y).rotated(Vector3.UP, camera_yaw)
	var speed := walk_speed * (SPRINT_MULTIPLIER if Input.is_action_pressed("sprint") else 1.0)
	if Farm3DTerrainProfile.is_water(global_position.x,global_position.z) and global_position.y < Farm3DTerrainProfile.WATER_HEIGHT:
		speed *= 0.6
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if direction.length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP, true)
	play_motion_animation(direction.length_squared() > 0.001)
	move_and_slide()
	if global_position.y < -8.0 or not Farm3DTerrainProfile.is_in_world(global_position.x, global_position.z, 1.0):
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
	play_motion_animation(false)
	if _animation_player != null and not fishing_locked and not golf_locked and String(_animation_player.current_animation).get_file().to_lower() == "work":
		_animation_player.seek(0.0, true)

func cancel_farm_action() -> void:
	_farm_action_seconds = 0.0
	var moving := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length_squared() > 0.001
	play_motion_animation(moving)

func play_motion_animation(is_walking: bool) -> void:
	if _animation_player == null or fishing_locked or golf_locked:
		return
	# The half-second farm action uses one complete work swing.
	var working := _farm_action_seconds > 0.0 and not is_walking
	_animation_player.speed_scale = 2.0 if working else SPRINT_MULTIPLIER if is_walking and Input.is_action_pressed("sprint") else 1.0
	var preferred := "Work" if working else "Walk" if is_walking else "Idle"
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
