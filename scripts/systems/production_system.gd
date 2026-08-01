class_name ProductionSystem
extends Node

const GameDataScript = preload("res://scripts/core/game_data.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const ProducerStateScript = preload("res://scripts/data/producer_state.gd")

const DAY_START_MINUTES := 6 * 60
const ROLLOVER_THRESHOLD_MINUTES := 18 * 60

var _registered_buildings: Array[BuildingInstance] = []
var _clock_synced := false
var _last_clock_minutes := 0
var _last_daily_effects_day := -1
var _last_finished_outputs_day := -1
var _event_bus: Node


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")
	if _event_bus != null and not _event_bus.time_changed.is_connected(_on_time_changed):
		_event_bus.time_changed.connect(_on_time_changed)


func get_building_snapshot(building: BuildingInstance) -> Dictionary:
	var state := _get_state(building)
	if state == null:
		return {}
	var snapshot: Dictionary = state.to_dict()
	snapshot["building_id"] = building.building_id
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
	var recipe := RecipeDatabaseScript.get_recipe(recipe_id)
	if recipe.is_empty():
		failure.reason = "unknown_recipe"
		return failure
	if str(recipe.station) != state.station_id:
		failure.reason = "station_mismatch"
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
	for item_id in inputs:
		if not inventory.remove_item(str(item_id), int(inputs[item_id])):
			_restore_inventory(inventory, inventory_snapshot)
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
		_end_inventory_event_transaction(owns_event_transaction, false, "item_removed", inputs)
		return false
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
	if not inventory.remove_item(item_id, quantity) or not state.add_input(item_id, quantity):
		_restore_inventory(inventory, inventory_snapshot)
		state.inputs = inputs_snapshot
		_end_inventory_event_transaction(
			owns_event_transaction,
			false,
			"item_removed",
			{item_id: quantity}
		)
		return false
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
	if total_day <= _last_daily_effects_day:
		return
	_last_daily_effects_day = total_day


func finish_daily_outputs(total_day: int) -> void:
	if total_day <= _last_finished_outputs_day:
		return
	_last_finished_outputs_day = total_day


func sync_clock(hour: int, minute: int) -> bool:
	if hour < 0 or hour >= 24 or minute < 0 or minute >= 60:
		return false
	_last_clock_minutes = hour * 60 + minute
	_clock_synced = true
	return true


func register_building(building: BuildingInstance) -> bool:
	if _get_state(building) == null:
		return false
	if not _registered_buildings.has(building):
		_registered_buildings.append(building)
	return true


func unregister_building(building: BuildingInstance) -> void:
	_registered_buildings.erase(building)


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
	var remaining := minutes
	while not state.jobs.is_empty():
		var job: Dictionary = state.jobs[0]
		if int(job.remaining_minutes) <= 0:
			if not _store_completed_job(building, state, job):
				return
			continue
		if remaining <= 0:
			return
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
	for item_id in requested:
		if not inventory.add_item(str(item_id), int(requested[item_id])):
			_restore_inventory(inventory, inventory_snapshot)
			_end_inventory_event_transaction(owns_event_transaction, false, "item_added", requested)
			return false
	if not state.remove_outputs(requested):
		_restore_inventory(inventory, inventory_snapshot)
		state.outputs = output_snapshot
		_end_inventory_event_transaction(owns_event_transaction, false, "item_added", requested)
		return false
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


func _begin_event_bus_transaction() -> bool:
	if _event_bus == null:
		_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
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
