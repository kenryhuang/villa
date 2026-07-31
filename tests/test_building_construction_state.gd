extends RefCounted

const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	for footprint in [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 2)]:
		assertions.equal(
			BuildingInstance.construction_duration_for(footprint),
			30.0,
			"construction duration follows three ten-second frame transitions"
		)

	var game_data = GameDataScript.new()
	var barn = BuildingDataScript.from_dictionary(game_data.get_building("barn"))
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
	var hammer := instance.get_node_or_null("VisualRoot/ConstructionHammer") as Node3D
	var hammer_sprite := instance.get_node_or_null("VisualRoot/ConstructionHammer/HammerSprite") as Sprite3D
	assertions.truthy(hammer != null, "construction creates hammer pivot")
	assertions.truthy(hammer_sprite != null, "construction creates hammer sprite")
	if hammer != null and hammer_sprite != null:
		assertions.truthy(hammer.visible, "unfinished construction shows hammer")
		assertions.truthy(hammer_sprite.texture != null, "hammer uses imported icon")
		var starting_rotation := hammer.rotation.z
		instance._animate_construction_hammer(0.2)
		assertions.truthy(not is_equal_approx(hammer.rotation.z, starting_rotation), "hammer swings while construction runs")
		instance.set_preview_mode(true)
		assertions.truthy(not hammer.visible, "building preview hides construction hammer")
		instance.set_preview_mode(false)
		assertions.truthy(hammer.visible, "leaving preview restores unfinished hammer")
	assertions.equal(instance.construction_stage, BuildingInstance.ConstructionStage.FOUNDATION, "construction starts at foundation")
	assertions.equal(instance.construction_elapsed, 0.0, "construction starts with zero elapsed")
	assertions.equal(instance.construction_duration, 30.0, "barn uses three ten-second frame transitions")
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
	instance.advance_construction(9.99)
	assertions.equal(
		instance.construction_stage,
		BuildingInstance.ConstructionStage.FOUNDATION,
		"construction remains on foundation before ten seconds"
	)
	assertions.equal(stage_events.size(), 0, "no early stage signal")
	instance.advance_construction(0.01)
	assertions.equal(instance.construction_stage, BuildingInstance.ConstructionStage.FRAME, "ten seconds advances to frame")
	assertions.equal(stage_events, [BuildingInstance.ConstructionStage.FRAME], "frame transition emits once")
	assertions.equal(instance.get_node("CameraOccluder").collision_layer, 32, "frame enables camera occlusion")
	assertions.equal(instance.get_node("InteractionArea").collision_layer, 0, "frame keeps interaction disabled")
	var construction_sprite := instance.get_node("VisualRoot/ConstructionLayer") as Sprite3D
	instance.set_camera_occluded(true)
	instance._process(1.0)
	assertions.near(construction_sprite.modulate.a, 0.3, 0.001, "camera occlusion fades construction art")
	if hammer_sprite != null:
		assertions.near(hammer_sprite.modulate.a, 1.0, 0.001, "camera occlusion does not fade construction hammer")
	instance.set_camera_occluded(false)
	var transitions := instance.get_node_or_null("VisualRoot/ConstructionTransitions")
	assertions.truthy(transitions != null, "construction transitions root exists")
	assertions.truthy(transitions != null and transitions.get_child_count() == 1, "stage change retains one outgoing sprite")
	if transitions != null and transitions.get_child_count() == 1:
		var outgoing := transitions.get_child(0) as Sprite3D
		assertions.equal(outgoing.texture, foundation_texture, "outgoing sprite keeps previous stage texture")
	assertions.near(instance.STAGE_FADE_OUT_DURATION, 0.12, 0.001, "outgoing stage fade duration")
	assertions.near(instance.STAGE_FADE_IN_DURATION, 0.18, 0.001, "incoming stage fade duration")

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
	if hammer != null:
		assertions.truthy(not hammer.visible, "completed construction hides hammer")
	instance.interact(instance)
	assertions.equal(interaction_events.size(), 1, "completed building accepts interaction")

	instance.advance_construction(20.0)
	instance.advance_construction_stage()
	instance.complete_construction()
	assertions.equal(stage_events.size(), 3, "completed construction ignores further advances")
	assertions.equal(completion_events.size(), 1, "completion signal never repeats")

	instance.start_construction()
	stage_events.clear()
	completion_events.clear()
	instance.advance_construction(30.0)
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
