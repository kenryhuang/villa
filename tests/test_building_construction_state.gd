extends RefCounted

const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	assertions.equal(BuildingInstance.construction_duration_for(Vector2i(1, 1)), 3.0, "1x1 construction duration")
	assertions.equal(BuildingInstance.construction_duration_for(Vector2i(2, 2)), 4.0, "2x2 construction duration")
	assertions.equal(BuildingInstance.construction_duration_for(Vector2i(3, 3)), 5.0, "3x3 construction duration")
	assertions.equal(BuildingInstance.construction_duration_for(Vector2i(4, 2)), 5.0, "large construction duration is capped")

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
	assertions.equal(instance.construction_stage, BuildingInstance.ConstructionStage.FOUNDATION, "construction starts at foundation")
	assertions.equal(instance.construction_elapsed, 0.0, "construction starts with zero elapsed")
	assertions.equal(instance.construction_duration, 4.0, "barn uses 2x2 duration")
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

	instance.advance_construction(instance.construction_duration / 3.0)
	assertions.equal(instance.construction_stage, BuildingInstance.ConstructionStage.FRAME, "time advances to frame")
	assertions.equal(stage_events, [BuildingInstance.ConstructionStage.FRAME], "frame transition emits once")
	assertions.equal(instance.get_node("CameraOccluder").collision_layer, 32, "frame enables camera occlusion")
	assertions.equal(instance.get_node("InteractionArea").collision_layer, 0, "frame keeps interaction disabled")

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
	instance.advance_construction(20.0)
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
	game_data.free()
