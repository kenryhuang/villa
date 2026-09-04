extends RefCounted

const AgentRuntimeScript = preload("res://scripts/ai_agent/agent_runtime.gd")
const MarketScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomyScript = preload("res://scripts/systems/npc_economy_system.gd")
const SeasonScript = preload("res://scripts/systems/season_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const DialogueScene = preload("res://scenes/ui/dialogue_ui.tscn")
const InventoryScript = preload("res://scripts/systems/inventory_system.gd")
const GameStateScript = preload("res://scripts/core/game_state.gd")


class FailOnceMarketPressureBridge:
	extends RefCounted
	var delegate: Variant
	var attempts := 0

	func publish_market_pressure(total_day: int, pressure: Dictionary, game_minute: int, source_id: String) -> bool:
		attempts += 1
		if attempts == 1:
			return false
		return bool(delegate.call("publish_market_pressure", total_day, pressure, game_minute, source_id))


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
	for field in ["projection_schema_version", "actor_context", "active_role", "goals", "allowed_read_tools", "allowed_command_tools", "public_world_state", "global_public_events", "known_actors", "own_event_delta", "market_summary", "market_view", "interaction_view", "agreement_view"]:
		assertions.truthy(initial_request.has(field), "runtime request includes %s" % field)
	assertions.truthy(not initial_request.has("snapshot"), "v2 request omits legacy snapshot")
	assertions.truthy(not initial_request.has("event_delta"), "v2 request omits legacy event delta")
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
		assertions.truthy(_has_market_fact(request.global_public_events, "grain", 777), "%s receives the shared public market event" % agent_id)
		assertions.truthy(not _has_market_fact(request.own_event_delta, "grain", 777), "%s does not receive the same market event twice" % agent_id)
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
	assertions.truthy(_has_market_fact((market_requests.lao_li as Dictionary).global_public_events, "grain", 777), "farmer acknowledgement leaves public history intact")
	runtime.call("_handle_stream_failure", "xuezhe_lin", str((market_requests.xuezhe_lin as Dictionary).request_id), "provider_timeout")
	var explorer_retry: Dictionary = runtime.call("_build_request", "xuezhe_lin", "event", 3, "")
	assertions.truthy(_has_market_fact(explorer_retry.global_public_events, "grain", 777), "failed request keeps public history visible on the next context")
	assertions.truthy(not _has_market_fact(explorer_retry.own_event_delta, "grain", 777), "released public event remains de-duplicated on retry")
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
	var player_inventory := InventoryScript.new()
	var player_wallet := GameStateScript.new()
	tree.root.add_child(player_inventory)
	tree.root.add_child(player_wallet)
	player_inventory.add_item("salt", 2)
	player_wallet.gold = 20
	assertions.truthy(runtime.configure_player_assets(player_inventory, player_wallet), "runtime configures Player assets for interaction commands")
	var player_offer := runtime.interaction_system.execute({"agent_id": "farmer_ahe", "tool_name": "propose_trade", "arguments": {"target_actor_id": "player", "give": {"items": {"carrot_seed": 1}, "gold": 0}, "receive": {"items": {"salt": 1}, "gold": 0}, "expires_in_minutes": 120, "note": "test"}, "idempotency_key": "runtime-player-offer", "action_id": "runtime-player-offer", "decision_id": "runtime-player-offer"}, 20)
	assertions.truthy(player_offer.ok, "runtime fixture creates a pending Player trade")
	var player_counter := runtime.respond_to_player_interaction("farmer_ahe", str(player_offer.offer_id), "counter", {"give": {"items": {"salt": 1}, "gold": 3}, "receive": {"items": {"carrot_seed": 1}, "gold": 0}, "expires_in_minutes": 180, "counter_note": "edited"})
	assertions.truthy(player_counter.ok, "Player counter command accepts complete edited trade terms")
	var counter_offer := runtime.interaction_system.get_offer(str(player_counter.offer_id), "player")
	assertions.equal(counter_offer.proposer_gives.gold, 3, "runtime uses edited trade terms instead of reconstructing the old offer")
	var agreement_terms := {"objective_id": "joint_crop_supply", "participants": ["player"], "commitments": [{"participant_id": "farmer_ahe", "items": {}, "gold": 0}, {"participant_id": "player", "items": {}, "gold": 0}], "reward_split": {"farmer_ahe": 1, "player": 1}, "deadline_minutes": 120, "note": "runtime save fixture"}
	var player_agreement := runtime.agreement_system.execute({"agent_id": "farmer_ahe", "tool_name": "propose_cooperation", "arguments": agreement_terms, "idempotency_key": "runtime-player-agreement", "action_id": "runtime-player-agreement", "decision_id": "runtime-player-agreement"}, 21)
	assertions.truthy(player_agreement.ok, "runtime fixture creates a pending Player agreement")
	var real_fact_bridge = runtime.world_fact_bridge
	var fail_once_bridge := FailOnceMarketPressureBridge.new()
	fail_once_bridge.delegate = real_fact_bridge
	runtime.world_fact_bridge = fail_once_bridge
	runtime.call("_on_market_pressure_settled", 1, {"day": 1, "items": {}})
	assertions.equal(fail_once_bridge.attempts, 1, "failed market-pressure publication is retained for retry")
	assertions.equal(runtime.to_dict().pending_market_pressure_facts.size(), 1, "failed market-pressure fact is persisted")
	runtime.world_fact_bridge = real_fact_bridge
	assertions.truthy(runtime.call("_retry_pending_market_pressure_facts"), "pending market-pressure fact retries through the real bridge")
	assertions.equal(runtime.to_dict().pending_market_pressure_facts, [], "successful correction clears the pending market-pressure fact")
	var saved: Dictionary = runtime.to_dict()
	assertions.equal(saved.version, 5, "Agent world save uses event-sourced Runtime version")
	for field in ["event_schema_version", "event_store", "projection_checkpoint", "checkpoint_sequence", "perception_inbox", "roles", "interactions", "agreements", "pending_market_pressure_facts"]:
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
	var role_tamper := saved.duplicate(true)
	role_tamper.session_id = "tampered-session"
	role_tamper.roles = (saved.roles as Dictionary).duplicate(true)
	role_tamper.roles.roles = (saved.roles.roles as Array).duplicate(true)
	for index in range((role_tamper.roles.roles as Array).size()):
		if str((role_tamper.roles.roles[index] as Dictionary).agent_id) == "farmer_ahe":
			role_tamper.roles.roles[index] = (role_tamper.roles.roles[index] as Dictionary).duplicate(true)
			role_tamper.roles.roles[index].active_role_id = "explorer"
			role_tamper.roles.roles[index].history = ["farmer", "explorer"]
	assertions.truthy(runtime.role_system.validate_dict(role_tamper.roles), "tampered runtime role snapshot remains structurally valid")
	assertions.truthy(not runtime.from_dict(role_tamper), "runtime rejects a role snapshot that disagrees with the event log")
	assertions.equal(runtime.to_dict(), before_corrupt_restore, "rejected event-derived state preserves session, registry role, and all live state")
	var old_v4 := saved.duplicate(true)
	old_v4.version = 4
	old_v4.erase("pending_market_pressure_facts")
	assertions.truthy(not runtime.validate_dict(old_v4), "obsolete development-only v4 Agent saves are rejected explicitly")
	var trade_tamper := saved.duplicate(true)
	trade_tamper.interactions = (saved.interactions as Dictionary).duplicate(true)
	trade_tamper.interactions.offers = (saved.interactions.offers as Array).duplicate(true)
	trade_tamper.interactions.offers[0] = (trade_tamper.interactions.offers[0] as Dictionary).duplicate(true)
	trade_tamper.interactions.offers[0].offer = (trade_tamper.interactions.offers[0].offer as Dictionary).duplicate(true)
	trade_tamper.interactions.offers[0].offer.status = "cancelled"
	assertions.truthy(not runtime.validate_dict(trade_tamper), "runtime rejects a trade snapshot that disagrees with the event log")
	var agreement_tamper := saved.duplicate(true)
	agreement_tamper.agreements = (saved.agreements as Dictionary).duplicate(true)
	agreement_tamper.agreements.agreements = (saved.agreements.agreements as Array).duplicate(true)
	agreement_tamper.agreements.agreements[0] = (agreement_tamper.agreements.agreements[0] as Dictionary).duplicate(true)
	agreement_tamper.agreements.agreements[0].agreement = (agreement_tamper.agreements.agreements[0].agreement as Dictionary).duplicate(true)
	agreement_tamper.agreements.agreements[0].agreement.status = "cancelled"
	assertions.truthy(not runtime.validate_dict(agreement_tamper), "runtime rejects an agreement snapshot that disagrees with the event log")
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
	assertions.truthy(runtime.role_system.validate_against_events(json_saved.roles, runtime.event_store.get_events_after(0)), "JSON role state agrees with event history")
	assertions.truthy(runtime.interaction_system.validate_against_events(json_saved.interactions, runtime.event_store.get_events_after(0)), "JSON interaction state agrees with event history")
	assertions.truthy(runtime.agreement_system.validate_against_events(json_saved.agreements, runtime.event_store.get_events_after(0)), "JSON agreement state agrees with event history")
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
	player_inventory.free()
	player_wallet.free()
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
