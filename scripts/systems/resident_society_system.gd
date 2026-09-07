extends RefCounted

const Data = preload("res://scripts/core/game_data.gd")
const CONFIG_PATH := "res://data/living_world/residents.json"
const DAY_MINUTES := 1080
var world: Node
var config: Dictionary
var residents: Dictionary = {}
var shifts: Dictionary = {}
var ledger: Array = []
var day_reports: Dictionary = {}
var last_minute := 0
var external_gold_net := 0
var initial_gold := 0
var paths := GridPathfinder.new()

static func configuration() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))

static func economy_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = Data.get_npc_economy_profiles()
	var cfg := configuration()
	var known := {}
	for p in result: known[p.id] = true
	for entry in cfg.residents + cfg.organizations:
		if known.has(entry.id): continue
		result.append({"id": entry.id, "display_name": entry.name, "gold": int(entry.get("gold", cfg.new_resident_gold)),
			"inventory": {} if entry.has("gold") else cfg.new_resident_inventory.duplicate(true), "essential_targets": {},
			"reserve_targets": {}, "production_recipes": [], "sale_targets": {}, "investment_gold_threshold": 0, "import_buffer": false})
	return result

static func external_population() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Builders/artisans are residents too. Only off-map tourists retain aggregate demand.
	for entry in Data.get_population_demand_profiles():
		if entry.id == "tourists": result.append(entry)
	return result

func configure(owner: Node) -> void:
	world = owner
	config = configuration()
	paths.configure(world.session.grid)
	for id in world.session.npc_economy._states: world.session.npc_economy.set_agent_managed(id, true)
	world.session.npc_economy.market_trade_committed.connect(_market_trade)
	reset(world.minute())

func reset(minute: int) -> void:
	residents.clear()
	shifts.clear()
	ledger.clear()
	day_reports.clear()
	last_minute = minute
	external_gold_net = 0
	initial_gold = 0
	for state in world.session.npc_economy._states.values(): initial_gold += int(state.gold)
	for index in config.residents.size():
		var entry: Dictionary = config.residents[index]
		var pos: Vector2 = world.session.market_site + Vector2(-8 + index % 4 * 2, -8 - index / 4 * 2)
		residents[entry.id] = {"id": entry.id, "name": entry.name, "occupation": entry.occupation,
			"position": {"x": pos.x, "z": pos.y}, "state": "休息", "last_meal_day": -1, "hungry_days": 0, "food_reason": "", "reserve_days": int(config.food_reserve_days)}
	_record("initial_endowment", "society", initial_gold, {}, "一次性初始／迁移余额基线")

func advance_to(target: int) -> void:
	if target <= last_minute: return
	for minute in range(last_minute + 1, target + 1):
		last_minute = minute
		var day := minute / DAY_MINUTES + 1
		var clock := minute % DAY_MINUTES
		if clock == 120: _open_shifts(day)
		_step_shifts(day, clock)
		if clock == 840: _feed_day(day)
		if clock == DAY_MINUTES - 1: _close_day(day)

func _open_shifts(day: int) -> void:
	world.board.daily(day)
	var workers: Array = config.residents.filter(func(entry: Dictionary): return entry.id not in ["farmer_ahe", "lao_li", "xuezhe_lin"])
	for slot in int(config.shift_slots):
		var actor := str(workers[((day - 1) * 3 + slot) % workers.size()].id)
		var id := "shift-%d-%s" % [day, actor]
		if shifts.has(id): continue
		var wage := int(config.shift_wage)
		if not world.assets.apply("village_inn", {}, -wage): continue
		shifts[id] = {"id": id, "actor_id": actor, "employer_id": "village_inn", "day": day,
			"wage": wage, "escrow": wage, "worked_minutes": 0, "status": "traveling", "position": {"x": world.session.market_site.x - 6, "z": world.session.market_site.y - 5}}
		_record("wage_escrow", "village_inn", -wage, {}, id)

func _step_shifts(day: int, clock: int) -> void:
	for shift in shifts.values():
		if int(shift.day) != day or shift.status not in ["traveling", "working"]: continue
		var resident: Dictionary = residents[shift.actor_id]
		var current := Vector2(resident.position.x, resident.position.z)
		var target := Vector2(shift.position.x, shift.position.z)
		if clock >= 540:
			if world.assets.apply(shift.employer_id, {}, int(shift.escrow)):
				shift.escrow = 0
				shift.status = "cancelled"
				resident.state = "班次未完成"
			continue
		if current.distance_to(target) > .5:
			var grid: GridSystem = world.session.grid
			var route := paths.find_path_cells(grid.world_to_grid(current.x, current.y), grid.world_to_grid(target.x, target.y))
			if route.is_empty():
				resident.state = "道路受阻，未计工时"
				continue
			var next: Vector2 = target if route.size() < 2 else grid.grid_to_world(route[1].x, route[1].y)
			current = current.move_toward(next, 1.2)
			resident.position = {"x": current.x, "z": current.y}
			resident.state = "前往旅店"
			continue
		shift.status = "working"
		resident.state = "旅店值班"
		shift.worked_minutes = int(shift.worked_minutes) + 1
		if int(shift.worked_minutes) >= int(config.shift_minutes) and world.assets.apply(shift.actor_id, {}, int(shift.escrow)):
			_record("wage_paid", shift.actor_id, int(shift.escrow), {}, shift.id)
			shift.escrow = 0
			shift.status = "completed"
			resident.state = "下班采购"

func _feed_day(day: int) -> void:
	if day_reports.has(str(day)): return
	world.board.buy_inn_share(day)
	var report := {"day": day, "fed": 0, "hungry": 0, "purchases": 0, "consumed": {}, "shortage": 0, "unaffordable": 0}
	for resident in residents.values():
		if int(resident.last_meal_day) >= day: continue
		var actor := str(resident.id)
		var stock: Dictionary = world.assets.available_items(actor)
		var reserve := 0
		for food in config.food_preferences: reserve += int(stock.get(food, 0))
		var reason := "market_shortage"
		for food in config.food_preferences:
			if reserve >= int(resident.reserve_days): break
			var needed := int(resident.reserve_days) - reserve
			for count in needed:
				if not world.session.market.can_buy(food, 1): break
				var price: int = world.session.npc_economy.quote_agent_buy(food, 1)
				if not world.assets.can_apply(actor, {}, -price):
					reason = "unaffordable"
					break
				if world.session.npc_economy.agent_buy(actor, food, 1):
					reserve += 1
					report.purchases += 1
		var fed := false
		for food in config.food_preferences:
			if world.assets.apply(actor, {food: -1}, 0):
				fed = true
				report.consumed[food] = int(report.consumed.get(food, 0)) + 1
				_record("food_consumed", actor, 0, {food: -1}, "day-%d" % day)
				break
		resident.last_meal_day = day
		resident.hungry_days = 0 if fed else int(resident.hungry_days) + 1
		resident.food_reason = "" if fed else reason
		resident.state = "已用餐" if fed else "缺少食物"
		report.fed += 1 if fed else 0
		report.hungry += 0 if fed else 1
		if not fed: report["unaffordable" if reason == "unaffordable" else "shortage"] += 1
	day_reports[str(day)] = report

func _close_day(day: int) -> void:
	var report: Dictionary = day_reports.get(str(day), {"day": day, "fed": 0, "hungry": 0})
	report.gold_in_accounts = total_gold()
	report.wage_escrow = wage_escrow()
	report.external_gold_net = external_gold_net
	day_reports[str(day)] = report

func total_gold() -> int:
	var total := 0
	for state in world.session.npc_economy._states.values(): total += int(state.gold)
	return total

func wage_escrow() -> int:
	var total := 0
	for shift in shifts.values(): total += int(shift.escrow)
	return total

func _market_trade(actor: String, items: Dictionary, total: int, buying: bool) -> void:
	var flow := -total if buying else total
	external_gold_net += flow
	_record("market_purchase" if buying else "market_sale", actor, flow, items, "外部市场做市商")

func _record(kind: String, actor: String, gold: int, items: Dictionary, source: String) -> void:
	ledger.append({"minute": last_minute, "kind": kind, "actor_id": actor, "gold": gold, "items": items.duplicate(true), "source": source})
	if ledger.size() > 4096: ledger.pop_front()

func summary() -> String:
	var last: Dictionary = day_reports.get(str(last_minute / DAY_MINUTES), {})
	return "12 名居民 · 2 个组织 · 昨日用餐 %d / 12，缺粮 %d · 市场净流入 %d 金币" % [int(last.get("fed", 0)), int(last.get("hungry", 0)), external_gold_net]

func to_dict() -> Dictionary:
	return {"version": 1, "residents": residents.duplicate(true), "shifts": shifts.duplicate(true), "ledger": ledger.duplicate(true), "day_reports": day_reports.duplicate(true), "last_minute": last_minute, "external_gold_net": external_gold_net, "initial_gold": initial_gold}

func validate(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 8 or value.get("version") != 1: return false
	if not value.get("residents") is Dictionary or value.residents.size() != 12 or not value.get("shifts") is Dictionary or not value.get("ledger") is Array or not value.get("day_reports") is Dictionary: return false
	for key in ["last_minute", "external_gold_net", "initial_gold"]:
		if not world.integer(value.get(key)): return false
	if int(value.last_minute) < 0 or int(value.initial_gold) < 0 or value.ledger.size() > 4096: return false
	for entry in config.residents:
		var r: Variant = value.residents.get(entry.id)
		if not r is Dictionary or r.get("id") != entry.id or not world.position_valid(r.get("position")): return false
		for key in ["last_meal_day", "hungry_days", "reserve_days"]:
			if not world.integer(r.get(key)): return false
		if int(r.hungry_days) < 0 or int(r.reserve_days) not in [1, 2, 3] or not r.get("state") is String or not r.get("food_reason") is String: return false
		if r.size() != 9 or r.get("name") != entry.name or r.get("occupation") != entry.occupation or int(r.last_meal_day) > int(value.last_minute) / DAY_MINUTES + 1: return false
	var occupied := {}
	for id in value.shifts:
		var shift: Variant = value.shifts[id]
		if not shift is Dictionary or shift.get("id") != id or not value.residents.has(shift.get("actor_id")) or shift.get("employer_id") != "village_inn": return false
		for key in ["day", "wage", "escrow", "worked_minutes"]:
			if not world.integer(shift.get(key)) or int(shift[key]) < 0: return false
		if not world.position_valid(shift.get("position")) or shift.get("status") not in ["traveling", "working", "completed", "cancelled"]: return false
		if int(shift.wage) != int(config.shift_wage) or int(shift.worked_minutes) > int(config.shift_minutes): return false
		if int(shift.escrow) != (int(shift.wage) if shift.status in ["traveling", "working"] else 0): return false
		var key := "%s:%d" % [shift.actor_id, int(shift.day)]
		if occupied.has(key): return false
		occupied[key] = true
	for entry in value.ledger:
		if not entry is Dictionary or entry.size() != 6 or not world.integer(entry.get("minute")) or int(entry.minute) < 0 or int(entry.minute) > int(value.last_minute) or not world.integer(entry.get("gold")) or not entry.get("kind") is String or not entry.get("actor_id") is String or not entry.get("source") is String or not entry.get("items") is Dictionary: return false
		for item in entry.items:
			if not item is String or not world.integer(entry.items[item]): return false
	for id in value.day_reports:
		var report: Variant = value.day_reports[id]
		if not report is Dictionary or not world.integer(report.get("day")) or str(int(report.day)) != id: return false
		for key in ["fed", "hungry"]:
			if not world.integer(report.get(key)) or int(report[key]) < 0 or int(report[key]) > 12: return false
		if int(report.fed) + int(report.hungry) > 12: return false
	return true

func restore(value: Dictionary) -> void:
	residents = value.residents.duplicate(true)
	shifts = value.shifts.duplicate(true)
	ledger = value.ledger.duplicate(true)
	day_reports = value.day_reports.duplicate(true)
	last_minute = int(value.last_minute)
	external_gold_net = int(value.external_gold_net)
	initial_gold = int(value.initial_gold)
