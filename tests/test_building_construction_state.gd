extends RefCounted

const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	for footprint in [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 2)]:
		assertions.equal(
			BuildingInstance.construction_duration_for(footprint),
			9.0,
			"construction duration follows three three-second frame transitions"
		)

	var game_data = GameDataScript.new()
	var barn = BuildingDataScript.from_dictionary(game_data.get_building("barn"))
	var feedback_hammer_height := clampf(
		minf(barn.visual_size.x, barn.visual_size.y) * 0.32,
		0.38,
		0.72
	)
	var instance = (load(barn.scene_path) as PackedScene).instantiate() as BuildingInstance
	tree.root.add_child(instance)
	instance.configure(barn, 4, 5, [])

	var stage_events: Array[int] = []
	var completion_events: Array[bool] = []
	var interaction_events: Array[bool] = []
	instance.construction_stage_changed.connect(
		func(_building: BuildingInstance, stage: BuildingInstance.ConstructionStage) -> void:
			stage_events.append(int(stage))
	)
	instance.construction_completed.connect(
		func(_building: BuildingInstance) -> void:
			completion_events.append(true)
	)
	instance.interacted.connect(
		func(_building: BuildingInstance, _player: Node) -> void:
			interaction_events.append(true)
	)

	instance.start_construction()
	var feedback := instance.get_node_or_null("ConstructionFeedback") as ConstructionFeedback
	var hammer := instance.get_node_or_null("ConstructionFeedback/HammerPivot") as Node3D
	var hammer_sprite := instance.get_node_or_null(
		"ConstructionFeedback/HammerPivot/HammerSprite"
	) as Sprite3D
	var progress_disk := instance.get_node_or_null(
		"ConstructionFeedback/Progress"
	) as Sprite3D
	var construction_sprite := instance.get_node("VisualRoot/ConstructionLayer") as Sprite3D
	var foundation_hammer_offset := Vector2.ZERO
	assertions.truthy(feedback != null, "construction creates independent feedback component")
	assertions.truthy(
		hammer != null and hammer_sprite != null,
		"feedback creates bottom hammer pivot and sprite"
	)
	assertions.truthy(progress_disk != null, "feedback creates upper-right progress disk")
	if feedback != null and hammer != null and hammer_sprite != null and progress_disk != null:
		assertions.truthy(feedback.visible, "unfinished construction shows feedback")
		assertions.truthy(hammer_sprite.texture != null, "hammer uses imported icon")
		assertions.truthy(
			not instance._visual_geometry().has(hammer_sprite),
			"hammer remains outside building visual tint and occlusion"
		)
		assertions.truthy(
			not instance._visual_geometry().has(progress_disk),
			"progress remains outside building visual tint and occlusion"
		)
		var foundation_material := hammer_sprite.material_override as ShaderMaterial
		assertions.truthy(foundation_material != null, "foundation configures hammer material")
		if foundation_material != null:
			foundation_hammer_offset = foundation_material.get_shader_parameter("screen_offset")
			var expected_foundation_offset := ConstructionFeedback.hammer_screen_offset_for(
				barn.visual_size,
				feedback_hammer_height,
				construction_sprite.texture
			)
			assertions.near(
				foundation_hammer_offset.distance_to(expected_foundation_offset),
				0.0,
				0.001,
				"foundation stage syncs its painted alpha contact to feedback"
			)
		var starting_rotation := hammer.rotation.z
		feedback.advance_animation(0.43)
		assertions.truthy(
			not is_equal_approx(hammer.rotation.z, starting_rotation),
			"hammer head strikes downward while construction runs"
		)
		instance.set_preview_mode(true)
		assertions.truthy(not feedback.visible, "building preview hides construction feedback")
		instance.set_preview_mode(false)
		assertions.truthy(feedback.visible, "leaving preview restores unfinished feedback")
	assertions.equal(instance.construction_stage, BuildingInstance.ConstructionStage.FOUNDATION, "construction starts at foundation")
	assertions.equal(instance.construction_elapsed, 0.0, "construction starts with zero elapsed")
	assertions.equal(instance.construction_duration, 9.0, "barn uses three three-second frame transitions")
	assertions.near(instance.get_construction_progress(), 0.0, 0.0001, "initial progress is zero")
	assertions.truthy(instance.has_node("VisualRoot/ConstructionLayer"), "construction sprite exists")
	assertions.truthy(instance.has_node("VisualRoot/ConstructionFallback"), "construction fallback exists")
	assertions.truthy(instance.has_node("VisualRoot/ConstructionEffects"), "construction effects root exists")
	assertions.equal(
		instance.get_construction_texture_path(BuildingInstance.ConstructionStage.FOUNDATION),
		"res://assets/buildings/construction/barn/barn_foundation.png",
		"foundation texture path is deterministic"
	)
	assertions.equal(instance.get_node("Collision").collision_layer, 16 | 64, "foundation blocks movement")
	assertions.equal(instance.get_node("InteractionArea").collision_layer, 0, "foundation interaction is disabled")
	assertions.equal(instance.get_node("CameraOccluder").collision_layer, 0, "foundation camera occluder is disabled")
	assertions.equal(instance.get_node("VisualRoot/BackLayer").visible, false, "foundation hides finished back art")
	assertions.equal(instance.get_node("VisualRoot/FrontLayer").visible, false, "foundation hides finished front art")
	instance.interact(instance)
	assertions.equal(interaction_events.size(), 0, "unfinished building rejects interaction")

	var foundation_texture: Texture2D = instance.get_node("VisualRoot/ConstructionLayer").texture
	for tween in tree.get_processed_tweens():
		tween.custom_step(2.0)
	instance.advance_construction(2.99)
	assertions.equal(
		instance.construction_stage,
		BuildingInstance.ConstructionStage.FOUNDATION,
		"construction remains on foundation before three seconds"
	)
	assertions.equal(stage_events.size(), 0, "no early stage signal")
	instance.advance_construction(0.01)
	assertions.equal(instance.construction_stage, BuildingInstance.ConstructionStage.FRAME, "three seconds advances to frame")
	assertions.equal(stage_events, [BuildingInstance.ConstructionStage.FRAME], "frame transition emits once")
	if progress_disk != null:
		var progress_material := progress_disk.material_override as ShaderMaterial
		assertions.truthy(progress_material != null, "progress disk uses shader material")
		if progress_material != null:
			assertions.near(
				float(progress_material.get_shader_parameter("progress")),
				1.0 / 3.0,
				0.001,
				"three seconds fills one third of total progress disk"
			)
	assertions.equal(instance.get_node("CameraOccluder").collision_layer, 32, "frame enables camera occlusion")
	assertions.equal(instance.get_node("InteractionArea").collision_layer, 0, "frame keeps interaction disabled")
	if hammer_sprite != null:
		var frame_material := hammer_sprite.material_override as ShaderMaterial
		assertions.truthy(frame_material != null, "frame stage keeps hammer material")
		if frame_material != null:
			var frame_hammer_offset: Vector2 = frame_material.get_shader_parameter("screen_offset")
			var expected_frame_offset := ConstructionFeedback.hammer_screen_offset_for(
				barn.visual_size,
				feedback_hammer_height,
				construction_sprite.texture
			)
			assertions.near(
				frame_hammer_offset.distance_to(expected_frame_offset),
				0.0,
				0.001,
				"frame stage recomputes hammer offset from its current texture"
			)
			assertions.truthy(
				frame_hammer_offset.distance_to(foundation_hammer_offset) > 0.001,
				"stage change updates hammer offset when painted bounds change"
			)
	var transitions := instance.get_node_or_null("VisualRoot/ConstructionTransitions")
	assertions.truthy(transitions != null, "construction transitions root exists")
	assertions.truthy(transitions != null and transitions.get_child_count() == 1, "stage change retains one outgoing sprite")
	assertions.near(instance.STAGE_FADE_OUT_DURATION, 2.0, 0.001, "outgoing stage fade duration")
	assertions.near(instance.STAGE_FADE_IN_DURATION, 2.0, 0.001, "incoming stage fade duration")
	if transitions != null and transitions.get_child_count() == 1:
		var outgoing := transitions.get_child(0) as Sprite3D
		assertions.equal(outgoing.texture, foundation_texture, "outgoing sprite keeps previous stage texture")
		for tween in tree.get_processed_tweens():
			tween.custom_step(1.0)
		assertions.near(outgoing.modulate.a, 0.5, 0.01, "outgoing frame is half transparent after one second")
		assertions.near(construction_sprite.modulate.a, 0.5, 0.01, "incoming frame is half visible after one second")
		for tween in tree.get_processed_tweens():
			tween.custom_step(1.0)
		assertions.near(outgoing.modulate.a, 0.0, 0.01, "outgoing frame finishes fading after two seconds")
		assertions.near(construction_sprite.modulate.a, 1.0, 0.01, "incoming frame finishes fading after two seconds")
		assertions.truthy(outgoing.is_queued_for_deletion(), "finished outgoing frame is queued for cleanup")
	instance.set_camera_occluded(true)
	instance._process(1.0)
	assertions.near(construction_sprite.modulate.a, 0.3, 0.001, "camera occlusion fades construction art")
	if hammer_sprite != null:
		assertions.near(hammer_sprite.modulate.a, 1.0, 0.001, "camera occlusion does not fade construction hammer")
	if progress_disk != null:
		assertions.near(progress_disk.modulate.a, 1.0, 0.001, "camera occlusion does not fade construction progress")
	instance.set_camera_occluded(false)
	instance.advance_construction_stage()
	assertions.equal(instance.construction_stage, BuildingInstance.ConstructionStage.HALF_BUILT, "manual advance moves exactly one stage")
	assertions.equal(stage_events.size(), 2, "manual transition emits once")

	instance.complete_construction()
	assertions.truthy(instance.is_construction_complete(), "explicit completion is observable")
	assertions.near(instance.get_construction_progress(), 1.0, 0.0001, "completed progress is one")
	assertions.equal(stage_events.size(), 3, "complete transition emits once")
	assertions.equal(completion_events.size(), 1, "completion signal emits once")
	assertions.equal(instance.get_node("InteractionArea").collision_layer, 64 | 256, "completion enables interaction")
	assertions.equal(instance.get_node("CameraOccluder").collision_layer, 32, "completion keeps camera occlusion")
	assertions.truthy(instance.get_node("VisualRoot/BackLayer").visible, "completion shows finished back art")
	assertions.truthy(instance.get_node("VisualRoot/FrontLayer").visible, "completion shows finished front art")
	assertions.equal(instance.get_node("VisualRoot/ConstructionLayer").visible, false, "completion hides construction sprite")
	if feedback != null:
		assertions.truthy(not feedback.visible, "completed construction hides feedback")
	instance.interact(instance)
	assertions.equal(interaction_events.size(), 1, "completed building accepts interaction")

	instance.advance_construction(9.0)
	instance.advance_construction_stage()
	instance.complete_construction()
	assertions.equal(stage_events.size(), 3, "completed construction ignores further advances")
	assertions.equal(completion_events.size(), 1, "completion signal never repeats")

	instance.start_construction()
	stage_events.clear()
	completion_events.clear()
	instance.advance_construction(9.0)
	assertions.equal(
		stage_events,
		[
			BuildingInstance.ConstructionStage.FRAME,
			BuildingInstance.ConstructionStage.HALF_BUILT,
			BuildingInstance.ConstructionStage.COMPLETE,
		],
		"large delta emits every crossed stage in order"
	)
	assertions.equal(completion_events.size(), 1, "large delta completes once")
	instance.start_construction()
	instance.deactivate()
	if feedback != null:
		assertions.truthy(not feedback.visible, "deactivated building hides construction feedback")

	instance.free()

	var missing_art = barn.duplicate(true) as BuildingData
	missing_art.building_id = "missing_construction_art"
	var fallback_instance = (load(missing_art.scene_path) as PackedScene).instantiate() as BuildingInstance
	tree.root.add_child(fallback_instance)
	fallback_instance.configure(missing_art, 8, 8, [])
	fallback_instance.start_construction()
	assertions.equal(
		fallback_instance.get_missing_construction_art_warning_count(),
		1,
		"missing construction art emits one deduplicated warning"
	)
	fallback_instance.restore_construction(BuildingInstance.ConstructionStage.FOUNDATION, 0.0)
	assertions.equal(
		fallback_instance.get_missing_construction_art_warning_count(),
		1,
		"reapplying a missing stage does not repeat its warning"
	)
	fallback_instance.advance_construction_stage()
	var fallback := fallback_instance.get_node("VisualRoot/ConstructionFallback") as Node3D
	var frame_post := fallback.get_node("Frame").get_child(0) as MeshInstance3D
	assertions.truthy(fallback.visible, "missing frame art shows procedural fallback")
	assertions.truthy(
		fallback_instance._visual_geometry().has(frame_post),
		"camera opacity traversal includes nested fallback geometry"
	)
	fallback_instance.set_camera_occluded(true)
	fallback_instance._process(1.0)
	assertions.near(frame_post.transparency, 0.7, 0.001, "nested fallback fades when camera-occluded")
	fallback_instance.free()
	game_data.free()
