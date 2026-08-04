class_name GatheringController
extends Node

signal state_changed(state: int, context: Dictionary)
signal gather_started(target: Node, preview: Dictionary)
signal gather_progress(target: Node, progress: float)
signal gather_completed(target: Node, result: Dictionary)
signal gather_failed(target: Node, reason: String)
signal gather_cancelled(reason: String)

enum State {
	IDLE,
	PREFLIGHT,
	PATHFINDING,
	MOVING,
	ARRIVAL_RECHECK,
	ACTING,
	COMMITTING,
	COMPLETED,
	CANCELLED,
	FAILED,
}

@export var action_duration := 1.2

var _state: State = State.IDLE
var _player
var _pathfinder
var _tools
var _season
var _target: Node
var _preview: Dictionary = {}
var _action_elapsed := 0.0
var _path_retry_used := false
var _clock_locked := false
var _request_token := 0


func configure(player, pathfinder, tools, season) -> bool:
	if (
		player == null
		or pathfinder == null
		or tools == null
		or season == null
		or not player.has_method("start_auto_path")
		or not player.has_method("stop_auto_movement")
		or not pathfinder.has_method("find_path_to_interaction")
		or not tools.has_method("preview_gather_unit")
		or not tools.has_method("commit_gather_unit")
		or not tools.has_method("switch_tool_by_id")
		or not season.has_method("acquire_action_clock_lock")
		or not season.has_method("release_action_clock_lock")
	):
		return false
	_disconnect_player_signals()
	_player = player
	_pathfinder = pathfinder
	_tools = tools
	_season = season
	_connect_player_signals()
	return true


func request_gather(target: Node) -> bool:
	if _player == null or target == null or not is_instance_valid(target):
		return false
	if _state != State.IDLE:
		cancel_current("replaced")
	_request_token += 1
	_target = target
	_path_retry_used = false
	_set_state(State.PREFLIGHT)
	_preview = _tools.call("preview_gather_unit", target)
	if not bool(_preview.get("allowed", false)):
		_fail(str(_preview.get("reason", "invalid_target")))
		return false
	if not bool(_tools.call("switch_tool_by_id", str(_preview.get("tool_id", "")))):
		_fail("invalid_tool")
		return false
	gather_started.emit(target, _preview.duplicate(true))
	return _start_path()


func cancel_current(reason: String) -> void:
	if _state == State.IDLE:
		return
	_request_token += 1
	var safe_reason := reason if not reason.is_empty() else "cancelled"
	if _player != null and _player.has_method("stop_auto_movement"):
		_player.call("stop_auto_movement", safe_reason)
	_release_clock()
	_set_state(State.CANCELLED, {"reason": safe_reason})
	gather_cancelled.emit(safe_reason)
	_clear_command()
	_set_state(State.IDLE)


func get_state_name() -> String:
	return State.keys()[int(_state)]


func _process(delta: float) -> void:
	if _state != State.ACTING:
		return
	if _target == null or not is_instance_valid(_target):
		_fail("target_invalid")
		return
	_action_elapsed = minf(action_duration, _action_elapsed + maxf(0.0, delta))
	var progress := 1.0 if action_duration <= 0.0 else clampf(_action_elapsed / action_duration, 0.0, 1.0)
	gather_progress.emit(_target, progress)
	if progress < 1.0:
		return
	_commit_action()


func _start_path() -> bool:
	if _target == null or not is_instance_valid(_target):
		_fail("target_invalid")
		return false
	_set_state(State.PATHFINDING)
	var range := float(_player.get("interaction_range")) if _has_property(_player, "interaction_range") else 2.5
	var path: Array[Vector3] = _pathfinder.call(
		"find_path_to_interaction",
		_player_position(),
		_target,
		range
	)
	if path.is_empty() or not bool(_player.call("start_auto_path", path)):
		_fail("unreachable")
		return false
	_set_state(State.MOVING)
	return true


func _on_auto_path_finished() -> void:
	if _state != State.MOVING:
		return
	_set_state(State.ARRIVAL_RECHECK)
	if _target == null or not is_instance_valid(_target):
		_fail("target_invalid")
		return
	_preview = _tools.call("preview_gather_unit", _target)
	if not bool(_preview.get("allowed", false)):
		_fail(str(_preview.get("reason", "target_changed")))
		return
	if not bool(_season.call("acquire_action_clock_lock", self)):
		_fail("clock_unavailable")
		return
	_clock_locked = true
	_action_elapsed = 0.0
	_set_state(State.ACTING)
	gather_progress.emit(_target, 0.0)


func _on_auto_path_blocked() -> void:
	if _state != State.MOVING:
		return
	if _path_retry_used:
		_fail("unreachable")
		return
	_path_retry_used = true
	_start_path()


func _on_manual_movement_requested() -> void:
	cancel_current("manual_input")


func _commit_action() -> void:
	_set_state(State.COMMITTING)
	var result: Dictionary = _tools.call("commit_gather_unit", _target)
	if not bool(result.get("allowed", false)):
		_fail(str(result.get("reason", "commit_failed")))
		return
	if _season.has_method("advance_game_minutes"):
		_season.call("advance_game_minutes", 10)
	_release_clock()
	_set_state(State.COMPLETED)
	gather_completed.emit(_target, result.duplicate(true))
	if _player != null:
		_player.call("stop_auto_movement", "completed")
	_clear_command()
	_set_state(State.IDLE)


func _fail(reason: String) -> void:
	var failed_target := _target
	if _player != null and _player.has_method("stop_auto_movement"):
		_player.call("stop_auto_movement", reason)
	_release_clock()
	_set_state(State.FAILED, {"reason": reason})
	gather_failed.emit(failed_target, reason)
	_clear_command()
	_set_state(State.IDLE)


func _release_clock() -> void:
	if not _clock_locked or _season == null:
		return
	_season.call("release_action_clock_lock", self)
	_clock_locked = false


func _clear_command() -> void:
	_target = null
	_preview.clear()
	_action_elapsed = 0.0
	_path_retry_used = false


func _set_state(next_state: State, extra: Dictionary = {}) -> void:
	_state = next_state
	var context := extra.duplicate(true)
	context["target"] = _target
	context["token"] = _request_token
	state_changed.emit(int(_state), context)


func _player_position() -> Vector3:
	if not _player is Node3D:
		return Vector3.ZERO
	return _player.global_position if _player.is_inside_tree() else _player.position


func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _connect_player_signals() -> void:
	for binding in [
		["manual_movement_requested", Callable(self, "_on_manual_movement_requested")],
		["auto_path_finished", Callable(self, "_on_auto_path_finished")],
		["auto_path_blocked", Callable(self, "_on_auto_path_blocked")],
	]:
		if _player.has_signal(binding[0]) and not _player.is_connected(binding[0], binding[1]):
			_player.connect(binding[0], binding[1])


func _disconnect_player_signals() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	for binding in [
		["manual_movement_requested", Callable(self, "_on_manual_movement_requested")],
		["auto_path_finished", Callable(self, "_on_auto_path_finished")],
		["auto_path_blocked", Callable(self, "_on_auto_path_blocked")],
	]:
		if _player.has_signal(binding[0]) and _player.is_connected(binding[0], binding[1]):
			_player.disconnect(binding[0], binding[1])


func _exit_tree() -> void:
	_release_clock()
	_disconnect_player_signals()
