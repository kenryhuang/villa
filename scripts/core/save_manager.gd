extends Node

## 存档系统 - JSON 格式存档/读档

const SAVE_DIR = "user://villa_saves/"
const SAVE_PREFIX = "save_"
const SAVE_EXT = ".json"
const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")

var save_directory := SAVE_DIR
var current_slot := 0
var _market_system: Variant
var _daily_simulation_system: Variant
var _season_system: Variant


func configure_economy(
	market_system: Variant,
	daily_simulation_system: Variant,
	season_system: Variant = null
) -> bool:
	if not _has_methods(market_system, ["configure", "to_dict", "from_dict"]):
		return false
	if not _has_property(daily_simulation_system, "last_simulated_day"):
		return false
	if season_system != null and not _has_properties(
		season_system,
		["current_season", "current_day", "total_days", "hour", "minute"]
	):
		return false
	_market_system = market_system
	_daily_simulation_system = daily_simulation_system
	_season_system = season_system
	return true


# ============================================================
# 存档
# ============================================================

func save_game(slot: int = 0) -> bool:
	var data = _gather_save_data()
	if data.is_empty():
		return false

	var json_string = JSON.stringify(data)
	var file_path := _save_path(slot)
	DirAccess.make_dir_recursive_absolute(save_directory)

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
	var season_system = _get_season_system()
	if season_system:
		data["season"] = season_system.current_season
		data["day"] = season_system.current_day
		data["total_days"] = season_system.total_days
		data["hour"] = season_system.hour
		data["minute"] = season_system.minute

	# 背包
	var inventory = _get_inventory_system()
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
	var building_system = _get_building_system()
	if building_system:
		data["buildings"] = _serialize_buildings(building_system)

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
		var game_data = GameDataScript.new()
		for v in game_data.get_all_villagers():
			affinity_data[v.id] = villager_system.get_affinity(v.id)
		game_data.free()
		data["villager_affinity"] = affinity_data

	# 迷雾
	var exploration = get_node_or_null("/root/ExplorationSystem")
	if exploration and exploration.fog_image:
		data["fog_data"] = Marshalls.raw_to_base64(exploration.fog_image.save_png_to_buffer())

	# 经济状态
	if _has_valid_economy_configuration():
		data["economy_version"] = 1
		data["market"] = _market_system.call("to_dict")
		data["last_simulated_day"] = int(_daily_simulation_system.get("last_simulated_day"))

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
	var file_path := _save_path(slot)

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

	if not _apply_save_data(data):
		return false

	current_slot = slot
	print("Game loaded from slot %d" % slot)
	return true


func _apply_save_data(data: Dictionary) -> bool:
	if not _validate_economy_save_data(data):
		return false

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
	var season_system = _get_season_system()
	if season_system and data.has("season"):
		season_system.current_season = data.season
		season_system.current_day = data.get("day", 1)
		season_system.total_days = data.get("total_days", 1)
		season_system.hour = data.get("hour", 6)
		season_system.minute = data.get("minute", 0)

	# 背包
	var inventory = _get_inventory_system()
	if inventory and data.has("inventory"):
		inventory.restore_state(
			data.inventory.get("slots", []),
			data.inventory.get("quick_mappings", [-1, -1, -1, -1, -1, -1])
		)

	# 网格状态
	var grid_system = _get_grid_system()
	var building_system = _get_building_system()
	if building_system:
		building_system.clear_buildings(true)
	if grid_system and data.has("grid"):
		grid_system.from_dict(data.grid)
	if building_system and data.has("buildings"):
		building_system.restore_buildings(data.buildings)

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

	_apply_economy_save_data(data)
	return true


# ============================================================
# 存档管理
# ============================================================

func get_save_slots() -> Array:
	var slots = []
	for i in range(5):
		var file_path := _save_path(i)
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
	if not has_save(slot):
		return false
	return clear_save(slot)


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_save_path(slot))


func clear_save(slot: int) -> bool:
	var file_path := _save_path(slot)
	if not FileAccess.file_exists(file_path):
		return true
	return DirAccess.remove_absolute(file_path) == OK


func _save_path(slot: int) -> String:
	return save_directory.path_join(SAVE_PREFIX + str(slot) + SAVE_EXT)


func _get_grid_system() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("grid_system")


func _get_inventory_system() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("inventory_system")


func _get_building_system() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("building_system")


func _serialize_buildings(building_system: Node) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if building_system == null or not building_system.has_method("get_all_buildings"):
		return records
	for building in building_system.get_all_buildings():
		if building != null and building.has_method("to_dict"):
			records.append(building.to_dict())
	return records


func _validate_economy_save_data(data: Dictionary) -> bool:
	if not data.has("economy_version"):
		return not data.has("market") and not data.has("last_simulated_day")
	if not _is_integer_number(data.get("economy_version")) or int(data["economy_version"]) != 1:
		return false
	if not _has_valid_economy_configuration():
		return false
	if not data.get("market", null) is Dictionary:
		return false
	if (
		not _is_integer_number(data.get("last_simulated_day"))
		or int(data["last_simulated_day"]) < 0
	):
		return false
	if _has_injected_season_system() and not _validate_calendar_bundle(data):
		return false
	if data.has("total_days") and (
		not _is_integer_number(data["total_days"])
		or int(data["total_days"]) < 0
		or int(data["total_days"]) != int(data["last_simulated_day"])
	):
		return false
	var validation_market := MarketSystemScript.new()
	var valid := validation_market.from_dict(data["market"])
	if valid:
		valid = validation_market.last_settled_day == int(data["last_simulated_day"])
	validation_market.free()
	return valid


func _apply_economy_save_data(data: Dictionary) -> void:
	if not _has_valid_economy_configuration():
		return
	if data.has("economy_version"):
		_market_system.call("from_dict", data["market"])
		_daily_simulation_system.set("last_simulated_day", int(data["last_simulated_day"]))
		return
	var loaded_day := maxi(int(data.get("total_days", 1)), 0)
	_market_system.call("configure", GameDataScript.get_market_items())
	_market_system.set("last_settled_day", loaded_day)
	_daily_simulation_system.set("last_simulated_day", loaded_day)


func _has_valid_economy_configuration() -> bool:
	return (
		_market_system != null
		and is_instance_valid(_market_system)
		and _daily_simulation_system != null
		and is_instance_valid(_daily_simulation_system)
		and _has_methods(_market_system, ["configure", "to_dict", "from_dict"])
		and _has_property(_daily_simulation_system, "last_simulated_day")
	)


func _has_injected_season_system() -> bool:
	return _season_system != null and is_instance_valid(_season_system)


func _validate_calendar_bundle(data: Dictionary) -> bool:
	for field in ["season", "day", "total_days", "hour", "minute"]:
		if not data.has(field) or not _is_integer_number(data[field]):
			return false
	var total_days := int(data["total_days"])
	if total_days < 1:
		return false
	var elapsed_days := total_days - 1
	var expected_day := elapsed_days % 7 + 1
	var expected_season := floori(float(elapsed_days) / 7.0) % 4
	return (
		int(data["season"]) >= 0
		and int(data["season"]) <= 3
		and int(data["season"]) == expected_season
		and int(data["day"]) >= 1
		and int(data["day"]) <= 7
		and int(data["day"]) == expected_day
		and total_days == int(data["last_simulated_day"])
		and int(data["hour"]) >= 0
		and int(data["hour"]) <= 23
		and int(data["minute"]) >= 0
		and int(data["minute"]) <= 59
	)


func _has_methods(target: Variant, methods: Array[String]) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	for method_name in methods:
		if not target.has_method(method_name):
			return false
	return true


func _has_property(target: Variant, property_name: String) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _has_properties(target: Variant, property_names: Array[String]) -> bool:
	for property_name in property_names:
		if not _has_property(target, property_name):
			return false
	return true


func _get_season_system() -> Variant:
	if _season_system != null and is_instance_valid(_season_system):
		return _season_system
	return get_node_or_null("/root/SeasonSystem")


func _is_integer_number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
	)
