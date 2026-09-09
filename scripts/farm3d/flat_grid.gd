class_name Farm3DFlatGrid
extends GridSystem

const ROAD_HALF_WIDTH := 1.55 # path width plus the half-cell safety padding used by GridSystem
const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const StaticCache = preload("res://scripts/farm3d/terrain_cache.gd")
const MIN_GX := int(Profile.WORLD_MIN.x - WORLD_ORIGIN_X)
const MAX_GX := int(Profile.WORLD_MAX.x - WORLD_ORIGIN_X)
const MIN_GZ := int(Profile.WORLD_MIN.y - WORLD_ORIGIN_Z)
const MAX_GZ := int(Profile.WORLD_MAX.y - WORLD_ORIGIN_Z)

var visual_system: Node


func get_navigation_bounds() -> Rect2i:
	return Rect2i(MIN_GX, MIN_GZ, MAX_GX - MIN_GX, MAX_GZ - MIN_GZ)


func configure_flat(next_visual_system: Node = null) -> bool:
	visual_system = next_visual_system
	terrain = null
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	_cells.clear()
	_base_states.clear()
	var cached := StaticCache.read("grid")
	var count := (MAX_GX - MIN_GX) * (MAX_GZ - MIN_GZ)
	var cache_valid := _valid_static_cache(cached, count)
	var heights := PackedFloat64Array()
	var slopes := PackedFloat64Array()
	var states := PackedByteArray()
	if cache_valid:
		heights = cached.heights; slopes = cached.slopes; states = cached.states
	else:
		heights.resize(count); slopes.resize(count); states.resize(count)
	var index := 0
	for gz in range(MIN_GZ,MAX_GZ):
		for gx in range(MIN_GX,MAX_GX):
			var cell := GridCell.new()
			cell.gx = gx
			cell.gz = gz
			var point := cell.world_position()
			if cache_valid:
				cell.terrain_height = heights[index]
				cell.slope = slopes[index]
				cell.state = states[index] as GridCell.State
			else:
				cell.terrain_height = Profile.surface_height(point.x,point.y)
				cell.slope = Profile.slope_at(point.x,point.y)
				cell.state = _base_state(cell)
				heights[index] = cell.terrain_height
				slopes[index] = cell.slope
				states[index] = cell.state
			var key := cell_key(gx, gz)
			_cells[key] = cell
			_base_states[key] = cell.state
			index += 1
	if not cache_valid: StaticCache.write("grid", {"heights": heights, "slopes": slopes, "states": states})
	return true


func _valid_static_cache(value: Dictionary, count: int) -> bool:
	if not value.get("heights") is PackedFloat64Array or not value.get("slopes") is PackedFloat64Array or not value.get("states") is PackedByteArray: return false
	if value.heights.size() != count or value.slopes.size() != count or value.states.size() != count: return false
	for index in count:
		if not is_finite(value.heights[index]) or not is_finite(value.slopes[index]) or value.slopes[index] < 0: return false
		if value.states[index] not in [GridCell.State.WASTELAND, GridCell.State.ROAD, GridCell.State.DECORATION, GridCell.State.WATER]: return false
	return true


func _base_state(cell: GridCell) -> GridCell.State:
	var point := cell.world_position()
	if Profile.Golf.BOUNDS.grow(2).has_point(point):
		return GridCell.State.DECORATION
	if not Profile.is_original_core(point.x,point.y):
		if Profile.is_bridge(point.x,point.y):
			return GridCell.State.DECORATION
		if Profile.is_water(point.x,point.y):
			return GridCell.State.WATER
		if Profile.is_fishing_shore(point.x,point.y):
			return GridCell.State.DECORATION
		if cell.slope > .18:
			return GridCell.State.DECORATION
		for tree in Profile.TREES:
			if point.distance_to(tree) < 1.15:
				return GridCell.State.DECORATION
		return GridCell.State.WASTELAND
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

func _is_in_bounds(gx: int, gz: int) -> bool:
	return gx >= MIN_GX and gx < MAX_GX and gz >= MIN_GZ and gz < MAX_GZ

func is_navigation_cell_walkable(cell: Vector2i) -> bool:
	if cell.x <= MIN_GX or cell.x >= MAX_GX-1 or cell.y <= MIN_GZ or cell.y >= MAX_GZ-1:
		return false
	var data := get_cell(cell.x,cell.y)
	if data == null or is_navigation_cell_blocked(cell): return false
	if _state_is_navigation_walkable(data.state): return true
	# Decoration also marks land that cannot be farmed/built on. Gentle hills,
	# bridges and golf turf are still physically walkable; trunks/water are not.
	if data.state != GridCell.State.DECORATION: return false
	var point := data.world_position()
	if Profile.is_original_core(point.x, point.y): return false
	if Profile.is_bridge(point.x, point.y): return true
	if Profile.is_water(point.x, point.y) or data.slope > 1.0: return false
	for tree in Profile.TREES:
		if point.distance_to(tree) < 1.15: return false
	if Profile.Golf.contains(point):
		if Profile.Golf.surface(point) == "water": return false
		for tree in Profile.Golf.TREES:
			if point.distance_to(Vector2(tree.x, tree.y)) < .6 * tree.z + .5: return false
	return true


func _sync_farmland_visual(cell: GridCell) -> void:
	if visual_system != null and visual_system.has_method("sync_cell"):
		visual_system.call("sync_cell", cell)


func rebuild_farmland_visuals() -> void:
	if visual_system != null and visual_system.has_method("rebuild"):
		visual_system.call("rebuild", _cells.values())
