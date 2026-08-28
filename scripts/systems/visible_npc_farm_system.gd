class_name VisibleNpcFarmSystem
extends Node

const FARM_WIDTH := 5
const FARM_HEIGHT := 4
const PLOT_COUNT := FARM_WIDTH * FARM_HEIGHT
const SEARCH_RADIUS := 12

var _grid: GridSystem
var _farming: FarmingSystem
var _economy: Variant
var _game_data: Variant
var _agent_id := ""
var _anchor := Vector2i(-1, -1)
var _plots: Array[Dictionary] = []


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
	_agent_id = agent_id
	var spawn_grid := _grid.world_to_grid(spawn_position.x, spawn_position.z)
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
		record.queued = false
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
				or not _grid.can_actor_use_cell(coordinate.x, coordinate.y, _agent_id)
			):
				return false
	return true


func _apply_anchor(anchor: Vector2i) -> bool:
	var coordinates: Array[Vector2i] = []
	var plots: Array[Dictionary] = []
	for row in range(FARM_HEIGHT):
		for column in range(FARM_WIDTH):
			var coordinate := anchor + Vector2i(column, row)
			coordinates.append(coordinate)
			plots.append({
				"plot_index": row * FARM_WIDTH + column,
				"coordinate": coordinate,
			})
	if not _grid.reserve_cells(_agent_id, coordinates):
		return false
	_anchor = anchor
	_plots = plots
	return true


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
