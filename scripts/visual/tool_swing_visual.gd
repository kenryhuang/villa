class_name ToolSwingVisual
extends Node3D

const ACTION_DURATION := 1.2
const PREPARE_END := 0.25
const STRIKE_END := 0.55
const IMPACT_END := 0.70
const AXE_ACTION_DURATION := 3.0
const AXE_SWING_CYCLE := 0.72
const AXE_PREPARE_END := 0.10
const AXE_STRIKE_END := 0.24
const AXE_IMPACT_END := 0.34
const CANCEL_RECOVERY_DURATION := 0.14
const TOOL_TEXTURES := {
	"axe": "res://assets/ui/action_icons/axe.png",
	"pickaxe": "res://assets/ui/action_icons/pickaxe.png",
}

var _tool_id := ""
var _cancel_tween: Tween


func _init() -> void:
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	var sprite := Sprite3D.new()
	sprite.name = "ToolSprite"
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.pixel_size = 0.0035
	# The handle end stays at Pivot; the painted tool extends upward from it.
	sprite.position = Vector3(0.0, 0.38, 0.0)
	pivot.add_child(sprite)
	visible = false


func play_tool(tool_id: String) -> bool:
	if not TOOL_TEXTURES.has(tool_id):
		return false
	var texture := load(str(TOOL_TEXTURES[tool_id])) as Texture2D
	if texture == null:
		return false
	if _cancel_tween != null and _cancel_tween.is_valid():
		_cancel_tween.kill()
	_tool_id = tool_id
	(get_node("Pivot/ToolSprite") as Sprite3D).texture = texture
	visible = true
	set_action_progress(0.0)
	return true


func set_action_progress(progress: float) -> void:
	var elapsed := clampf(progress, 0.0, 1.0) * ACTION_DURATION
	var prepare_end := PREPARE_END
	var strike_end := STRIKE_END
	var impact_end := IMPACT_END
	var cycle_duration := ACTION_DURATION
	if _tool_id == "axe":
		elapsed = fmod(clampf(progress, 0.0, 1.0) * AXE_ACTION_DURATION, AXE_SWING_CYCLE)
		prepare_end = AXE_PREPARE_END
		strike_end = AXE_STRIKE_END
		impact_end = AXE_IMPACT_END
		cycle_duration = AXE_SWING_CYCLE
	var rotation_value := 0.0
	if elapsed < prepare_end:
		rotation_value = lerpf(deg_to_rad(-20.0), deg_to_rad(-42.0), elapsed / prepare_end)
	elif elapsed < strike_end:
		rotation_value = lerpf(
			deg_to_rad(-42.0),
			deg_to_rad(-112.0),
			(elapsed - prepare_end) / (strike_end - prepare_end)
		)
	elif elapsed < impact_end:
		rotation_value = deg_to_rad(-112.0)
	else:
		rotation_value = lerpf(
			deg_to_rad(-112.0),
			deg_to_rad(-20.0),
			(elapsed - impact_end) / (cycle_duration - impact_end)
		)
	(get_node("Pivot") as Node3D).rotation.z = rotation_value


func get_phase_at(elapsed: float) -> String:
	var phase_elapsed := maxf(elapsed, 0.0)
	var prepare_end := PREPARE_END
	var strike_end := STRIKE_END
	var impact_end := IMPACT_END
	if _tool_id == "axe":
		phase_elapsed = fmod(phase_elapsed, AXE_SWING_CYCLE)
		prepare_end = AXE_PREPARE_END
		strike_end = AXE_STRIKE_END
		impact_end = AXE_IMPACT_END
	if phase_elapsed < prepare_end:
		return "prepare"
	if phase_elapsed < strike_end:
		return "strike"
	if phase_elapsed < impact_end:
		return "impact"
	return "recover"


func cancel_tool() -> void:
	if not visible:
		_tool_id = ""
		return
	if not is_inside_tree():
		_finish_cancel()
		return
	if _cancel_tween != null and _cancel_tween.is_valid():
		_cancel_tween.kill()
	_cancel_tween = create_tween()
	_cancel_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_cancel_tween.tween_property(
		get_node("Pivot"), "rotation:z", deg_to_rad(-20.0), CANCEL_RECOVERY_DURATION
	)
	_cancel_tween.tween_callback(_finish_cancel)


func get_cancel_recovery_duration() -> float:
	return CANCEL_RECOVERY_DURATION


func _finish_cancel() -> void:
	visible = false
	_tool_id = ""


func get_tool_id() -> String:
	return _tool_id
