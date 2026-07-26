class_name PlayerController
extends CharacterBody3D

## 玩家控制器 - 农庄模式
## 移动、工具使用、交互、体力系统

signal stamina_changed(value: int)
signal tool_changed(tool_type: int)

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
	if camera_rig:
		direction = _movement_from_input(input_vector)

	var current_speed = sprint_speed if _is_sprinting else speed
	velocity.x = move_toward(velocity.x, direction.x * current_speed, current_speed * 8.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * current_speed, current_speed * 8.0 * delta)

	if direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 1.0 - exp(-12.0 * delta))

	move_and_slide()
	_clamp_to_world()

	# 奔跑消耗体力
	if _is_sprinting and direction.length_squared() > 0.01:
		_consume_stamina(2, delta)

	# 体力自然恢复
	_stamina_regen_timer += delta
	if _stamina_regen_timer >= 1.0:
		_stamina_regen_timer = 0.0
		_regen_stamina(1)


func _movement_from_input(input_vector: Vector2) -> Vector3:
	var forward = camera_rig.get_planar_forward() if camera_rig else Vector3.FORWARD
	var right = camera_rig.get_planar_right() if camera_rig else Vector3.RIGHT
	var direction = right * input_vector.x + forward * -input_vector.y
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 1.0 else direction


func _unhandled_input(event: InputEvent) -> void:
	# 工具使用（鼠标左键）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_use_current_tool()

	# 交互（鼠标右键 / E键）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_interact()
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		_interact()

	# 工具切换（数字键 1-5）
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_switch_tool(ToolSystem.ToolType.HOE)
			KEY_2:
				_switch_tool(ToolSystem.ToolType.WATERING_CAN)
			KEY_3:
				_switch_tool(ToolSystem.ToolType.AXE)
			KEY_4:
				_switch_tool(ToolSystem.ToolType.PICKAXE)
			KEY_5:
				_switch_tool(ToolSystem.ToolType.FISHING_ROD)


func _use_current_tool() -> void:
	if tool_system == null:
		return

	var target = _raycast_to_grid_cell()
	if target:
		tool_system.use_tool_on(target)


func _interact() -> void:
	# 射线检测交互目标（NPC / 建筑 / 收集品）
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	var query = PhysicsRayQueryParameters3D.create(
		ray_origin, ray_origin + ray_dir * interaction_range
	)
	query.exclude = [get_rid()]
	# 检测 NPC 层(4) + 建筑层(64) + 收集品层(128)
	query.collision_mask = 4 | 64 | 128

	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var collider = hit.get("collider")
	if collider == null:
		return

	# NPC 对话
	if collider.has_method("start_dialogue"):
		collider.start_dialogue()
	# 建筑交互
	elif collider.has_method("interact"):
		collider.interact(self)
	# 收集品
	elif collider.has_method("collect"):
		collider.collect()


func _raycast_to_grid_cell() -> GridCell:
	if grid_system == null:
		return null

	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return null

	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	# 射线与地面平面(y=0)求交
	var t = -ray_origin.y / ray_dir.y if ray_dir.y != 0.0 else -1.0
	if t < 0:
		return null

	var hit_point = ray_origin + ray_dir * t
	var dist = global_position.distance_to(Vector3(hit_point.x, global_position.y, hit_point.z))
	if dist > interaction_range:
		return null

	return grid_system.get_cell_at_world(hit_point.x, hit_point.z)


func _switch_tool(tool_type: int) -> void:
	if tool_system:
		tool_system.switch_tool(tool_type)
	tool_changed.emit(tool_type)


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
