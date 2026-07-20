class_name GameWorld
extends Node3D

@onready var terrain: TerrainBuilder = $Terrain
@onready var road: RoadBuilder = $Road
@onready var vegetation: VegetationBuilder = $Vegetation

func _ready() -> void:
	if not terrain.build():
		push_error("World initialization stopped because terrain failed")
		return
	road.build(terrain)
	var route: Array[Dictionary] = []
	for point in RoadBuilder.MAIN_ROUTE:
		route.append(point.duplicate())
	vegetation.build(terrain, route)

func get_height_at(world_x: float, world_z: float) -> float:
	return terrain.get_height_at(world_x, world_z)

func get_bounds() -> Rect2:
	return Rect2(-17.2, -13.2, 34.4, 26.4)
