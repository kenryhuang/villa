class_name FishingSystem
extends Node

signal session_state_changed(previous_state: int, next_state: int, session_id: int)
signal catch_settled(spot_id: String, item_id: String, quantity: int)
signal session_failed(spot_id: String, reason: String)

const GameDataScript = preload("res://scripts/core/game_data.gd")
const FishingSpotDataScript = preload("res://scripts/data/fishing_spot_data.gd")
const SAVE_VERSION := 1
const CAST_SECONDS := 0.5
const MIN_BITE_WAIT_SECONDS := 2.0
const MAX_BITE_WAIT_SECONDS := 6.0
const BITE_WINDOW_SECONDS := 1.0
const COOLDOWN_SECONDS := 0.5
const DAYS_PER_SEASON := 7

enum SessionState {
	IDLE,
	CASTING,
	WAITING_BITE,
	BITE_WINDOW,
	RESOLVING,
	COOLDOWN,
}

var _grid: GridSystem
var _geography: RefCounted
var _inventory: InventorySystem
var _world_seed := 0
var _fishing_tables: Dictionary = {}
var _spots: Dictionary = {}
var _spot_states: Dictionary = {}
var _unique_catches: Dictionary = {}
var _state := SessionState.IDLE
var _active_session: Dictionary = {}
var _seconds_remaining := 0.0
var _next_session_id := 1
var _closed_sessions: Dictionary = {}
var _cast_cost_preflight_callback := Callable()
var _cast_cost_callback := Callable()


func _init() -> void:
	set_process(false)


func _process(delta: float) -> void:
	advance_realtime(delta)


func configure(
	grid: GridSystem,
	geography: RefCounted,
	inventory: InventorySystem,
	game_data: Variant,
	world_seed: int
) -> bool:
	if grid == null or geography == null or inventory == null:
		return false
	var tables: Variant = {}
	if game_data is Dictionary:
		tables = (game_data as Dictionary).get("FISHING_TABLES", {})
	else:
		tables = GameDataScript.FISHING_TABLES
	if not tables is Dictionary or (tables as Dictionary).is_empty():
		return false
	_grid = grid
	_geography = geography
	_inventory = inventory
	_world_seed = world_seed
	_fishing_tables = (tables as Dictionary).duplicate(true)
	return true


func set_cast_cost_callbacks(preflight_callback: Callable, commit_callback: Callable) -> bool:
	if not preflight_callback.is_valid() or not commit_callback.is_valid():
		return false
	_cast_cost_preflight_callback = preflight_callback
	_cast_cost_callback = commit_callback
	return true


func register_spot(spot: Resource) -> bool:
	if (
		spot == null
		or not spot.is_valid()
		or _grid == null
		or not _fishing_tables.has(spot.fish_table_id)
		or _spots.has(spot.spot_id)
		or _grid.get_cell(spot.stand_cell.x, spot.stand_cell.y) == null
		or _grid.get_cell(spot.water_cell.x, spot.water_cell.y) == null
		or _grid.get_cell(spot.water_cell.x, spot.water_cell.y).state != GridCell.State.WATER
		or not bool(_geography.call(
			"footprint_borders_natural_water", spot.stand_cell, Vector2i.ONE
		))
	):
		return false
	_spots[spot.spot_id] = spot.duplicate_data()
	_spot_states[spot.spot_id] = _new_spot_state(0)
	return true


func start_cast(
	spot_id: String,
	player_position: Vector3,
	total_day: int,
	hour: int,
	minute: int
) -> Dictionary:
	var failure := {"ok": false, "reason": "invalid_request"}
	if _state != SessionState.IDLE:
		failure.reason = "busy"
		return failure
	var spot: Variant = _spots.get(spot_id)
	if spot == null:
		failure.reason = "unknown_spot"
		return failure
	if total_day <= 0 or hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return failure
	_reset_spot_for_day(spot_id, total_day)
	var durable_state := _spot_states[spot_id] as Dictionary
	if int(durable_state.success_count) >= spot.daily_capacity:
		failure.reason = "depleted"
		return failure
	var stand_world := _grid.grid_to_world(spot.stand_cell.x, spot.stand_cell.y)
	if Vector2(player_position.x, player_position.z).distance_to(stand_world) > spot.max_distance:
		failure.reason = "too_far"
		return failure
	var water := _grid.get_cell(spot.water_cell.x, spot.water_cell.y)
	if water == null or water.state != GridCell.State.WATER:
		failure.reason = "water_required"
		return failure
	if not bool(_geography.call("is_clear_cast_line", spot.stand_cell, spot.water_cell)):
		failure.reason = "cast_blocked"
		return failure
	var candidates := _eligible_catches(spot.fish_table_id, total_day, hour, minute)
	if candidates.is_empty():
		failure.reason = "no_candidates"
		return failure
	var next_sequence := int(durable_state.cast_sequence) + 1
	var selected := _select_weighted(candidates, spot_id, total_day, next_sequence)
	var item_id := str(selected.get("item_id", ""))
	if item_id.is_empty():
		failure.reason = "no_candidates"
		return failure
	if not _preflight_cast_cost():
		failure.reason = "tool_unavailable"
		return failure
	var capacity_reservation: Variant = _inventory.reserve_item_capacity(item_id, 1)
	if capacity_reservation == null:
		failure.reason = "inventory_full"
		return failure
	durable_state.cast_sequence = next_sequence
	var session_id := _next_session_id
	_next_session_id += 1
	_active_session = {
		"session_id": session_id,
		"spot_id": spot_id,
		"item_id": item_id,
		"total_day": total_day,
		"cast_sequence": next_sequence,
		"capacity_reservation": capacity_reservation,
	}
	_transition_to(SessionState.CASTING, CAST_SECONDS)
	return {"ok": true, "reason": "", "session_id": session_id, "item_id": item_id}


func advance_realtime(delta: float) -> void:
	if _state == SessionState.IDLE or not is_finite(delta) or delta <= 0.0:
		return
	var remaining_delta := delta
	while remaining_delta > 0.000001 and _state != SessionState.IDLE:
		var consumed := minf(remaining_delta, _seconds_remaining)
		_seconds_remaining -= consumed
		remaining_delta -= consumed
		if _seconds_remaining > 0.000001:
			return
		match _state:
			SessionState.CASTING:
				if not _commit_cast_cost():
					_fail_and_idle("cast_cost_failed")
					return
				_transition_to(SessionState.WAITING_BITE, _bite_wait_seconds())
			SessionState.WAITING_BITE:
				_transition_to(SessionState.BITE_WINDOW, BITE_WINDOW_SECONDS)
			SessionState.BITE_WINDOW:
				_release_capacity_reservation()
				_mark_closed_session()
				var spot_id := str(_active_session.get("spot_id", ""))
				session_failed.emit(spot_id, "missed_bite")
				_transition_to(SessionState.COOLDOWN, COOLDOWN_SECONDS)
			SessionState.RESOLVING:
				_transition_to(SessionState.COOLDOWN, COOLDOWN_SECONDS)
			SessionState.COOLDOWN:
				_finish_to_idle()
			_:
				_finish_to_idle()


func reel(session_id: int) -> Dictionary:
	if _closed_sessions.has(session_id):
		return {"ok": false, "reason": "stale_session"}
	if int(_active_session.get("session_id", -1)) != session_id:
		return {"ok": false, "reason": "stale_session"}
	if _state != SessionState.BITE_WINDOW:
		return {"ok": false, "reason": "not_biting"}
	_transition_to(SessionState.RESOLVING, 0.0)
	var spot_id := str(_active_session.spot_id)
	var item_id := str(_active_session.item_id)
	var spot: Variant = _spots.get(spot_id)
	var durable_state := _spot_states.get(spot_id) as Dictionary
	if (
		spot == null
		or durable_state == null
		or int(durable_state.success_count) >= spot.daily_capacity
		or not _commit_capacity_reservation()
	):
		_release_capacity_reservation()
		_mark_closed_session()
		session_failed.emit(spot_id, "settlement_failed")
		_transition_to(SessionState.COOLDOWN, COOLDOWN_SECONDS)
		return {"ok": false, "reason": "settlement_failed"}
	durable_state.success_count = int(durable_state.success_count) + 1
	if _is_unique_item(item_id):
		_unique_catches[item_id] = true
	_mark_closed_session()
	catch_settled.emit(spot_id, item_id, 1)
	_transition_to(SessionState.COOLDOWN, COOLDOWN_SECONDS)
	return {"ok": true, "reason": "", "item_id": item_id, "quantity": 1}


func cancel(reason: String) -> bool:
	if _state == SessionState.IDLE:
		return false
	var spot_id := str(_active_session.get("spot_id", ""))
	_mark_closed_session()
	if not reason.is_empty():
		session_failed.emit(spot_id, reason)
	_finish_to_idle()
	return true


func get_session_state() -> int:
	return _state


func is_session_active() -> bool:
	return _state != SessionState.IDLE


func get_session_snapshot() -> Dictionary:
	var result := _active_session.duplicate(true)
	result.erase("capacity_reservation")
	result["state"] = _state
	result["seconds_remaining"] = _seconds_remaining
	return result


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"spots": _spot_states.duplicate(true),
		"unique_catches": _unique_catches.keys(),
	}


func validate_dict(value: Dictionary) -> bool:
	if not _is_integer_in_range(value.get("version"), SAVE_VERSION, SAVE_VERSION):
		return false
	var states: Variant = value.get("spots")
	var unique_values: Variant = value.get("unique_catches")
	if not states is Dictionary or not unique_values is Array:
		return false
	if (states as Dictionary).size() != _spots.size():
		return false
	for spot_id_value in states:
		var spot_id := str(spot_id_value)
		var spot: Variant = _spots.get(spot_id)
		var state_value: Variant = (states as Dictionary).get(spot_id_value)
		if spot == null or not state_value is Dictionary:
			return false
		var state := state_value as Dictionary
		if state.keys().size() != 3 or not state.has_all(["success_count", "cast_sequence", "reset_day"]):
			return false
		if (
			not _is_integer_in_range(state.success_count, 0, spot.daily_capacity)
			or not _is_integer_in_range(state.cast_sequence, 0, 0x7fffffff)
			or not _is_integer_in_range(state.reset_day, 0, 0x7fffffff)
		):
			return false
	var seen := {}
	for item_id_value in unique_values:
		if not item_id_value is String:
			return false
		var item_id := str(item_id_value)
		if seen.has(item_id) or not _is_unique_item(item_id):
			return false
		seen[item_id] = true
	return true


func from_dict(value: Dictionary) -> bool:
	if not validate_dict(value):
		return false
	cancel("restore")
	var normalized_states := {}
	for spot_id_value in (value.spots as Dictionary):
		var state := (value.spots as Dictionary)[spot_id_value] as Dictionary
		normalized_states[str(spot_id_value)] = {
			"success_count": int(state.success_count),
			"cast_sequence": int(state.cast_sequence),
			"reset_day": int(state.reset_day),
		}
	_spot_states = normalized_states
	_unique_catches.clear()
	for item_id in value.unique_catches:
		_unique_catches[str(item_id)] = true
	return true


func reset_state(unique_items: Array = []) -> bool:
	cancel("reset")
	for spot_id in _spots:
		_spot_states[spot_id] = _new_spot_state(0)
	_unique_catches.clear()
	for item_id_value in unique_items:
		var item_id := str(item_id_value)
		if _is_unique_item(item_id):
			_unique_catches[item_id] = true
	return true


func _eligible_catches(table_id: String, total_day: int, hour: int, minute: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var table_value: Variant = _fishing_tables.get(table_id, [])
	if not table_value is Array:
		return result
	var season := ((total_day - 1) / DAYS_PER_SEASON) % 4
	var time_value := float(hour) + float(minute) / 60.0
	for entry_value in table_value:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var item_id := str(entry.get("item_id", ""))
		if (
			item_id.is_empty()
			or GameDataScript.get_item(item_id) == null
			or float(entry.get("weight", 0.0)) <= 0.0
			or not season in entry.get("seasons", [])
			or (bool(entry.get("unique", false)) and _unique_catches.has(item_id))
			or not _time_matches(entry.get("hour_ranges", []), time_value)
		):
			continue
		result.append(entry.duplicate(true))
	return result


func _time_matches(ranges: Variant, time_value: float) -> bool:
	if not ranges is Array:
		return false
	for range_value in ranges:
		if not range_value is Array or (range_value as Array).size() != 2:
			continue
		var values := range_value as Array
		if time_value >= float(values[0]) and time_value < float(values[1]):
			return true
	return false


func _select_weighted(
	candidates: Array[Dictionary],
	spot_id: String,
	total_day: int,
	cast_sequence: int
) -> Dictionary:
	var total_weight := 0.0
	for entry in candidates:
		total_weight += float(entry.weight)
	if total_weight <= 0.0:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = _session_seed(spot_id, total_day, cast_sequence)
	var target := rng.randf() * total_weight
	var cumulative := 0.0
	for entry in candidates:
		cumulative += float(entry.weight)
		if target <= cumulative:
			return entry
	return candidates.back()


func _session_seed(spot_id: String, total_day: int, cast_sequence: int) -> int:
	var value := int(_world_seed) * 1103515245
	value ^= int(spot_id.hash()) * 2654435761
	value ^= total_day * 97531
	value ^= cast_sequence * 7919
	return value


func _bite_wait_seconds() -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = _session_seed(
		str(_active_session.get("spot_id", "")),
		int(_active_session.get("total_day", 0)),
		int(_active_session.get("cast_sequence", 0))
	) ^ 0x5A17
	return rng.randf_range(MIN_BITE_WAIT_SECONDS, MAX_BITE_WAIT_SECONDS)


func _commit_cast_cost() -> bool:
	return _cast_cost_callback.is_valid() and bool(_cast_cost_callback.call())


func _preflight_cast_cost() -> bool:
	return _cast_cost_preflight_callback.is_valid() and bool(_cast_cost_preflight_callback.call())


func _commit_capacity_reservation() -> bool:
	var token: Variant = _active_session.get("capacity_reservation")
	if token == null or not _inventory.commit_item_capacity_reservation(token):
		return false
	_active_session.erase("capacity_reservation")
	return true


func _release_capacity_reservation() -> void:
	var token: Variant = _active_session.get("capacity_reservation")
	if token != null:
		_inventory.release_item_capacity_reservation(token)
	_active_session.erase("capacity_reservation")


func _transition_to(next_state: int, duration: float) -> void:
	var previous := _state
	_state = next_state as SessionState
	_seconds_remaining = maxf(duration, 0.0)
	set_process(_state != SessionState.IDLE)
	session_state_changed.emit(previous, _state, int(_active_session.get("session_id", 0)))


func _fail_and_idle(reason: String) -> void:
	var spot_id := str(_active_session.get("spot_id", ""))
	_mark_closed_session()
	session_failed.emit(spot_id, reason)
	_finish_to_idle()


func _finish_to_idle() -> void:
	_release_capacity_reservation()
	var previous := _state
	var session_id := int(_active_session.get("session_id", 0))
	_state = SessionState.IDLE
	_seconds_remaining = 0.0
	_active_session.clear()
	set_process(false)
	session_state_changed.emit(previous, _state, session_id)


func _mark_closed_session() -> void:
	var session_id := int(_active_session.get("session_id", 0))
	if session_id > 0:
		_closed_sessions[session_id] = true
		if _closed_sessions.size() > 64:
			var ids: Array = _closed_sessions.keys()
			ids.sort()
			_closed_sessions.erase(ids[0])


func _reset_spot_for_day(spot_id: String, total_day: int) -> void:
	var state := _spot_states.get(spot_id) as Dictionary
	if state == null:
		state = _new_spot_state(total_day)
		_spot_states[spot_id] = state
	if int(state.reset_day) != total_day:
		state.success_count = 0
		state.cast_sequence = 0
		state.reset_day = total_day


func _new_spot_state(reset_day: int) -> Dictionary:
	return {"success_count": 0, "cast_sequence": 0, "reset_day": reset_day}


func _is_unique_item(item_id: String) -> bool:
	for table_value in _fishing_tables.values():
		if not table_value is Array:
			continue
		for entry_value in table_value:
			if (
				entry_value is Dictionary
				and str((entry_value as Dictionary).get("item_id", "")) == item_id
				and bool((entry_value as Dictionary).get("unique", false))
			):
				return true
	return false


func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
		and float(value) >= float(minimum)
		and float(value) <= float(maximum)
	)
