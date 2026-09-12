extends Node3D

const CAPTURE_WAIT_FRAMES := 8
const FarmSessionScript = preload("res://scripts/farm3d/farm_session.gd")
const MeadowScript = preload("res://scripts/farm3d/painted_meadow.gd")
const InteractionScript = preload("res://scripts/farm3d/farm_interaction.gd")
const LandscapeScript = preload("res://scripts/farm3d/landscape.gd")
const GroundStonesScript = preload("res://scripts/farm3d/ground_stones.gd")

@onready var player: Farm3DPlayer = $Player
@onready var camera_rig: Node3D = $CameraRig
@onready var pitch: Node3D = $CameraRig/Pitch
@onready var follow_camera: Camera3D = $CameraRig/Pitch/SpringArm3D/Camera3D
@onready var overview_camera: Camera3D = $OverviewCamera

var yaw := deg_to_rad(28.0)
var pitch_angle := deg_to_rad(-18.0)
var overview_enabled := false
var _capture_path := ""
var farm_session: Node
var meadow: Node3D
var _autosave_seconds := 0.0
var _quitting := false

func _ready() -> void:
	get_window().content_scale_size = Vector2i(1440, 960)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_apply_camera_rotation()
	overview_camera.look_at(Vector3(0.0, 1.0, -2.0), Vector3.UP)
	$CameraRig/Pitch/SpringArm3D.add_excluded_object(player.get_rid())
	_capture_path = _capture_argument()
	_initialize_landscape()
	if not _initialize_gameplay():
		return
	var shrubs := preload("res://scripts/farm3d/landscape_shrubs.gd").new()
	shrubs.name = "LandscapeShrubs"
	add_child(shrubs)
	shrubs.configure(farm_session.grid)
	if (OS.get_cmdline_args() + OS.get_cmdline_user_args()).has("--capture-overview"):
		set_overview(true)
	if not _capture_path.is_empty():
		_capture_after_frames()

func _process(delta: float) -> void:
	if not overview_enabled:
		camera_rig.global_position = player.global_position + Vector3.UP * 1.2
		player.camera_yaw = yaw
	else:
		player.camera_yaw = overview_camera.rotation.y
	if farm_session != null and farm_session.auto_save:
		_autosave_seconds += delta
		if _autosave_seconds >= 15.0:
			_autosave_seconds = 0.0
			farm_session.save_game()

func _initialize_landscape() -> void:
	# Keep the authored path and fence, replace the base terrain and ground rocks.
	for mesh_node in $EnvironmentModel.find_children("*", "MeshInstance3D", true, false):
		var mesh_name: String = str(mesh_node.name).to_lower()
		if "meadow" in mesh_name or "earth" in mesh_name:
			mesh_node.hide()
	var landscape := LandscapeScript.new()
	landscape.name = "Landscape"
	add_child(landscape)
	var stones := GroundStonesScript.new()
	stones.name = "GroundStones"
	add_child(stones)
	stones.replace_environment_rocks($EnvironmentModel)
	var map_center := (Farm3DTerrainProfile.WORLD_MIN+Farm3DTerrainProfile.WORLD_MAX)*.5
	overview_camera.position = Vector3(map_center.x+190,205,map_center.y+250)
	overview_camera.fov = 50.0
	overview_camera.look_at(Vector3(map_center.x,4,map_center.y),Vector3.UP)
	follow_camera.far = 340.0
	overview_camera.far = 650.0

func _initialize_gameplay() -> bool:
	var arguments := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var scenario := ""
	for argument in arguments:
		if argument.begins_with("--living-world-scenario="): scenario = argument.trim_prefix("--living-world-scenario=")
	var transient := not scenario.is_empty() or not _capture_path.is_empty() or arguments.has("--farm-test") or DisplayServer.get_name() == "headless"
	farm_session = FarmSessionScript.new()
	farm_session.name = "FarmSession"
	farm_session.enable_agents = true
	farm_session.live_test_agents = not scenario.is_empty() and arguments.has("--living-world-live-agents")
	for argument in arguments:
		if argument.begins_with("--agent-client-config="):
			farm_session.agent_client_config_path = argument.trim_prefix("--agent-client-config=")
	farm_session.auto_restore = not transient and not arguments.has("--fresh-farm")
	farm_session.auto_save = not transient
	add_child(farm_session)
	if not farm_session.configure(player):
		farm_session.auto_save = false
		player.ui_blocked = true
		player.set_physics_process(false)
		farm_session.process_mode = Node.PROCESS_MODE_DISABLED
		var notice := AcceptDialog.new()
		notice.title = "农场存档未能载入"
		notice.dialog_text = farm_session.save_error + "\n\n存档：" + ProjectSettings.globalize_path(farm_session.save_path)
		notice.ok_button_text = "退出游戏"
		notice.confirmed.connect(func(): get_tree().quit())
		notice.canceled.connect(func(): get_tree().quit())
		add_child(notice)
		notice.popup_centered.call_deferred(Vector2i(640,180))
		return false
	meadow = MeadowScript.new()
	meadow.name = "PaintedMeadow"
	add_child(meadow)
	meadow.apply_ground_material($EnvironmentModel)
	var interaction := InteractionScript.new()
	interaction.name = "FarmInteraction"
	add_child(interaction)
	interaction.configure(farm_session, player)
	farm_session.agent_runtime.spawn_farm3d_actors()
	farm_session.living_world.bind_scene()
	if not scenario.is_empty() and not preload("res://scripts/farm3d/living_world_scenarios.gd").setup(self, scenario, not OS.get_cmdline_args().has("--script")):
		push_error("Living world scenario could not initialize: " + scenario)
		get_tree().quit(1)
		return false
	if not transient:
		get_tree().auto_accept_quit = false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if player.ui_blocked or player.golf_locked:
		return
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
			get_node("FarmInteraction").fishing.cancel()
			player.reset_position()
		elif event.keycode == KEY_F12:
			await _save_screenshot("user://farm3d.png")
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if has_node("FarmInteraction") and get_node("FarmInteraction").fishing != null:
			get_node("FarmInteraction").fishing.cancel()
		if farm_session != null and farm_session.golf != null:
			farm_session.golf.release_control()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _quitting:
			return
		_quitting = true
		if farm_session != null and farm_session.auto_save:
			get_tree().paused = true
			if is_instance_valid(farm_session.agent_runtime):
				farm_session.agent_runtime.gateway.process_mode = Node.PROCESS_MODE_ALWAYS
				farm_session.agent_runtime.gateway.cancel_all("game_closed")
			farm_session.save_game()
			if is_instance_valid(farm_session.agent_runtime):
				await farm_session.agent_runtime.flush_farm3d_memory(farm_session.save_path)
		get_tree().quit()

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
