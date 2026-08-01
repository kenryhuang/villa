extends RefCounted

const FeedbackScript = preload("res://scripts/buildings/construction_feedback.gd")
const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const FRAME_BUILDING_IDS := [
	"barn",
	"greenhouse",
	"windmill",
	"chicken_coop",
	"beehive",
	"well",
	"workbench",
	"lamp",
	"fence",
]


func run(assertions: TestAssert, tree: SceneTree) -> void:
	assertions.near(
		FeedbackScript.STRIKE_PERIOD,
		0.6,
		0.001,
		"hammer completes a full strike every 0.6 seconds"
	)
	assertions.near(
		rad_to_deg(FeedbackScript.strike_angle_for_phase(0.0)),
		25.0,
		0.01,
		"strike starts raised"
	)
	assertions.near(
		rad_to_deg(FeedbackScript.strike_angle_for_phase(0.25)),
		25.0,
		0.01,
		"raised hold ends at 25 percent"
	)
	assertions.near(
		rad_to_deg(FeedbackScript.strike_angle_for_phase(0.48)),
		105.0,
		0.01,
		"hammer reaches the base at 48 percent"
	)
	assertions.near(
		rad_to_deg(FeedbackScript.strike_angle_for_phase(0.55)),
		105.0,
		0.01,
		"impact pause keeps the contact angle"
	)
	assertions.near(
		rad_to_deg(FeedbackScript.strike_angle_for_phase(1.0)),
		25.0,
		0.01,
		"rebound returns to raised angle"
	)

	var feedback := FeedbackScript.new()
	tree.root.add_child(feedback)
	feedback.configure(Vector2(3.0, 2.4))
	feedback.update_state(1.0 / 3.0, false, false, true)
	var pivot := feedback.get_node("HammerPivot") as Node3D
	var hammer_sprite := pivot.get_node("HammerSprite") as Sprite3D
	var progress := feedback.get_node("Progress") as Sprite3D
	assertions.equal(
		pivot.position,
		Vector3.ZERO,
		"hammer billboard pivot stays at the building foundation origin"
	)
	assertions.equal(
		hammer_sprite.position,
		Vector3.ZERO,
		"hammer sprite geometry is anchored directly at the handle-end pivot"
	)
	var hammer_material := hammer_sprite.material_override as ShaderMaterial
	assertions.truthy(hammer_material != null, "hammer uses a pivot-aware billboard shader")
	if hammer_material != null:
		assertions.equal(
			hammer_material.render_priority,
			10,
			"hammer feedback renders above transparent construction layers"
		)
		assertions.near(
			float(hammer_material.get_shader_parameter("strike_angle")),
			deg_to_rad(25.0),
			0.001,
			"hammer shader starts at the raised angle"
		)
		var supports_painted_pivot := hammer_material.shader.code.contains("pivot_uv")
		assertions.truthy(supports_painted_pivot, "hammer material exposes painted pivot UV")
		if supports_painted_pivot:
			var hammer_bounds := hammer_sprite.texture.get_image().get_used_rect()
			var expected_pivot_v := float(hammer_bounds.end.y - 1) / float(
				hammer_sprite.texture.get_height() - 1
			)
			var pivot_uv: Vector2 = hammer_material.get_shader_parameter("pivot_uv")
			assertions.near(pivot_uv.x, 0.5, 0.001, "painted handle pivot stays horizontally centered")
			assertions.near(
				pivot_uv.y,
				expected_pivot_v,
				0.001,
				"painted handle pivot follows the visible alpha endpoint"
			)
		var supports_screen_offset := hammer_material.shader.code.contains("screen_offset")
		assertions.truthy(
			supports_screen_offset,
			"hammer material exposes a camera-plane screen offset"
		)
		if supports_screen_offset:
			var screen_offset: Vector2 = hammer_material.get_shader_parameter("screen_offset")
			var expected_screen_offset := FeedbackScript.hammer_screen_offset_for(
				Vector2(3.0, 2.4), 0.72
			)
			var expected_lever := 0.72 * 0.72
			var expected_head_from_pivot := Vector2(
				-sin(FeedbackScript.IMPACT_ANGLE) * expected_lever,
				cos(FeedbackScript.IMPACT_ANGLE) * expected_lever
			)
			var expected_contact_offset := (
				Vector2(3.0 * 0.34, 2.4 * 0.10) - expected_head_from_pivot
			)
			assertions.near(
				expected_screen_offset.x,
				expected_contact_offset.x,
				0.001,
				"hammer offset helper back-solves the impact head contact x"
			)
			assertions.near(
				expected_screen_offset.y,
				expected_contact_offset.y,
				0.001,
				"hammer offset helper back-solves the impact head contact y"
			)
			assertions.equal(
				screen_offset,
				expected_screen_offset,
				"hammer material receives the impact head contact offset"
			)
			assertions.truthy(
				screen_offset.x > 3.0 * 0.30,
				"impact contact places the handle pivot right of the old width-only offset"
			)
			assertions.truthy(
				screen_offset.y > 0.0,
				"impact contact lifts the handle pivot so the hammer head meets the foundation"
			)
			assertions.near(
				hammer_sprite.extra_cull_margin,
				expected_screen_offset.length() + 0.72,
				0.001,
				"hammer cull margin covers its camera-plane offset and rotated sprite radius"
			)

	var texture_feedback := FeedbackScript.new()
	tree.root.add_child(texture_feedback)
	var supports_texture_configure := _method_argument_count(texture_feedback, "configure") >= 2
	var has_painted_contact_helper := texture_feedback.has_method("painted_foundation_contact_for")
	assertions.truthy(
		supports_texture_configure,
		"construction feedback configure accepts the current construction texture"
	)
	assertions.truthy(
		has_painted_contact_helper,
		"construction feedback exposes a painted foundation contact helper"
	)
	var game_data := GameDataScript.new()
	var offsets_by_id := {}
	for building_id in FRAME_BUILDING_IDS:
		var building_data := BuildingDataScript.from_dictionary(game_data.get_building(building_id))
		var frame_texture := load(
			"res://assets/buildings/construction/%s/%s_frame.png" % [building_id, building_id]
		) as Texture2D
		assertions.truthy(frame_texture != null, "%s frame texture loads for contact scan" % building_id)
		if frame_texture == null:
			continue
		var frame_hammer_height := clampf(
			minf(building_data.visual_size.x, building_data.visual_size.y) * 0.32,
			0.38,
			0.72
		)
		var expected_contact_info := _expected_painted_foundation_contact(
			building_data.visual_size,
			frame_hammer_height,
			frame_texture
		)
		if supports_texture_configure:
			texture_feedback.call("configure", building_data.visual_size, frame_texture)
		else:
			texture_feedback.configure(building_data.visual_size)
		var frame_sprite := texture_feedback.get_node("HammerPivot/HammerSprite") as Sprite3D
		var frame_material := frame_sprite.material_override as ShaderMaterial
		assertions.truthy(frame_material != null, "%s frame configures hammer material" % building_id)
		if frame_material == null:
			continue
		var frame_offset: Vector2 = frame_material.get_shader_parameter("screen_offset")
		var frame_lever := frame_hammer_height * 0.72
		var frame_head_from_pivot := Vector2(
			-sin(FeedbackScript.IMPACT_ANGLE) * frame_lever,
			cos(FeedbackScript.IMPACT_ANGLE) * frame_lever
		)
		var actual_contact := frame_offset + frame_head_from_pivot
		var expected_contact: Vector2 = expected_contact_info.contact
		var bottom_band_edge_x: float = expected_contact_info.edge_x
		assertions.truthy(
			actual_contact.x <= bottom_band_edge_x + 0.001,
			"%s hammer contact does not pass the bottom-band alpha right edge" % building_id
		)
		assertions.near(
			actual_contact.x,
			bottom_band_edge_x,
			0.001,
			"%s hammer contact reaches the bottom-band alpha right edge" % building_id
		)
		assertions.near(
			actual_contact.y,
			expected_contact.y,
			0.001,
			"%s hammer contact follows the painted foundation bottom" % building_id
		)
		if has_painted_contact_helper:
			var helper_contact: Vector2 = texture_feedback.call(
				"painted_foundation_contact_for",
				building_data.visual_size,
				frame_hammer_height,
				frame_texture
			)
			assertions.near(
				helper_contact.distance_to(expected_contact),
				0.0,
				0.001,
				"%s helper derives its contact from frame alpha" % building_id
			)
		offsets_by_id[building_id] = frame_offset
	assertions.truthy(
		(offsets_by_id.get("barn", Vector2.ZERO) as Vector2).distance_to(
			offsets_by_id.get("windmill", Vector2.ZERO) as Vector2
		) > 0.05,
		"barn and windmill frame alpha produce different hammer offsets"
	)
	if has_painted_contact_helper:
		var fallback_size := Vector2(3.0, 2.4)
		var fallback_height := 0.72
		var fallback_contact := Vector2(fallback_size.x * 0.34, fallback_size.y * 0.10)
		var null_contact: Vector2 = texture_feedback.call(
			"painted_foundation_contact_for", fallback_size, fallback_height, null
		)
		assertions.equal(null_contact, fallback_contact, "null construction art uses fallback contact")
		var empty_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		empty_image.fill(Color.TRANSPARENT)
		var empty_texture := ImageTexture.create_from_image(empty_image)
		var empty_contact: Vector2 = texture_feedback.call(
			"painted_foundation_contact_for", fallback_size, fallback_height, empty_texture
		)
		assertions.equal(empty_contact, fallback_contact, "empty construction art uses fallback contact")
	texture_feedback.free()
	game_data.free()

	var fixed_pivot := pivot.position
	feedback.advance_animation(0.0)
	assertions.near(pivot.rotation.z, deg_to_rad(25.0), 0.001, "zero delta leaves animation phase unchanged")
	pivot.visible = false
	feedback.advance_animation(0.3)
	assertions.near(
		pivot.rotation.z,
		deg_to_rad(25.0),
		0.001,
		"hidden hammer does not advance its strike animation"
	)
	pivot.visible = true
	feedback.advance_animation(0.15)
	assertions.near(
		pivot.rotation.z,
		deg_to_rad(25.0),
		0.001,
		"0.15 seconds reaches phase 0.25 and remains at the raised angle"
	)
	feedback.advance_animation(0.12)
	assertions.equal(pivot.position, fixed_pivot, "hammer handle end remains the fixed pivot")
	assertions.near(
		pivot.rotation.z,
		FeedbackScript.strike_angle_for_phase(0.45),
		0.001,
		"0.27 seconds reaches the exact non-boundary strike angle at phase 0.45"
	)
	if hammer_material != null:
		assertions.near(
			float(hammer_material.get_shader_parameter("strike_angle")),
			pivot.rotation.z,
			0.001,
			"rendered hammer angle follows the logical pivot angle"
		)
	assertions.truthy(feedback.visible, "active unfinished construction shows feedback")
	var progress_material := progress.material_override as ShaderMaterial
	assertions.truthy(progress_material != null, "progress uses a shader material")
	if progress_material != null:
		assertions.near(
			float(progress_material.get_shader_parameter("progress")),
			1.0 / 3.0,
			0.001,
			"progress shader receives total progress"
		)
	feedback.update_state(2.0 / 3.0, false, false, true)
	if progress_material != null:
		assertions.near(
			float(progress_material.get_shader_parameter("progress")),
			2.0 / 3.0,
			0.001,
			"progress continues across construction frames"
		)
	feedback.update_state(0.5, true, false, true)
	assertions.truthy(not feedback.visible, "preview hides construction feedback")
	feedback.update_state(1.0, false, true, true)
	assertions.truthy(not feedback.visible, "completion hides construction feedback")
	feedback.update_state(0.5, false, false, false)
	assertions.truthy(not feedback.visible, "deactivation hides construction feedback")
	feedback.free()


static func _method_argument_count(instance: Object, method_name: String) -> int:
	for method in instance.get_method_list():
		if method.get("name", "") == method_name:
			return (method.get("args", []) as Array).size()
	return 0


static func _expected_painted_foundation_contact(
	visual_size: Vector2,
	hammer_height: float,
	texture: Texture2D
) -> Dictionary:
	var fallback := Vector2(visual_size.x * 0.34, visual_size.y * 0.10)
	if texture == null:
		return {"contact": fallback, "edge_x": fallback.x}
	var image := texture.get_image()
	if image == null or image.is_empty():
		return {"contact": fallback, "edge_x": fallback.x}
	var painted_bounds := image.get_used_rect()
	if painted_bounds.size == Vector2i.ZERO:
		return {"contact": fallback, "edge_x": fallback.x}
	var band_height := maxi(ceili(float(painted_bounds.size.y) * 0.20), 1)
	var band_start_y := maxi(painted_bounds.position.y, painted_bounds.end.y - band_height)
	var right_x := -1
	var bottom_y := -1
	for y in range(band_start_y, painted_bounds.end.y):
		for x in range(painted_bounds.position.x, painted_bounds.end.x):
			if image.get_pixel(x, y).a <= 0.10:
				continue
			right_x = maxi(right_x, x)
			bottom_y = maxi(bottom_y, y)
	if right_x < 0 or bottom_y < 0:
		return {"contact": fallback, "edge_x": fallback.x}
	var u := float(right_x) / float(maxi(image.get_width() - 1, 1))
	var v := float(bottom_y) / float(maxi(image.get_height() - 1, 1))
	var edge_x := (u - 0.5) * visual_size.x
	var head_center_lift := hammer_height * -0.30
	return {
		"contact": Vector2(edge_x, (1.0 - v) * visual_size.y + head_center_lift),
		"edge_x": edge_x,
	}
