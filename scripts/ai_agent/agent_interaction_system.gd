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
const STATE_VERSION := 1
const MAX_SAFE_INTEGER := 9223372036854775807

var _economy: Variant
var _store: Variant
var _projector: Variant
var _wake_agent: Callable
var _market: Variant
var _offers: Dictionary = {}
var _results: Dictionary = {}
var _next_offer_id := 1
var _settled_pressure: Dictionary = {}
var _player_inventory: Variant
var _player_wallet: Variant
var _external_reservations: Dictionary = {}


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


func configure_player_assets(inventory: Variant, wallet: Variant) -> bool:
	if inventory == null or wallet == null or not inventory.has_method("get_item_count") or not inventory.has_method("remove_item") or not inventory.has_method("add_item") or not inventory.has_method("restore_state") or not wallet.has_method("spend_gold") or not wallet.has_method("add_gold") or not wallet.has_method("restore_gold_unchecked"):
		return false
	_player_inventory = inventory
	_player_wallet = wallet
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
	if actor_id == "player":
		if _player_inventory == null:
			return 0
		return int(_player_inventory.call("get_item_count", item_id)) - _reserved_item(actor_id, item_id)
	var state = _economy.call("get_npc_state", actor_id) if _economy != null else null
	if state == null:
		return 0
	var reserved := _reserved_item(actor_id, item_id)
	return maxi(0, int(state.inventory.get(item_id, 0)) - reserved)


func _reserved_item(actor_id: String, item_id: String, excluded_offer_id := "", excluded_reservation_id := "") -> int:
	var reserved := 0
	for offer_value in _offers.values():
		var offer := offer_value as Dictionary
		if str(offer.offer_id) != excluded_offer_id and str(offer.status) == OPEN_STATUS and str(offer.proposer_id) == actor_id:
			reserved += int(((offer.proposer_gives as Dictionary).items as Dictionary).get(item_id, 0))
	for reservation_id in _external_reservations:
		if str(reservation_id) == excluded_reservation_id:
			continue
		var reservation_value: Variant = _external_reservations[reservation_id]
		var reservation := reservation_value as Dictionary
		if str(reservation.actor_id) == actor_id:
			reserved += int((reservation.bundle.items as Dictionary).get(item_id, 0))
	return reserved


func available_gold(actor_id: String) -> int:
	if actor_id == "player":
		return maxi(0, int(_player_wallet.gold) - _reserved_gold(actor_id)) if _player_wallet != null else 0
	var state = _economy.call("get_npc_state", actor_id) if _economy != null else null
	if state == null:
		return 0
	return maxi(0, int(state.gold) - _reserved_gold(actor_id))


func _reserved_gold(actor_id: String, excluded_offer_id := "", excluded_reservation_id := "") -> int:
	var reserved := 0
	for offer_value in _offers.values():
		var offer := offer_value as Dictionary
		if str(offer.offer_id) != excluded_offer_id and str(offer.status) == OPEN_STATUS and str(offer.proposer_id) == actor_id:
			reserved += int((offer.proposer_gives as Dictionary).gold)
	for reservation_id in _external_reservations:
		if str(reservation_id) == excluded_reservation_id:
			continue
		var reservation_value: Variant = _external_reservations[reservation_id]
		var reservation := reservation_value as Dictionary
		if str(reservation.actor_id) == actor_id:
			reserved += int(reservation.bundle.gold)
	return reserved


func reserve_assets(actor_id: String, reservation_id: String, bundle_value: Variant) -> bool:
	if reservation_id.strip_edges().is_empty():
		return false
	if _external_reservations.has(reservation_id):
		var existing := _external_reservations[reservation_id] as Dictionary
		return str(existing.actor_id) == actor_id and existing.bundle == bundle_value
	var bundle: Variant = _normalize_bundle(bundle_value)
	if bundle == null or not _has_available(actor_id, bundle):
		return false
	_external_reservations[reservation_id] = {"actor_id": actor_id, "bundle": (bundle as Dictionary).duplicate(true)}
	return true


func release_reservation(reservation_id: String) -> bool:
	if not _external_reservations.has(reservation_id):
		return false
	_external_reservations.erase(reservation_id)
	return true


func snapshot_actor_assets(actor_id: String) -> Dictionary:
	if actor_id == "player":
		if _player_inventory == null or _player_wallet == null:
			return {}
		return {
			"actor_type": "player",
			"slots": _player_inventory.slots.duplicate(true),
			"quick_slot_mappings": _player_inventory.quick_slot_mappings.duplicate(),
			"gold": int(_player_wallet.gold),
		}
	var state = _economy.call("get_npc_state", actor_id) if _economy != null else null
	return {"actor_type": "npc", "state": state.to_dict()} if state != null else {}


func restore_actor_assets(actor_id: String, snapshot: Dictionary) -> bool:
	if actor_id == "player":
		if _player_inventory == null or _player_wallet == null or str(snapshot.get("actor_type", "")) != "player":
			return false
		_player_inventory.call("restore_state", snapshot.get("slots", []), snapshot.get("quick_slot_mappings", []))
		return bool(_player_wallet.call("restore_gold_unchecked", int(snapshot.get("gold", -1))))
	var state = _economy.call("get_npc_state", actor_id) if _economy != null else null
	return state != null and str(snapshot.get("actor_type", "")) == "npc" and snapshot.get("state") is Dictionary and bool(state.from_dict(snapshot.state))


func can_apply_actor_asset_delta(actor_id: String, item_delta: Dictionary, gold_delta: int, excluded_reservation_id := "") -> bool:
	if actor_id == "player":
		if _player_inventory == null or _player_wallet == null:
			return false
		var additions: Dictionary = {}
		for item_id_value in item_delta:
			var item_id := str(item_id_value)
			var delta := int(item_delta[item_id_value])
			if delta < 0 and int(_player_inventory.call("get_item_count", item_id)) - _reserved_item(actor_id, item_id, "", excluded_reservation_id) < -delta:
				return false
			if delta > 0:
				additions[item_id] = delta
		if not additions.is_empty() and (not _player_inventory.has_method("preflight_add_items") or not bool((_player_inventory.call("preflight_add_items", additions) as Dictionary).get("ok", false))):
			return false
		var available_player_gold := int(_player_wallet.gold) - _reserved_gold(actor_id, "", excluded_reservation_id)
		return (gold_delta >= 0 and available_player_gold <= MAX_SAFE_INTEGER - gold_delta) or (gold_delta < 0 and available_player_gold >= -gold_delta)
	var state = _economy.call("get_npc_state", actor_id) if _economy != null else null
	if state == null:
		return false
	for item_id_value in item_delta:
		var item_id := str(item_id_value)
		var delta := int(item_delta[item_id_value])
		if delta < 0 and int(state.inventory.get(item_id, 0)) - _reserved_item(actor_id, item_id, "", excluded_reservation_id) < -delta:
			return false
	var available_npc_gold := int(state.gold) - _reserved_gold(actor_id, "", excluded_reservation_id)
	if gold_delta < 0 and available_npc_gold < -gold_delta:
		return false
	return bool(_economy.call("can_apply_agent_asset_delta", actor_id, item_delta, gold_delta))


func apply_actor_asset_delta(actor_id: String, item_delta: Dictionary, gold_delta: int, excluded_reservation_id := "") -> bool:
	if not can_apply_actor_asset_delta(actor_id, item_delta, gold_delta, excluded_reservation_id):
		return false
	if actor_id != "player":
		return bool(_economy.call("apply_agent_asset_delta", actor_id, item_delta, gold_delta))
	var before := snapshot_actor_assets(actor_id)
	var item_ids := item_delta.keys()
	item_ids.sort()
	for item_id_value in item_ids:
		var item_id := str(item_id_value)
		var delta := int(item_delta[item_id_value])
		var applied := true
		if delta < 0:
			applied = bool(_player_inventory.call("remove_item", item_id, -delta))
		elif delta > 0:
			applied = bool(_player_inventory.call("add_item", item_id, delta))
		if not applied:
			restore_actor_assets(actor_id, before)
			return false
	var gold_applied := true
	if gold_delta < 0:
		gold_applied = bool(_player_wallet.call("spend_gold", -gold_delta))
	elif gold_delta > 0:
		gold_applied = bool(_player_wallet.call("add_gold", gold_delta))
	if not gold_applied:
		restore_actor_assets(actor_id, before)
		return false
	return true


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


func to_dict() -> Dictionary:
	return {
		"version": STATE_VERSION,
		"next_offer_id": _next_offer_id,
		"offers": _sorted_dictionary_records(_offers, "offer_id", "offer"),
		"idempotency_results": _sorted_dictionary_records(_results, "idempotency_key", "result"),
		"settled_pressure": _sorted_integer_records(_settled_pressure, "day", "items"),
		"external_reservations": _sorted_dictionary_records(_external_reservations, "reservation_id", "reservation"),
	}


func validate_dict(value: Dictionary) -> bool:
	return _normalize_state(value) != null


func validate_against_events(value: Dictionary, events: Array) -> bool:
	var normalized: Variant = _normalize_state(value)
	if normalized == null:
		return false
	var derived: Dictionary = {}
	var derived_pressure: Dictionary = {}
	var next_id := 1
	for event_value in events:
		if not event_value is Dictionary:
			return false
		var event := event_value as Dictionary
		var event_type := str(event.get("event_type", ""))
		var payload: Variant = event.get("payload")
		if event_type == "TradeOfferProposed":
			if not payload is Dictionary:
				return false
			var offer := (payload as Dictionary).duplicate(true)
			var offer_id := str(offer.get("offer_id", ""))
			if offer_id.is_empty() or derived.has(offer_id):
				return false
			derived[offer_id] = offer
			next_id = maxi(next_id, _numeric_suffix(offer_id) + 1)
		elif event_type in ["TradeOfferCountered", "TradeSettled", "TradeOfferRejected", "TradeOfferCancelled", "TradeOfferExpired"]:
			if not payload is Dictionary:
				return false
			var offer_id := str(payload.get("offer_id", ""))
			if not derived.has(offer_id):
				return false
			var offer := derived[offer_id] as Dictionary
			match event_type:
				"TradeOfferCountered":
					offer.status = "countered"
					offer.counter_offer_id = str(payload.get("counter_offer_id", ""))
				"TradeSettled":
					offer.status = "settled"
					var pressure: Variant = payload.get("settled_pressure")
					if not pressure is Dictionary or not _positive_integer(pressure.get("day")) or not _valid_pressure_items(pressure.get("items")):
						return false
					derived_pressure[int(pressure.day)] = (pressure.items as Dictionary).duplicate(true)
				"TradeOfferRejected": offer.status = "rejected"
				"TradeOfferCancelled": offer.status = "cancelled"
				"TradeOfferExpired": offer.status = "expired"
			derived[offer_id] = offer
		elif event_type == "MarketPressureSettled":
			if not payload is Dictionary or not _positive_integer(payload.get("day")):
				return false
			derived_pressure.erase(int(payload.day))
	return (
		int(normalized.next_offer_id) == next_id
		and _canonical_json_value(normalized.offers) == _canonical_json_value(derived)
		and _canonical_json_value(normalized.settled_pressure) == _canonical_json_value(derived_pressure)
	)


func validate_external_reservations(value: Dictionary, expected: Dictionary) -> bool:
	var normalized: Variant = _normalize_state(value)
	return normalized != null and normalized.external_reservations == expected


func _numeric_suffix(identifier: String) -> int:
	var separator := identifier.rfind("-")
	return identifier.substr(separator + 1).to_int() if separator >= 0 else 0


func _canonical_json_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)) and floorf(float(value)) == float(value):
		return int(value)
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonical_json_value(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = _canonical_json_value(value[key])
		return result
	return value


func from_dict(value: Dictionary, apply_market_pressure := true) -> bool:
	var normalized: Variant = _normalize_state(value)
	if normalized == null:
		return false
	_next_offer_id = int(normalized.next_offer_id)
	_offers = normalized.offers
	_results = normalized.results
	_settled_pressure = normalized.settled_pressure
	_external_reservations = normalized.external_reservations
	if apply_market_pressure:
		var minute := int((_projector.call("public_world_state") as Dictionary).get("absolute_game_minute", 0))
		return _refresh_market_pressure(minute)
	return true


func _normalize_state(value: Dictionary) -> Variant:
	var fields := ["version", "next_offer_id", "offers", "idempotency_results", "settled_pressure", "external_reservations"]
	if value.size() != fields.size():
		return null
	for field in fields:
		if not value.has(field):
			return null
	if value.version != STATE_VERSION or not _positive_integer(value.next_offer_id) or not value.offers is Array or not value.idempotency_results is Array or not value.settled_pressure is Array or not value.external_reservations is Array:
		return null
	var offers: Dictionary = {}
	var last_key := ""
	for record_value in value.offers:
		if not record_value is Dictionary:
			return null
		var record := record_value as Dictionary
		var key := str(record.get("offer_id", ""))
		if record.size() != 2 or key.is_empty() or key <= last_key or not record.get("offer") is Dictionary or not _valid_offer(record.offer, key):
			return null
		last_key = key
		offers[key] = (record.offer as Dictionary).duplicate(true)
	var results: Variant = _normalize_keyed_results(value.idempotency_results)
	if results == null:
		return null
	var pressure: Dictionary = {}
	var last_day := 0
	for record_value in value.settled_pressure:
		if not record_value is Dictionary:
			return null
		var record := record_value as Dictionary
		if record.size() != 2 or not _positive_integer(record.get("day")) or int(record.day) <= last_day or not _valid_pressure_items(record.get("items")):
			return null
		last_day = int(record.day)
		pressure[last_day] = (record.items as Dictionary).duplicate(true)
	var reservations: Dictionary = {}
	last_key = ""
	for record_value in value.external_reservations:
		if not record_value is Dictionary:
			return null
		var record := record_value as Dictionary
		var key := str(record.get("reservation_id", ""))
		var reservation: Variant = record.get("reservation")
		if record.size() != 2 or key.is_empty() or key <= last_key or not reservation is Dictionary or str(reservation.get("actor_id", "")).is_empty():
			return null
		var bundle: Variant = _normalize_bundle(reservation.get("bundle"))
		if bundle == null:
			return null
		last_key = key
		reservations[key] = {"actor_id": str(reservation.actor_id), "bundle": bundle}
	return {"next_offer_id": int(value.next_offer_id), "offers": offers, "results": results, "settled_pressure": pressure, "external_reservations": reservations}


func _valid_offer(value: Dictionary, offer_id: String) -> bool:
	if str(value.get("offer_id", "")) != offer_id or not str(value.get("status", "")) in ["open", "settled", "rejected", "cancelled", "expired", "countered"]:
		return false
	if not _actor_exists(str(value.get("proposer_id", ""))) or not _actor_exists(str(value.get("recipient_id", ""))) or str(value.proposer_id) == str(value.recipient_id):
		return false
	if _normalize_bundle(value.get("proposer_gives")) == null or _normalize_bundle(value.get("proposer_receives")) == null:
		return false
	return _nonnegative_integer(value.get("created_game_minute")) and _nonnegative_integer(value.get("expires_game_minute")) and int(value.expires_game_minute) >= int(value.created_game_minute)


func _normalize_keyed_results(records: Array) -> Variant:
	var result: Dictionary = {}
	var last_key := ""
	for record_value in records:
		if not record_value is Dictionary:
			return null
		var record := record_value as Dictionary
		var key := str(record.get("idempotency_key", ""))
		if record.size() != 2 or key.is_empty() or key <= last_key or not record.get("result") is Dictionary:
			return null
		last_key = key
		result[key] = (record.result as Dictionary).duplicate(true)
	return result


func _valid_pressure_items(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for pressure_value in value.values():
		if not pressure_value is Dictionary:
			return false
		var pressure := pressure_value as Dictionary
		for field in ["demand", "supply", "private_volume", "price_bias_bps"]:
			if not _nonnegative_integer(pressure.get(field)) and field != "price_bias_bps":
				return false
		if not _integer_number(pressure.get("price_bias_bps")) or absi(int(pressure.price_bias_bps)) > MAX_PRICE_BIAS_BPS:
			return false
	return true


func _sorted_dictionary_records(source: Dictionary, key_field: String, value_field: String) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var keys := source.keys()
	keys.sort()
	for key in keys:
		var record := {}
		record[key_field] = str(key)
		record[value_field] = source[key].duplicate(true)
		records.append(record)
	return records


func _sorted_integer_records(source: Dictionary, key_field: String, value_field: String) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var keys := source.keys()
	keys.sort()
	for key in keys:
		var record := {}
		record[key_field] = int(key)
		record[value_field] = source[key].duplicate(true)
		records.append(record)
	return records


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
		if str(offer.recipient_id) == "player":
			if agent_id != "player" or arguments.get("player_confirmed") != true:
				return _failure("player_confirmation_required")
		elif agent_id != str(offer.recipient_id):
			return _failure("only_receiver_can_accept")
		return _accept_player_trade(offer_id, offer, command, game_minute, agent_id)
	if str(offer.recipient_id) != agent_id:
		return _failure("only_receiver_can_accept")
	if not _has_total_assets(str(offer.proposer_id), offer.proposer_gives):
		return _failure("proposer_assets_changed")
	if not _has_total_assets(str(offer.recipient_id), offer.proposer_receives):
		return _failure("receiver_assets_changed")
	if not _has_settlement_assets(str(offer.proposer_id), offer.proposer_gives, offer_id):
		return _failure("proposer_assets_reserved")
	if not _has_settlement_assets(str(offer.recipient_id), offer.proposer_receives):
		return _failure("receiver_assets_reserved")
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
	var pressure_after := _settlement_pressure_after(offer, game_minute)
	var event := _event("TradeSettled", "trade_offer", offer_id, agent_id, game_minute, str(command.action_id), str(command.decision_id), {"offer_id": offer_id, "proposer_id": str(offer.proposer_id), "recipient_id": str(offer.recipient_id), "proposer_gives": offer.proposer_gives, "proposer_receives": offer.proposer_receives, "settled_pressure": pressure_after}, "participants", [str(offer.proposer_id), str(offer.recipient_id)])
	var committed := _commit([event], str(command.idempotency_key))
	if not bool(committed.get("ok", false)):
		proposer_state.from_dict(proposer_before)
		receiver_state.from_dict(receiver_before)
		return committed
	offer.status = "settled"
	_offers[offer_id] = offer
	_apply_settlement_pressure(pressure_after)
	_refresh_market_pressure(game_minute)
	_wake(str(offer.proposer_id), 3, game_minute)
	return {"ok": true, "offer_id": offer_id, "events": committed.events, "changed_entities": ["trade_offer:" + offer_id, "npc_inventory:" + str(offer.proposer_id), "npc_inventory:" + str(offer.recipient_id)], "resource_delta": {}}


func _accept_player_trade(offer_id: String, offer: Dictionary, command: Dictionary, game_minute: int, accepted_by: String) -> Dictionary:
	if _player_inventory == null or _player_wallet == null:
		return _failure("player_assets_unavailable")
	var player_is_proposer := str(offer.proposer_id) == "player"
	var npc_id := str(offer.recipient_id) if player_is_proposer else str(offer.proposer_id)
	var player_debits: Dictionary = offer.proposer_gives if player_is_proposer else offer.proposer_receives
	var player_credits: Dictionary = offer.proposer_receives if player_is_proposer else offer.proposer_gives
	var npc_debits: Dictionary = offer.proposer_receives if player_is_proposer else offer.proposer_gives
	var npc_credits: Dictionary = offer.proposer_gives if player_is_proposer else offer.proposer_receives
	if not _has_total_player_assets(player_debits):
		return _failure("player_assets_changed")
	if not _has_total_assets(npc_id, npc_debits):
		return _failure("npc_assets_changed")
	if not _has_settlement_assets("player", player_debits, offer_id if player_is_proposer else ""):
		return _failure("player_assets_reserved")
	if not _has_settlement_assets(npc_id, npc_debits, offer_id if not player_is_proposer else ""):
		return _failure("npc_assets_reserved")
	var capacity_tokens: Array = []
	for item_id in player_credits.items:
		var token = _player_inventory.call("reserve_item_capacity", str(item_id), int(player_credits.items[item_id]))
		if token == null:
			for held in capacity_tokens:
				_player_inventory.call("release_item_capacity_reservation", held)
			return _failure("player_inventory_full")
		capacity_tokens.append(token)
	var npc_delta := _bundle_delta(npc_debits, npc_credits)
	if not bool(_economy.call("can_apply_agent_asset_delta", npc_id, npc_delta.items, int(npc_delta.gold))):
		for held in capacity_tokens:
			_player_inventory.call("release_item_capacity_reservation", held)
		return _failure("asset_overflow")
	var slots_before: Array = _player_inventory.slots.duplicate(true)
	var mappings_before: Array = _player_inventory.quick_slot_mappings.duplicate()
	var gold_before := int(_player_wallet.gold)
	var npc_state = _economy.call("get_npc_state", npc_id)
	var npc_before: Dictionary = npc_state.to_dict()
	var ok := true
	for item_id in player_debits.items:
		ok = ok and bool(_player_inventory.call("remove_item", str(item_id), int(player_debits.items[item_id])))
	if int(player_debits.gold) > 0:
		ok = ok and bool(_player_wallet.call("spend_gold", int(player_debits.gold)))
	ok = ok and bool(_economy.call("apply_agent_asset_delta", npc_id, npc_delta.items, int(npc_delta.gold)))
	for token in capacity_tokens:
		ok = ok and bool(_player_inventory.call("commit_item_capacity_reservation", token))
	if int(player_credits.gold) > 0:
		ok = ok and bool(_player_wallet.call("add_gold", int(player_credits.gold)))
	if not ok:
		_player_inventory.call("restore_state", slots_before, mappings_before)
		_player_wallet.call("restore_gold_unchecked", gold_before)
		npc_state.from_dict(npc_before)
		for token in capacity_tokens:
			if bool(_player_inventory.call("has_item_capacity_reservation", token)):
				_player_inventory.call("release_item_capacity_reservation", token)
		return _failure("atomic_settlement_failed")
	var pressure_after := _settlement_pressure_after(offer, game_minute)
	var event := _event("TradeSettled", "trade_offer", offer_id, accepted_by, game_minute, str(command.action_id), str(command.decision_id), {"offer_id": offer_id, "proposer_id": str(offer.proposer_id), "recipient_id": str(offer.recipient_id), "proposer_gives": offer.proposer_gives, "proposer_receives": offer.proposer_receives, "settled_pressure": pressure_after}, "participants", [str(offer.proposer_id), str(offer.recipient_id)])
	var committed := _commit([event], str(command.idempotency_key))
	if not bool(committed.get("ok", false)):
		_player_inventory.call("restore_state", slots_before, mappings_before)
		_player_wallet.call("restore_gold_unchecked", gold_before)
		npc_state.from_dict(npc_before)
		return committed
	offer.status = "settled"
	_offers[offer_id] = offer
	_apply_settlement_pressure(pressure_after)
	_refresh_market_pressure(game_minute)
	_wake(npc_id, 3, game_minute)
	return {"ok": true, "offer_id": offer_id, "events": committed.events, "changed_entities": ["trade_offer:" + offer_id, "player_inventory", "npc_inventory:" + npc_id], "resource_delta": {}}


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


func _has_total_player_assets(bundle: Dictionary) -> bool:
	if _player_inventory == null or _player_wallet == null or int(_player_wallet.gold) < int(bundle.gold):
		return false
	for item_id in bundle.items:
		if int(_player_inventory.call("get_item_count", str(item_id))) < int(bundle.items[item_id]):
			return false
	return true


func _has_settlement_assets(actor_id: String, bundle: Dictionary, excluded_offer_id := "") -> bool:
	var total_gold := int(_player_wallet.gold) if actor_id == "player" and _player_wallet != null else -1
	var state = null
	if actor_id != "player":
		state = _economy.call("get_npc_state", actor_id)
		if state == null:
			return false
		total_gold = int(state.gold)
	if total_gold - _reserved_gold(actor_id, excluded_offer_id) < int(bundle.gold):
		return false
	for item_id in bundle.items:
		var total := int(_player_inventory.call("get_item_count", str(item_id))) if actor_id == "player" else int(state.inventory.get(item_id, 0))
		if total - _reserved_item(actor_id, str(item_id), excluded_offer_id) < int(bundle.items[item_id]):
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
	var day := _pressure_day(game_minute)
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


func _settlement_pressure_after(offer: Dictionary, game_minute: int) -> Dictionary:
	var day := _pressure_day(game_minute)
	var day_pressure: Dictionary = (_settled_pressure.get(day, {}) as Dictionary).duplicate(true)
	_record_cash_price_signal(day_pressure, offer.proposer_gives, offer.proposer_receives)
	_record_cash_price_signal(day_pressure, offer.proposer_receives, offer.proposer_gives)
	return {"day": day, "items": day_pressure}


func _apply_settlement_pressure(snapshot: Dictionary) -> void:
	_settled_pressure[int(snapshot.day)] = (snapshot.items as Dictionary).duplicate(true)


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
	var accepted_volume := new_volume - old_volume
	if accepted_volume > 0:
		pressure.price_bias_bps = clampi(roundi((float(int(pressure.price_bias_bps) * old_volume) + float(bias * accepted_volume)) / float(new_volume)), -MAX_PRICE_BIAS_BPS, MAX_PRICE_BIAS_BPS)
	pressure.private_volume = new_volume
	day_pressure[item_id] = pressure


func _pressure_day(game_minute: int) -> int:
	var calendar_day := int(game_minute / GAME_MINUTES_PER_DAY) + 1
	return maxi(calendar_day, int(_market.last_settled_day) + 1) if _market != null else calendar_day


func _empty_pressure() -> Dictionary:
	return {"demand": 0, "supply": 0, "private_volume": 0, "price_bias_bps": 0}


func _commit(events: Array[Dictionary], key: String) -> Dictionary:
	var committed: Dictionary = _store.call("append_projected_batch", events, key, _projector)
	if not bool(committed.get("ok", false)):
		return _failure(str(committed.get("error", "event_commit_failed")))
	var committed_events: Array[Dictionary] = []
	committed_events.assign(committed.events)
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


func _integer_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and floorf(float(value)) == float(value)
