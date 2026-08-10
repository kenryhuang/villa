extends RefCounted

const YardScript = preload("res://scripts/buildings/building_production_yard.gd")
const ASSETS := {
	"timber": "res://assets/buildings/yards/timber_yard_fence.png",
	"masonry": "res://assets/buildings/yards/masonry_yard_fence.png",
	"industrial": "res://assets/buildings/yards/industrial_yard_fence.png",
}
const FRAME_SIZE := Vector2i(512, 512)
const ATLAS_SIZE := Vector2(1024, 2048)


func run(assertions: TestAssert, tree: SceneTree) -> void:
	for style in ASSETS:
		assertions.truthy(ResourceLoader.exists(ASSETS[style]), "%s yard atlas exists" % style)
		_validate_painted_atlas(style, ASSETS[style], assertions)
		assertions.truthy(
			str(YardScript.TEXTURES.get(style, "")).ends_with(".png"),
			"%s yard runtime uses raster painted art" % style
		)
	assertions.equal(
		YardScript.ATLAS_FRAME_SIZE,
		Vector2(512.0, 512.0),
		"yard atlas exposes high-detail 512px frames"
	)

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


func _validate_painted_atlas(
	style: String,
	path: String,
	assertions: TestAssert
) -> void:
	if not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	assertions.truthy(texture != null, "%s yard atlas imports as Texture2D" % style)
	if texture == null:
		return
	assertions.equal(texture.get_size(), ATLAS_SIZE, "%s yard atlas has the 2x4 frame dimensions" % style)
	var image := texture.get_image()
	assertions.truthy(image.detect_alpha(), "%s yard atlas preserves transparency" % style)
	assertions.equal(image.get_pixel(0, 0).a, 0.0, "%s yard atlas has a transparent corner" % style)
	var baselines: Array[int] = []
	for row in 4:
		for column in 2:
			var baseline := _frame_baseline(image, column, row)
			assertions.truthy(
				baseline >= 0,
				"%s yard frame %d:%d contains painted pixels" % [style, column, row]
			)
			if baseline >= 0:
				baselines.append(baseline)
	if baselines.size() == 8:
		var lowest: int = int(baselines.min())
		var highest: int = int(baselines.max())
		assertions.truthy(
			highest - lowest <= 20,
			"%s yard frames share one ground baseline" % style
		)


func _frame_baseline(image: Image, column: int, row: int) -> int:
	var baseline := -1
	var x_start := column * FRAME_SIZE.x
	var y_start := row * FRAME_SIZE.y
	for local_y in range(0, FRAME_SIZE.y, 4):
		for local_x in range(0, FRAME_SIZE.x, 4):
			if image.get_pixel(x_start + local_x, y_start + local_y).a > 0.05:
				baseline = local_y
	return baseline
