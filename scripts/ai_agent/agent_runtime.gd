extends Node

signal dialogue_ready(agent_id: String, speech: String)

const AgentRegistryScript = preload("res://scripts/ai_agent/agent_registry.gd")
const AgentGatewayScript = preload("res://scripts/ai_agent/agent_gateway.gd")
const AgentProtocolScript = preload("res://scripts/ai_agent/agent_protocol.gd")
const AgentPerceptionInboxScript = preload("res://scripts/ai_agent/agent_perception_inbox.gd")
const AgentSchedulerScript = preload("res://scripts/ai_agent/agent_scheduler.gd")
const AgentValidatorScript = preload("res://scripts/ai_agent/agent_action_validator.gd")
const AgentExecutorScript = preload("res://scripts/ai_agent/agent_action_executor_router.gd")
const FarmScript = preload("res://scripts/systems/npc_farm_registry.gd")
const BuildingScript = preload("res://scripts/systems/npc_building_registry.gd")
const ActivityScript = preload("res://scripts/systems/npc_activity_system.gd")
const KnowledgeScript = preload("res://scripts/systems/explorer_knowledge_registry.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")

const VERSION := 1
const GAME_MINUTES_PER_DAY := 1080

var registry = AgentRegistryScript.new()
var farm_registry = FarmScript.new()
var building_registry = BuildingScript.new()
var activity_system = ActivityScript.new()
var knowledge_registry = KnowledgeScript.new()
var perception_inbox = AgentPerceptionInboxScript.new()
var validator = AgentValidatorScript.new()
var executor = AgentExecutorScript.new()
var scheduler = AgentSchedulerScript.new()
var gateway: Node
var session_id := "slot-0"
var service_enabled := false

var _npc_economy: Variant
var _market: Variant
var _season: Variant
var _hud_bus: Variant
var _request_sequence := 0
var _event_bus: Node


func configure(npc_economy: Variant, market: Variant, season: Variant, hud_bus: Variant) -> bool:
	if npc_economy == null or market == null or season == null or not registry.load_defaults():
		return false
	_npc_economy = npc_economy
	_market = market
	_season = season
	_hud_bus = hud_bus
	if farm_registry.get_plot("farmer_ahe", 0).is_empty() and not farm_registry.configure_farm("farmer_ahe", 12):
		return false
	for agent_id in registry.get_agent_ids():
		if not bool(_npc_economy.call("set_agent_managed", agent_id, true)):
			return false
	if not executor.configure(registry, farm_registry, building_registry, activity_system, knowledge_registry, _npc_economy, _publish_action_message):
		return false
	gateway = AgentGatewayScript.new()
	gateway.name = "AgentGateway"
	add_child(gateway)
	var service_url := OS.get_environment("AGENT_SERVICE_URL").strip_edges()
	if not service_url.is_empty():
		service_enabled = gateway.configure(service_url, OS.get_environment("AGENT_SERVICE_TOKEN"), 1)
	if not scheduler.configure(registry, gateway, _build_request, _handle_response):
		return false
	_connect_events()
	return true


func trigger_dialogue(agent_id: String, text: String = "") -> bool:
	return service_enabled and scheduler.trigger_dialogue(agent_id, text, _absolute_game_minute())


func is_agent_managed(agent_id: String) -> bool:
	return registry.is_agent_managed(agent_id)


func set_save_slot(slot: int) -> void:
	session_id = "slot-%d" % maxi(0, slot)


func to_dict() -> Dictionary:
	return {"version": VERSION, "world_revision": executor.world_revision, "session_id": session_id, "farm": farm_registry.to_dict(), "buildings": building_registry.to_dict(), "activities": activity_system.to_dict(), "knowledge": knowledge_registry.to_dict()}


func validate_dict(value: Dictionary) -> bool:
	if value.get("version") != VERSION or int(value.get("world_revision", -1)) < 0 or typeof(value.get("session_id")) != TYPE_STRING:
		return false
	var farm = FarmScript.new()
	var buildings = BuildingScript.new()
	var activities = ActivityScript.new()
	var knowledge = KnowledgeScript.new()
	return value.get("farm") is Dictionary and farm.from_dict(value.farm) and value.get("buildings") is Dictionary and buildings.from_dict(value.buildings) and value.get("activities") is Dictionary and activities.from_dict(value.activities) and value.get("knowledge") is Dictionary and knowledge.from_dict(value.knowledge)


func from_dict(value: Dictionary) -> bool:
	if not validate_dict(value):
		return false
	var before := to_dict()
	if not farm_registry.from_dict(value.farm) or not building_registry.from_dict(value.buildings) or not activity_system.from_dict(value.activities) or not knowledge_registry.from_dict(value.knowledge):
		farm_registry.from_dict(before.farm)
		building_registry.from_dict(before.buildings)
		activity_system.from_dict(before.activities)
		knowledge_registry.from_dict(before.knowledge)
		return false
	executor.world_revision = int(value.world_revision)
	session_id = str(value.session_id)
	if gateway != null:
		gateway.bump_epoch()
	return true


func _connect_events() -> void:
	_event_bus = get_node_or_null("/root/EventBus")
	if _event_bus == null:
		return
	if not _event_bus.time_changed.is_connected(_on_time_changed):
		_event_bus.time_changed.connect(_on_time_changed)
	if not _event_bus.market_price_changed.is_connected(_on_market_price_changed):
		_event_bus.market_price_changed.connect(_on_market_price_changed)
	if not _event_bus.market_stock_changed.is_connected(_on_market_stock_changed):
		_event_bus.market_stock_changed.connect(_on_market_stock_changed)


func _on_time_changed(_hour: int, _minute: int) -> void:
	var game_minute := _absolute_game_minute()
	executor.complete_due(game_minute)
	if service_enabled:
		scheduler.advance_to(game_minute)


func _on_market_price_changed(item_id: String, price: int) -> void:
	_queue_market_event(item_id, {"price": price}, 2)


func _on_market_stock_changed(item_id: String, stock: int) -> void:
	_queue_market_event(item_id, {"stock": stock}, 1 if stock > 3 else 3)


func _queue_market_event(item_id: String, payload: Dictionary, priority: int) -> void:
	var minute := _absolute_game_minute()
	perception_inbox.push_event("lao_li", "market", item_id, payload, minute, priority)
	if service_enabled:
		scheduler.notify_event("lao_li", priority, minute)


func _build_request(agent_id: String, trigger: String, game_minute: int, dialogue: String) -> Dictionary:
	_request_sequence += 1
	var state = _npc_economy.call("get_npc_state", agent_id)
	if state == null:
		return {}
	var market_snapshot: Dictionary = {}
	for definition in GameDataScript.get_market_items():
		var item_id := str(definition.id)
		market_snapshot[item_id] = _market.call("get_item_state", item_id)
	var snapshot := {"game_time": {"day": int(_season.total_days), "hour": int(_season.hour), "minute": int(_season.minute), "season": int(_season.current_season)}, "self": state.to_dict(), "farm": farm_registry.to_dict().farms.get(agent_id, []), "buildings": building_registry.to_dict().buildings, "private_knowledge": knowledge_registry.get_private(agent_id), "public_knowledge": knowledge_registry.to_dict().public, "market": market_snapshot}
	return AgentProtocolScript.make_decision_request("%s-%d" % [agent_id, _request_sequence], session_id, gateway.session_epoch, agent_id, trigger, game_minute, executor.world_revision, snapshot, perception_inbox.drain(agent_id), dialogue)


func _handle_response(agent_id: String, response: Dictionary) -> void:
	var checked := validator.validate(response, registry, executor.world_revision)
	if not checked.ok:
		_publish("warning", "%s 的 Agent 动作被拒绝：%s" % [agent_id, str(checked.error)], {"agent_id": agent_id})
		return
	var outcome: Dictionary = executor.execute(checked.value, _absolute_game_minute())
	if outcome.status in ["rejected", "failed"]:
		_publish("warning", "%s 的动作失败：%s" % [agent_id, str(outcome.get("failure_code", "unknown"))], {"agent_id": agent_id})
	if response.has("speech") and not str(response.speech).is_empty():
		dialogue_ready.emit(agent_id, str(response.speech))
	if service_enabled:
		gateway.report_outcome(agent_id, session_id, outcome)


func _publish_action_message(text: String) -> void:
	_publish("success", text, {})


func _publish(severity: String, text: String, metadata: Dictionary) -> void:
	if _hud_bus != null and _hud_bus.has_method("publish"):
		_hud_bus.call("publish", "agent", severity, text, metadata)


func _absolute_game_minute() -> int:
	return maxi(0, int(_season.total_days) - 1) * GAME_MINUTES_PER_DAY + maxi(0, int(_season.hour) - 6) * 60 + int(_season.minute)
