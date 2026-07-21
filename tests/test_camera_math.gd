extends RefCounted

const CameraMath = preload("res://scripts/camera/camera_math.gd")
const CameraRigScene = preload("res://scenes/camera/camera_rig.tscn")

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
