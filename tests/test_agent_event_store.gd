extends RefCounted

const AgentWorldEventStoreScript = preload("res://scripts/ai_agent/agent_world_event_store.gd")


func run(assertions: TestAssert) -> void:
	_test_atomic_append_and_versions(assertions)
	_test_idempotency(assertions)
	_test_failed_batch_is_atomic(assertions)
	_test_serialization_and_corruption(assertions)


func _test_atomic_append_and_versions(assertions: TestAssert) -> void:
	var store = AgentWorldEventStoreScript.new()
	var result: Dictionary = store.append_batch([
		_event("PublicStatusChanged", "actor", "farmer_ahe", {"status": "working"}),
		_event("ActorRegionChanged", "actor", "farmer_ahe", {"region_id": "farm"}),
	], "v2:decision-1:action-1")
	assertions.truthy(bool(result.get("ok", false)), "event batch appends atomically")
	assertions.equal((result.events as Array).size(), 2, "append returns committed events")
	assertions.equal(result.events[0].global_sequence, 1, "first event receives first sequence")
	assertions.equal(result.events[1].global_sequence, 2, "batch sequences are contiguous")
	assertions.equal(result.events[0].aggregate_version, 1, "aggregate starts at version one")
	assertions.equal(result.events[1].aggregate_version, 2, "same aggregate advances in batch")
	assertions.equal(store.get_aggregate_version("actor", "farmer_ahe"), 2, "aggregate version is queryable")
	assertions.equal(store.get_events_after(1).size(), 1, "events can replay after a sequence")


func _test_idempotency(assertions: TestAssert) -> void:
	var store = AgentWorldEventStoreScript.new()
	var first: Dictionary = store.append_batch([
		_event("MessageSent", "message", "message-1", {"text": "你好"}),
	], "v2:decision-2:action-1")
	var duplicate: Dictionary = store.append_batch([
		_event("MessageSent", "message", "message-2", {"text": "不应写入"}),
	], "v2:decision-2:action-1")
	assertions.equal(duplicate, first, "duplicate idempotency key returns original result")
	assertions.equal(store.get_events_after(0).size(), 1, "duplicate command adds no event")
	assertions.equal(store.get_idempotent_result("v2:decision-2:action-1"), first, "idempotent result is queryable")


func _test_failed_batch_is_atomic(assertions: TestAssert) -> void:
	var store = AgentWorldEventStoreScript.new()
	var result: Dictionary = store.append_batch([
		_event("DayStarted", "public_world", "clock", {"day": 2}),
		_event("", "public_world", "clock", {"day": 3}),
	], "v2:decision-3:action-1")
	assertions.truthy(not bool(result.get("ok", true)), "invalid event rejects batch")
	assertions.equal(str(result.get("error", "")), "invalid_event_type", "batch reports stable validation error")
	assertions.equal(store.get_events_after(0), [], "failed batch commits no prefix")
	assertions.equal(store.get_aggregate_version("public_world", "clock"), 0, "failed batch advances no aggregate")
	assertions.equal(store.get_idempotent_result("v2:decision-3:action-1"), {}, "failed batch is not cached as committed")


func _test_serialization_and_corruption(assertions: TestAssert) -> void:
	var store = AgentWorldEventStoreScript.new()
	assertions.truthy(bool(store.append_batch([
		_event("SeasonChanged", "public_world", "season", {"season": 2}),
	], "v2:decision-4:action-1").ok), "serialization fixture appends")
	var saved: Dictionary = store.to_dict()
	var restored = AgentWorldEventStoreScript.new()
	assertions.truthy(restored.from_dict(saved), "event store round trips")
	assertions.equal(restored.to_dict(), saved, "event serialization is deterministic")
	var json_saved: Dictionary = JSON.parse_string(JSON.stringify(saved))
	assertions.truthy(restored.from_dict(json_saved), "event store accepts its JSON round trip")
	assertions.equal(restored.to_dict(), saved, "JSON event restore canonicalizes numeric fields")
	assertions.equal(restored.get_events_after(0)[0].payload.season, 2, "replay preserves payload")

	var corrupt_sequence := saved.duplicate(true)
	corrupt_sequence.events[0].global_sequence = 9
	assertions.truthy(not restored.validate_dict(corrupt_sequence), "corrupt global sequence rejects")
	assertions.equal(restored.to_dict(), saved, "failed validation does not mutate live store")

	var corrupt_version := saved.duplicate(true)
	corrupt_version.events[0].aggregate_version = 3
	assertions.truthy(not restored.from_dict(corrupt_version), "corrupt aggregate version rejects atomically")
	assertions.equal(restored.to_dict(), saved, "failed restore preserves live state")


func _event(
	event_type: String,
	aggregate_type: String,
	aggregate_id: String,
	payload: Dictionary
) -> Dictionary:
	return {
		"event_type": event_type,
		"aggregate_type": aggregate_type,
		"aggregate_id": aggregate_id,
		"actor_id": "system",
		"game_minute": 120,
		"command_id": "command-1",
		"correlation_id": aggregate_id,
		"causation_event_id": "",
		"visibility": {"scope": "public", "actor_ids": []},
		"payload": payload,
	}
