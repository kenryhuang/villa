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
		assertions.equal(terrain_mesh.layers, 1 | (1 << 7), "terrain receives normal rendering and production ground decals")
	var terrain_body := terrain.get_node_or_null("TerrainBody") as StaticBody3D
	assertions.truthy(terrain_body != null, "terrain keeps its physical body")
	if terrain_body != null:
		assertions.equal(terrain_body.collision_layer, 1, "production decal layer does not alter terrain physics")
	terrain.free()
