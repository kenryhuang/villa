class_name EconomyProgressionSystem
extends Node

const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")

const VERSION := 2
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_UPGRADE_LEVELS := {
	"queue_slots": 2,
	"speed": 3,
	"storage": 3,
}
const TIER_ZERO_BLUEPRINTS := ["workbench", "stone_kiln", "beehive", "well", "fence"]
const BLUEPRINT_TIERS := {
	"workbench": 0,
	"stone_kiln": 0,
	"beehive": 0,
	"well": 0,
	"fence": 0,
	"barn": 1,
	"windmill": 1,
	"chicken_coop": 1,
	"waterwheel": 1,
	"furnace": 1,
	"lumberyard": 1,
	"quarry": 1,
	"lamp": 1,
	"greenhouse": 2,
	"mine": 2,
	"textile_machine": 2,
	"food_workshop": 2,
}
static var BLUEPRINT_SERVICES := {
	"blueprint_barn": _service("blueprint_barn", "blueprints", "谷仓蓝图", "blueprint", "barn", 1, 8, 2, 90, {"wood": 8, "stone": 4}, "解锁谷仓"),
	"blueprint_windmill": _service("blueprint_windmill", "blueprints", "风车蓝图", "blueprint", "windmill", 1, 8, 2, 120, {"wood": 10, "stone": 5}, "解锁风车与基础风车配方"),
	"blueprint_chicken_coop": _service("blueprint_chicken_coop", "blueprints", "鸡舍蓝图", "blueprint", "chicken_coop", 1, 8, 2, 100, {"wood": 8, "stone": 4}, "解锁鸡舍"),
	"blueprint_waterwheel": _service("blueprint_waterwheel", "blueprints", "水车蓝图", "blueprint", "waterwheel", 1, 8, 2, 140, {"wood": 10, "stone": 8}, "解锁自动灌溉水车"),
	"blueprint_furnace": _service("blueprint_furnace", "blueprints", "熔炉蓝图", "blueprint", "furnace", 1, 8, 2, 160, {"stone": 12, "coal": 3}, "解锁熔炉与基础冶炼配方"),
	"blueprint_lumberyard": _service("blueprint_lumberyard", "blueprints", "伐木场蓝图", "blueprint", "lumberyard", 1, 8, 2, 130, {"wood": 10, "stone": 6}, "解锁伐木场"),
	"blueprint_quarry": _service("blueprint_quarry", "blueprints", "采石场蓝图", "blueprint", "quarry", 1, 8, 2, 150, {"wood": 8, "stone": 10}, "解锁采石场"),
	"blueprint_lamp": _service("blueprint_lamp", "blueprints", "路灯蓝图", "blueprint", "lamp", 1, 8, 2, 50, {"plank": 2}, "解锁路灯"),
	"blueprint_greenhouse": _service("blueprint_greenhouse", "blueprints", "温室蓝图", "blueprint", "greenhouse", 2, 22, 4, 420, {"wood": 20, "glass": 8}, "解锁全年种植温室"),
	"blueprint_mine": _service("blueprint_mine", "blueprints", "矿场蓝图", "blueprint", "mine", 2, 22, 4, 460, {"wood": 20, "stone": 20}, "解锁矿场"),
	"blueprint_textile_machine": _service("blueprint_textile_machine", "blueprints", "纺织机蓝图", "blueprint", "textile_machine", 2, 22, 4, 380, {"wood": 16, "iron_ingot": 4}, "解锁纺织机与纺织配方"),
	"blueprint_food_workshop": _service("blueprint_food_workshop", "blueprints", "食品工坊蓝图", "blueprint", "food_workshop", 2, 22, 4, 360, {"wood": 15, "glass": 4}, "解锁食品工坊与食品配方"),
}
static var RECIPE_SERVICES := {
	"recipe_wooden_crate": _service("recipe_wooden_crate", "recipes", "木箱配方", "recipe", "wooden_crate", 1, 8, 2, 45, {"plank": 2}, "解锁工作台木箱配方"),
	"recipe_farm_tools": _service("recipe_farm_tools", "recipes", "农具配方", "recipe", "farm_tools", 1, 8, 2, 70, {"iron_ingot": 1}, "解锁工作台农具配方"),
	"recipe_lamp": _service("recipe_lamp", "recipes", "灯具配方", "recipe", "lamp", 1, 8, 2, 60, {"copper_ingot": 1, "glass": 1}, "解锁工作台灯具配方"),
	"recipe_candle": _service("recipe_candle", "recipes", "蜡烛配方", "recipe", "candle", 1, 8, 2, 50, {"beeswax": 1, "fiber": 2}, "解锁工作台蜡烛配方"),
	"recipe_steel": _service("recipe_steel", "recipes", "钢材配方", "recipe", "steel", 2, 22, 4, 120, {"iron_ingot": 2}, "解锁熔炉钢材配方"),
	"recipe_furniture": _service("recipe_furniture", "recipes", "家具配方", "recipe", "furniture", 2, 22, 4, 110, {"plank": 4, "cloth": 1}, "解锁工作台家具配方"),
	"recipe_machine_parts": _service("recipe_machine_parts", "recipes", "机械零件配方", "recipe", "machine_parts", 2, 22, 4, 140, {"steel": 1, "copper_ingot": 1}, "解锁工作台机械零件配方"),
	"recipe_perfume": _service("recipe_perfume", "recipes", "香水配方", "recipe", "perfume", 3, 36, 6, 160, {"rose": 2, "glass_bottle": 1}, "解锁食品工坊香水配方"),
	"recipe_jewelry": _service("recipe_jewelry", "recipes", "珠宝配方", "recipe", "jewelry", 3, 36, 6, 220, {"gold_ore": 1, "crystal": 1}, "解锁工作台珠宝配方"),
}
const PLACEHOLDER_SERVICES := {
	"transport_storage_future": {
		"id": "transport_storage_future", "category": "transport-storage", "display_name": "运输与仓储扩建",
		"kind": "disabled", "gate": "后续经营阶段", "current_state": "未开放", "gold_cost": 0,
		"materials": {}, "effect": "扩大运输与集中仓储范围", "disabled_reason": "该服务尚未开放", "owned": false,
	},
	"land_expansion_future": {
		"id": "land_expansion_future", "category": "land-expansion", "display_name": "土地扩张",
		"kind": "disabled", "gate": "后续经营阶段", "current_state": "未开放", "gold_cost": 0,
		"materials": {}, "effect": "扩大可经营土地", "disabled_reason": "该服务尚未开放", "owned": false,
	},
}

var unlocked_blueprints: Dictionary = {}
var unlocked_recipes: Dictionary = {}
var upgrade_levels: Dictionary = {}

var _tool_system: ToolSystem
var _production_system: ProductionSystem
var _inventory_system: InventorySystem
var _day_source: Variant
var _wallet: Variant
var _active_service_transactions: Dictionary = {}


func _init() -> void:
	reset_to_new_game()


func configure(
	tool_system: ToolSystem,
	production_system: ProductionSystem,
	inventory_system: InventorySystem,
	day_source: Variant = null,
	wallet: Variant = null
) -> bool:
	if tool_system == null or production_system == null or inventory_system == null:
		return false
	_tool_system = tool_system
	_production_system = production_system
	_inventory_system = inventory_system
	_day_source = day_source
	_wallet = wallet if wallet != null else (get_node_or_null("/root/GameState") if is_inside_tree() else null)
	if not _valid_wallet(_wallet):
		return false
	_production_system.set_progression_system(self)
	return true


func reset_to_new_game() -> bool:
	unlocked_blueprints.clear()
	unlocked_recipes.clear()
	upgrade_levels.clear()
	for blueprint_id in TIER_ZERO_BLUEPRINTS:
		unlocked_blueprints[blueprint_id] = true
	for recipe in RecipeDatabaseScript.get_all_recipes():
		if int(recipe.get("unlock_tier", -1)) == 0 and str(recipe.get("station", "")) in TIER_ZERO_BLUEPRINTS:
			unlocked_recipes[str(recipe.id)] = true
	return true


func is_blueprint_unlocked(blueprint_id: String) -> bool:
	return bool(unlocked_blueprints.get(blueprint_id, false))


func is_blueprint_managed(blueprint_id: String) -> bool:
	return BLUEPRINT_TIERS.has(blueprint_id)


func is_recipe_unlocked(recipe_id: String) -> bool:
	return bool(unlocked_recipes.get(recipe_id, false))


func debug_unlock_gate_eligible_blueprints() -> Dictionary:
	if not OS.is_debug_build():
		return {"ok": false, "reason": "debug_build_required"}
	if _day_source == null or not _valid_wallet(_wallet):
		return {"ok": false, "reason": "not_configured"}
	var service_ids: Array[String] = []
	for service_id_value in BLUEPRINT_SERVICES:
		service_ids.append(str(service_id_value))
	service_ids.sort()
	var granted_blueprints: Array[String] = []
	var granted_recipes: Array[String] = []
	for service_id in service_ids:
		var definition := BLUEPRINT_SERVICES[service_id] as Dictionary
		if not _gate_met(int(definition.day_gate), int(definition.level_gate)):
			continue
		var target_id := str(definition.target_id)
		if is_blueprint_unlocked(target_id):
			continue
		unlocked_blueprints[target_id] = true
		granted_blueprints.append(target_id)
		var tier := int(BLUEPRINT_TIERS.get(target_id, -1))
		for recipe in RecipeDatabaseScript.get_recipes_for_station(target_id):
			var recipe_id := str(recipe.id)
			if (
				int(recipe.get("unlock_tier", -1)) <= tier
				and not is_recipe_unlocked(recipe_id)
			):
				unlocked_recipes[recipe_id] = true
				granted_recipes.append(recipe_id)
	for blueprint_id in granted_blueprints:
		_emit_event("service_unlocked", ["blueprint", blueprint_id])
	return {
		"ok": true,
		"reason": "",
		"blueprints": granted_blueprints,
		"recipes": granted_recipes,
	}


func get_blueprint_service_id(building_id: String) -> String:
	for service_id in BLUEPRINT_SERVICES:
		if str((BLUEPRINT_SERVICES[service_id] as Dictionary).target_id) == building_id:
			return str(service_id)
	return ""


func get_recipe_service_id(recipe_id: String) -> String:
	for service_id in RECIPE_SERVICES:
		if str((RECIPE_SERVICES[service_id] as Dictionary).target_id) == recipe_id:
			return str(service_id)
	return ""


func get_blueprint_lock_info(building_id: String) -> Dictionary:
	if not is_blueprint_managed(building_id):
		return {"unlocked": false, "reason": "建筑蓝图数据不可用", "service_id": ""}
	if is_blueprint_unlocked(building_id):
		return {"unlocked": true, "reason": "", "service_id": ""}
	var service_id := get_blueprint_service_id(building_id)
	if service_id.is_empty():
		return {"unlocked": false, "reason": "尚未解锁", "service_id": ""}
	var service: Dictionary = _view_for_static_service(BLUEPRINT_SERVICES[service_id])
	return {
		"unlocked": false,
		"reason": str(service.get("disabled_reason", "尚未解锁")),
		"service_id": service_id,
	}


func can_eventually_unlock_recipe(recipe_id: String) -> bool:
	var recipe := RecipeDatabaseScript.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	var station := str(recipe.get("station", ""))
	if not BLUEPRINT_TIERS.has(station):
		return false
	return (
		int(recipe.get("unlock_tier", -1)) <= int(BLUEPRINT_TIERS[station])
		or not get_recipe_service_id(recipe_id).is_empty()
	)


func reconcile_placed_buildings(buildings: Array) -> int:
	var added := 0
	for value in buildings:
		var building := value as BuildingInstance
		if (
			building != null and is_instance_valid(building)
			and is_blueprint_managed(building.building_id)
			and not is_blueprint_unlocked(building.building_id)
		):
			unlocked_blueprints[building.building_id] = true
			added += 1
	return added


func get_available_services() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in BLUEPRINT_SERVICES.values():
		result.append(_view_for_static_service(definition as Dictionary))
	for definition in RECIPE_SERVICES.values():
		result.append(_view_for_static_service(definition as Dictionary))
	if _tool_system != null:
		for tool_id in _tool_system.get_tool_ids():
			result.append(_repair_service(tool_id))
	if _production_system != null:
		for building in _production_system.get_registered_buildings():
			if building == null or not is_instance_valid(building):
				continue
			for upgrade_id in _production_system.get_supported_upgrades(building):
				result.append(_upgrade_service(building, upgrade_id))
			result.append(_maintenance_service(building))
	for definition in PLACEHOLDER_SERVICES.values():
		result.append((definition as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return result


func purchase(service_id: String) -> bool:
	var definition: Dictionary = {}
	if BLUEPRINT_SERVICES.has(service_id):
		definition = BLUEPRINT_SERVICES[service_id]
	elif RECIPE_SERVICES.has(service_id):
		definition = RECIPE_SERVICES[service_id]
	else:
		return false
	var target_id := str(definition.target_id)
	var kind := str(definition.kind)
	if (kind == "blueprint" and is_blueprint_unlocked(target_id)) or (kind == "recipe" and is_recipe_unlocked(target_id)):
		return false
	if not _gate_met(int(definition.day_gate), int(definition.level_gate)):
		return false
	if kind == "recipe":
		var recipe := RecipeDatabaseScript.get_recipe(target_id)
		if recipe.is_empty() or not is_blueprint_unlocked(str(recipe.get("station", ""))):
			return false
	var transaction_key := "purchase:%s" % service_id
	if _active_service_transactions.has(transaction_key):
		return false
	_active_service_transactions[transaction_key] = true
	var blueprints_before := unlocked_blueprints.duplicate(true)
	var recipes_before := unlocked_recipes.duplicate(true)
	var committed := _commit_cost(
		int(definition.gold_cost),
		definition.materials,
		func() -> bool:
			if kind == "blueprint":
				unlocked_blueprints[target_id] = true
				var tier := int(BLUEPRINT_TIERS.get(target_id, -1))
				for recipe in RecipeDatabaseScript.get_recipes_for_station(target_id):
					if int(recipe.get("unlock_tier", -1)) <= tier:
						unlocked_recipes[str(recipe.id)] = true
			else:
				unlocked_recipes[target_id] = true
			return true,
		func() -> bool:
			unlocked_blueprints = blueprints_before.duplicate(true)
			unlocked_recipes = recipes_before.duplicate(true)
			return true
	)
	if committed:
		_emit_event("service_unlocked", [kind, target_id])
	_active_service_transactions.erase(transaction_key)
	return committed


func repair(tool_id: String) -> bool:
	return _tool_system != null and _tool_system.repair_tool(tool_id)


func upgrade(building: BuildingInstance, upgrade_id: String) -> bool:
	if building == null or _production_system == null or upgrade_id not in MAX_UPGRADE_LEVELS:
		return false
	var current := get_upgrade_level(building, upgrade_id)
	var next_level := current + 1
	if next_level > int(MAX_UPGRADE_LEVELS[upgrade_id]):
		return false
	if not _production_system.can_apply_upgrade(building, upgrade_id, next_level):
		return false
	var quote := get_upgrade_quote(building, upgrade_id)
	if quote.is_empty():
		return false
	var transaction_key := "upgrade:%s:%s" % [building_key(building), upgrade_id]
	if _active_service_transactions.has(transaction_key):
		return false
	var key := building_key(building)
	_active_service_transactions[transaction_key] = true
	var upgrades_before := upgrade_levels.duplicate(true)
	var state := building.producer_state as ProducerState
	var queue_before := state.max_queue_slots if state != null else 0
	var capacity_before := state.output_capacity if state != null else 0
	var committed := _commit_cost(
		int(quote.gold_cost),
		quote.materials,
		func() -> bool:
			if not _production_system.apply_upgrade(building, upgrade_id, next_level):
				return false
			var levels: Dictionary = upgrade_levels.get(key, {}).duplicate()
			levels[upgrade_id] = next_level
			upgrade_levels[key] = levels
			return true,
		func() -> bool:
			if state != null:
				state.max_queue_slots = queue_before
				state.output_capacity = capacity_before
			upgrade_levels = upgrades_before.duplicate(true)
			return true
	)
	if committed:
		_emit_event("building_upgrade_changed", [building, upgrade_id, next_level])
	_active_service_transactions.erase(transaction_key)
	return committed


func maintain(building: BuildingInstance) -> bool:
	return (
		_production_system != null
		and _production_system.maintain(
			building,
			_wallet,
			_inventory_system,
			get_maintenance_quote(building)
		)
	)


func get_maintenance_quote(building: BuildingInstance) -> Dictionary:
	if building == null or building.data == null or _production_system == null:
		return {}
	if building not in _production_system.get_registered_buildings():
		return {}
	var structure_size := building.get_structure_footprint()
	var area := int(structure_size.x * structure_size.y)
	var base_gold := 20
	var base_materials := 1
	if area >= 5:
		base_gold = 55
		base_materials = 3
	elif area >= 3:
		base_gold = 35
		base_materials = 2
	var upgrade_total := 0
	for upgrade_id in ["queue_slots", "speed", "storage"]:
		upgrade_total += get_upgrade_level(building, upgrade_id)
	var extra_materials := ceili(float(upgrade_total) / 2.0)
	return {
		"gold_cost": base_gold + 10 * upgrade_total,
		"materials": {
			"wood": base_materials + extra_materials,
			"stone": base_materials + extra_materials,
		},
	}


func get_upgrade_level(building: BuildingInstance, upgrade_id: String) -> int:
	if building == null or upgrade_id not in MAX_UPGRADE_LEVELS:
		return 0
	return int((upgrade_levels.get(building_key(building), {}) as Dictionary).get(upgrade_id, 0))


func get_upgrade_quote(building: BuildingInstance, upgrade_id: String) -> Dictionary:
	if (
		building == null or upgrade_id not in MAX_UPGRADE_LEVELS
		or _production_system == null
		or upgrade_id not in _production_system.get_supported_upgrades(building)
	):
		return {}
	var next_level := get_upgrade_level(building, upgrade_id) + 1
	if next_level > int(MAX_UPGRADE_LEVELS[upgrade_id]):
		return {}
	var base_gold := {"queue_slots": 80, "speed": 100, "storage": 60}
	var material_id := {"queue_slots": "wood", "speed": "stone", "storage": "wood"}
	return {
		"gold_cost": int(base_gold[upgrade_id]) * next_level,
		"materials": {str(material_id[upgrade_id]): next_level * 2},
		"level": next_level,
		"effect": _upgrade_effect(building, upgrade_id),
	}


func to_dict() -> Dictionary:
	var blueprints: Array[String] = []
	blueprints.assign(unlocked_blueprints.keys())
	blueprints.sort()
	var recipes: Array[String] = []
	recipes.assign(unlocked_recipes.keys())
	recipes.sort()
	var upgrades: Array[Dictionary] = []
	var keys: Array[String] = []
	keys.assign(upgrade_levels.keys())
	keys.sort()
	for key in keys:
		var level_records: Array[Dictionary] = []
		var ids: Array[String] = []
		ids.assign((upgrade_levels[key] as Dictionary).keys())
		ids.sort()
		for upgrade_id in ids:
			level_records.append({"upgrade_id": upgrade_id, "level": int(upgrade_levels[key][upgrade_id])})
		upgrades.append({"building_key": key, "levels": level_records})
	return {
		"version": VERSION,
		"unlocked_blueprints": blueprints,
		"unlocked_recipes": recipes,
		"upgrade_levels": upgrades,
	}


func validate_dict(data: Dictionary) -> bool:
	return _parse_dict(data) != null


func from_dict(data: Dictionary) -> bool:
	var parsed: Variant = _parse_dict(data)
	if not parsed is Dictionary:
		return false
	var next := parsed as Dictionary
	unlocked_blueprints = next.blueprints
	unlocked_recipes = next.recipes
	upgrade_levels = next.upgrades
	return true


static func building_key(building: BuildingInstance) -> String:
	if building == null:
		return ""
	return "%s:%d:%d" % [building.building_id, building.grid_x, building.grid_z]


static func is_valid_building_key(key: String) -> bool:
	var parts := key.split(":", false)
	if parts.size() != 3 or GameDataScript.get_building(parts[0]).is_empty():
		return false
	if not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return false
	var gx := int(parts[1])
	var gz := int(parts[2])
	return (
		gx >= -2147483647 and gx <= 2147483647
		and gz >= -2147483647 and gz <= 2147483647
		and key == "%s:%d:%d" % [parts[0], gx, gz]
	)


func clear_building_upgrades(building: BuildingInstance) -> void:
	if building != null:
		upgrade_levels.erase(building_key(building))


static func _service(
	id: String, category: String, display_name: String, kind: String, target_id: String,
	tier: int, day_gate: int, level_gate: int, gold_cost: int, materials: Dictionary, effect: String
) -> Dictionary:
	return {
		"id": id, "category": category, "display_name": display_name, "kind": kind,
		"target_id": target_id, "tier": tier, "day_gate": day_gate, "level_gate": level_gate,
		"gold_cost": gold_cost, "materials": materials, "effect": effect,
	}


func _view_for_static_service(definition: Dictionary) -> Dictionary:
	var view := definition.duplicate(true)
	var kind := str(view.kind)
	var target_id := str(view.target_id)
	var owned := is_blueprint_unlocked(target_id) if kind == "blueprint" else is_recipe_unlocked(target_id)
	view["owned"] = owned
	view["current_state"] = "已拥有" if owned else "未拥有"
	view["gate"] = "第%d天且等级%d" % [int(view.day_gate), int(view.level_gate)]
	var reason := "已拥有" if owned else ""
	if reason.is_empty() and kind == "recipe":
		var recipe := RecipeDatabaseScript.get_recipe(target_id)
		var station := str(recipe.get("station", ""))
		if not is_blueprint_unlocked(station):
			reason = "需要先解锁%s蓝图" % station
	if reason.is_empty():
		reason = _gate_reason(int(view.day_gate), int(view.level_gate))
	if reason.is_empty():
		reason = _cost_reason(int(view.gold_cost), view.materials)
	view["disabled_reason"] = reason
	return view


func _repair_service(tool_id: String) -> Dictionary:
	var durability := _tool_system.get_durability(tool_id)
	var quote := _tool_system.get_repair_quote(tool_id)
	var full := durability.is_empty() or int(durability.current) >= int(durability.max)
	return {
		"id": "repair_%s" % tool_id, "category": "repairs", "display_name": "%s维修" % _tool_system.get_tool_display_name(tool_id),
		"kind": "repair", "target_id": tool_id, "gate": "工具已损耗",
		"current_state": "%d/%d" % [int(durability.get("current", 0)), int(durability.get("max", 0))],
		"gold_cost": int(quote.get("gold_cost", 0)), "materials": quote.get("materials", {}),
		"effect": "恢复至最大耐久", "disabled_reason": "耐久已满" if full else _cost_reason(int(quote.get("gold_cost", 0)), quote.get("materials", {})), "owned": false,
	}


func _upgrade_service(building: BuildingInstance, upgrade_id: String) -> Dictionary:
	var quote := get_upgrade_quote(building, upgrade_id)
	var current := get_upgrade_level(building, upgrade_id)
	var labels := {"queue_slots": "队列", "speed": "速度", "storage": "容量"}
	var maxed := current >= int(MAX_UPGRADE_LEVELS[upgrade_id])
	var reason := ""
	if not building.is_construction_complete():
		reason = "建筑尚未完成"
	elif maxed:
		reason = "已达最高等级"
	else:
		reason = _cost_reason(int(quote.get("gold_cost", 0)), quote.get("materials", {}))
	return {
		"id": "upgrade_%s_%s" % [building_key(building), upgrade_id], "category": "upgrades",
		"display_name": "%s%s升级" % [GameDataScript.get_building(building.building_id).get("name", building.building_id), labels[upgrade_id]],
		"kind": "upgrade", "building": building, "target_id": upgrade_id, "gate": "建筑已完成",
		"current_state": "等级 %d/%d" % [current, int(MAX_UPGRADE_LEVELS[upgrade_id])],
		"gold_cost": int(quote.get("gold_cost", 0)), "materials": quote.get("materials", {}),
		"effect": _upgrade_effect(building, upgrade_id),
		"disabled_reason": reason, "owned": maxed,
	}


func _upgrade_effect(building: BuildingInstance, upgrade_id: String) -> String:
	if upgrade_id == "storage" and building != null and building.building_id == "barn":
		return "中央仓库容量 +100"
	return {
		"queue_slots": "队列槽 +1",
		"speed": "生产速度 +25%",
		"storage": "产物容量 +1",
	}.get(upgrade_id, "")


func _maintenance_service(building: BuildingInstance) -> Dictionary:
	var quote := get_maintenance_quote(building)
	var state := _production_system.get_maintenance_state(building)
	var current_state := "距到期 %d 天" % _production_system.get_maintenance_days_remaining(building)
	if state == "warning":
		current_state = "可提前维修"
	elif state == "overdue":
		current_state = "破损停产"
	elif state == "repairing":
		current_state = "维修中 %.1f 秒" % _production_system.get_repair_remaining_seconds(building)
	var disabled_reason := ""
	if state == "normal":
		disabled_reason = "维护尚未进入预警期"
	elif state == "repairing":
		disabled_reason = "维修正在进行"
	else:
		disabled_reason = _cost_reason(
			int(quote.get("gold_cost", 0)),
			quote.get("materials", {})
		)
	return {
		"id": "maintenance_%s" % building_key(building), "category": "maintenance",
		"display_name": "%s维护" % GameDataScript.get_building(building.building_id).get("name", building.building_id),
		"kind": "maintenance", "building": building, "target_id": building_key(building), "gate": "到期前1天可维修",
		"current_state": current_state,
		"gold_cost": int(quote.get("gold_cost", 0)), "materials": quote.get("materials", {}),
		"effect": "维修3秒并延后14天", "disabled_reason": disabled_reason, "owned": false,
	}


func _gate_met(day_gate: int, level_gate: int) -> bool:
	return _current_day() >= day_gate and _current_level() >= level_gate


func _gate_reason(day_gate: int, level_gate: int) -> String:
	if _current_day() < day_gate:
		return "需要第%d天" % day_gate
	if _current_level() < level_gate:
		return "需要等级%d" % level_gate
	return ""


func _cost_reason(gold_cost: int, materials: Dictionary) -> String:
	if not _valid_wallet(_wallet):
		return "金币系统未连接"
	var missing_gold := gold_cost - int(_wallet.gold)
	if missing_gold > 0:
		return "金币不足 %d" % missing_gold
	if _inventory_system == null:
		return "背包系统未连接"
	var ids: Array[String] = []
	ids.assign(materials.keys())
	ids.sort()
	for item_id in ids:
		var missing := int(materials[item_id]) - _inventory_system.get_item_count(item_id)
		if missing > 0:
			return "缺少%s ×%d" % [item_id, missing]
	return ""


func _current_day() -> int:
	if _day_source != null and _has_property(_day_source, "total_days"):
		return maxi(int(_day_source.get("total_days")), 0)
	return 1


func _current_level() -> int:
	if not _valid_wallet(_wallet):
		return 0
	return int(_wallet.player_state.level)


func _commit_cost(
	gold_cost: int,
	materials: Dictionary,
	domain_commit: Callable = Callable(),
	domain_rollback: Callable = Callable()
) -> bool:
	if not _valid_cost(gold_cost, materials) or not _valid_wallet(_wallet) or _inventory_system == null:
		return false
	if int(_wallet.gold) < gold_cost:
		return false
	for item_id in materials:
		if not _inventory_system.has_item(str(item_id), int(materials[item_id])):
			return false
	var snapshot := {"slots": _inventory_system.slots.duplicate(true), "mappings": _inventory_system.quick_slot_mappings.duplicate()}
	var gold_before := int(_wallet.gold)
	var event_bus := _event_bus()
	var owns_event := event_bus != null and not event_bus.is_blocking_signals()
	if owns_event:
		event_bus.set_block_signals(true)
	var owns_mapping := _inventory_system.begin_mapping_transaction()
	for item_id in materials:
		if not _inventory_system.remove_item(str(item_id), int(materials[item_id])):
			return _rollback_cost_transaction(snapshot, gold_before, owns_mapping, owns_event, event_bus, false, domain_rollback)
	if not bool(_wallet.spend_gold(gold_cost)):
		return _rollback_cost_transaction(snapshot, gold_before, owns_mapping, owns_event, event_bus, false, domain_rollback)
	var domain_started := domain_commit.is_valid()
	if domain_started and not bool(domain_commit.call()):
		return _rollback_cost_transaction(snapshot, gold_before, owns_mapping, owns_event, event_bus, true, domain_rollback)
	if owns_mapping:
		_inventory_system.end_mapping_transaction(true)
	if owns_event:
		event_bus.set_block_signals(false)
		event_bus.gold_changed.emit(int(_wallet.gold))
		for item_id in materials:
			event_bus.item_removed.emit(str(item_id), int(materials[item_id]))
	return true


func _rollback_cost_transaction(
	snapshot: Dictionary,
	gold_before: int,
	owns_mapping: bool,
	owns_event: bool,
	event_bus: Node,
	domain_started: bool,
	domain_rollback: Callable
) -> bool:
	var rollback_ok := true
	if domain_started:
		rollback_ok = domain_rollback.is_valid() and bool(domain_rollback.call())
	_inventory_system.restore_state(snapshot.slots, snapshot.mappings)
	_wallet.set("gold", gold_before)
	if owns_mapping:
		_inventory_system.end_mapping_transaction(false)
	rollback_ok = (
		rollback_ok
		and int(_wallet.gold) == gold_before
		and _inventory_system.slots == snapshot.slots
		and _inventory_system.quick_slot_mappings == snapshot.mappings
	)
	if owns_event:
		event_bus.set_block_signals(false)
	if not rollback_ok:
		push_error("Economy service transaction rollback failed")
	return false


func _refund_cost(gold_cost: int, materials: Dictionary) -> void:
	_wallet.add_gold(gold_cost)
	for item_id in materials:
		_inventory_system.add_item(str(item_id), int(materials[item_id]))


func _valid_cost(gold_cost: int, materials: Dictionary) -> bool:
	if gold_cost <= 0 or gold_cost > MAX_SAFE_INTEGER:
		return false
	for item_id in materials:
		var quantity: Variant = materials[item_id]
		if GameDataScript.get_item(str(item_id)) == null or not _integer_in_range(quantity, 1, MAX_SAFE_INTEGER):
			return false
	return true


func _parse_dict(data: Dictionary) -> Variant:
	if data.size() != 4 or not _integer_in_range(data.get("version"), 1, VERSION):
		return null
	var source_version := int(data.version)
	for field in ["unlocked_blueprints", "unlocked_recipes", "upgrade_levels"]:
		if not data.get(field) is Array:
			return null
	var blueprints := {}
	for value in data.unlocked_blueprints:
		if not value is String or not BLUEPRINT_TIERS.has(value) or blueprints.has(value):
			return null
		blueprints[value] = true
	if source_version == 1:
		for blueprint_id in TIER_ZERO_BLUEPRINTS:
			blueprints[blueprint_id] = true
	for required in TIER_ZERO_BLUEPRINTS:
		if not blueprints.has(required):
			return null
	var recipes := {}
	for value in data.unlocked_recipes:
		if not value is String or RecipeDatabaseScript.get_recipe(value).is_empty() or recipes.has(value):
			return null
		recipes[value] = true
	if source_version == 1:
		for recipe in RecipeDatabaseScript.get_all_recipes():
			if (
				int(recipe.get("unlock_tier", -1)) == 0
				and str(recipe.get("station", "")) in TIER_ZERO_BLUEPRINTS
			):
				recipes[str(recipe.id)] = true
	var required_recipes := {}
	var obtainable_recipes := {}
	for recipe in RecipeDatabaseScript.get_all_recipes():
		var station := str(recipe.get("station", ""))
		if blueprints.has(station) and int(recipe.get("unlock_tier", -1)) <= int(BLUEPRINT_TIERS[station]):
			required_recipes[str(recipe.id)] = true
			obtainable_recipes[str(recipe.id)] = true
	for definition in RECIPE_SERVICES.values():
		var recipe_id := str((definition as Dictionary).target_id)
		var recipe := RecipeDatabaseScript.get_recipe(recipe_id)
		if blueprints.has(str(recipe.get("station", ""))):
			obtainable_recipes[recipe_id] = true
	for recipe_id in required_recipes:
		if not recipes.has(recipe_id):
			return null
	for recipe_id in recipes:
		if not obtainable_recipes.has(recipe_id):
			return null
	var upgrades := {}
	for record_value in data.upgrade_levels:
		if not record_value is Dictionary:
			return null
		var record := record_value as Dictionary
		if record.size() != 2 or not record.get("building_key") is String or not record.get("levels") is Array:
			return null
		var key := str(record.building_key)
		if not is_valid_building_key(key) or upgrades.has(key):
			return null
		var levels := {}
		for level_value in record.levels:
			if not level_value is Dictionary:
				return null
			var level_record := level_value as Dictionary
			if level_record.size() != 2 or not level_record.get("upgrade_id") is String:
				return null
			var upgrade_id := str(level_record.upgrade_id)
			if upgrade_id not in MAX_UPGRADE_LEVELS or levels.has(upgrade_id):
				return null
			if not _integer_in_range(level_record.get("level"), 1, int(MAX_UPGRADE_LEVELS[upgrade_id])):
				return null
			levels[upgrade_id] = int(level_record.level)
		upgrades[key] = levels
	return {"blueprints": blueprints, "recipes": recipes, "upgrades": upgrades}


static func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	return (
		typeof(value) == TYPE_FLOAT and is_finite(value)
		and floorf(value) == value
		and value >= float(minimum) and value <= float(maximum)
	)


static func _valid_wallet(wallet: Variant) -> bool:
	return (
		wallet != null and is_instance_valid(wallet)
		and wallet.has_method("spend_gold") and wallet.has_method("add_gold")
		and _has_property(wallet, "gold") and _has_property(wallet, "player_state")
	)


static func _has_property(target: Variant, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _event_bus() -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/EventBus")
	var loop := Engine.get_main_loop()
	return loop.root.get_node_or_null("EventBus") if loop is SceneTree else null


func _emit_event(signal_name: StringName, arguments: Array) -> void:
	var event_bus := _event_bus()
	if event_bus != null and event_bus.has_signal(signal_name):
		event_bus.callv("emit_signal", [signal_name] + arguments)
