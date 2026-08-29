class_name VisibleNpcFarmSystem
extends Node

signal work_available
signal work_finished(intent: Dictionary, result: Dictionary)

const FARM_WIDTH := 5
const FARM_HEIGHT := 4
const PLOT_COUNT := FARM_WIDTH * FARM_HEIGHT
const SEARCH_RADIUS := 12

var _grid: GridSystem
var _farming: FarmingSystem
var _economy: Variant
var _game_data: Variant
var _agent_id := ""
var _spawn_grid := Vector2i(-1, -1)
var _anchor := Vector2i(-1, -1)
var _plots: Array[Dictionary] = []
var _work_queue: Array[Dictionary] = []
var _finished: Dictionary = {}


func configure(
	grid: GridSystem,
	farming: FarmingSystem,
	economy: Variant,
	game_data: Variant,
	agent_id: String,
	spawn_position: Vector3
) -> bool:
	if grid == null or farming == null or agent_id.strip_edges().is_empty():
		return false
	_grid = grid
	_farming = farming
	_economy = economy
	_game_data = game_data
	if _game_data != null:
		_farming.set("_game_data", _game_data)
	_agent_id = agent_id
	var spawn_grid := _grid.world_to_grid(spawn_position.x, spawn_position.z)
	_spawn_grid = spawn_grid
	var anchor := _select_anchor(spawn_grid)
	if anchor.x < 0:
		return false
	return _apply_anchor(anchor)


func get_plot_count(agent_id: String) -> int:
	return _plots.size() if agent_id == _agent_id else 0


func get_plot(agent_id: String, plot_index: int) -> Dictionary:
	if agent_id != _agent_id or plot_index < 0 or plot_index >= _plots.size():
		return {}
	return (_plots[plot_index] as Dictionary).duplicate(true)


func get_plot_cell(agent_id: String, plot_index: int) -> GridCell:
	var plot := get_plot(agent_id, plot_index)
	if plot.is_empty() or _grid == null:
		return null
	var coordinate: Vector2i = plot.coordinate
	return _grid.get_cell(coordinate.x, coordinate.y)


func get_snapshot(agent_id: String, _absolute_game_minute: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if agent_id != _agent_id:
		return result
	for plot in _plots:
		var index := int(plot.plot_index)
		var cell := get_plot_cell(agent_id, index)
		if cell == null:
			continue
		var record := (plot as Dictionary).duplicate(true)
		record.world_position = cell.world_position_3d()
		record.owner_id = _grid.get_cell_owner(cell.gx, cell.gz)
		record.reachable = true
		record.queued = _plot_is_queued(index)
		record.crop = {}
		record.growth_progress = 0.0
		record.remaining_minutes = 0
		record.season_valid = true
		match cell.state:
			GridCell.State.WASTELAND:
				record.state = "untilled"
			GridCell.State.FARMLAND:
				record.state = "tilled"
			GridCell.State.PLANTED:
				_populate_crop_snapshot(record, cell)
			_:
				record.state = "blocked"
		result.append(record)
	return result


func get_anchor() -> Vector2i:
	return _anchor


func has_pending_work(agent_id: String) -> bool:
	for record in _work_queue:
		if str(record.agent_id) == agent_id:
			return true
	return false


func queue_batch(intent: Dictionary, game_minute: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var agent_id := str(intent.get("agent_id", ""))
	if agent_id != _agent_id:
		return [{"ok": false, "error": "unknown_farm"}]
	var projected: Array[Dictionary] = get_snapshot(agent_id, game_minute)
	var seed_counts := _seed_counts(agent_id)
	for action_value in intent.get("actions", []):
		var action := (action_value as Dictionary).duplicate(true)
		action.agent_id = agent_id
		action.decision_id = str(intent.get("decision_id", ""))
		action.expected_revision = int(intent.get("expected_revision", 0))
		var key := str(action.get("idempotency_key", ""))
		if _finished.has(key):
			results.append((_finished[key] as Dictionary).duplicate(true))
			continue
		var existing := _find_queued(key)
		if not existing.is_empty():
			results.append(_queued_result(existing))
			continue
		var validation := _validate_projected(action, projected, seed_counts)
		if not bool(validation.get("ok", false)):
			results.append(validation)
			break
		var record := {
			"agent_id": agent_id,
			"request_id": str(intent.get("request_id", "")),
			"decision_id": str(action.decision_id),
			"action_id": str(action.get("action_id", "")),
			"idempotency_key": key,
			"tool_name": str(action.get("tool_name", "")),
			"arguments": (action.get("arguments", {}) as Dictionary).duplicate(true),
			"queued_game_minute": game_minute,
			"status": "queued",
		}
		_work_queue.append(record)
		results.append(_queued_result(record))
	if not _work_queue.is_empty():
		work_available.emit()
	return results


func peek_work() -> Dictionary:
	return (_work_queue[0] as Dictionary).duplicate(true) if not _work_queue.is_empty() else {}


func mark_work_started(idempotency_key: String) -> bool:
	if _work_queue.is_empty() or str(_work_queue[0].idempotency_key) != idempotency_key:
		return false
	_work_queue[0].status = "working"
	return true


func complete_work(idempotency_key: String) -> Dictionary:
	if _work_queue.is_empty() or str(_work_queue[0].idempotency_key) != idempotency_key:
		return {"ok": false, "error": "work_not_ready"}
	var intent := (_work_queue[0] as Dictionary).duplicate(true)
	var result := _commit_action(intent)
	_work_queue.pop_front()
	_finished[idempotency_key] = result.duplicate(true)
	work_finished.emit(intent, result)
	if not _work_queue.is_empty():
		work_available.emit()
	return result


func fail_work(idempotency_key: String, code: String) -> Dictionary:
	if _work_queue.is_empty() or str(_work_queue[0].idempotency_key) != idempotency_key:
		return {"ok": false, "error": "work_not_ready"}
	var intent := (_work_queue[0] as Dictionary).duplicate(true)
	var result := {"ok": false, "error": code}
	_work_queue.pop_front()
	_finished[idempotency_key] = result.duplicate(true)
	work_finished.emit(intent, result)
	if not _work_queue.is_empty():
		work_available.emit()
	return result


func to_dict() -> Dictionary:
	var plots: Array[Dictionary] = []
	for plot in _plots:
		plots.append({
			"plot_index": int(plot.plot_index),
			"coordinate": [int(plot.coordinate.x), int(plot.coordinate.y)],
		})
	return {
		"version": 1,
		"agent_id": _agent_id,
		"anchor": [_anchor.x, _anchor.y],
		"plots": plots,
		"work_queue": _work_queue.duplicate(true),
		"finished": _finished.duplicate(true),
	}


func restore_queue(value: Dictionary) -> bool:
	if not validate_dict(value) or str(value.get("agent_id", "")) != _agent_id:
		return false
	var coordinates: Array[Vector2i] = []
	var plots: Array[Dictionary] = []
	for plot_value in value.plots:
		var plot := plot_value as Dictionary
		var coordinate_values: Array = plot.coordinate
		var coordinate := Vector2i(int(coordinate_values[0]), int(coordinate_values[1]))
		coordinates.append(coordinate)
		plots.append({"plot_index": int(plot.plot_index), "coordinate": coordinate})
	var next_anchor := Vector2i(int(value.anchor[0]), int(value.anchor[1]))
	var relocation_sources: Array[Vector2i] = []
	if not _coordinates_clear(coordinates):
		relocation_sources = coordinates.duplicate()
		next_anchor = _select_anchor(_spawn_grid)
		if next_anchor.x < 0:
			return false
		coordinates = _coordinates_for_anchor(next_anchor)
		plots = _plots_for_coordinates(coordinates)
	_grid.release_cells(_agent_id)
	if not _grid.reserve_cells(_agent_id, coordinates):
		return false
	if not relocation_sources.is_empty():
		_relocate_world_state(relocation_sources, coordinates)
	_anchor = next_anchor
	_plots = plots
	_work_queue.assign((value.work_queue as Array).duplicate(true))
	_finished = (value.finished as Dictionary).duplicate(true)
	if not _work_queue.is_empty():
		work_available.emit()
	return true


func validate_dict(value: Dictionary) -> bool:
	if (
		int(value.get("version", 0)) != 1
		or typeof(value.get("agent_id")) != TYPE_STRING
		or not value.get("anchor", null) is Array
		or (value.anchor as Array).size() != 2
		or not value.get("plots", null) is Array
		or (value.plots as Array).size() != PLOT_COUNT
		or not value.get("work_queue", null) is Array
		or not value.get("finished", null) is Dictionary
	):
		return false
	var seen: Dictionary = {}
	for index in range(PLOT_COUNT):
		var plot_value: Variant = value.plots[index]
		if not plot_value is Dictionary:
			return false
		var plot := plot_value as Dictionary
		if int(plot.get("plot_index", -1)) != index or not plot.get("coordinate", null) is Array:
			return false
		var coordinate_values := plot.coordinate as Array
		if coordinate_values.size() != 2:
			return false
		var coordinate := Vector2i(int(coordinate_values[0]), int(coordinate_values[1]))
		if _grid == null or _grid.get_cell(coordinate.x, coordinate.y) == null or seen.has(coordinate):
			return false
		seen[coordinate] = true
	for record_value in value.work_queue:
		if (
			not record_value is Dictionary
			or str((record_value as Dictionary).get("agent_id", "")) != str(value.agent_id)
			or str((record_value as Dictionary).get("idempotency_key", "")).is_empty()
			or str((record_value as Dictionary).get("tool_name", "")) not in ["till", "plant", "harvest"]
		):
			return false
	return true


func from_dict(value: Dictionary) -> bool:
	return restore_queue(value)


func clear_pending_work() -> void:
	_work_queue.clear()


func _validate_projected(action: Dictionary, projected: Array[Dictionary], seed_counts: Dictionary) -> Dictionary:
	var tool_name := str(action.get("tool_name", ""))
	if tool_name not in ["till", "plant", "harvest"]:
		return {"ok": false, "error": "unsupported_farm_tool"}
	var arguments: Dictionary = action.get("arguments", {})
	var plot_index := int(arguments.get("plot", -1))
	if plot_index < 0 or plot_index >= projected.size():
		return {"ok": false, "error": "invalid_plot"}
	var plot := projected[plot_index]
	match tool_name:
		"till":
			if str(plot.state) != "untilled":
				return {"ok": false, "error": "invalid_plot"}
			plot.state = "tilled"
		"plant":
			var seed_item_id := str(arguments.get("seed_item_id", ""))
			if str(plot.state) != "tilled":
				return {"ok": false, "error": "plot_not_plantable"}
			if int(seed_counts.get(seed_item_id, 0)) <= 0:
				return {"ok": false, "error": "seed_unavailable"}
			seed_counts[seed_item_id] = int(seed_counts.get(seed_item_id, 0)) - 1
			plot.state = "growing"
			plot.seed_item_id = seed_item_id
		"harvest":
			if str(plot.state) != "mature":
				return {"ok": false, "error": "crop_not_mature"}
			plot.state = "tilled"
	return {"ok": true}


func _commit_action(intent: Dictionary) -> Dictionary:
	var plot_index := int((intent.arguments as Dictionary).get("plot", -1))
	var cell := get_plot_cell(_agent_id, plot_index)
	if cell == null or not _grid.is_reserved_for(cell.gx, cell.gz, _agent_id):
		return {"ok": false, "error": "invalid_plot"}
	match str(intent.tool_name):
		"till":
			if cell.state != GridCell.State.WASTELAND or not _grid.set_cell_state(cell.gx, cell.gz, GridCell.State.FARMLAND):
				return {"ok": false, "error": "invalid_plot"}
			return _commit_success("阿禾开垦了地块 %d。" % plot_index, ["npc_farm:%s:%d" % [_agent_id, plot_index]])
		"plant":
			return _commit_plant(intent, cell, plot_index)
		"harvest":
			return _commit_harvest(cell, plot_index)
	return {"ok": false, "error": "unsupported_farm_tool"}


func _commit_plant(intent: Dictionary, cell: GridCell, plot_index: int) -> Dictionary:
	if _economy == null:
		return {"ok": false, "error": "economy_unavailable"}
	var seed_item_id := str((intent.arguments as Dictionary).get("seed_item_id", ""))
	var state = _economy.call("get_npc_state", _agent_id)
	if state == null or int(state.inventory.get(seed_item_id, 0)) <= 0:
		return {"ok": false, "error": "seed_unavailable"}
	var preview: Dictionary = _farming.preview_plant(cell, seed_item_id)
	if not bool(preview.get("ok", false)):
		return {"ok": false, "error": str(preview.get("reason", "plot_not_plantable"))}
	var before: Dictionary = state.to_dict()
	state.inventory[seed_item_id] = int(state.inventory.get(seed_item_id, 0)) - 1
	if _farming.commit_plant(cell, seed_item_id, preview) == null:
		state.from_dict(before)
		return {"ok": false, "error": "plot_not_plantable"}
	var crop_data: CropData = preview.crop_data
	return _commit_success(
		"阿禾播种了%s。" % (crop_data.name if not crop_data.name.is_empty() else crop_data.crop_id),
		["npc_farm:%s:%d" % [_agent_id, plot_index], "npc_inventory:" + _agent_id],
		{seed_item_id: -1}
	)


func _commit_harvest(cell: GridCell, plot_index: int) -> Dictionary:
	if _economy == null:
		return {"ok": false, "error": "economy_unavailable"}
	var preview: Dictionary = _farming.preview_harvest(cell)
	if preview.is_empty():
		return {"ok": false, "error": "crop_not_mature"}
	var state = _economy.call("get_npc_state", _agent_id)
	if state == null:
		return {"ok": false, "error": "inventory_rejected"}
	var state_before: Dictionary = state.to_dict()
	var token = _farming.prepare_harvest(cell, preview)
	if token == null or not _farming.apply_prepared_harvest(token):
		if token != null:
			_farming.rollback_prepared_harvest(token)
		return {"ok": false, "error": "crop_not_mature"}
	for item_id in (preview.items as Dictionary):
		if not bool(_economy.call("receive_item", _agent_id, str(item_id), int(preview.items[item_id]))):
			state.from_dict(state_before)
			_farming.rollback_prepared_harvest(token)
			return {"ok": false, "error": "inventory_rejected"}
	var publication = _farming.seal_prepared_harvest(token)
	if publication == null or not _farming.can_arm_harvest_publication(publication):
		state.from_dict(state_before)
		if publication != null:
			_farming.cancel_harvest_publication(publication)
		else:
			_farming.rollback_prepared_harvest(token)
		return {"ok": false, "error": "harvest_commit_failed"}
	_farming.arm_harvest_publication(publication)
	_farming.publish_harvest_publication(publication)
	var item_id := str((preview.items as Dictionary).keys()[0])
	var quantity := int(preview.items[item_id])
	return _commit_success(
		"阿禾收获了%s ×%d，已进入库存。" % [item_id, quantity],
		["npc_farm:%s:%d" % [_agent_id, plot_index], "npc_inventory:" + _agent_id],
		{item_id: quantity}
	)


func _commit_success(message: String, changed: Array, delta: Dictionary = {}) -> Dictionary:
	return {"ok": true, "message": message, "changed_entities": changed, "resource_delta": delta}


func _queued_result(record: Dictionary) -> Dictionary:
	return {"ok": true, "status": "in_progress", "record": record.duplicate(true)}


func _find_queued(idempotency_key: String) -> Dictionary:
	for record in _work_queue:
		if str(record.idempotency_key) == idempotency_key:
			return record
	return {}


func _seed_counts(agent_id: String) -> Dictionary:
	if _economy == null:
		return {}
	var state = _economy.call("get_npc_state", agent_id)
	return state.inventory.duplicate(true) if state != null else {}


func _plot_is_queued(plot_index: int) -> bool:
	for record in _work_queue:
		if int((record.arguments as Dictionary).get("plot", -1)) == plot_index:
			return true
	return false


func _select_anchor(spawn_grid: Vector2i) -> Vector2i:
	var candidates: Array[Dictionary] = []
	for gz in range(spawn_grid.y - SEARCH_RADIUS, spawn_grid.y + SEARCH_RADIUS + 1):
		for gx in range(spawn_grid.x - SEARCH_RADIUS, spawn_grid.x + SEARCH_RADIUS + 1):
			var anchor := Vector2i(gx, gz)
			if not _valid_anchor(anchor):
				continue
			var center := Vector2(float(gx) + 2.5, float(gz) + 2.0)
			candidates.append({
				"anchor": anchor,
				"distance": center.distance_squared_to(Vector2(spawn_grid)),
			})
	if candidates.is_empty():
		return Vector2i(-1, -1)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.distance), float(b.distance)):
			return float(a.distance) < float(b.distance)
		var left: Vector2i = a.anchor
		var right: Vector2i = b.anchor
		return left.y < right.y or (left.y == right.y and left.x < right.x)
	)
	return candidates[0].anchor


func _valid_anchor(anchor: Vector2i) -> bool:
	for row in range(FARM_HEIGHT):
		for column in range(FARM_WIDTH):
			var coordinate := anchor + Vector2i(column, row)
			var cell := _grid.get_cell(coordinate.x, coordinate.y)
			if (
				cell == null
				or cell.state != GridCell.State.WASTELAND
				or cell.slope > GridSystem.SLOPE_THRESHOLD
				or not _grid.is_navigation_cell_walkable(coordinate)
				or not _grid.can_actor_use_cell(coordinate.x, coordinate.y, _agent_id)
			):
				return false
	return true


func _apply_anchor(anchor: Vector2i) -> bool:
	var coordinates := _coordinates_for_anchor(anchor)
	var plots := _plots_for_coordinates(coordinates)
	if not _grid.reserve_cells(_agent_id, coordinates):
		return false
	_anchor = anchor
	_plots = plots
	return true


func _coordinates_for_anchor(anchor: Vector2i) -> Array[Vector2i]:
	var coordinates: Array[Vector2i] = []
	for row in range(FARM_HEIGHT):
		for column in range(FARM_WIDTH):
			coordinates.append(anchor + Vector2i(column, row))
	return coordinates


func _plots_for_coordinates(coordinates: Array[Vector2i]) -> Array[Dictionary]:
	var plots: Array[Dictionary] = []
	for index in range(coordinates.size()):
		plots.append({"plot_index": index, "coordinate": coordinates[index]})
	return plots


func _coordinates_clear(coordinates: Array[Vector2i]) -> bool:
	if coordinates.size() != PLOT_COUNT:
		return false
	for coordinate in coordinates:
		if (
			_grid.get_cell(coordinate.x, coordinate.y) == null
			or not _grid.is_navigation_cell_walkable(coordinate)
		):
			return false
	return true


func _relocate_world_state(
	source_coordinates: Array[Vector2i],
	target_coordinates: Array[Vector2i]
) -> void:
	var snapshots: Array[Dictionary] = []
	for coordinate in source_coordinates:
		var source := _grid.get_cell(coordinate.x, coordinate.y)
		snapshots.append({
			"state": source.state,
			"watered": source.watered,
			"crop_instance": source.crop_instance,
		})
	for coordinate in source_coordinates:
		var source := _grid.get_cell(coordinate.x, coordinate.y)
		source.state = GridCell.State.WASTELAND
		source.watered = false
		source.crop_instance = null
	for index in range(target_coordinates.size()):
		var target_coordinate := target_coordinates[index]
		var target := _grid.get_cell(target_coordinate.x, target_coordinate.y)
		var snapshot := snapshots[index]
		target.state = int(snapshot.state) as GridCell.State
		target.watered = bool(snapshot.watered)
		target.crop_instance = snapshot.crop_instance
	_grid.rebuild_farmland_visuals()
	_farming.rebuild_visuals()
	_grid.notify_navigation_state_changed()


func _populate_crop_snapshot(record: Dictionary, cell: GridCell) -> void:
	var instance: CropInstance = cell.crop_instance
	if instance == null or instance.crop_data == null:
		record.state = "blocked"
		return
	var crop: CropData = instance.crop_data
	record.crop = instance.to_dict()
	record.growth_progress = (
		clampf(instance.growth_progress / float(crop.growth_days), 0.0, 1.0)
		if crop.growth_days > 0
		else 0.0
	)
	record.remaining_minutes = ceili(
		float(crop.growth_duration_minutes) * (1.0 - float(record.growth_progress))
	)
	match instance.lifecycle_state:
		CropInstance.LifecycleState.MATURE:
			record.state = "mature"
		CropInstance.LifecycleState.DORMANT:
			record.state = "dormant"
		CropInstance.LifecycleState.WITHERED:
			record.state = "withered"
		_:
			record.state = "growing"
