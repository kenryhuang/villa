class_name GeographicQueryService
extends RefCounted

const BLOCKING_CAST_STATES := [GridCell.State.BUILDING, GridCell.State.DECORATION]

var _grid: GridSystem


func configure(grid: GridSystem) -> bool:
	_grid = grid
	return _grid != null


func get_grid() -> GridSystem:
	return _grid


func footprint_borders_natural_water(origin: Vector2i, size: Vector2i) -> bool:
	return not _bordering_water_cells(origin, size).is_empty()


func water_anchor(origin: Vector2i, size: Vector2i) -> Vector2i:
	var cells := _bordering_water_cells(origin, size)
	if cells.is_empty():
		return Vector2i(-1, -1)
	var center := Vector2(
		float(origin.x) + float(size.x - 1) * 0.5,
		float(origin.y) + float(size.y - 1) * 0.5
	)
	cells.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var left_distance := Vector2(left).distance_squared_to(center)
		var right_distance := Vector2(right).distance_squared_to(center)
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		if left.y != right.y:
			return left.y < right.y
		return left.x < right.x
	)
	return cells[0]


func footprint_borders_saved_water(
	origin: Vector2i,
	size: Vector2i,
	grid_data: Dictionary
) -> bool:
	if _grid == null or size.x <= 0 or size.y <= 0:
		return false
	for gx in range(origin.x, origin.x + size.x):
		for gz in [origin.y - 1, origin.y + size.y]:
			if _grid.saved_cell_state(grid_data, gx, gz) == GridCell.State.WATER:
				return true
	for gz in range(origin.y, origin.y + size.y):
		for gx in [origin.x - 1, origin.x + size.x]:
			if _grid.saved_cell_state(grid_data, gx, gz) == GridCell.State.WATER:
				return true
	return false


func mature_flowers_near(
	center: Vector2,
	radius: float,
	cap: int = 0
) -> Array[GridCell]:
	var result: Array[GridCell] = []
	if _grid == null or not is_finite(radius) or radius < 0.0 or cap < 0:
		return result
	for value in _grid._cells.values():
		var cell := value as GridCell
		if (
			cell == null
			or cell.state != GridCell.State.PLANTED
			or cell.crop_instance == null
		):
			continue
		if Vector2(cell.gx, cell.gz).distance_to(center) > radius + 0.0001:
			continue
		if (
			cell.crop_instance.is_mature()
			and _crop_is_flower(cell.crop_instance.crop_data)
		):
			result.append(cell)
	result.sort_custom(func(left: GridCell, right: GridCell) -> bool:
		var left_distance := Vector2(left.gx, left.gz).distance_squared_to(center)
		var right_distance := Vector2(right.gx, right.gz).distance_squared_to(center)
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		if left.gz != right.gz:
			return left.gz < right.gz
		return left.gx < right.gx
	)
	if cap > 0 and result.size() > cap:
		result.resize(cap)
	return result


func is_clear_cast_line(from_cell: Vector2i, target_cell: Vector2i) -> bool:
	if _grid == null or _grid.get_cell(from_cell.x, from_cell.y) == null:
		return false
	if _grid.get_cell(target_cell.x, target_cell.y) == null:
		return false
	var points := _grid_line(from_cell, target_cell)
	for index in range(1, maxi(1, points.size() - 1)):
		var point: Vector2i = points[index]
		var cell := _grid.get_cell(point.x, point.y)
		if cell == null or cell.state in BLOCKING_CAST_STATES:
			return false
	return true


func _bordering_water_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if _grid == null or size.x <= 0 or size.y <= 0:
		return result
	var seen := {}
	for gx in range(origin.x, origin.x + size.x):
		_append_water_cell(result, seen, Vector2i(gx, origin.y - 1))
		_append_water_cell(result, seen, Vector2i(gx, origin.y + size.y))
	for gz in range(origin.y, origin.y + size.y):
		_append_water_cell(result, seen, Vector2i(origin.x - 1, gz))
		_append_water_cell(result, seen, Vector2i(origin.x + size.x, gz))
	return result


func _append_water_cell(
	result: Array[Vector2i],
	seen: Dictionary,
	position: Vector2i
) -> void:
	if seen.has(position):
		return
	seen[position] = true
	var cell := _grid.get_cell(position.x, position.y)
	if cell != null and cell.state == GridCell.State.WATER:
		result.append(position)


func _crop_is_flower(crop_data: Variant) -> bool:
	if crop_data == null:
		return false
	if str(crop_data.category) == "flower":
		return true
	for tag_value in crop_data.tags:
		if str(tag_value) == "flower":
			return true
	return false


func _grid_line(start: Vector2i, finish: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x0 := start.x
	var y0 := start.y
	var x1 := finish.x
	var y1 := finish.y
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var error := dx + dy
	while true:
		result.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var twice_error := error * 2
		if twice_error >= dy:
			error += dy
			x0 += sx
		if twice_error <= dx:
			error += dx
			y0 += sy
	return result
