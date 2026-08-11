class_name BuildingMaintenanceVisual
extends Node3D

const ConstructionFeedbackScript = preload("res://scripts/buildings/construction_feedback.gd")
const WARNING_TEXTURE_PATH := "res://assets/buildings/maintenance/maintenance_warning.svg"
const BROKEN_TEXTURE_PATH := "res://assets/buildings/maintenance/maintenance_broken.svg"
const TEXTURE_SIZE := 512.0

var state := "normal"
var remaining_seconds := 0.0
var _completion_tween: Tween


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(visual_size: Vector2, ground_anchor_uv: Vector2) -> bool:
	_ensure_nodes()
	var warning := get_node("WarningOverlay") as Sprite3D
	var broken := get_node("BrokenOverlay") as Sprite3D
	warning.texture = load(WARNING_TEXTURE_PATH) as Texture2D
	broken.texture = load(BROKEN_TEXTURE_PATH) as Texture2D
	if warning.texture == null or broken.texture == null:
		return false
	var pixel_size := visual_size.x / TEXTURE_SIZE
	var vertical_scale := visual_size.y / maxf(visual_size.x, 0.001)
	var center_y := (clampf(ground_anchor_uv.y, 0.0, 1.0) - 0.5) * visual_size.y
	for overlay in [warning, broken]:
		overlay.pixel_size = pixel_size
		overlay.scale = Vector3(1.0, vertical_scale, 1.0)
		overlay.position = Vector3(0.0, center_y, 0.18)
	var feedback := get_node("RepairFeedback") as ConstructionFeedback
	feedback.configure(visual_size)
	set_state(state, remaining_seconds)
	return true


func set_state(next_state: String, next_remaining_seconds: float = 0.0) -> void:
	_ensure_nodes()
	state = next_state if next_state in ["normal", "warning", "overdue", "repairing"] else "normal"
	remaining_seconds = maxf(0.0, next_remaining_seconds)
	var warning := get_node("WarningOverlay") as Sprite3D
	var broken := get_node("BrokenOverlay") as Sprite3D
	warning.modulate.a = 1.0
	broken.modulate.a = 1.0
	warning.visible = state == "warning"
	broken.visible = state in ["overdue", "repairing"]
	var feedback := get_node("RepairFeedback") as ConstructionFeedback
	feedback.update_state(0.0, false, false, state == "repairing")
	var progress := feedback.get_node_or_null("Progress") as Sprite3D
	if progress != null:
		progress.visible = false


func get_state() -> String:
	return state


func advance_animation(delta: float) -> void:
	if delta <= 0.0 or state != "repairing":
		return
	var feedback := get_node("RepairFeedback") as ConstructionFeedback
	feedback.advance_animation(delta)
	var progress := feedback.get_node_or_null("Progress") as Sprite3D
	if progress != null:
		progress.visible = false


func play_completion() -> void:
	_ensure_nodes()
	if _completion_tween != null:
		_completion_tween.kill()
	var broken := get_node("BrokenOverlay") as Sprite3D
	broken.visible = true
	broken.modulate.a = 1.0
	_completion_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_completion_tween.tween_property(broken, "modulate:a", 0.0, 0.35)
	_completion_tween.tween_callback(func() -> void: broken.visible = false)


func _process(delta: float) -> void:
	advance_animation(delta)


func _ensure_nodes() -> void:
	if get_node_or_null("WarningOverlay") == null:
		var warning := Sprite3D.new()
		warning.name = "WarningOverlay"
		add_child(warning)
		_configure_sprite(warning, 0.55)
	if get_node_or_null("BrokenOverlay") == null:
		var broken := Sprite3D.new()
		broken.name = "BrokenOverlay"
		add_child(broken)
		_configure_sprite(broken, 0.6)
	if get_node_or_null("RepairFeedback") == null:
		var feedback := ConstructionFeedbackScript.new() as ConstructionFeedback
		feedback.name = "RepairFeedback"
		feedback.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(feedback)


func _configure_sprite(sprite: Sprite3D, sorting_offset: float) -> void:
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.sorting_offset = sorting_offset
