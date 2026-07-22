class_name GridCell
extends RefCounted

enum State { WASTELAND, FARMLAND, PLANTED, BUILDING, ROAD, WATER, DECORATION }

var gx := 0
var gz := 0
var state: State = State.WASTELAND
var watered := false
var crop_instance
var terrain_height := 0.0
var slope := 0.0


func world_position() -> Vector2:
	return Vector2(float(gx) - 17.5, float(gz) - 13.5)


func world_position_3d() -> Vector3:
	var point := world_position()
	return Vector3(point.x, terrain_height, point.y)
