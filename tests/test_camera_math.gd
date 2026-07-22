extends RefCounted

const CameraMath = preload("res://scripts/camera/camera_math.gd")
const CameraRigScript = preload("res://scripts/camera/camera_rig.gd")
const CameraRigScene = preload("res://scenes/camera/camera_rig.tscn")
const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")

func run(assertions) -> void:
	assertions.near(CameraMath.DEFAULT_SIZE, 10.0, 0.001, "camera uses larger default map view")
	assertions.near(CameraMath.clamp_size(2.0), 5.0, 0.001, "camera enforces minimum zoom")
	assertions.near(CameraMath.clamp_size(20.0), 12.0, 0.001, "camera enforces maximum zoom")
	assertions.near(CameraMath.clamp_size(8.0), 8.0, 0.001, "camera preserves in-range zoom")
	var rig = CameraRigScene.instantiate()
	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.add_child(rig)
	assertions.near(rig.orthographic_size, CameraMath.DEFAULT_SIZE, 0.001, "camera rig starts at default map view")
	rig.global_position = Vector3.ZERO
	rig._apply_camera_transform()
	var center_direction: Vector3 = -rig.camera.global_basis.z
	rig.global_position = Vector3(17.0, 0.0, 13.0)
	rig._apply_camera_transform()
	var edge_direction: Vector3 = -rig.camera.global_basis.z
	assertions.near(center_direction.distance_to(edge_direction), 0.0, 0.0001, "camera translation does not rotate view")
	rig.free()

	var tree_a = TreeInstanceScript.new()
	var tree_b = TreeInstanceScript.new()
	var trees: Array[Node] = [tree_a, tree_b]
	var no_occluders: Array[Node] = []
	var tree_a_occludes: Array[Node] = [tree_a]
	tree_a.set_camera_occluded(true)
	tree_b.set_camera_occluded(true)
	CameraRigScript.apply_occlusion_state(trees, no_occluders)
	assertions.near(tree_a.occlusion_target, 1.0, 0.001, "clear tree A restores opacity")
	assertions.near(tree_b.occlusion_target, 1.0, 0.001, "clear tree B restores opacity")
	CameraRigScript.apply_occlusion_state(trees, tree_a_occludes)
	assertions.near(tree_a.occlusion_target, 0.3, 0.001, "occluding tree fades")
	assertions.near(tree_b.occlusion_target, 1.0, 0.001, "non-occluding tree remains clear")
	tree_a.free()
	tree_b.free()
