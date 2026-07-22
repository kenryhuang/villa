class_name CameraRig
extends Node3D

const CameraMathScript = preload("res://scripts/camera/camera_math.gd")

@onready var camera: Camera3D = $Camera3D

var target: Node3D
var yaw := -PI / 4.0
var orthographic_size := CameraMathScript.DEFAULT_SIZE
var dragging := false

const ORBIT_DISTANCE := 10.0
const ORBIT_HEIGHT := 8.8
const KEY_ROTATION_SPEED := 1.6
const DRAG_SENSITIVITY := 0.008
const CAMERA_OCCLUDER_MASK := 32
const MAX_OCCLUDERS := 8

static func apply_occlusion_state(trees: Array[Node], occluded: Array[Node]) -> void:
	for tree in trees:
		if is_instance_valid(tree) and tree.has_method("set_camera_occluded"):
			tree.set_camera_occluded(tree in occluded)

func _ready() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	_apply_camera_transform()

func set_target(value: Node3D) -> void:
	target = value
	if target:
		global_position = target.global_position

func get_planar_forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw)).normalized()

func get_planar_right() -> Vector3:
	return get_planar_forward().cross(Vector3.UP).normalized()

func _process(delta: float) -> void:
	var rotation_axis := Input.get_axis("camera_left", "camera_right")
	if not is_zero_approx(rotation_axis):
		yaw += rotation_axis * KEY_ROTATION_SPEED * delta
	if target:
		global_position = global_position.lerp(target.global_position, 1.0 - exp(-8.0 * delta))
	_apply_camera_transform()
	update_tree_occlusion()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orthographic_size = CameraMathScript.clamp_size(orthographic_size - 0.6)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orthographic_size = CameraMathScript.clamp_size(orthographic_size + 0.6)
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * DRAG_SENSITIVITY

func _apply_camera_transform() -> void:
	var offset := Vector3(sin(yaw) * ORBIT_DISTANCE, ORBIT_HEIGHT, cos(yaw) * ORBIT_DISTANCE)
	camera.position = offset
	camera.size = orthographic_size
	camera.look_at(global_position, Vector3.UP)

func update_tree_occlusion() -> void:
	if not is_inside_tree():
		return
	var trees: Array[Node] = get_tree().get_nodes_in_group("tree_instance")
	var occluded: Array[Node] = []
	if not is_instance_valid(target):
		apply_occlusion_state(trees, occluded)
		return

	var excluded: Array[RID] = []
	var ray_start := camera.global_position
	var ray_end := target.global_position + Vector3.UP * 0.55
	for _index in MAX_OCCLUDERS:
		var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end, CAMERA_OCCLUDER_MASK, excluded)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var collider = hit.get("collider")
		if not collider is Area3D:
			break
		excluded.append(collider.get_rid())
		var tree := collider.get_parent() as Node
		if is_instance_valid(tree) and tree not in occluded:
			occluded.append(tree)
	apply_occlusion_state(trees, occluded)
