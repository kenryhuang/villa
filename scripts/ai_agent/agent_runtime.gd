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
const AgentMarketSummaryScript = preload("res://scripts/ai_agent/agent_market_summary.gd")

const VERSION := 5
const EVENT_SCHEMA_VERSION := 1
const GAME_MINUTES_PER_DAY := 1080
const SAVE_DIRECTORY := "user://villa_saves/"
const EXPECTED_STREAM_CANCELLATIONS := {
	"cancelled": true,
	"game_closed": true,
	"session_changed": true,
	"client_reconfigured": true,
	"replaced": true,
	"dialogue_replaced": true,
	"dialogue_closed": true,
}

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
var market_summary = AgentMarketSummaryScript.new()
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
var _pending_market_pressure_facts: Dictionary = {}
var farm3d_session: Node
var farm3d_actors: Dictionary = {}
var _farm3d_memory_export_pending := false
var _deferred_responses: Array[Dictionary] = []
var _scheduled_tick_pending := false
var _restore_preparation_active := false
var _prepared_restore: Dictionary = {}
var _cancelled_requests: Dictionary = {}
const FARM3D_SPAWNS := {"farmer_ahe": Vector2(-12, -12), "lao_li": Vector2(-2, -10), "xuezhe_lin": Vector2(7, -12)}


func configure_farm3d(session: Node, hud_bus: Node, remote_enabled: bool, client_config_path: String = AgentClientConfigScript.DEFAULT_PATH) -> bool:
	farm3d_session = session
	session_id = "farm3d-" + _request_namespace
	var farm := VisibleNpcFarmSystem.new()
	add_child(farm)
	if not farm.configure(session.grid, session.farming, session.npc_economy, get_node("/root/GameData"), "farmer_ahe", Vector3(-12, 0, -12)):
		return false
	set_farm_port(farm)
	if not configure(session.npc_economy, session.market, session.season, hud_bus, client_config_path, remote_enabled):
		return false
	executor.farm3d_session = session
	activity_system.action_completion_guard = executor.complete_physical_action
	configure_player_assets(session.inventory, get_node("/root/GameState"))
	session.production.actor_assets.resolve_port = func(): return interaction_system
	session.production.rental_completed.connect(_on_rental_completed)
	session.production.service_order_changed.connect(_on_service_order_changed)
	dialogue_ready.connect(func(agent_id: String, _request_id: String, speech: String):
		if not speech.is_empty(): _publish("info", get_agent_display_name(agent_id) + "：" + speech, {}))
	return true


func spawn_farm3d_actors() -> void:
	for actor in farm3d_actors.values():
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.queue_free()
	farm3d_actors.clear()
	sync_focus_actors()

func sync_focus_actors() -> void:
	var society: RefCounted = farm3d_session.living_world.society if farm3d_session.living_world != null else null
	var focus: Array = society.focus if society != null else (preload("res://scripts/systems/resident_society_system.gd").configuration().focus_actors if preload("res://scripts/systems/resident_society_system.gd").expanded() else ["farmer_ahe", "lao_li", "xuezhe_lin"])
	for id in farm3d_actors.keys():
		if id in focus: continue
		farm3d_actors[id].process_mode = Node.PROCESS_MODE_DISABLED
		farm3d_actors[id].queue_free(); farm3d_actors.erase(id)
	for agent_id in focus:
		if farm3d_actors.has(agent_id): continue
		var actor := preload("res://scenes/actors/npc.tscn").instantiate()
		actor.villager_id = agent_id
		var spawn: Vector2 = FARM3D_SPAWNS.get(agent_id, Vector2(-8.5, 20.5))
		if society != null and society.residents.has(agent_id) and agent_id not in FARM3D_SPAWNS: spawn = Vector2(society.residents[agent_id].position.x, society.residents[agent_id].position.z)
		actor.position = Vector3(spawn.x, Farm3DTerrainProfile.surface_height(spawn.x, spawn.y), spawn.y)
		add_child(actor)
		actor.configure_agent(farm3d_session.player, agent_id, get_agent_display_name(agent_id))
		actor.configure_farm3d(farm3d_session.grid)
		var atlas_id := str(agent_id) if ResourceLoader.exists("res://assets/characters/npcs/%s/%s_directions.png" % [agent_id, agent_id]) else "lao_li"
		var atlas := load("res://assets/characters/npcs/%s/%s_directions.png" % [atlas_id, atlas_id]) as Texture2D
		actor.configure_agent_visual(atlas)
		farm3d_actors[agent_id] = actor
		if agent_id == "farmer_ahe":
			var controller := NpcFarmActionController.new()
			actor.add_child(controller)
			controller.configure(farm_registry, actor, actor.farm_action_visual)


func get_farm3d_environment() -> Dictionary:
	if not is_instance_valid(farm3d_session):
		return {}
	var s: Node = farm3d_session
	var buildings: Array[Dictionary] = []
	for building in s.buildings.get_all_buildings():
		var p: Vector3 = building.global_position
		buildings.append({"building_id": EconomyProgressionSystem.building_key(building), "type": building.building_id,
			"name": building.data.display_name, "owner_id": building.owner_id, "instance_id": building.instance_id, "service_policy": building.service_policy.duplicate(true), "position": {"x": p.x, "y": p.y, "z": p.z},
			"construction_complete": building.is_construction_complete(), "production": s.production.get_building_snapshot(building),
			"rental_fees": s.production.get_rental_fee_table(building)})
	var characters: Array[Dictionary] = []
	for id in ["player"] + registry.get_agent_ids():
		var actor: Node3D = s.player if id == "player" else farm3d_actors.get(id)
		var point: Vector3 = actor.global_position if is_instance_valid(actor) else Vector3.ZERO
		characters.append({"actor_id": id, "name": "玩家" if id == "player" else get_agent_display_name(id),
			"position": {"x": point.x, "y": point.y, "z": point.z}, "role": "player" if id == "player" else role_system.get_active_role(id)})
	if s.living_world != null:
		for resident in s.living_world.society.residents.values():
			if resident.id not in registry.get_agent_ids(): characters.append({"actor_id": resident.id, "name": resident.name, "role": resident.occupation, "state": resident.state, "position": resident.position.duplicate(true)})
	return {"buildings": buildings, "characters": characters, "map": {
		"coordinate_system": "east=+x, west=-x, south=+z, north=-z; world metres",
		"action_movement": "move(x,z) 可独立走动；buy/sell 自动前往市场，rent_production 自动前往建筑，农作自动前往地块。一次调用包含行走与到达后的操作，in_progress 不是已完成。",
		"bounds": {"min_x": Farm3DTerrainProfile.WORLD_MIN.x, "min_z": Farm3DTerrainProfile.WORLD_MIN.y, "max_x": Farm3DTerrainProfile.WORLD_MAX.x, "max_z": Farm3DTerrainProfile.WORLD_MAX.y},
		"market": {"x": s.market_site.x, "z": s.market_site.y},
		"lake": {"x": Farm3DTerrainProfile.LAKE_CENTER.x, "z": Farm3DTerrainProfile.LAKE_CENTER.y},
		"regions": [{"id": "farm", "description": "中央农场；玩家建筑与阿禾的专属农田"}, {"id": "creek", "description": "东侧河流，可钓鱼；南部有桥"}, {"id": "forest", "description": "西北林地"}, {"id": "hills", "description": "外围丘陵"}, {"id": "lake", "description": "南部沙地湖泊，可钓鱼"}, {"id": "golf", "description": "湖泊西侧高尔夫球场"}],
		"rental_rules": "使用 inspect_building 查询实际 building_id、配方与每批租费，再用 rent_production；系统会自动走到建筑后再下单，无需先调用 move；自备原料，加工费按该建筑费目表收取，排队托管，开工付给 owner_id；使用自有建筑免费。共用队列，完成后成品交付客户。max_fee 是总租金上限。"}}


func _on_service_order_changed(building: BuildingInstance, record: Dictionary) -> void:
	session_trace.record_action_event(str(record.job.request_id), "production_" + str(record.stage), {"order_id": record.job.order_id, "building_id": building.instance_id, "customer_id": record.job.tenant_id, "owner_id": building.owner_id, "payment_state": record.job.payment_state})
	var key := str(record.job.order_id)
	if str(record.stage) not in ["delivered", "cancelled"] or not executor._outcomes.has(key): return
	var outcome: Dictionary = executor._outcomes[key].duplicate(true)
	if str(outcome.status) != "in_progress": return
	executor.world_revision += 1
	outcome.status = "completed" if record.stage == "delivered" else "failed"
	outcome.committed_revision = executor.world_revision
	outcome.game_minute = _absolute_game_minute()
	outcome.hud_message = "订单 %s：%s" % [key, "成品已交付" if record.stage == "delivered" else "已取消并退款"]
	if record.stage == "cancelled": outcome.failure_code = "order_cancelled"
	executor._outcomes[key] = outcome.duplicate(true)
	_record_world_action_outcome(outcome)
	agreement_system.record_action_outcome(outcome, _absolute_game_minute())
	_publish_committed_outcome(str(outcome.agent_id), outcome)
	if service_enabled: gateway.report_outcome(str(outcome.agent_id), session_id, outcome)
	_report_continued_actions(outcome)


func _on_rental_completed(agent_id: String, building: BuildingInstance, recipe_id: String, outputs: Dictionary) -> void:
	if agent_id == "player":
		_publish("info", "加工完成，请到建筑收取你的成品。", {})
		return
	_publish("info", "%s在%s的租用加工完成，已收取成品。" % [get_agent_display_name(agent_id), building.data.display_name], {})
	perception_inbox.push_event(agent_id, "rental_completed", recipe_id, {"outputs": outputs}, _absolute_game_minute(), 2)
	if service_enabled:
		scheduler.notify_event(agent_id, 2, _absolute_game_minute())


func save_farm3d_memory(save_path: String) -> void:
	if not service_enabled or _farm3d_memory_export_pending:
		return
	var world_hash := FileAccess.get_sha256(save_path)
	var epoch: int = gateway.session_epoch
	_farm3d_memory_export_pending = true
	var callback := func(ok: bool, record: Dictionary, error: String):
		_farm3d_memory_export_pending = false
		if epoch != gateway.session_epoch or FileAccess.get_sha256(save_path) != world_hash:
			return
		if not ok or not _valid_checkpoint_record(record) or str(record.session_id) != session_id:
			_publish("warning", "NPC 记忆检查点未保存，农场存档已保留：" + error, {})
			return
		var path := save_path + ".agent-memory.json"
		var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
		if file == null:
			_publish("warning", "NPC 记忆清单写入失败，农场存档已保留。", {})
			return
		file.store_string(JSON.stringify({"world_sha256": world_hash, "checkpoint": record}, "  "))
		file.flush()
		var write_error := file.get_error()
		file.close()
		if write_error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) != OK:
			_publish("warning", "NPC 记忆清单写入失败，农场存档已保留。", {})
	if not gateway.export_checkpoint(session_id, "farm3d-" + world_hash.left(24), callback):
		_farm3d_memory_export_pending = false


func load_farm3d_memory(save_path: String) -> void:
	if not service_enabled:
		return
	var path := save_path + ".agent-memory.json"
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not manifest is Dictionary or manifest.get("world_sha256", "") != FileAccess.get_sha256(save_path) or not manifest.get("checkpoint") is Dictionary:
		gateway.sync_session(session_id, true)
		_publish("warning", "此存档没有匹配的 NPC 记忆检查点，已从农场当前状态继续决策。", {})
		return
	var record: Dictionary = manifest.checkpoint
	if not _valid_checkpoint_record(record) or str(record.session_id) != session_id:
		gateway.sync_session(session_id, true)
		return
	var epoch: int = gateway.session_epoch
	var callback := func(ok: bool, _response: Dictionary, error: String):
		if epoch != gateway.session_epoch:
			return
		if not ok:
			gateway.sync_session(session_id, true)
			_publish("warning", "NPC 记忆恢复失败，已从农场当前状态继续：" + error, {})
	if not gateway.import_checkpoint(record, callback):
		gateway.sync_session(session_id, true)


func flush_farm3d_memory(save_path: String) -> void:
	if not service_enabled:
		return
	var deadline := Time.get_ticks_msec() + 2500
	while _farm3d_memory_export_pending and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05, true).timeout
	save_farm3d_memory(save_path)
	while _farm3d_memory_export_pending and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05, true).timeout


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
	client_config_path: String = AgentClientConfigScript.DEFAULT_PATH,
	remote_enabled: bool = true
) -> bool:
	if npc_economy == null or market == null or season == null or not registry.load_defaults(farm3d_session != null and preload("res://scripts/systems/resident_society_system.gd").expanded()):
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
		_store_agent_session = remote_enabled and bool(client_config.value.store_agent_session)
		_agent_session_directory = str(client_config.value.agent_session_directory)
		if remote_enabled and bool(client_config.value.enabled):
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

func dialogue_unavailable_reason() -> String:
	if not service_enabled: return "Agent 服务暂时不可用，请稍后再试。"
	if scheduler.max_daily_dialogue_requests > 0 and scheduler.budget_day >= _absolute_game_minute() / 1080 and scheduler.dialogue_budget_calls >= scheduler.max_daily_dialogue_requests:
		return "今日的 AI 对话额度已用完，下一游戏日恢复；自主规划和已接受的工作会继续。"
	if scheduler.max_concurrent_dialogue_requests > 0 and scheduler.dialogue_in_flight_count() >= scheduler.max_concurrent_dialogue_requests:
		return "另一段对话正在回应，请稍后再发送。"
	return "角色暂时无法回应，请稍后重试；若刚刚跨日，请先关闭窗口让日结完成。"


func get_in_flight_request_id(agent_id: String) -> String:
	return scheduler.get_in_flight_request_id(agent_id)


func cancel_dialogue(agent_id: String, request_id: String) -> bool:
	if str(_request_triggers.get(request_id, "")) != "dialogue":
		return false
	_cancelled_requests[request_id] = true
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
	_deferred_responses.clear()
	_cancelled_requests.clear()
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
		"pending_market_pressure_facts": _pending_market_pressure_records(),
	}


func begin_restore_preparation() -> void:
	_prepared_restore.clear()
	_restore_preparation_active = true


func end_restore_preparation() -> void:
	_restore_preparation_active = false
	_prepared_restore.clear()


func _can_reuse_restore(value: Dictionary) -> bool:
	return _restore_preparation_active and not _prepared_restore.is_empty() and _prepared_restore.value == value and _prepared_restore.profiles == _actor_profiles() and _prepared_restore.agent_ids == registry.get_agent_ids()


func validate_dict(value: Dictionary) -> bool:
	# Only the synchronous full-save transaction can reuse this candidate. A
	# changed input or actor context always goes through all checks again.
	if _can_reuse_restore(value): return true
	_prepared_restore.clear()
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
	_deferred_responses.clear()
	_request_triggers.clear()
	_cancelled_requests.clear()
	if gateway != null:
		gateway.bump_epoch()
		if is_instance_valid(farm3d_session) and service_enabled:
			gateway.sync_session(session_id, false)
	return true


func _validate_event_sourced_state(value: Dictionary) -> bool:
	for field in ["event_schema_version", "event_store", "projection_checkpoint", "checkpoint_sequence", "perception_inbox", "roles", "interactions", "agreements", "pending_market_pressure_facts"]:
		if not value.has(field):
			return false
	if value.event_schema_version != EVENT_SCHEMA_VERSION or not value.event_store is Dictionary or not value.projection_checkpoint is Dictionary or not value.perception_inbox is Dictionary or not value.roles is Dictionary or not value.interactions is Dictionary or not value.agreements is Dictionary:
		return false
	if _normalize_pending_market_pressure_facts(value.pending_market_pressure_facts) == null:
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
	if not validation_registry.load_defaults(registry.get_agent_ids().size() > 3):
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
	if expected_reservations == null or not restored_interactions.validate_external_reservations(value.interactions, expected_reservations): return false
	if _restore_preparation_active:
		_prepared_restore = {"value": value.duplicate(true), "profiles": _actor_profiles(), "agent_ids": registry.get_agent_ids(), "store": restored_store, "inbox": restored_inbox, "projector": restored_projector}
	return true


func _restore_event_sourced_state(value: Dictionary, apply_market_pressure := true) -> bool:
	var restored_store = AgentWorldEventStoreScript.new()
	var restored_inbox = AgentPerceptionInboxScript.new()
	var restored_projector = AgentWorldProjectorScript.new()
	if _can_reuse_restore(value):
		restored_store = _prepared_restore.store
		restored_inbox = _prepared_restore.inbox
		restored_projector = _prepared_restore.projector
		_prepared_restore.clear()
	else:
		if not restored_store.from_dict(value.event_store): return false
		if not restored_projector.configure(registry.get_agent_ids(), _actor_profiles(), restored_inbox): return false
		if not restored_projector.replay(restored_store.get_events_after(0)): return false
	if not restored_inbox.from_dict(value.perception_inbox, restored_projector.get_last_sequence()):
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
	var restored_executor = AgentExecutorScript.new()
	if not restored_executor.configure(registry, farm_registry, building_registry, activity_system, knowledge_registry, _npc_economy, Callable(), restored_roles, restored_interactions, restored_agreements) or not restored_executor.from_dict(value.executor):
		return false
	event_store = restored_store
	perception_inbox = restored_inbox
	world_projector = restored_projector
	context_projection = restored_context
	world_fact_bridge = restored_bridge
	role_system = restored_roles
	interaction_system = restored_interactions
	agreement_system = restored_agreements
	restored_executor.farm3d_session = farm3d_session
	executor = restored_executor
	if is_instance_valid(farm3d_session):
		activity_system.action_completion_guard = executor.complete_physical_action
	_pending_market_pressure_facts = _normalize_pending_market_pressure_facts(value.pending_market_pressure_facts)
	return true


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
		"pending_market_pressure_facts": [],
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

func expand_saved_population(value: Dictionary) -> void:
	if int(value.get("version", 0)) < VERSION: return
	var store = AgentWorldEventStoreScript.new()
	if not store.from_dict(value.event_store): return
	var inbox = AgentPerceptionInboxScript.new()
	var projector = AgentWorldProjectorScript.new()
	if not projector.configure(registry.get_agent_ids(), _actor_profiles(), inbox) or not projector.replay(store.get_events_after(0)): return
	value.checkpoint_sequence = projector.get_last_sequence()
	value.projection_checkpoint = projector.to_dict()
	var known := {}
	for c in value.perception_inbox.consumption_cursors: known[c.agent_id] = true
	for id in registry.get_agent_ids():
		if known.has(id): continue
		value.perception_inbox.consumption_cursors.append({"agent_id": id, "consumed_sequence": projector.get_last_sequence()})
		var role: String = registry.get_agent(id).role_id
		value.roles.roles.append({"agent_id": id, "active_role_id": role, "last_changed_minute": -1, "history": [role]})
	value.perception_inbox.consumption_cursors.sort_custom(func(a, b): return a.agent_id < b.agent_id)
	value.roles.roles.sort_custom(func(a, b): return a.agent_id < b.agent_id)


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
	var had_pending_market_pressure := not _pending_market_pressure_facts.is_empty()
	if had_pending_market_pressure and _retry_pending_market_pressure_facts():
		_notify_public_event(2, game_minute)
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
	_scheduled_tick_pending = service_enabled
	_advance_scheduled_decisions()


func _advance_scheduled_decisions() -> void:
	if not service_enabled:
		_scheduled_tick_pending = false
		return
	if not _scheduled_tick_pending or get_tree().paused:
		return
	var game_minute := _absolute_game_minute()
	# The runtime receives time_changed before LivingWorld. Population settlement
	# can also span several frames, so retain the tick until its data is current.
	if farm3d_session != null and farm3d_session.living_world != null:
		if not farm3d_session.living_world.society.caught_up(game_minute):
			return
	_scheduled_tick_pending = false
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
	_pending_market_pressure_facts[total_day] = {"day": total_day, "pressure": pressure.duplicate(true), "game_minute": minute}
	if not _retry_pending_market_pressure_facts():
		_publish("warning", "Agent 市场压力结算事件写入失败，保留待核对状态。", {"day": total_day})
		return
	_notify_public_event(2, minute)


func _retry_pending_market_pressure_facts() -> bool:
	var days := _pending_market_pressure_facts.keys()
	days.sort()
	for day_value in days:
		var day := int(day_value)
		var record := _pending_market_pressure_facts[day] as Dictionary
		if not world_fact_bridge.publish_market_pressure(day, record.pressure, int(record.game_minute), "market-pressure:%d" % day):
			return false
		interaction_system.mark_market_pressure_consumed(day)
		_pending_market_pressure_facts.erase(day)
	return true


func _pending_market_pressure_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var days := _pending_market_pressure_facts.keys()
	days.sort()
	for day_value in days:
		records.append((_pending_market_pressure_facts[day_value] as Dictionary).duplicate(true))
	return records


func _normalize_pending_market_pressure_facts(value: Variant) -> Variant:
	if not value is Array:
		return null
	var result: Dictionary = {}
	var last_day := 0
	for record_value in value:
		if not record_value is Dictionary:
			return null
		var record := record_value as Dictionary
		if record.size() != 3 or not _is_nonnegative_integer(record.get("day")) or int(record.day) <= last_day or not record.get("pressure") is Dictionary or not _is_nonnegative_integer(record.get("game_minute")):
			return null
		last_day = int(record.day)
		result[last_day] = {"day": last_day, "pressure": (record.pressure as Dictionary).duplicate(true), "game_minute": int(record.game_minute)}
	return result


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
	if farm3d_session != null and farm3d_session.living_world != null and (agent_id not in farm3d_session.living_world.society.focus or not farm3d_session.living_world.society.caught_up(game_minute)): return {}
	if trigger != "dialogue" and farm3d_session != null and farm3d_session.living_world != null:
		var negotiating: bool = farm3d_session.living_world.work.pending_negotiation(agent_id)
		if not negotiating and (not farm3d_session.living_world.interruptions.running(agent_id).is_empty() or farm3d_session.living_world.work.owns_schedule(agent_id)): return {}
		var project: Dictionary = farm3d_session.living_world.projects.active(agent_id)
		if not negotiating and not project.is_empty() and not project.steps.values().any(func(step): return step.status == "blocked"): return {}
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
	public_world.time_of_day = {
		"hour": int(_season.hour),
		"minute": int(_season.minute),
		"text": "%02d:%02d" % [int(_season.hour), int(_season.minute)],
	}
	public_world.season = int(_season.current_season)
	public_world.season_name = str(SeasonSystem.Season.keys()[public_world.season]).to_lower()
	public_world.season_label = ["春季", "夏季", "秋季", "冬季"][public_world.season]
	public_world.season_day = int(_season.current_day)
	public_world.days_per_season = SeasonSystem.DAYS_PER_SEASON
	public_world.year = 1 + int(float(maxi(0, int(_season.total_days) - 1)) / float(SeasonSystem.DAYS_PER_SEASON * 4))
	projected.public_world_state = public_world
	var market_snapshot: Dictionary = {}
	var market_catalog: Dictionary = {}
	var agent_pressure: Dictionary = (_market.call("get_agent_market_pressure") as Dictionary).get("items", {}) if _market.has_method("get_agent_market_pressure") else {}
	for definition in GameDataScript.get_market_items():
		var item_id := str(definition.id)
		market_catalog[item_id] = definition.duplicate(true)
		market_snapshot[item_id] = _market.call("get_agent_item_view", item_id)
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
		"crop_options": _build_crop_options(agent_id),
		"buildings": building_registry.to_dict().buildings,
		"private_knowledge": knowledge_registry.get_private(agent_id),
		"known_discoveries": knowledge_registry.to_dict().public,
		"relationships": relationships,
	}
	if is_instance_valid(farm3d_session):
		var environment := get_farm3d_environment()
		projected.actor_context.exploration = knowledge_registry.cards(agent_id, trigger != "dialogue")
		projected.actor_context.living_world = farm3d_session.living_world.context(agent_id)
		projected.actor_context.environment = farm3d_session.living_world.environment.context()
		projected.actor_context.social = farm3d_session.living_world.social.context()
		projected.actor_context.planning_limits = {"concise": preload("res://scripts/systems/resident_society_system.gd").expanded(), "daily_private_requests": scheduler.max_daily_requests, "used": scheduler.budget_calls}
		projected.actor_context.world_map = environment.map
		projected.actor_context.player_buildings = environment.buildings
		projected.actor_context.characters = environment.characters
	projected.active_role = str(capabilities.get("role_id", ""))
	projected.goals = (capabilities.get("goals", []) as Array).duplicate()
	projected.allowed_read_tools = (capabilities.get("read_tools", []) as Array).duplicate()
	projected.allowed_command_tools = (capabilities.get("tools", []) as Array).duplicate()
	if is_instance_valid(farm3d_session): projected.allowed_command_tools.erase("propose_cooperation")
	if not is_instance_valid(farm3d_session):
		for name in ["move", "rent_production", "propose_activity", "enroll_activity", "leave_activity", "cancel_activity", "contribute_route_repair", "offer_intelligence", "buy_intelligence", "share_intelligence", "propose_investigation", "accept_investigation", "cancel_investigation", "propose_joint_project", "accept_joint_project", "exit_joint_project", "propose_work", "counter_work", "accept_work", "cancel_work", "start_learning", "start_leisure", "manage_building", "propose_delivery", "cancel_delivery", "revise_project", "submit_project", "retry_project", "cancel_project", "publish_commission", "propose_player_commission", "claim_commission", "deliver_commission", "suggest_behavior"]: projected.allowed_command_tools.erase(name)
	projected.market_summary = market_summary.build(
		str(capabilities.get("role_id", "")),
		game_minute,
		state.to_dict(),
		farm_snapshot if farm_snapshot is Array else [],
		market_snapshot,
		market_catalog
	)
	projected.interaction_view = {"active_offers": interaction_system.list_offers(agent_id)}
	projected.agreement_view = {"active_agreements": agreement_system.list_agreements(agent_id)}
	projected.projection_schema_version = 1
	var request := AgentProtocolScript.make_decision_request(request_id, session_id, gateway.session_epoch, agent_id, trigger, game_minute, executor.world_revision, dialogue, projected)
	_request_triggers[str(request.request_id)] = trigger
	return request


func _build_crop_options(agent_id: String) -> Array:
	if not farm_registry.has_method("get_crop_options"):
		return []
	var options: Array = farm_registry.call("get_crop_options", agent_id)
	return options.filter(func(option: Dictionary) -> bool:
		return str(option.get("seed_item_id", "")) in AgentValidatorScript.SEED_IDS
	)


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
	elif event_name == "content.delta" and trigger == "dialogue" and farm3d_session == null:
		dialogue_stream_delta.emit(agent_id, request_id, str((data.payload as Dictionary).get("delta", "")))
	elif event_name == "stream.error":
		context_projection.release(agent_id, request_id)
		if trigger == "dialogue":
			dialogue_stream_failed.emit(agent_id, request_id, str((data.payload as Dictionary).get("code", "stream_error")))
		_request_triggers.erase(request_id)


func _handle_stream_failure(agent_id: String, request_id: String, error: String) -> void:
	var trigger := str(_request_triggers.get(request_id, ""))
	context_projection.release(agent_id, request_id)
	var expected_cancellation := EXPECTED_STREAM_CANCELLATIONS.has(error)
	var trace_finished: bool = bool(
		session_trace.finish_cancelled(agent_id, request_id, error, trigger)
		if expected_cancellation
		else session_trace.finish_error(agent_id, request_id, error, trigger)
	)
	if not trace_finished:
		_publish("warning", "%s 的 Agent 失败会话无法记录。" % agent_id, {"agent_id": agent_id})
	if trigger == "dialogue" and not expected_cancellation:
		dialogue_stream_failed.emit(agent_id, request_id, error)
	_request_triggers.erase(request_id)


func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	if not _deferred_responses.is_empty():
		var pending: Dictionary = _deferred_responses.pop_front()
		_handle_response(str(pending.agent_id), pending.response)
	_advance_scheduled_decisions()


func _handle_response(agent_id: String, response: Dictionary) -> void:
	var request_id := str(response.get("request_id", ""))
	if _cancelled_requests.has(request_id):
		context_projection.release(agent_id, request_id)
		_request_triggers.erase(request_id)
		return
	var trigger := str(_request_triggers.get(request_id, ""))
	if farm3d_session != null and get_tree().paused and validator.validate(response, registry, executor.world_revision, role_system).ok:
		var safe_dialogue := trigger == "dialogue"
		for action in response.get("actions", []):
			if str(action.get("tool_name", "")) not in ["propose_activity", "enroll_activity", "leave_activity", "cancel_activity", "contribute_route_repair", "offer_intelligence", "buy_intelligence", "share_intelligence", "propose_investigation", "accept_investigation", "cancel_investigation", "propose_joint_project", "accept_joint_project", "exit_joint_project", "propose_work", "counter_work", "accept_work", "cancel_work", "start_learning", "start_leisure", "manage_building", "propose_delivery", "cancel_delivery", "cancel_project", "revise_project", "suggest_behavior", "propose_player_commission", "speak", "wait", "propose_trade", "counter_trade", "accept_trade", "reject_trade", "cancel_trade", "propose_cooperation", "counter_cooperation", "accept_cooperation", "reject_cooperation"]:
				safe_dialogue = false
		if not safe_dialogue:
			if not _deferred_responses.any(func(entry: Dictionary): return str(entry.response.get("request_id", "")) == request_id):
				_deferred_responses.append({"agent_id": agent_id, "response": response.duplicate(true)})
			if trigger == "dialogue":
				dialogue_ready.emit(agent_id, request_id, "行动请求已排队，恢复游戏后将重新核验并执行；尚未扣费或完成。")
			return
	_request_triggers.erase(request_id)
	var checked := validator.validate(response, registry, executor.world_revision, role_system)
	if not checked.ok:
		context_projection.release(agent_id, request_id)
		_publish("warning", "%s 的 Agent 动作被拒绝：%s" % [agent_id, str(checked.error)], {"agent_id": agent_id})
		if trigger == "dialogue": dialogue_ready.emit(agent_id, request_id, "请求未执行：动作或当前状态不符合要求（%s）。" % str(checked.error))
		return
	if not _event_pipeline_synchronized():
		context_projection.release(agent_id, request_id)
		_publish("warning", "%s 的 Agent 事件投影暂不同步，动作已推迟。" % agent_id, {"agent_id": agent_id})
		if trigger == "dialogue": dialogue_ready.emit(agent_id, request_id, "当前状态尚未同步，请稍后重试；本次操作未执行。")
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
	if trigger == "dialogue":
		var failed := outcomes.filter(func(outcome: Dictionary): return str(outcome.get("status", "")) in ["rejected", "failed"])
		# Decision summaries are diagnostics, never NPC dialogue. Some providers
		# return the actual reply only in a speak tool call instead of content.
		var speech := str(response.get("speech", "")).strip_edges()
		if speech.is_empty():
			var spoken: Array[String] = []
			for outcome in outcomes:
				var arguments: Dictionary = outcome.get("arguments", {})
				if outcome.get("status") == "completed" and outcome.get("tool_name") == "speak" and arguments.get("target_actor_id") == "player":
					var text := str(arguments.get("text", "")).strip_edges()
					if not text.is_empty(): spoken.append(text)
			speech = "\n".join(spoken)
		if speech.is_empty(): speech = "（对方暂时没有回应。）"
		var facts: Array[String] = []
		for outcome in outcomes:
			if str(outcome.get("tool_name", "")) not in ["speak", "wait"]:
				var fact := str(outcome.get("hud_message", ""))
				if fact.is_empty():
					fact = str({"propose_trade": "交易报价已生成，等待对方确认。", "counter_trade": "新报价已生成，原报价已失效，等待对方确认。", "accept_trade": "交易已成交，物品与金币已按确认条款结算。", "reject_trade": "交易已拒绝。", "cancel_trade": "报价已取消。"}.get(str(outcome.get("tool_name", "")), "操作结果已记录，请查看当前协议状态。"))
				facts.append(fact)
		if not facts.is_empty():
			speech = "\n".join(facts)
		elif farm3d_session != null:
			speech += "\n（本次仅交谈，没有提交交易或生产操作。）"
		if not failed.is_empty():
			speech = "本次操作未全部完成：" + str(failed[0].get("failure_code", "transaction_failed")) + "。请查看实际条款和订单状态。"
		dialogue_ready.emit(agent_id, request_id, speech)


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
	# Movement is observable; the activity's private survey target, evidence and
	# discovered report are not part of a global status event.
	if arguments.get("physical", false) and tool_name in ["travel", "survey"]:
		arguments = {"region_id": str(arguments.get("region_id", "village"))}
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
			"speak", "send_message":
				if farm3d_session != null: knowledge_registry.record_statement(agent_id, str(arguments.get("target_actor_id", "")), action_id, str(arguments.get("text", "")))
			"till": events.append(_world_action_event("FieldTilled", "farm", agent_id, agent_id, action_id, base_payload.merged({"region_id": region_id}, true), "region"))
			"plant": events.append(_world_action_event("CropPlanted", "farm", agent_id, agent_id, action_id, base_payload.merged({"region_id": region_id}, true), "region"))
			"harvest":
				var event_type := "CropCleared" if bool(outcome.get("cleared_withered", false)) else "CropHarvested"
				events.append(_world_action_event(event_type, "farm", agent_id, agent_id, action_id, base_payload.merged({"region_id": region_id}, true), "public"))
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
	_report_continued_actions(outcome)


func _report_continued_actions(completed: Dictionary) -> void:
	for outcome in executor.resume_batch_after(completed, _absolute_game_minute()):
		_record_world_action_outcome(outcome)
		agreement_system.record_action_outcome(outcome, _absolute_game_minute())
		_publish_committed_outcome(str(outcome.get("agent_id", completed.get("agent_id", ""))), outcome)
		if service_enabled: gateway.report_outcome(str(outcome.get("agent_id", completed.get("agent_id", ""))), session_id, outcome)


func _publish(severity: String, text: String, metadata: Dictionary) -> void:
	if _hud_bus != null and _hud_bus.has_method("publish"):
		_hud_bus.call("publish", "agent", severity, text, metadata)


func _absolute_game_minute() -> int:
	return maxi(0, int(_season.total_days) - 1) * GAME_MINUTES_PER_DAY + maxi(0, int(_season.hour) - 6) * 60 + int(_season.minute)
