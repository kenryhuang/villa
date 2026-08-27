extends RefCounted

const MainScript = preload("res://scripts/main.gd")
const NpcScene = preload("res://scenes/actors/npc.tscn")


class RuntimeDouble:
	extends Node

	var trigger_result := true
	var triggered: Array[Dictionary] = []
	var cancelled: Array[Dictionary] = []
	var applied_intervals: Array[Dictionary] = []
	var active_requests: Dictionary = {}
	var request_sequence := 0

	func is_agent_managed(agent_id: String) -> bool:
		return agent_id in ["farmer_ahe", "lao_li", "xuezhe_lin"]

	func get_agent_display_name(agent_id: String) -> String:
		return {"farmer_ahe": "阿禾", "lao_li": "老李", "xuezhe_lin": "学者林"}.get(agent_id, agent_id)

	func trigger_dialogue(agent_id: String, text: String = "") -> bool:
		triggered.append({"agent_id": agent_id, "text": text})
		if not trigger_result:
			return false
		request_sequence += 1
		active_requests[agent_id] = "%s-dialogue-%d" % [agent_id, request_sequence]
		return true

	func get_in_flight_request_id(agent_id: String) -> String:
		return str(active_requests.get(agent_id, ""))

	func cancel_dialogue(agent_id: String, request_id: String) -> bool:
		cancelled.append({"agent_id": agent_id, "request_id": request_id})
		active_requests.erase(agent_id)
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

	signal agent_message_submitted(villager_id: String, message: String)
	signal agent_dialogue_cancelled(villager_id: String, request_id: String)
	signal agent_dialogue_closed(villager_id: String, request_id: String)

	var opened: Array[Array] = []
	var failed_submissions: Array[Array] = []
	var failed_requests: Array[Array] = []
	var begun_requests: Array[Array] = []
	var appended_deltas: Array[Array] = []
	var finished_requests: Array[Array] = []

	func open_agent_dialogue(villager_id: String, display_name: String) -> bool:
		opened.append([villager_id, display_name])
		return true

	func fail_agent_submission(villager_id: String, message: String) -> bool:
		failed_submissions.append([villager_id, message])
		return true

	func fail_agent_dialogue(request_id: String) -> bool:
		failed_requests.append([request_id])
		return true

	func begin_agent_dialogue(villager_id: String, request_id: String) -> void:
		begun_requests.append([villager_id, request_id])

	func append_agent_dialogue(request_id: String, delta: String) -> void:
		appended_deltas.append([request_id, delta])

	func finish_agent_dialogue(request_id: String, speech: String) -> void:
		finished_requests.append([request_id, speech])


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
	var farmer_nameplate := farmer.get_node_or_null("Nameplate") as Label3D
	assertions.truthy(farmer_nameplate != null, "visible Agent NPC owns a nameplate")
	if farmer_nameplate != null:
		assertions.equal(farmer_nameplate.text, "阿禾", "visible farmer nameplate uses Agent display name")
		assertions.truthy(farmer_nameplate.visible, "visible farmer nameplate remains shown")
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

	assertions.truthy(
		main.has_method("_connect_agent_dialogue_ui"),
		"Main exposes focused Agent dialogue lifecycle wiring"
	)
	if main.has_method("_connect_agent_dialogue_ui"):
		main.call("_connect_agent_dialogue_ui")
		farmer.set_dialogue_busy(true)
		main.call("_on_dialogue_started", "farmer_ahe")
		assertions.equal(dialogue.opened, [["farmer_ahe", "阿禾"]], "NPC click opens composer immediately")
		assertions.equal(runtime.triggered.size(), 0, "opening composer sends no empty Agent request")
		dialogue.agent_message_submitted.emit("farmer_ahe", "今天适合种什么？")
		assertions.equal(runtime.triggered, [{"agent_id": "farmer_ahe", "text": "今天适合种什么？"}], "player submission sends exact dialogue text")
		var farmer_request := runtime.get_in_flight_request_id("farmer_ahe")
		assertions.equal(dialogue.begun_requests, [["farmer_ahe", farmer_request]], "accepted submission immediately binds request identity")
		main.call("_on_agent_dialogue_stream_started", "farmer_ahe", farmer_request)
		assertions.equal(dialogue.begun_requests.size(), 1, "stream start does not bind the same request twice")
		main.call("_on_agent_dialogue_stream_delta", "farmer_ahe", farmer_request, "胡萝卜不错。")
		assertions.equal(dialogue.appended_deltas, [[farmer_request, "胡萝卜不错。"]], "matching stream delta reaches open conversation")
		main.call("_on_agent_dialogue_ready", "farmer_ahe", farmer_request, "胡萝卜不错。")
		assertions.equal(dialogue.finished_requests, [[farmer_request, "胡萝卜不错。"]], "final speech completes matching conversation turn")
		assertions.truthy(farmer.is_dialogue_busy(), "completed turn keeps NPC reserved while window is open")
		dialogue.agent_dialogue_closed.emit("farmer_ahe", "")
		assertions.truthy(not farmer.is_dialogue_busy(), "closing completed conversation unlocks NPC")

		runtime.trigger_result = false
		merchant.set_dialogue_busy(true)
		main.call("_on_dialogue_started", "lao_li")
		dialogue.agent_message_submitted.emit("lao_li", "今天行情如何？")
		assertions.equal(dialogue.failed_submissions, [["lao_li", "Agent 服务不可用，请稍后再试。"]], "synchronous request failure stays visible in composer")
		assertions.truthy(merchant.is_dialogue_busy(), "request failure keeps NPC reserved while conversation remains open")
		assertions.equal(hud.records.size(), 1, "request failure publishes one warning")
		dialogue.agent_dialogue_closed.emit("lao_li", "")
		assertions.truthy(not merchant.is_dialogue_busy(), "closing failed conversation unlocks NPC")

		runtime.trigger_result = true
		explorer.set_dialogue_busy(true)
		main.call("_on_dialogue_started", "xuezhe_lin")
		dialogue.agent_message_submitted.emit("xuezhe_lin", "发现了什么？")
		var explorer_request := runtime.get_in_flight_request_id("xuezhe_lin")
		main.call("_on_agent_dialogue_stream_failed", "xuezhe_lin", explorer_request, "timeout")
		assertions.equal(dialogue.failed_requests, [[explorer_request]], "stream failure becomes a visible history entry")
		assertions.truthy(explorer.is_dialogue_busy(), "stream failure leaves conversation open")
		assertions.equal(hud.records.size(), 2, "stream failure publishes one additional warning")
		dialogue.agent_dialogue_closed.emit("xuezhe_lin", "")
		assertions.truthy(not explorer.is_dialogue_busy(), "closing stream-failed conversation unlocks NPC")

		farmer.set_dialogue_busy(true)
		main.call("_on_dialogue_started", "farmer_ahe")
		dialogue.agent_message_submitted.emit("farmer_ahe", "继续说")
		var cancelled_request := runtime.get_in_flight_request_id("farmer_ahe")
		dialogue.agent_dialogue_cancelled.emit("farmer_ahe", cancelled_request)
		dialogue.agent_dialogue_closed.emit("farmer_ahe", cancelled_request)
		assertions.equal(
			runtime.cancelled[-1],
			{"agent_id": "farmer_ahe", "request_id": cancelled_request},
			"wired cancel signal reaches Agent runtime"
		)
		assertions.truthy(not farmer.is_dialogue_busy(), "wired close signal unlocks farmer")

	main.free()
	fixture_root.free()
	runtime.free()
	dialogue.free()
	hud.free()
	debug_panel.free()
