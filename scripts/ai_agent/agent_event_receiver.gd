extends Node

# Transport only. This node may receive events during a modal pause; it must not
# advance the simulation or invoke the action engine until the game resumes.
var runtime: Node
var _cursor := 0
var _epoch := -1
var _session := ""
var _polling := false
var _poll_at := 0

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if not is_instance_valid(runtime) or not runtime.service_enabled: return
	if _epoch != runtime.gateway.session_epoch or _session != runtime.session_id:
		_epoch = runtime.gateway.session_epoch
		_session = runtime.session_id
		_cursor = 0
		_polling = false
		_poll_at = 0
	if _polling or Time.get_ticks_msec() < _poll_at: return
	_poll_at = Time.get_ticks_msec() + 2000
	_polling = true
	var epoch := _epoch
	var scope := _session
	var started: bool = runtime.gateway.poll_agent_events({"session_id":scope,"session_epoch":epoch,"cursor":_cursor}, func(ok: bool, result: Dictionary, _error: String):
		if runtime.gateway.session_epoch != epoch or runtime.session_id != scope: return
		_polling = false
		if not ok: return
		for event in result.get("events", []):
			var actor := str(event.agent_id)
			if not runtime.registry.is_agent_managed(actor): continue
			runtime.scheduler.event_queue.enqueue(actor, "dialogue", int(event.game_minute), str(event.source), str(event.event_id))
		_cursor = int(result.get("next_cursor", _cursor))
		if not get_tree().paused: runtime.scheduler.pump(runtime._absolute_game_minute())
	)
	if not started: _polling = false
