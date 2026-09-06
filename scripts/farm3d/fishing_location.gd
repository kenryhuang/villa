extends RefCounted

const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const MAX_CAST_DISTANCE := 12.0

static func find_location(player: Node3D, grid: GridSystem) -> Dictionary:
	if not valid_footing(player, grid):
		return {}
	var origin := Vector2(player.global_position.x, player.global_position.z)
	var directions: Array[Vector2] = [
		(Profile.LAKE_CENTER-origin).normalized(),
		Vector2(signf(Profile.river_x(origin.y)-origin.x),0),
	]
	for index in 24:
		directions.append(Vector2.RIGHT.rotated(index*TAU/24.0))
	for distance in [5.0,7.0,9.0,11.0,12.0]:
		for direction in directions:
			var point: Vector2 = origin + direction*distance
			var water := Vector3(point.x, Profile.WATER_HEIGHT+.035, point.y)
			if valid_water(player, grid, water):
				return {"stand": player.global_position, "water": water,
					"body": "lake" if Profile.is_lake(point.x,point.y) else "river"}
	return {}

static func valid_footing(player: Node3D, grid: GridSystem) -> bool:
	var p := player.global_position
	if not Profile.is_in_world(p.x,p.z) or Profile.is_water(p.x,p.z) or Profile.is_bridge(p.x,p.z):
		return false
	var height := Profile.surface_height(p.x,p.z)
	if absf(p.y-height) > .25 or height < Profile.WATER_HEIGHT+.15 or height > Profile.WATER_HEIGHT+3.4 or Profile.slope_at(p.x,p.z) > .65:
		return false
	if player is CharacterBody3D and not player.is_on_floor():
		return false
	var coords := grid.world_to_grid(p.x,p.z)
	var cell := grid.get_cell(coords.x,coords.y)
	return cell != null and cell.state not in [GridCell.State.BUILDING,GridCell.State.WATER]

static func valid_water(player: Node3D, grid: GridSystem, water: Vector3) -> bool:
	if not Profile.is_in_world(water.x,water.z) or Profile.is_bridge(water.x,water.z):
		return false
	if Profile.surface_height(water.x,water.z) > Profile.WATER_HEIGHT-.55:
		return false
	var coords := grid.world_to_grid(water.x,water.z)
	var cell := grid.get_cell(coords.x,coords.y)
	if cell == null or cell.state != GridCell.State.WATER:
		return false
	var distance := Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(water.x,water.z))
	if distance > MAX_CAST_DISTANCE or distance < 2.5:
		return false
	var ray := PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*1.3,water,1|4|32)
	return player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
