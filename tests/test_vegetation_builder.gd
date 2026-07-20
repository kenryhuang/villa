extends RefCounted

const VegetationBuilderScript = preload("res://scripts/world/vegetation_builder.gd")

func run(assertions) -> void:
	var texture_size := Vector2(448.0, 768.0)
	var target_size := Vector2(3.0, 4.0)
	var pixel_size := target_size.x / texture_size.x
	var vertical_scale := VegetationBuilderScript.vertical_scale_for(texture_size, target_size)
	assertions.near(vertical_scale, 4.0 / (768.0 * pixel_size), 0.0001, "vegetation corrects new texture aspect ratio")
	assertions.near(texture_size.y * pixel_size * vertical_scale, target_size.y, 0.0001, "vegetation renders authored height")
