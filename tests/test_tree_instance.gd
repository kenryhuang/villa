extends RefCounted

const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")

func run(assertions) -> void:
	assertions.near(TreeInstanceScript.trunk_radius_for(0.5), 0.24, 0.001, "small trunks clamp to minimum radius")
	assertions.near(TreeInstanceScript.trunk_radius_for(2.0), 0.46, 0.001, "large trunks clamp to maximum radius")
	assertions.near(TreeInstanceScript.trunk_height_for(2.0), 0.84, 0.001, "trunk height follows authored height")
	var occluder := TreeInstanceScript.occluder_dimensions(Vector2(2.0, 3.0))
	assertions.near(occluder.x, 0.92, 0.001, "occluder follows canopy width")
	assertions.near(occluder.y, 2.7, 0.001, "occluder follows canopy height")
	assertions.near(TreeInstanceScript.opacity_step(1.0, 0.3, 0.1), 0.5575, 0.001, "occluded opacity approaches target")
	var texture_size := Vector2(448.0, 768.0)
	var target_size := Vector2(3.0, 4.0)
	var pixel_size := target_size.x / texture_size.x
	var vertical_scale := TreeInstanceScript.vertical_scale_for(texture_size, target_size)
	assertions.near(vertical_scale, 4.0 / (768.0 * pixel_size), 0.0001, "tree corrects texture aspect ratio")
	assertions.near(texture_size.y * pixel_size * vertical_scale, target_size.y, 0.0001, "tree renders authored height")
