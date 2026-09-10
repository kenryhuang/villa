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
var _agent_dialogue_enabled := false
var _dialogue_busy := false
var _prompt_tween: Tween
var _prompt_visible_state := false
var _agent_work_arrived := false
var _farm3d_grid: GridSystem
var _farm3d_pathfinder: GridPathfinder
var _farm3d_path: Array[Vector3] = []
var character_model: Node3D
var character_animation: AnimationPlayer

const FARM3D_CHARACTER_MODELS := {
	"farmer_ahe": "res://assets/models/characters/farmer_ahe.glb",
	"lao_li": "res://assets/models/characters/lao_li.glb",
	"xuezhe_lin": "res://assets/models/characters/xuezhe_lin.glb",
}


func configure_farm3d(grid: GridSystem) -> void:
	_farm3d_grid = grid
	_farm3d_pathfinder = GridPathfinder.new()
	_farm3d_pathfinder.configure(grid)
	# The original actor is reused with a feet-based origin for uneven 3D ground.
	$CollisionShape3D.position.y = 0.65
	if placeholder_mesh != null:
		placeholder_mesh.position.y = 0.65
	collision_mask = 1 | 16
	_configure_character_model()


func _configure_character_model() -> void:
	if character_model != null or not FARM3D_CHARACTER_MODELS.has(villager_id):
		return
	var packed := load(FARM3D_CHARACTER_MODELS[villager_id]) as PackedScene
	if packed == null:
		return
	character_model = packed.instantiate() as Node3D
	character_model.name = "CharacterModel"
	add_child(character_model)
	var stature := 0.94 if villager_id == "farmer_ahe" else 1.035 if villager_id == "xuezhe_lin" else 1.0
	character_model.scale = Vector3.ONE * stature
	for child in character_model.find_children("*", "AnimationPlayer", true, false):
		character_animation = child as AnimationPlayer
		break
	if character_animation != null:
		for clip in character_animation.get_animation_list():
			if String(clip).get_file().to_lower() in ["idle", "walk", "work"]:
				character_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	if npc_visual != null:
		npc_visual.hide()
	if placeholder_mesh != null:
		placeholder_mesh.hide()
	if nameplate != null:
		nameplate.position.y = 2.16 * stature
	if dialogue_prompt != null:
		dialogue_prompt.position.y = 2.55 * stature
	_sync_visual_motion()

const INTERACTION_DISTANCE := 3.0
const PROMPT_INTERACTION_LAYER := 64

@onready var dialogue_prompt: Node3D = get_node_or_null("DialoguePrompt")
@onready var dialogue_prompt_icon: Sprite3D = get_node_or_null("DialoguePrompt/Icon")
@onready var dialogue_prompt_hit_area: Area3D = get_node_or_null("DialoguePrompt/HitArea")
@onready var nameplate: Label3D = get_node_or_null("Nameplate")
@onready var placeholder_mesh: MeshInstance3D = get_node_or_null("Mesh")
@onready var npc_visual: Sprite3D = get_node_or_null("NpcVisual")
@onready var farm_action_visual: Node3D = get_node_or_null("FarmActionVisual")


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")
	_set_dialogue_prompt_visible(false)

	# 注册到 VillagerSystem
	var villager_system = get_node_or_null("/root/VillagerSystem")
	if villager_system:
		villager_system.register_villager(self, villager_id)


func configure(player: Node3D) -> void:
	_player_ref = player
	refresh_dialogue_prompt()


func configure_agent(player: Node3D, agent_id: String, display_name: String = "") -> bool:
	configure(player)
	if agent_id.is_empty():
		return false
	villager_id = agent_id
	if nameplate != null:
		nameplate.text = display_name if not display_name.strip_edges().is_empty() else agent_id
		nameplate.visible = health > 0
	_agent_dialogue_enabled = true
	refresh_dialogue_prompt()
	return true


func configure_agent_visual_priority(visual_priority: int) -> void:
	if nameplate != null:
		nameplate.render_priority = visual_priority
	if dialogue_prompt_icon != null:
		dialogue_prompt_icon.render_priority = visual_priority + 1


func configure_agent_visual(atlas: Texture2D) -> bool:
	if character_model != null:
		return true
	var configured := (
		npc_visual != null
		and npc_visual.has_method("configure")
		and bool(npc_visual.call("configure", atlas))
	)
	if placeholder_mesh != null:
		placeholder_mesh.visible = not configured
	return configured


func is_player_in_dialogue_range() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return false
	return Vector2(global_position.x, global_position.z).distance_to(
		Vector2(_player_ref.global_position.x, _player_ref.global_position.z)
	) <= INTERACTION_DISTANCE


func set_dialogue_busy(value: bool) -> void:
	_dialogue_busy = value
	refresh_dialogue_prompt()


func is_dialogue_busy() -> bool:
	return _dialogue_busy


func refresh_dialogue_prompt() -> void:
	_set_dialogue_prompt_visible(
		_agent_dialogue_enabled
		and health > 0
		and not _dialogue_busy
		and is_player_in_dialogue_range()
	)


func _set_dialogue_prompt_visible(value: bool) -> void:
	if dialogue_prompt_hit_area != null:
		dialogue_prompt_hit_area.collision_layer = PROMPT_INTERACTION_LAYER if value else 0
		dialogue_prompt_hit_area.input_ray_pickable = value
	if dialogue_prompt == null:
		return
	if value == _prompt_visible_state and dialogue_prompt.visible == value:
		return
	_prompt_visible_state = value
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	if not value:
		dialogue_prompt.visible = false
		if dialogue_prompt_icon != null:
			dialogue_prompt_icon.modulate.a = 0.0
		return
	if dialogue_prompt.visible:
		if dialogue_prompt_icon != null:
			dialogue_prompt_icon.modulate.a = 1.0
		return
	dialogue_prompt.visible = true
	if dialogue_prompt_icon != null:
		dialogue_prompt_icon.modulate.a = 0.22
		_prompt_tween = create_tween()
		_prompt_tween.tween_property(dialogue_prompt_icon, "modulate:a", 1.0, 0.14)


func take_hit(damage: int, direction: Vector3) -> void:
	if damage <= 0 or health <= 0:
		return
	health = maxi(0, health - damage)
	if direction.length_squared() > 0.0001:
		knockback_velocity = direction.normalized() * float(damage)
	if health == 0 and not _defeated_emitted:
		_defeated_emitted = true
		if nameplate != null:
			nameplate.visible = false
		refresh_dialogue_prompt()
		defeated.emit(self)


func set_target_location(location: String) -> void:
	if _current_state == "AGENT_WORK":
		return
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
		"MOVING_TO_HOME", "WORKING", "WANDERING", "AGENT_WORK":
			_move_toward_target(delta)
		"IDLE", "SLEEPING":
			velocity = Vector3.ZERO
	_sync_visual_motion()
	refresh_dialogue_prompt()
	if _farm3d_grid != null:
		global_position.y = Farm3DTerrainProfile.surface_height(global_position.x, global_position.z)


func _sync_visual_motion() -> void:
	if character_model != null:
		if character_animation != null:
			var moving := Vector2(velocity.x, velocity.z).length_squared() > 0.01
			var working := farm_action_visual != null and bool(farm_action_visual.call("is_playing"))
			var preferred := "walk" if moving else "work" if working else "idle"
			character_animation.speed_scale = clampf(Vector2(velocity.x, velocity.z).length() / 2.0, 0.5, 2.5) if moving else 1.0
			for clip in character_animation.get_animation_list():
				if String(clip).get_file().to_lower() == preferred:
					if character_animation.current_animation != clip:
						character_animation.play(clip, 0.16)
					break
		return
	if npc_visual == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var camera_right := camera.global_basis.x
	camera_right.y = 0.0
	var camera_forward := -camera.global_basis.z
	camera_forward.y = 0.0
	if camera_right.length_squared() <= 0.0001 or camera_forward.length_squared() <= 0.0001:
		return
	camera_right = camera_right.normalized()
	camera_forward = camera_forward.normalized()
	npc_visual.call("sync_motion", Vector2(
		velocity.dot(camera_right),
		-velocity.dot(camera_forward)
	))


func _move_toward_target(delta: float) -> void:
	if not _farm3d_path.is_empty():
		var point := _farm3d_path[0]
		if Vector2(global_position.x, global_position.z).distance_to(Vector2(point.x, point.z)) < 0.55:
			_farm3d_path.pop_front()
		_target_position = _farm3d_path[0] if not _farm3d_path.is_empty() else point
	var to_target = _target_position - global_position
	to_target.y = 0
	var dist = to_target.length()

	if dist < 0.5:
		velocity = Vector3.ZERO
		if _current_state == "AGENT_WORK" and _farm3d_path.is_empty():
			_agent_work_arrived = true
		elif _current_state == "MOVING_TO_HOME":
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


func begin_agent_work(target: Vector3) -> bool:
	if health <= 0:
		return false
	if _farm3d_pathfinder != null:
		_farm3d_path.clear()
		var cells := _farm3d_pathfinder.find_path_cells(_farm3d_grid.world_to_grid(global_position.x, global_position.z), _farm3d_grid.world_to_grid(target.x, target.z))
		if cells.is_empty():
			return false
		for coordinate in cells:
			_farm3d_path.append(_farm3d_grid.get_cell(coordinate.x, coordinate.y).world_position_3d())
		# A grid route ends at the cell centre; retain the requested final point.
		if _farm3d_path.back().distance_to(target) > 0.01:
			_farm3d_path.append(target)
	_target_position = target
	_target_position.y = global_position.y
	_agent_work_arrived = false
	_current_state = "AGENT_WORK"
	return true


func has_agent_work_target() -> bool:
	return _current_state == "AGENT_WORK"


func is_agent_work_arrived() -> bool:
	return _agent_work_arrived


func stop_agent_work() -> void:
	if _current_state == "AGENT_WORK":
		_current_state = "IDLE"
	velocity = Vector3.ZERO
	_farm3d_path.clear()
	_agent_work_arrived = false


func face_world_point(target: Vector3) -> void:
	var direction := target - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		rotation.y = atan2(direction.x, direction.z)


func start_dialogue() -> bool:
	if (
		not _agent_dialogue_enabled
		or health <= 0
		or _dialogue_busy
		or not is_player_in_dialogue_range()
	):
		return false
	_dialogue_busy = true
	refresh_dialogue_prompt()
	dialogue_started.emit(villager_id)
	return true
