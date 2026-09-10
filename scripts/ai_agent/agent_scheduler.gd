extends RefCounted

var _registry: Variant
var _gateway: Variant
var _build_request: Callable
var _handle_response: Callable
var _handle_stream_event: Callable
var _handle_failure: Callable
var _in_flight: Dictionary = {}
var _dialogue_in_flight: Dictionary = {}
var _pending: Dictionary = {}
var _last_dispatched: Dictionary = {}
var _decision_interval_overrides: Dictionary = {}
var _current_minute := 0
var max_daily_requests := 0
var max_concurrent_requests := 0
var max_concurrent_dialogue_requests := 1
var max_daily_dialogue_requests := 0
var budget_day := -1
var budget_calls := 0
var dialogue_budget_calls := 0
var _rotation := 0

const MAX_DEBUG_INTERVAL_HOURS := 168


func configure(
	registry: Variant,
	gateway: Variant,
	build_request: Callable,
	handle_response: Callable,
	handle_stream_event: Callable = Callable(),
	handle_failure: Callable = Callable()
) -> bool:
	if registry == null or gateway == null or not build_request.is_valid() or not handle_response.is_valid():
		return false
	_registry = registry
	_gateway = gateway
	_build_request = build_request
	_handle_response = handle_response
	_handle_stream_event = handle_stream_event
	_handle_failure = handle_failure
	_decision_interval_overrides.clear()
	return true


func advance_to(game_minute: int) -> int:
	_reset_daily_budget(game_minute)
	if game_minute < _current_minute:
		_last_dispatched.clear()
	_current_minute = game_minute
	var dispatched := 0
	for actor in _pending.keys():
		if is_in_flight(actor): continue
		var pending: Dictionary = _pending[actor]
		if _dispatch(actor, pending.trigger, game_minute, pending.dialogue):
			_pending.erase(actor); dispatched += 1
	var ids: Array = _registry.call("get_agent_ids")
	if not ids.is_empty():
		_rotation = (_rotation + 1) % ids.size()
		ids = ids.slice(_rotation) + ids.slice(0, _rotation)
	for agent_id_value in ids:
		var agent_id := str(agent_id_value)
		var interval_hours := get_decision_interval_hours(agent_id)
		if interval_hours <= 0:
			continue
		var interval := interval_hours * 60
		var last := int(_last_dispatched.get(agent_id, 0))
		if game_minute - last < interval:
			continue
		var trigger := "catch_up" if game_minute - last > interval else "schedule"
		if _dispatch(agent_id, trigger, game_minute, ""):
			dispatched += 1
	return dispatched


func notify_event(agent_id: String, priority: int, game_minute: int) -> bool:
	if priority < 2:
		return false
	return _queue_or_dispatch(agent_id, "event", game_minute, "", priority)


func trigger_dialogue(agent_id: String, text: String, game_minute: int) -> bool:
	if text.length() > 1000 or not _registry.call("is_agent_managed", agent_id):
		return false
	return _queue_or_dispatch(agent_id, "dialogue", game_minute, text, 100)


func is_in_flight(agent_id: String) -> bool:
	return _in_flight.has(agent_id)


func get_in_flight_request_id(agent_id: String) -> String:
	return str(_in_flight.get(agent_id, ""))


func background_in_flight_count() -> int:
	return _in_flight.size() - _dialogue_in_flight.size()


func dialogue_in_flight_count() -> int:
	return _dialogue_in_flight.size()


func _has_capacity(trigger: String, replacing_agent: String = "") -> bool:
	if trigger == "dialogue":
		var count := dialogue_in_flight_count() - (1 if _dialogue_in_flight.has(replacing_agent) else 0)
		return max_concurrent_dialogue_requests <= 0 or count < max_concurrent_dialogue_requests
	return max_concurrent_requests <= 0 or background_in_flight_count() < max_concurrent_requests


func _reset_daily_budget(game_minute: int) -> void:
	var day := game_minute / 1080
	if day > budget_day:
		budget_day = day
		budget_calls = 0
		dialogue_budget_calls = 0


func _has_budget(trigger: String) -> bool:
	if trigger == "dialogue":
		return max_daily_dialogue_requests <= 0 or dialogue_budget_calls < max_daily_dialogue_requests
	return max_daily_requests <= 0 or budget_calls < max_daily_requests


func set_decision_interval_hours(agent_id: String, hours: int) -> bool:
	if not _registry.call("is_agent_managed", agent_id) or hours < 0 or hours > MAX_DEBUG_INTERVAL_HOURS:
		return false
	_decision_interval_overrides[agent_id] = hours
	return true


func get_decision_interval_hours(agent_id: String) -> int:
	if not _registry.call("is_agent_managed", agent_id):
		return -1
	if _decision_interval_overrides.has(agent_id):
		return int(_decision_interval_overrides[agent_id])
	var agent: Dictionary = _registry.call("get_agent", agent_id)
	var range_value: Array = agent.get("decision_interval_hours", [1, 1])
	return maxi(1, int(range_value[0]))


func _queue_or_dispatch(agent_id: String, trigger: String, game_minute: int, dialogue: String, priority: int) -> bool:
	if is_in_flight(agent_id):
		if trigger == "dialogue" and _gateway.has_method("cancel_agent"):
			_reset_daily_budget(game_minute)
			if not _has_budget(trigger) or not _has_capacity(trigger, agent_id):
				return false
			var replaced_request_id := str(_in_flight.get(agent_id, ""))
			_in_flight.erase(agent_id)
			_dialogue_in_flight.erase(agent_id)
			# Keep a coalesced world event while replacing the conversation.
			if _pending.get(agent_id, {}).get("trigger", "") == "dialogue":
				_pending.erase(agent_id)
			_gateway.call("cancel_agent", agent_id, "dialogue_replaced")
			if _handle_failure.is_valid():
				_handle_failure.call(agent_id, replaced_request_id, "dialogue_replaced")
			return _dispatch(agent_id, trigger, game_minute, dialogue)
		var current: Dictionary = _pending.get(agent_id, {})
		if priority >= int(current.get("priority", -1)):
			_pending[agent_id] = {"trigger": trigger, "game_minute": game_minute, "dialogue": dialogue, "priority": priority}
		return true
	if _dispatch(agent_id, trigger, game_minute, dialogue): return true
	# Background events are coalesced for a later fair pass. Dialogues return a
	# visible failure immediately rather than waiting for an entire game day.
	if trigger != "dialogue":
		_pending[agent_id] = {"trigger": trigger, "game_minute": game_minute, "dialogue": dialogue, "priority": priority}
	return false


func _dispatch(agent_id: String, trigger: String, game_minute: int, dialogue: String) -> bool:
	if is_in_flight(agent_id):
		return false
	_reset_daily_budget(game_minute)
	if not _has_budget(trigger) or not _has_capacity(trigger): return false
	var request: Dictionary = _build_request.call(agent_id, trigger, game_minute, dialogue)
	if request.is_empty():
		return false
	var request_id := str(request.get("request_id", ""))
	if request_id.is_empty():
		return false
	var callback := Callable(self, "_on_gateway_response").bind(agent_id, request_id)
	var event_callback := Callable(self, "_on_gateway_event").bind(agent_id, request_id)
	if not bool(_gateway.call("request_decision", agent_id, request, callback, event_callback)):
		return false
	_in_flight[agent_id] = request_id
	if trigger == "dialogue":
		_dialogue_in_flight[agent_id] = request_id
		dialogue_budget_calls += 1
	else:
		budget_calls += 1
		_last_dispatched[agent_id] = game_minute
	return true

func budget_state() -> Dictionary: return {"day": budget_day, "calls": budget_calls, "dialogue_calls": dialogue_budget_calls}
func restore_budget(value: Dictionary) -> void:
	budget_day = int(value.get("day", -1)); budget_calls = int(value.get("calls", 0))
	# Old saves counted dialogue inside calls. Keep that conservative count.
	dialogue_budget_calls = int(value.get("dialogue_calls", 0))


func _on_gateway_event(event: Dictionary, agent_id: String, request_id: String) -> void:
	if str(_in_flight.get(agent_id, "")) != request_id:
		return
	if _handle_stream_event.is_valid():
		_handle_stream_event.call(agent_id, event)


func _on_gateway_response(
	ok: bool,
	response: Dictionary,
	error: String,
	agent_id: String,
	request_id: String
) -> void:
	if str(_in_flight.get(agent_id, "")) != request_id:
		return
	_in_flight.erase(agent_id)
	var was_dialogue := _dialogue_in_flight.has(agent_id)
	_dialogue_in_flight.erase(agent_id)
	if not was_dialogue:
		_last_dispatched[agent_id] = _current_minute
	if ok:
		_handle_response.call(agent_id, response)
	elif _handle_failure.is_valid():
		_handle_failure.call(agent_id, request_id, error)
	if _pending.has(agent_id):
		var pending: Dictionary = _pending[agent_id]
		if _dispatch(agent_id, str(pending.trigger), maxi(_current_minute, int(pending.game_minute)), str(pending.dialogue)): _pending.erase(agent_id)
