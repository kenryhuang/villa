class_name PlayerController
extends CharacterBody3D

## 玩家控制器 - 农庄模式
## 移动、工具使用、交互、体力系统

signal stamina_changed(value: int)
signal tool_changed(tool_type: int)
signal manual_movement_requested
signal auto_path_finished
signal auto_path_blocked

@export var speed := 4.5
@export var sprint_speed := 7.0
@export var jump_velocity := 5.2
@export var interaction_range := 2.5

var camera_rig
var game_world
var tool_system: ToolSystem
var grid_system: GridSystem
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

var _is_sprinting := false
var _stamina_regen_timer := 0.0
const STAMINA_REGEN_RATE := 1.0  # 每秒恢复 1 点体力
const AUTO_WAYPOINT_TOLERANCE := 0.15
const AUTO_STALL_SECONDS := 0.5
const AUTO_PROGRESS_EPSILON := 0.01

var _auto_path: Array[Vector3] = []
var _auto_path_index := 0
var _auto_stall_elapsed := 0.0
var _auto_last_distance := INF
@onready var player_visual: PlayerVisual = $PlayerVisual


func configure(new_camera_rig: Node, new_world: Node, tools: ToolSystem, grid: GridSystem) -> void:
	camera_rig = new_camera_rig
	game_world = new_world
	tool_system = tools
	grid_system = grid


func _physics_process(delta: float) -> void:
	# 重力
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 跳跃
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# 奔跑
	_is_sprinting = Input.is_action_pressed("sprint")
	if _is_sprinting and not is_on_floor():
		_is_sprinting = false

	# 移动
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3.ZERO
	var using_auto_movement := has_auto_movement()
	if input_vector.length_squared() > 0.0001:
		if using_auto_movement:
			_cancel_auto_for_manual_input()
		using_auto_movement = false
		if camera_rig:
			direction = _movement_from_input(input_vector)
	elif using_auto_movement:
		direction = _update_auto_movement(delta)

	var current_speed = speed if using_auto_movement else (sprint_speed if _is_sprinting else speed)
	velocity.x = move_toward(velocity.x, direction.x * current_speed, current_speed * 8.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * current_speed, current_speed * 8.0 * delta)

	move_and_slide()
	_clamp_to_world()
	if player_visual != null:
		player_visual.sync_motion(
			Vector2(velocity.x, velocity.z),
			_is_sprinting,
			is_on_floor()
		)

	# 奔跑消耗体力
	if _is_sprinting and direction.length_squared() > 0.01:
		_consume_stamina(2, delta)

	# 体力自然恢复
	_stamina_regen_timer += delta
	if _stamina_regen_timer >= 1.0:
		_stamina_regen_timer = 0.0
		_regen_stamina(1)


func start_auto_path(points: Array[Vector3]) -> bool:
	if points.is_empty():
		return false
	for point in points:
		if not _finite_vector3(point):
			return false
	stop_auto_movement("replaced")
	_auto_path.assign(points)
	_auto_path_index = 0
	_auto_stall_elapsed = 0.0
	_auto_last_distance = INF
	return true


func stop_auto_movement(_reason: String) -> void:
	_auto_path.clear()
	_auto_path_index = 0
	_auto_stall_elapsed = 0.0
	_auto_last_distance = INF
	velocity.x = 0.0
	velocity.z = 0.0


func has_auto_movement() -> bool:
	return not _auto_path.is_empty() and _auto_path_index < _auto_path.size()


func _update_auto_movement(delta: float) -> Vector3:
	if not has_auto_movement():
		return Vector3.ZERO
	_is_sprinting = false
	var current_position := global_position if is_inside_tree() else position
	var current_flat := Vector2(current_position.x, current_position.z)
	while _auto_path_index < _auto_path.size():
		var waypoint := _auto_path[_auto_path_index]
		var waypoint_flat := Vector2(waypoint.x, waypoint.z)
		if current_flat.distance_to(waypoint_flat) > AUTO_WAYPOINT_TOLERANCE:
			break
		_auto_path_index += 1
		_auto_last_distance = INF
		_auto_stall_elapsed = 0.0
	if _auto_path_index >= _auto_path.size():
		stop_auto_movement("finished")
		auto_path_finished.emit()
		return Vector3.ZERO

	var target := _auto_path[_auto_path_index]
	var target_flat := Vector2(target.x, target.z)
	var distance := current_flat.distance_to(target_flat)
	if _auto_last_distance == INF or distance < _auto_last_distance - AUTO_PROGRESS_EPSILON:
		_auto_stall_elapsed = 0.0
	else:
		_auto_stall_elapsed += maxf(0.0, delta)
	_auto_last_distance = distance
	if _auto_stall_elapsed >= AUTO_STALL_SECONDS:
		stop_auto_movement("blocked")
		auto_path_blocked.emit()
		return Vector3.ZERO
	var direction := Vector3(target.x - current_position.x, 0.0, target.z - current_position.z)
	return direction.normalized()


func _cancel_auto_for_manual_input() -> void:
	if not has_auto_movement():
		return
	stop_auto_movement("manual_input")
	manual_movement_requested.emit()


func _finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _movement_from_input(input_vector: Vector2) -> Vector3:
	var forward = camera_rig.get_planar_forward() if camera_rig else Vector3.FORWARD
	var right = camera_rig.get_planar_right() if camera_rig else Vector3.RIGHT
	return movement_from_input(input_vector, forward, right)


static func movement_from_input(input_vector: Vector2, forward: Vector3, right: Vector3) -> Vector3:
	var direction = right * input_vector.x + forward * -input_vector.y
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 1.0 else direction


static func find_interaction_target(node: Node) -> Node:
	var current := node
	while current:
		if current.has_method("interact") or current.has_method("start_dialogue") or current.has_method("collect"):
			return current
		current = current.get_parent()
	return null


static func is_interaction_hit_in_range(
	player_position: Vector3,
	hit_position: Vector3,
	maximum_range: float
) -> bool:
	return Vector2(player_position.x, player_position.z).distance_to(
		Vector2(hit_position.x, hit_position.z)
	) <= maximum_range


func _consume_stamina(amount: int, delta: float) -> void:
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.player_state:
		game_state.player_state.stamina = maxi(0, game_state.player_state.stamina - amount)
		stamina_changed.emit(game_state.player_state.stamina)


func _regen_stamina(amount: int) -> void:
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.player_state:
		var ps = game_state.player_state
		if ps.stamina < ps.max_stamina:
			ps.stamina = mini(ps.max_stamina, ps.stamina + amount)
			stamina_changed.emit(ps.stamina)


func _clamp_to_world() -> void:
	if game_world == null:
		return
	var bounds: Rect2 = game_world.get_bounds()
	global_position.x = clampf(global_position.x, bounds.position.x, bounds.end.x)
	global_position.z = clampf(global_position.z, bounds.position.y, bounds.end.y)
