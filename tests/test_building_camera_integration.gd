extends RefCounted

const CameraRigScript = preload("res://scripts/camera/camera_rig.gd")
const PlayerScript = preload("res://scripts/actors/player.gd")
const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var game_data = GameDataScript.new()
	var data = BuildingDataScript.from_dictionary(game_data.get_building("barn"))
	var building = (load(data.scene_path) as PackedScene).instantiate()
	tree.root.add_child(building)
	building.configure(data, 1, 1, [])
	var tree_instance = TreeInstanceScript.new()

	var occluders: Array[Node] = [tree_instance, building]
	var only_building: Array[Node] = [building]
	CameraRigScript.apply_occlusion_state(occluders, only_building)
	assertions.near(building.get_target_opacity(), 0.3, 0.001, "occluding building fades")
	assertions.near(tree_instance.occlusion_target, 1.0, 0.001, "non-occluding tree remains clear")
	assertions.equal(
		CameraRigScript.find_occlusion_target(building.get_node("CameraOccluder")),
		building,
		"camera resolves building from child occluder"
	)
	assertions.equal(
		PlayerScript.find_interaction_target(building.get_node("InteractionArea")),
		building,
		"player resolves building from interaction area"
	)
	assertions.equal(
		PlayerScript.find_interaction_target(building.get_node("Collision/CollisionShape3D")),
		building,
		"player resolves building from collision child"
	)
	assertions.truthy(
		PlayerScript.is_interaction_hit_in_range(Vector3.ZERO, Vector3(2.4, 8.0, 0.0), 2.5),
		"interaction range uses horizontal player distance"
	)
	assertions.equal(
		PlayerScript.is_interaction_hit_in_range(Vector3.ZERO, Vector3(2.6, 0.0, 0.0), 2.5),
		false,
		"interaction rejects hits beyond the player range"
	)
	var unrelated := Node3D.new()
	assertions.equal(PlayerScript.find_interaction_target(unrelated), null, "unrelated node is not interactive")

	unrelated.free()
	tree_instance.free()
	building.free()
	game_data.free()
