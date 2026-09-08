extends RefCounted

const DEFAULT := Vector2(-12, 12)
const HALF_SIZE := Vector2(4, 3)

static func contains(site: Vector2, point: Vector2) -> bool:
	return absf(point.x - site.x) < HALF_SIZE.x and absf(point.y - site.y) < HALF_SIZE.y

static func reachable_counter(grid: GridSystem, start: Vector3, site: Vector2) -> Vector3:
	var finder := GridPathfinder.new()
	finder.configure(grid)
	var start_cell := grid.world_to_grid(start.x, start.z)
	var best_length := 2147483647
	var target := Vector3.INF
	# The market faces south. Its reserved footprint is not a walking target.
	for dz in [3.5, 4.5, 5.5]:
		for dx in [-3.5, -2.5, -1.5, -.5, .5, 1.5, 2.5, 3.5]:
			var coordinate := grid.world_to_grid(site.x + dx, site.y + dz)
			var route := finder.find_path_cells(start_cell, coordinate)
			if not route.is_empty() and route.size() < best_length:
				best_length = route.size()
				target = grid.get_cell(coordinate.x, coordinate.y).world_position_3d()
	return target

static func cells(grid: GridSystem, site: Vector2) -> Array[GridCell]:
	var result: Array[GridCell] = []
	for z in range(int(site.y - HALF_SIZE.y), int(site.y + HALF_SIZE.y)):
		for x in range(int(site.x - HALF_SIZE.x), int(site.x + HALF_SIZE.x)):
			var coords := grid.world_to_grid(x + .5, z + .5)
			var cell := grid.get_cell(coords.x, coords.y)
			if cell != null:
				result.append(cell)
	return result

static func find_available(grid: GridSystem) -> Vector2:
	# Older saves may already have crops or buildings at the default site.
	for z in [12, 20, 30, 40, 50, 60, 70]:
		for x in [-12, 12, -24, 24, -40, -56, 56]:
			var candidate := Vector2(x, z)
			var footprint := cells(grid, candidate)
			if footprint.size() == 48 and footprint.all(func(cell: GridCell): return cell.state == GridCell.State.WASTELAND and cell.crop_instance == null and cell.slope < .12):
				return candidate
	return Vector2.INF
