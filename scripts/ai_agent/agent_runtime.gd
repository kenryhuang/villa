extends Node

signal dialogue_ready(agent_id: String, request_id: String, speech: String)
signal dialogue_stream_started(agent_id: String, request_id: String)
signal dialogue_stream_delta(agent_id: String, request_id: String, delta: String)
signal dialogue_stream_failed(agent_id: String, request_id: String, error: String)

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
const AgentClientConfigScript = preload("res://scripts/ai_agent/agent_client_config.gd")
const AgentSessionTraceScript = preload("res://scripts/ai_agent/agent_session_trace.gd")

const VERSION := 2
const GAME_MINUTES_PER_DAY := 1080
const SAVE_DIRECTORY := "user://villa_saves/"

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
var session_trace: Node = AgentSessionTraceScript.new()

var _npc_economy: Variant
var _market: Variant
var _season: Variant
var _hud_bus: Variant
var _request_sequence := 0
var _event_bus: Node
var _save_manager: Variant
var _store_agent_session := false
var _agent_session_directory := AgentClientConfigScript.DEFAULT_SESSION_DIRECTORY
var _request_triggers: Dictionary = {}


func configure(
	npc_economy: Variant,
	market: Variant,
	season: Variant,
	hud_bus: Variant,
	client_config_path: String = AgentClientConfigScript.DEFAULT_PATH
) -> bool:
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
	if not executor.configure(registry, farm_registry, building_registry, activity_system, knowledge_registry, _npc_economy):
		return false
	gateway = AgentGatewayScript.new()
	gateway.name = "AgentGateway"
	add_child(gateway)
	session_trace.name = "AgentSessionTrace"
	add_child(session_trace)
	var client_config := AgentClientConfigScript.load_file(client_config_path)
	if not client_config.ok:
		_publish("warning", "Agent 客户端配置不可用，远程决策已关闭：%s" % str(client_config.error), {})
	else:
		_store_agent_session = bool(client_config.value.store_agent_session)
		_agent_session_directory = str(client_config.value.agent_session_directory)
		if bool(client_config.value.enabled):
			service_enabled = gateway.configure(
				str(client_config.value.service_url),
				str(client_config.value.token),
				1,
				float(client_config.value.timeout_seconds)
			)
	if not session_trace.configure(_store_agent_session, session_id, _agent_session_directory):
		_publish("warning", "Agent 调试会话文件无法创建，已退回内存记录。", {})
		session_trace.configure(false, session_id)
	if not scheduler.configure(
		registry,
		gateway,
		_build_request,
		_handle_response,
		_handle_stream_event,
		_handle_stream_failure
	):
		return false
	_connect_events()
	if service_enabled:
		gateway.sync_session(session_id, false)
	return true


func configure_save_manager(save_manager: Variant) -> bool:
	if (
		save_manager == null
		or not is_instance_valid(save_manager)
		or not save_manager.has_signal("save_completed")
		or not save_manager.has_signal("load_completed")
	):
		return false
	_save_manager = save_manager
	var save_callback := Callable(self, "_on_save_completed")
	if not save_manager.is_connected("save_completed", save_callback):
		save_manager.connect("save_completed", save_callback)
	var load_callback := Callable(self, "_on_load_completed")
	if not save_manager.is_connected("load_completed", load_callback):
		save_manager.connect("load_completed", load_callback)
	return true


func trigger_dialogue(agent_id: String, text: String = "") -> bool:
	return service_enabled and scheduler.trigger_dialogue(agent_id, text, _absolute_game_minute())


func cancel_dialogue(agent_id: String, request_id: String) -> bool:
	if str(_request_triggers.get(request_id, "")) != "dialogue":
		return false
	_request_triggers.erase(request_id)
	return gateway != null and bool(gateway.call("cancel_agent", agent_id, "dialogue_closed"))


func get_session_trace() -> Node:
	return session_trace


func is_agent_managed(agent_id: String) -> bool:
	return registry.is_agent_managed(agent_id)


func set_save_slot(slot: int) -> void:
	var next_session_id := "slot-%d" % maxi(0, slot)
	if session_id == next_session_id:
		return
	session_id = next_session_id
	_request_triggers.clear()
	if gateway != null:
		gateway.bump_epoch()
	if session_trace != null:
		if not session_trace.configure(_store_agent_session, session_id, _agent_session_directory):
			session_trace.configure(false, session_id)


func _on_save_completed(slot: int) -> void:
	set_save_slot(slot)
	if not service_enabled:
		return
	var callback := Callable(self, "_on_checkpoint_exported").bind(slot)
	if not gateway.export_checkpoint(session_id, "slot-%d" % slot, callback):
		_publish("warning", "Agent 记忆检查点导出未启动；世界存档已保留。", {"slot": slot})


func _on_checkpoint_exported(success: bool, response: Dictionary, error: String, slot: int) -> void:
	if not success or not _valid_checkpoint_record(response):
		_publish("warning", "Agent 记忆检查点导出失败：%s" % error, {"slot": slot})
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIRECTORY))
	var file := FileAccess.open(_manifest_path(slot), FileAccess.WRITE)
	if file == null:
		_publish("warning", "Agent 记忆清单无法写入；世界存档已保留。", {"slot": slot})
		return
	file.store_string(JSON.stringify(response))
	file.close()


func _on_load_completed(slot: int) -> void:
	set_save_slot(slot)
	if not service_enabled:
		_publish("warning", "Agent 服务未连接；世界已加载，角色记忆暂不可用。", {"slot": slot})
		return
	var file := FileAccess.open(_manifest_path(slot), FileAccess.READ)
	if file == null:
		gateway.sync_session(session_id, true)
		_publish("warning", "未找到 Agent 记忆检查点，已用空记忆继续加载。", {"slot": slot})
		return
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not value is Dictionary or not _valid_checkpoint_record(value):
		gateway.sync_session(session_id, true)
		_publish("warning", "Agent 记忆检查点损坏，已用空记忆继续加载。", {"slot": slot})
		return
	var record := value as Dictionary
	if str(record.session_id) != session_id:
		gateway.sync_session(session_id, true)
		_publish("warning", "Agent 记忆检查点与存档不匹配，已用空记忆继续加载。", {"slot": slot})
		return
	if not gateway.import_checkpoint(record, Callable(self, "_on_checkpoint_imported").bind(slot)):
		_publish("warning", "Agent 记忆检查点恢复未启动；世界加载不受影响。", {"slot": slot})


func _on_checkpoint_imported(success: bool, _response: Dictionary, error: String, slot: int) -> void:
	if success:
		return
	gateway.sync_session(session_id, true)
	_publish("warning", "Agent 记忆恢复失败，已用空记忆继续：%s" % error, {"slot": slot})


func _manifest_path(slot: int) -> String:
	return SAVE_DIRECTORY.path_join("save_%d.agent-memory.json" % maxi(0, slot))


func _valid_checkpoint_record(value: Dictionary) -> bool:
	return (
		typeof(value.get("path")) == TYPE_STRING
		and not str(value.path).is_empty()
		and typeof(value.get("sha256")) == TYPE_STRING
		and str(value.sha256).length() == 64
		and typeof(value.get("session_id")) == TYPE_STRING
	)


func to_dict() -> Dictionary:
	return {"version": VERSION, "session_id": session_id, "executor": executor.to_dict(), "farm": farm_registry.to_dict(), "buildings": building_registry.to_dict(), "activities": activity_system.to_dict(), "knowledge": knowledge_registry.to_dict()}


func validate_dict(value: Dictionary) -> bool:
	if value.get("version") != VERSION or typeof(value.get("session_id")) != TYPE_STRING or not value.get("executor") is Dictionary:
		return false
	var farm = FarmScript.new()
	var buildings = BuildingScript.new()
	var activities = ActivityScript.new()
	var knowledge = KnowledgeScript.new()
	return executor.validate_dict(value.executor) and value.get("farm") is Dictionary and farm.from_dict(value.farm) and value.get("buildings") is Dictionary and buildings.from_dict(value.buildings) and value.get("activities") is Dictionary and activities.from_dict(value.activities) and value.get("knowledge") is Dictionary and knowledge.from_dict(value.knowledge)


func from_dict(value: Dictionary) -> bool:
	if not validate_dict(value):
		return false
	var before := to_dict()
	if not farm_registry.from_dict(value.farm) or not building_registry.from_dict(value.buildings) or not activity_system.from_dict(value.activities) or not knowledge_registry.from_dict(value.knowledge) or not executor.from_dict(value.executor):
		farm_registry.from_dict(before.farm)
		building_registry.from_dict(before.buildings)
		activity_system.from_dict(before.activities)
		knowledge_registry.from_dict(before.knowledge)
		return false
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
	for outcome in executor.complete_due(game_minute):
		_publish_committed_outcome(str(outcome.get("agent_id", "")), outcome)
		if service_enabled:
			gateway.report_outcome(str(outcome.get("agent_id", "")), session_id, outcome)
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
	var request := AgentProtocolScript.make_decision_request("%s-%d" % [agent_id, _request_sequence], session_id, gateway.session_epoch, agent_id, trigger, game_minute, executor.world_revision, snapshot, perception_inbox.drain(agent_id), dialogue)
	_request_triggers[str(request.request_id)] = trigger
	return request


func _handle_stream_event(agent_id: String, event: Dictionary) -> void:
	if not session_trace.accept_event(event):
		_publish("warning", "%s 的 Agent 流事件无法记录。" % agent_id, {"agent_id": agent_id})
		return
	var data := event.data as Dictionary
	var request_id := str(data.request_id)
	var event_name := str(event.event)
	var trigger := str(_request_triggers.get(request_id, ""))
	if event_name == "stream.started" and trigger == "dialogue":
		dialogue_stream_started.emit(agent_id, request_id)
	elif event_name == "content.delta" and trigger == "dialogue":
		dialogue_stream_delta.emit(agent_id, request_id, str((data.payload as Dictionary).get("delta", "")))
	elif event_name == "stream.error":
		if trigger == "dialogue":
			dialogue_stream_failed.emit(agent_id, request_id, str((data.payload as Dictionary).get("code", "stream_error")))
		_request_triggers.erase(request_id)


func _handle_stream_failure(agent_id: String, request_id: String, error: String) -> void:
	if str(_request_triggers.get(request_id, "")) == "dialogue":
		dialogue_stream_failed.emit(agent_id, request_id, error)
	_request_triggers.erase(request_id)


func _handle_response(agent_id: String, response: Dictionary) -> void:
	var request_id := str(response.get("request_id", ""))
	var trigger := str(_request_triggers.get(request_id, ""))
	_request_triggers.erase(request_id)
	var checked := validator.validate(response, registry, executor.world_revision)
	if not checked.ok:
		_publish("warning", "%s 的 Agent 动作被拒绝：%s" % [agent_id, str(checked.error)], {"agent_id": agent_id})
		return
	var outcomes: Array[Dictionary] = executor.execute_batch(checked.value, _absolute_game_minute())
	for outcome in outcomes:
		if outcome.status in ["rejected", "failed"]:
			_publish("warning", "%s 的动作失败：%s" % [agent_id, str(outcome.get("failure_code", "unknown"))], {"agent_id": agent_id})
		else:
			_publish_committed_outcome(agent_id, outcome)
		if service_enabled:
			gateway.report_outcome(agent_id, session_id, outcome)
	if trigger == "dialogue" and response.has("speech") and not str(response.speech).is_empty():
		dialogue_ready.emit(agent_id, request_id, str(response.speech))


func _publish_committed_outcome(agent_id: String, outcome: Dictionary) -> void:
	var text := str(outcome.get("hud_message", ""))
	if text.is_empty():
		return
	_publish("success", text, {
		"agent_id": agent_id,
		"decision_id": str(outcome.get("decision_id", "")),
		"changed_entities": outcome.get("changed_entities", []).duplicate(),
	})


func _publish(severity: String, text: String, metadata: Dictionary) -> void:
	if _hud_bus != null and _hud_bus.has_method("publish"):
		_hud_bus.call("publish", "agent", severity, text, metadata)


func _absolute_game_minute() -> int:
	return maxi(0, int(_season.total_days) - 1) * GAME_MINUTES_PER_DAY + maxi(0, int(_season.hour) - 6) * 60 + int(_season.minute)
