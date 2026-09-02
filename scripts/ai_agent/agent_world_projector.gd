class_name AgentWorldProjector
extends RefCounted

const GLOBAL_EVENT_LIMIT := 64
const ACTOR_EVENT_LIMIT := 32
const KNOWN_ACTOR_EVENT_LIMIT := 12

var _agent_ids: Array[String] = []
var _actors: Dictionary = {}
var _public_world_state: Dictionary = {
	"game_day": 1,
	"absolute_game_minute": 0,
	"time_of_day": {},
	"season": 0,
	"weather": "",
	"environment_conditions": {},
	"public_hazards": {},
	"unlocked_regions": [],
	"market_summary": {},
	"public_discoveries": [],
}
var _global_public_events: Array[Dictionary] = []
var _actor_public_events: Dictionary = {}
var _inbox: Variant
var _last_sequence := 0


func configure(agent_ids: Array, actor_profiles: Array, inbox: Variant) -> bool:
	if inbox == null or not inbox.has_method("configure_agents"):
		return false
	var normalized_agents: Array[String] = []
	for value in agent_ids:
		if typeof(value) != TYPE_STRING or str(value).strip_edges().is_empty() or str(value) in normalized_agents:
			return false
		normalized_agents.append(str(value))
	var normalized_actors: Dictionary = {}
	for value in actor_profiles:
		if not value is Dictionary:
			return false
		var actor := value as Dictionary
		for field in ["actor_id", "actor_type", "display_name", "public_role", "region_id"]:
			if typeof(actor.get(field)) != TYPE_STRING or str(actor[field]).strip_edges().is_empty():
				return false
		var actor_id := str(actor.actor_id)
		if normalized_actors.has(actor_id):
			return false
		normalized_actors[actor_id] = {
			"actor_id": actor_id,
			"actor_type": str(actor.actor_type),
			"display_name": str(actor.display_name),
			"public_role": str(actor.public_role),
			"region_id": str(actor.region_id),
			"current_public_state": {
				"public_role": str(actor.public_role),
				"region_id": str(actor.region_id),
				"status": "idle",
			},
		}
	_agent_ids = normalized_agents
	_actors = normalized_actors
	_actor_public_events.clear()
	for actor_id in _actors:
		_actor_public_events[actor_id] = []
	_inbox = inbox
	return bool(_inbox.call("configure_agents", _agent_ids))


func replay(events: Array[Dictionary]) -> bool:
	_reset_projection()
	return apply_batch(events)


func apply_batch(events: Array[Dictionary]) -> bool:
	var expected := _last_sequence + 1
	for value in events:
		if not value is Dictionary or int((value as Dictionary).get("global_sequence", -1)) != expected:
			return false
		expected += 1
	for value in events:
		var event := (value as Dictionary).duplicate(true)
		_apply_public_world(event)
		_apply_actor_activity(event)
		_route_to_inboxes(event)
		_last_sequence = int(event.global_sequence)
	return true


func public_world_state() -> Dictionary:
	return _public_world_state.duplicate(true)


func market_view() -> Dictionary:
	return (_public_world_state.get("market_summary", {}) as Dictionary).duplicate(true)


func get_last_sequence() -> int:
	return _last_sequence


func get_actor(actor_id: String) -> Dictionary:
	return (_actors.get(actor_id, {}) as Dictionary).duplicate(true)


func global_public_events(limit: int = 24) -> Array[Dictionary]:
	return _tail(_global_public_events, clampi(limit, 0, GLOBAL_EVENT_LIMIT))


func actor_public_events(actor_id: String, observer_id: String, limit: int = KNOWN_ACTOR_EVENT_LIMIT) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	for value in _actor_public_events.get(actor_id, []) as Array:
		var event := value as Dictionary
		if _is_visible_to(event, observer_id):
			visible.append(event.duplicate(true))
	return _tail(visible, clampi(limit, 0, ACTOR_EVENT_LIMIT))


func known_actors(observer_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var actor_ids := _actors.keys()
	actor_ids.sort()
	for actor_id_value in actor_ids:
		var actor_id := str(actor_id_value)
		if actor_id == observer_id:
			continue
		var actor: Dictionary = _actors[actor_id]
		result.append({
			"actor_id": actor_id,
			"actor_type": str(actor.actor_type),
			"display_name": str(actor.display_name),
			"public_role": str(actor.public_role),
			"region_id": str(actor.region_id),
			"current_public_state": (actor.current_public_state as Dictionary).duplicate(true),
			"observable_status": str((actor.current_public_state as Dictionary).get("status", "idle")),
			"relationship": {},
			"active_public_interactions": [],
			"recent_public_events": actor_public_events(actor_id, observer_id),
		})
	return result


func _apply_public_world(event: Dictionary) -> void:
	var scope := str((event.visibility as Dictionary).scope)
	if scope == "public":
		_global_public_events.append(event.duplicate(true))
		_trim_front(_global_public_events, GLOBAL_EVENT_LIMIT)
	var payload := event.payload as Dictionary
	match str(event.event_type):
		"TimeChanged":
			_public_world_state.absolute_game_minute = int(payload.get("absolute_game_minute", _public_world_state.absolute_game_minute))
			_public_world_state.time_of_day = {
				"hour": int(payload.get("hour", 0)),
				"minute": int(payload.get("minute", 0)),
			}
		"DayStarted":
			_public_world_state.game_day = int(payload.get("day", _public_world_state.game_day))
		"SeasonChanged":
			_public_world_state.season = payload.get("season", _public_world_state.season)
		"WeatherChanged":
			_public_world_state.weather = str(payload.get("weather", ""))
		"EnvironmentConditionChanged":
			var conditions := (_public_world_state.environment_conditions as Dictionary).duplicate(true)
			conditions[str(event.aggregate_id)] = payload.duplicate(true)
			_public_world_state.environment_conditions = conditions
		"MarketPriceChanged", "MarketStockChanged":
			var market := (_public_world_state.market_summary as Dictionary).duplicate(true)
			var item_id := str(payload.get("item_id", event.aggregate_id))
			var item := (market.get(item_id, {}) as Dictionary).duplicate(true)
			for key in payload:
				item[key] = payload[key]
			market[item_id] = item
			_public_world_state.market_summary = market
		"MarketPressureSettled":
			_public_world_state["last_market_pressure"] = payload.duplicate(true)
			var market := (_public_world_state.market_summary as Dictionary).duplicate(true)
			var pressure_items: Dictionary = ((payload.get("pressure", {}) as Dictionary).get("items", {}) as Dictionary)
			for item_id_value in pressure_items:
				var item_id := str(item_id_value)
				var item := (market.get(item_id, {}) as Dictionary).duplicate(true)
				item["last_agent_pressure"] = (pressure_items[item_id] as Dictionary).duplicate(true)
				market[item_id] = item
			_public_world_state.market_summary = market


func _apply_actor_activity(event: Dictionary) -> void:
	var actor_id := str(event.actor_id)
	if actor_id == "system" or not _actors.has(actor_id):
		return
	var scope := str((event.visibility as Dictionary).scope)
	if not scope in ["public", "region"]:
		return
	var events: Array = _actor_public_events[actor_id]
	events.append(event.duplicate(true))
	_trim_front(events, ACTOR_EVENT_LIMIT)
	var actor: Dictionary = _actors[actor_id]
	var state := (actor.current_public_state as Dictionary).duplicate(true)
	var payload := event.payload as Dictionary
	match str(event.event_type):
		"PublicStatusChanged":
			state.status = str(payload.get("status", state.get("status", "idle")))
		"ActorRegionChanged":
			var region_id := str(payload.get("region_id", actor.region_id))
			actor.region_id = region_id
			state.region_id = region_id
		"RoleChanged":
			var public_role := str(payload.get("role_id", actor.public_role))
			actor.public_role = public_role
			state.public_role = public_role
	actor.current_public_state = state
	_actors[actor_id] = actor


func _route_to_inboxes(event: Dictionary) -> void:
	for agent_id in _agent_ids:
		if _is_visible_to(event, agent_id):
			_inbox.call("push_world_event", agent_id, event)


func _is_visible_to(event: Dictionary, observer_id: String) -> bool:
	var visibility := event.visibility as Dictionary
	match str(visibility.scope):
		"public":
			return true
		"participants", "private":
			return observer_id in (visibility.actor_ids as Array)
		"region":
			if not _actors.has(observer_id):
				return false
			var payload := event.payload as Dictionary
			var target_region := str(payload.get("region_id", ""))
			if target_region.is_empty() and _actors.has(str(event.actor_id)):
				target_region = str((_actors[str(event.actor_id)] as Dictionary).region_id)
			return str((_actors[observer_id] as Dictionary).region_id) == target_region
	return false


func _reset_projection() -> void:
	_last_sequence = 0
	_global_public_events.clear()
	_public_world_state = {
		"game_day": 1,
		"absolute_game_minute": 0,
		"time_of_day": {},
		"season": 0,
		"weather": "",
		"environment_conditions": {},
		"public_hazards": {},
		"unlocked_regions": [],
		"market_summary": {},
		"public_discoveries": [],
	}
	for actor_id in _actor_public_events:
		_actor_public_events[actor_id] = []


func _trim_front(values: Array, maximum: int) -> void:
	while values.size() > maximum:
		values.pop_front()


func _tail(values: Array, limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if limit <= 0:
		return result
	var first := maxi(0, values.size() - limit)
	for index in range(first, values.size()):
		result.append((values[index] as Dictionary).duplicate(true))
	return result
