extends RefCounted

const AgentRegistryScript = preload("res://scripts/ai_agent/agent_registry.gd")
const AgentActionValidatorScript = preload("res://scripts/ai_agent/agent_action_validator.gd")
const AgentActionExecutorScript = preload("res://scripts/ai_agent/agent_action_executor_router.gd")
const FarmScript = preload("res://scripts/systems/npc_farm_registry.gd")
const BuildingScript = preload("res://scripts/systems/npc_building_registry.gd")
const ActivityScript = preload("res://scripts/systems/npc_activity_system.gd")
const KnowledgeScript = preload("res://scripts/systems/explorer_knowledge_registry.gd")
const MarketScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomyScript = preload("res://scripts/systems/npc_economy_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_validator(assertions)
	_test_real_farmer_flow(assertions, tree)
	_test_agent_managed_skips_daily_autonomy(assertions, tree)


func _test_validator(assertions: TestAssert) -> void:
	var registry := AgentRegistryScript.new()
	registry.load_defaults()
	var validator := AgentActionValidatorScript.new()
	assertions.truthy(validator.validate(_intent("farmer_ahe", "plant", {"plot": 0, "seed_item_id": "carrot_seed"}, 4, "p1"), registry, 4).ok, "valid role action passes")
	assertions.equal(validator.validate(_intent("lao_li", "plant", {}, 4, "p2"), registry, 4).error, "unauthorized_tool", "merchant cannot plant")
	assertions.equal(validator.validate(_intent("farmer_ahe", "plant", {}, 3, "p3"), registry, 4).error, "stale_world_revision", "stale revision rejects")
	assertions.equal(validator.validate(_intent("farmer_ahe", "plant", {"plot": 0, "seed_item_id": "invented_seed"}, 4, "p4"), registry, 4).error, "invalid_arguments", "unknown seed rejects")
	assertions.equal(validator.validate(_intent("farmer_ahe", "buy", {"item_id": "wood", "quantity": 101}, 4, "p5"), registry, 4).error, "invalid_arguments", "oversized trade rejects")
	assertions.equal(validator.validate(_intent("farmer_ahe", "build", {"building_type": "castle", "building_id": "x"}, 4, "p6"), registry, 4).error, "invalid_arguments", "arbitrary building type rejects")
	assertions.equal(validator.validate(_intent("farmer_ahe", "till", {"plot": 0, "extra": true}, 4, "p7"), registry, 4).error, "invalid_arguments", "unexpected command fields reject")
	var network_intent: Dictionary = JSON.parse_string(JSON.stringify(
		_intent("farmer_ahe", "till", {"plot": 0}, 4, "network-integer")
	))
	assertions.equal(typeof(network_intent.arguments.plot), TYPE_FLOAT, "JSON transport decodes numeric arguments as floats")
	assertions.truthy(validator.validate(network_intent, registry, 4).ok, "integer-valued JSON number passes")
	var fractional_intent: Dictionary = JSON.parse_string(JSON.stringify(
		_intent("farmer_ahe", "till", {"plot": 0.5}, 4, "network-fraction")
	))
	assertions.equal(validator.validate(fractional_intent, registry, 4).error, "invalid_arguments", "fractional JSON number rejects")


func _test_real_farmer_flow(assertions: TestAssert, tree: SceneTree) -> void:
	var market := MarketScript.new()
	var economy := NpcEconomyScript.new()
	tree.root.add_child(market)
	tree.root.add_child(economy)
	assertions.truthy(market.configure(GameDataScript.get_market_items()), "Agent market configures")
	assertions.truthy(economy.configure(market, GameDataScript.get_npc_economy_profiles(), []), "Agent NPC economy configures")
	var registry := AgentRegistryScript.new()
	registry.load_defaults()
	var farm := FarmScript.new()
	farm.configure_farm("farmer_ahe", 12)
	var messages: Array[String] = []
	var executor := AgentActionExecutorScript.new()
	executor.configure(registry, farm, BuildingScript.new(), ActivityScript.new(), KnowledgeScript.new(), economy, func(text: String): messages.append(text))
	var state = economy.get_npc_state("farmer_ahe")
	assertions.equal(state.inventory.carrot_seed, 6, "farmer starts with carrot seed")
	assertions.equal(executor.execute(_intent("farmer_ahe", "till", {"plot": 0}, 0, "till-1"), 100).status, "completed", "till commits")
	var plant := executor.execute(_intent("farmer_ahe", "plant", {"plot": 0, "seed_item_id": "carrot_seed"}, 1, "plant-1"), 100)
	assertions.equal(plant.status, "completed", "plant commits")
	assertions.equal(state.inventory.carrot_seed, 5, "plant consumes NPC seed")
	assertions.equal(executor.execute(_intent("farmer_ahe", "harvest", {"plot": 0}, 2, "harvest-early"), 159).status, "rejected", "immature harvest rejects")
	var harvest := executor.execute(_intent("farmer_ahe", "harvest", {"plot": 0}, 2, "harvest-1"), 160)
	assertions.equal(harvest.status, "completed", "mature harvest commits")
	assertions.equal(state.inventory.carrot, 4, "harvest enters NPC inventory")
	assertions.equal(farm.get_plot("farmer_ahe", 0).state, "tilled", "harvested plot can replant")
	var duplicate := executor.execute(_intent("farmer_ahe", "harvest", {"plot": 0}, 3, "harvest-1"), 161)
	assertions.equal(duplicate, harvest, "duplicate idempotency returns original outcome")
	assertions.equal(state.inventory.carrot, 4, "duplicate harvest adds no crop")
	var restored_executor := AgentActionExecutorScript.new()
	restored_executor.configure(registry, farm, BuildingScript.new(), ActivityScript.new(), KnowledgeScript.new(), economy)
	assertions.truthy(restored_executor.from_dict(executor.to_dict()), "executor idempotency state restores")
	var restored_duplicate := restored_executor.execute(_intent("farmer_ahe", "harvest", {"plot": 0}, 3, "harvest-1"), 162)
	assertions.equal(restored_duplicate, harvest, "duplicate remains idempotent after save restore")
	assertions.equal(state.inventory.carrot, 4, "restored duplicate adds no crop")
	assertions.equal(messages.size(), 3, "only committed till plant harvest publish HUD")
	var travel := executor.execute(_intent("xuezhe_lin", "travel", {"region_id": "creek", "duration_minutes": 60}, 3, "travel-1"), 200)
	assertions.equal(travel.status, "in_progress", "travel starts as a real timed activity")
	assertions.equal(executor.complete_due(259), [], "travel cannot complete early")
	var completed_travel := executor.complete_due(260)
	assertions.equal(completed_travel.size(), 1, "travel completes once")
	assertions.equal(completed_travel[0].idempotency_key, "travel-1", "completion keeps decision idempotency key")
	assertions.equal(executor.execute(_intent("xuezhe_lin", "travel", {"region_id": "creek", "duration_minutes": 60}, 4, "travel-1"), 261), completed_travel[0], "completed activity remains idempotent")
	economy.free()
	market.free()


func _test_agent_managed_skips_daily_autonomy(assertions: TestAssert, tree: SceneTree) -> void:
	var market := MarketScript.new()
	var economy := NpcEconomyScript.new()
	tree.root.add_child(market)
	tree.root.add_child(economy)
	market.configure(GameDataScript.get_market_items())
	var profile := GameDataScript.get_npc_economy_profiles().filter(func(value): return value.id == "lao_li")
	economy.configure(market, profile, [])
	economy.set_agent_managed("lao_li", true)
	var before := economy.get_npc_state("lao_li").to_dict()
	assertions.truthy(economy.simulate_day(1), "managed economy advances day")
	assertions.equal(economy.get_npc_state("lao_li").to_dict().inventory, before.inventory, "managed NPC skips autonomous inventory mutations")
	assertions.equal(economy.get_npc_state("lao_li").to_dict().gold, before.gold, "managed NPC skips autonomous gold mutations")
	economy.free()
	market.free()


func _intent(agent_id: String, tool_name: String, arguments: Dictionary, revision: int, key: String) -> Dictionary:
	return {
		"protocol_version": 1, "decision_id": "decision-" + key, "request_id": "request-" + key,
		"agent_id": agent_id, "expected_revision": revision, "idempotency_key": key,
		"tool_name": tool_name, "tool_version": 1, "arguments": arguments,
		"decision_summary": "test",
	}
