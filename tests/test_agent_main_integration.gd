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
	var revision_before_empty: int = runtime.executor.world_revision
	var empty_response := batch_response.duplicate(true)
	empty_response.request_id = "runtime-empty-request"
	empty_response.decision_id = "runtime-empty"
	empty_response.actions = []
	runtime.call("_handle_response", "farmer_ahe", empty_response)
	assertions.equal(runtime.executor.world_revision, revision_before_empty, "empty runtime batch changes no world state")
	var saved: Dictionary = runtime.to_dict()
	var restored := AgentRuntimeScript.new()
	tree.root.add_child(restored)
	assertions.truthy(restored.configure(economy, market, season, null, disabled_config_path), "second runtime configures")
	assertions.truthy(restored.from_dict(saved), "Agent world state restores")
	assertions.equal(restored.to_dict(), saved, "Agent world state round trip is stable")
	var save_manager = tree.root.get_node("SaveManager")
	assertions.truthy(save_manager.configure_agent_runtime(runtime), "SaveManager accepts Agent runtime")
	assertions.truthy(runtime.configure_save_manager(save_manager), "runtime coordinates asynchronous memory sidecars")
	assertions.equal(save_manager.call("_gather_save_data").agent_world, runtime.to_dict(), "SaveManager gathers Agent world state")
	assertions.truthy(runtime.gateway.has_method("export_checkpoint"), "gateway exports memory checkpoints")
	assertions.truthy(runtime.gateway.has_method("import_checkpoint"), "gateway imports memory checkpoints")
	var dialogue = DialogueScene.instantiate()
	assertions.truthy(dialogue.has_method("start_agent_dialogue"), "Dialogue UI exposes AI speech entry")
	assertions.truthy(dialogue.has_method("begin_agent_dialogue"), "Dialogue UI exposes streaming begin")
	assertions.truthy(dialogue.has_method("append_agent_dialogue"), "Dialogue UI exposes streaming append")
	assertions.truthy(dialogue.has_method("finish_agent_dialogue"), "Dialogue UI exposes streaming finish")
	assertions.truthy(dialogue.has_method("fail_agent_dialogue"), "Dialogue UI exposes streaming failure")
	assertions.truthy(dialogue.has_signal("agent_dialogue_cancelled"), "Dialogue UI exposes streaming cancellation")
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
