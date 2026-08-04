class_name GridPathfinder
extends RefCounted

var _grid: GridSystem
var _astar := AStarGrid2D.new()
var _built_revision := -1
var _rebuild_count := 0


func configure(grid: GridSystem) -> bool:
	if grid == null:
		return false
	_grid = grid
	_built_revision = -1
	_rebuild_count = 0
	return true


func invalidate() -> void:
	_built_revision = -1


func get_rebuild_count() -> int:
	return _rebuild_count


func get_navigation_revision() -> int:
	return _grid.get_navigation_revision() if _grid != null else -1


func is_path_walkable(points: Array[Vector3]) -> bool:
	if _grid == null or points.is_empty():
		return false
	for point in points:
		if not _grid.is_navigation_cell_walkable(
			_grid.world_to_grid(point.x, point.z)
		):
			return false
	return true


func find_path_cells(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if _grid == null:
		return empty
	_ensure_built()
	if (
		not _grid.is_navigation_cell_walkable(start)
		or not _grid.is_navigation_cell_walkable(goal)
	):
		return empty
	return _astar.get_id_path(start, goal)


func find_path_to_interaction(
	start_world: Vector3,
	target: Node3D,
	interaction_range: float
) -> Array[Vector3]:
	var empty: Array[Vector3] = []
	if _grid == null or target == null or interaction_range <= 0.0:
		return empty
	_ensure_built()
	var start := _grid.world_to_grid(start_world.x, start_world.z)
	if not _grid.is_navigation_cell_walkable(start):
		return empty
	var target_position := target.global_position if target.is_inside_tree() else target.position
	var target_cell := _grid.world_to_grid(target_position.x, target_position.z)
	var target_radius := _target_radius(target)
	var maximum_distance := interaction_range + target_radius
	var cell_radius := ceili(maximum_distance / GridSystem.CELL_SIZE) + 1
	var best_path: Array[Vector2i] = []
	var best_front_score := -INF
	for gz in range(target_cell.y - cell_radius, target_cell.y + cell_radius + 1):
		for gx in range(target_cell.x - cell_radius, target_cell.x + cell_radius + 1):
			var candidate := Vector2i(gx, gz)
			if candidate == target_cell or not _grid.is_navigation_cell_walkable(candidate):
				continue
			var candidate_world := _grid.grid_to_world(gx, gz)
			var flat_distance := candidate_world.distance_to(
				Vector2(target_position.x, target_position.z)
			)
			if flat_distance > maximum_distance:
				continue
			var candidate_path: Array[Vector2i] = _astar.get_id_path(start, candidate)
			if candidate_path.is_empty():
				continue
			var front_score := _front_score(target, candidate_world, target_position)
			if (
				best_path.is_empty()
				or candidate_path.size() < best_path.size()
				or (candidate_path.size() == best_path.size() and front_score > best_front_score)
			):
				best_path = candidate_path
				best_front_score = front_score
	if best_path.is_empty():
		return empty
	var result: Array[Vector3] = []
	for cell in best_path:
		var point := _grid.grid_to_world(cell.x, cell.y)
		var height := 0.0
		if _grid.terrain != null:
			height = _grid.terrain.get_height_at(point.x, point.y)
		result.append(Vector3(point.x, height, point.y))
	return result


func _ensure_built() -> void:
	if _grid == null or _built_revision == _grid.get_navigation_revision():
		return
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, GridSystem.GRID_WIDTH, GridSystem.GRID_DEPTH)
	_astar.cell_size = Vector2.ONE * GridSystem.CELL_SIZE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for gz in range(GridSystem.GRID_DEPTH):
		for gx in range(GridSystem.GRID_WIDTH):
			var cell := Vector2i(gx, gz)
			_astar.set_point_solid(cell, not _grid.is_navigation_cell_walkable(cell))
	_built_revision = _grid.get_navigation_revision()
	_rebuild_count += 1


func _target_radius(target: Node3D) -> float:
	if target.has_method("get_interaction_radius"):
		return maxf(0.0, float(target.call("get_interaction_radius")))
	return 0.0


func _front_score(target: Node3D, candidate: Vector2, target_position: Vector3) -> float:
	var target_forward := -target.global_basis.z if target.is_inside_tree() else -target.basis.z
	var flat_forward := Vector2(target_forward.x, target_forward.z).normalized()
	if flat_forward.is_zero_approx():
		return 0.0
	var direction := (candidate - Vector2(target_position.x, target_position.z)).normalized()
	return direction.dot(flat_forward)
