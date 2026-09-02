class_name AgentWorldFactBridge
extends RefCounted

var _store: Variant
var _projector: Variant


func configure(store: Variant, projector: Variant) -> bool:
	if (
		store == null
		or projector == null
		or not store.has_method("append_batch")
		or not projector.has_method("apply_batch")
		or not projector.has_method("get_last_sequence")
	):
		return false
	_store = store
	_projector = projector
	return true


func publish_day(day: int, game_minute: int, source_id: String) -> bool:
	return _publish("DayStarted", "public_world", "clock", {"day": day}, game_minute, source_id)


func publish_season(season: int, game_minute: int, source_id: String) -> bool:
	return _publish("SeasonChanged", "public_world", "season", {"season": season}, game_minute, source_id)


func publish_time(hour: int, minute: int, absolute_game_minute: int, source_id: String) -> bool:
	return _publish("TimeChanged", "public_world", "clock", {
		"hour": hour,
		"minute": minute,
		"absolute_game_minute": absolute_game_minute,
	}, absolute_game_minute, source_id)


func publish_weather(weather: String, game_minute: int, source_id: String) -> bool:
	return _publish("WeatherChanged", "public_world", "weather", {"weather": weather}, game_minute, source_id)


func publish_environment(condition_id: String, state: Dictionary, game_minute: int, source_id: String) -> bool:
	return _publish("EnvironmentConditionChanged", "public_world", condition_id, state, game_minute, source_id)


func publish_market_price(item_id: String, price: int, game_minute: int, source_id: String, state: Dictionary = {}) -> bool:
	var payload := state.duplicate(true)
	payload["item_id"] = item_id
	payload["price"] = price
	return _publish("MarketPriceChanged", "market", item_id, payload, game_minute, source_id)


func publish_market_stock(item_id: String, stock: int, game_minute: int, source_id: String, state: Dictionary = {}) -> bool:
	var payload := state.duplicate(true)
	payload["item_id"] = item_id
	payload["stock"] = stock
	return _publish("MarketStockChanged", "market", item_id, payload, game_minute, source_id)


func publish_market_pressure(total_day: int, pressure: Dictionary, game_minute: int, source_id: String) -> bool:
	return _publish("MarketPressureSettled", "market_pressure", "day-%d" % total_day, {"day": total_day, "pressure": pressure.duplicate(true)}, game_minute, source_id)


func _publish(
	event_type: String,
	aggregate_type: String,
	aggregate_id: String,
	payload: Dictionary,
	game_minute: int,
	source_id: String
) -> bool:
	if _store == null or _projector == null or source_id.strip_edges().is_empty():
		return false
	var candidates: Array[Dictionary] = [{
		"event_type": event_type,
		"aggregate_type": aggregate_type,
		"aggregate_id": aggregate_id,
		"actor_id": "system",
		"game_minute": maxi(0, game_minute),
		"command_id": source_id,
		"correlation_id": aggregate_id,
		"causation_event_id": "",
		"visibility": {"scope": "public", "actor_ids": []},
		"payload": payload.duplicate(true),
	}]
	var result: Dictionary = _store.call("append_batch", candidates, "world-fact:" + source_id)
	if not bool(result.get("ok", false)):
		return false
	var committed := result.get("events", []) as Array
	if committed.is_empty():
		return false
	if int((committed[-1] as Dictionary).global_sequence) <= int(_projector.call("get_last_sequence")):
		return true
	if bool(_projector.call("apply_batch", committed)):
		return true
	return bool(_projector.call("replay", _store.call("get_events_after", 0)))
