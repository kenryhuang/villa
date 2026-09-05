class_name Farm3DSession
extends Node

const FlatGridScript = preload("res://scripts/farm3d/flat_grid.gd")
const CropVisualSystemScript = preload("res://scripts/farm3d/crop_visual_system.gd")
const CropCatalogScript = preload("res://scripts/core/crop_catalog.gd")
const FarmingSystemScript = preload("res://scripts/farm3d/farm3d_farming_system.gd")
const SeasonSystemScript = preload("res://scripts/systems/season_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const ToolSystemScript = preload("res://scripts/systems/tool_system.gd")
const ActionControllerScript = preload("res://scripts/actors/player_action_controller.gd")

const ACTION_RANGE := 2.6
const SAVE_VERSION := 1

@export var auto_restore := true
@export var auto_save := true
@export var save_path := "user://farm_3d_save.json"

var grid: GridSystem
var farming: FarmingSystem
var season: SeasonSystem
var inventory: InventorySystem
var tools: ToolSystem
var action_controller: PlayerActionController
var visuals: Node3D
var player: Node3D


func configure(next_player: Node3D) -> bool:
	if next_player == null:
		return false
	player = next_player
	_ensure_grain_registered()
	visuals = CropVisualSystemScript.new()
	visuals.name = "Farm3DVisuals"
	add_child(visuals)
	grid = FlatGridScript.new()
	grid.name = "Farm3DFlatGrid"
	add_child(grid)
	grid.configure_flat(visuals)
	season = SeasonSystemScript.new()
	add_child(season)
	farming = FarmingSystemScript.new()
	add_child(farming)
	farming.visual_adapter = visuals
	farming.configure(grid, season, _game_state())
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null and event_bus.has_signal("day_changed"):
		event_bus.day_changed.connect(farming.on_day_changed)
	inventory = InventorySystemScript.new()
	add_child(inventory)
	tools = ToolSystemScript.new()
	add_child(tools)
	tools.configure(grid, inventory, player, farming)
	action_controller = ActionControllerScript.new()
	add_child(action_controller)
	action_controller.configure(player, grid, farming, null, tools, inventory, null)
	action_controller.set_process(false)
	action_controller.set_process_input(false)
	action_controller.set_process_unhandled_input(false)
	action_controller.switch_mode(PlayerActionController.ActionMode.FARMING)
	action_controller.set_selected_plant_item_id("grain_seed")
	if auto_restore and load_game():
		return true
	_grant_initial_state()
	return true


func act(cell: GridCell, mode: String) -> Dictionary:
	if cell == null:
		return _failure("invalid_cell")
	if not _in_range(cell):
		return _failure("out_of_range")
	if mode in ["hoe", "seed", "water"] and cell.crop_instance != null and cell.crop_instance.is_mature():
		return _failure("crop_mature")
	var result: Dictionary
	match mode:
		"hoe":
			var tool_failure := _tool_failure("hoe")
			if not tool_failure.is_empty():
				return _failure(tool_failure)
			var clearing: bool = cell.crop_instance != null and cell.crop_instance.lifecycle_state == CropInstance.LifecycleState.WITHERED
			action_controller.select_slot(0)
			result = _result(action_controller.perform_cell_action(cell), "已清理枯萎作物" if clearing else "已开垦地块")
		"seed":
			action_controller.set_selected_plant_item_id("grain_seed")
			action_controller.select_slot(PlayerActionController.SEED_SLOT)
			result = _result(action_controller.perform_cell_action(cell), "已播种谷物", _plant_failure_reason())
		"water":
			var water_failure := _tool_failure("watering_can")
			if not water_failure.is_empty():
				return _failure(water_failure)
			action_controller.select_slot(1)
			result = _result(action_controller.perform_cell_action(cell), "已浇水")
		"harvest":
			result = _harvest_or_clear(cell)
		_:
			return _failure("invalid_mode")
	if result.ok and auto_save:
		save_game()
	return result


func rest() -> Dictionary:
	season.advance_to_next_day()
	var state := _game_state()
	if state != null and state.player_state != null:
		state.player_state.stamina = state.player_state.max_stamina
	if auto_save:
		save_game()
	return {"ok": true, "reason": "", "message": "已休息至次日"}


func save_game() -> bool:
	if grid == null or inventory == null or season == null or tools == null:
		return false
	var temporary_path := save_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	var state := _game_state()
	var stamina := int(state.player_state.stamina) if state != null and state.player_state != null else 100
	var experience := int(state.player_state.exp) if state != null and state.player_state != null else 0
	var level := int(state.player_state.level) if state != null and state.player_state != null else 1
	var harvest_seed := int(state.harvest_seed) if state != null else 42
	var data := {
		"version": SAVE_VERSION,
		"grid": grid.to_dict(),
		"inventory": {"slots": inventory.slots, "quick": inventory.quick_slot_mappings},
		"season": {"season": season.current_season, "day": season.current_day, "total_days": season.total_days, "hour": season.hour, "minute": season.minute},
		"tools": tools.to_dict(),
		"stamina": stamina,
		"experience": experience,
		"level": level,
		"harvest_seed": harvest_seed,
	}
	file.store_string(JSON.stringify(data))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(save_path)) == OK


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return false
	var parsed = json.data
	if not _valid_save(parsed):
		return false
	var data: Dictionary = parsed
	var normalized = inventory.normalize_saved_state(data.inventory.slots, data.inventory.quick)
	if normalized == null:
		return false
	# All validation completed before any live state changes.
	if not grid.from_dict(data.grid) or not tools.from_dict(data.tools):
		return false
	inventory.restore_state(normalized.slots, normalized.quick_mappings)
	season.current_season = int(data.season.season) as SeasonSystem.Season
	season.current_day = int(data.season.day)
	season.total_days = int(data.season.total_days)
	season.hour = int(data.season.hour)
	season.minute = int(data.season.minute)
	var state := _game_state()
	if state != null and state.player_state != null:
		state.player_state.stamina = int(data.stamina)
		state.player_state.exp = int(data.experience)
		state.player_state.level = int(data.level)
		state.harvest_seed = int(data.harvest_seed)
	farming.sync_growth_clock()
	return true


func _harvest_or_clear(cell: GridCell) -> Dictionary:
	if cell.crop_instance != null and cell.crop_instance.lifecycle_state == CropInstance.LifecycleState.WITHERED:
		return _result(farming.clear_withered(cell), "已清理枯萎作物")
	var preview := farming.preview_harvest(cell)
	if preview.is_empty():
		return _failure("not_mature")
	var items: Dictionary = preview.get("items", {})
	for item_id in items:
		if not inventory.can_add_item(str(item_id), int(items[item_id])):
			return _failure("inventory_full")
	var inventory_snapshot := {"slots": inventory.slots.duplicate(true), "quick": inventory.quick_slot_mappings.duplicate()}
	var owns_notification_transaction := inventory.begin_restore_notification_transaction()
	var token = farming.prepare_harvest(cell, preview)
	if token == null or not farming.apply_prepared_harvest(token):
		if token != null:
			farming.rollback_prepared_harvest(token)
		if owns_notification_transaction:
			inventory.end_restore_notification_transaction(false)
		return _failure("transaction_failed")
	for item_id in items:
		if not inventory.add_item(str(item_id), int(items[item_id])):
			farming.rollback_prepared_harvest(token)
			inventory.restore_state(inventory_snapshot.slots, inventory_snapshot.quick)
			if owns_notification_transaction:
				inventory.end_restore_notification_transaction(false)
			return _failure("inventory_full")
	var publication = farming.seal_prepared_harvest(token)
	if publication == null or not farming.can_arm_harvest_publication(publication):
		if publication == null:
			farming.rollback_prepared_harvest(token)
		else:
			farming.cancel_harvest_publication(publication)
		inventory.restore_state(inventory_snapshot.slots, inventory_snapshot.quick)
		if owns_notification_transaction:
			inventory.end_restore_notification_transaction(false)
		return _failure("transaction_failed")
	farming.arm_harvest_publication(publication)
	farming.publish_harvest_publication(publication)
	if owns_notification_transaction:
		inventory.end_restore_notification_transaction(true)
	return {"ok": true, "reason": "", "message": "已收获谷物", "items": items.duplicate(true)}


func _grant_initial_state() -> void:
	inventory.add_item("grain_seed", 99)
	for base_x in [19, 22, 25]:
		for base_z in [12, 9, 6]:
			for gx in [base_x, base_x + 1]:
				for gz in [base_z, base_z - 1]:
					var cell := grid.get_cell(gx, gz)
					grid.set_cell_state(gx, gz, GridCell.State.FARMLAND)
					# Left column stays as empty examples.  The middle has young
					# crops and the right demonstrates fully mature grain.
					if base_x == 22 and (gx + gz) % 2 == 0:
						var young := farming.commit_plant(cell, "grain_seed", farming.preview_plant(cell, "grain_seed"))
						if young != null:
							young.set_growth_state(1.5, CropInstance.LifecycleState.GROWING)
					elif base_x == 25:
						var mature := farming.commit_plant(cell, "grain_seed", farming.preview_plant(cell, "grain_seed"))
						if mature != null:
							mature.set_growth_state(float(mature.crop_data.growth_days), CropInstance.LifecycleState.MATURE)
	visuals.rebuild(grid._cells.values())


func _ensure_grain_registered() -> void:
	var data = get_node_or_null("/root/GameData")
	if data != null and data.get_crop("grain") == null:
		data.register_crop(CropCatalogScript.grain_definition())


func _in_range(cell: GridCell) -> bool:
	if player == null:
		return false
	var position := player.global_position if player.is_inside_tree() else player.position
	return Vector2(position.x, position.z).distance_to(cell.world_position()) <= ACTION_RANGE


func _plant_failure_reason() -> String:
	var details := action_controller.get_last_plant_failure_details()
	return str(details.get("reason", "plant_failed"))


func _result(ok: bool, success_message: String, failure_reason: String = "action_failed") -> Dictionary:
	return {"ok": ok, "reason": "" if ok else failure_reason, "message": success_message if ok else _message_for(failure_reason)}


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": _message_for(reason)}


func _message_for(reason: String) -> String:
	return {
		"invalid_cell": "目标地块无效",
		"out_of_range": "离地块太远",
		"invalid_mode": "未知农事操作",
		"wrong_season": "当前季节不适宜播种",
		"no_seed": "谷物种子不足",
		"plot_unavailable": "地块暂时不能种植",
		"not_mature": "作物尚未成熟",
		"crop_mature": "作物已成熟，请先收获",
		"inventory_full": "背包空间不足",
		"cleared_withered": "已清理枯萎作物",
		"action_failed": "操作未能完成",
		"plant_failed": "播种未能完成",
		"transaction_failed": "收获交易未能完成",
		"tool_broken": "工具耐久已耗尽，需先修理",
		"insufficient_stamina": "体力不足，请先休息",
	}.get(reason, reason)


func _valid_save(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var data: Dictionary = value
	if data.size() != 9 or not _is_integer(data.get("version")) or int(data.version) != SAVE_VERSION:
		return false
	if not data.get("grid") is Dictionary or not grid.validate_dict(data.grid):
		return false
	if not data.get("inventory") is Dictionary or not data.inventory.has("slots") or not data.inventory.has("quick"):
		return false
	if not data.get("tools") is Dictionary or not tools.validate_dict(data.tools):
		return false
	if not data.get("season") is Dictionary or not _is_integer(data.get("stamina")) or not _is_integer(data.get("experience")) or not _is_integer(data.get("level")) or not _is_integer(data.get("harvest_seed")):
		return false
	var clock: Dictionary = data.season
	for field in ["season", "day", "total_days", "hour", "minute"]:
		if not _is_integer(clock.get(field)):
			return false
	return (int(clock.season) >= SeasonSystem.Season.SPRING and int(clock.season) <= SeasonSystem.Season.WINTER and int(clock.day) >= 1 and int(clock.day) <= SeasonSystem.DAYS_PER_SEASON and int(clock.total_days) >= 1 and int(clock.hour) >= 0 and int(clock.hour) < 24 and int(clock.minute) >= 0 and int(clock.minute) < 60 and int(data.stamina) >= 0 and int(data.stamina) <= 100 and int(data.experience) >= 0 and int(data.level) >= 1 and int(data.harvest_seed) >= 1 and int(data.harvest_seed) <= 2147483647)


func _tool_failure(tool_id: String) -> String:
	var durability := tools.get_durability(tool_id)
	if durability.is_empty() or int(durability.current) <= 0:
		return "tool_broken"
	var state := _game_state()
	var type := ToolSystem.ToolType.HOE if tool_id == "hoe" else ToolSystem.ToolType.WATERING_CAN
	var cost := int(ToolSystem.TOOL_STAMINA_COST.get(type, 0))
	if state == null or state.player_state == null or int(state.player_state.stamina) < cost:
		return "insufficient_stamina"
	return ""


func _is_integer(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and floorf(float(value)) == float(value)


func _game_state() -> Node:
	return get_node_or_null("/root/GameState")
