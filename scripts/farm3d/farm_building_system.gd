extends BuildingSystem

var farmer: Node3D

func diagnose_placement(building: Variant, gx: int, gz: int) -> Dictionary:
	var result := super.diagnose_placement(building, gx, gz)
	if not result.allowed or farmer == null:
		return result
	var cell := grid_system_ref.get_cell(gx, gz)
	var point := Vector2(farmer.global_position.x, farmer.global_position.z)
	if point.distance_to(cell.world_position()) > 2.6:
		result.allowed = false
		result.code = "out_of_range"
		result.message = "离建筑位置太远，请走近后再放置"
		return result
	var data := _resolve_data(building)
	var footprint := Rect2(cell.world_position() - Vector2(0.5, 0.5), Vector2(data.footprint)).grow(0.32)
	if footprint.has_point(point):
		result.allowed = false
		result.code = "player_in_footprint"
		result.message = "请站到建筑占地之外再放置"
	return result
