extends BuildingSystem

const PLACEMENT_RANGE := 2.6

var farmer: Node3D
var actor_lookup: Callable

func _resolve_data(building: Variant) -> BuildingData:
	var resolved := super._resolve_data(building)
	if resolved != null and resolved.building_id in ["barn", "windmill", "food_workshop", "beehive", "chicken_coop"]:
		# Copy so the shared catalogue and original game keep their own visuals.
		resolved = resolved.duplicate() as BuildingData
		resolved.scene_path = "res://scenes/farm3d/buildings/%s.tscn" % resolved.building_id
		resolved.visual_size = Vector2(2.4,3.2) if resolved.building_id == "barn" else Vector2(3.1,4.2)
		if resolved.building_id == "food_workshop":
			resolved.visual_size = Vector2(3.8,3.6)
		if resolved.building_id == "beehive":
			resolved.visual_size = Vector2(1.55, 1.85)
		if resolved.building_id == "chicken_coop":
			resolved.visual_size = Vector2(2.95, 2.4)
	return resolved

func diagnose_placement(building: Variant, gx: int, gz: int, actor_id := "player", check_distance := true) -> Dictionary:
	var result := super.diagnose_placement(building, gx, gz, actor_id, check_distance)
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
	if not check_distance: return result
	var actor: Node3D = farmer if actor_id == "player" else (actor_lookup.call(actor_id) if actor_lookup.is_valid() else null)
	if actor == null:
		result.allowed = actor_id == "player"
		result.code = "actor_unavailable"
		return result
	var cell := grid_system_ref.get_cell(gx, gz)
	var point := Vector2(actor.global_position.x, actor.global_position.z)
	var footprint := Rect2(cell.world_position() - Vector2.ONE * GridSystem.CELL_SIZE * .5, Vector2(data.footprint) * GridSystem.CELL_SIZE)
	# Reach the nearest edge of the whole building, regardless of which side
	# the actor approaches. Keep height in the check to prevent cliff placement.
	var nearest := Vector3(
		clampf(point.x, footprint.position.x, footprint.end.x),
		clampf(actor.global_position.y, low, high),
		clampf(point.y, footprint.position.y, footprint.end.y)
	)
	if actor.global_position.distance_to(nearest) > PLACEMENT_RANGE:
		result.allowed = false
		result.code = "out_of_range"
		result.message = "离建筑边缘太远，请靠近到 %.1f 米内再放置" % PLACEMENT_RANGE
		return result
	if footprint.grow(0.32).has_point(point):
		result.allowed = false
		result.code = "player_in_footprint"
		result.message = "请站到建筑占地之外再放置"
	return result
