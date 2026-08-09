extends RefCounted

const YardScript = preload("res://scripts/buildings/building_production_yard.gd")
const ASSETS := {
	"timber": "res://assets/buildings/yards/timber_yard_fence.svg",
	"masonry": "res://assets/buildings/yards/masonry_yard_fence.svg",
	"industrial": "res://assets/buildings/yards/industrial_yard_fence.svg",
}


func run(assertions: TestAssert, tree: SceneTree) -> void:
	for style in ASSETS:
		assertions.truthy(ResourceLoader.exists(ASSETS[style]), "%s yard atlas exists" % style)

	var yard := YardScript.new()
	tree.root.add_child(yard)
	assertions.truthy(yard.configure(Vector2i(3, 3), "timber", Vector3(0.0, 0.0, -0.35)), "3x3 timber yard configures")
	assertions.equal(yard.get_fence_segment_count(), 12, "3x3 yard has one fence segment per perimeter edge cell")
	assertions.equal(yard.get_output_slots().size(), 6, "3x3 yard provides six collection slots")
	assertions.truthy(yard.all_output_slots_inside_bounds(), "3x3 collection slots stay inside the fence")
	assertions.equal(yard.get_style(), "timber", "yard preserves its style")
	yard.set_construction_stage(1)
	assertions.equal(yard.get_construction_stage(), 1, "yard exposes the frame construction stage")
	yard.set_preview_state(true, false)
	assertions.equal(yard.get_visual_tint(), Color(1.0, 0.38, 0.38, 0.68), "invalid preview tints the whole fence red")
	yard.set_preview_state(false, true)
	yard.set_maintenance_state("overdue")
	assertions.equal(yard.get_visual_tint(), Color(0.76, 0.72, 0.66, 1.0), "overdue maintenance desaturates the fence")
	yard.set_interaction_enabled(true)
	assertions.truthy(yard.has_enabled_collisions(), "completed yard enables perimeter collision")
	assertions.equal(yard.get_collision_layers(), [16], "yard collision uses only the physical world layer")
	yard.set_interaction_enabled(false)
	assertions.truthy(not yard.has_enabled_collisions(), "preview yard disables perimeter collision")
	yard.free()

	var large := YardScript.new()
	tree.root.add_child(large)
	assertions.truthy(large.configure(Vector2i(4, 4), "industrial", Vector3(0.0, 0.0, -0.55)), "4x4 industrial yard configures")
	assertions.equal(large.get_fence_segment_count(), 16, "4x4 yard has sixteen perimeter segments")
	assertions.equal(large.get_output_slots().size(), 8, "4x4 yard provides eight collection slots")
	assertions.truthy(large.all_output_slots_inside_bounds(), "4x4 collection slots stay inside the fence")
	assertions.truthy(not large.configure(Vector2i(2, 2), "timber", Vector3.ZERO), "unsupported yard size rejects")
	assertions.truthy(not large.configure(Vector2i(4, 4), "plastic", Vector3.ZERO), "unknown yard style rejects")
	large.clear_immediately()
	assertions.equal(large.get_fence_segment_count(), 0, "yard cleanup removes all derived fence segments")
	large.free()

