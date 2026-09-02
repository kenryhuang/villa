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
const AgentWorldEventStoreScript = preload("res://scripts/ai_agent/agent_world_event_store.gd")
const AgentWorldProjectorScript = preload("res://scripts/ai_agent/agent_world_projector.gd")
const AgentContextProjectionScript = preload("res://scripts/ai_agent/agent_context_projection.gd")
const AgentWorldFactBridgeScript = preload("res://scripts/ai_agent/agent_world_fact_bridge.gd")
const AgentRoleSystemScript = preload("res://scripts/ai_agent/agent_role_system.gd")
const AgentInteractionSystemScript = preload("res://scripts/ai_agent/agent_interaction_system.gd")
const AgentAgreementSystemScript = preload("res://scripts/ai_agent/agent_agreement_system.gd")

const VERSION := 4
const EVENT_SCHEMA_VERSION := 1
const GAME_MINUTES_PER_DAY := 1080
const SAVE_DIRECTORY := "user://villa_saves/"

var registry = AgentRegistryScript.new()
var farm_registry = FarmScript.new()
var building_registry = BuildingScript.new()
var activity_system = ActivityScript.new()
var knowledge_registry = KnowledgeScript.new()
var perception_inbox = AgentPerceptionInboxScript.new()
var event_store = AgentWorldEventStoreScript.new()
var world_projector = AgentWorldProjectorScript.new()
var context_projection = AgentContextProjectionScript.new()
var world_fact_bridge = AgentWorldFactBridgeScript.new()
var role_system = AgentRoleSystemScript.new()
var interaction_system = AgentInteractionSystemScript.new()
var agreement_system = AgentAgreementSystemScript.new()
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
var _request_namespace := ""
var _event_bus: Node
var _save_manager: Variant
var _store_agent_session := false
var _agent_session_directory := AgentClientConfigScript.DEFAULT_SESSION_DIRECTORY
var _request_triggers: Dictionary = {}
var _farm_port: Variant
var _base_actor_profiles: Array[Dictionary] = []


func _init() -> void:
	_request_namespace = "%x-%x" % [
		int(Time.get_unix_time_from_system() * 1_000_000.0),
		get_instance_id(),
	]


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
	_base_actor_profiles.clear()
	_base_actor_profiles = _actor_profiles()
	if not _configure_world_context():
		return false
	if not role_system.configure(registry, _npc_economy, event_store, world_projector, building_registry, knowledge_registry):
		return false
	if not interaction_system.configure(_npc_economy, event_store, world_projector, Callable(self, "_wake_agent_for_interaction"), _market):
		return false
	if not agreement_system.configure(_npc_economy, interaction_system, event_store, world_projector, Callable(self, "_wake_agent_for_interaction")):
		return false
	if _farm_port != null:
		farm_registry = _farm_port
	elif farm_registry.get_plot("farmer_ahe", 0).is_empty() and not farm_registry.configure_farm("farmer_ahe", 12):
		return false
	for agent_id in registry.get_agent_ids():
		if not bool(_npc_economy.call("set_agent_managed", agent_id, true)):
			return false
	if not executor.configure(registry, farm_registry, building_registry, activity_system, knowledge_registry, _npc_economy, Callable(), role_system, interaction_system, agreement_system):
		return false
	if farm_registry.has_signal("work_finished"):
		var callback := Callable(self, "_on_farm_work_finished")
		if not farm_registry.is_connected("work_finished", callback):
			farm_registry.connect("work_finished", callback)
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


func set_farm_port(farm_port: Variant) -> bool:
	if farm_port == null or not farm_port.has_method("get_snapshot") or not farm_port.has_method("queue_batch"):
		return false
	_farm_port = farm_port
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


func configure_player_assets(inventory: Variant, wallet: Variant) -> bool:
	return interaction_system.configure_player_assets(inventory, wallet)


func get_player_interactions(agent_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for offer_value in interaction_system.list_offers("player"):
		var offer := offer_value as Dictionary
		if agent_id in [str(offer.proposer_id), str(offer.recipient_id)]:
			var record := offer.duplicate(true)
			record.interaction_id = str(offer.offer_id)
			record.interaction_type = "trade"
			record.snapshot_game_minute = _absolute_game_minute()
			result.append(record)
	for agreement_value in agreement_system.list_agreements("player"):
		var agreement := agreement_value as Dictionary
		if agent_id in (agreement.participants as Array):
			var record := agreement.duplicate(true)
			record.interaction_id = str(agreement.agreement_id)
			record.interaction_type = "cooperation"
			record.snapshot_game_minute = _absolute_game_minute()
			result.append(record)
	return result


func respond_to_player_interaction(agent_id: String, interaction_id: String, response: String, counter_terms: Dictionary = {}) -> Dictionary:
	var minute := _absolute_game_minute()
	var key := "player:%s:%s:%d" % [interaction_id, response, Time.get_ticks_usec()]
	var offer := interaction_system.get_offer(interaction_id, "player")
	if not offer.is_empty() and agent_id in [str(offer.proposer_id), str(offer.recipient_id)]:
		var tool_name := ""
		var arguments: Dictionary = {"offer_id": interaction_id}
		match response:
			"accept":
				tool_name = "accept_trade"
				arguments.player_confirmed = true
			"reject":
				tool_name = "cancel_trade" if str(offer.proposer_id) == "player" else "reject_trade"
				if tool_name == "reject_trade": arguments.reason_code = "player_rejected"
			"counter":
				if not counter_terms.get("give") is Dictionary or not counter_terms.get("receive") is Dictionary or typeof(counter_terms.get("expires_in_minutes")) != TYPE_INT:
					return {"ok": false, "error": "invalid_counter_terms"}
				tool_name = "counter_trade"
				arguments.give = (counter_terms.give as Dictionary).duplicate(true)
				arguments.receive = (counter_terms.receive as Dictionary).duplicate(true)
				arguments.expires_in_minutes = int(counter_terms.expires_in_minutes)
				arguments.note = str(counter_terms.get("counter_note", "Player counteroffer"))
			_:
				return {"ok": false, "error": "invalid_interaction_response"}
		return interaction_system.execute({"agent_id": "player", "tool_name": tool_name, "arguments": arguments, "idempotency_key": key, "action_id": key, "decision_id": key}, minute)
	var agreement := agreement_system.get_agreement(interaction_id, "player")
	if agreement.is_empty() or not agent_id in (agreement.participants as Array):
		return {"ok": false, "error": "interaction_not_found"}
	var cooperation_tool := ""
	var cooperation_arguments: Dictionary = {"agreement_id": interaction_id}
	match response:
		"accept":
			cooperation_tool = "accept_cooperation"
			cooperation_arguments.terms_version = int(agreement.terms_version)
			cooperation_arguments.player_confirmed = true
		"reject":
			cooperation_tool = "reject_cooperation"
			cooperation_arguments.reason_code = "player_rejected"
		"counter":
			if not counter_terms.get("revised_terms") is Dictionary:
				return {"ok": false, "error": "invalid_counter_terms"}
			cooperation_tool = "counter_cooperation"
			cooperation_arguments.revised_terms = (counter_terms.revised_terms as Dictionary).duplicate(true)
			cooperation_arguments.note = str(counter_terms.get("counter_note", "Player counterproposal"))
		_:
			return {"ok": false, "error": "invalid_interaction_response"}
	return agreement_system.execute({"agent_id": "player", "tool_name": cooperation_tool, "arguments": cooperation_arguments, "idempotency_key": key, "action_id": key, "decision_id": key}, minute)


func trigger_dialogue(agent_id: String, text: String = "") -> bool:
	return service_enabled and scheduler.trigger_dialogue(agent_id, text, _absolute_game_minute())


func get_in_flight_request_id(agent_id: String) -> String:
	return scheduler.get_in_flight_request_id(agent_id)


func cancel_dialogue(agent_id: String, request_id: String) -> bool:
	if str(_request_triggers.get(request_id, "")) != "dialogue":
		return false
	var cancelled := gateway != null and bool(gateway.call("cancel_agent", agent_id, "dialogue_closed"))
	if not cancelled:
		context_projection.release(agent_id, request_id)
		_request_triggers.erase(request_id)
	return cancelled


func get_session_trace() -> Node:
	return session_trace


func record_farm_lifecycle(event_name: String, record: Dictionary) -> bool:
	var request_id := str(record.get("request_id", ""))
	return (
		not request_id.is_empty()
		and session_trace.has_method("record_action_event")
		and bool(session_trace.call("record_action_event", request_id, event_name, {
			"action_id": str(record.get("action_id", "")),
			"idempotency_key": str(record.get("idempotency_key", "")),
			"tool_name": str(record.get("tool_name", "")),
			"arguments": (record.get("arguments", {}) as Dictionary).duplicate(true),
		}))
	)


func is_agent_managed(agent_id: String) -> bool:
	return registry.is_agent_managed(agent_id)


func get_agent_display_name(agent_id: String) -> String:
	var agent: Dictionary = registry.get_agent(agent_id)
	return str(agent.get("display_name", agent_id))


func get_agent_debug_settings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for agent_id_value in registry.get_agent_ids():
		var agent_id := str(agent_id_value)
		result.append({
			"agent_id": agent_id,
			"display_name": get_agent_display_name(agent_id),
			"decision_interval_hours": scheduler.get_decision_interval_hours(agent_id),
		})
	return result


func apply_agent_debug_intervals(intervals: Dictionary) -> bool:
	var agent_ids: Array = registry.get_agent_ids()
	if intervals.size() != agent_ids.size():
		return false
	for agent_id_value in agent_ids:
		var agent_id := str(agent_id_value)
		var value: Variant = intervals.get(agent_id)
		if typeof(value) != TYPE_INT or int(value) < 0 or int(value) > AgentSchedulerScript.MAX_DEBUG_INTERVAL_HOURS:
			return false
	for agent_id_value in agent_ids:
		var agent_id := str(agent_id_value)
		if not scheduler.set_decision_interval_hours(agent_id, int(intervals[agent_id])):
			return false
	return true


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
	interaction_system.refresh_market_pressure(_absolute_game_minute())
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
	return {
		"version": VERSION,
		"event_schema_version": EVENT_SCHEMA_VERSION,
		"session_id": session_id,
		"executor": executor.to_dict(),
		"farm": farm_registry.to_dict(),
		"buildings": building_registry.to_dict(),
		"activities": activity_system.to_dict(),
		"knowledge": knowledge_registry.to_dict(),
		"event_store": event_store.to_dict(),
		"projection_checkpoint": world_projector.to_dict(),
		"checkpoint_sequence": world_projector.get_last_sequence(),
		"perception_inbox": perception_inbox.to_dict(),
		"roles": role_system.to_dict(),
		"interactions": interaction_system.to_dict(),
		"agreements": agreement_system.to_dict(),
	}


func validate_dict(value: Dictionary) -> bool:
	var version := int(value.get("version", 0))
	if version not in [2, 3, VERSION] or typeof(value.get("session_id")) != TYPE_STRING or not value.get("executor") is Dictionary:
		return false
	var farm = FarmScript.new() if _farm_port == null or version == 2 else farm_registry
	var buildings = BuildingScript.new()
	var activities = ActivityScript.new()
	var knowledge = KnowledgeScript.new()
	var farm_valid := false
	if value.get("farm") is Dictionary:
		farm_valid = (
			bool(farm.call("validate_dict", value.farm))
			if farm.has_method("validate_dict")
			else bool(farm.call("from_dict", value.farm))
		)
	var legacy_valid := executor.validate_dict(value.executor) and farm_valid and value.get("buildings") is Dictionary and buildings.from_dict(value.buildings) and value.get("activities") is Dictionary and activities.from_dict(value.activities) and value.get("knowledge") is Dictionary and knowledge.from_dict(value.knowledge)
	if not legacy_valid or version < VERSION:
		return legacy_valid
	return _validate_event_sourced_state(value)


func from_dict(value: Dictionary, apply_market_pressure := true) -> bool:
	if not validate_dict(value):
		return false
	var apply_pressure_now: bool = apply_market_pressure and not (
		_save_manager != null
		and is_instance_valid(_save_manager)
		and _save_manager.has_method("is_restore_transaction_active")
		and bool(_save_manager.call("is_restore_transaction_active"))
	)
	var before := to_dict()
	var previous_session_id := session_id
	var restore_farm := true
	if _farm_port != null and int(value.version) == 2:
		farm_registry.call("clear_pending_work")
	else:
		restore_farm = bool(farm_registry.call("from_dict", value.farm))
	if not restore_farm or not building_registry.from_dict(value.buildings) or not activity_system.from_dict(value.activities) or not knowledge_registry.from_dict(value.knowledge) or not executor.from_dict(value.executor):
		if farm_registry.has_method("from_dict"):
			farm_registry.call("from_dict", before.farm)
		building_registry.from_dict(before.buildings)
		activity_system.from_dict(before.activities)
		knowledge_registry.from_dict(before.knowledge)
		return false
	if int(value.version) == VERSION:
		if not _restore_event_sourced_state(value, apply_pressure_now):
			_restore_legacy_components(before)
			role_system.from_dict(before.roles)
			session_id = previous_session_id
			return false
	else:
		if not _bootstrap_legacy_event_state(int(value.version), str(value.session_id), apply_pressure_now):
			_restore_legacy_components(before)
			role_system.from_dict(before.roles)
			session_id = previous_session_id
			return false
	session_id = str(value.session_id)
	if gateway != null:
		gateway.bump_epoch()
	return true


func _validate_event_sourced_state(value: Dictionary) -> bool:
	for field in ["event_schema_version", "event_store", "projection_checkpoint", "checkpoint_sequence", "perception_inbox", "roles", "interactions", "agreements"]:
		if not value.has(field):
			return false
	if value.event_schema_version != EVENT_SCHEMA_VERSION or not value.event_store is Dictionary or not value.projection_checkpoint is Dictionary or not value.perception_inbox is Dictionary or not value.roles is Dictionary or not value.interactions is Dictionary or not value.agreements is Dictionary:
		return false
	var restored_store = AgentWorldEventStoreScript.new()
	if not restored_store.from_dict(value.event_store):
		return false
	var last_sequence := int(value.event_store.next_global_sequence) - 1
	if not _is_nonnegative_integer(value.checkpoint_sequence) or int(value.checkpoint_sequence) > last_sequence:
		return false
	var restored_inbox = AgentPerceptionInboxScript.new()
	var restored_projector = AgentWorldProjectorScript.new()
	if not restored_projector.configure(registry.get_agent_ids(), _actor_profiles(), restored_inbox):
		return false
	var prefix: Array[Dictionary] = []
	var tail: Array[Dictionary] = []
	for event_value in restored_store.get_events_after(0):
		if int(event_value.global_sequence) <= int(value.checkpoint_sequence):
			prefix.append(event_value)
		else:
			tail.append(event_value)
	if not restored_projector.replay(prefix) or _canonical_json_value(restored_projector.to_dict()) != _canonical_json_value(value.projection_checkpoint):
		return false
	if not restored_projector.apply_batch(tail) or restored_projector.get_last_sequence() != last_sequence:
		return false
	if not restored_inbox.validate_dict(value.perception_inbox, last_sequence):
		return false
	var validation_registry = AgentRegistryScript.new()
	if not validation_registry.load_defaults():
		return false
	var restored_roles = AgentRoleSystemScript.new()
	var events: Array[Dictionary] = restored_store.get_events_after(0)
	if not restored_roles.configure(validation_registry, _npc_economy, restored_store, restored_projector, building_registry, knowledge_registry) or not restored_roles.validate_against_events(value.roles, events):
		return false
	var restored_interactions = AgentInteractionSystemScript.new()
	if not restored_interactions.configure(_npc_economy, restored_store, restored_projector, Callable(), _market) or not restored_interactions.validate_against_events(value.interactions, events):
		return false
	var restored_agreements = AgentAgreementSystemScript.new()
	if not restored_agreements.configure(_npc_economy, restored_interactions, restored_store, restored_projector) or not restored_agreements.validate_against_events(value.agreements, events):
		return false
	var expected_reservations: Variant = restored_agreements.expected_reservations(value.agreements)
	return expected_reservations != null and restored_interactions.validate_external_reservations(value.interactions, expected_reservations)


func _restore_event_sourced_state(value: Dictionary, apply_market_pressure := true) -> bool:
	var restored_store = AgentWorldEventStoreScript.new()
	if not restored_store.from_dict(value.event_store):
		return false
	var restored_inbox = AgentPerceptionInboxScript.new()
	var restored_projector = AgentWorldProjectorScript.new()
	if not restored_projector.configure(registry.get_agent_ids(), _actor_profiles(), restored_inbox):
		return false
	var all_events: Array[Dictionary] = restored_store.get_events_after(0)
	if not restored_projector.replay(all_events) or not restored_inbox.from_dict(value.perception_inbox, restored_projector.get_last_sequence()):
		return false
	var restored_context = AgentContextProjectionScript.new()
	var restored_bridge = AgentWorldFactBridgeScript.new()
	if not restored_context.configure(restored_projector, restored_inbox) or not restored_bridge.configure(restored_store, restored_projector):
		return false
	var restored_roles = AgentRoleSystemScript.new()
	if not restored_roles.configure(registry, _npc_economy, restored_store, restored_projector, building_registry, knowledge_registry):
		return false
	var restored_interactions = AgentInteractionSystemScript.new()
	if not restored_interactions.configure(_npc_economy, restored_store, restored_projector, Callable(self, "_wake_agent_for_interaction"), _market):
		return false
	if interaction_system._player_inventory != null and not restored_interactions.configure_player_assets(interaction_system._player_inventory, interaction_system._player_wallet):
		return false
	if not restored_interactions.from_dict(value.interactions, apply_market_pressure):
		return false
	var restored_agreements = AgentAgreementSystemScript.new()
	if not restored_agreements.configure(_npc_economy, restored_interactions, restored_store, restored_projector, Callable(self, "_wake_agent_for_interaction")) or not restored_agreements.from_dict(value.agreements):
		return false
	# Apply the role snapshot last: this is the only staged component that mutates
	# the shared registry used by the scheduler and validator.
	if not restored_roles.from_dict(value.roles):
		return false
	event_store = restored_store
	perception_inbox = restored_inbox
	world_projector = restored_projector
	context_projection = restored_context
	world_fact_bridge = restored_bridge
	role_system = restored_roles
	interaction_system = restored_interactions
	agreement_system = restored_agreements
	if not executor.configure(registry, farm_registry, building_registry, activity_system, knowledge_registry, _npc_economy, Callable(), role_system, interaction_system, agreement_system):
		return false
	return executor.from_dict(value.executor)


func _bootstrap_legacy_event_state(source_version: int, target_session_id: String, apply_market_pressure := true) -> bool:
	var restored_store = AgentWorldEventStoreScript.new()
	var minute := _absolute_game_minute()
	var candidate: Array[Dictionary] = [{
		"event_type": "AgentWorldBootstrapped",
		"aggregate_type": "agent_world",
		"aggregate_id": target_session_id if not target_session_id.is_empty() else "legacy",
		"actor_id": "system",
		"game_minute": minute,
		"command_id": "migrate-runtime-v%d" % source_version,
		"correlation_id": "legacy-agent-world-migration",
		"causation_event_id": "",
		"visibility": {"scope": "public", "actor_ids": []},
		"payload": {
			"source_runtime_version": source_version,
			"world_revision": executor.world_revision,
			"agent_ids": registry.get_agent_ids(),
		},
	}]
	var committed: Dictionary = restored_store.append_batch(candidate, "legacy-bootstrap:%s:v%d" % [target_session_id, source_version])
	if not bool(committed.get("ok", false)):
		return false
	var legacy_state := {
		"event_store": restored_store.to_dict(),
		"perception_inbox": _empty_inbox_state(),
		"roles": role_system.to_dict(),
		"interactions": {"version": 1, "next_offer_id": 1, "offers": [], "idempotency_results": [], "settled_pressure": [], "external_reservations": []},
		"agreements": {"version": 1, "next_agreement_id": 1, "agreements": [], "idempotency_results": [], "relationships": [], "relationship_daily_changes": []},
		"executor": executor.to_dict(),
	}
	return _restore_event_sourced_state(legacy_state, apply_market_pressure)


func _empty_inbox_state() -> Dictionary:
	var cursors: Array[Dictionary] = []
	for agent_id in registry.get_agent_ids():
		cursors.append({"agent_id": str(agent_id), "consumed_sequence": 0})
	cursors.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.agent_id) < str(right.agent_id))
	return {"version": 1, "consumption_cursors": cursors}


func _restore_legacy_components(value: Dictionary) -> void:
	if farm_registry.has_method("from_dict"):
		farm_registry.call("from_dict", value.farm)
	building_registry.from_dict(value.buildings)
	activity_system.from_dict(value.activities)
	knowledge_registry.from_dict(value.knowledge)
	executor.from_dict(value.executor)


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


func _is_nonnegative_integer(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
		and int(value) >= 0
	)


func _configure_world_context() -> bool:
	var agent_ids: Array = registry.get_agent_ids()
	var actor_profiles := _actor_profiles()
	if not world_projector.configure(agent_ids, actor_profiles, perception_inbox):
		return false
	if not context_projection.configure(world_projector, perception_inbox):
		return false
	if not world_fact_bridge.configure(event_store, world_projector):
		return false
	var existing_events: Array[Dictionary] = event_store.get_events_after(0)
	if not existing_events.is_empty():
		return world_projector.replay(existing_events)
	var minute := _absolute_game_minute()
	if not world_fact_bridge.publish_day(int(_season.total_days), minute, "bootstrap-day:%d" % int(_season.total_days)):
		return false
	if not world_fact_bridge.publish_season(int(_season.current_season), minute, "bootstrap-season:%d" % int(_season.current_season)):
		return false
	if not world_fact_bridge.publish_time(int(_season.hour), int(_season.minute), minute, "bootstrap-time:%d" % minute):
		return false
	for definition in GameDataScript.get_market_items():
		var item_id := str(definition.id)
		var market_state: Dictionary = _market.call("get_item_state", item_id)
		if not world_fact_bridge.publish_market_price(
			item_id,
			int(market_state.get("mid_price", 0)),
			minute,
			"bootstrap-market:%s" % item_id,
			market_state
		):
			return false
	return true


func _actor_profiles() -> Array[Dictionary]:
	if not _base_actor_profiles.is_empty():
		return _base_actor_profiles.duplicate(true)
	var actor_profiles: Array[Dictionary] = []
	var default_regions := {
		"farmer_ahe": "farm",
		"lao_li": "village",
		"xuezhe_lin": "forest",
	}
	for agent_id_value in registry.get_agent_ids():
		var agent_id := str(agent_id_value)
		var agent: Dictionary = registry.get_agent(agent_id)
		actor_profiles.append({
			"actor_id": agent_id,
			"actor_type": "npc_agent",
			"display_name": str(agent.get("display_name", agent_id)),
			"public_role": str(agent.get("role_id", "unknown")),
			"region_id": str(default_regions.get(agent_id, "village")),
		})
	actor_profiles.append({
		"actor_id": "player",
		"actor_type": "player",
		"display_name": "玩家",
		"public_role": "farmer",
		"region_id": "farm",
	})
	return actor_profiles


func _connect_events() -> void:
	_event_bus = get_node_or_null("/root/EventBus")
	if _event_bus == null:
		return
	if not _event_bus.time_changed.is_connected(_on_time_changed):
		_event_bus.time_changed.connect(_on_time_changed)
	if not _event_bus.day_changed.is_connected(_on_day_changed):
		_event_bus.day_changed.connect(_on_day_changed)
	if not _event_bus.season_changed.is_connected(_on_season_changed):
		_event_bus.season_changed.connect(_on_season_changed)
	if not _event_bus.market_price_changed.is_connected(_on_market_price_changed):
		_event_bus.market_price_changed.connect(_on_market_price_changed)
	if not _event_bus.market_stock_changed.is_connected(_on_market_stock_changed):
		_event_bus.market_stock_changed.connect(_on_market_stock_changed)
	if not _event_bus.market_pressure_settled.is_connected(_on_market_pressure_settled):
		_event_bus.market_pressure_settled.connect(_on_market_pressure_settled)
	if not _event_bus.weather_changed.is_connected(_on_weather_changed):
		_event_bus.weather_changed.connect(_on_weather_changed)
	if not _event_bus.environment_condition_changed.is_connected(_on_environment_condition_changed):
		_event_bus.environment_condition_changed.connect(_on_environment_condition_changed)


func _on_time_changed(hour: int, minute: int) -> void:
	var game_minute := _absolute_game_minute()
	if minute == 0:
		world_fact_bridge.publish_time(hour, minute, game_minute, "time:%d" % game_minute)
	for expired in interaction_system.expire_due(game_minute):
		if _event_bus != null:
			_event_bus.agent_interaction_changed.emit(str(expired.get("offer_id", "")), "expired")
	for expired in agreement_system.expire_due(game_minute):
		if _event_bus != null:
			_event_bus.agent_interaction_changed.emit(str(expired.get("agreement_id", "")), "failed")
	for outcome in executor.complete_due(game_minute):
		_record_world_action_outcome(outcome)
		agreement_system.record_action_outcome(outcome, game_minute)
		_publish_committed_outcome(str(outcome.get("agent_id", "")), outcome)
		if service_enabled:
			gateway.report_outcome(str(outcome.get("agent_id", "")), session_id, outcome)
	if service_enabled:
		scheduler.advance_to(game_minute)


func _on_market_price_changed(item_id: String, price: int) -> void:
	var minute := _absolute_game_minute()
	world_fact_bridge.publish_market_price(item_id, price, minute, "market-price:%s:%d:%d" % [item_id, minute, price], _market.call("get_item_state", item_id))
	_notify_public_event(2, minute)


func _on_market_stock_changed(item_id: String, stock: int) -> void:
	var minute := _absolute_game_minute()
	var priority := 1 if stock > 3 else 3
	world_fact_bridge.publish_market_stock(item_id, stock, minute, "market-stock:%s:%d:%d" % [item_id, minute, stock], _market.call("get_item_state", item_id))
	_notify_public_event(priority, minute)


func _on_day_changed(total_day: int) -> void:
	var minute := _absolute_game_minute()
	interaction_system.refresh_market_pressure(minute)
	world_fact_bridge.publish_day(total_day, minute, "day:%d" % total_day)
	_notify_public_event(2, minute)


func _on_season_changed(season: int) -> void:
	var minute := _absolute_game_minute()
	world_fact_bridge.publish_season(season, minute, "season:%d:%d" % [int(_season.total_days), season])
	_notify_public_event(3, minute)


func _on_weather_changed(weather: String) -> void:
	var minute := _absolute_game_minute()
	world_fact_bridge.publish_weather(weather, minute, "weather:%d:%s" % [minute, weather])
	_notify_public_event(2, minute)


func _on_environment_condition_changed(condition_id: String, state: Dictionary) -> void:
	var minute := _absolute_game_minute()
	world_fact_bridge.publish_environment(condition_id, state, minute, "environment:%s:%d:%d" % [condition_id, minute, JSON.stringify(state).hash()])
	_notify_public_event(2, minute)


func _on_market_pressure_settled(total_day: int, pressure: Dictionary) -> void:
	var minute := _absolute_game_minute()
	interaction_system.mark_market_pressure_consumed(total_day)
	world_fact_bridge.publish_market_pressure(total_day, pressure, minute, "market-pressure:%d" % total_day)
	_notify_public_event(2, minute)


func _notify_public_event(priority: int, game_minute: int) -> void:
	if not service_enabled:
		return
	for agent_id in registry.get_agent_ids():
		scheduler.notify_event(str(agent_id), priority, game_minute)


func _wake_agent_for_interaction(agent_id: String, priority: int, game_minute: int) -> void:
	if _event_bus != null:
		_event_bus.agent_interaction_changed.emit(agent_id, "urgent")
	if service_enabled:
		scheduler.notify_event(agent_id, priority, game_minute)


func _build_request(agent_id: String, trigger: String, game_minute: int, dialogue: String) -> Dictionary:
	if (
		trigger != "dialogue"
		and farm_registry.has_method("has_pending_work")
		and bool(farm_registry.call("has_pending_work", agent_id))
	):
		return {}
	_request_sequence += 1
	var request_id := "%s-%s-%d" % [agent_id, _request_namespace, _request_sequence]
	var state = _npc_economy.call("get_npc_state", agent_id)
	if state == null:
		return {}
	var projected: Dictionary = context_projection.build(agent_id, request_id)
	var public_world := (projected.get("public_world_state", {}) as Dictionary).duplicate(true)
	public_world.game_day = int(_season.total_days)
	public_world.absolute_game_minute = game_minute
	public_world.time_of_day = {"hour": int(_season.hour), "minute": int(_season.minute)}
	public_world.season = int(_season.current_season)
	projected.public_world_state = public_world
	var market_snapshot: Dictionary = {}
	var agent_pressure: Dictionary = (_market.call("get_agent_market_pressure") as Dictionary).get("items", {}) if _market.has_method("get_agent_market_pressure") else {}
	for definition in GameDataScript.get_market_items():
		var item_id := str(definition.id)
		market_snapshot[item_id] = _market.call("get_item_state", item_id)
		if agent_pressure.has(item_id):
			(market_snapshot[item_id] as Dictionary)["agent_pressure"] = (agent_pressure[item_id] as Dictionary).duplicate(true)
	projected.market_view = market_snapshot.duplicate(true)
	var farm_snapshot: Variant = (
		farm_registry.call("get_snapshot", agent_id, game_minute)
		if farm_registry.has_method("get_snapshot")
		else farm_registry.to_dict().farms.get(agent_id, [])
	)
	var capabilities: Dictionary = role_system.get_capabilities(agent_id)
	var role_options: Array[Dictionary] = []
	for role_id_value in registry.get_role_ids():
		var role: Dictionary = registry.get_role(str(role_id_value))
		role_options.append({"role_id": str(role.role_id), "goals": (role.goals as Array).duplicate()})
	public_world.role_options = role_options
	projected.public_world_state = public_world
	var relationships: Dictionary = {}
	for known_actor_value in projected.known_actors:
		var known_actor := known_actor_value as Dictionary
		relationships[str(known_actor.actor_id)] = (known_actor.get("relationship", {}) as Dictionary).duplicate(true)
	projected.actor_context = {
		"self": state.to_dict(),
		"farm": farm_snapshot,
		"buildings": building_registry.to_dict().buildings,
		"private_knowledge": knowledge_registry.get_private(agent_id),
		"known_discoveries": knowledge_registry.to_dict().public,
		"relationships": relationships,
	}
	projected.active_role = str(capabilities.get("role_id", ""))
	projected.goals = (capabilities.get("goals", []) as Array).duplicate()
	projected.allowed_read_tools = (capabilities.get("read_tools", []) as Array).duplicate()
	projected.allowed_command_tools = (capabilities.get("tools", []) as Array).duplicate()
	projected.interaction_view = {"active_offers": interaction_system.list_offers(agent_id)}
	projected.agreement_view = {"active_agreements": agreement_system.list_agreements(agent_id)}
	var snapshot := {"game_time": {"day": int(_season.total_days), "hour": int(_season.hour), "minute": int(_season.minute), "season": int(_season.current_season)}, "self": state.to_dict(), "farm": farm_snapshot, "buildings": building_registry.to_dict().buildings, "private_knowledge": knowledge_registry.get_private(agent_id), "public_knowledge": knowledge_registry.to_dict().public, "market": market_snapshot, "public_world_state": projected.public_world_state, "global_public_events": projected.global_public_events, "known_actors": projected.known_actors, "own_event_delta": projected.own_event_delta, "market_view": projected.market_view}
	projected.projection_schema_version = 1
	var request := AgentProtocolScript.make_decision_request(request_id, session_id, gateway.session_epoch, agent_id, trigger, game_minute, executor.world_revision, snapshot, projected.own_event_delta, dialogue, projected)
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
		context_projection.release(agent_id, request_id)
		if trigger == "dialogue":
			dialogue_stream_failed.emit(agent_id, request_id, str((data.payload as Dictionary).get("code", "stream_error")))
		_request_triggers.erase(request_id)


func _handle_stream_failure(agent_id: String, request_id: String, error: String) -> void:
	var trigger := str(_request_triggers.get(request_id, ""))
	context_projection.release(agent_id, request_id)
	if not session_trace.finish_error(agent_id, request_id, error, trigger):
		_publish("warning", "%s 的 Agent 失败会话无法记录。" % agent_id, {"agent_id": agent_id})
	if trigger == "dialogue":
		dialogue_stream_failed.emit(agent_id, request_id, error)
	_request_triggers.erase(request_id)


func _handle_response(agent_id: String, response: Dictionary) -> void:
	var request_id := str(response.get("request_id", ""))
	var trigger := str(_request_triggers.get(request_id, ""))
	_request_triggers.erase(request_id)
	if trigger == "dialogue":
		var speech := str(response.get("speech", "")).strip_edges()
		if speech.is_empty():
			speech = str(response.get("decision_summary", "")).strip_edges()
		if speech.is_empty():
			speech = "……"
		dialogue_ready.emit(agent_id, request_id, speech)
	var checked := validator.validate(response, registry, executor.world_revision, role_system)
	if not checked.ok:
		context_projection.release(agent_id, request_id)
		_publish("warning", "%s 的 Agent 动作被拒绝：%s" % [agent_id, str(checked.error)], {"agent_id": agent_id})
		return
	if not _event_pipeline_synchronized():
		context_projection.release(agent_id, request_id)
		_publish("warning", "%s 的 Agent 事件投影暂不同步，动作已推迟。" % agent_id, {"agent_id": agent_id})
		return
	context_projection.acknowledge(agent_id, request_id)
	var outcomes: Array[Dictionary] = executor.execute_batch(checked.value, _absolute_game_minute())
	for outcome in outcomes:
		_record_world_action_outcome(outcome)
		agreement_system.record_action_outcome(outcome, _absolute_game_minute())
		if str(outcome.get("status", "")) == "in_progress":
			record_farm_lifecycle("queued", {
				"request_id": request_id,
				"action_id": str(outcome.get("action_id", "")),
				"idempotency_key": str(outcome.get("idempotency_key", "")),
			})
		if outcome.status in ["rejected", "failed"]:
			_publish("warning", "%s 的动作失败：%s" % [agent_id, str(outcome.get("failure_code", "unknown"))], {"agent_id": agent_id})
		else:
			_publish_committed_outcome(agent_id, outcome)
		if service_enabled:
			gateway.report_outcome(agent_id, session_id, outcome)


func _publish_committed_outcome(agent_id: String, outcome: Dictionary) -> void:
	var text := str(outcome.get("hud_message", ""))
	if text.is_empty():
		return
	_publish("success", text, {
		"agent_id": agent_id,
		"decision_id": str(outcome.get("decision_id", "")),
		"changed_entities": outcome.get("changed_entities", []).duplicate(),
	})


func _record_world_action_outcome(outcome: Dictionary) -> bool:
	var status := str(outcome.get("status", ""))
	var tool_name := str(outcome.get("tool_name", ""))
	if status not in ["in_progress", "completed"] or tool_name in [
		"", "wait", "send_message", "speak", "propose_trade", "counter_trade",
		"accept_trade", "reject_trade", "cancel_trade", "propose_cooperation",
		"counter_cooperation", "accept_cooperation", "reject_cooperation",
		"commit_contribution", "cancel_cooperation", "propose_role_change",
	]:
		return true
	if not _event_pipeline_synchronized():
		return false
	var agent_id := str(outcome.get("agent_id", ""))
	var action_id := str(outcome.get("action_id", outcome.get("idempotency_key", "action")))
	var arguments := (outcome.get("arguments", {}) as Dictionary).duplicate(true)
	var base_payload := {
		"tool_name": tool_name,
		"status": status,
		"arguments": arguments,
		"changed_entities": (outcome.get("changed_entities", []) as Array).duplicate(true),
		"resource_delta": (outcome.get("resource_delta", {}) as Dictionary).duplicate(true),
		"agreement_id": str(outcome.get("agreement_id", "")),
	}
	var events: Array[Dictionary] = []
	var region_id := str(world_projector.get_actor(agent_id).get("region_id", "village"))
	if status == "in_progress" and tool_name in ["travel", "build"]:
		var activity_status := "traveling" if tool_name == "travel" else "building"
		events.append(_world_action_event("PublicStatusChanged", "actor", agent_id, agent_id, action_id, base_payload.merged({"status": activity_status, "region_id": region_id}, true), "public"))
	elif status == "completed":
		match tool_name:
			"till": events.append(_world_action_event("FieldTilled", "farm", agent_id, agent_id, action_id, base_payload.merged({"region_id": region_id}, true), "region"))
			"plant": events.append(_world_action_event("CropPlanted", "farm", agent_id, agent_id, action_id, base_payload.merged({"region_id": region_id}, true), "region"))
			"harvest": events.append(_world_action_event("CropHarvested", "farm", agent_id, agent_id, action_id, base_payload.merged({"region_id": region_id}, true), "public"))
			"buy", "sell", "prepare_supplies": events.append(_world_action_event("PublicMarketTradeExecuted", "market_trade", action_id, agent_id, action_id, base_payload, "public"))
			"travel":
				var destination := str(arguments.get("region_id", region_id))
				events.append(_world_action_event("ActorRegionChanged", "actor", agent_id, agent_id, action_id, base_payload.merged({"region_id": destination}, true), "public"))
				events.append(_world_action_event("PublicStatusChanged", "actor", agent_id, agent_id, action_id, base_payload.merged({"status": "idle", "region_id": destination}, true), "public"))
			"build":
				events.append(_world_action_event("BuildingCompleted", "building", str(arguments.get("building_id", action_id)), agent_id, action_id, base_payload.merged({"region_id": region_id}, true), "public"))
				events.append(_world_action_event("PublicStatusChanged", "actor", agent_id, agent_id, action_id, base_payload.merged({"status": "idle", "region_id": region_id}, true), "public"))
			"survey": events.append(_world_action_event("RegionSurveyed", "region", str(arguments.get("region_id", region_id)), agent_id, action_id, base_payload.merged({"region_id": str(arguments.get("region_id", region_id))}, true), "public"))
			"collect_sample": events.append(_world_action_event("SampleCollected", "agent_knowledge", agent_id, agent_id, action_id, base_payload, "private", [agent_id]))
			"register_discovery": events.append(_world_action_event("DiscoveryRegistered", "public_knowledge", str(arguments.get("discovery_id", action_id)), agent_id, action_id, base_payload, "public"))
	if events.is_empty():
		return true
	var key := "agent-outcome:%s:%s" % [str(outcome.get("idempotency_key", action_id)), status]
	var committed: Dictionary = event_store.append_projected_batch(events, key, world_projector)
	if not bool(committed.get("ok", false)):
		return false
	var committed_events: Array[Dictionary] = []
	committed_events.assign(committed.events)
	return not committed_events.is_empty() and int(committed_events[-1].global_sequence) <= world_projector.get_last_sequence()


func _world_action_event(event_type: String, aggregate_type: String, aggregate_id: String, actor_id: String, command_id: String, payload: Dictionary, scope: String, actor_ids: Array = []) -> Dictionary:
	return {
		"event_type": event_type,
		"aggregate_type": aggregate_type,
		"aggregate_id": aggregate_id,
		"actor_id": actor_id,
		"game_minute": _absolute_game_minute(),
		"command_id": command_id,
		"correlation_id": "agent-action:" + actor_id,
		"causation_event_id": "",
		"visibility": {"scope": scope, "actor_ids": actor_ids.duplicate()},
		"payload": payload.duplicate(true),
	}


func _event_pipeline_synchronized() -> bool:
	return event_store.get_last_sequence() == world_projector.get_last_sequence()


func _on_farm_work_finished(intent: Dictionary, result: Dictionary) -> void:
	var outcome := executor.finalize_queued_action(intent, result, _absolute_game_minute())
	_record_world_action_outcome(outcome)
	agreement_system.record_action_outcome(outcome, _absolute_game_minute())
	record_farm_lifecycle("committed" if bool(result.get("ok", false)) else "rejected", intent)
	var agent_id := str(intent.get("agent_id", "farmer_ahe"))
	if str(outcome.get("status", "")) in ["rejected", "failed"]:
		_publish("warning", "%s 的动作失败：%s" % [agent_id, str(outcome.get("failure_code", "unknown"))], {"agent_id": agent_id})
	else:
		_publish_committed_outcome(agent_id, outcome)
	if service_enabled:
		gateway.report_outcome(agent_id, session_id, outcome)


func _publish(severity: String, text: String, metadata: Dictionary) -> void:
	if _hud_bus != null and _hud_bus.has_method("publish"):
		_hud_bus.call("publish", "agent", severity, text, metadata)


func _absolute_game_minute() -> int:
	return maxi(0, int(_season.total_days) - 1) * GAME_MINUTES_PER_DAY + maxi(0, int(_season.hour) - 6) * 60 + int(_season.minute)
