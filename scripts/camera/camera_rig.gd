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
