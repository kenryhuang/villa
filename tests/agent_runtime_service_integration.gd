extends SceneTree

const AgentRuntimeScript = preload("res://scripts/ai_agent/agent_runtime.gd")
const MarketScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomyScript = preload("res://scripts/systems/npc_economy_system.gd")
const SeasonScript = preload("res://scripts/systems/season_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")

var _finished := false
var _measured_request_bytes := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var market := MarketScript.new()
	var economy := NpcEconomyScript.new()
	var season := SeasonScript.new()
	var runtime := AgentRuntimeScript.new()
	root.add_child(market)
	root.add_child(economy)
	root.add_child(season)
	root.add_child(runtime)
	market.configure(GameDataScript.get_market_items())
	economy.configure(
		market,
		GameDataScript.get_npc_economy_profiles(),
		GameDataScript.get_population_demand_profiles(),
	)
	if not runtime.configure(economy, market, season, null):
		_fail("runtime_configure_failed")
		return
	if not runtime.service_enabled:
		print("SKIP: Agent Runtime service integration requires an enabled client config")
		quit(0)
		return
	var measured_request: Dictionary = runtime.call(
		"_build_request", "farmer_ahe", "dialogue", 0, "请求体大小检查"
	)
	if measured_request.has("snapshot") or measured_request.has("event_delta"):
		_fail("legacy_request_fields")
		return
	_measured_request_bytes = JSON.stringify(measured_request).to_utf8_buffer().size()
	if _measured_request_bytes >= 131072:
		_fail("runtime_request_too_large:%d" % _measured_request_bytes)
		return
	runtime.call(
		"_handle_stream_failure",
		"farmer_ahe",
		str(measured_request.request_id),
		"measurement",
	)
	runtime.dialogue_ready.connect(func(agent_id: String, _request_id: String, speech: String):
		if agent_id == "farmer_ahe" and not speech.is_empty():
			_finish_success()
	)
	runtime.dialogue_stream_failed.connect(func(agent_id: String, _request_id: String, error: String):
		if agent_id == "farmer_ahe":
			_fail(error)
	)
	if not runtime.trigger_dialogue("farmer_ahe", "今天适合种什么？"):
		_fail("dialogue_not_dispatched")
		return
	await create_timer(65.0).timeout
	if not _finished:
		_fail("runtime_dialogue_timeout")


func _finish_success() -> void:
	if _finished:
		return
	_finished = true
	print("PASS: Agent Runtime reaches configured service (request_bytes=%d)" % _measured_request_bytes)
	quit(0)


func _fail(error: String) -> void:
	if _finished:
		return
	_finished = true
	push_error("Agent Runtime service integration failed: " + error)
	quit(1)
