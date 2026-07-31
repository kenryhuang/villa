extends RefCounted

const FeedbackScript = preload("res://scripts/buildings/construction_feedback.gd")


func run(assertions: TestAssert, tree: SceneTree) -> void:
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
	var progress := feedback.get_node("Progress") as Sprite3D
	var fixed_pivot := pivot.position
	feedback.advance_animation(0.0)
	assertions.near(pivot.rotation.z, deg_to_rad(25.0), 0.001, "zero delta leaves animation phase unchanged")
	feedback.advance_animation(0.43)
	assertions.equal(pivot.position, fixed_pivot, "hammer handle end remains the fixed pivot")
	assertions.truthy(
		pivot.rotation.z > deg_to_rad(25.0),
		"strike rotates the head down toward the base"
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
