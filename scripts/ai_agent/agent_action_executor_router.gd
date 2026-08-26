extends RefCounted

const CROP_BY_SEED := {
	"tomato_seed": {"item_id": "tomato", "minutes": 60, "yield": 4},
	"carrot_seed": {"item_id": "carrot", "minutes": 60, "yield": 4},
	"potato_seed": {"item_id": "potato", "minutes": 75, "yield": 4},
	"grain_seed": {"item_id": "grain", "minutes": 90, "yield": 4},
	"lavender_seed": {"item_id": "lavender", "minutes": 90, "yield": 3},
	"grape_seed": {"item_id": "grape", "minutes": 120, "yield": 3},
	"lemon_sapling": {"item_id": "lemon", "minutes": 180, "yield": 3},
}
const SURVEY_RESULTS := {"creek": "crop:moonflower", "hills": "terrain:cliff", "forest": "crop:stardust_fruit"}
const SAMPLE_ITEMS := {"crop:moonflower": "moonflower", "crop:stardust_fruit": "stardust_fruit"}

var world_revision := 0
var _registry: Variant
var _farm: Variant
var _buildings: Variant
var _activities: Variant
var _knowledge: Variant
var _economy: Variant
var _publish_hud: Callable
var _outcomes: Dictionary = {}


func configure(
	registry: Variant,
	farm: Variant,
	buildings: Variant,
	activities: Variant,
	knowledge: Variant,
	economy: Variant,
	publish_hud: Callable = Callable()
) -> bool:
	if registry == null or farm == null or buildings == null or activities == null or knowledge == null or economy == null:
		return false
	_registry = registry
	_farm = farm
	_buildings = buildings
	_activities = activities
	_knowledge = knowledge
	_economy = economy
	_publish_hud = publish_hud
	return true


func execute(intent: Dictionary, game_minute: int) -> Dictionary:
	var idempotency_key := str(intent.get("idempotency_key", ""))
	if _outcomes.has(idempotency_key):
		return (_outcomes[idempotency_key] as Dictionary).duplicate(true)
	var agent_id := str(intent.get("agent_id", ""))
	var tool_name := str(intent.get("tool_name", ""))
	if not _registry.call("is_tool_allowed", agent_id, tool_name):
		return _failure(intent, game_minute, "unauthorized_tool")
	if int(intent.get("expected_revision", -1)) != world_revision:
		return _failure(intent, game_minute, "stale_world_revision")
	var arguments: Dictionary = intent.get("arguments", {})
	var result := _execute_tool(agent_id, tool_name, arguments, game_minute, idempotency_key)
	if not result.ok:
		return _failure(intent, game_minute, str(result.error))
	if bool(result.get("mutated", false)):
		world_revision += 1
	var status := str(result.get("status", "completed"))
	var outcome := {
		"protocol_version": 1,
		"decision_id": str(intent.get("decision_id", "")),
		"idempotency_key": idempotency_key,
		"status": status,
		"committed_revision": world_revision,
		"changed_entities": result.get("changed_entities", []),
		"resource_delta": result.get("resource_delta", {}),
		"hud_message": str(result.get("message", "")),
		"game_minute": game_minute,
	}
	_outcomes[idempotency_key] = outcome.duplicate(true)
	if not outcome.hud_message.is_empty() and _publish_hud.is_valid():
		_publish_hud.call(outcome.hud_message)
	return outcome


func complete_due(game_minute: int) -> Array[Dictionary]:
	var outcomes: Array[Dictionary] = []
	for activity in _activities.call("complete_due", game_minute):
		var record := activity as Dictionary
		var message := "%s完成了%s" % [str(record.agent_id), str(record.kind)]
		var changed: Array[String] = ["npc_activity:" + str(record.activity_id)]
		if record.kind == "build":
			var payload: Dictionary = record.payload
			if _buildings.call("add_building", str(record.agent_id), str(payload.building_type), str(payload.building_id), game_minute):
				changed.append("npc_building:" + str(payload.building_id))
		world_revision += 1
		var outcome := {"status": "completed", "committed_revision": world_revision, "changed_entities": changed, "resource_delta": {}, "hud_message": message, "game_minute": game_minute}
		outcomes.append(outcome)
		if _publish_hud.is_valid():
			_publish_hud.call(message)
	return outcomes


func _execute_tool(agent_id: String, tool_name: String, arguments: Dictionary, game_minute: int, key: String) -> Dictionary:
	match tool_name:
		"till":
			var plot := int(arguments.get("plot", -1))
			if not _farm.call("till", agent_id, plot):
				return _error("invalid_plot")
			return _success("%s开垦了地块 %d。" % [_display_name(agent_id), plot], ["npc_farm:%s:%d" % [agent_id, plot]])
		"plant":
			return _plant(agent_id, arguments, game_minute)
		"harvest":
			return _harvest(agent_id, arguments, game_minute)
		"buy", "sell":
			return _trade(agent_id, tool_name, arguments)
		"travel":
			var region_id := str(arguments.get("region_id", ""))
			var duration := clampi(int(arguments.get("duration_minutes", 60)), 10, 240)
			if region_id.is_empty() or not _activities.call("start", agent_id, "travel", key, game_minute, game_minute + duration, {"region_id": region_id}):
				return _error("travel_unavailable")
			return {"ok": true, "mutated": true, "status": "in_progress", "message": "%s出发前往%s。" % [_display_name(agent_id), region_id], "changed_entities": ["npc_activity:" + key], "resource_delta": {}}
		"build":
			var building_type := str(arguments.get("building_type", ""))
			var building_id := str(arguments.get("building_id", key))
			if building_type.is_empty() or not _activities.call("start", agent_id, "build", key, game_minute, game_minute + 120, {"building_type": building_type, "building_id": building_id}):
				return _error("build_unavailable")
			return {"ok": true, "mutated": true, "status": "in_progress", "message": "%s开始建造%s。" % [_display_name(agent_id), building_type], "changed_entities": ["npc_activity:" + key], "resource_delta": {}}
		"survey":
			var region_id := str(arguments.get("region_id", ""))
			var discovery_id := str(SURVEY_RESULTS.get(region_id, ""))
			if discovery_id.is_empty() or not _knowledge.call("discover", agent_id, discovery_id, region_id, game_minute):
				return _error("nothing_new_found")
			return _success("%s在%s发现了新线索。" % [_display_name(agent_id), region_id], ["private_knowledge:%s:%s" % [agent_id, discovery_id]])
		"register_discovery":
			var discovery_id := str(arguments.get("discovery_id", ""))
			if not _knowledge.call("publish", agent_id, discovery_id, game_minute):
				return _error("discovery_not_verified")
			return _success("%s登记了发现%s。" % [_display_name(agent_id), discovery_id], ["public_knowledge:" + discovery_id])
		"collect_sample":
			var discovery_id := str(arguments.get("discovery_id", ""))
			var item_id := str(SAMPLE_ITEMS.get(discovery_id, ""))
			if item_id.is_empty() or not _economy.call("receive_item", agent_id, item_id, 1):
				return _error("sample_unavailable")
			return _success("%s采集了%s。" % [_display_name(agent_id), item_id], ["npc_inventory:" + agent_id], {item_id: 1})
		"prepare_supplies", "propose_trade", "speak", "wait":
			return {"ok": true, "mutated": false, "message": "", "changed_entities": [], "resource_delta": {}}
	return _error("unsupported_tool")


func _plant(agent_id: String, arguments: Dictionary, game_minute: int) -> Dictionary:
	var plot := int(arguments.get("plot", -1))
	var seed_item_id := str(arguments.get("seed_item_id", ""))
	var crop: Dictionary = CROP_BY_SEED.get(seed_item_id, {})
	var state = _economy.call("get_npc_state", agent_id)
	if crop.is_empty() or state == null or int(state.inventory.get(seed_item_id, 0)) <= 0:
		return _error("seed_unavailable")
	var state_before: Dictionary = state.to_dict()
	state.inventory[seed_item_id] = int(state.inventory.get(seed_item_id, 0)) - 1
	if not _farm.call("plant", agent_id, plot, crop.item_id, game_minute, game_minute + int(crop.minutes), int(crop.yield)):
		state.from_dict(state_before)
		return _error("plot_not_plantable")
	return _success("%s播种了%s。" % [_display_name(agent_id), str(crop.item_id)], ["npc_farm:%s:%d" % [agent_id, plot], "npc_inventory:" + agent_id], {seed_item_id: -1})


func _harvest(agent_id: String, arguments: Dictionary, game_minute: int) -> Dictionary:
	var plot := int(arguments.get("plot", -1))
	var farm_before: Dictionary = _farm.call("to_dict")
	var harvested: Dictionary = _farm.call("harvest", agent_id, plot, game_minute)
	if harvested.is_empty():
		return _error("crop_not_mature")
	if not _economy.call("receive_item", agent_id, str(harvested.item_id), int(harvested.quantity)):
		_farm.call("from_dict", farm_before)
		return _error("inventory_rejected")
	return _success("%s收获了%s ×%d，已进入库存。" % [_display_name(agent_id), str(harvested.item_id), int(harvested.quantity)], ["npc_farm:%s:%d" % [agent_id, plot], "npc_inventory:" + agent_id], {str(harvested.item_id): int(harvested.quantity)})


func _trade(agent_id: String, tool_name: String, arguments: Dictionary) -> Dictionary:
	var item_id := str(arguments.get("item_id", ""))
	var quantity := int(arguments.get("quantity", 0))
	var succeeded := bool(_economy.call("agent_buy" if tool_name == "buy" else "agent_sell", agent_id, item_id, quantity))
	if not succeeded:
		return _error("trade_rejected")
	var delta := quantity if tool_name == "buy" else -quantity
	return _success("%s%s了%s ×%d。" % [_display_name(agent_id), "购买" if tool_name == "buy" else "出售", item_id, quantity], ["npc_inventory:" + agent_id, "market:" + item_id], {item_id: delta})


func _display_name(agent_id: String) -> String:
	return str((_registry.call("get_agent", agent_id) as Dictionary).get("display_name", agent_id))


func _success(message: String, changed: Array, delta: Dictionary = {}) -> Dictionary:
	return {"ok": true, "mutated": true, "message": message, "changed_entities": changed, "resource_delta": delta}


func _error(error: String) -> Dictionary:
	return {"ok": false, "error": error}


func _failure(intent: Dictionary, game_minute: int, error: String) -> Dictionary:
	return {"protocol_version": 1, "decision_id": str(intent.get("decision_id", "")), "idempotency_key": str(intent.get("idempotency_key", "")), "status": "rejected", "failure_code": error, "committed_revision": world_revision, "changed_entities": [], "resource_delta": {}, "hud_message": "", "game_minute": game_minute}
