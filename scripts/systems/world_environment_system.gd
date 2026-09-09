extends RefCounted

const Rules = preload("res://scripts/systems/npc_project_system.gd")
const ORIGIN := {"grain": 120, "bread": 60, "carrot": 60, "potato": 60, "salt": 60}
const REPAIR := {"wood": 6, "stone": 4}
const SITE := Vector3(-18.5, 0, 22.5)
const TOOLS := ["contribute_route_repair"]
var world: Node
var seed := 93
var last_minute := 0
var days := {}
var warehouse := ORIGIN.duplicate(true)
var transports := {}
var event := {}
var repairs := {}
var receipts := {}
var public_funding := {}
var watered := {}
var _rain_scan_minute := -1

func configure(owner: Node) -> void:
	world = owner
	last_minute = world.minute()
	world.session.npc_economy.import_dispatcher = dispatch_import
	ensure_day(last_minute / 1080)

func ensure_day(day: int) -> Dictionary:
	var key := str(day)
	if not days.has(key):
		var rainy := absi(hash("weather:%d:%d" % [seed, day])) % 4 == 0
		days[key] = {"day": day, "rain": rainy, "start": day * 1080 + 180, "end": day * 1080 + 660, "forecast_issued": maxi(0, (day - 1) * 1080), "kind": "forecast"}
	return days[key]

func raining(minute := -1) -> bool:
	if minute < 0: minute = world.minute()
	var d := ensure_day(minute / 1080)
	return d.rain and minute >= int(d.start) and minute < int(d.end)

func route_open() -> bool:
	return event.is_empty() or event.status == "recovered"

func advance_to(target: int) -> void:
	if world.get_tree().paused or target < last_minute: return
	_advance_public()
	for now in range(last_minute + 1, target + 1):
		last_minute = now
		var day := ensure_day(now / 1080)
		if now == int(day.start) and day.rain and route_open():
			event = {"id": "road-%d" % (now / 1080), "status": "blocked", "started": now, "natural_recovery": now + 1080, "materials": {"wood": 0, "stone": 0}, "labor": 0, "recovered": -1, "cause": "降雨冲坏场外商道，商队停留；庄园内步道可通行"}
		if now == int(day.start) and day.rain: _apply_rain(now)
		_advance_repairs(now)
		if not route_open() and now >= int(event.natural_recovery): _recover("natural_drainage")
		for t in transports.values():
			if t.status != "transit": continue
			if not route_open(): t.arrival = int(t.arrival) + 1; t.delayed = int(t.delayed) + 1
			elif now >= int(t.arrival): _arrive(t)
	ensure_day(target / 1080 + 1)
	_apply_rain(target)
	_advance_public()

func _apply_rain(now: int) -> void:
	if not raining(now) or _rain_scan_minute == now: return
	_rain_scan_minute = now
	var day := str(now / 1080)
	if not watered.has(day): watered[day] = []
	for cell in world.session.farming.get_all_planted_cells():
		if cell.crop_instance == null or cell.crop_instance.crop_data.crop_id not in ["grain", "carrot", "potato"] or world.session.farming.is_greenhouse_cell(cell): continue
		var key := GridSystem.cell_key(cell.gx, cell.gz)
		if key in watered[day]: continue
		cell.watered = true
		cell.crop_instance.is_watered_today = true
		watered[day].append(key)

func dispatch_import(actor: String, item: String, quantity: int, cost: int, day: int) -> bool:
	if not route_open() or not warehouse.has(item) or quantity < 1 or cost < 1 or int(warehouse[item]) < quantity: return false
	var used := 0
	for t in transports.values():
		if int(t.departure) / 1080 == world.minute() / 1080: used += int(t.quantity)
	if used + quantity > 24: return false
	var id := "import-%d-%s" % [day, item]
	if transports.has(id): return false
	if not world.assets.apply(actor, {}, -cost): return false
	warehouse[item] = int(warehouse[item]) - quantity
	transports[id] = {"id": id, "owner": actor, "item_id": item, "quantity": quantity, "cost": cost, "departure": world.minute(), "arrival": world.minute() + (480 if raining() else 180), "delayed": 0, "status": "transit", "received": -1}
	world.session.npc_economy._demand_tags["import:" + item] = "商队已付款装货，尚未到达；库存仍在场外运输中"
	return true

func _arrive(t: Dictionary) -> void:
	# Original market transaction updates stock and supply exactly once. The importer
	# has prepaid the origin; local sale receipts are the importer's actual income.
	var market: Node = world.session.market
	var price: int = market.quote_sell(t.item_id, int(t.quantity))
	if price < 0 or not world.assets.can_apply(t.owner, {}, price): return
	var before: Dictionary = market.to_dict()
	var transaction: Variant = market.begin_atomic_transaction()
	if transaction == null: return
	if not market.stage_sell(transaction, t.item_id, int(t.quantity)):
		market.rollback_atomic_transaction(transaction); return
	var publication: Variant = market.seal_atomic_transaction(transaction)
	if publication == null: market.rollback_atomic_transaction(transaction); return
	var batch: Variant = market.finalize_sealed_publication(publication)
	if batch == null: market.restore_from_dict_with_current_catalog(before); return
	world.assets.apply(t.owner, {}, price)
	t.status = "arrived"; t.received = last_minute; t.proceeds = price
	world.society._market_trade(t.owner, {t.item_id: int(t.quantity)}, price, false)
	market.dispatch_finalized_publication(batch)
	world.session.npc_economy._demand_tags["import:" + t.item_id] = "商队实到 %d 份，延误 %d 分钟；按实际供给结算价格" % [t.quantity, t.delayed]

static func valid_command(tool: String, a: Dictionary) -> bool:
	return tool == "contribute_route_repair" and a.size() == 3 and Rules._id(a.get("event_id")) and a.get("materials") is Dictionary and a.materials.keys().all(func(k): return k in REPAIR and Rules._count(a.materials[k], 1, REPAIR[k])) and Rules._count(a.get("labor_minutes"), 0, 60) and (not a.materials.is_empty() or int(a.labor_minutes) > 0)

func command(actor: String, tool: String, args: Dictionary, key: String) -> Dictionary:
	if not valid_command(tool, args) or not world.assets.exists(actor) or key.is_empty(): return _error("invalid_repair")
	var intent := {"actor": actor, "tool": tool, "arguments": args.duplicate(true)}
	if receipts.has(key): return receipts[key].result.duplicate(true) if receipts[key].intent == intent else _error("idempotency_conflict")
	if route_open() or args.event_id != event.id: return _error("repair_event_closed")
	var body: Node3D = world.actor(actor)
	if body == null or Vector2(body.position.x, body.position.z).distance_to(Vector2(SITE.x, SITE.z)) > 2.5: return _error("repair_requires_arrival")
	if int(args.labor_minutes) > 0 and world.work.occupied(actor): return _error("repair_worker_busy")
	var debit := {}
	for item in args.materials:
		if int(event.materials[item]) + int(args.materials[item]) > int(REPAIR[item]): return _error("repair_material_quota")
		debit[item] = -int(args.materials[item])
	if not world.assets.apply(actor, debit, 0): return _error("repair_materials_missing")
	for item in args.materials: event.materials[item] = int(event.materials[item]) + int(args.materials[item])
	repairs[key] = {"id": key, "event_id": event.id, "actor": actor, "materials": args.materials.duplicate(true), "requested": int(args.labor_minutes), "worked": 0, "last_minute": world.minute(), "status": "working" if int(args.labor_minutes) > 0 else "completed", "paid": 0}
	var result := {"ok": true, "message": "材料已投入；工时仅在修复点实际停留时累计，离开或恢复通路后停止。"}
	receipts[key] = {"intent": intent, "result": result}
	_check_repaired()
	return result

func busy(actor: String) -> bool:
	return repairs.values().any(func(r): return r.actor == actor and r.status == "working")

func _advance_repairs(now: int) -> void:
	for r in repairs.values():
		if r.status != "working": continue
		var elapsed := maxi(0, now - int(r.last_minute)); r.last_minute = now
		if route_open() or r.event_id != event.id: r.status = "stopped"; continue
		var body: Node3D = world.actor(r.actor)
		if body == null or Vector2(body.position.x, body.position.z).distance_to(Vector2(SITE.x, SITE.z)) > 2.5: continue
		var count := mini(elapsed, mini(int(r.requested) - int(r.worked), 60 - int(event.labor)))
		r.worked = int(r.worked) + count; event.labor = int(event.labor) + count
		if int(r.worked) >= int(r.requested) or int(event.labor) >= 60:
			r.status = "completed"
			var fund: Dictionary = public_funding.get(r.event_id, {})
			var wage := int(r.worked)
			if not fund.is_empty() and int(fund.escrow) >= wage and world.assets.apply(r.actor, {}, wage): fund.escrow = int(fund.escrow) - wage; fund.paid = int(fund.paid) + wage; r.paid = wage
	_check_repaired()

func _check_repaired() -> void:
	if not route_open() and int(event.labor) >= 60 and REPAIR.keys().all(func(item): return int(event.materials[item]) >= int(REPAIR[item])): _recover("materials_and_labor")

func _recover(cause: String) -> void:
	event.status = "recovered"; event.recovered = last_minute; event.resolution = cause

func fund_repair(actor: String, key: String) -> Dictionary:
	if actor != "village_public" or route_open() or public_funding.has(event.id): return _error("public_repair_unavailable")
	if world.public_plans.budget().daily_remaining < 260 or not world.assets.can_apply(actor, {}, -260): return _error("public_budget_insufficient")
	# Materials use the existing funded procurement board and actual delivery receipts.
	var ids := []
	for item in REPAIR:
		var quantity := int(REPAIR[item]) - int(event.materials[item])
		if quantity <= 0: continue
		var id := "repair-" + str(event.id) + "-" + str(item)
		world.board.demand(id, actor, item, quantity)
		var result: Dictionary = world.board.publish(actor, id, {"demand_id": id, "item_id": item, "quantity": quantity, "unit_reward": 20, "kind": "purchase", "deadline_minutes": maxi(60, int(event.natural_recovery) - world.minute()), "max_claims": 4})
		if not result.ok:
			for prior in ids: world.board.cancel(actor, prior)
			return result
		ids.append(id)
	if not world.assets.apply(actor, {}, -60):
		for prior in ids: world.board.cancel(actor, prior)
		return _error("public_labor_budget_missing")
	public_funding[event.id] = {"key": key, "created": world.minute(), "commissions": ids, "escrow": 60, "paid": 0, "refunded": 0, "materials": {}, "status": "active"}
	return {"ok": true, "message": "公共修复已托管采购款和60金币工时补贴；实际交料、劳动才兑现。"}

func _advance_public() -> void:
	for id in public_funding:
		var f: Dictionary = public_funding[id]
		if f.status != "active": continue
		if route_open() or id != event.id:
			for cid in f.commissions: world.board.cancel("village_public", cid)
			if world.assets.apply("village_public", {}, int(f.escrow)): f.refunded = int(f.escrow); f.escrow = 0; f.status = "closed"
			continue
		for cid in f.commissions:
			var c: Dictionary = world.board.commissions[cid]
			var item: String = c.terms.item_id
			var count := mini(int(c.delivered) - int(f.materials.get(item, 0)), int(REPAIR[item]) - int(event.materials[item]))
			if count > 0 and world.assets.apply("village_public", {item: -count}, 0): f.materials[item] = int(f.materials.get(item, 0)) + count; event.materials[item] = int(event.materials[item]) + count
	_check_repaired()

func public_cost_today() -> int:
	var total := 0
	for f in public_funding.values():
		if int(f.created) / 1080 != world.minute() / 1080: continue
		total += int(f.escrow) + int(f.paid)
		for id in f.commissions:
			var c: Dictionary = world.board.commissions.get(id, {})
			total += int(c.get("escrow", 0)) + int(c.get("delivered", 0)) * 20
	return total

func context() -> Dictionary:
	return {"weather": "rain" if raining() else "clear", "forecast": ensure_day(world.minute() / 1080 + 1).duplicate(true), "route": event.duplicate(true), "route_open": route_open(), "repair_site": {"x": SITE.x, "z": SITE.z}, "required_materials": REPAIR, "required_labor": 60, "transports": transports.values().map(func(t): return {"id": t.id, "item_id": t.item_id, "quantity": t.quantity, "arrival": t.arrival, "status": t.status}), "rules": "Forecast is a prediction with issue time, not an observed fact. The off-map caravan has finite stock and 24 units/day capacity. Blocked routes pause delivery; natural drainage restores after 1080 minutes. Local paths and signed local work remain valid. Repair needs actual materials plus 60 minutes at repair_site; subsidies require existing public funding and actual work, once per receipt. Market prices use actual arrivals, no extra weather multiplier."}

func to_dict() -> Dictionary:
	return {"version": 1, "seed": seed, "last_minute": last_minute, "days": days.duplicate(true), "warehouse": warehouse.duplicate(true), "transports": transports.duplicate(true), "event": event.duplicate(true), "repairs": repairs.duplicate(true), "receipts": receipts.duplicate(true), "public_funding": public_funding.duplicate(true), "watered": watered.duplicate(true)}

func restore(v: Dictionary) -> void:
	_rain_scan_minute = -1
	if v.is_empty():
		seed = 93; last_minute = world.minute(); days = {}; warehouse = ORIGIN.duplicate(true); transports = {}; event = {}; repairs = {}; receipts = {}; public_funding = {}; watered = {}; return
	seed = int(v.seed); last_minute = int(v.last_minute)
	days = v.days.duplicate(true); warehouse = v.warehouse.duplicate(true); transports = v.transports.duplicate(true); event = v.event.duplicate(true); repairs = v.repairs.duplicate(true); receipts = v.receipts.duplicate(true); public_funding = v.public_funding.duplicate(true); watered = v.watered.duplicate(true)

func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != 11 or v.get("version") != 1 or not Rules._count(v.get("seed"), 1, 2147483647) or not Rules._count(v.get("last_minute"), 0, 9007199254740991): return false
	for field in ["days", "warehouse", "transports", "event", "repairs", "receipts", "public_funding", "watered"]:
		if not v.get(field) is Dictionary: return false
	var used := {}
	for t in v.transports.values():
		if not t is Dictionary or not ORIGIN.has(t.get("item_id")) or not Rules._id(t.get("owner")) or t.get("status") not in ["transit", "arrived"]: return false
		for field in ["quantity", "cost", "departure", "arrival", "delayed"]:
			if not Rules._count(t.get(field), 0, 9007199254740991): return false
		if int(t.quantity) not in range(1, 25) or int(t.arrival) < int(t.departure) + 180 + int(t.delayed): return false
		if t.status == "arrived" and (not Rules._count(t.get("received"), int(t.arrival), int(v.last_minute)) or not Rules._count(t.get("proceeds"), 0, 9007199254740991)): return false
		used[t.item_id] = int(used.get(t.item_id, 0)) + int(t.quantity)
	for item in ORIGIN:
		if not Rules._count(v.warehouse.get(item), 0, ORIGIN[item]) or int(v.warehouse[item]) + int(used.get(item, 0)) != int(ORIGIN[item]): return false
	for d in v.days.values():
		if not d is Dictionary or not Rules._count(d.get("day"), 0, 9007199254740991) or d.get("rain") != (absi(hash("weather:%d:%d" % [v.seed, d.day])) % 4 == 0) or d.get("start") != int(d.day) * 1080 + 180 or d.get("end") != int(d.day) * 1080 + 660 or d.get("kind") != "forecast": return false
	if not v.event.is_empty():
		if v.event.get("status") not in ["blocked", "recovered"] or not v.event.get("materials") is Dictionary or not Rules._count(v.event.get("labor"), 0, 60) or not Rules._count(v.event.get("started"), 0, 9007199254740991) or v.event.get("natural_recovery") != int(v.event.started) + 1080: return false
		for item in REPAIR:
			if not Rules._count(v.event.materials.get(item), 0, REPAIR[item]): return false
	for r in v.repairs.values():
		if not r is Dictionary or not v.receipts.has(r.get("id")) or not Rules._id(r.get("actor")) or r.get("status") not in ["working", "completed", "stopped"] or not Rules._count(r.get("requested"), 0, 60) or not Rules._count(r.get("worked"), 0, int(r.requested)) or not Rules._count(r.get("paid"), 0, int(r.worked)) or not Rules._count(r.get("last_minute"), 0, int(v.last_minute)): return false
		var receipt: Dictionary = v.receipts[r.id]
		if not receipt.get("intent") is Dictionary or receipt.get("result", {}).get("ok") != true: return false
		var intent: Dictionary = receipt.intent
		if intent.get("actor") != r.actor or not intent.get("arguments") is Dictionary or not valid_command(str(intent.get("tool", "")), intent.arguments): return false
		if intent.arguments.event_id != r.get("event_id") or intent.arguments.materials != r.get("materials") or intent.arguments.labor_minutes != r.requested: return false
		if int(r.paid) > 0 and not v.public_funding.has(r.event_id): return false
	for f in v.public_funding.values():
		if not f is Dictionary or not f.get("commissions") is Array or f.get("status") not in ["active", "closed"]: return false
		for field in ["created", "escrow", "paid", "refunded"]:
			if not Rules._count(f.get(field), 0, 9007199254740991): return false
		if int(f.escrow) + int(f.paid) + int(f.refunded) != 60: return false
	for id in v.public_funding:
		var paid := 0
		for r in v.repairs.values():
			if r.event_id == id: paid += int(r.paid)
		if paid != int(v.public_funding[id].paid): return false
	if not v.event.is_empty():
		var materials: Dictionary = v.public_funding.get(v.event.id, {}).get("materials", {}).duplicate(true)
		var labor := 0
		for r in v.repairs.values():
			if r.event_id != v.event.id: continue
			labor += int(r.worked)
			for item in r.materials: materials[item] = int(materials.get(item, 0)) + int(r.materials[item])
		if labor != int(v.event.labor): return false
		for item in REPAIR:
			if int(materials.get(item, 0)) != int(v.event.materials[item]): return false
	return true

static func _error(code: String) -> Dictionary: return {"ok": false, "error": code}
