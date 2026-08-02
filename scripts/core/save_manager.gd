extends Node

## 存档系统 - JSON 格式存档/读档

signal load_completed(slot: int)

const SAVE_DIR = "user://villa_saves/"
const SAVE_PREFIX = "save_"
const SAVE_EXT = ".json"
const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const EconomyProgressionScript = preload("res://scripts/systems/economy_progression_system.gd")
const ProductionSystemScript = preload("res://scripts/systems/production_system.gd")

var save_directory := SAVE_DIR
var current_slot := 0
var _market_system: Variant
var _daily_simulation_system: Variant
var _season_system: Variant
var _resource_world: Variant
var _npc_economy_system: Variant
var _economy_system: Variant
var _progression_system: Variant
var _tool_system: Variant
var _production_system: Variant


func configure_economy(
	market_system: Variant,
	daily_simulation_system: Variant,
	season_system: Variant = null,
	resource_world: Variant = null,
	npc_economy_system: Variant = null,
	economy_system: Variant = null,
	progression_system: Variant = null,
	tool_system: Variant = null,
	production_system: Variant = null
) -> bool:
	var upkeep_dependency_count := 0
	for dependency in [progression_system, tool_system, production_system]:
		if dependency != null:
			upkeep_dependency_count += 1
	if upkeep_dependency_count != 0 and upkeep_dependency_count != 3:
		return false
	if not _has_methods(market_system, ["configure", "to_dict", "from_dict"]):
		return false
	if not _has_property(daily_simulation_system, "last_simulated_day"):
		return false
	if season_system != null and not _has_properties(
		season_system,
		["current_season", "current_day", "total_days", "hour", "minute"]
	):
		return false
	if resource_world != null and not _has_methods(resource_world, [
		"to_resource_dicts",
		"validate_resource_dicts",
		"restore_resource_dicts",
		"initialize_resources_at_day",
	]):
		return false
	if npc_economy_system != null and not _has_methods(npc_economy_system, [
		"to_dict", "from_dict", "validate_dict", "reset_to_profile_defaults",
	]):
		return false
	if economy_system != null and not _has_methods(economy_system, [
		"to_dict", "from_dict", "validate_dict", "reset_order_state",
	]):
		return false
	if progression_system != null and not _has_methods(progression_system, [
		"to_dict", "from_dict", "validate_dict", "reset_to_new_game",
	]):
		return false
	if tool_system != null and not _has_methods(tool_system, [
		"to_dict", "from_dict", "validate_dict", "reset_durability",
	]):
		return false
	if production_system != null and not _has_methods(production_system, [
		"to_dict", "from_dict", "validate_dict", "reset_maintenance",
	]):
		return false
	_market_system = market_system
	_daily_simulation_system = daily_simulation_system
	_season_system = season_system
	_resource_world = resource_world
	_npc_economy_system = npc_economy_system
	_economy_system = economy_system
	_progression_system = progression_system
	_tool_system = tool_system
	_production_system = production_system
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
		if _has_valid_npc_configuration():
			data["npc_economy"] = _npc_economy_system.call("to_dict")
		if _has_valid_order_configuration():
			data["economy_state"] = _economy_system.call("to_dict")
		if _has_valid_resource_configuration():
			data["resource_nodes"] = _resource_world.call("to_resource_dicts")
		if _has_valid_progression_configuration():
			data["progression"] = _progression_system.call("to_dict")
		if _has_valid_tool_configuration():
			data["tool_durability"] = _tool_system.call("to_dict")
		if _has_valid_production_configuration():
			data["production_upkeep"] = _production_system.call("to_dict")

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
	_finalize_committed_load()
	load_completed.emit(slot)
	print("Game loaded from slot %d" % slot)
	return true


func _apply_save_data(data: Dictionary) -> bool:
	var migrated_value: Variant = _migrate_save_data(data)
	if not migrated_value is Dictionary:
		return false
	var migrated_data := migrated_value as Dictionary
	if not _validate_save_data(migrated_data):
		return false
	var previous_state := _gather_save_data().duplicate(true)
	if _apply_migrated_save_data(migrated_data):
		return true
	if not _apply_migrated_save_data(previous_state):
		push_error("Failed to roll back rejected save data")
	return false


func _apply_migrated_save_data(data: Dictionary) -> bool:
	if not _apply_economy_save_data(data):
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
	if data.has("grid") and not data["grid"] is Dictionary:
		return false
	if data.has("buildings") and not data["buildings"] is Array:
		return false
	if building_system:
		building_system.clear_buildings(true, false)
	if grid_system and data.has("grid"):
		if grid_system.has_method("reset_state"):
			grid_system.reset_state()
		if not bool(grid_system.from_dict(data.grid)):
			return false
	elif data.has("grid"):
		return false
	if data.has("buildings"):
		if building_system == null:
			return false
		var building_records := data["buildings"] as Array
		var restored_count := int(building_system.restore_buildings(building_records, false))
		if restored_count != building_records.size():
			return false

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
		return (
			not data.has("market")
			and not data.has("last_simulated_day")
			and not data.has("resource_nodes")
			and not data.has("npc_economy")
			and not data.has("economy_state")
			and not data.has("progression")
			and not data.has("tool_durability")
			and not data.has("production_upkeep")
		)
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
	if data.has("resource_nodes"):
		var loaded_day := int(data.get("total_days", data["last_simulated_day"]))
		if (
			not _has_valid_resource_configuration()
			or not bool(_resource_world.call(
				"validate_resource_dicts",
				data["resource_nodes"],
				loaded_day
			))
		):
			return false
	if data.has("npc_economy"):
		if (
			not _has_valid_npc_configuration()
			or not data["npc_economy"] is Dictionary
			or not bool(_npc_economy_system.call("validate_dict", data["npc_economy"]))
			or int((data["npc_economy"] as Dictionary).get("last_simulated_day", -1))
				!= int(data["last_simulated_day"])
		):
			return false
	if data.has("economy_state"):
		if (
			not _has_valid_order_configuration()
			or not data["economy_state"] is Dictionary
			or not bool(_economy_system.call("validate_dict", data["economy_state"]))
			or int((data["economy_state"] as Dictionary).get("last_processed_day", -1))
				!= int(data["last_simulated_day"])
		):
			return false
	var upkeep_field_count := 0
	for field in ["progression", "tool_durability", "production_upkeep"]:
		if data.has(field):
			upkeep_field_count += 1
	if upkeep_field_count != 0 and upkeep_field_count != 3:
		return false
	if data.has("progression") and (
		not _has_valid_progression_configuration()
		or not data["progression"] is Dictionary
		or not bool(_progression_system.call("validate_dict", data["progression"]))
	):
		return false
	if data.has("tool_durability") and (
		not _has_valid_tool_configuration()
		or not data["tool_durability"] is Dictionary
		or not bool(_tool_system.call("validate_dict", data["tool_durability"]))
	):
		return false
	if data.has("production_upkeep") and (
		not _has_valid_production_configuration()
		or not data["production_upkeep"] is Dictionary
		or not bool(_production_system.call("validate_dict", data["production_upkeep"]))
	):
		return false
	var validation_market := MarketSystemScript.new()
	var valid := validation_market.from_dict(data["market"])
	if valid:
		valid = validation_market.last_settled_day == int(data["last_simulated_day"])
	validation_market.free()
	return valid


func _validate_save_data(data: Dictionary) -> bool:
	if not _validate_economy_save_data(data):
		return false
	var inventory = _get_inventory_system()
	var grid_system = _get_grid_system()
	var building_system = _get_building_system()
	var has_world_snapshot_runtime := (
		inventory != null or grid_system != null or building_system != null
	)
	if data.has("economy_version") and has_world_snapshot_runtime:
		if get_node_or_null("/root/GameState") != null and (
			not data.has("gold") or not data.has("player")
		):
			return false
		if inventory != null and not data.has("inventory"):
			return false
		if grid_system != null and not data.has("grid"):
			return false
		if building_system != null and not data.has("buildings"):
			return false
	if data.has("grid") != data.has("buildings"):
		return false
	if data.has("gold") and (
		not _is_integer_number(data.gold) or int(data.gold) < 0
	):
		return false
	if data.has("player") and not _validate_player_save_data(data.player):
		return false
	if data.has("inventory"):
		if inventory == null or not data.inventory is Dictionary:
			return false
		var inventory_data := data.inventory as Dictionary
		if not inventory_data.has("slots") or not inventory_data.has("quick_mappings"):
			return false
		if inventory.normalize_saved_state(
			inventory_data.slots,
			inventory_data.quick_mappings
		) == null:
			return false
	if data.has("grid"):
		if (
			not data.grid is Dictionary
			or grid_system == null
			or not grid_system.has_method("validate_dict")
			or not bool(grid_system.validate_dict(data.grid))
		):
			return false
	if data.has("buildings"):
		if not data.buildings is Array or not data.get("grid", null) is Dictionary:
			return false
		if (
			building_system == null
			or not building_system.has_method("validate_restore_buildings")
			or not bool(building_system.validate_restore_buildings(data.buildings, data.grid))
		):
			return false
		if not _validate_economy_building_keys(data):
			return false
	return true


func _validate_economy_building_keys(data: Dictionary) -> bool:
	if not data.has("progression"):
		return true
	var valid_keys := {}
	var building_records := {}
	for value in data.buildings:
		if not value is Dictionary:
			return false
		var record := value as Dictionary
		var key := "%s:%d:%d" % [str(record.get("building_id", "")), int(record.get("gx", 0)), int(record.get("gz", 0))]
		if not EconomyProgressionScript.is_valid_building_key(key):
			return false
		valid_keys[key] = true
		building_records[key] = record
	var upgrade_levels_by_key := {}
	for value in (data.progression as Dictionary).get("upgrade_levels", []):
		var upgrade_record := value as Dictionary
		var upgrade_key := str(upgrade_record.get("building_key", ""))
		if not valid_keys.has(upgrade_key):
			return false
		var levels := {}
		for level_value in upgrade_record.get("levels", []):
			var level_record := level_value as Dictionary
			levels[str(level_record.get("upgrade_id", ""))] = int(level_record.get("level", 0))
		upgrade_levels_by_key[upgrade_key] = levels
	for key in building_records:
		var building_record := building_records[key] as Dictionary
		if not building_record.has("producer_state"):
			continue
		var producer := building_record.producer_state as Dictionary
		var levels: Dictionary = upgrade_levels_by_key.get(key, {})
		var expected_queue := ProductionSystemScript.expected_max_queue_slots(int(levels.get("queue_slots", 0)))
		var expected_output := ProductionSystemScript.expected_output_capacity(str(building_record.building_id), int(levels.get("storage", 0)))
		if int(producer.get("max_queue_slots", -1)) != expected_queue:
			return false
		if int(producer.get("output_capacity", -1)) != expected_output:
			return false
		if producer.has("storage_quantity_capacity") and int(producer.storage_quantity_capacity) != ProductionSystemScript.expected_storage_quantity_capacity(str(building_record.building_id), int(levels.get("storage", 0))):
			return false
	var upkeep := data.production_upkeep as Dictionary
	for field in ["maintenance", "speed_accumulators"]:
		for value in upkeep.get(field, []):
			if not valid_keys.has(str((value as Dictionary).get("building_key", ""))):
				return false
	return true


func _finalize_committed_load() -> void:
	if get_tree() == null:
		return
	for production_system in get_tree().get_nodes_in_group("production_system"):
		if production_system.has_method("rebuild_registered_buildings"):
			production_system.rebuild_registered_buildings()


func _validate_player_save_data(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var player := value as Dictionary
	for field in ["stamina", "max_stamina", "level", "exp"]:
		if player.has(field) and not _is_integer_number(player[field]):
			return false
	var stamina := int(player.get("stamina", 100))
	var max_stamina := int(player.get("max_stamina", 100))
	var level := int(player.get("level", 1))
	var exp := int(player.get("exp", 0))
	return (
		stamina >= 0
		and max_stamina > 0
		and stamina <= max_stamina
		and level > 0
		and exp >= 0
	)


func _apply_economy_save_data(data: Dictionary) -> bool:
	if not _has_valid_economy_configuration():
		return true
	var market_before: Dictionary = _market_system.call("to_dict")
	var daily_before := int(_daily_simulation_system.get("last_simulated_day"))
	var npc_before: Dictionary = {}
	if _has_valid_npc_configuration():
		npc_before = _npc_economy_system.call("to_dict")
	var orders_before: Dictionary = {}
	if _has_valid_order_configuration():
		orders_before = _economy_system.call("to_dict")
	var resources_before: Array = []
	if _has_valid_resource_configuration():
		resources_before = _resource_world.call("to_resource_dicts")
	var progression_before: Dictionary = {}
	if _has_valid_progression_configuration():
		progression_before = _progression_system.call("to_dict")
	var tools_before: Dictionary = {}
	if _has_valid_tool_configuration():
		tools_before = _tool_system.call("to_dict")
	var production_before: Dictionary = {}
	if _has_valid_production_configuration():
		production_before = _production_system.call("to_dict")
	var loaded_day := maxi(int(data.get("total_days", data.get("last_simulated_day", 1))), 0)
	var applied := true
	if data.has("economy_version"):
		applied = bool(_market_system.call("from_dict", data["market"]))
		_daily_simulation_system.set("last_simulated_day", int(data["last_simulated_day"]))
		if applied and _has_valid_npc_configuration():
			if data.has("npc_economy"):
				applied = bool(_npc_economy_system.call("from_dict", data["npc_economy"]))
			else:
				applied = bool(_npc_economy_system.call("reset_to_profile_defaults", loaded_day))
		if applied and _has_valid_order_configuration():
			if data.has("economy_state"):
				applied = bool(_economy_system.call("from_dict", data["economy_state"]))
			else:
				applied = bool(_economy_system.call("reset_order_state", loaded_day))
		if applied and _has_valid_progression_configuration():
			if data.has("progression"):
				applied = bool(_progression_system.call("from_dict", data["progression"]))
			else:
				applied = bool(_progression_system.call("reset_to_new_game"))
		if applied and _has_valid_tool_configuration():
			if data.has("tool_durability"):
				applied = bool(_tool_system.call("from_dict", data["tool_durability"]))
			else:
				applied = bool(_tool_system.call("reset_durability"))
		if applied and _has_valid_production_configuration():
			if data.has("production_upkeep"):
				applied = bool(_production_system.call("from_dict", data["production_upkeep"]))
			else:
				applied = bool(_production_system.call("reset_maintenance", loaded_day))
	else:
		applied = bool(_market_system.call("configure", GameDataScript.get_market_items()))
		if applied:
			_market_system.set("last_settled_day", loaded_day)
			_daily_simulation_system.set("last_simulated_day", loaded_day)
		if applied and _has_valid_npc_configuration():
			applied = bool(_npc_economy_system.call("reset_to_profile_defaults", loaded_day))
		if applied and _has_valid_order_configuration():
			applied = bool(_economy_system.call("reset_order_state", loaded_day))
		if applied and _has_valid_progression_configuration():
			applied = bool(_progression_system.call("reset_to_new_game"))
		if applied and _has_valid_tool_configuration():
			applied = bool(_tool_system.call("reset_durability"))
		if applied and _has_valid_production_configuration():
			applied = bool(_production_system.call("reset_maintenance", loaded_day))
	if applied:
		applied = _apply_resource_save_data(data, loaded_day)
	if not applied:
		_market_system.call("from_dict", market_before)
		_daily_simulation_system.set("last_simulated_day", daily_before)
		if _has_valid_npc_configuration() and not npc_before.is_empty():
			_npc_economy_system.call("from_dict", npc_before)
		if _has_valid_order_configuration() and not orders_before.is_empty():
			_economy_system.call("from_dict", orders_before)
		if _has_valid_resource_configuration() and not resources_before.is_empty():
			_resource_world.call("restore_resource_dicts", resources_before, daily_before)
		if _has_valid_progression_configuration() and not progression_before.is_empty():
			_progression_system.call("from_dict", progression_before)
		if _has_valid_tool_configuration() and not tools_before.is_empty():
			_tool_system.call("from_dict", tools_before)
		if _has_valid_production_configuration() and not production_before.is_empty():
			_production_system.call("from_dict", production_before)
		return false
	return true


func _apply_resource_save_data(data: Dictionary, loaded_day: int) -> bool:
	if not _has_valid_resource_configuration():
		return true
	if data.has("resource_nodes"):
		return bool(_resource_world.call(
			"restore_resource_dicts",
			data["resource_nodes"],
			loaded_day
		))
	else:
		_resource_world.call("initialize_resources_at_day", loaded_day)
	return true


func _migrate_save_data(data: Dictionary) -> Variant:
	var migrated := data.duplicate(true)
	var inventory_value: Variant = migrated.get("inventory")
	if inventory_value == null:
		return migrated
	if not inventory_value is Dictionary:
		return null
	var inventory_data := inventory_value as Dictionary
	if not inventory_data.has("slots") or not inventory_data.has("quick_mappings"):
		return null
	var inventory = _get_inventory_system()
	if inventory == null or not inventory.has_method("normalize_saved_state"):
		return null
	var normalized: Variant = inventory.normalize_saved_state(
		inventory_data.slots,
		inventory_data.quick_mappings
	)
	if not normalized is Dictionary:
		return null
	migrated["inventory"] = normalized
	return migrated


func _has_valid_economy_configuration() -> bool:
	return (
		_market_system != null
		and is_instance_valid(_market_system)
		and _daily_simulation_system != null
		and is_instance_valid(_daily_simulation_system)
		and _has_methods(_market_system, ["configure", "to_dict", "from_dict"])
		and _has_property(_daily_simulation_system, "last_simulated_day")
	)


func _has_valid_resource_configuration() -> bool:
	return (
		_resource_world != null
		and is_instance_valid(_resource_world)
		and _has_methods(_resource_world, [
			"to_resource_dicts",
			"validate_resource_dicts",
			"restore_resource_dicts",
			"initialize_resources_at_day",
		])
	)


func _has_valid_npc_configuration() -> bool:
	return (
		_npc_economy_system != null
		and is_instance_valid(_npc_economy_system)
		and _has_methods(_npc_economy_system, [
			"to_dict", "from_dict", "validate_dict", "reset_to_profile_defaults",
		])
	)


func _has_valid_order_configuration() -> bool:
	return (
		_economy_system != null
		and is_instance_valid(_economy_system)
		and _has_methods(_economy_system, [
			"to_dict", "from_dict", "validate_dict", "reset_order_state",
		])
	)


func _has_valid_progression_configuration() -> bool:
	return (
		_progression_system != null and is_instance_valid(_progression_system)
		and _has_methods(_progression_system, [
			"to_dict", "from_dict", "validate_dict", "reset_to_new_game",
		])
	)


func _has_valid_tool_configuration() -> bool:
	return (
		_tool_system != null and is_instance_valid(_tool_system)
		and _has_methods(_tool_system, [
			"to_dict", "from_dict", "validate_dict", "reset_durability",
		])
	)


func _has_valid_production_configuration() -> bool:
	return (
		_production_system != null and is_instance_valid(_production_system)
		and _has_methods(_production_system, [
			"to_dict", "from_dict", "validate_dict", "reset_maintenance",
		])
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
