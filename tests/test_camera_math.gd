extends RefCounted

const CameraMath = preload("res://scripts/camera/camera_math.gd")
const CameraRigScript = preload("res://scripts/camera/camera_rig.gd")
const CameraRigScene = preload("res://scenes/camera/camera_rig.tscn")
const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")

func _has_property(object: Object, property_name: StringName) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false

func _middle_button_event(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = pressed
	return event

func _motion_event(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event

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
	var initial_yaw: float = rig.yaw
	Input.action_press("camera_right")
	rig._process(0.25)
	Input.action_release("camera_right")
	assertions.near(rig.yaw, initial_yaw, 0.0001, "camera right input keeps the fixed direction")
	Input.action_press("camera_left")
	rig._process(0.25)
	Input.action_release("camera_left")
	assertions.near(rig.yaw, initial_yaw, 0.0001, "camera left input keeps the fixed direction")

	assertions.truthy(rig.has_method("pan_delta_for"), "camera rig exposes map pan helper")
	if rig.has_method("pan_delta_for"):
		var planar_right := Vector3(1.0, 0.0, 0.0)
		var planar_forward := Vector3(0.0, 0.0, 1.0)
		var pan_delta: Vector3 = rig.call("pan_delta_for", Vector2(80.0, -40.0), 10.0, 1000.0, planar_right, planar_forward)
		assertions.near(pan_delta.distance_to(-planar_right * 0.8 - planar_forward * 0.4), 0.0, 0.0001, "map pan uses orthographic world units per pixel")
		var zero_height_delta: Vector3 = rig.call("pan_delta_for", Vector2(80.0, -40.0), 10.0, 0.0, planar_right, planar_forward)
		assertions.near(zero_height_delta.distance_to(-planar_right * 800.0 - planar_forward * 400.0), 0.0, 0.0001, "map pan protects against zero viewport height")

	assertions.truthy(_has_property(rig, &"pan_offset"), "camera rig stores map pan offset")
	if _has_property(rig, &"pan_offset") and rig.has_method("pan_delta_for"):
		var drag_yaw: float = rig.yaw
		var drag_relative := Vector2(80.0, -40.0)
		var viewport_height := rig.get_viewport().get_visible_rect().size.y
		var expected_drag_delta: Vector3 = rig.call("pan_delta_for", drag_relative, rig.orthographic_size, viewport_height, rig.get_planar_right(), rig.get_planar_forward())
		rig._unhandled_input(_middle_button_event(true))
		rig._unhandled_input(_motion_event(drag_relative))
		assertions.near(rig.yaw, drag_yaw, 0.0001, "middle drag keeps the fixed direction")
		assertions.near((rig.get("pan_offset") as Vector3).distance_to(expected_drag_delta), 0.0, 0.0001, "middle drag pans the map")
		rig._unhandled_input(_middle_button_event(false))
		var released_offset: Vector3 = rig.get("pan_offset")
		rig._unhandled_input(_motion_event(Vector2(20.0, 20.0)))
		assertions.near((rig.get("pan_offset") as Vector3).distance_to(released_offset), 0.0, 0.0001, "released middle drag no longer pans the map")

	if _has_property(rig, &"pan_offset"):
		var follow_target := Node3D.new()
		scene_tree.root.add_child(follow_target)
		rig.set("pan_offset", Vector3(2.0, 0.0, -3.0))
		follow_target.global_position = Vector3(9.0, 0.0, 4.0)
		rig.set_target(follow_target)
		assertions.near(rig.global_position.distance_to(follow_target.global_position + rig.get("pan_offset")), 0.0, 0.0001, "set target includes existing map pan offset")
		follow_target.global_position = Vector3(12.0, 0.0, 5.0)
		rig._process(10.0)
		assertions.near(rig.global_position.distance_to(follow_target.global_position + rig.get("pan_offset")), 0.0, 0.0001, "target follow includes map pan offset")
		follow_target.free()

	var original_size: float = rig.orthographic_size
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	rig._unhandled_input(wheel_up)
	assertions.near(rig.orthographic_size, CameraMath.clamp_size(original_size - 0.6), 0.0001, "wheel up keeps the zoom step and clamp")
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	rig._unhandled_input(wheel_down)
	assertions.near(rig.orthographic_size, CameraMath.clamp_size(original_size), 0.0001, "wheel down keeps the zoom step and clamp")
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
