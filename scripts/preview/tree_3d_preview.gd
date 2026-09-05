extends Node3D

const CAPTURE_WAIT_FRAMES := 8
const TARGET := Vector3(0.0, 2.7, 0.0)
const DEFAULT_CAMERA_POSITION := Vector3(8.0, 5.0, 11.0)
const MIN_DISTANCE := 5.4
const MAX_DISTANCE := 19.0
const TURN_SPEED := 0.22

@onready var camera: Camera3D = $Camera3D

var yaw := 0.0
var pitch := 0.0
var distance := 1.0
var turntable_enabled := false
var capture_path := ""

func _ready() -> void:
	get_window().content_scale_size = Vector2i(1440, 1000)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_reset_camera()
	_apply_requested_view()
	capture_path = _capture_argument()
	if not capture_path.is_empty():
		_capture_after_frames()

func _process(delta: float) -> void:
	if turntable_enabled:
		yaw += TURN_SPEED * delta
		_update_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(MIN_DISTANCE, distance - 0.7)
			_update_camera()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(MAX_DISTANCE, distance + 0.7)
			_update_camera()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch - event.relative.y * 0.005, deg_to_rad(2.0), deg_to_rad(36.0))
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				turntable_enabled = not turntable_enabled
			KEY_1:
				_set_view(0.0)
			KEY_2:
				_set_view(deg_to_rad(90.0))
			KEY_3:
				_set_view(PI)
			KEY_R:
				_reset_camera()
			KEY_F12:
				await _save_screenshot("user://tree_3d_preview.png")
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _reset_camera() -> void:
	var offset := DEFAULT_CAMERA_POSITION - TARGET
	distance = offset.length()
	yaw = atan2(offset.x, offset.z)
	pitch = asin(offset.y / distance)
	turntable_enabled = false
	_update_camera()

func _set_view(view_yaw: float) -> void:
	yaw = view_yaw
	pitch = deg_to_rad(10.5)
	distance = DEFAULT_CAMERA_POSITION.distance_to(TARGET)
	turntable_enabled = false
	_update_camera()

func _update_camera() -> void:
	var horizontal := cos(pitch) * distance
	camera.global_position = TARGET + Vector3(sin(yaw) * horizontal, sin(pitch) * distance, cos(yaw) * horizontal)
	camera.look_at(TARGET, Vector3.UP)

func _apply_requested_view() -> void:
	for argument in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument == "--view=front":
			_set_view(0.0)
		elif argument == "--view=side":
			_set_view(deg_to_rad(90.0))
		elif argument == "--view=back":
			_set_view(PI)
		elif argument == "--view=detail":
			_set_view(deg_to_rad(28.0))
			distance = MIN_DISTANCE
			pitch = deg_to_rad(13.0)
			_update_camera()

func _capture_argument() -> String:
	for argument in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--capture-preview="):
			return argument.trim_prefix("--capture-preview=")
	return ""

func _capture_after_frames() -> void:
	for _frame in CAPTURE_WAIT_FRAMES:
		await get_tree().process_frame
	var result := await _save_screenshot(capture_path)
	get_tree().quit(0 if result == OK else 1)

func _save_screenshot(path: String) -> Error:
	if DisplayServer.get_name() == "headless":
		push_error("Tree preview screenshots require a GPU-backed display server.")
		return ERR_UNAVAILABLE
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.is_empty():
		push_error("Tree preview viewport did not produce an image.")
		return ERR_CANT_ACQUIRE_RESOURCE
	var result := image.save_png(path)
	if result != OK:
		push_error("Unable to save tree preview screenshot: %s" % path)
	return result
