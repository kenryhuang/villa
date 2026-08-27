extends RefCounted

const MainScript = preload("res://scripts/main.gd")
const NpcScene = preload("res://scenes/actors/npc.tscn")


class RuntimeDouble:
	extends Node

	var trigger_result := true
	var triggered: Array[String] = []
	var cancelled: Array[Dictionary] = []
	var applied_intervals: Array[Dictionary] = []

	func is_agent_managed(agent_id: String) -> bool:
		return agent_id in ["farmer_ahe", "lao_li", "xuezhe_lin"]

	func trigger_dialogue(agent_id: String, _text: String = "") -> bool:
		triggered.append(agent_id)
		return trigger_result

	func cancel_dialogue(agent_id: String, request_id: String) -> bool:
		cancelled.append({"agent_id": agent_id, "request_id": request_id})
		return true

	func get_agent_debug_settings() -> Array[Dictionary]:
		return [
			{"agent_id": "farmer_ahe", "display_name": "阿禾", "decision_interval_hours": 1},
			{"agent_id": "lao_li", "display_name": "老李", "decision_interval_hours": 2},
			{"agent_id": "xuezhe_lin", "display_name": "学者林", "decision_interval_hours": 4},
		]

	func apply_agent_debug_intervals(intervals: Dictionary) -> bool:
		applied_intervals.append(intervals.duplicate(true))
		return true


class DebugPanelDouble:
	extends Node

	signal agent_settings_apply_requested(intervals: Dictionary)

	var configured: Array[Dictionary] = []
	var results: Array[bool] = []

	func configure_agent_settings(settings: Array[Dictionary]) -> bool:
		configured = settings.duplicate(true)
		return true

	func show_agent_settings_result(ok: bool) -> void:
		results.append(ok)


class DialogueDouble:
	extends Node

	signal agent_dialogue_cancelled(villager_id: String, request_id: String)
	signal agent_dialogue_closed(villager_id: String, request_id: String)

	var fixed_dialogue_calls := 0
	var failed_requests: Array[Array] = []
	var begun_requests: Array[Array] = []

	func start_dialogue(_villager_id: String) -> void:
		fixed_dialogue_calls += 1

	func fail_agent_dialogue(request_id: String, fallback: String = "__omitted__") -> bool:
		failed_requests.append([request_id, fallback])
		return true

	func begin_agent_dialogue(villager_id: String, request_id: String) -> void:
		begun_requests.append([villager_id, request_id])


class HudBusDouble:
	extends Node

	var records: Array[Dictionary] = []

	func publish(source: String, severity: String, message: String, metadata: Dictionary = {}) -> bool:
		records.append({
			"source": source,
			"severity": severity,
			"message": message,
			"metadata": metadata.duplicate(true),
		})
		return true


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var main_script: Script = MainScript
	var script_constants: Dictionary = main_script.get_script_constant_map()
	var bindings: Dictionary = script_constants.get("AGENT_NPC_BINDINGS", {})
	var main_probe = MainScript.new()
	var has_route: bool = main_probe.has_method("get_agent_npc")
	var has_close: bool = main_probe.has_method("_on_agent_dialogue_closed")
	assertions.truthy(
		"NpcNorthwest" in bindings,
		"Main declares the northwest Agent NPC binding"
	)
	assertions.truthy(has_route, "Main exposes Agent-to-NPC routing")
	assertions.truthy(has_close, "Main handles dialogue close")
	main_probe.free()
	if not "NpcNorthwest" in bindings or not has_route or not has_close:
		return
	assertions.equal(
		str((bindings.NpcNorthwest as Dictionary).agent_id),
		"farmer_ahe",
		"northwest NPC is farmer Ahe"
	)
	assertions.equal(
		str((bindings.NpcSouth as Dictionary).agent_id),
		"lao_li",
		"south NPC is merchant Lao Li"
	)
	assertions.equal(
		str((bindings.NpcEast as Dictionary).agent_id),
		"xuezhe_lin",
		"east NPC is explorer Xuezhe Lin"
	)

	var fixture_root := Node3D.new()
	var player := Node3D.new()
	var npcs := Node3D.new()
	fixture_root.add_child(player)
	fixture_root.add_child(npcs)
	for node_name in ["NpcNorthwest", "NpcSouth", "NpcEast"]:
		var npc = NpcScene.instantiate()
		npc.name = node_name
		npcs.add_child(npc)
	tree.root.add_child(fixture_root)
	var main = MainScript.new()
	var runtime := RuntimeDouble.new()
	var dialogue := DialogueDouble.new()
	var hud := HudBusDouble.new()
	var debug_panel := DebugPanelDouble.new()
	main.player = player
	main.npcs = npcs
	main.world = null
	main.agent_runtime = runtime
	main.dialogue_ui = dialogue
	main.hud_message_bus = hud
	main.debug_panel = debug_panel
	main.call("_setup_npcs")

	var farmer = main.npcs.get_node("NpcNorthwest")
	var merchant = main.npcs.get_node("NpcSouth")
	var explorer = main.npcs.get_node("NpcEast")
	assertions.equal(farmer.villager_id, "farmer_ahe", "farmer scene node receives Agent ID")
	assertions.equal(merchant.villager_id, "lao_li", "merchant scene node receives Agent ID")
	assertions.equal(explorer.villager_id, "xuezhe_lin", "explorer scene node receives Agent ID")
	assertions.equal(main.call("get_agent_npc", "farmer_ahe"), farmer, "Main routes farmer by Agent ID")
	assertions.equal(main.call("get_agent_npc", "lao_li"), merchant, "Main routes merchant by Agent ID")
	assertions.equal(main.call("get_agent_npc", "xuezhe_lin"), explorer, "Main routes explorer by Agent ID")
	assertions.truthy(main.has_method("_connect_agent_debug_settings"), "Main exposes focused Agent debug settings wiring")
	if main.has_method("_connect_agent_debug_settings"):
		assertions.truthy(main.call("_connect_agent_debug_settings"), "Main configures Agent debug settings")
		assertions.equal(debug_panel.configured.size(), 3, "Main sends every Agent setting to debug panel")
		debug_panel.agent_settings_apply_requested.emit({"farmer_ahe": 0, "lao_li": 2, "xuezhe_lin": 4})
		assertions.equal(runtime.applied_intervals, [{"farmer_ahe": 0, "lao_li": 2, "xuezhe_lin": 4}], "Main routes Agent interval settings to runtime")
		assertions.equal(debug_panel.results, [true], "Main returns Agent settings result to panel")

	farmer.set_dialogue_busy(true)
	main.call("_on_dialogue_started", "farmer_ahe")
	assertions.equal(runtime.triggered, ["farmer_ahe"], "farmer intent starts Agent runtime")
	assertions.truthy(farmer.is_dialogue_busy(), "accepted request keeps farmer busy")
	assertions.truthy(not merchant.is_dialogue_busy(), "accepted farmer request does not lock merchant")

	runtime.trigger_result = false
	merchant.set_dialogue_busy(true)
	main.call("_on_dialogue_started", "lao_li")
	assertions.equal(runtime.triggered, ["farmer_ahe", "lao_li"], "merchant intent attempts one request")
	assertions.truthy(not merchant.is_dialogue_busy(), "failed request immediately unlocks merchant")
	assertions.truthy(farmer.is_dialogue_busy(), "merchant failure does not unlock farmer")
	assertions.equal(dialogue.fixed_dialogue_calls, 0, "managed Agent never opens fixed dialogue")
	assertions.equal(hud.records.size(), 1, "failed request publishes one warning")
	if not hud.records.is_empty():
		assertions.equal(hud.records[0].source, "agent", "service warning uses Agent source")
		assertions.equal(hud.records[0].severity, "warning", "service warning has warning severity")
		assertions.equal(
			hud.records[0].message,
			"Agent 服务不可用，请稍后再试。",
			"service warning uses the shared message"
		)
		assertions.equal(hud.records[0].metadata.agent_id, "lao_li", "warning identifies failed Agent")

	main.call("_on_agent_dialogue_stream_started", "farmer_ahe", "dialogue-request-1")
	assertions.equal(
		dialogue.begun_requests,
		[["farmer_ahe", "dialogue-request-1"]],
		"stream start records the active Agent request"
	)
	main.call("_on_agent_dialogue_cancelled", "farmer_ahe", "dialogue-request-1")
	assertions.equal(
		runtime.cancelled,
		[{"agent_id": "farmer_ahe", "request_id": "dialogue-request-1"}],
		"dialogue cancellation preserves Agent and request identity"
	)
	main.call("_on_agent_dialogue_closed", "farmer_ahe", "dialogue-request-1")
	assertions.truthy(not farmer.is_dialogue_busy(), "closing dialogue unlocks only its NPC")
	assertions.truthy(not merchant.is_dialogue_busy(), "merchant remains in its own unlocked state")

	farmer.set_dialogue_busy(true)
	main.call("_on_agent_dialogue_stream_started", "farmer_ahe", "dialogue-request-current")
	var cancellation_count_before_stale := runtime.cancelled.size()
	main.call("_on_agent_dialogue_cancelled", "farmer_ahe", "dialogue-request-stale")
	main.call("_on_agent_dialogue_closed", "farmer_ahe", "dialogue-request-stale")
	assertions.equal(
		runtime.cancelled.size(),
		cancellation_count_before_stale,
		"stale close cannot cancel the current request"
	)
	assertions.truthy(farmer.is_dialogue_busy(), "stale close cannot unlock the current request")
	main.call("_on_agent_dialogue_closed", "farmer_ahe", "dialogue-request-current")
	assertions.truthy(not farmer.is_dialogue_busy(), "matching close unlocks the current request")

	merchant.set_dialogue_busy(true)
	explorer.set_dialogue_busy(true)
	main.call("_on_agent_dialogue_stream_failed", "xuezhe_lin", "dialogue-request-2", "timeout")
	assertions.equal(
		dialogue.failed_requests,
		[["dialogue-request-2", "__omitted__"]],
		"stream failure clears dialogue without fallback speech"
	)
	assertions.truthy(not explorer.is_dialogue_busy(), "stream failure unlocks failed explorer")
	assertions.truthy(merchant.is_dialogue_busy(), "explorer failure does not unlock merchant")
	assertions.equal(hud.records.size(), 2, "stream failure publishes one additional warning")
	if hud.records.size() >= 2:
		assertions.equal(hud.records[1].message, "Agent 服务不可用，请稍后再试。", "stream failure uses shared warning")
		assertions.equal(hud.records[1].metadata.agent_id, "xuezhe_lin", "stream warning identifies explorer")

	assertions.truthy(
		main.has_method("_connect_agent_dialogue_ui"),
		"Main exposes focused Agent dialogue lifecycle wiring"
	)
	if main.has_method("_connect_agent_dialogue_ui"):
		main.call("_connect_agent_dialogue_ui")
		farmer.set_dialogue_busy(true)
		main.call("_on_agent_dialogue_stream_started", "farmer_ahe", "dialogue-request-3")
		dialogue.agent_dialogue_cancelled.emit("farmer_ahe", "dialogue-request-3")
		dialogue.agent_dialogue_closed.emit("farmer_ahe", "dialogue-request-3")
		assertions.equal(
			runtime.cancelled[-1],
			{"agent_id": "farmer_ahe", "request_id": "dialogue-request-3"},
			"wired cancel signal reaches Agent runtime"
		)
		assertions.truthy(not farmer.is_dialogue_busy(), "wired close signal unlocks farmer")

	main.free()
	fixture_root.free()
	runtime.free()
	dialogue.free()
	hud.free()
	debug_panel.free()
