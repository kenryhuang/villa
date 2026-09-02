class_name AgentInteractionSystem
extends RefCounted

const MAX_TEXT_LENGTH := 1000
const MAX_NOTE_LENGTH := 500
const MAX_OFFER_MINUTES := 10080
const MAX_ASSET_QUANTITY := 9223372036854775807
const OPEN_STATUS := "open"
const GAME_MINUTES_PER_DAY := 1080
const MAX_PRESSURE_PER_OFFER := 20
const MAX_PRESSURE_PER_AGENT := 40
const MAX_PRESSURE_PER_DAY := 80
const MAX_PRICE_BIAS_BPS := 2000

var _economy: Variant
var _store: Variant
var _projector: Variant
var _wake_agent: Callable
var _market: Variant
var _offers: Dictionary = {}
var _results: Dictionary = {}
var _next_offer_id := 1
var _settled_pressure: Dictionary = {}


func configure(economy: Variant, store: Variant, projector: Variant, wake_agent: Callable = Callable(), market: Variant = null) -> bool:
	if (
		economy == null
		or store == null
		or projector == null
		or not economy.has_method("get_npc_state")
		or not economy.has_method("can_apply_agent_asset_delta")
		or not economy.has_method("apply_agent_asset_delta")
		or not store.has_method("append_batch")
		or not projector.has_method("apply_batch")
	):
		return false
	_economy = economy
	_store = store
	_projector = projector
	_wake_agent = wake_agent
	_market = market
	if _market != null and (not _market.has_method("set_agent_market_pressure") or not _market.has_method("get_mid_price")):
		return false
	return true


func execute(command: Dictionary, game_minute: int) -> Dictionary:
	var key := str(command.get("idempotency_key", "")).strip_edges()
	if key.is_empty() or game_minute < 0:
		return _failure("invalid_command")
	if _results.has(key):
		return (_results[key] as Dictionary).duplicate(true)
	var agent_id := str(command.get("agent_id", ""))
	var tool_name := str(command.get("tool_name", ""))
	var arguments: Variant = command.get("arguments", {})
	if not _actor_exists(agent_id) or not arguments is Dictionary:
		return _remember(key, _failure("invalid_actor_or_arguments"))
	var result: Dictionary
	match tool_name:
		"send_message": result = _send_message(agent_id, arguments, command, game_minute)
		"speak": result = _speak(agent_id, arguments, command, game_minute)
		"propose_trade": result = _propose_trade(agent_id, arguments, command, game_minute)
		"counter_trade": result = _counter_trade(agent_id, arguments, command, game_minute)
		"accept_trade": result = _accept_trade(agent_id, arguments, command, game_minute)
		"reject_trade": result = _close_offer(agent_id, arguments, command, game_minute, "rejected")
		"cancel_trade": result = _close_offer(agent_id, arguments, command, game_minute, "cancelled")
		_: result = _failure("unsupported_interaction_tool")
	return _remember(key, result)


func expire_due(game_minute: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var offer_ids := _offers.keys()
	offer_ids.sort()
	for offer_id_value in offer_ids:
		var offer_id := str(offer_id_value)
		var offer: Dictionary = _offers[offer_id]
		if str(offer.status) != OPEN_STATUS or int(offer.expires_game_minute) > game_minute:
			continue
		var event := _event("TradeOfferExpired", "trade_offer", offer_id, "system", game_minute, "expire:" + offer_id, "trade:" + offer_id, {"offer_id": offer_id}, "participants", [str(offer.proposer_id), str(offer.recipient_id)])
		var committed := _commit([event], "expire:%s:%d" % [offer_id, game_minute])
		if not bool(committed.get("ok", false)):
			continue
		offer.status = "expired"
		_offers[offer_id] = offer
		_refresh_market_pressure(game_minute)
		_wake(str(offer.proposer_id), 3, game_minute)
		_wake(str(offer.recipient_id), 3, game_minute)
		results.append({"ok": true, "offer_id": offer_id, "events": committed.events})
	return results


func available_item(actor_id: String, item_id: String) -> int:
	var state = _economy.call("get_npc_state", actor_id) if _economy != null else null
	if state == null:
		return 0
	var reserved := 0
	for offer_value in _offers.values():
		var offer := offer_value as Dictionary
		if str(offer.status) == OPEN_STATUS and str(offer.proposer_id) == actor_id:
			reserved += int(((offer.proposer_gives as Dictionary).items as Dictionary).get(item_id, 0))
	return maxi(0, int(state.inventory.get(item_id, 0)) - reserved)


func available_gold(actor_id: String) -> int:
	var state = _economy.call("get_npc_state", actor_id) if _economy != null else null
	if state == null:
		return 0
	var reserved := 0
	for offer_value in _offers.values():
		var offer := offer_value as Dictionary
		if str(offer.status) == OPEN_STATUS and str(offer.proposer_id) == actor_id:
			reserved += int((offer.proposer_gives as Dictionary).gold)
	return maxi(0, int(state.gold) - reserved)


func get_offer(offer_id: String, observer_id: String) -> Dictionary:
	var offer: Dictionary = _offers.get(offer_id, {})
	if offer.is_empty() or not observer_id in [str(offer.proposer_id), str(offer.recipient_id)]:
		return {}
	return offer.duplicate(true)


func list_offers(observer_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var offer_ids := _offers.keys()
	offer_ids.sort()
	for offer_id_value in offer_ids:
		var offer := get_offer(str(offer_id_value), observer_id)
		if not offer.is_empty():
			result.append(offer)
	return result


func refresh_market_pressure(game_minute: int) -> bool:
	return _refresh_market_pressure(game_minute)


func mark_market_pressure_consumed(total_day: int) -> void:
	_settled_pressure.erase(total_day)


func _send_message(agent_id: String, arguments: Dictionary, command: Dictionary, game_minute: int) -> Dictionary:
	var target_id := str(arguments.get("target_actor_id", ""))
	var text: Variant = arguments.get("text")
	var urgency := str(arguments.get("urgency", "normal"))
	if not _actor_exists(target_id) or target_id == agent_id or typeof(text) != TYPE_STRING or str(text).is_empty() or str(text).length() > MAX_TEXT_LENGTH or not urgency in ["normal", "urgent"]:
		return _failure("invalid_message")
	var event := _event("MessageSent", "message", str(command.idempotency_key), agent_id, game_minute, str(command.action_id), str(command.decision_id), {"sender_id": agent_id, "target_actor_id": target_id, "text": str(text), "urgency": urgency}, "participants", [agent_id, target_id])
	var committed := _commit([event], str(command.idempotency_key))
	if bool(committed.get("ok", false)) and urgency == "urgent":
		_wake(target_id, 3, game_minute)
	return committed


func _speak(agent_id: String, arguments: Dictionary, command: Dictionary, game_minute: int) -> Dictionary:
	var target_id := str(arguments.get("target_actor_id", ""))
	var text: Variant = arguments.get("text")
	var actor: Dictionary = _projector.call("get_actor", agent_id)
	if actor.is_empty() or (not target_id.is_empty() and not _actor_exists(target_id)) or typeof(text) != TYPE_STRING or str(text).is_empty() or str(text).length() > MAX_TEXT_LENGTH:
		return _failure("invalid_speech")
	var event := _event("ActorSpoke", "speech", str(command.idempotency_key), agent_id, game_minute, str(command.action_id), str(command.decision_id), {"speaker_id": agent_id, "target_actor_id": target_id, "text": str(text), "region_id": str(actor.region_id)}, "region", [])
	return _commit([event], str(command.idempotency_key))


func _propose_trade(agent_id: String, arguments: Dictionary, command: Dictionary, game_minute: int) -> Dictionary:
	var target_id := str(arguments.get("target_actor_id", ""))
	if not _actor_exists(target_id) or target_id == agent_id:
		return _failure("invalid_trade_participant")
	var offer_value: Variant = _new_offer(agent_id, target_id, arguments.get("give"), arguments.get("receive"), arguments.get("expires_in_minutes"), arguments.get("note", ""), game_minute, "")
	if offer_value == null:
		return _failure("invalid_trade_offer")
	var offer := offer_value as Dictionary
	if not _has_available(agent_id, offer.proposer_gives):
		return _failure("insufficient_available_assets")
	var event := _event("TradeOfferProposed", "trade_offer", str(offer.offer_id), agent_id, game_minute, str(command.action_id), str(command.decision_id), offer, "participants", [agent_id, target_id])
	var committed := _commit([event], str(command.idempotency_key))
	if not bool(committed.get("ok", false)):
		return committed
	_offers[str(offer.offer_id)] = offer
	_next_offer_id += 1
	_refresh_market_pressure(game_minute)
	_wake(target_id, 3, game_minute)
	return {"ok": true, "offer_id": str(offer.offer_id), "events": committed.events}


func _counter_trade(agent_id: String, arguments: Dictionary, command: Dictionary, game_minute: int) -> Dictionary:
	var old_id := str(arguments.get("offer_id", ""))
	var old_offer: Dictionary = _offers.get(old_id, {})
	if old_offer.is_empty() or str(old_offer.status) != OPEN_STATUS or str(old_offer.recipient_id) != agent_id:
		return _failure("offer_not_counterable")
	var new_value: Variant = _new_offer(agent_id, str(old_offer.proposer_id), arguments.get("give"), arguments.get("receive"), arguments.get("expires_in_minutes"), arguments.get("note", ""), game_minute, old_id)
	if new_value == null:
		return _failure("invalid_trade_offer")
	var new_offer := new_value as Dictionary
	if not _has_available(agent_id, new_offer.proposer_gives):
		return _failure("insufficient_available_assets")
	var closed_payload := {"offer_id": old_id, "counter_offer_id": str(new_offer.offer_id)}
	var events: Array[Dictionary] = [
		_event("TradeOfferCountered", "trade_offer", old_id, agent_id, game_minute, str(command.action_id), str(command.decision_id), closed_payload, "participants", [str(old_offer.proposer_id), str(old_offer.recipient_id)]),
		_event("TradeOfferProposed", "trade_offer", str(new_offer.offer_id), agent_id, game_minute, str(command.action_id), str(command.decision_id), new_offer, "participants", [str(new_offer.proposer_id), str(new_offer.recipient_id)]),
	]
	var committed := _commit(events, str(command.idempotency_key))
	if not bool(committed.get("ok", false)):
		return committed
	old_offer.status = "countered"
	old_offer.counter_offer_id = str(new_offer.offer_id)
	_offers[old_id] = old_offer
	_offers[str(new_offer.offer_id)] = new_offer
	_next_offer_id += 1
	_refresh_market_pressure(game_minute)
	_wake(str(new_offer.recipient_id), 3, game_minute)
	return {"ok": true, "offer_id": str(new_offer.offer_id), "events": committed.events}


func _accept_trade(agent_id: String, arguments: Dictionary, command: Dictionary, game_minute: int) -> Dictionary:
	var offer_id := str(arguments.get("offer_id", ""))
	var offer: Dictionary = _offers.get(offer_id, {})
	if offer.is_empty() or str(offer.status) != OPEN_STATUS:
		return _failure("offer_not_open")
	if "player" in [str(offer.proposer_id), str(offer.recipient_id)]:
		return _failure("player_confirmation_required")
	if str(offer.recipient_id) != agent_id:
		return _failure("only_receiver_can_accept")
	if not _has_total_assets(str(offer.proposer_id), offer.proposer_gives):
		return _failure("proposer_assets_changed")
	if not _has_total_assets(str(offer.recipient_id), offer.proposer_receives):
		return _failure("receiver_assets_changed")
	var proposer_delta := _bundle_delta(offer.proposer_gives, offer.proposer_receives)
	var receiver_delta := _bundle_delta(offer.proposer_receives, offer.proposer_gives)
	if not bool(_economy.call("can_apply_agent_asset_delta", str(offer.proposer_id), proposer_delta.items, int(proposer_delta.gold))) or not bool(_economy.call("can_apply_agent_asset_delta", str(offer.recipient_id), receiver_delta.items, int(receiver_delta.gold))):
		return _failure("asset_overflow")
	var proposer_state = _economy.call("get_npc_state", str(offer.proposer_id))
	var receiver_state = _economy.call("get_npc_state", str(offer.recipient_id))
	var proposer_before: Dictionary = proposer_state.to_dict()
	var receiver_before: Dictionary = receiver_state.to_dict()
	if not bool(_economy.call("apply_agent_asset_delta", str(offer.proposer_id), proposer_delta.items, int(proposer_delta.gold))):
		return _failure("atomic_settlement_failed")
	if not bool(_economy.call("apply_agent_asset_delta", str(offer.recipient_id), receiver_delta.items, int(receiver_delta.gold))):
		proposer_state.from_dict(proposer_before)
		return _failure("atomic_settlement_failed")
	var event := _event("TradeSettled", "trade_offer", offer_id, agent_id, game_minute, str(command.action_id), str(command.decision_id), {"offer_id": offer_id, "proposer_id": str(offer.proposer_id), "recipient_id": str(offer.recipient_id), "proposer_gives": offer.proposer_gives, "proposer_receives": offer.proposer_receives}, "participants", [str(offer.proposer_id), str(offer.recipient_id)])
	var committed := _commit([event], str(command.idempotency_key))
	if not bool(committed.get("ok", false)):
		proposer_state.from_dict(proposer_before)
		receiver_state.from_dict(receiver_before)
		return committed
	offer.status = "settled"
	_offers[offer_id] = offer
	_record_settlement_pressure(offer, game_minute)
	_refresh_market_pressure(game_minute)
	_wake(str(offer.proposer_id), 3, game_minute)
	return {"ok": true, "offer_id": offer_id, "events": committed.events, "changed_entities": ["trade_offer:" + offer_id, "npc_inventory:" + str(offer.proposer_id), "npc_inventory:" + str(offer.recipient_id)], "resource_delta": {}}


func _close_offer(agent_id: String, arguments: Dictionary, command: Dictionary, game_minute: int, status: String) -> Dictionary:
	var offer_id := str(arguments.get("offer_id", ""))
	var offer: Dictionary = _offers.get(offer_id, {})
	if offer.is_empty() or str(offer.status) != OPEN_STATUS:
		return _failure("offer_not_open")
	if (status == "rejected" and agent_id != str(offer.recipient_id)) or (status == "cancelled" and agent_id != str(offer.proposer_id)):
		return _failure("offer_close_unauthorized")
	var event_type := "TradeOfferRejected" if status == "rejected" else "TradeOfferCancelled"
	var payload := {"offer_id": offer_id, "reason_code": str(arguments.get("reason_code", ""))}
	var committed := _commit([_event(event_type, "trade_offer", offer_id, agent_id, game_minute, str(command.action_id), str(command.decision_id), payload, "participants", [str(offer.proposer_id), str(offer.recipient_id)])], str(command.idempotency_key))
	if not bool(committed.get("ok", false)):
		return committed
	offer.status = status
	_offers[offer_id] = offer
	_refresh_market_pressure(game_minute)
	_wake(str(offer.proposer_id) if agent_id == str(offer.recipient_id) else str(offer.recipient_id), 3, game_minute)
	return {"ok": true, "offer_id": offer_id, "events": committed.events}


func _new_offer(proposer_id: String, recipient_id: String, give_value: Variant, receive_value: Variant, expires_value: Variant, note_value: Variant, game_minute: int, parent_offer_id: String) -> Variant:
	var give: Variant = _normalize_bundle(give_value)
	var receive: Variant = _normalize_bundle(receive_value)
	if give == null or receive == null or typeof(expires_value) != TYPE_INT or int(expires_value) < 1 or int(expires_value) > MAX_OFFER_MINUTES or typeof(note_value) != TYPE_STRING or str(note_value).length() > MAX_NOTE_LENGTH:
		return null
	if _bundle_empty(give) or _bundle_empty(receive):
		return null
	for item_id in (give.items as Dictionary):
		if (receive.items as Dictionary).has(item_id):
			return null
	return {
		"offer_id": "offer-%06d" % _next_offer_id,
		"proposer_id": proposer_id,
		"recipient_id": recipient_id,
		"proposer_gives": give,
		"proposer_receives": receive,
		"status": OPEN_STATUS,
		"created_game_minute": game_minute,
		"expires_game_minute": game_minute + int(expires_value),
		"parent_offer_id": parent_offer_id,
		"counter_offer_id": "",
		"note": str(note_value),
	}


func _normalize_bundle(value: Variant) -> Variant:
	if not value is Dictionary or value.size() != 2 or not value.has("items") or not value.has("gold") or not value.items is Dictionary or not _nonnegative_integer(value.gold):
		return null
	var items: Dictionary = {}
	for item_id_value in value.items:
		var item_id := str(item_id_value)
		var quantity: Variant = value.items[item_id_value]
		if item_id.is_empty() or not bool(_economy.call("has_item", item_id)) or not _positive_integer(quantity):
			return null
		items[item_id] = int(quantity)
	return {"items": items, "gold": int(value.gold)}


func _bundle_empty(bundle: Dictionary) -> bool:
	return int(bundle.gold) == 0 and (bundle.items as Dictionary).is_empty()


func _has_available(actor_id: String, bundle: Dictionary) -> bool:
	if available_gold(actor_id) < int(bundle.gold):
		return false
	for item_id in bundle.items:
		if available_item(actor_id, str(item_id)) < int(bundle.items[item_id]):
			return false
	return true


func _has_total_assets(actor_id: String, bundle: Dictionary) -> bool:
	var state = _economy.call("get_npc_state", actor_id)
	if state == null or int(state.gold) < int(bundle.gold):
		return false
	for item_id in bundle.items:
		if int(state.inventory.get(item_id, 0)) < int(bundle.items[item_id]):
			return false
	return true


func _bundle_delta(debits: Dictionary, credits: Dictionary) -> Dictionary:
	var items: Dictionary = {}
	for item_id in debits.items:
		items[str(item_id)] = -int(debits.items[item_id])
	for item_id in credits.items:
		items[str(item_id)] = int(items.get(str(item_id), 0)) + int(credits.items[item_id])
	return {"items": items, "gold": int(credits.gold) - int(debits.gold)}


func _refresh_market_pressure(game_minute: int) -> bool:
	if _market == null:
		return true
	var day := int(game_minute / GAME_MINUTES_PER_DAY) + 1
	var per_agent: Dictionary = {}
	for offer_value in _offers.values():
		var offer := offer_value as Dictionary
		if str(offer.status) != OPEN_STATUS or int(offer.expires_game_minute) <= game_minute:
			continue
		var agent_id := str(offer.proposer_id)
		var agent_items: Dictionary = per_agent.get(agent_id, {})
		_add_bundle_pressure(agent_items, offer.proposer_gives, "supply")
		_add_bundle_pressure(agent_items, offer.proposer_receives, "demand")
		per_agent[agent_id] = agent_items
	var combined: Dictionary = {}
	for agent_items_value in per_agent.values():
		for item_id_value in (agent_items_value as Dictionary):
			var item_id := str(item_id_value)
			var source: Dictionary = agent_items_value[item_id]
			var target: Dictionary = combined.get(item_id, _empty_pressure())
			target.demand = mini(MAX_PRESSURE_PER_DAY, int(target.demand) + mini(MAX_PRESSURE_PER_AGENT, int(source.demand)))
			target.supply = mini(MAX_PRESSURE_PER_DAY, int(target.supply) + mini(MAX_PRESSURE_PER_AGENT, int(source.supply)))
			combined[item_id] = target
	for item_id_value in (_settled_pressure.get(day, {}) as Dictionary):
		var item_id := str(item_id_value)
		var settled: Dictionary = _settled_pressure[day][item_id]
		var target: Dictionary = combined.get(item_id, _empty_pressure())
		target.private_volume = mini(MAX_PRESSURE_PER_DAY, int(settled.private_volume))
		target.price_bias_bps = clampi(int(settled.price_bias_bps), -MAX_PRICE_BIAS_BPS, MAX_PRICE_BIAS_BPS)
		combined[item_id] = target
	return bool(_market.call("set_agent_market_pressure", {"day": day, "items": combined}))


func _add_bundle_pressure(target: Dictionary, bundle: Dictionary, field: String) -> void:
	for item_id_value in bundle.items:
		var item_id := str(item_id_value)
		var pressure: Dictionary = target.get(item_id, _empty_pressure())
		pressure[field] = mini(MAX_PRESSURE_PER_AGENT, int(pressure[field]) + mini(MAX_PRESSURE_PER_OFFER, int(bundle.items[item_id])))
		target[item_id] = pressure


func _record_settlement_pressure(offer: Dictionary, game_minute: int) -> void:
	if _market == null:
		return
	var day := int(game_minute / GAME_MINUTES_PER_DAY) + 1
	var day_pressure: Dictionary = _settled_pressure.get(day, {})
	_record_cash_price_signal(day_pressure, offer.proposer_gives, offer.proposer_receives)
	_record_cash_price_signal(day_pressure, offer.proposer_receives, offer.proposer_gives)
	_settled_pressure[day] = day_pressure


func _record_cash_price_signal(day_pressure: Dictionary, item_side: Dictionary, cash_side: Dictionary) -> void:
	if int(cash_side.gold) <= 0 or (item_side.items as Dictionary).size() != 1:
		return
	var item_id := str((item_side.items as Dictionary).keys()[0])
	var quantity := int(item_side.items[item_id])
	var midpoint := int(_market.call("get_mid_price", item_id))
	if quantity <= 0 or midpoint <= 0:
		return
	var clearing_price := float(cash_side.gold) / float(quantity)
	var bias := clampi(roundi((clearing_price - float(midpoint)) * 10000.0 / float(midpoint)), -MAX_PRICE_BIAS_BPS, MAX_PRICE_BIAS_BPS)
	var pressure: Dictionary = day_pressure.get(item_id, _empty_pressure())
	var old_volume := int(pressure.private_volume)
	var added_volume := mini(MAX_PRESSURE_PER_OFFER, quantity)
	var new_volume := mini(MAX_PRESSURE_PER_DAY, old_volume + added_volume)
	if new_volume > 0:
		pressure.price_bias_bps = clampi(roundi((float(int(pressure.price_bias_bps) * old_volume) + float(bias * added_volume)) / float(old_volume + added_volume)), -MAX_PRICE_BIAS_BPS, MAX_PRICE_BIAS_BPS)
	pressure.private_volume = new_volume
	day_pressure[item_id] = pressure


func _empty_pressure() -> Dictionary:
	return {"demand": 0, "supply": 0, "private_volume": 0, "price_bias_bps": 0}


func _commit(events: Array[Dictionary], key: String) -> Dictionary:
	var committed: Dictionary = _store.call("append_batch", events, key)
	if not bool(committed.get("ok", false)):
		return _failure(str(committed.get("error", "event_commit_failed")))
	var committed_events: Array[Dictionary] = []
	committed_events.assign(committed.events)
	if not bool(_projector.call("apply_batch", committed_events)):
		return _failure("event_projection_failed")
	return {"ok": true, "events": committed_events}


func _event(event_type: String, aggregate_type: String, aggregate_id: String, actor_id: String, game_minute: int, command_id: String, correlation_id: String, payload: Dictionary, scope: String, actor_ids: Array) -> Dictionary:
	return {"event_type": event_type, "aggregate_type": aggregate_type, "aggregate_id": aggregate_id, "actor_id": actor_id, "game_minute": game_minute, "command_id": command_id, "correlation_id": correlation_id, "causation_event_id": "", "visibility": {"scope": scope, "actor_ids": actor_ids}, "payload": payload.duplicate(true)}


func _actor_exists(actor_id: String) -> bool:
	return not actor_id.is_empty() and (actor_id == "player" or (_economy != null and bool(_economy.call("has_npc", actor_id)))) and not (_projector.call("get_actor", actor_id) as Dictionary).is_empty()


func _wake(agent_id: String, priority: int, game_minute: int) -> void:
	if agent_id != "player" and _wake_agent.is_valid():
		_wake_agent.call(agent_id, priority, game_minute)


func _remember(key: String, result: Dictionary) -> Dictionary:
	_results[key] = result.duplicate(true)
	return result


func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}


func _nonnegative_integer(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and floorf(float(value)) == float(value) and int(value) >= 0 and int(value) <= MAX_ASSET_QUANTITY


func _positive_integer(value: Variant) -> bool:
	return _nonnegative_integer(value) and int(value) > 0
