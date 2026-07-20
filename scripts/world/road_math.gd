class_name RoadMath
extends RefCounted

static func sample_route(route: Array[Dictionary], steps_per_segment: int) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	if route.size() < 2 or steps_per_segment < 1:
		return samples
	for segment in range(route.size() - 1):
		var b: Dictionary = route[segment]
		var c: Dictionary = route[segment + 1]
		var a: Dictionary = route[segment - 1] if segment > 0 else _extrapolate(b, c)
		var d: Dictionary = route[segment + 2] if segment + 2 < route.size() else _extrapolate(c, b)
		for step in steps_per_segment:
			var t := float(step) / float(steps_per_segment)
			samples.append({
				"x": _catmull(a.x, b.x, c.x, d.x, t),
				"z": _catmull(a.z, b.z, c.z, d.z, t),
				"width": _catmull(a.width, b.width, c.width, d.width, t),
			})
	samples.append(route[-1].duplicate())
	return samples

static func distance_to_route(point: Vector2, clearance: float, route: Array[Dictionary]) -> float:
	if route.size() < 2:
		return INF
	var closest := INF
	for index in range(route.size() - 1):
		var a := Vector2(float(route[index].x), float(route[index].z))
		var b := Vector2(float(route[index + 1].x), float(route[index + 1].z))
		var segment := b - a
		var length_squared := maxf(segment.length_squared(), 0.000001)
		var t := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
		var road_width := lerpf(float(route[index].width), float(route[index + 1].width), t)
		var edge_distance := point.distance_to(a + segment * t) - road_width * 0.5 - clearance
		closest = minf(closest, edge_distance)
	return closest

static func _extrapolate(origin: Dictionary, toward: Dictionary) -> Dictionary:
	return {
		"x": float(origin.x) * 2.0 - float(toward.x),
		"z": float(origin.z) * 2.0 - float(toward.z),
		"width": float(origin.width) * 2.0 - float(toward.width),
	}

static func _catmull(a: float, b: float, c: float, d: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (2.0 * b + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3)
