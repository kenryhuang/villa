extends RefCounted

const EventStoreScript = preload("res://scripts/ai_agent/agent_world_event_store.gd")
const ProjectorScript = preload("res://scripts/ai_agent/agent_world_projector.gd")
const ContextScript = preload("res://scripts/ai_agent/agent_context_projection.gd")
const InboxScript = preload("res://scripts/ai_agent/agent_perception_inbox.gd")

const AGENT_IDS := ["farmer_ahe", "lao_li", "xuezhe_lin"]


func run(assertions: TestAssert) -> void:
	_test_public_facts_reach_independent_inboxes(assertions)
	_test_actor_activity_respects_visibility(assertions)
	_test_projection_windows_do_not_truncate_store(assertions)


func _test_public_facts_reach_independent_inboxes(assertions: TestAssert) -> void:
	var fixture := _fixture()
	var committed := _append(fixture.store, [
		_event("DayStarted", "public_world", "clock", "system", {"day": 3}),
		_event("SeasonChanged", "public_world", "season", "system", {"season": 2}),
		_event("WeatherChanged", "public_world", "weather", "system", {"weather": "rain"}),
		_event("EnvironmentConditionChanged", "public_world", "soil", "system", {"condition": "wet"}),
		_event("MarketPriceChanged", "market", "grain", "system", {"item_id": "grain", "price": 19}),
	], "facts-1")
	assertions.truthy(fixture.projector.apply_batch(committed), "public fact batch projects")

	var farmer_context: Dictionary = fixture.context.build("farmer_ahe", "request-farmer")
	var merchant_context: Dictionary = fixture.context.build("lao_li", "request-merchant")
	var explorer_context: Dictionary = fixture.context.build("xuezhe_lin", "request-explorer")
	assertions.equal(farmer_context.own_event_delta.size(), 5, "farmer independently receives public facts")
	assertions.equal(merchant_context.own_event_delta.size(), 5, "merchant independently receives public facts")
	assertions.equal(explorer_context.own_event_delta.size(), 5, "explorer independently receives public facts")
	assertions.equal(farmer_context.public_world_state.game_day, 3, "context exposes current day")
	assertions.equal(farmer_context.public_world_state.season, 2, "context exposes current season")
	assertions.equal(farmer_context.public_world_state.weather, "rain", "context exposes current weather")
	assertions.equal(farmer_context.market_view.grain.price, 19, "context exposes current market fact")

	assertions.truthy(fixture.context.acknowledge("farmer_ahe", "request-farmer"), "farmer acknowledges own batch")
	assertions.equal(fixture.context.build("farmer_ahe", "request-farmer-2").own_event_delta, [], "acknowledged events leave farmer queue")
	assertions.equal(fixture.context.build("lao_li", "request-merchant").own_event_delta.size(), 5, "farmer acknowledgement does not consume merchant queue")
	assertions.truthy(fixture.context.release("xuezhe_lin", "request-explorer"), "failed explorer request releases frozen batch")
	assertions.equal(fixture.context.build("xuezhe_lin", "request-explorer-2").own_event_delta.size(), 5, "released events return to explorer context")


func _test_actor_activity_respects_visibility(assertions: TestAssert) -> void:
	var fixture := _fixture()
	var public_event := _event("PublicStatusChanged", "actor", "lao_li", "lao_li", {"status": "trading"})
	var private_event := _event("MessageSent", "message", "message-1", "lao_li", {"text": "private"})
	private_event.visibility = {"scope": "private", "actor_ids": ["farmer_ahe"]}
	var region_event := _event("PublicStatusChanged", "actor", "xuezhe_lin", "xuezhe_lin", {"status": "surveying", "region_id": "forest"})
	region_event.visibility = {"scope": "region", "actor_ids": []}
	var committed := _append(fixture.store, [public_event, private_event, region_event], "actors-1")
	assertions.truthy(fixture.projector.apply_batch(committed), "actor activity projects")

	var farmer_known: Array = fixture.projector.known_actors("farmer_ahe")
	var explorer_known: Array = fixture.projector.known_actors("xuezhe_lin")
	var lao_li_for_farmer := _actor(farmer_known, "lao_li")
	assertions.equal(lao_li_for_farmer.current_public_state.status, "trading", "known actor exposes current public state")
	assertions.equal(lao_li_for_farmer.recent_public_events.size(), 1, "known actor excludes private message")
	assertions.equal(_actor(explorer_known, "lao_li").recent_public_events.size(), 1, "public activity reaches unrelated observer")
	assertions.equal(fixture.context.build("farmer_ahe", "private-farmer").own_event_delta.size(), 2, "private recipient gets public and private events")
	assertions.equal(fixture.context.build("lao_li", "private-merchant").own_event_delta.size(), 1, "private sender gets only public event when not addressed")
	assertions.equal(fixture.context.build("xuezhe_lin", "private-explorer").own_event_delta.size(), 2, "forest actor gets own regional event")
	assertions.equal(_actor(farmer_known, "xuezhe_lin").recent_public_events.size(), 0, "different region cannot observe regional activity")


func _test_projection_windows_do_not_truncate_store(assertions: TestAssert) -> void:
	var fixture := _fixture()
	var events: Array[Dictionary] = []
	for index in range(70):
		events.append(_event("MarketPriceChanged", "market", "grain", "lao_li", {"item_id": "grain", "price": index + 1, "sample": index}))
	var committed := _append(fixture.store, events, "window-1")
	assertions.truthy(fixture.projector.apply_batch(committed), "large public batch projects")
	assertions.equal(fixture.projector.global_public_events(100).size(), 64, "global projection retains sixty-four events")
	assertions.equal(fixture.context.build("farmer_ahe", "window-request").global_public_events.size(), 24, "context includes at most twenty-four global events")
	assertions.equal(fixture.projector.actor_public_events("lao_li", "farmer_ahe", 100).size(), 32, "actor projection retains thirty-two events")
	assertions.equal(_actor(fixture.projector.known_actors("farmer_ahe"), "lao_li").recent_public_events.size(), 12, "known actor exposes at most twelve events")
	assertions.equal(fixture.store.get_events_after(0).size(), 70, "projection windows never truncate immutable event store")


func _fixture() -> Dictionary:
	var store = EventStoreScript.new()
	var inbox = InboxScript.new()
	var projector = ProjectorScript.new()
	projector.configure(AGENT_IDS, [
		{"actor_id": "farmer_ahe", "actor_type": "npc_agent", "display_name": "阿禾", "public_role": "farmer", "region_id": "farm"},
		{"actor_id": "lao_li", "actor_type": "npc_agent", "display_name": "老李", "public_role": "merchant", "region_id": "village"},
		{"actor_id": "xuezhe_lin", "actor_type": "npc_agent", "display_name": "学者林", "public_role": "explorer", "region_id": "forest"},
		{"actor_id": "player", "actor_type": "player", "display_name": "玩家", "public_role": "farmer", "region_id": "farm"},
	], inbox)
	var context = ContextScript.new()
	context.configure(projector, inbox)
	return {"store": store, "inbox": inbox, "projector": projector, "context": context}


func _append(store: Variant, events: Array[Dictionary], key: String) -> Array[Dictionary]:
	var result: Dictionary = store.append_batch(events, key)
	return result.get("events", []) as Array[Dictionary]


func _event(
	event_type: String,
	aggregate_type: String,
	aggregate_id: String,
	actor_id: String,
	payload: Dictionary
) -> Dictionary:
	return {
		"event_type": event_type,
		"aggregate_type": aggregate_type,
		"aggregate_id": aggregate_id,
		"actor_id": actor_id,
		"game_minute": 180,
		"command_id": "command-1",
		"correlation_id": aggregate_id,
		"causation_event_id": "",
		"visibility": {"scope": "public", "actor_ids": []},
		"payload": payload,
	}


func _actor(actors: Array, actor_id: String) -> Dictionary:
	for actor_value in actors:
		var actor := actor_value as Dictionary
		if str(actor.get("actor_id", "")) == actor_id:
			return actor
	return {}
