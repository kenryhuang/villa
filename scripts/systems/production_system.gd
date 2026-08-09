class_name ProductionSystem
extends Node

const GameDataScript = preload("res://scripts/core/game_data.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const ProducerStateScript = preload("res://scripts/data/producer_state.gd")
const ProgressionScript = preload("res://scripts/systems/economy_progression_system.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")

const DAY_START_MINUTES := 6 * 60
const ROLLOVER_THRESHOLD_MINUTES := 18 * 60
const MAINTENANCE_INTERVAL_DAYS := 14
const MAINTENANCE_WARNING_DAYS := 1
const MAX_SAFE_INTEGER := EconomyLimitsScript.MAX_SAFE_INTEGER
const MAX_SAFE_DATE := EconomyLimitsScript.MAX_SAFE_DATE

var _registered_buildings: Array[BuildingInstance] = []
var _clock_synced := false
var _last_clock_minutes := 0
var _last_daily_effects_day := -1
var _last_finished_outputs_day := -1
var _event_bus: Node
var _grid_system: GridSystem
var _farming_system: FarmingSystem
var _building_system: BuildingSystem
var _inventory_system: InventorySystem
var _progression_system: Variant
var _current_day := 0
var maintenance_due_days: Dictionary = {}
var repair_remaining_seconds: Dictionary = {}
var speed_accumulators: Dictionary = {}
var _active_maintenance_transactions: Dictionary = {}
var _feed_shortage_active: Dictionary = {}
var _passive_output_blocked: Dictionary = {}


func _ready() -> void:
	add_to_group("production_system")
	_event_bus = get_node_or_null("/root/EventBus")
	if _event_bus != null and not _event_bus.time_changed.is_connected(_on_time_changed):
		_event_bus.time_changed.connect(_on_time_changed)


func configure(
	grid_system: GridSystem,
	farming_system: FarmingSystem,
	building_system: BuildingSystem = null,
	inventory_system: InventorySystem = null
) -> bool:
	if grid_system == null or farming_system == null:
		return false
	_disconnect_building_system()
	_grid_system = grid_system
	_farming_system = farming_system
	_building_system = building_system
	_inventory_system = inventory_system
	_connect_building_system()
	register_existing_buildings()
	_refresh_greenhouse_cells()
	return true


func get_building_snapshot(building: BuildingInstance) -> Dictionary:
	var state := _get_state(building)
	if state == null:
		return {}
	var snapshot: Dictionary = state.to_dict()
	snapshot["building_id"] = building.building_id
	snapshot["maintenance_due_day"] = get_maintenance_due_day(building)
	snapshot["maintenance_state"] = get_maintenance_state(building)
	snapshot["maintenance_days_remaining"] = get_maintenance_days_remaining(building)
	snapshot["repair_remaining_seconds"] = get_repair_remaining_seconds(building)
	snapshot["maintenance_paused"] = is_maintenance_paused(building)
	snapshot["storage_quantity_capacity"] = _storage_quantity_capacity(building)
	if bool(snapshot.maintenance_paused) and not snapshot.jobs.is_empty():
		snapshot.jobs[0].status = "maintenance_paused"
	return snapshot


func refresh_indicator(building: BuildingInstance) -> String:
	if building == null or not is_instance_valid(building):
		return ""
	var kind := ""
	var state := _get_state(building)
	if _building_is_active(building):
		if is_maintenance_paused(building):
			kind = "maintenance"
		elif state != null and _is_output_full(building, state):
			kind = "full"
	if building.has_method("sync_output_display"):
		building.call(
			"sync_output_display",
			state.outputs if state != null else {},
			_storage_quantity_capacity(building)
		)
	if building.has_method("set_economy_indicator"):
		building.call("set_economy_indicator", kind)
	return kind


func preflight_recipe(
	building: BuildingInstance,
	recipe_id: String,
	batches: int,
	inventory: InventorySystem
) -> Dictionary:
	var failure := {"ok": false, "reason": "invalid_request", "missing": {}}
	if building == null or inventory == null or recipe_id.is_empty() or batches <= 0:
		return failure
	var state := _get_state(building)
	if state == null:
		failure.reason = "not_a_producer"
		return failure
	if is_maintenance_paused(building):
		failure.reason = "maintenance_overdue"
		return failure
	var recipe := RecipeDatabaseScript.get_recipe(recipe_id)
	if recipe.is_empty():
		failure.reason = "unknown_recipe"
		return failure
	if str(recipe.station) != state.station_id:
		failure.reason = "station_mismatch"
		return failure
	if (
		_progression_system != null
		and is_instance_valid(_progression_system)
		and _progression_system.has_method("is_recipe_unlocked")
		and not bool(_progression_system.call("is_recipe_unlocked", recipe_id))
	):
		failure.reason = "recipe_locked"
		return failure
	if not _building_is_active(building):
		failure.reason = "building_incomplete"
		return failure
	if state.jobs.size() >= state.max_queue_slots:
		failure.reason = "queue_full"
		return failure
	var required := _multiplied_counts(recipe.inputs, batches)
	var missing := {}
	for item_id in required:
		var shortfall := int(required[item_id]) - inventory.get_item_count(str(item_id))
		if shortfall > 0:
			missing[item_id] = shortfall
	if not missing.is_empty():
		failure.reason = "missing_inputs"
		failure.missing = missing
		return failure
	return {
		"ok": true,
		"reason": "",
		"missing": {},
		"inputs": required,
		"outputs": _multiplied_counts(recipe.outputs, batches),
		"duration_minutes": int(recipe.duration_minutes) * batches,
	}


func start_recipe(
	building: BuildingInstance,
	recipe_id: String,
	batches: int,
	inventory: InventorySystem
) -> bool:
	var preflight := preflight_recipe(building, recipe_id, batches, inventory)
	if not bool(preflight.get("ok", false)):
		return false
	var state := _get_state(building)
	var inventory_snapshot := _snapshot_inventory(inventory)
	var jobs_snapshot: Array[Dictionary] = state.jobs.duplicate(true)
	var inputs: Dictionary = preflight.inputs
	var owns_event_transaction := _begin_event_bus_transaction()
	var owns_mapping_transaction: bool = inventory.begin_mapping_transaction()
	for item_id in inputs:
		if not inventory.remove_item(str(item_id), int(inputs[item_id])):
			_restore_inventory(inventory, inventory_snapshot)
			_end_mapping_transaction(inventory, owns_mapping_transaction, false)
			_end_inventory_event_transaction(owns_event_transaction, false, "item_removed", inputs)
			return false
	var job := {
		"recipe_id": recipe_id,
		"batches": batches,
		"remaining_minutes": int(preflight.duration_minutes),
		"status": "running" if state.jobs.is_empty() else "queued",
	}
	if not state.enqueue_job(job):
		_restore_inventory(inventory, inventory_snapshot)
		state.jobs.assign(jobs_snapshot)
		_end_mapping_transaction(inventory, owns_mapping_transaction, false)
		_end_inventory_event_transaction(owns_event_transaction, false, "item_removed", inputs)
		return false
	_end_mapping_transaction(inventory, owns_mapping_transaction, true)
	_end_inventory_event_transaction(owns_event_transaction, true, "item_removed", inputs)
	register_building(building)
	_emit_event("production_job_started", [building, recipe_id, batches])
	return true


func add_input(
	building: BuildingInstance,
	item_id: String,
	quantity: int,
	inventory: InventorySystem
) -> bool:
	var state := _get_state(building)
	if state == null or inventory == null or quantity <= 0:
		return false
	if GameDataScript.get_item(item_id) == null or not inventory.has_item(item_id, quantity):
		return false
	var inventory_snapshot := _snapshot_inventory(inventory)
	var inputs_snapshot: Dictionary = state.inputs.duplicate(true)
	var owns_event_transaction := _begin_event_bus_transaction()
	var owns_mapping_transaction: bool = inventory.begin_mapping_transaction()
	if not inventory.remove_item(item_id, quantity) or not state.add_input(item_id, quantity):
		_restore_inventory(inventory, inventory_snapshot)
		state.inputs = inputs_snapshot
		_end_mapping_transaction(inventory, owns_mapping_transaction, false)
		_end_inventory_event_transaction(
			owns_event_transaction,
			false,
			"item_removed",
			{item_id: quantity}
		)
		return false
	_end_mapping_transaction(inventory, owns_mapping_transaction, true)
	_end_inventory_event_transaction(
		owns_event_transaction,
		true,
		"item_removed",
		{item_id: quantity}
	)
	register_building(building)
	_emit_event("production_input_changed", [building, item_id, state.get_input_count(item_id)])
	return true


func advance_minutes(minutes: int) -> void:
	if minutes <= 0:
		return
	for building in _valid_registered_buildings():
		if not _building_is_active(building):
			refresh_indicator(building)
			continue
		_advance_building(building, minutes)
		refresh_indicator(building)


func collect_all(building: BuildingInstance, inventory: InventorySystem) -> bool:
	return bool(collect_outputs(building, inventory).get("ok", false))


func collect_item(
	building: BuildingInstance,
	item_id: String,
	inventory: InventorySystem
) -> bool:
	return bool(collect_outputs(building, inventory, item_id).get("ok", false))


func preflight_output_collection(
	building: BuildingInstance,
	inventory: InventorySystem,
	item_id: String = ""
) -> Dictionary:
	var failure := {"ok": false, "reason": "invalid_request", "requested": {}}
	var state := _get_state(building)
	if state == null or inventory == null:
		return failure
	var requested: Dictionary = state.outputs.duplicate(true)
	if not item_id.is_empty():
		var quantity := state.get_output_count(item_id)
		if quantity <= 0:
			failure.reason = "nothing_to_collect"
			return failure
		requested = {item_id: quantity}
	if requested.is_empty():
		failure.reason = "nothing_to_collect"
		return failure
	var result: Dictionary = inventory.preflight_add_items(requested)
	result["requested"] = requested.duplicate(true)
	return result


func collect_outputs(
	building: BuildingInstance,
	inventory: InventorySystem,
	item_id: String = ""
) -> Dictionary:
	var result := preflight_output_collection(building, inventory, item_id)
	if not bool(result.get("ok", false)):
		return result
	if not _collect(building, inventory, result.requested):
		result.ok = false
		result.reason = "transaction_failed"
	else:
		var state := _get_state(building)
		if state != null:
			_prepare_running_job(building, state)
		refresh_indicator(building)
	return result


func apply_daily_effects(total_day: int) -> void:
	if not begin_day(total_day):
		return
	if total_day <= _last_daily_effects_day:
		return
	_last_daily_effects_day = total_day
	for building in _valid_registered_buildings():
		if (
			not _building_is_active(building)
			or not _has_effect(building, "irrigation")
			or is_maintenance_paused(building)
		):
			continue
		if not is_water_connected(building):
			continue
		for position in get_irrigated_cells(building):
			_grid_system.water_cell(position.x, position.y)


func finish_daily_outputs(total_day: int) -> void:
	if not begin_day(total_day):
		return
	if total_day <= _last_finished_outputs_day:
		return
	_last_finished_outputs_day = total_day
	for building in _valid_registered_buildings():
		if not _building_is_active(building):
			continue
		_finish_passive_building(building, total_day)
		refresh_indicator(building)


func sync_clock(hour: int, minute: int) -> bool:
	if hour < 0 or hour >= 24 or minute < 0 or minute >= 60:
		return false
	_last_clock_minutes = hour * 60 + minute
	_clock_synced = true
	return true


func begin_day(total_day: int) -> bool:
	if total_day < _current_day or total_day > MAX_SAFE_DATE:
		return false
	if total_day == _current_day:
		return true
	var previous_day := _current_day
	_current_day = total_day
	for building in _valid_registered_buildings():
		var due_day := get_maintenance_due_day(building)
		if due_day > previous_day and due_day <= total_day:
			_emit_event("production_maintenance_changed", [building, due_day])
		refresh_indicator(building)
	_refresh_greenhouse_cells()
	return true


func sync_daily_cursor(total_day: int) -> bool:
	if total_day < 0 or total_day > MAX_SAFE_DATE:
		return false
	_last_daily_effects_day = total_day
	_last_finished_outputs_day = total_day
	_current_day = total_day
	_feed_shortage_active.clear()
	_passive_output_blocked.clear()
	_refresh_greenhouse_cells()
	for building in _valid_registered_buildings():
		refresh_indicator(building)
	return true


func get_current_day() -> int:
	return _current_day


func register_building(building: BuildingInstance) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	_ensure_passive_state(building)
	if _get_state(building) == null and not _is_effect_building(building):
		return false
	if not _registered_buildings.has(building):
		_registered_buildings.append(building)
	var key := building_key(building)
	if not maintenance_due_days.has(key):
		maintenance_due_days[key] = _current_day + MAINTENANCE_INTERVAL_DAYS
	_apply_saved_upgrades(building)
	_refresh_greenhouse_cells()
	refresh_indicator(building)
	return true


func unregister_building(building: BuildingInstance) -> void:
	_registered_buildings.erase(building)
	if building != null:
		if is_instance_valid(building) and building.has_method("set_economy_indicator"):
			building.call("set_economy_indicator", "")
		var key := building_key(building)
		maintenance_due_days.erase(key)
		speed_accumulators.erase(key)
		_feed_shortage_active.erase(key)
		_passive_output_blocked.erase(key)
	_refresh_greenhouse_cells()


func register_existing_buildings() -> int:
	if _building_system == null:
		return 0
	var registered := 0
	for building in _building_system.get_all_buildings():
		if register_building(building):
			registered += 1
	return registered


func rebuild_registered_buildings() -> int:
	_registered_buildings.clear()
	_feed_shortage_active.clear()
	_passive_output_blocked.clear()
	return register_existing_buildings()


func get_registered_buildings() -> Array[BuildingInstance]:
	return _valid_registered_buildings().duplicate()


func set_progression_system(progression_system: Variant) -> bool:
	if progression_system == null or not progression_system.has_method("get_upgrade_level"):
		return false
	_progression_system = progression_system
	for building in _valid_registered_buildings():
		_apply_saved_upgrades(building)
	return true


func get_maintenance_due_day(building: BuildingInstance) -> int:
	if building == null:
		return -1
	return int(maintenance_due_days.get(building_key(building), -1))


func set_maintenance_due_day(building: BuildingInstance, due_day: int) -> bool:
	if building == null or due_day < 0 or due_day > MAX_SAFE_INTEGER:
		return false
	if not _registered_buildings.has(building):
		return false
	var previous_due_day := get_maintenance_due_day(building)
	maintenance_due_days[building_key(building)] = due_day
	_refresh_greenhouse_cells()
	refresh_indicator(building)
	if due_day <= _current_day and (previous_due_day < 0 or previous_due_day > _current_day):
		_emit_event("production_maintenance_changed", [building, due_day])
	return true


func is_maintenance_overdue(building: BuildingInstance) -> bool:
	var due_day := get_maintenance_due_day(building)
	return due_day >= 0 and _current_day >= due_day


func get_maintenance_days_remaining(building: BuildingInstance) -> int:
	var due_day := get_maintenance_due_day(building)
	return maxi(0, due_day - _current_day) if due_day >= 0 else -1


func get_repair_remaining_seconds(building: BuildingInstance) -> float:
	if building == null:
		return 0.0
	return float(repair_remaining_seconds.get(building_key(building), 0.0))


func get_maintenance_state(building: BuildingInstance) -> String:
	if building == null or get_maintenance_due_day(building) < 0:
		return "normal"
	if get_repair_remaining_seconds(building) > 0.0:
		return "repairing"
	var remaining := get_maintenance_due_day(building) - _current_day
	if remaining <= 0:
		return "overdue"
	if remaining <= MAINTENANCE_WARNING_DAYS:
		return "warning"
	return "normal"


func is_maintenance_paused(building: BuildingInstance) -> bool:
	return get_maintenance_state(building) in ["overdue", "repairing"]


func get_maintenance_quote(building: BuildingInstance) -> Dictionary:
	if building == null or not _registered_buildings.has(building):
		return {}
	return {"gold_cost": 25, "materials": {"wood": 1, "stone": 1}}


func maintain(
	building: BuildingInstance,
	wallet: Variant,
	inventory: InventorySystem
) -> bool:
	if building == null or wallet == null or inventory == null or not is_maintenance_overdue(building):
		return false
	var key := building_key(building)
	if _active_maintenance_transactions.has(key):
		return false
	var quote := get_maintenance_quote(building)
	if quote.is_empty() or int(wallet.gold) < int(quote.gold_cost):
		return false
	for item_id in quote.materials:
		if not inventory.has_item(str(item_id), int(quote.materials[item_id])):
			return false
	_active_maintenance_transactions[key] = true
	var snapshot := {
		"slots": inventory.slots.duplicate(true),
		"mappings": inventory.quick_slot_mappings.duplicate(),
	}
	var gold_before := int(wallet.gold)
	var due_before := get_maintenance_due_day(building)
	var owns_event := _begin_event_bus_transaction()
	var owns_mapping := inventory.begin_mapping_transaction()
	for item_id in quote.materials:
		if not inventory.remove_item(str(item_id), int(quote.materials[item_id])):
			_rollback_maintenance_transaction(inventory, wallet, snapshot, gold_before, due_before, key, owns_mapping, owns_event)
			_active_maintenance_transactions.erase(key)
			return false
	if not wallet.spend_gold(int(quote.gold_cost)):
		_rollback_maintenance_transaction(inventory, wallet, snapshot, gold_before, due_before, key, owns_mapping, owns_event)
		_active_maintenance_transactions.erase(key)
		return false
	maintenance_due_days[key] = _current_day + MAINTENANCE_INTERVAL_DAYS
	_refresh_greenhouse_cells()
	refresh_indicator(building)
	if owns_mapping:
		inventory.end_mapping_transaction(true)
	_end_inventory_event_transaction(owns_event, true, "item_removed", quote.materials)
	if owns_event and _event_bus != null:
		_event_bus.gold_changed.emit(int(wallet.gold))
	_emit_event("production_maintenance_changed", [building, get_maintenance_due_day(building)])
	_active_maintenance_transactions.erase(key)
	return true


func _rollback_maintenance_transaction(
	inventory: InventorySystem,
	wallet: Variant,
	snapshot: Dictionary,
	gold_before: int,
	due_before: int,
	key: String,
	owns_mapping: bool,
	owns_event: bool
) -> bool:
	inventory.restore_state(snapshot.slots, snapshot.mappings)
	wallet.set("gold", gold_before)
	maintenance_due_days[key] = due_before
	if owns_mapping:
		inventory.end_mapping_transaction(false)
	_end_inventory_event_transaction(owns_event, false, "item_removed", {})
	var rollback_ok: bool = (
		int(wallet.gold) == gold_before
		and inventory.slots == snapshot.slots
		and inventory.quick_slot_mappings == snapshot.mappings
		and int(maintenance_due_days.get(key, -1)) == due_before
	)
	if not rollback_ok:
		push_error("Maintenance transaction rollback failed")
	return rollback_ok


func can_apply_upgrade(building: BuildingInstance, upgrade_id: String, level: int) -> bool:
	return (
		building != null and _registered_buildings.has(building)
		and _get_state(building) != null
		and _building_is_active(building)
		and upgrade_id in get_supported_upgrades(building)
		and level >= 1 and level <= 3
	)


func get_supported_upgrades(building: BuildingInstance) -> Array[String]:
	if building == null or not _registered_buildings.has(building) or _get_state(building) == null:
		return []
	if _effect_type(building) == "crafting":
		return ["queue_slots", "speed", "storage"]
	if _effect_type(building) in ["honey", "animal", "resource_output"]:
		return ["storage"]
	return []


func apply_upgrade(building: BuildingInstance, upgrade_id: String, level: int) -> bool:
	if not can_apply_upgrade(building, upgrade_id, level):
		return false
	var state := _get_state(building)
	match upgrade_id:
		"queue_slots":
			state.max_queue_slots = expected_max_queue_slots(level)
		"storage":
			state.output_capacity = expected_output_capacity(building.building_id, level)
		"speed":
			pass
	refresh_indicator(building)
	return true


func to_dict() -> Dictionary:
	var records: Array[Dictionary] = []
	var keys: Array[String] = []
	keys.assign(maintenance_due_days.keys())
	keys.sort()
	for key in keys:
		records.append({"building_key": key, "due_day": int(maintenance_due_days[key])})
	var speed_records: Array[Dictionary] = []
	var speed_keys: Array[String] = []
	speed_keys.assign(speed_accumulators.keys())
	speed_keys.sort()
	for key in speed_keys:
		speed_records.append({"building_key": key, "remainder": int(speed_accumulators[key])})
	return {"version": 1, "maintenance": records, "speed_accumulators": speed_records}


func validate_dict(data: Dictionary) -> bool:
	return _parse_maintenance(data) != null


func from_dict(data: Dictionary) -> bool:
	var parsed: Variant = _parse_maintenance(data)
	if not parsed is Dictionary:
		return false
	maintenance_due_days = parsed.maintenance
	speed_accumulators = parsed.speed
	for building in _valid_registered_buildings():
		refresh_indicator(building)
	return true


func reset_maintenance(total_day: int = 0) -> bool:
	if total_day < 0 or total_day > MAX_SAFE_DATE:
		return false
	_current_day = total_day
	maintenance_due_days.clear()
	speed_accumulators.clear()
	_feed_shortage_active.clear()
	_passive_output_blocked.clear()
	for building in _valid_registered_buildings():
		refresh_indicator(building)
	return true


static func building_key(building: BuildingInstance) -> String:
	return ProgressionScript.building_key(building)


func _parse_maintenance(data: Dictionary) -> Variant:
	if data.size() != 3 or not _integer_number_in_range(data.get("version"), 1, 1):
		return null
	if not data.get("maintenance") is Array or not data.get("speed_accumulators") is Array:
		return null
	var maintenance := {}
	for value in data.maintenance:
		if not value is Dictionary:
			return null
		var record := value as Dictionary
		if record.size() != 2 or not record.get("building_key") is String:
			return null
		var key := str(record.building_key)
		if not _valid_building_key(key) or maintenance.has(key):
			return null
		if not _integer_number_in_range(record.get("due_day"), 0, MAX_SAFE_INTEGER):
			return null
		maintenance[key] = int(record.due_day)
	var speed := {}
	for value in data.speed_accumulators:
		if not value is Dictionary:
			return null
		var record := value as Dictionary
		if record.size() != 2 or not record.get("building_key") is String:
			return null
		var key := str(record.building_key)
		if not _valid_building_key(key) or speed.has(key):
			return null
		if not _integer_number_in_range(record.get("remainder"), 0, 99):
			return null
		speed[key] = int(record.remainder)
	return {"maintenance": maintenance, "speed": speed}


func _valid_building_key(key: String) -> bool:
	return ProgressionScript.is_valid_building_key(key)


static func _integer_number_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	return (
		typeof(value) == TYPE_FLOAT and is_finite(value)
		and floorf(value) == value and value >= float(minimum) and value <= float(maximum)
	)


func passive_output_for(id: String, day: int, flowers: int) -> Dictionary:
	match id:
		"beehive":
			if day % 2 != 0:
				return {}
			return {"honey": 2, "beeswax": 1} if mini(flowers, 4) >= 4 else {"honey": 1}
		"chicken_coop":
			return {"egg": 2}
	return {}


func count_nearby_mature_flowers(building: BuildingInstance) -> int:
	if building == null or _grid_system == null:
		return 0
	var config := _effect_config(building)
	var radius := float(config.get("flower_radius", 4))
	var cap := maxi(0, int(config.get("flower_cap", 4)))
	var center := _building_center(building)
	var count := 0
	for cell in _grid_system._cells.values():
		if not cell is GridCell or cell.crop_instance == null:
			continue
		if Vector2(cell.gx, cell.gz).distance_to(center) > radius + 0.0001:
			continue
		if cell.crop_instance.is_mature() and _crop_has_flower_tag(cell.crop_instance.crop_data):
			count += 1
			if count >= cap:
				return cap
	return count


func is_water_connected(building: BuildingInstance) -> bool:
	if building == null or _grid_system == null or not _has_effect(building, "irrigation"):
		return false
	var footprint := _footprint_for(building)
	for x in range(building.grid_x, building.grid_x + footprint.x):
		for z in [building.grid_z - 1, building.grid_z + footprint.y]:
			var cell := _grid_system.get_cell(x, z)
			if cell != null and cell.state == GridCell.State.WATER:
				return true
	for z in range(building.grid_z, building.grid_z + footprint.y):
		for x in [building.grid_x - 1, building.grid_x + footprint.x]:
			var cell := _grid_system.get_cell(x, z)
			if cell != null and cell.state == GridCell.State.WATER:
				return true
	return false


func get_irrigated_cells(building: BuildingInstance) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for position in get_waterwheel_covered_cells(building):
		var cell := _grid_system.get_cell(position.x, position.y)
		if cell.state in [GridCell.State.FARMLAND, GridCell.State.PLANTED]:
			result.append(position)
	return result


func get_waterwheel_covered_cells(waterwheel: BuildingInstance) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if waterwheel == null or _grid_system == null or not _has_effect(waterwheel, "irrigation"):
		return result
	var radius := float(_effect_config(waterwheel).get("radius", 4))
	var center := _building_center(waterwheel)
	for gz in range(floori(center.y - radius), ceili(center.y + radius) + 1):
		for gx in range(floori(center.x - radius), ceili(center.x + radius) + 1):
			if Vector2(gx, gz).distance_to(center) > radius + 0.0001:
				continue
			if _grid_system.get_cell(gx, gz) != null:
				result.append(Vector2i(gx, gz))
	return result


func get_greenhouse_cells(building: BuildingInstance) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if building == null or not _has_effect(building, "ignore_season"):
		return result
	var footprint := _footprint_for(building)
	var gx := building.grid_x
	var gz := building.grid_z
	for x in range(gx, gx + footprint.x):
		result.append(Vector2i(x, gz - 1))
	result.append(Vector2i(gx - 1, gz + footprint.y / 2))
	result.append(Vector2i(gx + footprint.x, gz + footprint.y / 2))
	for x in range(gx, gx + footprint.x):
		result.append(Vector2i(x, gz + footprint.y))
	return result


func get_greenhouse_crop_maturity(greenhouse: BuildingInstance) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _grid_system == null or not _building_is_active(greenhouse):
		return result
	for position in get_greenhouse_cells(greenhouse):
		var cell := _grid_system.get_cell(position.x, position.y)
		if cell == null or cell.crop_instance == null or cell.crop_instance.crop_data == null:
			continue
		var crop_data = cell.crop_instance.crop_data
		var crop_id := str(_property_value(crop_data, "crop_id", ""))
		var growth_days := maxi(0, int(_property_value(crop_data, "growth_days", 0)))
		if crop_id.is_empty() or growth_days <= 0:
			continue
		var total_half_steps := growth_days * 2
		var completed_half_steps := clampi(
			roundi(float(cell.crop_instance.growth_progress) * 2.0),
			0,
			total_half_steps
		)
		var remaining_half_steps := total_half_steps - completed_half_steps
		var sustained_irrigation := _is_crop_cell_currently_irrigated(position)
		var first_day_half_steps := 3 if bool(cell.crop_instance.is_watered_today) or sustained_irrigation else 2
		var future_daily_half_steps := 3 if sustained_irrigation else 2
		var remaining_days := 0
		if remaining_half_steps > 0:
			remaining_days = 1 + ceili(
				float(maxi(0, remaining_half_steps - first_day_half_steps))
				/ float(future_daily_half_steps)
			)
		result.append({
			"cell": position,
			"crop_id": crop_id,
			"remaining_days": remaining_days,
			"maturity_day": _current_day + remaining_days,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_cell := a.cell as Vector2i
		var b_cell := b.cell as Vector2i
		return a_cell.y < b_cell.y or (a_cell.y == b_cell.y and a_cell.x < b_cell.x)
	)
	return result


func _is_crop_cell_currently_irrigated(position: Vector2i) -> bool:
	for waterwheel in _valid_registered_buildings():
		if (
			not _building_is_active(waterwheel)
			or not _has_effect(waterwheel, "irrigation")
			or is_maintenance_paused(waterwheel)
			or not is_water_connected(waterwheel)
		):
			continue
		if position in get_irrigated_cells(waterwheel):
			return true
	return false


func get_covered_greenhouses(waterwheel: BuildingInstance) -> Array[String]:
	var result: Array[String] = []
	if (
		not _building_is_active(waterwheel)
		or not _has_effect(waterwheel, "irrigation")
		or is_maintenance_paused(waterwheel)
		or not is_water_connected(waterwheel)
	):
		return result
	var covered := {}
	for position in get_waterwheel_covered_cells(waterwheel):
		covered[position] = true
	for greenhouse in _valid_registered_buildings():
		if (
			not _building_is_active(greenhouse)
			or not _has_effect(greenhouse, "ignore_season")
			or is_maintenance_paused(greenhouse)
		):
			continue
		for position in get_greenhouse_cells(greenhouse):
			if covered.has(position):
				result.append(building_key(greenhouse))
				break
	result.sort()
	return result


func is_greenhouse_water_connected(greenhouse: BuildingInstance) -> bool:
	if not _building_is_active(greenhouse) or get_greenhouse_cells(greenhouse).is_empty():
		return false
	var greenhouse_key := building_key(greenhouse)
	for building in _valid_registered_buildings():
		if greenhouse_key in get_covered_greenhouses(building):
			return true
	return false


func collect_nearby_outputs(
	barn: BuildingInstance,
	inventory: InventorySystem = null
) -> bool:
	return bool(collect_barn_outputs(barn, inventory).get("ok", false))


func get_nearby_output_groups(barn: BuildingInstance) -> Dictionary:
	var result := {}
	for source in _nearby_output_sources(barn):
		var source_key := str(source.source_key)
		var building := source.building as BuildingInstance
		result[source_key] = {
			"source_key": source_key,
			"building_id": building.building_id,
			"display_name": building.data.display_name if building.data != null else building.building_id,
			"outputs": (source.outputs as Dictionary).duplicate(true),
		}
	return result.duplicate(true)


func preflight_barn_collection(
	barn: BuildingInstance,
	inventory: InventorySystem = null,
	source_key: String = "",
	item_id: String = ""
) -> Dictionary:
	var destination := inventory if inventory != null else _inventory_system
	var failure := {"ok": false, "reason": "invalid_request", "requested": {}, "groups": {}}
	if barn == null or destination == null or not _has_effect(barn, "inventory_expand"):
		return failure
	var all_groups := get_nearby_output_groups(barn)
	if not source_key.is_empty() and not all_groups.has(source_key):
		failure.reason = "source_not_found"
		return failure
	var sources := _nearby_output_sources(barn, source_key, item_id)
	if sources.is_empty():
		failure.reason = "nothing_to_collect"
		return failure
	var combined := {}
	for source in sources:
		_merge_counts(combined, source.outputs)
	var result: Dictionary = destination.preflight_add_items(combined)
	result["requested"] = combined.duplicate(true)
	result["groups"] = all_groups.duplicate(true)
	return result


func collect_barn_outputs(
	barn: BuildingInstance,
	inventory: InventorySystem = null,
	source_key: String = "",
	item_id: String = ""
) -> Dictionary:
	var destination := inventory if inventory != null else _inventory_system
	var result := preflight_barn_collection(barn, destination, source_key, item_id)
	if not bool(result.get("ok", false)):
		return result
	var sources := _nearby_output_sources(barn, source_key, item_id)
	var combined: Dictionary = result.requested
	var inventory_snapshot := _snapshot_inventory(destination)
	var owns_event_transaction := _begin_event_bus_transaction()
	var owns_mapping_transaction: bool = destination.begin_mapping_transaction()
	for collected_item_id in combined:
		if not destination.add_item(str(collected_item_id), int(combined[collected_item_id])):
			_restore_inventory(destination, inventory_snapshot)
			_end_mapping_transaction(destination, owns_mapping_transaction, false)
			_end_inventory_event_transaction(owns_event_transaction, false, "item_added", combined)
			result.ok = false
			result.reason = "transaction_failed"
			return result
	for source in sources:
		var state := source.state as ProducerState
		if not state.remove_outputs(source.outputs):
			_restore_inventory(destination, inventory_snapshot)
			for rollback_source in sources:
				(rollback_source.state as ProducerState).outputs = rollback_source.outputs.duplicate(true)
			_end_mapping_transaction(destination, owns_mapping_transaction, false)
			_end_inventory_event_transaction(owns_event_transaction, false, "item_added", combined)
			result.ok = false
			result.reason = "transaction_failed"
			return result
	_end_mapping_transaction(destination, owns_mapping_transaction, true)
	_end_inventory_event_transaction(owns_event_transaction, true, "item_added", combined)
	for source in sources:
		var state := source.state as ProducerState
		for changed_item_id in source.outputs:
			var owner := _building_for_state(state)
			if owner != null:
				_emit_event("production_output_changed", [owner, str(changed_item_id), state.get_output_count(str(changed_item_id))])
	return result


func _nearby_output_sources(
	barn: BuildingInstance,
	source_key: String = "",
	item_id: String = ""
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if barn == null or not _has_effect(barn, "inventory_expand"):
		return result
	var radius := float(_effect_config(barn).get("collection_radius", 6))
	var center := _building_center(barn)
	for building in _valid_registered_buildings():
		if building == barn or not _building_is_active(building):
			continue
		if _building_center(building).distance_to(center) > radius + 0.0001:
			continue
		var key := building_key(building)
		if not source_key.is_empty() and key != source_key:
			continue
		var state := _get_state(building)
		if state == null or state.outputs.is_empty():
			continue
		var outputs: Dictionary = state.outputs.duplicate(true)
		if not item_id.is_empty():
			var quantity := int(outputs.get(item_id, 0))
			if quantity <= 0:
				continue
			outputs = {item_id: quantity}
		result.append({"building": building, "source_key": key, "state": state, "outputs": outputs})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.source_key) < str(b.source_key))
	return result


func _connect_building_system() -> void:
	if _building_system == null:
		return
	var placed := Callable(self, "_on_building_registered")
	var removed := Callable(self, "_on_building_unregistered")
	var completed := Callable(self, "_on_building_completed")
	if not _building_system.building_instance_placed.is_connected(placed):
		_building_system.building_instance_placed.connect(placed)
	if not _building_system.building_instance_removed.is_connected(removed):
		_building_system.building_instance_removed.connect(removed)
	if not _building_system.building_construction_completed.is_connected(completed):
		_building_system.building_construction_completed.connect(completed)


func _disconnect_building_system() -> void:
	if _building_system == null or not is_instance_valid(_building_system):
		return
	var placed := Callable(self, "_on_building_registered")
	var removed := Callable(self, "_on_building_unregistered")
	var completed := Callable(self, "_on_building_completed")
	if _building_system.building_instance_placed.is_connected(placed):
		_building_system.building_instance_placed.disconnect(placed)
	if _building_system.building_instance_removed.is_connected(removed):
		_building_system.building_instance_removed.disconnect(removed)
	if _building_system.building_construction_completed.is_connected(completed):
		_building_system.building_construction_completed.disconnect(completed)


func _on_building_registered(building: BuildingInstance) -> void:
	register_building(building)


func _on_building_unregistered(building: BuildingInstance) -> void:
	unregister_building(building)


func _on_building_completed(building: BuildingInstance) -> void:
	register_building(building)


func _finish_passive_building(building: BuildingInstance, total_day: int) -> void:
	if is_maintenance_paused(building):
		return
	var id := building.building_id
	var state := _get_state(building)
	if state == null:
		return
	var output := {}
	if id == "beehive":
		output = passive_output_for(id, total_day, count_nearby_mature_flowers(building))
	elif id == "chicken_coop":
		output = passive_output_for(id, total_day, 0)
	else:
		output = _resource_output_for(building, total_day)
	if output.is_empty():
		return
	var passive_id := "passive:%s" % id
	if not _can_store_passive_outputs(building, state, output):
		_set_passive_output_blocked(building, passive_id, true)
		return
	_set_passive_output_blocked(building, passive_id, false)
	var inputs_snapshot: Dictionary = state.inputs.duplicate(true)
	var outputs_snapshot: Dictionary = state.outputs.duplicate(true)
	if id == "chicken_coop":
		var config := _effect_config(building)
		var feed_item := str(config.get("feed_item", "animal_feed"))
		var feed_count := int(config.get("feed_per_day", 1))
		if feed_count <= 0 or not state.remove_input(feed_item, feed_count):
			_set_feed_shortage(building, feed_item, true, total_day)
			return
		_set_feed_shortage(building, feed_item, false, total_day)
	if not state.add_outputs(output):
		state.inputs = inputs_snapshot
		state.outputs = outputs_snapshot
		_set_passive_output_blocked(building, passive_id, true)
		return
	if id == "chicken_coop":
		var feed_item := str(_effect_config(building).get("feed_item", "animal_feed"))
		_emit_event("production_input_changed", [building, feed_item, state.get_input_count(feed_item)])
	for item_id in output:
		_emit_event("production_output_changed", [building, str(item_id), state.get_output_count(str(item_id))])
	_emit_event("production_job_completed", [building, passive_id, output.duplicate(true)])


func _set_feed_shortage(
	building: BuildingInstance,
	item_id: String,
	shortage: bool,
	total_day: int
) -> void:
	var key := building_key(building)
	var previous := bool(_feed_shortage_active.get(key, false))
	if previous == shortage:
		return
	if shortage:
		_feed_shortage_active[key] = true
	else:
		_feed_shortage_active.erase(key)
	_emit_event("production_feed_shortage", [building, item_id, shortage, total_day])


func _set_passive_output_blocked(
	building: BuildingInstance,
	passive_id: String,
	blocked: bool
) -> void:
	var key := building_key(building)
	var previous := bool(_passive_output_blocked.get(key, false))
	if previous == blocked:
		return
	if blocked:
		_passive_output_blocked[key] = true
		_emit_event("production_output_blocked", [building, passive_id])
	else:
		_passive_output_blocked.erase(key)


func _can_store_passive_outputs(
	building: BuildingInstance,
	state: ProducerState,
	output: Dictionary
) -> bool:
	if not state.can_store_outputs(output):
		return false
	var quantity_capacity := _storage_quantity_capacity(building)
	if quantity_capacity <= 0:
		return true
	var stored_quantity := 0
	for quantity in state.outputs.values():
		stored_quantity += int(quantity)
	var produced_quantity := 0
	for quantity in output.values():
		produced_quantity += int(quantity)
	return stored_quantity + produced_quantity <= quantity_capacity


func _is_output_full(building: BuildingInstance, state: ProducerState) -> bool:
	for job in state.jobs:
		if str((job as Dictionary).get("status", "")) == "output_full":
			return true
	if bool(_passive_output_blocked.get(building_key(building), false)):
		return true
	var quantity_capacity := _storage_quantity_capacity(building)
	if quantity_capacity > 0:
		var stored_quantity := 0
		for quantity in state.outputs.values():
			stored_quantity += int(quantity)
		if stored_quantity >= quantity_capacity:
			return true
	return state.output_capacity > 0 and state.outputs.size() >= state.output_capacity


func _resource_output_for(building: BuildingInstance, total_day: int) -> Dictionary:
	if not _has_effect(building, "resource_output"):
		return {}
	var config := _effect_config(building)
	if building.building_id == "mine":
		var tier := str(config.get("depth_tier", "shallow"))
		var table: Dictionary = config.get("depth_outputs", {})
		var output: Dictionary = table.get(tier, {}).duplicate(true)
		var interval := int(config.get("deep_bonus_every_days", 0))
		if tier == "deep" and interval > 0 and total_day % interval == 0:
			_merge_counts(output, config.get("deep_bonus_output", {}))
		return output
	var output: Dictionary = config.get("daily_output", {}).duplicate(true)
	var interval := int(config.get("bonus_every_days", 0))
	if interval > 0 and total_day % interval == 0:
		_merge_counts(output, config.get("bonus_output", {}))
	return output


func _ensure_passive_state(building: BuildingInstance) -> void:
	if building.producer_state != null or not _building_needs_passive_state(building):
		return
	building.producer_state = ProducerStateScript.new(building.building_id)
	building.producer_state.output_capacity = int(
		_effect_config(building).get("output_capacity", 3)
	)


func _building_needs_passive_state(building: BuildingInstance) -> bool:
	return (
		building != null
		and (
			building.building_id in ["beehive", "chicken_coop"]
			or _has_effect(building, "resource_output")
		)
	)


func _is_effect_building(building: BuildingInstance) -> bool:
	return (
		building != null
		and _effect_type(building) in [
			"honey",
			"animal",
			"irrigation",
			"ignore_season",
			"inventory_expand",
			"resource_output",
		]
	)


func _has_effect(building: BuildingInstance, effect_type: String) -> bool:
	return _effect_type(building) == effect_type


func _effect_type(building: BuildingInstance) -> String:
	if building == null:
		return ""
	if building.data != null:
		return building.data.effect_type
	return str(GameDataScript.get_building(building.building_id).get("effect", ""))


func _effect_config(building: BuildingInstance) -> Dictionary:
	if building == null:
		return {}
	if building.data != null:
		return building.data.effect_config
	return GameDataScript.get_building(building.building_id).get("effect_config", {})


func _footprint_for(building: BuildingInstance) -> Vector2i:
	if building != null and building.data != null:
		return building.data.footprint
	var source := GameDataScript.get_building(building.building_id if building != null else "")
	return Vector2i(int(source.get("footprint_x", 1)), int(source.get("footprint_z", 1)))


func _building_center(building: BuildingInstance) -> Vector2:
	var footprint := _footprint_for(building)
	return Vector2(
		float(building.grid_x) + float(footprint.x - 1) * 0.5,
		float(building.grid_z) + float(footprint.y - 1) * 0.5
	)


func _building_is_active(building: BuildingInstance) -> bool:
	return (
		building != null
		and is_instance_valid(building)
		and building.is_construction_complete()
	)


func _valid_registered_buildings() -> Array[BuildingInstance]:
	var result: Array[BuildingInstance] = []
	for building in _registered_buildings:
		if building != null and is_instance_valid(building):
			result.append(building)
	_registered_buildings = result.duplicate()
	return result


func _refresh_greenhouse_cells() -> void:
	if _farming_system == null:
		return
	var cells: Array = []
	var seen := {}
	for building in _valid_registered_buildings():
		if (
			not _building_is_active(building)
			or not _has_effect(building, "ignore_season")
			or is_maintenance_paused(building)
		):
			continue
		for position in get_greenhouse_cells(building):
			if not seen.has(position):
				seen[position] = true
				cells.append(position)
	_farming_system.set_greenhouse_cells(cells)


func _crop_has_flower_tag(crop_data: Variant) -> bool:
	if crop_data == null:
		return false
	if crop_data is Dictionary:
		return (
			str(crop_data.get("category", "")) == "flower"
			or "flower" in crop_data.get("tags", [])
		)
	var category: Variant = _property_value(crop_data, "category", "")
	var tags: Variant = _property_value(crop_data, "tags", [])
	return str(category) == "flower" or (tags is Array and "flower" in tags)


func _property_value(target: Object, property_name: String, fallback: Variant) -> Variant:
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return target.get(property_name)
	return fallback


func _merge_counts(target: Dictionary, additions: Dictionary) -> void:
	for item_id in additions:
		target[item_id] = int(target.get(item_id, 0)) + int(additions[item_id])


func _building_for_state(state: ProducerState) -> BuildingInstance:
	for building in _valid_registered_buildings():
		if _get_state(building) == state:
			return building
	return null


func _on_time_changed(hour: int, minute: int) -> void:
	if hour < 0 or hour >= 24 or minute < 0 or minute >= 60:
		return
	var current := hour * 60 + minute
	if not _clock_synced:
		_last_clock_minutes = current
		_clock_synced = true
		return
	if current == _last_clock_minutes:
		return
	var elapsed := 0
	if current > _last_clock_minutes:
		elapsed = current - _last_clock_minutes
	elif (
		_last_clock_minutes >= ROLLOVER_THRESHOLD_MINUTES
		and current >= DAY_START_MINUTES
		and current < ROLLOVER_THRESHOLD_MINUTES
	):
		elapsed = (24 * 60 - _last_clock_minutes) + (current - DAY_START_MINUTES)
	else:
		return
	_last_clock_minutes = current
	advance_minutes(elapsed)


func _advance_building(building: BuildingInstance, minutes: int) -> void:
	var state := _get_state(building)
	if state == null:
		return
	if is_maintenance_paused(building):
		return
	var base_minutes_remaining := minutes
	while base_minutes_remaining > 0:
		if not _prepare_running_job(building, state):
			return
		var current_job := state.jobs[0] as Dictionary
		var effective_needed := maxi(int(current_job.get("remaining_minutes", 0)), 1)
		var base_chunk := _base_minutes_for_effective_work(
			building,
			effective_needed,
			base_minutes_remaining
		)
		_advance_effective_minutes(
			building,
			state,
			_effective_minutes(building, base_chunk)
		)
		base_minutes_remaining -= base_chunk


func _base_minutes_for_effective_work(
	building: BuildingInstance,
	effective_needed: int,
	available_base_minutes: int
) -> int:
	if available_base_minutes <= 1:
		return maxi(available_base_minutes, 1)
	if _preview_effective_minutes(building, available_base_minutes) < effective_needed:
		return available_base_minutes
	var low := 1
	var high := available_base_minutes
	while low < high:
		var middle := (low + high) / 2
		if _preview_effective_minutes(building, middle) >= effective_needed:
			high = middle
		else:
			low = middle + 1
	return low


func _preview_effective_minutes(building: BuildingInstance, minutes: int) -> int:
	if minutes <= 0:
		return 0
	var speed_level := 0
	if _progression_system != null and is_instance_valid(_progression_system):
		speed_level = int(_progression_system.call("get_upgrade_level", building, "speed"))
	if speed_level <= 0:
		return minutes
	var percent := speed_level * 25
	var prior := int(speed_accumulators.get(building_key(building), 0))
	var whole_bonus := (minutes / 100) * percent
	whole_bonus += ((minutes % 100) * percent + prior) / 100
	return minutes + whole_bonus


func _prepare_running_job(building: BuildingInstance, state: ProducerState) -> bool:
	while not state.jobs.is_empty():
		var job: Dictionary = state.jobs[0]
		if int(job.remaining_minutes) <= 0:
			if not _store_completed_job(building, state, job):
				return false
			continue
		return true
	return false


func _advance_effective_minutes(
	building: BuildingInstance,
	state: ProducerState,
	effective_minutes: int
) -> void:
	var remaining := effective_minutes
	while not state.jobs.is_empty():
		var job: Dictionary = state.jobs[0]
		if remaining <= 0:
			return
		if int(job.remaining_minutes) <= 0:
			if not _store_completed_job(building, state, job):
				return
			continue
		job.status = "running"
		var consumed := mini(remaining, int(job.remaining_minutes))
		job.remaining_minutes = int(job.remaining_minutes) - consumed
		remaining -= consumed
		if int(job.remaining_minutes) > 0:
			return
		if not _store_completed_job(building, state, job):
			return


func _store_completed_job(
	building: BuildingInstance,
	state: ProducerState,
	job: Dictionary
) -> bool:
	var recipe := RecipeDatabaseScript.get_recipe(str(job.recipe_id))
	if recipe.is_empty():
		job.status = "invalid_recipe"
		return false
	var produced := _multiplied_counts(recipe.outputs, int(job.batches))
	if not state.can_store_outputs(produced):
		var was_blocked := str(job.get("status", "")) == "output_full"
		job.status = "output_full"
		if not was_blocked:
			_emit_event("production_output_blocked", [building, str(job.recipe_id)])
		return false
	if not state.add_outputs(produced):
		return false
	state.jobs.pop_front()
	if not state.jobs.is_empty():
		state.jobs[0].status = "running"
	for item_id in produced:
		_emit_event("production_output_changed", [building, str(item_id), state.get_output_count(str(item_id))])
	_emit_event("production_job_completed", [building, str(job.recipe_id), produced.duplicate(true)])
	return true


func _collect(
	building: BuildingInstance,
	inventory: InventorySystem,
	requested: Dictionary
) -> bool:
	var state := _get_state(building)
	if state == null or not _can_add_all(inventory, requested):
		return false
	var inventory_snapshot := _snapshot_inventory(inventory)
	var output_snapshot := state.outputs.duplicate(true)
	var owns_event_transaction := _begin_event_bus_transaction()
	var owns_mapping_transaction: bool = inventory.begin_mapping_transaction()
	for item_id in requested:
		if not inventory.add_item(str(item_id), int(requested[item_id])):
			_restore_inventory(inventory, inventory_snapshot)
			_end_mapping_transaction(inventory, owns_mapping_transaction, false)
			_end_inventory_event_transaction(owns_event_transaction, false, "item_added", requested)
			return false
	if not state.remove_outputs(requested):
		_restore_inventory(inventory, inventory_snapshot)
		state.outputs = output_snapshot
		_end_mapping_transaction(inventory, owns_mapping_transaction, false)
		_end_inventory_event_transaction(owns_event_transaction, false, "item_added", requested)
		return false
	_end_mapping_transaction(inventory, owns_mapping_transaction, true)
	_end_inventory_event_transaction(owns_event_transaction, true, "item_added", requested)
	for item_id in requested:
		_emit_event("production_output_changed", [building, str(item_id), state.get_output_count(str(item_id))])
	return true


func _can_add_all(inventory: InventorySystem, requested: Dictionary) -> bool:
	return inventory != null and bool(inventory.preflight_add_items(requested).get("ok", false))


func _get_state(building: BuildingInstance) -> ProducerState:
	if building == null or not is_instance_valid(building):
		return null
	return building.producer_state as ProducerState


func _effective_minutes(building: BuildingInstance, minutes: int) -> int:
	if minutes <= 0:
		return 0
	var speed_level := 0
	if _progression_system != null and is_instance_valid(_progression_system):
		speed_level = int(_progression_system.call("get_upgrade_level", building, "speed"))
	var key := building_key(building)
	if speed_level <= 0:
		speed_accumulators.erase(key)
		return minutes
	var percent := speed_level * 25
	var prior := int(speed_accumulators.get(key, 0))
	var whole_bonus := (minutes / 100) * percent
	var partial := (minutes % 100) * percent + prior
	whole_bonus += partial / 100
	speed_accumulators[key] = partial % 100
	return minutes + whole_bonus


func _apply_saved_upgrades(building: BuildingInstance) -> void:
	var state := _get_state(building)
	if state == null:
		return
	var queue_level := 0
	var storage_level := 0
	if _progression_system != null and is_instance_valid(_progression_system):
		queue_level = int(_progression_system.call("get_upgrade_level", building, "queue_slots"))
		storage_level = int(_progression_system.call("get_upgrade_level", building, "storage"))
	state.max_queue_slots = expected_max_queue_slots(queue_level)
	state.output_capacity = expected_output_capacity(building.building_id, storage_level)


func _base_output_capacity(building: BuildingInstance) -> int:
	return expected_output_capacity(building.building_id if building != null else "", 0)


func _storage_quantity_capacity(building: BuildingInstance) -> int:
	var level := 0
	if _progression_system != null and is_instance_valid(_progression_system):
		level = int(_progression_system.call("get_upgrade_level", building, "storage"))
	return expected_storage_quantity_capacity(building.building_id if building != null else "", level)


static func expected_max_queue_slots(queue_level: int) -> int:
	return 2 + maxi(queue_level, 0)


static func expected_output_capacity(building_id: String, storage_level: int) -> int:
	var source := GameDataScript.get_building(building_id)
	var config: Dictionary = source.get("effect_config", {})
	return maxi(int(config.get("output_capacity", 3)), 1) + maxi(storage_level, 0)


static func expected_storage_quantity_capacity(building_id: String, storage_level: int) -> int:
	var source := GameDataScript.get_building(building_id)
	var config: Dictionary = source.get("effect_config", {})
	var base := int(config.get("storage_quantity_capacity", 0))
	return base + maxi(storage_level, 0) if base > 0 else 0


func _multiplied_counts(counts: Dictionary, multiplier: int) -> Dictionary:
	var result := {}
	for item_id in counts:
		result[item_id] = int(counts[item_id]) * multiplier
	return result


func _snapshot_inventory(inventory: InventorySystem) -> Dictionary:
	return {
		"slots": inventory.slots.duplicate(true),
		"quick_slot_mappings": inventory.quick_slot_mappings.duplicate(),
	}


func _restore_inventory(inventory: InventorySystem, snapshot: Dictionary) -> void:
	inventory.restore_state(snapshot.slots, snapshot.quick_slot_mappings)


func _end_mapping_transaction(
	inventory: InventorySystem,
	owns_transaction: bool,
	commit_changes: bool
) -> void:
	if owns_transaction:
		inventory.end_mapping_transaction(commit_changes)


func _begin_event_bus_transaction() -> bool:
	if _event_bus == null:
		if is_inside_tree():
			_event_bus = get_node_or_null("/root/EventBus")
		else:
			var loop := Engine.get_main_loop()
			_event_bus = loop.root.get_node_or_null("EventBus") if loop is SceneTree else null
	if _event_bus == null or _event_bus.is_blocking_signals():
		return false
	_event_bus.set_block_signals(true)
	return true


func _end_inventory_event_transaction(
	owns_transaction: bool,
	commit_changes: bool,
	signal_name: StringName,
	quantities: Dictionary
) -> void:
	if not owns_transaction or _event_bus == null:
		return
	_event_bus.set_block_signals(false)
	if not commit_changes:
		return
	for item_id in quantities:
		_event_bus.emit_signal(signal_name, str(item_id), int(quantities[item_id]))


func _emit_event(signal_name: StringName, arguments: Array) -> void:
	if _event_bus == null:
		_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if _event_bus != null and _event_bus.has_signal(signal_name):
		_event_bus.callv("emit_signal", [signal_name] + arguments)
