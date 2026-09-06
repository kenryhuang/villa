extends Node3D

## Keep the shared maintenance state, with a depth-tested label above the model.
## Flat damage overlays from the original sprite buildings do not fit 3D walls.
var state := "normal"
var remaining_seconds := 0.0
var _status: Label3D
var _completion_seconds := 0.0

func configure(visual_size: Vector2, _ground_anchor_uv: Vector2) -> bool:
	_ensure_status()
	_status.position = Vector3(0, visual_size.y + .42, 0)
	_refresh()
	return true

func set_state(next_state: String, next_remaining_seconds := 0.0) -> void:
	_ensure_status()
	if next_state != state:
		_completion_seconds = 0
	state = next_state if next_state in ["normal", "warning", "overdue", "repairing"] else "normal"
	remaining_seconds = maxf(0, next_remaining_seconds)
	_refresh()

func get_state() -> String:
	return state

func play_completion() -> void:
	_ensure_status()
	_completion_seconds = 1.2
	_refresh()

func advance_animation(delta: float) -> void:
	if _completion_seconds <= 0 or delta <= 0:
		return
	_completion_seconds = maxf(0, _completion_seconds - delta)
	_refresh()

func _process(delta: float) -> void:
	advance_animation(delta)

func _ensure_status() -> void:
	if _status != null:
		return
	_status = Label3D.new()
	_status.name = "Status"
	_status.font_size = 36
	_status.pixel_size = .005
	_status.outline_size = 6
	_status.outline_modulate = Color("302d26")
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.no_depth_test = false
	_status.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_status)

func _refresh() -> void:
	_status.text = {"normal": "维护完成" if _completion_seconds > 0 else "", "warning": "即将需要维护", "overdue": "需要维护", "repairing": "维护中"}[state]
	_status.modulate = {"normal": Color("b7dea0"), "warning": Color("efd48b"), "overdue": Color("efa07c"), "repairing": Color("b0d7e5")}[state]
	_status.visible = not _status.text.is_empty()
