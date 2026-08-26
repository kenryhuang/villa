extends Node

## 存档系统 - JSON 格式存档/读档

signal load_completed(slot: int)
signal save_completed(slot: int)

const SAVE_DIR = "user://villa_saves/"
const SAVE_PREFIX = "save_"
const SAVE_EXT = ".json"
const BUILDING_LAYOUT_VERSION := 3
const LEGACY_BUILDING_LAYOUT_VERSIONS := [1, 2]
const LEGACY_GRID_VERSIONS := [1, 2]
const LEGACY_DEFAULT_SEASON := 0
const MIN_SEASON := 0
const MAX_SEASON := 3
const DEFAULT_INVENTORY_SLOTS := 20
const MIN_INVENTORY_SLOTS := 1
const MAX_INVENTORY_SLOTS := 100
const GameDataScript = preload("res://scripts/core/game_data.gd")
const GameStateScript = preload("res://scripts/core/game_state.gd")
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const EconomyProgressionScript = preload("res://scripts/systems/economy_progression_system.gd")
const ProductionSystemScript = preload("res://scripts/systems/production_system.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")

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
var _notification_system: Variant
var _state_transition_owner: Variant
var _farm_storage_system: Variant
var _agent_runtime: Variant
var _restore_transaction_active := false
var _restore_notification_participants: Array[Node] = []


func configure_economy(
	market_system: Variant,
	daily_simulation_system: Variant,
	season_system: Variant = null,
	resource_world: Variant = null,
	npc_economy_system: Variant = null,
	economy_system: Variant = null,
	progression_system: Variant = null,
	tool_system: Variant = null,
	production_system: Variant = null,
	notification_system: Variant = null,
	state_transition_owner: Variant = null,
	farm_storage_system: Variant = null
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
		"sync_daily_cursor", "get_current_day",
	]):
		return false
	if notification_system != null and not _has_methods(notification_system, [
		"to_dict", "from_dict", "validate_dict", "reset_notifications",
	]):
		return false
	if state_transition_owner != null and not _has_methods(
		state_transition_owner,
		["cancel_transient_actions"]
	):
		return false
	if farm_storage_system != null and not _has_methods(farm_storage_system, [
		"to_dict", "validate_dict", "restore_items_unchecked",
		"begin_restore_notification_transaction", "end_restore_notification_transaction",
		"refresh_capacity",
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
	_notification_system = notification_system
	_state_transition_owner = state_transition_owner
	_farm_storage_system = farm_storage_system
	return true


func configure_agent_runtime(agent_runtime: Variant) -> bool:
	if not _has_methods(agent_runtime, ["to_dict", "from_dict", "validate_dict"]):
		return false
	_agent_runtime = agent_runtime
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
	save_completed.emit(slot)
	return true


func _gather_save_data() -> Dictionary:
	var data := {}

	# 游戏状态
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		data["gold"] = game_state.gold
		data["harvest_seed"] = game_state.harvest_seed
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
			"max_slots": int(inventory.max_slots),
			"slots": inventory.slots,
			"quick_mappings": inventory.quick_slot_mappings,
		}
	if _has_valid_farm_storage_configuration():
		data["farm_storage"] = _farm_storage_system.call("to_dict")

	# 网格状态
	var grid_system = _get_grid_system()
	if grid_system:
		data["grid"] = grid_system.to_dict()

	# 建筑
	var building_system = _get_building_system()
	if building_system:
		data["buildings"] = _serialize_buildings(building_system)
	if grid_system != null or building_system != null:
		data["building_layout_version"] = BUILDING_LAYOUT_VERSION

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
		if _has_valid_notification_configuration():
			data["notifications"] = _notification_system.call("to_dict")
	if _has_valid_agent_configuration():
		data["agent_world"] = _agent_runtime.call("to_dict")

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
	if _restore_transaction_active:
		return false
	var migrated_value: Variant = _migrate_save_data(data)
	if not migrated_value is Dictionary:
		return false
	var migrated_data := migrated_value as Dictionary
	if not _validate_save_data(migrated_data):
		return false
	_cancel_transient_actions_for_restore()
	var previous_state := _gather_save_data().duplicate(true)
	if not _begin_restore_transaction():
		return false
	var applied := _apply_migrated_save_data(migrated_data)
	if not applied and not _apply_migrated_save_data(previous_state, false):
		push_error("Failed to roll back rejected save data")
	if applied and _has_valid_farm_storage_configuration():
		_farm_storage_system.call("refresh_capacity")
	_end_restore_transaction(applied)
	return applied


func _begin_restore_transaction() -> bool:
	if _restore_transaction_active:
		return false
	_restore_transaction_active = true
	_restore_notification_participants.clear()
	for participant in [_get_inventory_system(), _get_grid_system(), _farm_storage_system]:
		if (
			participant == null
			or not participant.has_method("begin_restore_notification_transaction")
			or not participant.has_method("end_restore_notification_transaction")
		):
			continue
		if not bool(participant.call("begin_restore_notification_transaction")):
			for begun_participant in _restore_notification_participants:
				begun_participant.call("end_restore_notification_transaction", false)
			_restore_notification_participants.clear()
			_restore_transaction_active = false
			return false
		_restore_notification_participants.append(participant)
	if (
		_production_system != null
		and is_instance_valid(_production_system)
		and _production_system.has_method("begin_restore_transaction")
	):
		_production_system.call("begin_restore_transaction")
	return true


func _end_restore_transaction(commit_changes: bool) -> void:
	if not _restore_transaction_active:
		return
	if (
		_production_system != null
		and is_instance_valid(_production_system)
		and _production_system.has_method("end_restore_transaction")
	):
		_production_system.call("end_restore_transaction")
	for participant in _restore_notification_participants:
		if is_instance_valid(participant):
			participant.call("end_restore_notification_transaction", commit_changes)
	_restore_notification_participants.clear()
	_restore_transaction_active = false


func _cancel_transient_actions_for_restore() -> void:
	if (
		_state_transition_owner != null
		and is_instance_valid(_state_transition_owner)
		and _state_transition_owner.has_method("cancel_transient_actions")
	):
		_state_transition_owner.call("cancel_transient_actions", "save_restore")


func _apply_migrated_save_data(data: Dictionary, replace_game_state := true) -> bool:
	var game_state = get_node_or_null("/root/GameState")
	if game_state and data.has("harvest_seed"):
		if not game_state.set_harvest_seed(int(data.harvest_seed)):
			return false
	if not _apply_economy_save_data(data):
		return false
	if data.has("agent_world") and (
		not _has_valid_agent_configuration()
		or not bool(_agent_runtime.call("from_dict", data["agent_world"]))
	):
		return false
	if data.has("farm_storage"):
		if (
			not _has_valid_farm_storage_configuration()
			or not bool(_farm_storage_system.call(
				"restore_items_unchecked",
				(data["farm_storage"] as Dictionary)["items"]
			))
		):
			return false

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
		inventory.max_slots = int(data.inventory.get("max_slots", DEFAULT_INVENTORY_SLOTS))
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
	if building_system != null and _has_valid_progression_configuration():
		_progression_system.call(
			"reconcile_placed_buildings",
			building_system.get_all_buildings()
		)
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

	# GameState replacement is the load commit point. Nothing below it may reject the load.
	if replace_game_state and game_state and data.has("gold"):
		if game_state.has_method("invalidate_exp_state_for_replacement"):
			game_state.invalidate_exp_state_for_replacement()
		game_state.gold = data.gold
		if data.has("player"):
			var p = data.player
			game_state.player_state.stamina = p.get("stamina", 100)
			game_state.player_state.max_stamina = p.get("max_stamina", 100)
			game_state.player_state.level = p.get("level", 1)
			game_state.player_state.exp = p.get("exp", 0)

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
	var removed := not FileAccess.file_exists(file_path) or DirAccess.remove_absolute(file_path) == OK
	var agent_manifest := save_directory.path_join("save_%d.agent-memory.json" % slot)
	if FileAccess.file_exists(agent_manifest):
		removed = DirAccess.remove_absolute(agent_manifest) == OK and removed
	return removed


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
	if (
		_state_transition_owner != null
		and is_instance_valid(_state_transition_owner)
		and _has_property(_state_transition_owner, "building_system")
	):
		var owned_building_system: Variant = _state_transition_owner.get("building_system")
		if owned_building_system is Node and is_instance_valid(owned_building_system):
			return owned_building_system
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
			and not data.has("notifications")
		)
	if not _is_integer_number(data.get("economy_version")) or int(data["economy_version"]) != 1:
		return false
	if not _has_valid_economy_configuration():
		return false
	if not data.get("market", null) is Dictionary:
		return false
	if not EconomyLimitsScript.is_safe_date(data.get("last_simulated_day")):
		return false
	if _has_injected_season_system() and not _validate_calendar_bundle(data):
		return false
	if data.has("total_days") and (
		not EconomyLimitsScript.is_safe_date(data["total_days"])
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
	if data.has("notifications") and (
		not _has_valid_notification_configuration()
		or not data["notifications"] is Dictionary
		or not bool(_notification_system.call("validate_dict", data["notifications"]))
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
	if data.has("agent_world") and (
		not _has_valid_agent_configuration()
		or not data["agent_world"] is Dictionary
		or not bool(_agent_runtime.call("validate_dict", data["agent_world"]))
	):
		return false
	var has_layout_snapshot := data.has("grid") or data.has("buildings")
	if has_layout_snapshot:
		if (
			not data.has("building_layout_version")
			or not _is_integer_number(data.get("building_layout_version"))
			or int(data["building_layout_version"]) != BUILDING_LAYOUT_VERSION
		):
			return false
	elif data.has("building_layout_version"):
		return false
	var inventory = _get_inventory_system()
	var grid_system = _get_grid_system()
	var building_system = _get_building_system()
	var has_world_snapshot_runtime := (
		inventory != null or grid_system != null or building_system != null
		or _has_valid_farm_storage_configuration()
	)
	if (
		has_layout_snapshot
		and _has_valid_farm_storage_configuration()
		and not data.has("farm_storage")
	):
		return false
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
		if _has_valid_farm_storage_configuration() and not data.has("farm_storage"):
			return false
	if data.has("grid") != data.has("buildings"):
		return false
	if data.has("gold") and (
		not _is_integer_number(data.gold) or int(data.gold) < 0
	):
		return false
	if (
		not data.has("harvest_seed")
		or not _is_integer_number(data.harvest_seed)
		or not GameStateScript.is_valid_harvest_seed(int(data.harvest_seed))
	):
		return false
	if data.has("player") and not _validate_player_save_data(data.player):
		return false
	if data.has("inventory"):
		if inventory == null or not data.inventory is Dictionary:
			return false
		var inventory_data := data.inventory as Dictionary
		if (
			not inventory_data.has("slots")
			or not inventory_data.has("quick_mappings")
			or not _integer_number_in_range(
				inventory_data.get("max_slots"),
				MIN_INVENTORY_SLOTS,
				MAX_INVENTORY_SLOTS
			)
		):
			return false
		var target_max_slots := int(inventory_data.max_slots)
		if inventory.normalize_saved_state(
			inventory_data.slots,
			inventory_data.quick_mappings,
			target_max_slots
		) == null:
			return false
		for slot_value in inventory_data.slots:
			if not slot_value is Dictionary or (slot_value as Dictionary).is_empty():
				continue
			var item_id := str((slot_value as Dictionary).get("item_id", ""))
			var definition: Variant = GameDataScript.get_item(item_id)
			if not definition is Dictionary:
				return false
			var category := str((definition as Dictionary).get("category", ""))
			if category == "crop":
				return false
			if category == "seed" and not _is_registered_plant_item(item_id):
				return false
	if data.has("farm_storage"):
		if (
			not _has_valid_farm_storage_configuration()
			or not data["farm_storage"] is Dictionary
			or not bool(_farm_storage_system.call("validate_dict", data["farm_storage"]))
		):
			return false
		for item_id in (data["farm_storage"] as Dictionary)["items"]:
			if not _is_registered_crop_id(str(item_id)):
				return false
	elif _has_valid_farm_storage_configuration() and data.has("economy_version"):
		return false
	if data.has("grid"):
		if (
			not data.grid is Dictionary
			or grid_system == null
			or not grid_system.has_method("validate_dict")
			or not bool(grid_system.validate_dict(data.grid))
		):
			return false
		for entry_value in (data.grid as Dictionary).get("cells", []):
			if (
				entry_value is Dictionary
				and (entry_value as Dictionary).has("crop")
				and not _is_registered_crop_id(str(
					((entry_value as Dictionary).crop as Dictionary).get("crop_id", "")
				))
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
	if data.has("grid") and not _validate_canonical_crop_environments(data):
		return false
	return true


func _validate_canonical_crop_environments(data: Dictionary) -> bool:
	var context_value: Variant = _greenhouse_context_from_records(
		data.get("buildings", []),
		data.get("production_upkeep", {}),
		int(data.get("total_days", data.get("last_simulated_day", 1)))
	)
	if not context_value is Dictionary:
		return false
	var context := context_value as Dictionary
	var active_cells := context.active as Dictionary
	var paused_cells := context.paused as Dictionary
	var season := int(data.get("season", 0))
	for entry_value in (data.grid as Dictionary).get("cells", []):
		if not entry_value is Dictionary:
			return false
		var entry := entry_value as Dictionary
		if not entry.has("crop"):
			continue
		var crop_record := entry.crop as Dictionary
		var crop_data = _registered_crop(str(crop_record.get("crop_id", "")))
		if crop_data == null:
			return false
		var location := Vector2i(int(entry.get("gx", -1)), int(entry.get("gz", -1)))
		var lifecycle_state := int(crop_record.get("lifecycle_state", -1))
		if paused_cells.has(location):
			continue
		if active_cells.has(location):
			if lifecycle_state == CropInstance.LifecycleState.DORMANT:
				return false
			continue
		if str(crop_data.environment) == "greenhouse_only":
			if lifecycle_state != CropInstance.LifecycleState.WITHERED:
				return false
			continue
		var allowed_season: bool = (crop_data.seasons as Array).is_empty() or season in crop_data.seasons
		if allowed_season:
			if lifecycle_state == CropInstance.LifecycleState.DORMANT:
				return false
		elif str(crop_data.lifecycle_type) in ["annual", "annual_regrow"]:
			if lifecycle_state != CropInstance.LifecycleState.WITHERED:
				return false
		elif str(crop_data.lifecycle_type) in ["bush", "tree", "vine"]:
			if lifecycle_state != CropInstance.LifecycleState.DORMANT:
				return false
		else:
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
	for field in ["maintenance", "speed_accumulators", "repairing"]:
		for value in upkeep.get(field, []):
			if not valid_keys.has(str((value as Dictionary).get("building_key", ""))):
				return false
	return true


func _finalize_committed_load() -> void:
	if get_tree() == null:
		return
	for production_system in get_tree().get_nodes_in_group("production_system"):
		if (
			production_system == _production_system
			and production_system.has_method("end_restore_transaction")
		):
			continue
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
	var production_day_before := 0
	if _has_valid_production_configuration():
		production_before = _production_system.call("to_dict")
		production_day_before = int(_production_system.call("get_current_day"))
	var notifications_before: Dictionary = {}
	if _has_valid_notification_configuration():
		notifications_before = _notification_system.call("to_dict")
	var loaded_day := maxi(int(data.get("total_days", data.get("last_simulated_day", 1))), 0)
	var applied := true
	if data.has("economy_version"):
		if _market_system.has_method("restore_from_dict_with_current_catalog"):
			applied = bool(_market_system.call(
				"restore_from_dict_with_current_catalog",
				data["market"]
			))
		else:
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
			if applied:
				applied = bool(_production_system.call("sync_daily_cursor", loaded_day))
		if applied and _has_valid_notification_configuration():
			if data.has("notifications"):
				applied = bool(_notification_system.call("from_dict", data["notifications"]))
			else:
				_notification_system.call("reset_notifications")
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
				applied = bool(_production_system.call("sync_daily_cursor", loaded_day))
		if applied and _has_valid_notification_configuration():
			_notification_system.call("reset_notifications")
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
			_production_system.call("sync_daily_cursor", production_day_before)
		if _has_valid_notification_configuration() and not notifications_before.is_empty():
			_notification_system.call("from_dict", notifications_before)
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
	if not migrated.has("economy_version") and not _prevalidate_calendar(migrated):
		return null
	var has_layout_version := migrated.has("building_layout_version")
	var layout_version_value: Variant = migrated.get("building_layout_version")
	var is_legacy_layout := false
	if has_layout_version:
		if not _is_integer_number(layout_version_value):
			return null
		var layout_version := int(layout_version_value)
		if layout_version == BUILDING_LAYOUT_VERSION:
			# Season-less v3 snapshots remain compatible only when no crop depends on it.
			if (
				(_save_grid_has_crop_records(migrated.get("grid")) or migrated.has("season"))
				and not _valid_explicit_season(migrated.get("season"))
			):
				return null
			if migrated.has("farm_storage") and not _normalize_canonical_farm_storage(migrated):
				return null
			return _normalize_inventory_migrations(migrated)
		if layout_version not in LEGACY_BUILDING_LAYOUT_VERSIONS:
			return null
		is_legacy_layout = true
	if not migrated.has("harvest_seed"):
		migrated["harvest_seed"] = GameStateScript.LEGACY_HARVEST_SEED
	if is_legacy_layout:
		if not _prevalidate_legacy_lifecycle_structure(migrated):
			return null
		if not migrated.has("season"):
			migrated["season"] = LEGACY_DEFAULT_SEASON
		return _migrate_legacy_lifecycle_save(migrated)
	if migrated.has("inventory"):
		if migrated.has("farm_storage"):
			if not _normalize_canonical_farm_storage(migrated):
				return null
			return _normalize_inventory_migrations(migrated)
		var inventory_result: Variant = _migrate_legacy_inventory(migrated["inventory"])
		if not inventory_result is Dictionary:
			return null
		migrated["inventory"] = (inventory_result as Dictionary).inventory
		var farm_items := (inventory_result as Dictionary).farm_storage_items as Dictionary
		if _has_valid_farm_storage_configuration():
			migrated["farm_storage"] = {"items": farm_items}
		elif not farm_items.is_empty():
			return null
		return migrated
	if _has_valid_farm_storage_configuration():
		return null
	return _normalize_inventory_migrations(migrated)


func _normalize_canonical_farm_storage(data: Dictionary) -> bool:
	var storage_value: Variant = data.get("farm_storage")
	if (
		not storage_value is Dictionary
		or (storage_value as Dictionary).size() != 1
		or not (storage_value as Dictionary).get("items") is Dictionary
	):
		return false
	var normalized_items := {}
	for item_id in (storage_value as Dictionary).items:
		var quantity: Variant = (storage_value as Dictionary).items[item_id]
		if (
			typeof(item_id) != TYPE_STRING
			or not _is_integer_number(quantity)
			or float(quantity) <= 0.0
			or float(quantity) > float(EconomyLimitsScript.MAX_SAFE_INTEGER)
		):
			return false
		normalized_items[item_id] = int(quantity)
	data["farm_storage"] = {"items": normalized_items}
	return true


func _prevalidate_legacy_lifecycle_structure(data: Dictionary) -> bool:
	if (
		data.has("farm_storage")
		or not data.get("inventory") is Dictionary
		or not _prevalidate_calendar(data)
		or not _prevalidate_legacy_buildings(data.get("buildings"))
		or not _prevalidate_legacy_grid(data.get("grid"))
	):
		return false
	if data.has("production_upkeep"):
		if (
			not data.production_upkeep is Dictionary
			or not _has_valid_production_configuration()
			or not bool(_production_system.call("validate_dict", data.production_upkeep))
		):
			return false
	return true


func _prevalidate_calendar(data: Dictionary) -> bool:
	if data.has("season") and not _valid_explicit_season(data.season):
		return false
	for field in ["total_days", "last_simulated_day"]:
		if data.has(field) and not EconomyLimitsScript.is_safe_date(data[field], false):
			return false
	if (
		data.has("total_days")
		and data.has("last_simulated_day")
		and float(data.total_days) != float(data.last_simulated_day)
	):
		return false
	for field_and_range in [["day", 1, 7], ["hour", 0, 23], ["minute", 0, 59]]:
		var field := str(field_and_range[0])
		if data.has(field) and not _integer_number_in_range(
			data[field], int(field_and_range[1]), int(field_and_range[2])
		):
			return false
	return true


func _prevalidate_legacy_buildings(value: Variant) -> bool:
	if not value is Array:
		return false
	for record_value in value:
		if not record_value is Dictionary:
			return false
		var record := record_value as Dictionary
		if typeof(record.get("building_id")) != TYPE_STRING:
			return false
		var definition: Dictionary = GameDataScript.get_building(record.building_id)
		if definition.is_empty():
			return false
		if not _valid_grid_integer(record.get("gx")) or not _valid_grid_integer(record.get("gz")):
			return false
		var gx := int(record.gx)
		var gz := int(record.gz)
		var width := int(definition.get("footprint_x", 1))
		var depth := int(definition.get("footprint_z", 1))
		if (
			gx < 0 or gz < 0
			or gx + width > GridSystemScript.GRID_WIDTH
			or gz + depth > GridSystemScript.GRID_DEPTH
		):
			return false
		if not record.get("occupied_cells") is Array:
			return false
		for occupied_value in record.occupied_cells:
			if not occupied_value is Dictionary:
				return false
			var occupied := occupied_value as Dictionary
			if (
				not _valid_bounded_grid_location(occupied.get("gx"), occupied.get("gz"))
				or not _integer_number_in_range(
					occupied.get("previous_state"),
					GridCell.State.WASTELAND,
					GridCell.State.DECORATION
				)
			):
				return false
		var construction_fields := [
			"construction_stage", "construction_elapsed", "construction_duration",
		]
		var construction_count := 0
		for field in construction_fields:
			if record.has(field):
				construction_count += 1
		if construction_count not in [0, construction_fields.size()]:
			return false
		if construction_count == construction_fields.size() and (
			not _integer_number_in_range(
				record.construction_stage,
				BuildingInstance.ConstructionStage.FOUNDATION,
				BuildingInstance.ConstructionStage.COMPLETE
			)
			or not _finite_number_in_range(
				record.construction_elapsed, 0.0, float(EconomyLimitsScript.MAX_SAFE_INTEGER)
			)
			or not _finite_number_in_range(
				record.construction_duration, 0.0, float(EconomyLimitsScript.MAX_SAFE_INTEGER)
			)
		):
			return false
	return true


func _prevalidate_legacy_grid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var grid_data := value as Dictionary
	if (
		grid_data.size() != 2
		or not _integer_number_in_range(grid_data.get("version"), 1, 2)
		or not grid_data.get("cells") is Array
	):
		return false
	var seen := {}
	for entry_value in grid_data.cells:
		if not entry_value is Dictionary:
			return false
		var entry := entry_value as Dictionary
		if (
			not _valid_bounded_grid_location(entry.get("gx"), entry.get("gz"))
			or not _integer_number_in_range(
				entry.get("state"), GridCell.State.WASTELAND, GridCell.State.DECORATION
			)
			or typeof(entry.get("watered")) != TYPE_BOOL
		):
			return false
		var location := Vector2i(int(entry.gx), int(entry.gz))
		if seen.has(location):
			return false
		seen[location] = true
		var has_crop := entry.has("crop")
		if has_crop != (int(entry.state) == GridCell.State.PLANTED):
			return false
		if not has_crop:
			continue
		if not _prevalidate_legacy_crop(entry.crop):
			return false
	return true


func _prevalidate_legacy_crop(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var crop := value as Dictionary
	for field in ["crop_id", "growth_progress", "is_watered_today", "harvest_count"]:
		if not crop.has(field):
			return false
	if typeof(crop.crop_id) != TYPE_STRING:
		return false
	var crop_data = _registered_crop(crop.crop_id)
	if crop_data == null:
		return false
	if (
		not _finite_number_in_range(
			crop.growth_progress, 0.0, float(crop_data.growth_days)
		)
		or typeof(crop.is_watered_today) != TYPE_BOOL
		or not EconomyLimitsScript.is_safe_due_date(crop.harvest_count)
	):
		return false
	if crop.has("lifecycle_state") and not _integer_number_in_range(
		crop.lifecycle_state,
		CropInstance.LifecycleState.GROWING,
		CropInstance.LifecycleState.WITHERED
	):
		return false
	return true


func _valid_explicit_season(value: Variant) -> bool:
	return _integer_number_in_range(value, MIN_SEASON, MAX_SEASON)


func _save_grid_has_crop_records(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var cells: Variant = (value as Dictionary).get("cells")
	if not cells is Array:
		return false
	for entry in cells:
		if entry is Dictionary and (entry as Dictionary).has("crop"):
			return true
	return false


func _valid_grid_integer(value: Variant) -> bool:
	return (
		_is_integer_number(value)
		and float(value) >= 0.0
		and float(value) <= float(EconomyLimitsScript.MAX_SAFE_INTEGER)
	)


func _valid_bounded_grid_location(gx_value: Variant, gz_value: Variant) -> bool:
	return (
		_valid_grid_integer(gx_value)
		and _valid_grid_integer(gz_value)
		and float(gx_value) < float(GridSystemScript.GRID_WIDTH)
		and float(gz_value) < float(GridSystemScript.GRID_DEPTH)
	)


func _integer_number_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		_is_integer_number(value)
		and float(value) >= float(minimum)
		and float(value) <= float(maximum)
	)


func _finite_number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and float(value) >= minimum
		and float(value) <= maximum
	)


func _normalize_inventory_migrations(migrated: Dictionary) -> Variant:
	var inventory_value: Variant = migrated.get("inventory")
	if inventory_value == null:
		return migrated
	if not inventory_value is Dictionary:
		return null
	var inventory_data := inventory_value as Dictionary
	if not inventory_data.has("slots") or not inventory_data.has("quick_mappings"):
		return null
	var target_max_slots_value: Variant = inventory_data.get(
		"max_slots", DEFAULT_INVENTORY_SLOTS
	)
	if not _integer_number_in_range(
		target_max_slots_value,
		MIN_INVENTORY_SLOTS,
		MAX_INVENTORY_SLOTS
	):
		return null
	var target_max_slots := int(target_max_slots_value)
	var inventory = _get_inventory_system()
	if inventory == null or not inventory.has_method("normalize_saved_state"):
		return null
	var normalized: Variant = inventory.normalize_saved_state(
		inventory_data.slots,
		inventory_data.quick_mappings,
		target_max_slots
	)
	if not normalized is Dictionary:
		return null
	(normalized as Dictionary)["max_slots"] = target_max_slots
	migrated["inventory"] = normalized
	return migrated


func _migrate_legacy_lifecycle_save(migrated: Dictionary) -> Variant:
	if (
		migrated.has("farm_storage")
		or not migrated.get("inventory") is Dictionary
		or not migrated.get("grid") is Dictionary
		or not migrated.get("buildings") is Array
	):
		return null
	var canonical_buildings: Variant = _canonicalize_legacy_buildings(
		migrated["buildings"]
	)
	if not canonical_buildings is Array:
		return null
	var has_legacy_progression := migrated.has("progression")
	var canonical_progression: Variant = {}
	if has_legacy_progression:
		canonical_progression = _canonicalize_legacy_progression(migrated["progression"])
		if not canonical_progression is Dictionary:
			return null
	var grid_data := migrated["grid"] as Dictionary
	if (
		grid_data.size() != 2
		or not _is_integer_number(grid_data.get("version"))
		or int(grid_data["version"]) not in LEGACY_GRID_VERSIONS
		or not grid_data.get("cells") is Array
	):
		return null
	var capacity_context: Variant = _legacy_farm_storage_capacity(
		canonical_buildings,
		canonical_progression if canonical_progression is Dictionary else {}
	)
	if capacity_context == null:
		return null
	var inventory_result: Variant = _migrate_legacy_inventory(migrated["inventory"])
	if not inventory_result is Dictionary:
		return null
	var canonical_grid: Variant = _migrate_legacy_grid(
		grid_data,
		canonical_buildings,
		migrated.get("production_upkeep", {}),
		int(migrated.get("season", 0)),
		int(migrated.get("total_days", migrated.get("last_simulated_day", 1)))
	)
	if not canonical_grid is Dictionary:
		return null
	migrated["inventory"] = (inventory_result as Dictionary)["inventory"]
	migrated["buildings"] = canonical_buildings
	if has_legacy_progression:
		migrated["progression"] = canonical_progression
	migrated["farm_storage"] = {
		"items": (inventory_result as Dictionary)["farm_storage_items"],
	}
	migrated["grid"] = canonical_grid
	migrated["building_layout_version"] = BUILDING_LAYOUT_VERSION
	return migrated


func _canonicalize_legacy_buildings(value: Variant) -> Variant:
	if not value is Array:
		return null
	var canonical: Array = (value as Array).duplicate(true)
	for record_value in canonical:
		if not record_value is Dictionary:
			return null
		var record := record_value as Dictionary
		var construction_fields := [
			"construction_stage", "construction_elapsed", "construction_duration",
		]
		var field_count := 0
		for field in construction_fields:
			if record.has(field):
				field_count += 1
		if field_count == 0:
			var definition: Dictionary = GameDataScript.get_building(
				str(record.get("building_id", ""))
			)
			if definition.is_empty():
				return null
			var footprint := Vector2i(
				int(definition.get("footprint_x", 1)),
				int(definition.get("footprint_z", 1))
			)
			var duration := BuildingInstance.construction_duration_for(footprint)
			record["construction_stage"] = int(BuildingInstance.ConstructionStage.COMPLETE)
			record["construction_elapsed"] = duration
			record["construction_duration"] = duration
		elif field_count != construction_fields.size():
			return null
	return canonical


func _canonicalize_legacy_progression(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var temporary := EconomyProgressionScript.new()
	if not temporary.from_dict(value):
		temporary.free()
		return null
	var canonical: Dictionary = temporary.to_dict()
	temporary.free()
	return canonical


func _migrate_legacy_inventory(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var source := value as Dictionary
	if (
		source.size() not in [2, 3]
		or not source.get("slots") is Array
		or not source.get("quick_mappings") is Array
	):
		return null
	if source.size() == 3 and not source.has("max_slots"):
		return null
	var target_max_slots_value: Variant = source.get(
		"max_slots", DEFAULT_INVENTORY_SLOTS
	)
	if not _integer_number_in_range(
		target_max_slots_value,
		MIN_INVENTORY_SLOTS,
		MAX_INVENTORY_SLOTS
	):
		return null
	var target_max_slots := int(target_max_slots_value)
	var inventory = _get_inventory_system()
	if inventory == null or not inventory.has_method("normalize_saved_state"):
		return null
	var slots := (source["slots"] as Array).duplicate(true)
	var mappings_source := source["quick_mappings"] as Array
	if slots.size() > target_max_slots or mappings_source.size() != 6:
		return null
	var sanitized_mappings: Array[int] = []
	for mapping_value in mappings_source:
		if not _is_integer_number(mapping_value):
			return null
		var mapped_index := int(mapping_value)
		if mapped_index < 0 or mapped_index >= slots.size():
			sanitized_mappings.append(-1)
		elif slots[mapped_index] is Dictionary and (slots[mapped_index] as Dictionary).is_empty():
			sanitized_mappings.append(-1)
		else:
			sanitized_mappings.append(mapped_index)
	var normalized_source: Variant = inventory.call(
		"normalize_saved_state", slots, sanitized_mappings, target_max_slots
	)
	if not normalized_source is Dictionary:
		return null
	slots = ((normalized_source as Dictionary).slots as Array).duplicate(true)
	var normalized_mappings := ((normalized_source as Dictionary).quick_mappings as Array).duplicate()
	var farm_items: Dictionary = {}
	var removed_indices := {}
	for index in range(slots.size()):
		var slot_value: Variant = slots[index]
		if not slot_value is Dictionary:
			return null
		var slot := slot_value as Dictionary
		if slot.is_empty():
			continue
		if slot.size() != 2 or typeof(slot.get("item_id")) != TYPE_STRING:
			return null
		var item_id := str(slot["item_id"])
		var definition: Variant = GameDataScript.get_item(item_id)
		if not definition is Dictionary:
			return null
		if (definition as Dictionary).get("category") != "crop":
			continue
		var quantity := int(slot["quantity"])
		if not _is_registered_crop_id(item_id):
			return null
		var previous := int(farm_items.get(item_id, 0))
		if quantity > EconomyLimitsScript.MAX_SAFE_INTEGER - previous:
			return null
		farm_items[item_id] = previous + quantity
		slots[index] = {}
		removed_indices[index] = true
	var mappings: Array[int] = []
	for mapping_value in normalized_mappings:
		var mapped_index := int(mapping_value)
		if (
			mapped_index < 0
			or mapped_index >= slots.size()
			or removed_indices.has(mapped_index)
			or not slots[mapped_index] is Dictionary
			or (slots[mapped_index] as Dictionary).is_empty()
		):
			mappings.append(-1)
		else:
			mappings.append(mapped_index)
	return {
		"inventory": {
			"max_slots": target_max_slots,
			"slots": slots,
			"quick_mappings": mappings,
		},
		"farm_storage_items": farm_items,
	}


func _migrate_legacy_grid(
	grid_data: Dictionary,
	building_values: Variant,
	production_upkeep: Variant,
	season: int,
	loaded_day: int
) -> Variant:
	var greenhouse_context: Variant = _greenhouse_context_from_records(
		building_values, production_upkeep, loaded_day
	)
	if not greenhouse_context is Dictionary:
		return null
	var protected_cells := (greenhouse_context as Dictionary).active as Dictionary
	for location in (greenhouse_context as Dictionary).paused:
		protected_cells[location] = true
	var canonical := {"version": 3, "cells": (grid_data["cells"] as Array).duplicate(true)}
	for entry_value in canonical.cells:
		if not entry_value is Dictionary:
			return null
		var entry := entry_value as Dictionary
		if not entry.has("crop"):
			continue
		if not entry.crop is Dictionary:
			return null
		var crop := entry.crop as Dictionary
		for field in ["crop_id", "growth_progress", "is_watered_today", "harvest_count"]:
			if not crop.has(field):
				return null
		if typeof(crop.crop_id) != TYPE_STRING:
			return null
		var crop_data = _registered_crop(str(crop.crop_id))
		if crop_data == null:
			return null
		var progress_value: Variant = crop.growth_progress
		if (
			not _is_number(progress_value)
			or not is_finite(float(progress_value))
			or float(progress_value) < 0.0
			or float(progress_value) > float(crop_data.growth_days)
		):
			return null
		var location := Vector2i(int(entry.get("gx", -1)), int(entry.get("gz", -1)))
		var lifecycle := CropInstance.LifecycleState.GROWING
		if protected_cells.has(location):
			lifecycle = (
				CropInstance.LifecycleState.MATURE
				if float(progress_value) >= float(crop_data.growth_days)
				else CropInstance.LifecycleState.GROWING
			)
		elif str(crop_data.environment) == "greenhouse_only":
			lifecycle = CropInstance.LifecycleState.WITHERED
		elif (crop_data.seasons as Array).is_empty() or season in crop_data.seasons:
			lifecycle = (
				CropInstance.LifecycleState.MATURE
				if float(progress_value) >= float(crop_data.growth_days)
				else CropInstance.LifecycleState.GROWING
			)
		elif str(crop_data.lifecycle_type) in ["annual", "annual_regrow"]:
			lifecycle = CropInstance.LifecycleState.WITHERED
		else:
			lifecycle = CropInstance.LifecycleState.DORMANT
		crop["lifecycle_state"] = lifecycle
	return canonical


func _greenhouse_context_from_records(
	building_values: Variant,
	production_upkeep: Variant,
	loaded_day: int
) -> Variant:
	if not building_values is Array or not production_upkeep is Dictionary:
		return null
	var upkeep := production_upkeep as Dictionary
	var maintenance_records: Variant = upkeep.get("maintenance", [])
	var repairing_records: Variant = upkeep.get("repairing", [])
	if not maintenance_records is Array or not repairing_records is Array:
		return null
	var due_days := {}
	for value in maintenance_records:
		if not value is Dictionary:
			return null
		var record := value as Dictionary
		var key := str(record.get("building_key", ""))
		if key.is_empty() or due_days.has(key) or not _is_integer_number(record.get("due_day")):
			return null
		due_days[key] = int(record.due_day)
	var repairing := {}
	for value in repairing_records:
		if not value is Dictionary:
			return null
		var record := value as Dictionary
		var key := str(record.get("building_key", ""))
		if key.is_empty() or repairing.has(key) or not due_days.has(key):
			return null
		repairing[key] = true
	var active := {}
	var paused := {}
	for value in building_values:
		if not value is Dictionary:
			return null
		var record := value as Dictionary
		if str(record.get("building_id", "")) != "greenhouse":
			continue
		var stage_value: Variant = record.get("construction_stage", 3)
		if not _is_integer_number(stage_value) or int(stage_value) != 3:
			continue
		if not _is_integer_number(record.get("gx")) or not _is_integer_number(record.get("gz")):
			return null
		var definition := GameDataScript.get_building("greenhouse")
		var gx := int(record.gx)
		var gz := int(record.gz)
		var building_key := "greenhouse:%d:%d" % [gx, gz]
		var maintenance_paused := (
			repairing.has(building_key)
			or (due_days.has(building_key) and int(due_days[building_key]) - loaded_day <= 0)
		)
		var destination := paused if maintenance_paused else active
		var width := int(definition.get("footprint_x", 3))
		var depth := int(definition.get("footprint_z", 3))
		for x in range(gx, gx + width):
			destination[Vector2i(x, gz - 1)] = true
			destination[Vector2i(x, gz + depth)] = true
		destination[Vector2i(gx - 1, gz + depth / 2)] = true
		destination[Vector2i(gx + width, gz + depth / 2)] = true
	for location in active:
		paused.erase(location)
	return {"active": active, "paused": paused}


func _legacy_farm_storage_capacity(building_values: Variant, progression: Variant) -> Variant:
	if not building_values is Array or not progression is Dictionary:
		return null
	var levels_by_key := {}
	var upgrade_values: Variant = (progression as Dictionary).get("upgrade_levels", [])
	if not upgrade_values is Array:
		return null
	for value in upgrade_values:
		if not value is Dictionary:
			return null
		var record := value as Dictionary
		var levels := {}
		if not record.get("levels", []) is Array:
			return null
		for level_value in record.get("levels", []):
			if not level_value is Dictionary:
				return null
			levels[str((level_value as Dictionary).get("upgrade_id", ""))] = int((level_value as Dictionary).get("level", 0))
		levels_by_key[str(record.get("building_key", ""))] = levels
	var capacity := 200
	for value in building_values:
		if not value is Dictionary:
			return null
		var building := value as Dictionary
		if str(building.get("building_id", "")) != "barn":
			continue
		if not _is_integer_number(building.get("construction_stage", 3)):
			return null
		if int(building.get("construction_stage", 3)) != 3:
			continue
		var key := "barn:%d:%d" % [int(building.get("gx", 0)), int(building.get("gz", 0))]
		capacity += 200 + clampi(int((levels_by_key.get(key, {}) as Dictionary).get("storage", 0)), 0, 3) * 100
	return capacity


func _registered_crop(crop_id: String) -> Variant:
	var game_data = get_node_or_null("/root/GameData")
	return game_data.get_crop(crop_id) if game_data != null else null


func _is_registered_crop_id(crop_id: String) -> bool:
	var crop = _registered_crop(crop_id)
	if crop == null or str(crop.crop_id) != crop_id:
		return false
	var game_data = get_node_or_null("/root/GameData")
	return game_data.get_crop_for_plant_item(str(crop.plant_item_id)) == crop


func _is_registered_plant_item(item_id: String) -> bool:
	var game_data = get_node_or_null("/root/GameData")
	if game_data == null:
		return false
	var crop = game_data.get_crop_for_plant_item(item_id)
	return (
		crop != null
		and str(crop.plant_item_id) == item_id
		and game_data.get_crop(str(crop.crop_id)) == crop
	)


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _has_valid_farm_storage_configuration() -> bool:
	return (
		_farm_storage_system != null
		and is_instance_valid(_farm_storage_system)
		and _has_methods(_farm_storage_system, [
			"to_dict", "validate_dict", "restore_items_unchecked",
			"begin_restore_notification_transaction", "end_restore_notification_transaction",
			"refresh_capacity",
		])
	)


func manages_farm_storage(storage: Variant) -> bool:
	return _has_valid_farm_storage_configuration() and _farm_storage_system == storage


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
			"reconcile_placed_buildings",
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
			"sync_daily_cursor", "get_current_day",
		])
	)


func _has_valid_notification_configuration() -> bool:
	return (
		_notification_system != null
		and is_instance_valid(_notification_system)
		and _has_methods(_notification_system, [
			"to_dict", "from_dict", "validate_dict", "reset_notifications",
		])
	)


func _has_valid_agent_configuration() -> bool:
	return (
		_agent_runtime != null
		and is_instance_valid(_agent_runtime)
		and _has_methods(_agent_runtime, ["to_dict", "from_dict", "validate_dict"])
	)


func _has_injected_season_system() -> bool:
	return _season_system != null and is_instance_valid(_season_system)


func _validate_calendar_bundle(data: Dictionary) -> bool:
	for field in ["season", "day", "total_days", "hour", "minute"]:
		if not data.has(field) or not _is_integer_number(data[field]):
			return false
	var total_days := int(data["total_days"])
	if not EconomyLimitsScript.is_safe_date(total_days, false):
		return false
	var elapsed_days := total_days - 1
	var expected_day := elapsed_days % 7 + 1
	var expected_season := floori(float(elapsed_days % 28) / 7.0)
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
