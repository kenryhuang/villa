extends RefCounted

var _registry: Variant
var _gateway: Variant
var _build_request: Callable
var _handle_response: Callable
var _in_flight: Dictionary = {}
var _pending: Dictionary = {}
var _last_dispatched: Dictionary = {}
var _current_minute := 0


func configure(registry: Variant, gateway: Variant, build_request: Callable, handle_response: Callable) -> bool:
	if registry == null or gateway == null or not build_request.is_valid() or not handle_response.is_valid():
		return false
	_registry = registry
	_gateway = gateway
	_build_request = build_request
	_handle_response = handle_response
	return true


func advance_to(game_minute: int) -> int:
	if game_minute < _current_minute:
		_last_dispatched.clear()
	_current_minute = game_minute
	var dispatched := 0
	for agent_id_value in _registry.call("get_agent_ids"):
		var agent_id := str(agent_id_value)
		var agent: Dictionary = _registry.call("get_agent", agent_id)
		var range_value: Array = agent.get("decision_interval_hours", [1, 1])
		var interval := maxi(60, int(range_value[0]) * 60)
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
	return bool(_in_flight.get(agent_id, false))


func _queue_or_dispatch(agent_id: String, trigger: String, game_minute: int, dialogue: String, priority: int) -> bool:
	if is_in_flight(agent_id):
		var current: Dictionary = _pending.get(agent_id, {})
		if priority >= int(current.get("priority", -1)):
			_pending[agent_id] = {"trigger": trigger, "game_minute": game_minute, "dialogue": dialogue, "priority": priority}
		return true
	return _dispatch(agent_id, trigger, game_minute, dialogue)


func _dispatch(agent_id: String, trigger: String, game_minute: int, dialogue: String) -> bool:
	if is_in_flight(agent_id):
		return false
	var request: Dictionary = _build_request.call(agent_id, trigger, game_minute, dialogue)
	if request.is_empty():
		return false
	var callback := Callable(self, "_on_gateway_response").bind(agent_id)
	if not bool(_gateway.call("request_decision", agent_id, request, callback)):
		return false
	_in_flight[agent_id] = true
	_last_dispatched[agent_id] = game_minute
	return true


func _on_gateway_response(ok: bool, response: Dictionary, _error: String, agent_id: String) -> void:
	_in_flight.erase(agent_id)
	if ok:
		_handle_response.call(agent_id, response)
	if _pending.has(agent_id):
		var pending: Dictionary = _pending[agent_id]
		_pending.erase(agent_id)
		_dispatch(agent_id, str(pending.trigger), int(pending.game_minute), str(pending.dialogue))
