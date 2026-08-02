class_name ProductionSystem
extends Node

const GameDataScript = preload("res://scripts/core/game_data.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const ProducerStateScript = preload("res://scripts/data/producer_state.gd")
const ProgressionScript = preload("res://scripts/systems/economy_progression_system.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")

const DAY_START_MINUTES := 6 * 60
const ROLLOVER_THRESHOLD_MINUTES := 18 * 60
const MAINTENANCE_INTERVAL_DAYS := 7
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
var speed_accumulators: Dictionary = {}
var _active_maintenance_transactions: Dictionary = {}


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
	snapshot["maintenance_paused"] = is_maintenance_overdue(building)
	snapshot["storage_quantity_capacity"] = _storage_quantity_capacity(building)
	if bool(snapshot.maintenance_paused) and not snapshot.jobs.is_empty():
		snapshot.jobs[0].status = "maintenance_paused"
	return snapshot


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
	if is_maintenance_overdue(building):
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
	var stale: Array[BuildingInstance] = []
	for building in _registered_buildings:
		if not is_instance_valid(building):
			stale.append(building)
			continue
		if not _building_is_active(building):
			continue
		_advance_building(building, minutes)
	for building in stale:
		_registered_buildings.erase(building)


func collect_all(building: BuildingInstance, inventory: InventorySystem) -> bool:
	var state := _get_state(building)
	if state == null or inventory == null or state.outputs.is_empty():
		return false
	return _collect(building, inventory, state.outputs.duplicate(true))


func collect_item(
	building: BuildingInstance,
	item_id: String,
	inventory: InventorySystem
) -> bool:
	var state := _get_state(building)
	if state == null or inventory == null:
		return false
	var quantity := state.get_output_count(item_id)
	if quantity <= 0:
		return false
	return _collect(building, inventory, {item_id: quantity})


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
			or is_maintenance_overdue(building)
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
	_current_day = total_day
	_refresh_greenhouse_cells()
	return true


func sync_daily_cursor(total_day: int) -> bool:
	if total_day < 0 or total_day > MAX_SAFE_DATE:
		return false
	_last_daily_effects_day = total_day
	_last_finished_outputs_day = total_day
	_current_day = total_day
	_refresh_greenhouse_cells()
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
	return true


func unregister_building(building: BuildingInstance) -> void:
	_registered_buildings.erase(building)
	if building != null:
		var key := building_key(building)
		maintenance_due_days.erase(key)
		speed_accumulators.erase(key)
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
	maintenance_due_days[building_key(building)] = due_day
	return true


func is_maintenance_overdue(building: BuildingInstance) -> bool:
	var due_day := get_maintenance_due_day(building)
	return due_day >= 0 and _current_day >= due_day


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
	return true


func reset_maintenance(total_day: int = 0) -> bool:
	if total_day < 0 or total_day > MAX_SAFE_DATE:
		return false
	_current_day = total_day
	maintenance_due_days.clear()
	speed_accumulators.clear()
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
	if building == null or _grid_system == null or not _has_effect(building, "irrigation"):
		return result
	var radius := float(_effect_config(building).get("radius", 4))
	var center := _building_center(building)
	for gz in range(floori(center.y - radius), ceili(center.y + radius) + 1):
		for gx in range(floori(center.x - radius), ceili(center.x + radius) + 1):
			if Vector2(gx, gz).distance_to(center) > radius + 0.0001:
				continue
			var cell := _grid_system.get_cell(gx, gz)
			if cell != null and cell.state in [GridCell.State.FARMLAND, GridCell.State.PLANTED]:
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


func is_greenhouse_water_connected(greenhouse: BuildingInstance) -> bool:
	var greenhouse_cells := get_greenhouse_cells(greenhouse)
	if greenhouse_cells.is_empty():
		return false
	for building in _valid_registered_buildings():
		if not _building_is_active(building) or not _has_effect(building, "irrigation"):
			continue
		if not is_water_connected(building):
			continue
		var radius := float(_effect_config(building).get("radius", 4))
		var center := _building_center(building)
		for position in greenhouse_cells:
			if Vector2(position.x, position.y).distance_to(center) <= radius + 0.0001:
				return true
	return false


func collect_nearby_outputs(
	barn: BuildingInstance,
	inventory: InventorySystem = null
) -> bool:
	var destination := inventory if inventory != null else _inventory_system
	if barn == null or destination == null or not _has_effect(barn, "inventory_expand"):
		return false
	var radius := float(_effect_config(barn).get("collection_radius", 6))
	var center := _building_center(barn)
	var sources: Array[Dictionary] = []
	var combined := {}
	for building in _valid_registered_buildings():
		if building == barn or not _building_is_active(building):
			continue
		var state := _get_state(building)
		if state == null or state.outputs.is_empty():
			continue
		if _building_center(building).distance_to(center) > radius + 0.0001:
			continue
		var outputs: Dictionary = state.outputs.duplicate(true)
		sources.append({"state": state, "outputs": outputs})
		_merge_counts(combined, outputs)
	if sources.is_empty() or not _can_add_all(destination, combined):
		return false
	var inventory_snapshot := _snapshot_inventory(destination)
	var owns_event_transaction := _begin_event_bus_transaction()
	var owns_mapping_transaction: bool = destination.begin_mapping_transaction()
	for item_id in combined:
		if not destination.add_item(str(item_id), int(combined[item_id])):
			_restore_inventory(destination, inventory_snapshot)
			_end_mapping_transaction(destination, owns_mapping_transaction, false)
			_end_inventory_event_transaction(owns_event_transaction, false, "item_added", combined)
			return false
	for source in sources:
		var state := source.state as ProducerState
		if not state.remove_outputs(source.outputs):
			_restore_inventory(destination, inventory_snapshot)
			for rollback_source in sources:
				(rollback_source.state as ProducerState).outputs = rollback_source.outputs.duplicate(true)
			_end_mapping_transaction(destination, owns_mapping_transaction, false)
			_end_inventory_event_transaction(owns_event_transaction, false, "item_added", combined)
			return false
	_end_mapping_transaction(destination, owns_mapping_transaction, true)
	_end_inventory_event_transaction(owns_event_transaction, true, "item_added", combined)
	for source in sources:
		var state := source.state as ProducerState
		for item_id in source.outputs:
			var owner := _building_for_state(state)
			if owner != null:
				_emit_event("production_output_changed", [owner, str(item_id), state.get_output_count(str(item_id))])
	return true


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
	if is_maintenance_overdue(building):
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
	if output.is_empty() or not _can_store_passive_outputs(building, state, output):
		return
	var inputs_snapshot: Dictionary = state.inputs.duplicate(true)
	var outputs_snapshot: Dictionary = state.outputs.duplicate(true)
	if id == "chicken_coop":
		var config := _effect_config(building)
		var feed_item := str(config.get("feed_item", "animal_feed"))
		var feed_count := int(config.get("feed_per_day", 1))
		if feed_count <= 0 or not state.remove_input(feed_item, feed_count):
			return
	if not state.add_outputs(output):
		state.inputs = inputs_snapshot
		state.outputs = outputs_snapshot
		return
	if id == "chicken_coop":
		var feed_item := str(_effect_config(building).get("feed_item", "animal_feed"))
		_emit_event("production_input_changed", [building, feed_item, state.get_input_count(feed_item)])
	for item_id in output:
		_emit_event("production_output_changed", [building, str(item_id), state.get_output_count(str(item_id))])


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
	for building in _registered_buildings.duplicate():
		if building == null or not is_instance_valid(building):
			_registered_buildings.erase(building)
		else:
			result.append(building)
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
			or is_maintenance_overdue(building)
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
	if is_maintenance_overdue(building):
		return
	for _minute in range(minutes):
		if not _prepare_running_job(building, state):
			return
		_advance_effective_minutes(building, state, _effective_minutes(building, 1))


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
	if inventory == null or requested.is_empty():
		return false
	var simulated: Array = inventory.slots.duplicate(true)
	for item_id_value in requested:
		var item_id := str(item_id_value)
		var quantity := int(requested[item_id_value])
		var item_data = GameDataScript.get_item(item_id)
		if item_data == null or quantity <= 0:
			return false
		var max_stack := int(item_data.get("max_stack", 99))
		for index in range(simulated.size()):
			var slot: Dictionary = simulated[index]
			if slot.get("item_id", "") != item_id:
				continue
			var added := mini(quantity, max_stack - int(slot.get("quantity", 0)))
			if added > 0:
				slot.quantity = int(slot.get("quantity", 0)) + added
				quantity -= added
			if quantity <= 0:
				break
		for index in range(simulated.size()):
			if quantity <= 0:
				break
			if (simulated[index] as Dictionary).is_empty():
				var added := mini(quantity, max_stack)
				simulated[index] = {"item_id": item_id, "quantity": added}
				quantity -= added
		if quantity > 0:
			return false
	return true


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
