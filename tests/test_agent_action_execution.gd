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
	_test_batch_stop_rules(assertions, tree)
	_test_agent_managed_skips_daily_autonomy(assertions, tree)


func _test_validator(assertions: TestAssert) -> void:
	var registry := AgentRegistryScript.new()
	registry.load_defaults()
	var validator := AgentActionValidatorScript.new()
	assertions.truthy(validator.validate(_intent("farmer_ahe", "plant", {"plot": 0, "seed_item_id": "carrot_seed"}, 4, "p1"), registry, 4).ok, "valid role action passes")
	assertions.equal(validator.validate(_intent("lao_li", "plant", {}, 4, "p2"), registry, 4).error, "unauthorized_tool", "merchant cannot plant")
	assertions.truthy(validator.validate(_intent("farmer_ahe", "plant", {"plot": 0, "seed_item_id": "carrot_seed"}, 3, "p3"), registry, 4).ok, "old revision remains valid for current-state checks")
	assertions.equal(validator.validate(_intent("farmer_ahe", "plant", {"plot": 0, "seed_item_id": "invented_seed"}, 4, "p4"), registry, 4).error, "invalid_arguments", "unknown seed rejects")
	assertions.equal(validator.validate(_intent("farmer_ahe", "buy", {"item_id": "wood", "quantity": 101}, 4, "p5"), registry, 4).error, "invalid_arguments", "oversized trade rejects")
	assertions.equal(validator.validate(_intent("farmer_ahe", "build", {"building_type": "castle", "building_id": "x"}, 4, "p6"), registry, 4).error, "invalid_arguments", "arbitrary building type rejects")
	assertions.equal(validator.validate(_intent("farmer_ahe", "till", {"plot": 0, "extra": true}, 4, "p7"), registry, 4).error, "invalid_arguments", "unexpected command fields reject")
	var network_intent: Dictionary = JSON.parse_string(JSON.stringify(
		_intent("farmer_ahe", "till", {"plot": 0}, 4, "network-integer")
	))
	assertions.equal(typeof(network_intent.actions[0].arguments.plot), TYPE_FLOAT, "JSON transport decodes numeric arguments as floats")
	assertions.truthy(validator.validate(network_intent, registry, 4).ok, "integer-valued JSON number passes")
	var fractional_intent: Dictionary = JSON.parse_string(JSON.stringify(
		_intent("farmer_ahe", "till", {"plot": 0.5}, 4, "network-fraction")
	))
	assertions.equal(validator.validate(fractional_intent, registry, 4).error, "invalid_arguments", "fractional JSON number rejects")
	assertions.truthy(validator.validate(_batch_intent("farmer_ahe", [], 0, "empty"), registry, 9).ok, "empty action batch is valid")
	var four_actions := []
	for index in range(4):
		four_actions.append(_action("speak", {}, "four-%d" % index))
	assertions.equal(validator.validate(_batch_intent("farmer_ahe", four_actions, 0, "four"), registry, 0).error, "invalid_actions", "four actions reject")
	assertions.equal(validator.validate(_batch_intent("farmer_ahe", [_action("wait", {}, "wait"), _action("speak", {}, "speak")], 0, "wait-many"), registry, 0).error, "wait_must_be_exclusive", "wait must be the only action")
	var duplicate := _action("speak", {}, "duplicate")
	assertions.equal(validator.validate(_batch_intent("farmer_ahe", [duplicate, duplicate], 0, "duplicates"), registry, 0).error, "duplicate_action_id", "duplicate action IDs reject")
	var legacy := _intent("farmer_ahe", "speak", {}, 0, "legacy")
	legacy.protocol_version = 1
	assertions.equal(validator.validate(legacy, registry, 0).error, "invalid_protocol_version", "v1 action intent rejects")


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
	var prepared: Array[Dictionary] = executor.execute_batch(_batch_intent("farmer_ahe", [
		_action("till", {"plot": 0}, "till-1"),
		_action("plant", {"plot": 0, "seed_item_id": "carrot_seed"}, "plant-1"),
	], 99, "prepare"), 100)
	assertions.equal(prepared.size(), 2, "multi-action preparation executes in order")
	assertions.equal(prepared[0].status, "completed", "till commits")
	var plant := prepared[1]
	assertions.equal(plant.status, "completed", "plant commits")
	assertions.equal(state.inventory.carrot_seed, 5, "plant consumes NPC seed")
	assertions.equal(_execute_one(executor, _intent("farmer_ahe", "harvest", {"plot": 0}, 2, "harvest-early"), 159).status, "rejected", "immature harvest rejects")
	var harvest := _execute_one(executor, _intent("farmer_ahe", "harvest", {"plot": 0}, 2, "harvest-1"), 160)
	assertions.equal(harvest.status, "completed", "mature harvest commits")
	assertions.equal(state.inventory.carrot, 4, "harvest enters NPC inventory")
	assertions.equal(farm.get_plot("farmer_ahe", 0).state, "tilled", "harvested plot can replant")
	var duplicate_outcome := _execute_one(executor, _intent("farmer_ahe", "harvest", {"plot": 0}, 3, "harvest-1"), 161)
	assertions.equal(duplicate_outcome, harvest, "duplicate idempotency returns original outcome")
	assertions.equal(state.inventory.carrot, 4, "duplicate harvest adds no crop")
	var restored_executor := AgentActionExecutorScript.new()
	restored_executor.configure(registry, farm, BuildingScript.new(), ActivityScript.new(), KnowledgeScript.new(), economy)
	assertions.truthy(restored_executor.from_dict(executor.to_dict()), "executor idempotency state restores")
	var restored_duplicate := _execute_one(restored_executor, _intent("farmer_ahe", "harvest", {"plot": 0}, 3, "harvest-1"), 162)
	assertions.equal(restored_duplicate, harvest, "duplicate remains idempotent after save restore")
	assertions.equal(state.inventory.carrot, 4, "restored duplicate adds no crop")
	assertions.equal(messages.size(), 3, "only committed till plant harvest publish HUD")
	var travel := _execute_one(executor, _intent("xuezhe_lin", "travel", {"region_id": "creek", "duration_minutes": 60}, 3, "travel-1"), 200)
	assertions.equal(travel.status, "in_progress", "travel starts as a real timed activity")
	assertions.equal(executor.complete_due(259), [], "travel cannot complete early")
	var completed_travel := executor.complete_due(260)
	assertions.equal(completed_travel.size(), 1, "travel completes once")
	assertions.equal(completed_travel[0].idempotency_key, "v2:travel-1", "completion keeps action idempotency key")
	assertions.equal(_execute_one(executor, _intent("xuezhe_lin", "travel", {"region_id": "creek", "duration_minutes": 60}, 4, "travel-1"), 261), completed_travel[0], "completed activity remains idempotent")
	economy.free()
	market.free()


func _test_batch_stop_rules(assertions: TestAssert, tree: SceneTree) -> void:
	var market := MarketScript.new()
	var economy := NpcEconomyScript.new()
	tree.root.add_child(market)
	tree.root.add_child(economy)
	market.configure(GameDataScript.get_market_items())
	economy.configure(market, GameDataScript.get_npc_economy_profiles(), [])
	var registry := AgentRegistryScript.new()
	registry.load_defaults()
	var farm := FarmScript.new()
	farm.configure_farm("farmer_ahe", 12)
	farm.till("farmer_ahe", 0)
	var executor := AgentActionExecutorScript.new()
	executor.configure(registry, farm, BuildingScript.new(), ActivityScript.new(), KnowledgeScript.new(), economy)
	assertions.equal(executor.execute_batch(_batch_intent("farmer_ahe", [], 0, "idle"), 100), [], "empty actions produce no outcomes")
	var stopped: Array[Dictionary] = executor.execute_batch(_batch_intent("farmer_ahe", [
		_action("plant", {"plot": 0, "seed_item_id": "carrot_seed"}, "plant-first"),
		_action("plant", {"plot": 0, "seed_item_id": "carrot_seed"}, "plant-conflict"),
		_action("till", {"plot": 1}, "must-not-run"),
	], 999, "conflict"), 100)
	assertions.equal(stopped.size(), 2, "domain failure stops later actions")
	assertions.equal(stopped[0].status, "completed", "first action remains committed")
	assertions.equal(stopped[1].failure_code, "plot_not_plantable", "conflict reports current-state domain failure")
	assertions.equal(farm.get_plot("farmer_ahe", 1).state, "untilled", "action after failure does not execute")
	var traveling: Array[Dictionary] = executor.execute_batch(_batch_intent("xuezhe_lin", [
		_action("travel", {"region_id": "creek", "duration_minutes": 60}, "travel-stop"),
		_action("survey", {"region_id": "creek"}, "survey-must-not-run"),
	], 0, "travel-batch"), 200)
	assertions.equal(traveling.size(), 1, "in-progress action stops later actions")
	assertions.equal(traveling[0].status, "in_progress", "travel enters progress")
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
	return _batch_intent(agent_id, [_action(tool_name, arguments, key)], revision, key)


func _batch_intent(agent_id: String, actions: Array, revision: int, key: String) -> Dictionary:
	return {
		"protocol_version": 2, "decision_id": "decision-" + key, "request_id": "request-" + key,
		"agent_id": agent_id, "expected_revision": revision, "actions": actions,
		"decision_summary": "test batch",
	}


func _action(tool_name: String, arguments: Dictionary, key: String) -> Dictionary:
	return {
		"action_id": "action-" + key,
		"idempotency_key": "v2:" + key,
		"tool_name": tool_name,
		"tool_version": 1,
		"arguments": arguments,
	}


func _execute_one(executor: Variant, intent: Dictionary, game_minute: int) -> Dictionary:
	var outcomes: Array[Dictionary] = executor.execute_batch(intent, game_minute)
	return outcomes[0]
