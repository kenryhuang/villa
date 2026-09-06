extends BuildingSystem

var farmer: Node3D

func diagnose_placement(building: Variant, gx: int, gz: int) -> Dictionary:
	var result := super.diagnose_placement(building, gx, gz)
	if not result.allowed:
		return result
	var data := _resolve_data(building)
	var low := INF
	var high := -INF
	for coordinate in _footprint_cells(data,gx,gz):
		var height := grid_system_ref.get_terrain_height_at_cell(coordinate.x,coordinate.y)
		low = minf(low,height)
		high = maxf(high,height)
	if high-low > .20:
		result.allowed = false
		result.code = "uneven_terrain"
		result.message = "地面高差过大，请选择平坦区域建造"
		return result
	if farmer == null:
		return result
	var cell := grid_system_ref.get_cell(gx, gz)
	var point := Vector2(farmer.global_position.x, farmer.global_position.z)
	if farmer.global_position.distance_to(cell.world_position_3d()) > 2.6:
		result.allowed = false
		result.code = "out_of_range"
		result.message = "离建筑位置太远，请走近后再放置"
		return result
	var footprint := Rect2(cell.world_position() - Vector2(0.5, 0.5), Vector2(data.footprint)).grow(0.32)
	if footprint.has_point(point):
		result.allowed = false
		result.code = "player_in_footprint"
		result.message = "请站到建筑占地之外再放置"
	return result
