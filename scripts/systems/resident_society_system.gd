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
var focus: Array = []
var batch_times_us: Array = []
var batch_max_us := 0
var feeding := {}
var minute_batch := {}
var cooperative: VisibleNpcFarmSystem
var cooperative_saved := {}
var shift_routes := {}

func bind_cooperative() -> void:
	if not expanded(): return
	if cooperative == null:
		cooperative = VisibleNpcFarmSystem.new()
		cooperative.farm_width = 10; cooperative.farm_height = 8
		world.add_child(cooperative)
		if not cooperative.configure(world.session.grid, world.session.farming, world.session.npc_economy, world.get_node("/root/GameData"), "village_coop", Vector3(14, 0, 16)):
			cooperative.queue_free(); cooperative = null; return
	elif cooperative_saved.is_empty():
		world.session.grid.release_cells("village_coop")
		cooperative.configure(world.session.grid, world.session.farming, world.session.npc_economy, world.get_node("/root/GameData"), "village_coop", Vector3(14, 0, 16))
	if not cooperative_saved.is_empty(): cooperative.from_dict(cooperative_saved)
	cooperative_saved = cooperative.to_dict()
	paths.invalidate()

func valid_cooperative(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if not expanded() or value.get("agent_id") != "village_coop": return false
	var validator := VisibleNpcFarmSystem.new()
	validator.farm_width = 10; validator.farm_height = 8; validator._grid = world.session.grid
	var valid := validator.validate_dict(value)
	validator.free()
	return valid

func _work_fields(shift: Dictionary, operation: int) -> void:
	if cooperative == null: return
	for plot in ([shift.plots[operation]] if operation < 4 else []):
		var cell := cooperative.get_plot_cell("village_coop", int(plot))
		if cell == null: continue
		if cell.crop_instance != null:
			var harvest: Dictionary = cooperative._commit_harvest(cell, int(plot))
			if harvest.ok: _record("farm_harvest", "village_coop", 0, harvest.get("resource_delta", {}), shift.id)
		if cell.state == GridCell.State.WASTELAND: cooperative._commit_action({"tool_name": "till", "arguments": {"plot": int(plot)}})
		if cell.state == GridCell.State.FARMLAND:
			for seed_item in (["carrot_seed", "potato_seed"] if int(plot) % 2 == 0 else ["potato_seed", "carrot_seed"]):
				var preview: Dictionary = world.session.farming.preview_plant(cell, seed_item)
				if not preview.ok: continue
				if int(world.assets.available_items("village_coop").get(seed_item, 0)) == 0: world.session.npc_economy.agent_buy("village_coop", seed_item, 1)
				var planted: Dictionary = cooperative._commit_plant({"arguments": {"seed_item_id": seed_item}}, cell, int(plot))
				if planted.ok: _record("seed_planted", "village_coop", 0, {seed_item: -1}, shift.id)
				break
		if cell.crop_instance != null: world.session.farming.water(cell)
	# Harvest belongs to the cooperative until sold through the original market.
	for food in ([["carrot", "potato"][operation - 4]] if operation >= 4 else []):
		var quantity := mini(12, int(world.assets.available_items("village_coop").get(food, 0)))
		if quantity > 0: world.session.npc_economy.agent_sell("village_coop", food, quantity)

static func expanded() -> bool:
	var args := OS.get_cmdline_user_args()
	if "--living-world-scenario=P12" in args: return true
	if "--farm-test" in args or Array(args).any(func(a): return str(a).begins_with("--living-world-scenario=")): return false
	return true

static func configuration(small := false) -> Dictionary:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if expanded() and not small:
		cfg.residents.append_array(cfg.get("additional_residents", []))
		cfg.organizations.append_array(cfg.get("additional_organizations", []))
		cfg.shift_slots = int(cfg.get("expanded_shift_slots", 24))
		cfg.shift_wage = 30
		cfg.food_preferences = ["carrot", "potato", "bread", "grilled_fish"]
	return cfg

static func economy_profiles(small := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = Data.get_npc_economy_profiles()
	var cfg := configuration(small)
	var known := {}
	for p in result: known[p.id] = true
	for entry in cfg.residents + cfg.organizations:
		if known.has(entry.id): continue
		result.append({"id": entry.id, "display_name": entry.name, "gold": int(entry.get("gold", cfg.new_resident_gold)),
			"inventory": entry.get("inventory", {}).duplicate(true) if entry.has("gold") else cfg.new_resident_inventory.duplicate(true), "essential_targets": {},
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
	feeding = {}
	minute_batch = {}
	shift_routes.clear()
	residents.clear()
	shifts.clear()
	ledger.clear()
	day_reports.clear()
	last_minute = minute
	external_gold_net = 0
	initial_gold = 0
	focus = config.focus_actors.duplicate() if expanded() else ["farmer_ahe", "lao_li", "xuezhe_lin"]
	for state in world.session.npc_economy._states.values(): initial_gold += int(state.gold)
	for index in config.residents.size():
		var entry: Dictionary = config.residents[index]
		var pos: Vector2 = world.session.market_site + Vector2(-8 + index % 4 * 2, -8 - index / 4 * 2)
		if expanded():
			var origin: Vector2i = world.session.grid.world_to_grid(pos.x, pos.y)
			for radius in range(0, 5):
				var found := false
				for offset in [Vector2i(radius, 0), Vector2i(-radius, 0), Vector2i(0, radius), Vector2i(0, -radius)]:
					if world.session.grid.is_navigation_cell_walkable(origin + offset):
						pos = world.session.grid.grid_to_world(origin.x + offset.x, origin.y + offset.y); found = true; break
				if found: break
		residents[entry.id] = {"id": entry.id, "name": entry.name, "occupation": entry.occupation,
			"position": {"x": pos.x, "z": pos.y}, "state": "休息", "last_meal_day": -1, "hungry_days": 0, "food_reason": "", "reserve_days": int(config.food_reserve_days)}
	_record("initial_endowment", "society", initial_gold, {}, "一次性初始／迁移余额基线")

func advance_to(target: int, budget_us := 0) -> void:
	var started := Time.get_ticks_usec()
	while not caught_up(target):
		if not minute_batch.is_empty():
			_step_minute_batch()
		elif not feeding.is_empty():
			var id: String = feeding.queue[int(feeding.index)]
			_feed_resident(residents[id], int(feeding.day), day_reports[str(feeding.day)])
			feeding.index = int(feeding.index) + 1
			if int(feeding.index) >= feeding.queue.size(): feeding = {}
		else:
			last_minute += 1
			var day := last_minute / DAY_MINUTES + 1
			var clock := last_minute % DAY_MINUTES
			if expanded():
				minute_batch = {"phase": "open" if clock == 120 else "work", "day": day, "clock": clock, "index": 0, "keys": []}
				if clock != 120: _queue_shift_steps()
			else:
				if clock == 120: _open_shifts(day)
				_step_shifts(day, clock)
				_finish_minute(day, clock)
		if budget_us > 0 and Time.get_ticks_usec() - started >= budget_us: break
	var elapsed_us := Time.get_ticks_usec() - started
	batch_max_us = maxi(batch_max_us, elapsed_us)
	batch_times_us.append(elapsed_us)
	if batch_times_us.size() > 10000: batch_times_us.pop_front()

func caught_up(target: int) -> bool:
	return last_minute >= target and feeding.is_empty() and minute_batch.is_empty()

func _finish_minute(day: int, clock: int) -> void:
	if clock == 840: _feed_day(day)
	if clock == DAY_MINUTES - 1: _close_day(day)

func _queue_shift_steps() -> void:
	minute_batch.phase = "work"; minute_batch.index = 0
	minute_batch.keys = shifts.keys().filter(func(id): return int(shifts[id].day) == int(minute_batch.day) and shifts[id].status in ["traveling", "working"])
	if minute_batch.keys.is_empty():
		_finish_minute(int(minute_batch.day), int(minute_batch.clock)); minute_batch = {}

func _step_minute_batch() -> void:
	if minute_batch.phase == "open":
		_open_shifts(int(minute_batch.day), int(minute_batch.index), 1)
		minute_batch.index = int(minute_batch.index) + 1
		if int(minute_batch.index) >= int(config.shift_slots): _queue_shift_steps()
		return
	_step_shifts(int(minute_batch.day), int(minute_batch.clock), str(minute_batch.keys[int(minute_batch.index)]))
	minute_batch.index = int(minute_batch.index) + 1
	if int(minute_batch.index) >= minute_batch.keys.size():
		_finish_minute(int(minute_batch.day), int(minute_batch.clock)); minute_batch = {}


func _open_shifts(day: int, first_slot := 0, slot_count := -1) -> void:
	if first_slot == 0: world.board.daily(day)
	var workers: Array = config.residents.filter(func(entry: Dictionary): return entry.id not in focus)
	for slot in range(first_slot, int(config.shift_slots) if slot_count < 0 else mini(int(config.shift_slots), first_slot + slot_count)):
		var actor := str(workers[((day - 1) * 3 + slot) % workers.size()].id)
		if world.work != null and world.work.owns_schedule(actor): continue
		var id := "shift-%d-%s" % [day, actor]
		if shifts.has(id): continue
		var wage := int(config.shift_wage)
		var employer := "village_coop" if expanded() and cooperative != null and slot < 20 else "village_inn"
		if not world.assets.apply(employer, {}, -wage): continue
		shifts[id] = {"id": id, "actor_id": actor, "employer_id": employer, "day": day,
			"wage": wage, "escrow": wage, "worked_minutes": 0, "status": "traveling", "position": {"x": world.session.market_site.x - 6, "z": world.session.market_site.y - 5}}
		if employer == "village_coop":
			shifts[id].plots = [slot * 4, slot * 4 + 1, slot * 4 + 2, slot * 4 + 3]
			var cell := cooperative.get_plot_cell(employer, slot * 4)
			var pos := cell.world_position_3d()
			shifts[id].position = {"x": pos.x, "z": pos.z}
		_record("wage_escrow", employer, -wage, {}, id)

func _step_shifts(day: int, clock: int, only_id := "") -> void:
	for shift in (shifts.values() if only_id.is_empty() else [shifts[only_id]]):
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
			var cached: Dictionary = shift_routes.get(shift.id, {})
			if cached.is_empty() or int(cached.revision) != grid.get_navigation_revision():
				cached = {"revision": grid.get_navigation_revision(), "cells": paths.find_path_cells(grid.world_to_grid(current.x, current.y), grid.world_to_grid(target.x, target.y))}
				shift_routes[shift.id] = cached
			var route: Array = cached.cells
			if route.is_empty():
				resident.state = "道路受阻，未计工时"
				continue
			var here: Vector2i = grid.world_to_grid(current.x, current.y)
			while route.size() > 1 and route[0] == here: route.pop_front()
			var next: Vector2 = target if route.size() == 1 and route[0] == here else grid.grid_to_world(route[0].x, route[0].y)
			current = current.move_toward(next, 1.2)
			resident.position = {"x": current.x, "z": current.y}
			resident.state = "前往合作社农田" if shift.employer_id == "village_coop" else "前往旅店"
			continue
		shift.status = "working"
		resident.state = "合作社农务" if shift.employer_id == "village_coop" else "旅店值班"
		shift.worked_minutes = mini(int(config.shift_minutes), int(shift.worked_minutes) + 1)
		if int(shift.worked_minutes) >= int(config.shift_minutes) and shift.employer_id == "village_coop":
			var cursor := int(shift.get("field_cursor", 0))
			if cursor < 6:
				_work_fields(shift, cursor)
				shift.field_cursor = cursor + 1
			if int(shift.field_cursor) < 6: continue
		if int(shift.worked_minutes) >= int(config.shift_minutes) and world.assets.apply(shift.actor_id, {}, int(shift.escrow)):
			_record("wage_paid", shift.actor_id, int(shift.escrow), {}, shift.id)
			shift.escrow = 0
			shift.status = "completed"
			resident.state = "下班采购"

func _feed_day(day: int) -> void:
	if day_reports.has(str(day)): return
	world.board.buy_inn_share(day)
	day_reports[str(day)] = {"day": day, "fed": 0, "hungry": 0, "purchases": 0, "consumed": {}, "shortage": 0, "unaffordable": 0}
	feeding = {"day": day, "queue": residents.keys(), "index": 0}

func _feed_resident(resident: Dictionary, day: int, report: Dictionary) -> void:
	if int(resident.last_meal_day) >= day: return
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
	return "%d 名居民 · %d 个组织 · 昨日用餐 %d / %d，缺粮 %d · 市场净流入 %d 金币" % [residents.size(), config.organizations.size(), int(last.get("fed", 0)), residents.size(), int(last.get("hungry", 0)), external_gold_net]

func to_dict() -> Dictionary:
	return {"version": 5, "minute_batch": minute_batch.duplicate(true), "cooperative": cooperative.to_dict() if cooperative != null else {}, "feeding": feeding.duplicate(true), "focus": focus.duplicate(), "residents": residents.duplicate(true), "shifts": shifts.duplicate(true), "ledger": ledger.duplicate(true), "day_reports": day_reports.duplicate(true), "last_minute": last_minute, "external_gold_net": external_gold_net, "initial_gold": initial_gold}

func validate(value: Variant) -> bool:
	if not value is Dictionary or not world.integer(value.get("version")) or int(value.version) not in [1, 2, 3, 4, 5] or value.size() != (7 + int(value.version)): return false
	if not value.get("residents") is Dictionary or value.residents.size() != config.residents.size() or not value.get("shifts") is Dictionary or not value.get("ledger") is Array or not value.get("day_reports") is Dictionary: return false
	if value.version >= 2:
		if not value.get("focus") is Array or value.focus.size() > 8: return false
		for actor in value.focus:
			if not value.residents.has(actor) or value.focus.count(actor) != 1: return false
	for key in ["last_minute", "external_gold_net", "initial_gold"]:
		if not world.integer(value.get(key)): return false
	if int(value.last_minute) < 0 or int(value.initial_gold) < 0 or value.ledger.size() > 4096: return false
	if value.version >= 5:
		if not value.get("minute_batch") is Dictionary: return false
		if not value.minute_batch.is_empty():
			var batch: Dictionary = value.minute_batch
			if batch.size() != 5 or batch.get("phase") not in ["open", "work"] or not world.integer(batch.get("day")) or not world.integer(batch.get("clock")) or not world.integer(batch.get("index")) or not batch.get("keys") is Array: return false
			if int(batch.day) != int(value.last_minute) / DAY_MINUTES + 1 or int(batch.clock) != int(value.last_minute) % DAY_MINUTES or int(batch.index) < 0: return false
			if batch.phase == "open" and (int(batch.clock) != 120 or int(batch.index) >= int(config.shift_slots) or not batch.keys.is_empty()): return false
			if batch.phase == "work":
				if int(batch.index) >= batch.keys.size(): return false
				for id in batch.keys:
					if not value.shifts.has(id) or batch.keys.count(id) != 1 or int(value.shifts[id].day) != int(batch.day): return false
	if value.version >= 4 and not valid_cooperative(value.get("cooperative")): return false
	if value.version >= 3:
		if not value.get("feeding") is Dictionary: return false
		if not value.feeding.is_empty():
			var f: Dictionary = value.feeding
			if f.size() != 3 or not world.integer(f.get("day")) or not world.integer(f.get("index")) or not f.get("queue") is Array or f.queue.size() != value.residents.size() or int(f.index) < 0 or int(f.index) >= f.queue.size() or not value.day_reports.has(str(int(f.day))): return false
			for id in f.queue:
				if not value.residents.has(id) or f.queue.count(id) != 1: return false
	for entry in config.residents:
		var r: Variant = value.residents.get(entry.id)
		if not r is Dictionary or r.get("id") != entry.id or not world.position_valid(r.get("position")): return false
		for key in ["last_meal_day", "hungry_days", "reserve_days"]:
			if not world.integer(r.get(key)): return false
		if int(r.hungry_days) < 0 or int(r.reserve_days) not in [1, 2, 3, 4, 5] or not r.get("state") is String or not r.get("food_reason") is String: return false
		if r.size() != 9 or r.get("name") != entry.name or r.get("occupation") != entry.occupation or int(r.last_meal_day) > int(value.last_minute) / DAY_MINUTES + 1: return false
	var occupied := {}
	for id in value.shifts:
		var shift: Variant = value.shifts[id]
		if not shift is Dictionary or shift.get("id") != id or not value.residents.has(shift.get("actor_id")) or shift.get("employer_id") not in (["village_inn", "village_coop"] if expanded() else ["village_inn"]): return false
		for key in ["day", "wage", "escrow", "worked_minutes"]:
			if not world.integer(shift.get(key)) or int(shift[key]) < 0: return false
		if not world.position_valid(shift.get("position")) or shift.get("status") not in ["traveling", "working", "completed", "cancelled"]: return false
		if int(shift.wage) not in [30, 90] or int(shift.worked_minutes) > int(config.shift_minutes): return false
		if shift.employer_id == "village_coop":
			if not shift.get("plots") is Array or shift.plots.size() != 4: return false
			if shift.has("field_cursor") and (not world.integer(shift.field_cursor) or int(shift.field_cursor) < 0 or int(shift.field_cursor) > 6 or int(shift.worked_minutes) != int(config.shift_minutes)): return false
			for plot in shift.plots:
				if not world.integer(plot) or int(plot) < 0 or int(plot) >= 80 or shift.plots.count(plot) != 1: return false
		if shift.status == "completed" and int(shift.worked_minutes) != int(config.shift_minutes): return false
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
			if not world.integer(report.get(key)) or int(report[key]) < 0 or int(report[key]) > config.residents.size(): return false
		if int(report.fed) + int(report.hungry) > config.residents.size(): return false
	return true

func restore(value: Dictionary) -> void:
	minute_batch = value.get("minute_batch", {}).duplicate(true)
	cooperative_saved = value.get("cooperative", {}).duplicate(true)
	shift_routes.clear()
	feeding = value.get("feeding", {}).duplicate(true)
	focus = value.get("focus", ["farmer_ahe", "lao_li", "xuezhe_lin"]).duplicate()
	residents = value.residents.duplicate(true)
	shifts = value.shifts.duplicate(true)
	ledger = value.ledger.duplicate(true)
	day_reports = value.day_reports.duplicate(true)
	last_minute = int(value.last_minute)
	external_gold_net = int(value.external_gold_net)
	initial_gold = int(value.initial_gold)

func set_focus(actor: String, enabled: bool) -> Dictionary:
	if not residents.has(actor) or not world.session.agent_runtime.registry.is_agent_managed(actor): return {"ok": false, "error": "unknown_resident_profile"}
	if (actor in focus) == enabled: return {"ok": true}
	if enabled and focus.size() >= 8: return {"ok": false, "error": "focus_pool_full"}
	if (world.work.occupied(actor) or world.session.agent_runtime.scheduler.is_in_flight(actor)): return {"ok": false, "error": "finish_existing_commitment_before_demotion"}
	var body: Node3D = world.actor(actor)
	if body != null: residents[actor].position = {"x": body.position.x, "z": body.position.z}
	if enabled: focus.append(actor)
	else: focus.erase(actor)
	world.session.agent_runtime.sync_focus_actors()
	return {"ok": true, "message": "角色保留原账户、关系、项目和记忆；仅切换自主规划与背景生活执行。"}
