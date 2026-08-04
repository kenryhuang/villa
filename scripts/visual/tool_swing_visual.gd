class_name ToolSwingVisual
extends Node3D

const ACTION_DURATION := 1.2
const PREPARE_END := 0.25
const STRIKE_END := 0.55
const IMPACT_END := 0.70
const TOOL_TEXTURES := {
	"axe": "res://assets/ui/action_icons/axe.png",
	"pickaxe": "res://assets/ui/action_icons/pickaxe.png",
}

var _tool_id := ""


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
	_tool_id = tool_id
	(get_node("Pivot/ToolSprite") as Sprite3D).texture = texture
	visible = true
	set_action_progress(0.0)
	return true


func set_action_progress(progress: float) -> void:
	var elapsed := clampf(progress, 0.0, 1.0) * ACTION_DURATION
	var rotation_value := 0.0
	if elapsed < PREPARE_END:
		rotation_value = lerpf(deg_to_rad(-20.0), deg_to_rad(-42.0), elapsed / PREPARE_END)
	elif elapsed < STRIKE_END:
		rotation_value = lerpf(
			deg_to_rad(-42.0),
			deg_to_rad(-112.0),
			(elapsed - PREPARE_END) / (STRIKE_END - PREPARE_END)
		)
	elif elapsed < IMPACT_END:
		rotation_value = deg_to_rad(-112.0)
	else:
		rotation_value = lerpf(
			deg_to_rad(-112.0),
			deg_to_rad(-20.0),
			(elapsed - IMPACT_END) / (ACTION_DURATION - IMPACT_END)
		)
	(get_node("Pivot") as Node3D).rotation.z = rotation_value


func get_phase_at(elapsed: float) -> String:
	if elapsed < PREPARE_END:
		return "prepare"
	if elapsed < STRIKE_END:
		return "strike"
	if elapsed < IMPACT_END:
		return "impact"
	return "recover"


func cancel_tool() -> void:
	visible = false
	_tool_id = ""


func get_tool_id() -> String:
	return _tool_id
