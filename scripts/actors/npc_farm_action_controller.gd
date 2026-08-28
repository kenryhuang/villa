class_name NpcFarmActionController
extends Node

signal work_state_changed(state: String, record: Dictionary)

const STALL_TIMEOUT := 3.0
const PROGRESS_EPSILON := 0.02

var _farm: Variant
var _actor: Variant
var _visual: Variant
var _state := "idle"
var _current: Dictionary = {}
var _last_position := Vector3.ZERO
var _stall_elapsed := 0.0


func configure(farm: Variant, actor: Variant, visual: Variant = null) -> bool:
	if farm == null or actor == null:
		return false
	if not farm.has_method("peek_work") or not actor.has_method("begin_agent_work"):
		return false
	_farm = farm
	_actor = actor
	_visual = visual
	var callback := Callable(self, "_on_work_available")
	if farm.has_signal("work_available") and not farm.is_connected("work_available", callback):
		farm.connect("work_available", callback)
	if _visual != null and _visual.has_signal("finished"):
		var visual_callback := Callable(self, "_on_visual_finished")
		if not _visual.is_connected("finished", visual_callback):
			_visual.connect("finished", visual_callback)
	set_process(true)
	call_deferred("_try_start_next")
	return true


func get_work_state() -> String:
	return _state


func get_current_work() -> Dictionary:
	return _current.duplicate(true)


func resume() -> void:
	_try_start_next()


func _process(delta: float) -> void:
	if _state != "moving" or _actor == null:
		return
	if bool(_actor.call("is_agent_work_arrived")):
		_arrive()
		return
	var current_position: Vector3 = _actor.global_position
	if current_position.distance_to(_last_position) >= PROGRESS_EPSILON:
		_last_position = current_position
		_stall_elapsed = 0.0
	else:
		_stall_elapsed += delta
		if _stall_elapsed >= STALL_TIMEOUT:
			_fail_current("path_blocked")


func _on_work_available() -> void:
	call_deferred("_try_start_next")


func _try_start_next() -> void:
	if _state != "idle" or _farm == null or _actor == null:
		return
	_current = _farm.call("peek_work")
	if _current.is_empty():
		return
	var plot_index := int((_current.arguments as Dictionary).get("plot", -1))
	var cell: GridCell = _farm.call("get_plot_cell", str(_current.agent_id), plot_index)
	if cell == null:
		_fail_current("invalid_plot")
		return
	var target := cell.world_position_3d()
	target.y = _actor.global_position.y
	if not bool(_actor.call("begin_agent_work", target)):
		_fail_current("path_blocked")
		return
	_state = "moving"
	_last_position = _actor.global_position
	_stall_elapsed = 0.0
	work_state_changed.emit(_state, _current.duplicate(true))


func _arrive() -> void:
	_actor.call("stop_agent_work")
	_actor.call("face_world_point", _farm.call(
		"get_plot_cell",
		str(_current.agent_id),
		int((_current.arguments as Dictionary).get("plot", -1))
	).world_position_3d())
	if not bool(_farm.call("mark_work_started", str(_current.idempotency_key))):
		_fail_current("work_not_ready")
		return
	_state = "animating"
	work_state_changed.emit("arrived", _current.duplicate(true))
	work_state_changed.emit(_state, _current.duplicate(true))
	if _visual == null or not _visual.has_method("play") or not bool(_visual.call("play", str(_current.tool_name))):
		var timer := get_tree().create_timer(1.0)
		timer.timeout.connect(_on_visual_finished, CONNECT_ONE_SHOT)


func _on_visual_finished() -> void:
	if _state != "animating" or _farm == null:
		return
	var completed := _current.duplicate(true)
	_farm.call("complete_work", str(_current.idempotency_key))
	_state = "idle"
	_current.clear()
	work_state_changed.emit("committed", completed)
	_try_start_next()


func _fail_current(code: String) -> void:
	var failed := _current.duplicate(true)
	if _actor != null and _actor.has_method("stop_agent_work"):
		_actor.call("stop_agent_work")
	if _farm != null and not _current.is_empty():
		_farm.call("fail_work", str(_current.idempotency_key), code)
	_state = "idle"
	_current.clear()
	work_state_changed.emit("rejected", failed)
	_try_start_next()
