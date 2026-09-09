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
const SAVE_VERSION := 13
const LivingWorld = preload("res://scripts/farm3d/living_world_system.gd")
var living_world: Node
const GolfRound = preload("res://scripts/farm3d/golf_round.gd")
const MarketScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomyScript = preload("res://scripts/systems/npc_economy_system.gd")
const MarketSite = preload("res://scripts/farm3d/market_site.gd")
signal state_loaded
const EconomyScript = preload("res://scripts/systems/economy_system.gd")
const BuildingsScript = preload("res://scripts/farm3d/farm_building_system.gd")
const ProductionScript = preload("res://scripts/systems/production_system.gd")
const DataScript = preload("res://scripts/core/game_data.gd")
const STARTER_MATERIALS := ["wood", "stone", "fiber", "plank", "stone_brick", "brick", "charcoal", "glass", "iron_ingot", "rope", "steel", "wooden_crate", "farm_tools", "machine_parts", "lamp"]

@export var auto_restore := true
@export var auto_save := true
const DEFAULT_SAVE_PATH := "res://data/farm_3d_save.json"
@export var save_path := DEFAULT_SAVE_PATH
var save_error := ""
var _backup_written_for := ""

var grid: GridSystem
var farming: FarmingSystem
var season: SeasonSystem
var inventory: InventorySystem
var tools: ToolSystem
var action_controller: PlayerActionController
var visuals: Node3D
var player: Node3D
var economy: EconomySystem
var market: MarketSystem
var npc_economy: NpcEconomySystem
var market_site := MarketSite.DEFAULT
var _market_reserved: Dictionary = {}
var buildings: BuildingSystem
var production: ProductionSystem
var paddy_cells: Dictionary = {}
var fishing: Node
var golf: Node
var golf_round := GolfRound.new()
var golf_sensitivity := 1.0
@export var enable_agents := false
@export var live_test_agents := false
@export var agent_client_config_path := "res://config/agent-client.local.json"
var agent_runtime: Node
var agent_bus: Node


func _configure_agents() -> bool:
	if not enable_agents:
		return true
	agent_bus = preload("res://scripts/ui/hud_message_bus.gd").new()
	add_child(agent_bus)
	agent_runtime = preload("res://scripts/ai_agent/agent_runtime.gd").new()
	agent_runtime.name = "AgentRuntime"
	add_child(agent_runtime)
	return agent_runtime.configure_farm3d(self, agent_bus, auto_save or live_test_agents, agent_client_config_path)


func configure(next_player: Node3D) -> bool:
	if next_player == null:
		return false
	player = next_player
	_ensure_crops_registered()
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
	inventory.max_slots = 60
	inventory.reset_slots()
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
	economy = EconomyScript.new()
	add_child(economy)
	market = MarketScript.new()
	add_child(market)
	if not market.configure(DataScript.get_market_items()):
		return false
	npc_economy = NpcEconomyScript.new()
	add_child(npc_economy)
	if not npc_economy.configure(market, LivingWorld.Society.economy_profiles(), LivingWorld.Society.external_population()):
		return false
	market.last_settled_day = season.total_days
	npc_economy.reset_to_profile_defaults(season.total_days)
	if not economy.configure(inventory, _game_state(), market, npc_economy):
		return false
	buildings = BuildingsScript.new()
	buildings.farmer = player
	add_child(buildings)
	buildings.configure(grid, economy)
	production = ProductionScript.new()
	add_child(production)
	production.configure(grid, farming, buildings, inventory)
	production.configure_rentals(npc_economy, _game_state())
	production.sync_clock(season.hour, season.minute)
	production.sync_daily_cursor(season.total_days)
	if event_bus != null:
		event_bus.day_changed.connect(production.apply_daily_effects)
		event_bus.day_changed.connect(production.finish_daily_outputs)
		event_bus.day_changed.connect(_settle_market_day)
	if not _configure_agents():
		return false
	living_world = LivingWorld.new()
	living_world.name = "LivingWorld"
	add_child(living_world)
	living_world.configure(self)
	if auto_restore and FileAccess.file_exists(save_path):
		# A missing or damaged project-local save starts a clean farm. The old
		# user:// location is intentionally not consulted.
		if load_game():
			return true
		push_warning("Farm save could not be loaded; starting a fresh farm")
	_grant_initial_state()
	market_site = MarketSite.find_available(grid)
	_reserve_market_site()
	return true


func _settle_market_day(day: int) -> void:
	if day <= market.last_settled_day:
		return
	if living_world != null:
		living_world.advance()
		if not living_world.society.caught_up((day - 1) * 1080): return
	_commit_market_day(day)


func _commit_market_day(day: int) -> void:
	if day <= market.last_settled_day: return
	# Same economic order as the original daily simulation: NPC flows, then pricing.
	if npc_economy.simulate_day(day):
		market.settle_day(day)


func _release_market_site() -> void:
	for key in _market_reserved:
		var cell: GridCell = grid._cells[key]
		grid._base_states[key] = _market_reserved[key]
		cell.state = _market_reserved[key]
	_market_reserved.clear()


func _reserve_market_site() -> void:
	if not market_site.is_finite():
		push_error("No free land for the village market")
		return
	for cell in MarketSite.cells(grid, market_site):
		var key := GridSystem.cell_key(cell.gx, cell.gz)
		_market_reserved[key] = grid._base_states[key]
		grid._base_states[key] = GridCell.State.DECORATION
		cell.state = GridCell.State.DECORATION
	grid.rebuild_farmland_visuals()
	grid.notify_navigation_state_changed()


func act(cell: GridCell, mode: String, seed_id: String = "grain_seed") -> Dictionary:
	if cell == null:
		return _failure("invalid_cell")
	if not grid.can_actor_use_cell(cell.gx, cell.gz, "player"):
		return {"ok": false, "reason": "npc_land", "message": "这是 NPC 的专属农田"}
	if not _in_range(cell):
		return _failure("out_of_range")
	if mode in ["hoe", "seed", "water"] and cell.crop_instance != null and cell.crop_instance.is_harvestable():
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
			action_controller.set_selected_plant_item_id(seed_id)
			action_controller.select_slot(PlayerActionController.SEED_SLOT)
			result = _result(action_controller.perform_cell_action(cell), "已播种%s" % item_name(seed_id), _plant_failure_reason())
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
	if is_instance_valid(fishing):
		fishing.cancel()
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
		"living_world": living_world.to_dict(),
		"grid": grid.to_dict(),
		"inventory": {"slots": inventory.slots, "quick": inventory.quick_slot_mappings},
		"season": {"season": season.current_season, "day": season.current_day, "total_days": season.total_days, "hour": season.hour, "minute": season.minute},
		"tools": tools.to_dict(),
		"stamina": stamina,
		"experience": experience,
		"level": level,
		"harvest_seed": harvest_seed,
		"paddy_cells": paddy_cells.keys(),
		"production": production.to_dict(),
		"buildings": buildings.get_all_buildings().map(func(b: BuildingInstance): return b.to_dict()),
		"gold": int(state.gold) if state != null else 100,
		"market": market.to_dict(),
		"npc_economy": npc_economy.to_dict(),
		"market_site": {"x": market_site.x, "z": market_site.y},
		"golf": golf_round.to_dict(),
		"agents": agent_runtime.to_dict() if is_instance_valid(agent_runtime) else {},
	}
	file.store_string(JSON.stringify(data, "  "))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	# Keep the farm from before this session's first overwrite. Frequent
	# autosaves must not rotate that recovery copy away within seconds.
	if _backup_written_for != save_path and FileAccess.file_exists(save_path):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(save_path+".bak")) != OK:
			save_error = "无法备份原存档，本次保存已停止"
			return false
		_backup_written_for = save_path
	var saved := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(save_path)) == OK
	if saved and is_instance_valid(agent_runtime):
		agent_runtime.save_farm3d_memory(save_path)
	return saved


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
	_migrate_residents(parsed)
	_migrate_population(parsed)
	if not _valid_save(parsed):
		return false
	var data: Dictionary = parsed
	var normalized = inventory.normalize_saved_state(data.inventory.slots, data.inventory.quick)
	if normalized == null:
		return false
	# All validation completed before any live state changes.
	if is_instance_valid(fishing):
		fishing.cancel()
	if is_instance_valid(golf):
		golf.release_control()
	_release_market_site()
	grid.reset_state()
	if not grid.from_dict(data.grid) or not tools.from_dict(data.tools):
		return false
	production.begin_restore_transaction()
	paddy_cells.clear()
	for key in data.get("paddy_cells", []):
		paddy_cells[int(key)] = true
	_sync_paddy()
	buildings.restore_buildings(data.get("buildings", []))
	inventory.restore_state(normalized.slots, normalized.quick_mappings)
	season.current_season = int(data.season.season) as SeasonSystem.Season
	season.current_day = int(data.season.day)
	season.total_days = int(data.season.total_days)
	season.hour = int(data.season.hour)
	season.minute = int(data.season.minute)
	if int(data.version) >= 3:
		market.restore_from_dict_with_current_catalog(data.market)
		npc_economy.from_dict(data.npc_economy)
		market_site = Vector2(data.market_site.x, data.market_site.z)
	else:
		market.configure(DataScript.get_market_items())
		market.last_settled_day = season.total_days
		npc_economy.reset_to_profile_defaults(season.total_days)
		market_site = MarketSite.find_available(grid)
	_reserve_market_site()
	var state := _game_state()
	if state != null and state.player_state != null:
		state.player_state.stamina = int(data.stamina)
		state.player_state.exp = int(data.experience)
		state.player_state.level = int(data.level)
		state.harvest_seed = int(data.harvest_seed)
		state.gold = int(data.get("gold", state.gold))
	if int(data.version) == 1:
		_grant_catalog_items()
	if data.has("production"):
		production.from_dict(data.production)
	production.sync_clock(season.hour, season.minute)
	production.sync_daily_cursor(season.total_days)
	production.end_restore_transaction()
	farming.sync_growth_clock()
	golf_round = GolfRound.new()
	if int(data.version) >= 4:
		golf_round.restore(data.golf)
	if is_instance_valid(agent_runtime):
		if int(data.version) >= 5 and not data.agents.is_empty():
			if not agent_runtime.from_dict(data.agents):
				return false
		else:
			grid.release_cells("farmer_ahe")
			if not agent_runtime.farm_registry.configure(grid, farming, npc_economy, get_node("/root/GameData"), "farmer_ahe", Vector3(-12, 0, -12)):
				return false
		if not agent_runtime.farm3d_actors.is_empty():
			agent_runtime.spawn_farm3d_actors()
		agent_runtime.load_farm3d_memory(save_path)
	if int(data.version) >= 7: living_world.restore(data.living_world)
	else: living_world.reset_for_legacy()
	save_error = ""
	state_loaded.emit()
	return true


func _harvest_or_clear(cell: GridCell) -> Dictionary:
	if cell.crop_instance != null and cell.crop_instance.lifecycle_state == CropInstance.LifecycleState.WITHERED:
		return _result(farming.clear_withered(cell), "已清理枯萎作物")
	var harvested_name: String = cell.crop_instance.crop_data.crop_name if cell.crop_instance != null else "作物"
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
	return {"ok": true, "reason": "", "message": "已收获%s，物品已放入背包" % harvested_name, "items": items.duplicate(true)}


func _grant_initial_state() -> void:
	inventory.add_item("grain_seed", 99)
	_grant_catalog_items()
	_game_state().gold = 50_000
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


func _ensure_crops_registered() -> void:
	var data = get_node_or_null("/root/GameData")
	if data != null:
		for crop in CropCatalogScript.default_crop_definitions():
			if data.get_crop(crop.crop_id) == null:
				data.register_crop(crop)


func _in_range(cell: GridCell) -> bool:
	if player == null:
		return false
	var position := player.global_position if player.is_inside_tree() else player.position
	return position.distance_to(cell.world_position_3d()) <= ACTION_RANGE


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
		"no_seed": "种子不足，请查看背包",
		"requires_greenhouse": "这种作物需要种在温室周围的种植区",
		"greenhouse_required": "这种作物需要温室环境",
		"no_target": "请从下方选择农田、种子或建筑",
		"already_watered": "这块地已经浇过水了",
		"invalid_target": "这里不能放置所选目标",
		"plot_unavailable": "地块暂时不能种植",
		"not_mature": "作物尚未成熟",
		"crop_mature": "作物已成熟，请先收获",
		"crop_dormant": "作物正在休眠，暂不需要浇水",
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
	if not _is_integer(data.get("version")) or int(data.version) not in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, SAVE_VERSION]:
		return false
	if data.size() != {1: 9, 2: 13, 3: 16, 4: 17, 5: 18, 6: 18, 7: 19, 8: 19, 9: 19, 10: 19, 11: 19, 12: 19, 13: 19}[int(data.version)]:
		return false
	if int(data.version) >= 7 and not living_world.validate_save(data): return false
	if int(data.version) >= 5:
		if not data.get("agents") is Dictionary:
			return false
		if not data.agents.is_empty() and (not is_instance_valid(agent_runtime) or not agent_runtime.validate_dict(data.agents)):
			return false
	if int(data.version) >= 4 and not GolfRound.valid(data.get("golf")):
		return false
	if int(data.version) >= 2:
		if not data.get("paddy_cells") is Array or not data.get("buildings") is Array or not _is_integer(data.get("gold")) or int(data.gold) < 0:
			return false
		if not data.get("production") is Dictionary or not production.validate_dict(data.production):
			return false
		for key in data.paddy_cells:
			if not _is_integer(key) or not grid._cells.has(int(key)):
				return false
	if not data.get("grid") is Dictionary or not grid.validate_dict(data.grid):
		return false
	if not buildings.validate_restore_buildings(data.get("buildings", []), data.grid):
		return false
	var identities := {}
	for saved_building in data.get("buildings", []):
		var owner := str(saved_building.get("owner_id", "player"))
		var identity := str(saved_building.get("instance_id", "legacy-%s-%s-%s" % [saved_building.building_id, saved_building.gx, saved_building.gz]))
		if identities.has(identity) or (owner != "player" and not npc_economy.has_npc(owner)): return false
		identities[identity] = true
		var producer: Dictionary = saved_building.get("producer_state", {})
		for customer in producer.get("customer_outputs", {}):
			if customer != "player" and not npc_economy.has_npc(customer): return false
		for record in producer.get("service_records", {}).values():
			if str(record.job.fee_owner) != owner or (record.job.tenant_id != "player" and not npc_economy.has_npc(record.job.tenant_id)): return false
		for job in saved_building.get("producer_state", {}).get("jobs", []):
			if job.has("tenant_id") and str(job.tenant_id) != "player" and not npc_economy.has_npc(str(job.tenant_id)):
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
	if int(data.version) >= 3 and not _valid_market_save(data):
		return false
	return (int(clock.season) >= SeasonSystem.Season.SPRING and int(clock.season) <= SeasonSystem.Season.WINTER and int(clock.day) >= 1 and int(clock.day) <= SeasonSystem.DAYS_PER_SEASON and int(clock.total_days) >= 1 and int(clock.hour) >= 0 and int(clock.hour) < 24 and int(clock.minute) >= 0 and int(clock.minute) < 60 and int(data.stamina) >= 0 and int(data.stamina) <= 100 and int(data.experience) >= 0 and int(data.level) >= 1 and int(data.harvest_seed) >= 1 and int(data.harvest_seed) <= 2147483647)


func _valid_market_save(data: Dictionary) -> bool:
	if not data.get("market") is Dictionary or not data.get("npc_economy") is Dictionary or not data.get("market_site") is Dictionary:
		return false
	var site_data: Dictionary = data.market_site
	if site_data.size() != 2 or not _is_integer(site_data.get("x")) or not _is_integer(site_data.get("z")):
		return false
	if absf(float(site_data.x)) > 72 or float(site_data.z) < -72 or float(site_data.z) > 136:
		return false
	var site := Vector2(site_data.x, site_data.z)
	var footprint := MarketSite.cells(grid, site)
	if footprint.size() != 48:
		return false
	for cell in footprint:
		var key := GridSystem.cell_key(cell.gx, cell.gz)
		if int(_market_reserved.get(key, grid._base_states[key])) != GridCell.State.WASTELAND or cell.slope >= .12:
			return false
	for entry in data.grid.cells:
		var cell := grid.get_cell(int(entry.gx), int(entry.gz))
		if cell != null and MarketSite.contains(site, cell.world_position()):
			return false
	var candidate := MarketScript.new()
	candidate.configure(DataScript.get_market_items())
	var valid := candidate.restore_from_dict_with_current_catalog(data.market)
	var settled_day: int = candidate.last_settled_day
	if int(data.version) >= 13 and data.get("living_world", {}).get("society") is Dictionary:
		# A rest can advance the clock while the saved resident batch is still
		# pending. Market and NPC cursors must agree and bracket that batch.
		var social_minute := int(data.living_world.society.last_minute)
		valid = valid and settled_day >= 1 and settled_day <= int(data.season.total_days) and social_minute >= (settled_day - 1) * 1080 and social_minute <= settled_day * 1080
	else:
		valid = valid and settled_day == int(data.season.total_days)
	candidate.free()
	return valid and npc_economy.validate_dict(data.npc_economy) and int(data.npc_economy.last_simulated_day) == settled_day


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


func _grant_catalog_items() -> void:
	# Upgrade old 3D saves once; subsequent loads never replenish spent supplies.
	for crop in CropCatalogScript.default_crop_definitions():
		if crop.plant_item_id != "grain_seed":
			inventory.add_item(crop.plant_item_id, 20)
	for item_id in STARTER_MATERIALS:
		inventory.add_item(item_id, 99)


func item_name(item_id: String) -> String:
	var item: Variant = DataScript.get_item(item_id)
	return str(item.get("name", item_id)) if item != null else item_id


func apply_target(cell: GridCell, category: String, target_id: String) -> Dictionary:
	if category.is_empty() and (cell == null or cell.state not in [GridCell.State.FARMLAND, GridCell.State.PLANTED]):
		return _failure("no_target")
	if cell == null:
		return _failure("invalid_cell")
	if not grid.can_actor_use_cell(cell.gx, cell.gz, "player"):
		return {"ok": false, "reason": "npc_land", "message": "这是 NPC 的专属农田"}
	if not _in_range(cell):
		return _failure("out_of_range")
	# Existing crops decide the farming action even if a seed/soil option remains selected.
	if category != "building" and cell.crop_instance != null:
		category = ""
	var result: Dictionary
	match category:
		"farmland":
			if target_id not in ["dry", "paddy"] or cell.crop_instance != null or cell.state not in [GridCell.State.WASTELAND, GridCell.State.FARMLAND]:
				return _failure("invalid_target")
			var key := GridSystem.cell_key(cell.gx, cell.gz)
			if cell.state == GridCell.State.FARMLAND and paddy_cells.has(key) == (target_id == "paddy"):
				return {"ok": false, "reason": "already_farmland", "message": "这里已经是所选类型的农田"}
			if int(_game_state().player_state.stamina) < 5:
				return _failure("insufficient_stamina")
			if cell.state == GridCell.State.WASTELAND and not grid.set_cell_state(cell.gx, cell.gz, GridCell.State.FARMLAND):
				return _failure("invalid_target")
			_game_state().player_state.stamina -= 5
			if target_id == "paddy":
				paddy_cells[key] = true
				grid.water_cell(cell.gx, cell.gz)
			else:
				paddy_cells.erase(key)
			_sync_paddy()
			result = _result(true, "已开垦水田 · 持续灌溉" if target_id == "paddy" else "已开垦旱地")
		"seed":
			if get_node("/root/GameData").get_crop_for_plant_item(target_id) == null:
				return _failure("invalid_target")
			return act(cell, "seed", target_id)
		"building":
			var source: Variant = DataScript.get_building(target_id)
			if source == null:
				return _failure("invalid_target")
			var placement := buildings.try_place_building(target_id, cell.gx, cell.gz)
			if placement.placed:
				for location in placement.instance.occupied_cells:
					paddy_cells.erase(GridSystem.cell_key(location.gx, location.gz))
				_sync_paddy()
			result = {"ok": placement.placed, "reason": placement.diagnostic.code, "message": "开始建造%s" % DataScript.get_building(target_id).name if placement.placed else placement.diagnostic.message}
		"":
			if cell.crop_instance != null and (cell.crop_instance.is_harvestable() or cell.crop_instance.lifecycle_state == CropInstance.LifecycleState.WITHERED):
				result = _harvest_or_clear(cell)
			elif cell.crop_instance != null and cell.crop_instance.lifecycle_state == CropInstance.LifecycleState.DORMANT:
				return _failure("crop_dormant")
			elif cell.state in [GridCell.State.FARMLAND, GridCell.State.PLANTED]:
				if cell.watered:
					return _failure("already_watered")
				if int(_game_state().player_state.stamina) < 2:
					return _failure("insufficient_stamina")
				result = _result(grid.water_cell(cell.gx, cell.gz), "已浇水")
				if result.ok:
					_game_state().player_state.stamina -= 2
			else:
				return _failure("no_target")
		_:
			return _failure("invalid_target")
	if result.ok and auto_save:
		save_game()
	return result


func _sync_paddy() -> void:
	visuals.paddy_cells = paddy_cells.duplicate()
	farming.paddy_cells = paddy_cells.duplicate()
	visuals.rebuild(grid._cells.values())


func _migrate_residents(value: Variant) -> void:
	if not value is Dictionary or not _is_integer(value.get("version")) or int(value.version) > 6: return
	if not value.get("npc_economy") is Dictionary or not value.npc_economy.get("npc_states") is Array: return
	var entries: Array = value.npc_economy.npc_states
	if entries.size() != 6: return
	var known := {}
	for entry in entries:
		if not entry is Dictionary or not entry.get("npc_id") is String or known.has(entry.npc_id): return
		known[entry.npc_id] = true
	for profile in DataScript.get_npc_economy_profiles():
		if not known.has(profile.id): return
	for profile in LivingWorld.Society.economy_profiles(true):
		if known.has(profile.id): continue
		entries.append({"npc_id": profile.id, "gold": profile.gold, "inventory": profile.inventory.duplicate(true), "reserve_targets": {}, "production_recipes": [], "sale_targets": {}, "last_simulated_day": value.npc_economy.last_simulated_day, "investment_planned": false})

func _migrate_population(value: Variant) -> void:
	if not LivingWorld.Society.expanded() or not value is Dictionary or not _is_integer(value.get("version")) or int(value.version) >= 13 or not value.get("npc_economy", {}).get("npc_states") is Array or value.npc_economy.npc_states.size() != 14: return
	# Validate the original snapshot against its original population before adding
	# configured immigrants. Existing event history, assets and liabilities stay intact.
	var original_config: Dictionary = living_world.society.config
	var original_profiles: Dictionary = npc_economy._profiles
	var original_states: Dictionary = npc_economy._states
	var original_registry: RefCounted = agent_runtime.registry
	var original_actors: Array = agent_runtime._base_actor_profiles.duplicate(true)
	var old_registry = preload("res://scripts/ai_agent/agent_registry.gd").new()
	if not old_registry.load_defaults(): return
	living_world.society.config = LivingWorld.Society.configuration(true)
	var small_profiles := {}
	var small_states := {}
	for p in LivingWorld.Society.economy_profiles(true): small_profiles[p.id] = original_profiles[p.id]
	for id in small_profiles: small_states[id] = original_states[id]
	npc_economy._profiles = small_profiles
	npc_economy._states = small_states
	agent_runtime.registry = old_registry
	agent_runtime._base_actor_profiles.assign(original_actors.filter(func(p): return p.actor_id == "player" or old_registry.is_agent_managed(p.actor_id)))
	var valid := _valid_save(value)
	if not valid and "--farm-test" in OS.get_cmdline_user_args(): print("MIGRATION CHECK world=", living_world.validate_save(value), " agents=", agent_runtime.validate_dict(value.agents), " economy=", npc_economy.validate_dict(value.npc_economy))
	living_world.society.config = original_config
	npc_economy._profiles = original_profiles
	npc_economy._states = original_states
	agent_runtime.registry = original_registry
	agent_runtime._base_actor_profiles.assign(original_actors)
	if not valid: return
	var added_gold := 0
	for p in LivingWorld.Society.economy_profiles():
		if small_profiles.has(p.id): continue
		value.npc_economy.npc_states.append({"npc_id": p.id, "gold": p.gold, "inventory": p.inventory.duplicate(true), "reserve_targets": {}, "production_recipes": [], "sale_targets": {}, "last_simulated_day": value.npc_economy.last_simulated_day, "investment_planned": false})
		added_gold += int(p.gold)
	if value.has("agents") and not value.agents.is_empty(): agent_runtime.expand_saved_population(value.agents)
	if int(value.version) >= 7:
		var society: Dictionary = value.living_world.society
		for id in living_world.society.residents:
			if not society.residents.has(id): society.residents[id] = living_world.society.residents[id].duplicate(true)
		society.initial_gold = int(society.initial_gold) + added_gold
		society.ledger.append({"minute": int(society.last_minute), "kind": "population_migration", "actor_id": "society", "gold": added_gold, "items": {}, "source": "P12一次性移入人口与组织初始资金"})
		if society.ledger.size() > 4096: society.ledger.pop_front()
		society.version = 2; society.focus = original_config.focus_actors.duplicate()
		value.version = 13
