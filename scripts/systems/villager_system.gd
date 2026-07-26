class_name VillagerSystem
extends Node

## 村民系统 - 管理村民 AI、好感度、对话

var _villagers: Dictionary = {}  # villager_id → VillagerData
var _affinity: Dictionary = {}   # villager_id → int (0-100)
var _event_bus


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")

	# 初始化所有村民的好感度
	for v in GameData.get_all_villagers():
		_affinity[v.id] = 0

	# 连接时间事件
	if _event_bus:
		_event_bus.time_changed.connect(_on_time_changed)


func register_villager(villager_node: Node3D, villager_id: String) -> void:
	var data = GameData.get_villager(villager_id)
	if data.is_empty():
		push_error("Unknown villager: %s" % villager_id)
		return

	_villagers[villager_id] = {
		"node": villager_node,
		"data": data,
		"current_state": "IDLE",
		"target_position": Vector3.ZERO,
	}


# ============================================================
# 好感度系统
# ============================================================

enum AffinityLevel { STRANGER, FRIEND, CLOSE, SOULMATE }

func get_affinity(villager_id: String) -> int:
	return _affinity.get(villager_id, 0)


func add_affinity(villager_id: String, amount: int) -> void:
	if not _affinity.has(villager_id):
		return

	var old_level = get_affinity_level(villager_id)
	_affinity[villager_id] = clampi(_affinity[villager_id] + amount, 0, 100)
	var new_level = get_affinity_level(villager_id)

	if _event_bus:
		_event_bus.affinity_changed.emit(villager_id, _affinity[villager_id])
		if new_level != old_level:
			_event_bus.affinity_level_up.emit(villager_id, new_level)
			_grant_level_reward(villager_id, new_level)


func get_affinity_level(villager_id: String) -> int:
	var value = get_affinity(villager_id)
	if value <= 20:
		return AffinityLevel.STRANGER
	elif value <= 50:
		return AffinityLevel.FRIEND
	elif value <= 80:
		return AffinityLevel.CLOSE
	else:
		return AffinityLevel.SOULMATE


func get_affinity_level_name(level: int) -> String:
	match level:
		AffinityLevel.STRANGER:
			return "陌生"
		AffinityLevel.FRIEND:
			return "友好"
		AffinityLevel.CLOSE:
			return "亲密"
		AffinityLevel.SOULMATE:
			return "知己"
	return ""


func _grant_level_reward(villager_id: String, level: int) -> void:
	# 好感度升级奖励
	match level:
		AffinityLevel.FRIEND:
			# 解锁折扣
			pass
		AffinityLevel.CLOSE:
			# 获得稀有物品
			pass
		AffinityLevel.SOULMATE:
			# 特殊奖励
			pass


# ============================================================
# 日程系统
# ============================================================

func _on_time_changed(hour: int, _minute: int) -> void:
	for villager_id in _villagers:
		_update_villager_schedule(villager_id, hour)


func _update_villager_schedule(villager_id: String, hour: int) -> void:
	var v = _villagers.get(villager_id)
	if v == null:
		return

	var schedule = v.data.get("schedule", {})
	var target_location = schedule.get(hour, "home")

	# 确定新状态
	var new_state = "IDLE"
	match target_location:
		"home":
			new_state = "MOVING_TO_HOME"
		"shop", "forge", "garden", "library", "creek":
			new_state = "WORKING"
		"wander":
			new_state = "WANDERING"

	v.current_state = new_state

	# 设置目标位置（由 NPC 节点自身处理移动）
	if v.node and v.node.has_method("set_target_location"):
		v.node.set_target_location(target_location)


# ============================================================
# 对话系统
# ============================================================

func get_dialogue(villager_id: String, player_level: int = 1) -> Array:
	# 返回对话选项
	var v_data = GameData.get_villager(villager_id)
	if v_data.is_empty():
		return []

	var affinity_level = get_affinity_level(villager_id)
	var dialogues = []

	# 基础问候
	dialogues.append({
		"text": "你好，%s。今天过得怎么样？" % v_data.name,
		"choices": [
			{"text": "还不错！", "effect": {"affinity": 1}},
			{"text": "忙着种地呢", "effect": {"affinity": 2}},
		],
	})

	# 根据好感度添加更多对话
	if affinity_level >= AffinityLevel.FRIEND:
		dialogues.append({
			"text": "最近农庄经营得不错啊。",
			"choices": [
				{"text": "谢谢！还在努力", "effect": {"affinity": 1}},
			],
		})

	if affinity_level >= AffinityLevel.CLOSE:
		dialogues.append({
			"text": "我有个东西想给你看看...",
			"choices": [
				{"text": "是什么？", "effect": {"affinity": 3}},
			],
		})

	return dialogues
