extends RefCounted

const AgentRegistryScript = preload("res://scripts/ai_agent/agent_registry.gd")
const AgentPerceptionInboxScript = preload("res://scripts/ai_agent/agent_perception_inbox.gd")
const AgentSchedulerScript = preload("res://scripts/ai_agent/agent_scheduler.gd")
const AgentGatewayScript = preload("res://scripts/ai_agent/agent_gateway.gd")

class FakeGateway:
	extends RefCounted
	var requests: Array[Dictionary] = []
	var callbacks: Dictionary = {}

	func request_decision(agent_id: String, request: Dictionary, callback: Callable) -> bool:
		if callbacks.has(agent_id):
			return false
		requests.append({"agent_id": agent_id, "request": request.duplicate(true)})
		callbacks[agent_id] = callback
		return true

	func succeed(agent_id: String, response: Dictionary = {}) -> void:
		var callback: Callable = callbacks.get(agent_id, Callable())
		callbacks.erase(agent_id)
		callback.call(true, response, "")


func run(assertions: TestAssert, _tree: SceneTree) -> void:
	_test_perception_coalescing(assertions)
	_test_role_schedule_and_backpressure(assertions)
	_test_gateway_configuration(assertions)


func _test_perception_coalescing(assertions: TestAssert) -> void:
	var inbox := AgentPerceptionInboxScript.new()
	inbox.push_event("lao_li", "market", "salt", {"price": 7}, 100, 1)
	inbox.push_event("lao_li", "market", "salt", {"price": 9}, 105, 2)
	inbox.push_event("lao_li", "market", "grain", {"price": 30}, 103, 1)
	var events := inbox.drain("lao_li")
	assertions.equal(events.size(), 2, "same market entity coalesces")
	assertions.equal(events[0].entity_id, "salt", "higher priority event sorts first")
	assertions.equal(events[0].payload.price, 9, "coalesced event keeps latest value")
	assertions.equal(inbox.drain("lao_li"), [], "drain consumes events")


func _test_role_schedule_and_backpressure(assertions: TestAssert) -> void:
	var registry := AgentRegistryScript.new()
	registry.load_defaults()
	var gateway := FakeGateway.new()
	var handled: Array[Dictionary] = []
	var scheduler := AgentSchedulerScript.new()
	assertions.truthy(scheduler.configure(
		registry,
		gateway,
		func(agent_id: String, trigger: String, game_minute: int, dialogue: String): return {"agent_id": agent_id, "trigger": trigger, "game_minute": game_minute, "dialogue_input": dialogue},
		func(agent_id: String, response: Dictionary): handled.append({"agent_id": agent_id, "response": response})
	), "scheduler configures")
	scheduler.advance_to(60)
	assertions.equal(gateway.requests.map(func(value): return value.agent_id), ["farmer_ahe", "lao_li"], "farmer and merchant are due by one hour")
	scheduler.advance_to(600)
	assertions.equal(gateway.requests.size(), 3, "time jump adds only the previously idle explorer")
	assertions.equal(gateway.requests.filter(func(value): return value.agent_id == "farmer_ahe").size(), 1, "in-flight farmer is not duplicated")
	assertions.truthy(scheduler.trigger_dialogue("farmer_ahe", "你好", 601), "dialogue queues behind in-flight decision")
	gateway.succeed("farmer_ahe", {"tool_name": "wait"})
	assertions.equal(gateway.requests.size(), 4, "queued dialogue dispatches immediately after current request")
	assertions.equal(gateway.requests[3].request.trigger, "dialogue", "queued request keeps dialogue priority")
	gateway.succeed("farmer_ahe", {"speech": "你好"})
	assertions.equal(handled.size(), 2, "matching responses are handled")
	gateway.succeed("lao_li", {"tool_name": "wait"})
	scheduler.advance_to(600)
	var explorer_count := gateway.requests.filter(func(value): return value.agent_id == "xuezhe_lin").size()
	assertions.equal(explorer_count, 1, "large time jump creates one explorer catch-up decision")


func _test_gateway_configuration(assertions: TestAssert) -> void:
	var gateway := AgentGatewayScript.new()
	assertions.truthy(not gateway.configure("", "", 1), "gateway rejects empty base URL")
	assertions.truthy(gateway.configure("http://127.0.0.1:8787", "session-token", 2), "gateway accepts local service config")
	assertions.equal(gateway.session_epoch, 2, "gateway exposes active epoch")
	gateway.cancel_all()
	gateway.free()
