extends Node3D

const CAPTURE_WAIT_FRAMES := 8

@onready var player: FarmPreviewPlayer = $Player
@onready var camera_rig: Node3D = $CameraRig
@onready var pitch: Node3D = $CameraRig/Pitch
@onready var follow_camera: Camera3D = $CameraRig/Pitch/SpringArm3D/Camera3D
@onready var overview_camera: Camera3D = $OverviewCamera

var yaw := deg_to_rad(28.0)
var pitch_angle := deg_to_rad(-18.0)
var overview_enabled := false
var _capture_path := ""

func _ready() -> void:
	get_window().content_scale_size = Vector2i(1440, 960)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_apply_camera_rotation()
	overview_camera.look_at(Vector3(0.0, 1.0, -2.0), Vector3.UP)
	$CameraRig/Pitch/SpringArm3D.add_excluded_object(player.get_rid())
	_capture_path = _capture_argument()
	if (OS.get_cmdline_args() + OS.get_cmdline_user_args()).has("--capture-overview"):
		set_overview(true)
	if not _capture_path.is_empty():
		_capture_after_frames()

func _process(_delta: float) -> void:
	if not overview_enabled:
		camera_rig.global_position = player.global_position + Vector3.UP * 1.2
		player.camera_yaw = yaw
	else:
		player.camera_yaw = overview_camera.rotation.y

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			$CameraRig/Pitch/SpringArm3D.spring_length = clampf($CameraRig/Pitch/SpringArm3D.spring_length - 0.7, 3.0, 10.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			$CameraRig/Pitch/SpringArm3D.spring_length = clampf($CameraRig/Pitch/SpringArm3D.spring_length + 0.7, 3.0, 10.0)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not overview_enabled:
		yaw -= event.relative.x * 0.006
		pitch_angle = clampf(pitch_angle - event.relative.y * 0.005, deg_to_rad(-62.0), deg_to_rad(18.0))
		_apply_camera_rotation()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			set_overview(not overview_enabled)
		elif event.keycode == KEY_R:
			player.reset_position()
		elif event.keycode == KEY_F12:
			await _save_screenshot("user://farm_3d_preview.png")
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_overview(enabled: bool) -> void:
	overview_enabled = enabled
	overview_camera.current = enabled
	follow_camera.current = not enabled
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _apply_camera_rotation() -> void:
	camera_rig.rotation.y = yaw
	pitch.rotation.x = pitch_angle

func _capture_argument() -> String:
	for argument in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--capture-preview="):
			return argument.trim_prefix("--capture-preview=")
	return ""

func _capture_after_frames() -> void:
	for frame in CAPTURE_WAIT_FRAMES:
		await get_tree().process_frame
	var result := await _save_screenshot(_capture_path)
	get_tree().quit(0 if result == OK else 1)

func _save_screenshot(path: String) -> Error:
	if DisplayServer.get_name() == "headless":
		push_warning("Preview screenshot skipped because Godot is running headless.")
		return ERR_UNAVAILABLE
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(path)
	if result != OK:
		push_error("Unable to save preview screenshot: %s" % path)
	return result
