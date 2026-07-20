class_name RoadBuilder
extends Node3D

const RoadMathScript = preload("res://scripts/world/road_math.gd")

const MAIN_ROUTE := [
	{"x": -17.2, "z": -10.5, "width": 2.3},
	{"x": -12.0, "z": -8.1, "width": 2.45},
	{"x": -8.0, "z": -6.4, "width": 2.35},
	{"x": -3.0, "z": -5.2, "width": 2.55},
	{"x": 0.0, "z": -1.2, "width": 2.7},
	{"x": 4.0, "z": -0.4, "width": 2.5},
	{"x": 8.0, "z": 0.0, "width": 2.25},
	{"x": 12.0, "z": 4.5, "width": 2.4},
	{"x": 17.2, "z": 8.8, "width": 2.3},
]

func build(terrain: TerrainBuilder) -> bool:
	if MAIN_ROUTE.size() < 2:
		push_error("Road requires at least two control points")
		return false
	var route: Array[Dictionary] = []
	for point in MAIN_ROUTE:
		route.append(point.duplicate())
	var samples := RoadMathScript.sample_route(route, 12)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cross_segments := 6
	var row_size := cross_segments + 1
	var traveled := 0.0
	var previous := Vector2(float(samples[0].x), float(samples[0].z))
	for index in samples.size():
		var current: Dictionary = samples[index]
		var previous_sample: Dictionary = samples[maxi(0, index - 1)]
		var next_sample: Dictionary = samples[mini(samples.size() - 1, index + 1)]
		var tangent := Vector2(float(next_sample.x - previous_sample.x), float(next_sample.z - previous_sample.z)).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var center := Vector2(float(current.x), float(current.z))
		traveled += center.distance_to(previous)
		previous = center
		for cross in range(cross_segments + 1):
			var u := float(cross) / float(cross_segments)
			var lateral := (u - 0.5) * float(current.width)
			var position_2d := center - normal * lateral
			var crown := 0.012 + pow(sin(PI * u), 0.55) * 0.045
			surface.set_uv(Vector2(u, traveled / 5.0))
			surface.add_vertex(Vector3(position_2d.x, terrain.get_height_at(position_2d.x, position_2d.y) + crown, position_2d.y))
	for row in range(samples.size() - 1):
		for cross in cross_segments:
			var a := row * row_size + cross
			var b := a + 1
			var c := a + row_size
			var d := c + 1
			surface.add_index(a); surface.add_index(c); surface.add_index(b)
			surface.add_index(b); surface.add_index(c); surface.add_index(d)
	surface.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "RoadMesh"
	mesh_instance.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/terrain/road-ribbon-seamless.png") as Texture2D
	material.albedo_color = Color(0.78, 0.74, 0.66) if material.albedo_texture else Color(0.45, 0.25, 0.1)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	add_child(mesh_instance)
	return true
