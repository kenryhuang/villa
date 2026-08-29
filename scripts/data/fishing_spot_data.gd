class_name FishingSpotData
extends Resource

@export var spot_id := ""
@export var water_body_id := ""
@export var fish_table_id := ""
@export var stand_cell := Vector2i(-1, -1)
@export var water_cell := Vector2i(-1, -1)
@export_range(0.1, 10.0, 0.1) var max_distance := 2.25
@export_range(1, 20, 1) var daily_capacity := 3


func is_valid() -> bool:
	return (
		not spot_id.strip_edges().is_empty()
		and not water_body_id.strip_edges().is_empty()
		and not fish_table_id.strip_edges().is_empty()
		and stand_cell.x >= 0
		and stand_cell.y >= 0
		and water_cell.x >= 0
		and water_cell.y >= 0
		and stand_cell != water_cell
		and is_finite(max_distance)
		and max_distance > 0.0
		and daily_capacity > 0
	)


func duplicate_data() -> Resource:
	var copy := get_script().new() as Resource
	copy.spot_id = spot_id
	copy.water_body_id = water_body_id
	copy.fish_table_id = fish_table_id
	copy.stand_cell = stand_cell
	copy.water_cell = water_cell
	copy.max_distance = max_distance
	copy.daily_capacity = daily_capacity
	return copy
