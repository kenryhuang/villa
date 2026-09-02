extends RefCounted

const AgentRuntimeScript = preload("res://scripts/ai_agent/agent_runtime.gd")
const MarketScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomyScript = preload("res://scripts/systems/npc_economy_system.gd")
const SeasonScript = preload("res://scripts/systems/season_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const DialogueScene = preload("res://scenes/ui/dialogue_ui.tscn")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var disabled_config_path := "user://agent-main-integration-disabled.json"
	var trace_directory := "user://agent-main-trace-%d" % Time.get_ticks_usec()
	var disabled_config := FileAccess.open(disabled_config_path, FileAccess.WRITE)
	disabled_config.store_string(JSON.stringify({
		"enabled": false,
		"service_url": "",
		"token": "",
		"timeout_seconds": 10,
		"store_agent_session": true,
		"agent_session_directory": trace_directory,
	}))
	disabled_config.close()
	var market := MarketScript.new()
	var economy := NpcEconomyScript.new()
	var season := SeasonScript.new()
	var runtime := AgentRuntimeScript.new()
	tree.root.add_child(market)
	tree.root.add_child(economy)
	tree.root.add_child(season)
	tree.root.add_child(runtime)
	market.configure(GameDataScript.get_market_items())
	economy.configure(market, GameDataScript.get_npc_economy_profiles(), GameDataScript.get_population_demand_profiles())
	assertions.truthy(runtime.configure(economy, market, season, null, disabled_config_path), "Agent runtime configures against authoritative systems")
	var initial_request: Dictionary = runtime.call("_build_request", "farmer_ahe", "dialogue", 0, "看看周围")
	for field in ["projection_schema_version", "actor_context", "active_role", "goals", "allowed_read_tools", "allowed_command_tools", "public_world_state", "global_public_events", "known_actors", "own_event_delta", "market_view", "interaction_view", "agreement_view"]:
		assertions.truthy(initial_request.has(field), "runtime request includes %s" % field)
	assertions.equal(initial_request.active_role, "farmer", "runtime request uses the active projected role")
	assertions.truthy(initial_request.allowed_read_tools.has("inspect_farm_plots"), "farmer receives farm read capability")
	assertions.truthy(initial_request.allowed_command_tools.has("plant"), "farmer receives role command capability")
	assertions.equal(initial_request.known_actors.size(), 3, "Agent sees two NPC Agents and the public Player actor")
	assertions.equal(initial_request.public_world_state.game_day, int(season.total_days), "public world state includes authoritative day")
	assertions.equal(initial_request.public_world_state.season, int(season.current_season), "public world state includes authoritative season")
	assertions.truthy(initial_request.market_view.has("grain"), "every Agent context includes current market")
	runtime.call("_handle_stream_failure", "farmer_ahe", str(initial_request.request_id), "fixture_release")

	runtime.call("_on_market_price_changed", "grain", 777)
	var market_requests: Dictionary = {}
	for agent_id in ["farmer_ahe", "lao_li", "xuezhe_lin"]:
		var request: Dictionary = runtime.call("_build_request", agent_id, "event", 1, "")
		market_requests[agent_id] = request
		assertions.truthy(_has_market_fact(request.own_event_delta, "grain", 777), "%s receives the same public market event" % agent_id)
	var farmer_response := {
		"protocol_version": 2,
		"decision_id": "ack-farmer",
		"request_id": str((market_requests.farmer_ahe as Dictionary).request_id),
		"agent_id": "farmer_ahe",
		"expected_revision": 0,
		"actions": [],
		"decision_summary": "已看到行情",
	}
	runtime.call("_handle_response", "farmer_ahe", farmer_response)
	var farmer_after_ack: Dictionary = runtime.call("_build_request", "farmer_ahe", "event", 2, "")
	assertions.truthy(not _has_market_fact(farmer_after_ack.own_event_delta, "grain", 777), "valid response acknowledges only farmer event delta")
	assertions.truthy(_has_market_fact((market_requests.lao_li as Dictionary).own_event_delta, "grain", 777), "farmer acknowledgement leaves merchant copy intact")
	runtime.call("_handle_stream_failure", "xuezhe_lin", str((market_requests.xuezhe_lin as Dictionary).request_id), "provider_timeout")
	var explorer_retry: Dictionary = runtime.call("_build_request", "xuezhe_lin", "event", 3, "")
	assertions.truthy(_has_market_fact(explorer_retry.own_event_delta, "grain", 777), "failed request releases explorer events for next context")
	assertions.truthy(
		str(runtime.get_session_trace().get_log_path()).begins_with(trace_directory + "/"),
		"runtime opens Agent trace in configured directory",
	)
	runtime.set_save_slot(3)
	assertions.truthy(
		str(runtime.get_session_trace().get_log_path()).begins_with(trace_directory + "/"),
		"save-slot change preserves configured Agent trace directory",
	)
	assertions.truthy(not runtime.service_enabled, "disabled client configuration keeps remote decisions off")
	var agent_settings: Array[Dictionary] = runtime.get_agent_debug_settings()
	assertions.equal(agent_settings.size(), 3, "runtime exposes all Agent debug settings")
	assertions.equal(agent_settings[0].display_name, "阿禾", "runtime settings use Agent display names")
	assertions.truthy(runtime.apply_agent_debug_intervals({"farmer_ahe": 0, "lao_li": 4, "xuezhe_lin": 12}), "runtime applies complete Agent interval overrides")
	assertions.equal(runtime.scheduler.get_decision_interval_hours("farmer_ahe"), 0, "runtime applies zero automatic interval")
	assertions.equal(runtime.scheduler.get_decision_interval_hours("lao_li"), 4, "runtime applies merchant automatic interval")
	assertions.truthy(not runtime.apply_agent_debug_intervals({"farmer_ahe": 1}), "runtime rejects incomplete Agent interval maps")
	assertions.truthy(economy.is_agent_managed("lao_li"), "merchant is removed from deterministic autonomy")
	assertions.truthy(economy.is_agent_managed("xuezhe_lin"), "explorer is removed from deterministic autonomy")
	assertions.truthy(economy.is_agent_managed("farmer_ahe"), "farmer is Agent managed")
	assertions.equal(runtime.farm_registry.get_plot("farmer_ahe", 11).plot_index, 11, "runtime creates twelve headless farmer plots")
	var batch_response := {
		"protocol_version": 2,
		"decision_id": "runtime-batch",
		"request_id": "runtime-request",
		"agent_id": "farmer_ahe",
		"expected_revision": 99,
		"actions": [
			{"action_id": "runtime-till", "idempotency_key": "v2:runtime:0:till", "tool_name": "till", "tool_version": 1, "arguments": {"plot": 0}},
			{"action_id": "runtime-plant", "idempotency_key": "v2:runtime:1:plant", "tool_name": "plant", "tool_version": 1, "arguments": {"plot": 0, "seed_item_id": "carrot_seed"}},
		],
		"decision_summary": "prepare one crop",
	}
	runtime.call("_handle_response", "farmer_ahe", batch_response)
	assertions.equal(runtime.farm_registry.get_plot("farmer_ahe", 0).state, "planted", "runtime executes every action in a v2 batch")
	assertions.equal(runtime.executor.world_revision, 2, "runtime batch commits one revision per mutation")
	var action_event_types := runtime.event_store.get_events_after(0).map(func(event: Dictionary): return str(event.event_type))
	assertions.truthy("FieldTilled" in action_event_types and "CropPlanted" in action_event_types, "committed farming actions enter the replayable Agent event log")
	var trade_response := {
		"protocol_version": 2, "decision_id": "runtime-trade", "request_id": "runtime-trade-request",
		"agent_id": "farmer_ahe", "expected_revision": 2, "decision_summary": "sell one seed",
		"actions": [{"action_id": "runtime-sell", "idempotency_key": "v2:runtime:sell", "tool_name": "sell", "tool_version": 1, "arguments": {"item_id": "carrot_seed", "quantity": 1}}],
	}
	runtime.call("_handle_response", "farmer_ahe", trade_response)
	action_event_types = runtime.event_store.get_events_after(0).map(func(event: Dictionary): return str(event.event_type))
	assertions.truthy("PublicMarketTradeExecuted" in action_event_types, "public Agent market trade enters the event log through the production response path")
	var eligible_role_change: Dictionary = runtime.role_system.propose_change("farmer_ahe", "merchant", "通过真实成交积累经验", 5, "runtime-role-after-trade")
	assertions.truthy(bool(eligible_role_change.get("approved", false)), "production market event satisfies configured merchant experience")
	var travel_response := {
		"protocol_version": 2, "decision_id": "runtime-travel", "request_id": "runtime-travel-request",
		"agent_id": "xuezhe_lin", "expected_revision": 3, "decision_summary": "travel to creek",
		"actions": [{"action_id": "runtime-travel", "idempotency_key": "v2:runtime:travel", "tool_name": "travel", "tool_version": 1, "arguments": {"region_id": "creek", "duration_minutes": 10}}],
	}
	runtime.call("_handle_response", "xuezhe_lin", travel_response)
	assertions.equal(runtime.world_projector.get_actor("xuezhe_lin").current_public_state.status, "traveling", "in-progress travel updates public Agent status")
	season.hour = 6
	season.minute = 10
	runtime.call("_on_time_changed", 6, 10)
	assertions.equal(runtime.world_projector.get_actor("xuezhe_lin").region_id, "creek", "completed travel updates projected Agent region")
	assertions.equal(runtime.world_projector.get_actor("xuezhe_lin").current_public_state.status, "idle", "completed travel restores public Agent status")
	var revision_before_empty: int = runtime.executor.world_revision
	var empty_response := batch_response.duplicate(true)
	empty_response.request_id = "runtime-empty-request"
	empty_response.decision_id = "runtime-empty"
	empty_response.actions = []
	runtime.call("_handle_response", "farmer_ahe", empty_response)
	assertions.equal(runtime.executor.world_revision, revision_before_empty, "empty runtime batch changes no world state")
	var dialogue_speech: Array[Array] = []
	runtime.dialogue_ready.connect(func(agent_id: String, request_id: String, speech: String): dialogue_speech.append([agent_id, request_id, speech]))
	runtime._request_triggers["runtime-dialogue-invalid-action"] = "dialogue"
	var dialogue_response := batch_response.duplicate(true)
	dialogue_response.request_id = "runtime-dialogue-invalid-action"
	dialogue_response.decision_id = "runtime-dialogue-invalid-action"
	dialogue_response.decision_summary = "我先回答你的问题。"
	dialogue_response.erase("speech")
	dialogue_response.actions = [{"tool_name": "unauthorized"}]
	runtime.call("_handle_response", "farmer_ahe", dialogue_response)
	assertions.equal(dialogue_speech, [["farmer_ahe", "runtime-dialogue-invalid-action", "我先回答你的问题。"]], "dialogue summary completes conversation even when world action rejects")
	var saved: Dictionary = runtime.to_dict()
	assertions.equal(saved.version, 4, "Agent world save uses event-sourced Runtime version")
	for field in ["event_schema_version", "event_store", "projection_checkpoint", "checkpoint_sequence", "perception_inbox", "roles", "interactions", "agreements"]:
		assertions.truthy(saved.has(field), "Agent world save includes %s" % field)
	assertions.equal(saved.checkpoint_sequence, int(saved.event_store.next_global_sequence) - 1, "checkpoint follows the complete saved event log")
	assertions.truthy((saved.event_store.events as Array).size() > 0, "Agent world save contains its replay log")
	var corrupt := saved.duplicate(true)
	corrupt.event_store = (saved.event_store as Dictionary).duplicate(true)
	corrupt.event_store.events = (saved.event_store.events as Array).duplicate(true)
	(corrupt.event_store.events as Array)[0] = ((corrupt.event_store.events as Array)[0] as Dictionary).duplicate(true)
	(corrupt.event_store.events as Array)[0].global_sequence = 2
	var before_corrupt_restore := runtime.to_dict()
	assertions.truthy(not runtime.from_dict(corrupt), "corrupt Agent event log is rejected atomically")
	assertions.equal(runtime.to_dict(), before_corrupt_restore, "failed Agent restore leaves live state unchanged")
	var restored := AgentRuntimeScript.new()
	tree.root.add_child(restored)
	assertions.truthy(restored.configure(economy, market, season, null, disabled_config_path), "second runtime configures")
	var json_saved: Dictionary = JSON.parse_string(JSON.stringify(saved))
	assertions.truthy(runtime.event_store.validate_dict(json_saved.event_store), "JSON event store validates")
	assertions.truthy(runtime.world_projector.validate_dict(json_saved.projection_checkpoint), "JSON projection checkpoint validates")
	assertions.truthy(runtime.perception_inbox.validate_dict(json_saved.perception_inbox, int(json_saved.checkpoint_sequence)), "JSON perception cursors validate")
	assertions.truthy(runtime.role_system.validate_dict(json_saved.roles), "JSON role state validates")
	assertions.truthy(runtime.interaction_system.validate_dict(json_saved.interactions), "JSON interaction state validates")
	assertions.truthy(runtime.agreement_system.validate_dict(json_saved.agreements), "JSON agreement state validates")
	assertions.truthy(restored.from_dict(json_saved), "Agent world state restores after JSON round trip")
	assertions.equal(
		runtime.call("_canonical_json_value", restored.to_dict()),
		runtime.call("_canonical_json_value", saved),
		"Agent world state JSON round trip is semantically stable",
	)
	var first_runtime_request: Dictionary = runtime.call("_build_request", "lao_li", "dialogue", 100, "第一条问题")
	var second_runtime_request: Dictionary = restored.call("_build_request", "lao_li", "dialogue", 100, "第一条问题")
	assertions.truthy(
		str(first_runtime_request.request_id) != str(second_runtime_request.request_id),
		"separate game runtimes never reuse the same Agent request ID",
	)
	for legacy_version in [2, 3]:
		var legacy := saved.duplicate(true)
		legacy.version = legacy_version
		for field in ["event_schema_version", "event_store", "projection_checkpoint", "checkpoint_sequence", "perception_inbox", "roles", "interactions", "agreements"]:
			legacy.erase(field)
		var migrated := AgentRuntimeScript.new()
		tree.root.add_child(migrated)
		assertions.truthy(migrated.configure(economy, market, season, null, disabled_config_path), "legacy v%d migration runtime configures" % legacy_version)
		assertions.truthy(migrated.from_dict(legacy), "legacy v%d Agent state migrates" % legacy_version)
		var migrated_events: Array = migrated.event_store.get_events_after(0)
		assertions.equal(migrated_events.size(), 1, "legacy v%d migration creates one deterministic bootstrap event" % legacy_version)
		assertions.equal(str((migrated_events[0] as Dictionary).event_type), "AgentWorldBootstrapped", "legacy v%d migration records bootstrap event" % legacy_version)
		migrated.free()
	var save_manager = tree.root.get_node("SaveManager")
	assertions.truthy(save_manager.configure_agent_runtime(runtime), "SaveManager accepts Agent runtime")
	assertions.truthy(runtime.configure_save_manager(save_manager), "runtime coordinates asynchronous memory sidecars")
	assertions.equal(save_manager.call("_gather_save_data").agent_world, runtime.to_dict(), "SaveManager gathers Agent world state")
	assertions.truthy(runtime.gateway.has_method("export_checkpoint"), "gateway exports memory checkpoints")
	assertions.truthy(runtime.gateway.has_method("import_checkpoint"), "gateway imports memory checkpoints")
	var dialogue = DialogueScene.instantiate()
	assertions.truthy(dialogue.has_method("start_agent_dialogue"), "Dialogue UI exposes AI speech entry")
	assertions.truthy(dialogue.has_method("open_agent_dialogue"), "Dialogue UI exposes immediate conversation opening")
	assertions.truthy(dialogue.has_method("get_agent_history"), "Dialogue UI exposes per-Agent conversation history")
	assertions.truthy(dialogue.has_method("begin_agent_dialogue"), "Dialogue UI exposes streaming begin")
	assertions.truthy(dialogue.has_method("append_agent_dialogue"), "Dialogue UI exposes streaming append")
	assertions.truthy(dialogue.has_method("finish_agent_dialogue"), "Dialogue UI exposes streaming finish")
	assertions.truthy(dialogue.has_method("fail_agent_dialogue"), "Dialogue UI exposes streaming failure")
	assertions.truthy(dialogue.has_signal("agent_dialogue_cancelled"), "Dialogue UI exposes streaming cancellation")
	assertions.truthy(dialogue.has_signal("agent_dialogue_closed"), "Dialogue UI exposes request-scoped close")
	assertions.truthy(dialogue.has_signal("agent_message_submitted"), "Dialogue UI exposes player message submission")
	var fail_argument_count := -1
	for method_record in dialogue.get_method_list():
		if str(method_record.name) == "fail_agent_dialogue":
			fail_argument_count = (method_record.args as Array).size()
			break
	assertions.equal(fail_argument_count, 1, "stream failure API accepts only request ID")
	dialogue.free()
	restored.free()
	runtime.free()
	season.free()
	economy.free()
	market.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(disabled_config_path))
	var absolute_trace_directory := ProjectSettings.globalize_path(trace_directory)
	if DirAccess.dir_exists_absolute(absolute_trace_directory):
		for file_name in DirAccess.get_files_at(trace_directory):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(trace_directory.path_join(file_name)))
		DirAccess.remove_absolute(absolute_trace_directory)


func _has_market_fact(events: Array, item_id: String, price: int) -> bool:
	for value in events:
		var event := value as Dictionary
		var payload := event.get("payload", {}) as Dictionary
		if str(event.get("event_type", "")) == "MarketPriceChanged" and str(payload.get("item_id", "")) == item_id and int(payload.get("price", -1)) == price:
			return true
	return false
