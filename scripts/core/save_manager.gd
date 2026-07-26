extends Node

## 存档系统 - JSON 格式存档/读档

const SAVE_DIR = "user://villa_saves/"
const SAVE_PREFIX = "save_"
const SAVE_EXT = ".json"

var _event_bus


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")

	# 确保存档目录存在
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	# 连接自动存档
	if _event_bus:
		_event_bus.day_changed.connect(_on_day_changed)


# ============================================================
# 存档
# ============================================================

func save_game(slot: int = 0) -> bool:
	var data = _gather_save_data()
	if data.is_empty():
		return false

	var json_string = JSON.stringify(data)
	var file_path = SAVE_DIR + SAVE_PREFIX + str(slot) + SAVE_EXT

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open save file for writing: %s" % file_path)
		return false

	file.store_string(json_string)
	file.close()

	print("Game saved to slot %d" % slot)
	return true


func _gather_save_data() -> Dictionary:
	var data := {}

	# 游戏状态
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		data["gold"] = game_state.gold
		data["player"] = {
			"stamina": game_state.player_state.stamina,
			"max_stamina": game_state.player_state.max_stamina,
			"level": game_state.player_state.level,
			"exp": game_state.player_state.exp,
		}

	# 季节/时间
	var season_system = get_node_or_null("/root/SeasonSystem")
	if season_system:
		data["season"] = season_system.current_season
		data["day"] = season_system.current_day
		data["total_days"] = season_system.total_days
		data["hour"] = season_system.hour
		data["minute"] = season_system.minute

	# 背包
	var inventory = get_node_or_null("/root/InventorySystem")
	if inventory:
		data["inventory"] = {
			"slots": inventory.slots,
			"quick_mappings": inventory.quick_slot_mappings,
		}

	# 网格状态
	var grid_system = _get_grid_system()
	if grid_system:
		data["grid"] = grid_system.to_dict()

	# 建筑
	var building_system = get_node_or_null("/root/BuildingSystem")
	if building_system:
		var buildings_data = []
		for b in building_system.get_all_buildings():
			buildings_data.append({
				"building_id": b.building_id,
				"gx": b.gx,
				"gz": b.gz,
			})
		data["buildings"] = buildings_data

	# 故事
	var story_system = get_node_or_null("/root/StorySystem")
	if story_system:
		data["story_fragments"] = story_system.collected_fragments

	# 收集品
	var collectible_system = get_node_or_null("/root/CollectibleSystem")
	if collectible_system:
		data["discovered_collectibles"] = collectible_system.discovered.keys()

	# 村民好感度
	var villager_system = get_node_or_null("/root/VillagerSystem")
	if villager_system:
		var affinity_data = {}
		for v in GameData.get_all_villagers():
			affinity_data[v.id] = villager_system.get_affinity(v.id)
		data["villager_affinity"] = affinity_data

	# 迷雾
	var exploration = get_node_or_null("/root/ExplorationSystem")
	if exploration and exploration.fog_image:
		data["fog_data"] = Marshalls.raw_to_base64(exploration.fog_image.save_png_to_buffer())

	# 存档元数据
	data["meta"] = {
		"save_time": Time.get_datetime_string_from_system(),
		"total_days": data.get("total_days", 1),
	}

	return data


# ============================================================
# 读档
# ============================================================

func load_game(slot: int = 0) -> bool:
	var file_path = SAVE_DIR + SAVE_PREFIX + str(slot) + SAVE_EXT

	if not FileAccess.file_exists(file_path):
		return false

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open save file for reading: %s" % file_path)
		return false

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("Failed to parse save data: %s" % json.get_error_message())
		return false

	var data = json.data
	if not data is Dictionary:
		push_error("Invalid save data format")
		return false

	_apply_save_data(data)

	print("Game loaded from slot %d" % slot)
	return true


func _apply_save_data(data: Dictionary) -> void:
	# 游戏状态
	var game_state = get_node_or_null("/root/GameState")
	if game_state and data.has("gold"):
		game_state.gold = data.gold
		if data.has("player"):
			var p = data.player
			game_state.player_state.stamina = p.get("stamina", 100)
			game_state.player_state.max_stamina = p.get("max_stamina", 100)
			game_state.player_state.level = p.get("level", 1)
			game_state.player_state.exp = p.get("exp", 0)

	# 季节/时间
	var season_system = get_node_or_null("/root/SeasonSystem")
	if season_system and data.has("season"):
		season_system.current_season = data.season
		season_system.current_day = data.get("day", 1)
		season_system.total_days = data.get("total_days", 1)
		season_system.hour = data.get("hour", 6)
		season_system.minute = data.get("minute", 0)

	# 背包
	var inventory = get_node_or_null("/root/InventorySystem")
	if inventory and data.has("inventory"):
		inventory.slots = data.inventory.get("slots", [])
		inventory.quick_slot_mappings = data.inventory.get("quick_mappings", [-1,-1,-1,-1,-1,-1])

	# 网格状态
	var grid_system = _get_grid_system()
	if grid_system and data.has("grid"):
		grid_system.from_dict(data.grid)

	# 故事
	var story_system = get_node_or_null("/root/StorySystem")
	if story_system and data.has("story_fragments"):
		story_system.collected_fragments = data.story_fragments

	# 收集品
	var collectible_system = get_node_or_null("/root/CollectibleSystem")
	if collectible_system and data.has("discovered_collectibles"):
		for cid in data.discovered_collectibles:
			collectible_system.discovered[cid] = true

	# 村民好感度
	var villager_system = get_node_or_null("/root/VillagerSystem")
	if villager_system and data.has("villager_affinity"):
		for vid in data.villager_affinity:
			villager_system._affinity[vid] = data.villager_affinity[vid]

	# 迷雾
	var exploration = get_node_or_null("/root/ExplorationSystem")
	if exploration and data.has("fog_data"):
		var fog_bytes = Marshalls.base64_to_raw(data.fog_data)
		var loaded_image = Image.new()
		if loaded_image.load_png_from_buffer(fog_bytes) == OK:
			exploration.fog_image = loaded_image
			exploration.fog_texture = ImageTexture.create_from_image(loaded_image)


# ============================================================
# 存档管理
# ============================================================

func get_save_slots() -> Array:
	var slots = []
	for i in range(5):
		var file_path = SAVE_DIR + SAVE_PREFIX + str(i) + SAVE_EXT
		if FileAccess.file_exists(file_path):
			var file = FileAccess.open(file_path, FileAccess.READ)
			if file:
				var json = JSON.new()
				json.parse(file.get_as_text())
				file.close()
				var data = json.data
				var meta = data.get("meta", {}) if data is Dictionary else {}
				slots.append({
					"slot": i,
					"exists": true,
					"save_time": meta.get("save_time", "unknown"),
					"total_days": meta.get("total_days", 0),
				})
			else:
				slots.append({"slot": i, "exists": false})
		else:
			slots.append({"slot": i, "exists": false})
	return slots


func delete_save(slot: int) -> bool:
	var file_path = SAVE_DIR + SAVE_PREFIX + str(slot) + SAVE_EXT
	if not FileAccess.file_exists(file_path):
		return false
	DirAccess.remove_absolute(file_path)
	return true


func _on_day_changed(_total_day: int) -> void:
	# 自动存档到 slot 0
	save_game(0)


func _get_grid_system() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("grid_system")
