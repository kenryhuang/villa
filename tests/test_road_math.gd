extends RefCounted

const RoadMath = preload("res://scripts/world/road_math.gd")

func run(assertions) -> void:
	var route: Array[Dictionary] = [
		{"x": 0.0, "z": 0.0, "width": 2.0},
		{"x": 4.0, "z": 0.0, "width": 2.0},
	]
	var samples := RoadMath.sample_route(route, 4)
	assertions.equal(samples.size(), 5, "road contains both endpoints")
	assertions.near(samples[0].x, 0.0, 0.001, "road starts at first point")
	assertions.near(samples[-1].x, 4.0, 0.001, "road ends at last point")
	assertions.near(RoadMath.distance_to_route(Vector2(2.0, 2.0), 0.5, route), 0.5, 0.001, "road clearance includes half width and object radius")
