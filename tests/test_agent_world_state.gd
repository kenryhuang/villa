extends RefCounted

const AgentProtocolScript = preload("res://scripts/ai_agent/agent_protocol.gd")
const AgentRegistryScript = preload("res://scripts/ai_agent/agent_registry.gd")
const NpcFarmRegistryScript = preload("res://scripts/systems/npc_farm_registry.gd")
const NpcBuildingRegistryScript = preload("res://scripts/systems/npc_building_registry.gd")
const NpcActivitySystemScript = preload("res://scripts/systems/npc_activity_system.gd")
const ExplorerKnowledgeRegistryScript = preload("res://scripts/systems/explorer_knowledge_registry.gd")


func run(assertions: TestAssert, _tree: SceneTree) -> void:
	_test_protocol_and_profiles(assertions)
	_test_farm_lifecycle(assertions)
	_test_building_activity_and_knowledge(assertions)


func _test_protocol_and_profiles(assertions: TestAssert) -> void:
	var text := FileAccess.get_file_as_string("res://shared/agent_protocol/v1/action-intent.json")
	var parsed := AgentProtocolScript.parse_action_intent(JSON.parse_string(text), ["plant", "wait"])
	assertions.truthy(parsed.ok, "Godot accepts role Agent intent fixture")
	assertions.equal(parsed.value.tool_name, "plant", "Godot preserves command tool")
	assertions.truthy(not AgentProtocolScript.parse_action_intent(parsed.value, ["wait"]).ok, "Godot rejects unauthorized command")
	var registry := AgentRegistryScript.new()
	assertions.truthy(registry.load_defaults(), "Agent registry loads role data")
	assertions.equal(registry.get_agent_ids(), ["farmer_ahe", "lao_li", "xuezhe_lin"], "Agent IDs are deterministic")
	assertions.truthy(registry.is_tool_allowed("farmer_ahe", "plant"), "farmer can plant")
	assertions.truthy(not registry.is_tool_allowed("lao_li", "plant"), "merchant cannot plant")


func _test_farm_lifecycle(assertions: TestAssert) -> void:
	var farm := NpcFarmRegistryScript.new()
	assertions.truthy(farm.configure_farm("farmer_ahe", 12), "farmer receives twelve plots")
	assertions.truthy(farm.till("farmer_ahe", 0), "farmer tills own plot")
	assertions.truthy(farm.plant("farmer_ahe", 0, "carrot", 120, 180, 4), "farmer plants crop")
	assertions.equal(farm.harvest("farmer_ahe", 0, 179), {}, "immature crop cannot harvest")
	assertions.equal(farm.harvest("farmer_ahe", 0, 180), {"item_id": "carrot", "quantity": 4}, "mature harvest returns yield")
	assertions.equal(farm.get_plot("farmer_ahe", 0).state, "tilled", "harvest clears plot for replanting")
	var restored := NpcFarmRegistryScript.new()
	assertions.truthy(restored.from_dict(farm.to_dict()), "farm state round trips")
	assertions.equal(restored.to_dict(), farm.to_dict(), "farm serialization is stable")


func _test_building_activity_and_knowledge(assertions: TestAssert) -> void:
	var buildings := NpcBuildingRegistryScript.new()
	assertions.truthy(buildings.add_building("farmer_ahe", "shed", "shed-1", 300), "headless building registers")
	assertions.truthy(not buildings.add_building("farmer_ahe", "shed", "shed-1", 301), "building ID is unique")
	var activities := NpcActivitySystemScript.new()
	assertions.truthy(activities.start("xuezhe_lin", "travel", "travel-1", 100, 160, {"region_id": "creek"}), "travel activity starts")
	assertions.equal(activities.complete_due(159), [], "travel waits until due")
	assertions.equal(activities.complete_due(160).size(), 1, "travel completes once")
	assertions.equal(activities.complete_due(200), [], "completed travel is not repeated")
	var knowledge := ExplorerKnowledgeRegistryScript.new()
	assertions.truthy(knowledge.discover("xuezhe_lin", "crop:moonflower", "creek", 200), "private discovery records")
	assertions.truthy(not knowledge.is_public("crop:moonflower"), "new discovery stays private")
	assertions.truthy(knowledge.publish("xuezhe_lin", "crop:moonflower", 220), "verified discovery publishes")
	assertions.truthy(knowledge.is_public("crop:moonflower"), "published knowledge is global")
