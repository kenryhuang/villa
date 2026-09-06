extends RefCounted

const DEFAULT := Vector2(-12, 12)
const HALF_SIZE := Vector2(4, 3)

static func contains(site: Vector2, point: Vector2) -> bool:
	return absf(point.x - site.x) < HALF_SIZE.x and absf(point.y - site.y) < HALF_SIZE.y

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
