extends RefCounted

const MainScript = preload("res://scripts/main.gd")
const NpcScene = preload("res://scenes/actors/npc.tscn")


class RuntimeDouble:
	extends Node

	var trigger_result := true
	var triggered: Array[String] = []
	var cancelled: Array[Dictionary] = []

	func is_agent_managed(agent_id: String) -> bool:
		return agent_id in ["farmer_ahe", "lao_li", "xuezhe_lin"]

	func trigger_dialogue(agent_id: String, _text: String = "") -> bool:
		triggered.append(agent_id)
		return trigger_result

	func cancel_dialogue(agent_id: String, request_id: String) -> bool:
		cancelled.append({"agent_id": agent_id, "request_id": request_id})
		return true


class DialogueDouble:
	extends Node

	var fixed_dialogue_calls := 0

	func start_dialogue(_villager_id: String) -> void:
		fixed_dialogue_calls += 1


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
	main.player = player
	main.npcs = npcs
	main.world = null
	main.agent_runtime = runtime
	main.dialogue_ui = dialogue
	main.hud_message_bus = hud
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

	main.call("_on_agent_dialogue_cancelled", "farmer_ahe", "dialogue-request-1")
	assertions.equal(
		runtime.cancelled,
		[{"agent_id": "farmer_ahe", "request_id": "dialogue-request-1"}],
		"dialogue cancellation preserves Agent and request identity"
	)
	main.call("_on_agent_dialogue_closed", "farmer_ahe", "dialogue-request-1")
	assertions.truthy(not farmer.is_dialogue_busy(), "closing dialogue unlocks only its NPC")
	assertions.truthy(not merchant.is_dialogue_busy(), "merchant remains in its own unlocked state")

	main.free()
	fixture_root.free()
	runtime.free()
	dialogue.free()
	hud.free()
