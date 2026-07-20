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
