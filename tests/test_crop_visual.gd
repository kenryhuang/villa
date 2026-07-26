extends RefCounted

const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")


func run(assertions: TestAssert) -> void:
	var farming = FarmingSystemScript.new()
	var visual = MeshInstance3D.new()

	# Stage 0 = seed brown
	farming._update_visual_color(visual, 0, 4)
	var mat = visual.material_override as StandardMaterial3D
	assertions.truthy(mat != null, "stage 0 has material")
	assertions.near(mat.albedo_color.r, 0.55, 0.01, "seed brown red")

	# Stage 1 = sprout green
	farming._update_visual_color(visual, 1, 4)
	mat = visual.material_override as StandardMaterial3D
	assertions.near(mat.albedo_color.g, 0.7, 0.01, "sprout green")

	# Stage 2 = growing yellow-green
	farming._update_visual_color(visual, 2, 4)
	mat = visual.material_override as StandardMaterial3D
	assertions.near(mat.albedo_color.g, 0.8, 0.01, "growing green")

	# Stage 3 = mature gold (last stage)
	farming._update_visual_color(visual, 3, 4)
	mat = visual.material_override as StandardMaterial3D
	assertions.near(mat.albedo_color.r, 1.0, 0.01, "mature gold red")
	assertions.near(mat.albedo_color.g, 0.84, 0.01, "mature gold green")

	visual.free()
