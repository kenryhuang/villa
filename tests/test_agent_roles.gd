extends RefCounted

const RegistryScript = preload("res://scripts/ai_agent/agent_registry.gd")
const RoleSystemScript = preload("res://scripts/ai_agent/agent_role_system.gd")
const EventStoreScript = preload("res://scripts/ai_agent/agent_world_event_store.gd")
const ProjectorScript = preload("res://scripts/ai_agent/agent_world_projector.gd")
const InboxScript = preload("res://scripts/ai_agent/agent_perception_inbox.gd")
const ValidatorScript = preload("res://scripts/ai_agent/agent_action_validator.gd")
const MarketScript = preload("res://scripts/systems/market_system.gd")
const EconomyScript = preload("res://scripts/systems/npc_economy_system.gd")
const BuildingScript = preload("res://scripts/systems/npc_building_registry.gd")
const KnowledgeScript = preload("res://scripts/systems/explorer_knowledge_registry.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")


func run(assertions: TestAssert) -> void:
	_test_role_change_rules_and_capabilities(assertions)


func _test_role_change_rules_and_capabilities(assertions: TestAssert) -> void:
	var registry := RegistryScript.new()
	assertions.truthy(registry.load_defaults(), "role fixture registry loads")
	var market := MarketScript.new()
	var economy := EconomyScript.new()
	market.configure(GameDataScript.get_market_items())
	economy.configure(market, GameDataScript.get_npc_economy_profiles(), GameDataScript.get_population_demand_profiles())
	var store := EventStoreScript.new()
	var inbox := InboxScript.new()
	var projector := ProjectorScript.new()
	projector.configure(registry.get_agent_ids(), _actor_profiles(registry), inbox)
	var roles := RoleSystemScript.new()
	assertions.truthy(roles.configure(registry, economy, store, projector, BuildingScript.new(), KnowledgeScript.new()), "dynamic role system configures")

	var original_soul: Dictionary = registry.get_agent("farmer_ahe").soul
	assertions.equal(roles.get_active_role("farmer_ahe"), "farmer", "Agent starts in profile role")
	assertions.truthy((roles.get_capabilities("farmer_ahe").tools as Array).has("plant"), "farmer capability contains plant")
	for general_tool in ["send_message", "counter_trade", "accept_trade", "propose_cooperation", "accept_cooperation", "propose_role_change"]:
		assertions.truthy((roles.get_capabilities("farmer_ahe").tools as Array).has(general_tool), "farmer retains general capability %s" % general_tool)

	var rejected: Dictionary = roles.propose_change("farmer_ahe", "merchant", "想经营农产品", 30, "role-reject-1")
	assertions.truthy(bool(rejected.get("ok", false)), "eligibility rejection is an audited command result")
	assertions.truthy(not bool(rejected.get("approved", true)), "missing trade experience rejects merchant role")
	assertions.equal(str(rejected.get("error", "")), "missing_event_experience", "role rejection reports concrete eligibility reason")
	assertions.equal(store.get_events_after(0).map(func(event: Dictionary): return event.event_type), ["RoleChangeProposed", "RoleChangeRejected"], "rejected role request records proposal and audit")
	assertions.equal(int(economy.get_npc_state("farmer_ahe").gold), 500, "rejected role change charges nothing")

	var trade_result: Dictionary = store.append_batch([_event("PublicMarketTradeExecuted", "market_trade", "trade-1", "farmer_ahe", {"item_id": "grain", "quantity": 1})], "role-prerequisite-trade")
	projector.apply_batch(trade_result.events)
	var changed: Dictionary = roles.propose_change("farmer_ahe", "merchant", "已有真实交易经验", 60, "role-change-1")
	assertions.truthy(bool(changed.get("approved", false)), "eligible Agent changes role")
	assertions.equal(roles.get_active_role("farmer_ahe"), "merchant", "active role updates immediately")
	assertions.equal(int(economy.get_npc_state("farmer_ahe").gold), 400, "successful merchant transition charges exact cost")
	assertions.truthy((roles.get_capabilities("farmer_ahe").tools as Array).has("propose_trade"), "new role tools activate")
	assertions.truthy((roles.get_capabilities("farmer_ahe").tools as Array).has("accept_cooperation"), "general interaction tools survive role change")
	assertions.truthy(not (roles.get_capabilities("farmer_ahe").tools as Array).has("plant"), "old role-specific tools deactivate")
	assertions.equal(registry.get_agent("farmer_ahe").soul, original_soul, "role change preserves Soul")
	assertions.equal(_actor(projector.known_actors("lao_li"), "farmer_ahe").public_role, "merchant", "role event updates public actor identity")

	var validator := ValidatorScript.new()
	var old_action := _intent("farmer_ahe", "plant", {"plot": 0, "seed_item_id": "grain_seed"})
	assertions.equal(validator.validate(old_action, registry, 0, roles).error, "role_capability_changed", "late old-role action gets specific rejection")
	var before_cooldown_gold := int(economy.get_npc_state("farmer_ahe").gold)
	var cooldown: Dictionary = roles.propose_change("farmer_ahe", "explorer", "马上再换", 61, "role-change-2")
	assertions.equal(str(cooldown.get("error", "")), "role_change_cooldown", "role cooldown prevents rapid switching")
	assertions.equal(int(economy.get_npc_state("farmer_ahe").gold), before_cooldown_gold, "cooldown rejection charges nothing")

	var saved: Dictionary = roles.to_dict()
	assertions.truthy(roles.validate_dict(saved), "role state validates")
	var registry_restored := RegistryScript.new()
	registry_restored.load_defaults()
	var restored := RoleSystemScript.new()
	assertions.truthy(restored.configure(registry_restored, economy, store, projector, BuildingScript.new(), KnowledgeScript.new()), "restored role system configures")
	assertions.truthy(restored.from_dict(saved), "role state restores")
	assertions.equal(restored.get_active_role("farmer_ahe"), "merchant", "restored role reapplies registry capabilities")
	market.free()
	economy.free()


func _actor_profiles(registry: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for agent_id_value in registry.get_agent_ids():
		var agent_id := str(agent_id_value)
		var agent: Dictionary = registry.get_agent(agent_id)
		result.append({"actor_id": agent_id, "actor_type": "npc_agent", "display_name": str(agent.display_name), "public_role": str(agent.role_id), "region_id": "village"})
	return result


func _actor(actors: Array, actor_id: String) -> Dictionary:
	for actor_value in actors:
		if str((actor_value as Dictionary).get("actor_id", "")) == actor_id:
			return actor_value
	return {}


func _intent(agent_id: String, tool_name: String, arguments: Dictionary) -> Dictionary:
	return {
		"protocol_version": 2,
		"decision_id": "late-role-decision",
		"request_id": "late-role-request",
		"agent_id": agent_id,
		"expected_revision": 0,
		"actions": [{"action_id": "late-role-action", "idempotency_key": "late-role-key", "tool_name": tool_name, "tool_version": 1, "arguments": arguments}],
		"decision_summary": "old role action",
	}


func _event(event_type: String, aggregate_type: String, aggregate_id: String, actor_id: String, payload: Dictionary) -> Dictionary:
	return {
		"event_type": event_type,
		"aggregate_type": aggregate_type,
		"aggregate_id": aggregate_id,
		"actor_id": actor_id,
		"game_minute": 45,
		"command_id": aggregate_id,
		"correlation_id": aggregate_id,
		"causation_event_id": "",
		"visibility": {"scope": "public", "actor_ids": []},
		"payload": payload,
	}
