extends RefCounted

const TerrainBuilder = preload("res://scripts/world/terrain_builder.gd")

func run(assertions) -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color(0.0, 0.0, 0.0))
	image.set_pixel(1, 0, Color(1.0, 1.0, 1.0))
	image.set_pixel(0, 1, Color(0.25, 0.25, 0.25))
	image.set_pixel(1, 1, Color(0.75, 0.75, 0.75))
	assertions.near(TerrainBuilder.sample_height(image, -100.0, -100.0), -0.12, 0.001, "height sampling clamps lower corner")
	assertions.near(TerrainBuilder.sample_height(image, 100.0, -100.0), 0.9, 0.001, "height sampling clamps upper x corner")
	var center := TerrainBuilder.sample_height(image, 0.0, 0.0)
	assertions.truthy(center >= -0.12 and center <= 0.9, "sampled height stays in configured range")
	assertions.near(center, TerrainBuilder.sample_height(image, 0.0, 0.0), 0.0001, "height sampling is deterministic")
	var terrain := TerrainBuilder.new()
	assertions.truthy(terrain.build(), "terrain builds for production-ground projection test")
	var terrain_mesh := terrain.get_node_or_null("TerrainMesh") as MeshInstance3D
	assertions.truthy(terrain_mesh != null, "terrain exposes its visual mesh")
	if terrain_mesh != null:
		assertions.equal(terrain_mesh.layers, 1, "painted ground mesh requires no special terrain receiver layer")
	assertions.truthy(terrain.has_method("get_surface_height_at"), "terrain exposes its rendered triangle height")
	if terrain_mesh != null and terrain.has_method("get_surface_height_at"):
		for point in [Vector2(-17.1, -3.6), Vector2(0.13, 0.27), Vector2(12.4, 8.7)]:
			assertions.near(
				float(terrain.call("get_surface_height_at", point.x, point.y)),
				_rendered_mesh_height(terrain_mesh, point.x, point.y),
				0.0001,
				"surface height matches the rendered terrain triangle at %s" % point
			)
	assertions.equal(
		ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"gl_compatibility",
		"production ground tests exercise the configured Compatibility renderer"
	)
	var terrain_body := terrain.get_node_or_null("TerrainBody") as StaticBody3D
	assertions.truthy(terrain_body != null, "terrain keeps its physical body")
	if terrain_body != null:
		assertions.equal(terrain_body.collision_layer, 1, "painted ground visuals do not alter terrain physics")
	terrain.free()


func _rendered_mesh_height(terrain_mesh: MeshInstance3D, world_x: float, world_z: float) -> float:
	var arrays := (terrain_mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var grid_x := clampf(world_x / TerrainBuilder.WORLD_SIZE.x + 0.5, 0.0, 1.0) * TerrainBuilder.SUBDIVISIONS
	var grid_z := clampf(world_z / TerrainBuilder.WORLD_SIZE.y + 0.5, 0.0, 1.0) * TerrainBuilder.SUBDIVISIONS
	var cell_x := mini(floori(grid_x), TerrainBuilder.SUBDIVISIONS - 1)
	var cell_z := mini(floori(grid_z), TerrainBuilder.SUBDIVISIONS - 1)
	var local_x := grid_x - float(cell_x)
	var local_z := grid_z - float(cell_z)
	var stride := TerrainBuilder.SUBDIVISIONS + 1
	var a := vertices[cell_z * stride + cell_x].y
	var b := vertices[cell_z * stride + cell_x + 1].y
	var c := vertices[(cell_z + 1) * stride + cell_x].y
	var d := vertices[(cell_z + 1) * stride + cell_x + 1].y
	if local_x + local_z <= 1.0:
		return a * (1.0 - local_x - local_z) + b * local_x + c * local_z
	return b * (1.0 - local_z) + c * (1.0 - local_x) + d * (local_x + local_z - 1.0)
