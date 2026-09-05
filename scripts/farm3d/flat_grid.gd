class_name Farm3DFlatGrid
extends GridSystem

const ROAD_HALF_WIDTH := 1.55 # path width plus the half-cell safety padding used by GridSystem

var visual_system: Node


func configure_flat(next_visual_system: Node = null) -> bool:
	visual_system = next_visual_system
	terrain = null
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	_cells.clear()
	_base_states.clear()
	for gz in GRID_DEPTH:
		for gx in GRID_WIDTH:
			var cell := GridCell.new()
			cell.gx = gx
			cell.gz = gz
			cell.terrain_height = 0.0
			cell.slope = 0.0
			cell.state = _base_state(cell)
			var key := cell_key(gx, gz)
			_cells[key] = cell
			_base_states[key] = cell.state
	return true


func _base_state(cell: GridCell) -> GridCell.State:
	var point := cell.world_position()
	var road_x := -2.8 + sin(point.y * 0.14) * 1.3
	if absf(point.x - road_x) <= ROAD_HALF_WIDTH:
		return GridCell.State.ROAD
	for obstacle in [
		Vector2(-8, -5), Vector2(-10, 2), Vector2(12, -9),
		Vector2(10, 5), Vector2(-5, -12), Vector2(5, -14),
	]:
		if point.distance_to(obstacle) < 1.15:
			return GridCell.State.DECORATION
	for boulder in [
		{"point": Vector2(-6, 6), "radius": 0.7},
		{"point": Vector2(11, 1), "radius": 0.5},
		{"point": Vector2(-11, -8), "radius": 0.9},
	]:
		if point.distance_to(boulder.point) < float(boulder.radius) + 0.71:
			return GridCell.State.DECORATION
	# The authored north fence spans x=.7..9.9 at z=-9.66.  Block cells whose
	# half extents overlap it; do not make unrelated world boundaries unusable.
	if point.x >= 0.2 and point.x <= 10.4 and absf(point.y + 9.66) <= 0.5:
		return GridCell.State.DECORATION
	return GridCell.State.WASTELAND


func _sync_farmland_visual(cell: GridCell) -> void:
	if visual_system != null and visual_system.has_method("sync_cell"):
		visual_system.call("sync_cell", cell)


func rebuild_farmland_visuals() -> void:
	if visual_system != null and visual_system.has_method("rebuild"):
		visual_system.call("rebuild", _cells.values())
