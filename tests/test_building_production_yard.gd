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
	for style in ASSETS:
		var staged_yard := YardScript.new()
		tree.root.add_child(staged_yard)
		assertions.truthy(
			staged_yard.configure(Vector2i(3, 3), style, Vector3.ZERO),
			"%s yard configures for frame inspection" % style
		)
		for stage in 4:
			staged_yard.set_construction_stage(stage)
			for sprite in _fence_sprites(staged_yard):
				var axis := int(sprite.get_meta("axis", -1))
				assertions.truthy(axis in [0, 1], "%s fence segment records its world axis" % style)
				assertions.equal(
					sprite.region_rect,
					Rect2(512.0, float(stage) * 512.0, 512.0, 512.0),
					"%s stage %d uses the diagonal 2.5D frame" % [style, stage]
				)
				assertions.equal(
					sprite.billboard,
					BaseMaterial3D.BILLBOARD_ENABLED,
					"%s fence follows the locked 2.5D camera" % style
				)
				assertions.equal(
					sprite.flip_h,
					axis == 1,
					"%s fence mirrors only the Z-axis edge" % style
				)
				assertions.truthy(
					sprite.pixel_size * 512.0 * sprite.scale.y <= 0.82,
					"%s fence remains visually low" % style
				)
		staged_yard.free()

	var yard := YardScript.new()
	tree.root.add_child(yard)
	assertions.truthy(yard.configure(Vector2i(3, 3), "timber", Vector3(0.0, 0.0, -0.35)), "3x3 timber yard configures")
	assertions.equal(yard.get_fence_segment_count(), 12, "3x3 yard has one fence segment per perimeter edge cell")
	assertions.equal(yard.get_output_slots().size(), 6, "3x3 yard provides six collection slots")
	assertions.truthy(yard.all_output_slots_inside_bounds(), "3x3 collection slots stay inside the fence")
	assertions.equal(yard.get_style(), "timber", "yard preserves its style")
	_assert_closed_rectangle_layout(yard, Vector2i(3, 3), assertions)
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

	var transition_yard := YardScript.new()
	tree.root.add_child(transition_yard)
	assertions.truthy(
		transition_yard.configure(Vector2i(3, 3), "masonry", Vector3.ZERO),
		"transition test yard configures"
	)
	var has_transition_api := (
		transition_yard.has_method("get_transition_sprite_count")
		and transition_yard.has_method("advance_transition_for_test")
	)
	assertions.truthy(has_transition_api, "yard exposes deterministic crossfade lifecycle")
	if has_transition_api:
		transition_yard.set_construction_stage(0)
		assertions.equal(
			transition_yard.get_transition_sprite_count(),
			12,
			"stage change keeps one outgoing sprite per fence segment"
		)
		_assert_sprite_stage(_fence_sprites(transition_yard), 0, assertions, "incoming fence uses the new stage")
		_assert_sprite_stage(_transition_sprites(transition_yard), 3, assertions, "outgoing fence keeps the old stage")
		transition_yard.advance_transition_for_test(2.0)
		assertions.equal(transition_yard.get_transition_sprite_count(), 0, "two seconds completes the fence crossfade")

		transition_yard.set_construction_stage(1)
		transition_yard.advance_transition_for_test(0.5)
		transition_yard.set_construction_stage(2)
		assertions.equal(
			transition_yard.get_transition_sprite_count(),
			12,
			"interrupted crossfade replaces rather than stacks outgoing sprites"
		)
		_assert_sprite_stage(_transition_sprites(transition_yard), 1, assertions, "interrupted crossfade departs from the latest stage")
		transition_yard.set_preview_state(true, false)
		for sprite in _fence_sprites(transition_yard):
			assertions.truthy(sprite.modulate.a < 0.68, "preview tint preserves incoming crossfade alpha")
		transition_yard.clear_immediately()
		assertions.equal(transition_yard.get_transition_sprite_count(), 0, "immediate cleanup removes outgoing fence sprites")
		assertions.equal(_all_fence_sprites(transition_yard).size(), 0, "immediate cleanup removes every fence visual")
	transition_yard.free()


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
	for column in 2:
		assertions.truthy(
			_frame_horizontal_span(image, column, 3) >= 480,
			"%s completed fence orientation %d reaches adjacent grid cells" % [style, column]
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


func _frame_horizontal_span(image: Image, column: int, row: int) -> int:
	var left := FRAME_SIZE.x
	var right := -1
	var x_start := column * FRAME_SIZE.x
	var y_start := row * FRAME_SIZE.y
	for local_y in range(0, FRAME_SIZE.y, 4):
		for local_x in range(0, FRAME_SIZE.x, 4):
			if image.get_pixel(x_start + local_x, y_start + local_y).a > 0.05:
				left = mini(left, local_x)
				right = maxi(right, local_x)
	return right - left + 1 if right >= left else 0


func _assert_closed_rectangle_layout(
	yard: Node3D,
	size: Vector2i,
	assertions: TestAssert
) -> void:
	var expected: Array[Vector2] = []
	var half_x := float(size.x) * 0.5
	var half_z := float(size.y) * 0.5
	for index in size.x:
		var x := -half_x + 0.5 + float(index)
		expected.append(Vector2(x, -half_z))
		expected.append(Vector2(x, half_z))
	for index in size.y:
		var z := -half_z + 0.5 + float(index)
		expected.append(Vector2(-half_x, z))
		expected.append(Vector2(half_x, z))
	var actual: Array[Vector2] = []
	for sprite in _fence_sprites(yard):
		actual.append(Vector2(sprite.position.x, sprite.position.z))
	for point in expected:
		assertions.truthy(point in actual, "yard fence occupies closed perimeter point %s" % point)


func _fence_sprites(root: Node) -> Array[Sprite3D]:
	var result: Array[Sprite3D] = []
	for child in root.get_children():
		if child is Sprite3D and not child.get_meta("yard_transition", false):
			result.append(child as Sprite3D)
		result.append_array(_fence_sprites(child))
	return result


func _transition_sprites(root: Node) -> Array[Sprite3D]:
	var result: Array[Sprite3D] = []
	for child in root.get_children():
		if child is Sprite3D and child.get_meta("yard_transition", false):
			result.append(child as Sprite3D)
		result.append_array(_transition_sprites(child))
	return result


func _all_fence_sprites(root: Node) -> Array[Sprite3D]:
	var result: Array[Sprite3D] = []
	for child in root.get_children():
		if child is Sprite3D:
			result.append(child as Sprite3D)
		result.append_array(_all_fence_sprites(child))
	return result


func _assert_sprite_stage(
	sprites: Array[Sprite3D],
	stage: int,
	assertions: TestAssert,
	message: String
) -> void:
	for sprite in sprites:
		assertions.equal(sprite.region_rect.position.y, float(stage) * 512.0, message)
