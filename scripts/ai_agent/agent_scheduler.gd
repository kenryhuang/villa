extends RefCounted

var _registry: Variant
var _gateway: Variant
var _build_request: Callable
var _handle_response: Callable
var _handle_stream_event: Callable
var _handle_failure: Callable
var _in_flight: Dictionary = {}
var _dialogue_in_flight: Dictionary = {}
var event_queue = preload("res://scripts/ai_agent/agent_event_queue.gd").new()
var clock_source = preload("res://scripts/ai_agent/agent_clock_source.gd").new()
var _active_events: Dictionary = {}
var _draining := false
var _retry_at: Dictionary = {}
var execution_actors: Callable
var event_admission: Callable
var _last_dispatched: Dictionary = {}
var _decision_interval_overrides: Dictionary = {}
var _current_minute := 0
var max_daily_requests := 0
var max_concurrent_requests := 3
var max_concurrent_dialogue_requests := 1
var max_daily_dialogue_requests := 0
var budget_day := -1
var budget_calls := 0
var dialogue_budget_calls := 0

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
	clock_source.publish(self,game_minute)
	return pump(game_minute)


func notify_event(agent_id: String, priority: int, game_minute: int, source := "world_event", event_id := "", kind := "system") -> bool:
	if priority < 2:
		return false
	if not can_enqueue_event(agent_id, kind, source): return false
	event_queue.enqueue(agent_id,kind,game_minute,source,event_id,priority)
	pump(game_minute)
	return true


func pump(game_minute: int) -> int:
	if _draining: return 0
	prune_events()
	_draining = true
	_current_minute = game_minute
	_reset_daily_budget(game_minute)
	var dispatched := 0
	for event in event_queue.messages.duplicate(true):
		if not _has_budget("event") or not _has_capacity("event"): break
		if is_in_flight(event.agent_id) or Time.get_ticks_msec() < int(_retry_at.get(event.agent_id, 0)): continue
		if _dispatch(event.agent_id,event.trigger,game_minute,"",event):
			event_queue.remove(event.event_id)
			dispatched += 1
	_draining = false
	return dispatched


func can_enqueue_event(actor: String, kind: String, source: String) -> bool:
	return _registry.call("is_agent_managed", actor) and (not event_admission.is_valid() or bool(event_admission.call(actor, kind, source)))

func prune_events() -> void:
	event_queue.messages = event_queue.messages.filter(func(e): return can_enqueue_event(e.agent_id, e.kind, e.source))


func queue_state() -> Dictionary:
	return {"waiting":event_queue.messages.duplicate(true),"running":_active_events.duplicate(true),"concurrency":background_in_flight_count(),"limit":max_concurrent_requests}

func snapshot_queue() -> Dictionary:
	var state: Dictionary = event_queue.snapshot(_active_events)
	state["last_dispatched"] = _last_dispatched.duplicate(true)
	return state

func restore_queue(state: Dictionary, legacy: Dictionary = {}) -> void:
	_in_flight.clear(); _dialogue_in_flight.clear(); _active_events.clear()
	_retry_at.clear()
	event_queue.restore(state)
	_last_dispatched = state.get("last_dispatched",{}).duplicate(true)
	for actor in legacy:
		if event_queue.has_actor(actor): continue
		var entry: Dictionary = legacy[actor]
		if entry.get("trigger") == "dialogue": continue
		event_queue.enqueue(actor,"system",int(entry.get("game_minute",0)),"restored_pending_event")


func trigger_dialogue(agent_id: String, text: String, game_minute: int) -> bool:
	if text.length() > 1000 or not _registry.call("is_agent_managed", agent_id):
		return false
	return _queue_or_dispatch(agent_id, "dialogue", game_minute, text)


func is_in_flight(agent_id: String) -> bool:
	return _in_flight.has(agent_id)


func get_in_flight_request_id(agent_id: String) -> String:
	return str(_in_flight.get(agent_id, ""))


func background_in_flight_count() -> int:
	var count := _in_flight.size() - _dialogue_in_flight.size()
	if execution_actors.is_valid():
		for actor in execution_actors.call():
			if not _in_flight.has(actor) or _dialogue_in_flight.has(actor): count += 1
	return count


func dialogue_in_flight_count() -> int:
	return _dialogue_in_flight.size()


func _has_capacity(trigger: String, replacing_agent: String = "") -> bool:
	if trigger == "dialogue":
		var count := dialogue_in_flight_count() - (1 if _dialogue_in_flight.has(replacing_agent) else 0)
		return max_concurrent_dialogue_requests <= 0 or count < max_concurrent_dialogue_requests
	return background_in_flight_count() < maxi(1,max_concurrent_requests)


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


func _queue_or_dispatch(agent_id: String, trigger: String, game_minute: int, dialogue: String) -> bool:
	if is_in_flight(agent_id):
		if trigger == "dialogue" and _gateway.has_method("cancel_agent"):
			_reset_daily_budget(game_minute)
			if not _has_budget(trigger) or not _has_capacity(trigger, agent_id):
				return false
			var replaced_request_id := str(_in_flight.get(agent_id, ""))
			_in_flight.erase(agent_id)
			_dialogue_in_flight.erase(agent_id)
			if _active_events.has(agent_id):
				event_queue.requeue(_active_events[agent_id])
				_active_events.erase(agent_id)
			_gateway.call("cancel_agent", agent_id, "dialogue_replaced")
			if _handle_failure.is_valid():
				_handle_failure.call(agent_id, replaced_request_id, "dialogue_replaced")
			return _dispatch(agent_id, trigger, game_minute, dialogue)
		return false
	if _dispatch(agent_id, trigger, game_minute, dialogue): return true
	return false


func _dispatch(agent_id: String, trigger: String, game_minute: int, dialogue: String, event: Dictionary = {}) -> bool:
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
	if not event.is_empty(): request["trigger_events"] = [event.duplicate(true)]
	var callback := Callable(self, "_on_gateway_response").bind(agent_id, request_id)
	var event_callback := Callable(self, "_on_gateway_event").bind(agent_id, request_id)
	# Reserve before IO: even an immediate transport callback cannot race the slot.
	_in_flight[agent_id] = request_id
	if trigger == "dialogue": _dialogue_in_flight[agent_id] = request_id
	elif not event.is_empty(): _active_events[agent_id] = event.duplicate(true)
	if trigger == "dialogue": dialogue_budget_calls += 1
	else: budget_calls += 1
	if not bool(_gateway.call("request_decision", agent_id, request, callback, event_callback)):
		var still_reserved := str(_in_flight.get(agent_id, "")) == request_id
		if still_reserved:
			_in_flight.erase(agent_id)
			_dialogue_in_flight.erase(agent_id)
			_active_events.erase(agent_id)
		if trigger == "dialogue": dialogue_budget_calls -= 1
		else: budget_calls -= 1
		_retry_at[agent_id] = Time.get_ticks_msec() + 2000
		if still_reserved and _handle_failure.is_valid(): _handle_failure.call(agent_id, request_id, "request_not_started")
		return false
	if trigger != "dialogue":
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
	_active_events.erase(agent_id)
	var was_dialogue := _dialogue_in_flight.has(agent_id)
	_dialogue_in_flight.erase(agent_id)
	if not was_dialogue:
		_last_dispatched[agent_id] = _current_minute
	# Applying a result may publish more events; finish that transaction first.
	var already_draining := _draining
	_draining = true
	if ok:
		_handle_response.call(agent_id, response)
	elif _handle_failure.is_valid():
		_handle_failure.call(agent_id, request_id, error)
	_draining = already_draining
	# Any freed slot serves the global FIFO, not just this NPC's pending request.
	pump(_current_minute)
