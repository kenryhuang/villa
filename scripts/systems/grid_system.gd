class_name GridSystem
extends Node3D

const GRID_WIDTH := 36
const GRID_DEPTH := 28
const CELL_SIZE := 1.0
const WORLD_ORIGIN_X := -18.0
const WORLD_ORIGIN_Z := -14.0
const SLOPE_THRESHOLD := 0.35

var terrain: TerrainBuilder
var _cells := {}
var _event_bus


static func cell_key(gx: int, gz: int) -> int:
	return gx * 1000 + gz


func configure(terrain_node: TerrainBuilder) -> void:
	terrain = terrain_node
	_event_bus = get_node_or_null("/root/EventBus")


func world_to_grid(wx: float, wz: float) -> Vector2i:
	return Vector2i(floori(wx + 18.0), floori(wz + 14.0))


func grid_to_world(gx: int, gz: int) -> Vector2:
	return Vector2(float(gx) - 17.5, float(gz) - 13.5)


func _is_in_bounds(gx: int, gz: int) -> bool:
	return gx >= 0 and gx < GRID_WIDTH and gz >= 0 and gz < GRID_DEPTH


func _ensure_cell(gx: int, gz: int) -> GridCell:
	var key := cell_key(gx, gz)
	if _cells.has(key):
		return _cells[key]
	var cell := GridCell.new()
	cell.gx = gx
	cell.gz = gz
	if terrain:
		var point := grid_to_world(gx, gz)
		cell.terrain_height = terrain.get_height_at(point.x, point.y)
		cell.slope = _calc_slope(gx, gz)
	_cells[key] = cell
	return cell


func _calc_slope(gx: int, gz: int) -> float:
	if terrain == null:
		return 0.0
	var point := grid_to_world(gx, gz)
	var center := terrain.get_height_at(point.x, point.y)
	var sx := absf(terrain.get_height_at(point.x + 0.5, point.y) - center) / 0.5
	var sz := absf(terrain.get_height_at(point.x, point.y + 0.5) - center) / 0.5
	return sqrt(sx * sx + sz * sz)


func get_cell(gx: int, gz: int) -> GridCell:
	if not _is_in_bounds(gx, gz):
		return null
	return _ensure_cell(gx, gz)


func get_cell_at_world(wx: float, wz: float) -> GridCell:
	var grid_pos := world_to_grid(wx, wz)
	return get_cell(grid_pos.x, grid_pos.y)


func get_cells_in_rect(gx: int, gz: int, w: int, h: int) -> Array:
	var result := []
	for z in range(gz, gz + h):
		for x in range(gx, gx + w):
			if _is_in_bounds(x, z):
				result.append(_ensure_cell(x, z))
	return result


func get_terrain_height_at_cell(gx: int, gz: int) -> float:
	if not _is_in_bounds(gx, gz):
		return NAN
	var cell := _ensure_cell(gx, gz)
	return cell.terrain_height


func get_slope_at_cell(gx: int, gz: int) -> float:
	if not _is_in_bounds(gx, gz):
		return NAN
	var cell := _ensure_cell(gx, gz)
	return cell.slope


func can_farm_at(gx: int, gz: int) -> bool:
	if not _is_in_bounds(gx, gz):
		return false
	var cell := _ensure_cell(gx, gz)
	if cell.slope > SLOPE_THRESHOLD:
		return false
	if cell.state in [5, 3, 4, 6]:  # WATER, BUILDING, ROAD, DECORATION
		return false
	return true


func is_cell_available(gx: int, gz: int, required_state: int) -> bool:
	var cell := get_cell(gx, gz)
	if cell == null:
		return false
	return cell.state == required_state


func set_cell_state(gx: int, gz: int, next_state: int) -> bool:
	var cell := get_cell(gx, gz)
	if cell == null:
		return false
	if not _transition_allowed(cell.state, next_state):
		return false
	cell.state = next_state
	if _event_bus:
		_event_bus.cell_state_changed.emit(gx, gz, next_state)
	return true


func _transition_allowed(current: int, next: int) -> bool:
	if current == next:
		return true
	if current == 0:  # WASTELAND
		return next == 1 or next == 3  # FARMLAND or BUILDING
	if current == 1:  # FARMLAND
		return next == 2 or next == 3  # PLANTED or BUILDING
	if current == 2:  # PLANTED
		return next == 1  # FARMLAND
	if current == 3:  # BUILDING
		return next == 0 or next == 1  # WASTELAND or FARMLAND
	return false


func plant_crop(gx: int, gz: int, crop_data) -> CropInstance:
	if crop_data == null or not is_cell_available(gx, gz, 1):  # FARMLAND
		return null
	var cell := get_cell(gx, gz)
	var instance := CropInstance.new()
	instance.crop_data = crop_data
	cell.crop_instance = instance
	cell.state = 2  # PLANTED
	if _event_bus:
		_event_bus.cell_state_changed.emit(gx, gz, 2)  # PLANTED
		_event_bus.crop_planted.emit(gx, gz, crop_data.crop_id)
	return instance


func harvest_crop(gx: int, gz: int) -> Dictionary:
	var cell := get_cell(gx, gz)
	if cell == null or cell.state != GridCell.State.PLANTED:
		return {}
	if cell.crop_instance == null:
		return {}
	if not cell.crop_instance.advance_growth() or cell.crop_instance.growth_progress < cell.crop_instance.crop_data.growth_days:
		return {}
	var crop_id: String = cell.crop_instance.crop_data.crop_id
	var exp_reward: int = cell.crop_instance.crop_data.exp_reward
	if _event_bus:
		_event_bus.crop_harvested.emit(gx, gz, crop_id)
	cell.crop_instance = null
	cell.watered = false
	cell.state = GridCell.State.FARMLAND
	if _event_bus:
		_event_bus.cell_state_changed.emit(gx, gz, GridCell.State.FARMLAND)
	return {"items": [crop_id], "exp": exp_reward}


func water_cell(gx: int, gz: int) -> bool:
	var cell := get_cell(gx, gz)
	if cell == null:
		return false
	if cell.state != GridCell.State.FARMLAND and cell.state != GridCell.State.PLANTED:
		return false
	cell.watered = true
	if cell.crop_instance:
		cell.crop_instance.is_watered_today = true
	if _event_bus:
		_event_bus.cell_watered.emit(gx, gz)
	return true
