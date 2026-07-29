extends CharacterBody3D

## 村民 NPC - 日程驱动的状态机
## 状态：IDLE → MOVING → WORKING → WANDERING → SLEEPING

signal dialogue_started(villager_id: String)
signal defeated(npc: CharacterBody3D)

@export var villager_id: String = "lao_li"
@export var move_speed: float = 2.0
@export var health: int = 3

var knockback_velocity: Vector3 = Vector3.ZERO
var _defeated_emitted := false
var _current_state: String = "IDLE"
var _target_position: Vector3 = Vector3.ZERO
var _player_ref
var _event_bus

const INTERACTION_DISTANCE := 3.0


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")

	# 注册到 VillagerSystem
	var villager_system = get_node_or_null("/root/VillagerSystem")
	if villager_system:
		villager_system.register_villager(self, villager_id)


func configure(player: Node3D) -> void:
	_player_ref = player


func take_hit(damage: int, direction: Vector3) -> void:
	if damage <= 0 or health <= 0:
		return
	health = maxi(0, health - damage)
	if direction.length_squared() > 0.0001:
		knockback_velocity = direction.normalized() * float(damage)
	if health == 0 and not _defeated_emitted:
		_defeated_emitted = true
		defeated.emit(self)


func set_target_location(location: String) -> void:
	# 根据位置名称设置目标点
	# 实际位置由场景中的 Marker3D 定义
	match location:
		"home":
			_target_position = _find_marker("home")
			_current_state = "MOVING_TO_HOME"
		"shop":
			_target_position = _find_marker("shop")
			_current_state = "WORKING"
		"forge":
			_target_position = _find_marker("forge")
			_current_state = "WORKING"
		"garden":
			_target_position = _find_marker("garden")
			_current_state = "WORKING"
		"library":
			_target_position = _find_marker("library")
			_current_state = "WORKING"
		"creek":
			_target_position = _find_marker("creek")
			_current_state = "WORKING"
		"wander":
			_target_position = _random_wander_point()
			_current_state = "WANDERING"
		_:
			_current_state = "IDLE"


func _find_marker(name: String) -> Vector3:
	# 在场景中查找对应标记点
	var marker = get_tree().get_first_node_in_group("marker_" + name)
	if marker and marker is Node3D:
		return marker.global_position
	return global_position  # 找不到就原地不动


func _random_wander_point() -> Vector3:
	var offset_x = randf_range(-5.0, 5.0)
	var offset_z = randf_range(-5.0, 5.0)
	return global_position + Vector3(offset_x, 0, offset_z)


func _physics_process(delta: float) -> void:
	match _current_state:
		"MOVING_TO_HOME", "WORKING", "WANDERING":
			_move_toward_target(delta)
		"IDLE", "SLEEPING":
			velocity = Vector3.ZERO


func _move_toward_target(delta: float) -> void:
	var to_target = _target_position - global_position
	to_target.y = 0
	var dist = to_target.length()

	if dist < 0.5:
		velocity = Vector3.ZERO
		if _current_state == "MOVING_TO_HOME":
			_current_state = "SLEEPING"
		elif _current_state == "WANDERING":
			# 到达后随机选新目标
			if randf() < 0.3:
				_target_position = _random_wander_point()
			else:
				_current_state = "IDLE"
		return

	var direction = to_target.normalized()
	velocity = direction * move_speed

	# 面向移动方向
	if direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 1.0 - exp(-8.0 * delta))

	move_and_slide()


func start_dialogue() -> void:
	if _player_ref == null:
		return

	var dist = global_position.distance_to(_player_ref.global_position)
	if dist > INTERACTION_DISTANCE:
		return

	dialogue_started.emit(villager_id)

	# 增加好感度
	var villager_system = get_node_or_null("/root/VillagerSystem")
	if villager_system:
		villager_system.add_affinity(villager_id, 1)
