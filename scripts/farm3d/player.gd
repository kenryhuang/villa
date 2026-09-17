class_name Farm3DPlayer
extends CharacterBody3D

const SPRINT_MULTIPLIER := 2.0
# Contact travel measured on the retargeted clips; gameplay remains 3 / 6 m/s.
const WALK_REFERENCE_SPEED := 1.73
const RUN_REFERENCE_SPEED := 4.34

@export var walk_speed := 3.0
@export var jump_velocity := 6.0
@export var start_position := Vector3(-2.0, 0.0, 4.0)

var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var camera_yaw := 0.0
var _animation_player: AnimationPlayer
var _has_run_animation := false
var _farm_action_seconds := 0.0
var ui_blocked := false:
	set(value):
		if ui_blocked == value: return
		ui_blocked = value
		_release_movement_input()
var fishing_locked := false:
	set(value):
		if fishing_locked == value: return
		fishing_locked = value
		_release_movement_input()
var golf_locked := false:
	set(value):
		if golf_locked == value: return
		golf_locked = value
		_release_movement_input()
var _dialogue_input_blocked := false
var _input_rearm_actions: Dictionary = {}
var _window_focused := true
const MOVEMENT_ACTIONS := [&"move_left", &"move_right", &"move_forward", &"move_back", &"jump", &"sprint"]

func set_dialogue_input_blocked(blocked: bool) -> void:
	_dialogue_input_blocked = blocked
	_release_movement_input()

func set_window_focused(focused: bool) -> void:
	_window_focused = focused
	_release_movement_input()

func _release_movement_input() -> void:
	velocity = Vector3.ZERO
	_farm_action_seconds = 0
	play_motion_animation(false)
	for action in MOVEMENT_ACTIONS:
		Input.action_release(action)
		_input_rearm_actions[action] = true

func _movement_input_blocked() -> bool:
	if ui_blocked or _dialogue_input_blocked or fishing_locked or golf_locked or not _window_focused: return true
	if not is_inside_tree(): return false
	var focus := get_viewport().gui_get_focus_owner()
	return get_tree().paused or focus is LineEdit or focus is TextEdit

func _movement_action_strength(action: StringName) -> float:
	if _movement_input_blocked() or _input_rearm_actions.has(action): return 0.0
	return Input.get_action_strength(action)

func get_movement_input() -> Vector2:
	return Vector2(
		_movement_action_strength(&"move_right") - _movement_action_strength(&"move_left"),
		_movement_action_strength(&"move_back") - _movement_action_strength(&"move_forward")
	).limit_length(1.0)

func filter_dialogue_input(event: InputEvent) -> void:
	# Releasing gameplay actions must not consume TextEdit's event.
	# Golf owns these same direction actions for aiming while the body is locked.
	if (fishing_locked or golf_locked) and not ui_blocked and not _dialogue_input_blocked and _window_focused: return
	for action in MOVEMENT_ACTIONS:
		if not event.is_action(action):
			continue
		if not _movement_input_blocked() and event.is_pressed() and not (event is InputEventKey and event.echo):
			_input_rearm_actions.erase(action)
		elif _movement_input_blocked() or _input_rearm_actions.has(action):
			Input.action_release(action)
			_input_rearm_actions[action] = true

func _input(event: InputEvent) -> void:
	filter_dialogue_input(event)

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 16
	_animation_player = _find_animation_player(self)
	if _animation_player != null:
		for animation_name in _animation_player.get_animation_list():
			if String(animation_name).get_file().to_lower() == "run":
				_has_run_animation = true
			if String(animation_name).get_file().to_lower() in ["idle", "walk", "run"]:
				_animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	play_motion_animation(false)

func _physics_process(delta: float) -> void:
	_farm_action_seconds = maxf(0.0, _farm_action_seconds - delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	if _movement_action_strength(&"jump") > 0 and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	var input_vector := get_movement_input()
	if ui_blocked or _dialogue_input_blocked or fishing_locked or golf_locked or _farm_action_seconds > 0.0:
		input_vector = Vector2.ZERO
	var direction := Vector3(input_vector.x, 0.0, input_vector.y).rotated(Vector3.UP, camera_yaw)
	var speed := walk_speed * (SPRINT_MULTIPLIER if _movement_action_strength(&"sprint") > 0 else 1.0)
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
	var moving := get_movement_input().length_squared() > 0.001
	play_motion_animation(moving)

func play_motion_animation(is_walking: bool) -> void:
	if _animation_player == null or fishing_locked or golf_locked:
		return
	# The half-second farm action uses one complete work swing.
	var working := _farm_action_seconds > 0.0 and not is_walking
	var sprinting := is_walking and _movement_action_strength(&"sprint") > 0
	var travel_speed := walk_speed * (SPRINT_MULTIPLIER if sprinting else 1.0)
	if Farm3DTerrainProfile.is_water(global_position.x,global_position.z) and global_position.y < Farm3DTerrainProfile.WATER_HEIGHT:
		travel_speed *= 0.6
	var stride_speed := RUN_REFERENCE_SPEED if sprinting and _has_run_animation else WALK_REFERENCE_SPEED
	_animation_player.speed_scale = 2.0 if working else travel_speed / stride_speed if is_walking else 1.0
	var preferred := "Work" if working else "Run" if sprinting and _has_run_animation else "Walk" if is_walking else "Idle"
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
