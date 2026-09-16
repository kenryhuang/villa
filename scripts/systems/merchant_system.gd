extends RefCounted

const Data = preload("res://scripts/core/game_data.gd")
const Protocol = preload("res://scripts/ai_agent/agent_protocol.gd")
const ACTOR := "village_market"
const CORE := ["grain_seed", "carrot_seed", "potato_seed"]
const EXPORTS := ["grain", "carrot", "potato"]
const LIMIT := 9007199254740991
var world: Node
var market: Node
var _seed_alerts: Dictionary = {}

static func initial(items: Dictionary, minute: int) -> Dictionary:
	var basis := {}
	var supplier := {}
	for id in items:
		basis[id] = int(items[id].stock) * int(items[id].base_price)
		if Data.get_item(id).get("category") == "seed": supplier[id] = int(items[id].target_stock) * 2
	return {"version": 1, "cash": 10000, "seed_reserve": 2000, "opening_capital": 10000,
		"local_net": 0, "external_net": 0, "asset_net": 0, "cost_basis": basis,
		"supplier": supplier, "shipments": {}, "requests": {}, "receipts": {}, "procurements": {},
		"sales": {}, "shortages": {}, "ledger": [], "sequence": 0,
		"minute": minute, "last_check": minute - 60, "quota_day": minute / 1080,
		"freight_used": 0, "export_used": 0, "enabled": true}

static func integer(v: Variant, low := 0, high := LIMIT) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v)) and float(v) == floor(float(v)) and v >= low and v <= high

static func valid(v: Variant, items: Dictionary) -> bool:
	if not v is Dictionary or v.size() != 23 or v.get("version") != 1 or not v.get("enabled") is bool: return false
	for k in ["cash", "seed_reserve", "opening_capital", "sequence", "minute", "quota_day", "freight_used", "export_used"]:
		if not integer(v.get(k)): return false
	for k in ["local_net", "external_net", "asset_net", "last_check"]:
		if not integer(v.get(k), -LIMIT): return false
	if v.cash != v.opening_capital + v.local_net + v.external_net + v.asset_net: return false
	for k in ["cost_basis", "supplier", "shipments", "requests", "receipts", "procurements", "sales", "shortages"]:
		if not v.get(k) is Dictionary: return false
	for k in ["cost_basis", "supplier", "sales"]:
		for id in v[k]:
			if not items.has(id) or not integer(v[k][id]): return false
	if not v.ledger is Array or v.ledger.size() > 256: return false
	for row in v.ledger:
		if not row is Dictionary or not integer(row.get("sequence"), 1) or not integer(row.get("minute")) or not row.get("kind") is String or not row.get("details") is Dictionary: return false
	for key in v.shipments:
		var s: Variant = v.shipments[key]
		if not s is Dictionary or s.get("id") != key or s.get("direction") not in ["import", "export"] or s.get("status") not in ["transit", "arrived"] or not items.has(s.get("item_id")): return false
		for field in ["quantity", "amount", "cost_basis", "departure", "arrival", "delayed"]:
			if not integer(s.get(field)): return false
		if s.quantity < 1 or s.arrival < s.departure: return false
	for key in v.requests:
		var r: Variant = v.requests[key]
		if not r is Dictionary or not r.get("actor") is String or not items.has(r.get("item_id")) or not integer(r.get("quantity"), 1, 100) or not integer(r.get("expires")): return false
	for key in v.receipts:
		var r: Variant = v.receipts[key]
		if not r is Dictionary or not r.get("intent") is Dictionary or not r.get("result") is Dictionary: return false
	for id in v.procurements:
		if not items.has(id) or not v.procurements[id] is Dictionary or not v.procurements[id].get("id") is String or not integer(v.procurements[id].get("opened")): return false
	for id in v.shortages:
		if not items.has(id) or not v.shortages[id] is String: return false
	return true

static func core_item(id: String) -> bool:
	return id in CORE

static func record(m: Dictionary, kind: String, details: Dictionary) -> void:
	m.sequence = int(m.sequence) + 1
	m.ledger.append({"sequence": m.sequence, "minute": m.minute, "kind": kind, "details": details.duplicate(true)})
	while m.ledger.size() > 256: m.ledger.pop_front()

static func sale_limit(m: Dictionary, state: Dictionary, quantity: int, total: int) -> String:
	var cash := int(m.cash) - (0 if core_item(state.item_id) else int(m.seed_reserve))
	if total > cash: return "merchant_insufficient_cash"
	if int(state.stock) + quantity > int(state.target_stock) * 2: return "merchant_stock_limit"
	return ""

static func local_trade(m: Dictionary, state: Dictionary, quantity: int, total: int, buying: bool) -> void:
	var delta := total if buying else -total
	m.cash = int(m.cash) + delta
	m.local_net = int(m.local_net) + delta
	var id: String = state.item_id
	if buying:
		var old_stock := int(state.stock)
		m.cost_basis[id] = maxi(0, int(m.cost_basis.get(id, 0)) - ceili(float(m.cost_basis.get(id, 0)) * quantity / maxi(1, old_stock)))
		m.sales[id] = int(m.sales.get(id, 0)) + quantity
	else: m.cost_basis[id] = int(m.cost_basis.get(id, 0)) + total
	record(m, "local_sale" if buying else "local_purchase", {"item_id": id, "quantity": quantity, "gold": delta})

func configure(owner: Node) -> void:
	world = owner
	market = world.session.market
	market.enable_merchant(world.minute())
	# Old paid transports remain owned by their original importer. Only new dispatch changes.
	world.session.npc_economy.import_dispatcher = func(_a, _i, _q, _c, _d): return false

func _emit(kind: String, details: Dictionary) -> void:
	var m: Dictionary = market.merchant
	record(m, kind, details)
	var runtime: Node = world.session.agent_runtime
	if runtime == null: return
	for actor in runtime.registry.get_agent_ids():
		var resources = world.session.npc_economy.get_npc_state(actor)
		var id := str(details.get("item_id", ""))
		var interested := resources != null and (int(resources.reserve_targets.get(id, 0)) > 0 or int(resources.inventory.get(id, 0)) > 0)
		for r in m.requests.values():
			if r.actor == actor and r.item_id == id and int(r.expires) > int(m.minute): interested = true
		if interested:
			runtime.loop_state.record(actor, {"event_id": "merchant:%d" % m.sequence, "kind": kind, "game_minute": m.minute, "payload": details.duplicate(true)})
			if kind in ["ImportArrived", "LocalProcurementOpened"]: runtime.scheduler.notify_event(actor, 2, int(m.minute))

func request_supply(actor: String, args: Dictionary, key: String) -> Dictionary:
	if not world.assets.exists(actor) or not valid_request(args) or not market._items.has(args.item_id): return {"ok": false, "error": "invalid_supply_request"}
	var m: Dictionary = market.merchant
	var intent := {"actor": actor, "arguments": args.duplicate(true)}
	if m.receipts.has(key): return m.receipts[key].result.duplicate(true) if m.receipts[key].intent == intent else {"ok": false, "error": "idempotency_conflict"}
	if m.receipts.size() >= 4096: return {"ok": false, "error": "request_history_full"}
	m.requests[actor + ":" + str(args.item_id)] = {"actor": actor, "item_id": args.item_id, "quantity": args.quantity, "expires": world.minute() + 1080}
	var result := {"ok": true, "message": "补货需求已登记，未扣款、未成交；商行会核对货源和资金，实际到货请查询市场。"}
	m.receipts[key] = {"intent": intent, "result": result.duplicate(true)}
	_emit("MarketSupplyRequested", {"item_id": args.item_id, "quantity": args.quantity, "actor": actor})
	return result

static func valid_request(a: Dictionary) -> bool:
	return a.size() == 2 and a.get("item_id") is String and a.item_id.length() in range(1, 81) and integer(a.get("quantity"), 1, 100)

func incoming(id: String) -> int:
	var count := 0
	for s in world.environment.transports.values():
		if s.item_id == id and s.status == "transit": count += int(s.quantity)
	for s in market.merchant.shipments.values():
		if s.direction == "import" and s.item_id == id and s.status == "transit": count += int(s.quantity)
	var p: Dictionary = market.merchant.procurements.get(id, {})
	var c: Dictionary = world.board.commissions.get(p.get("id", ""), {})
	if c.get("status") == "open": count += int(c.claimed)
	return count

func supply_view(id: String) -> Dictionary:
	if not market._items.has(id): return {"error": "unknown_item"}
	var m: Dictionary = market.merchant
	var p: Dictionary = m.procurements.get(id, {})
	var c: Dictionary = world.board.commissions.get(p.get("id", ""), {})
	return {"item_id": id, "incoming": incoming(id), "reason": m.shortages.get(id, ""),
		"target": target(id), "supplier_stock": m.supplier.get(id, world.environment.warehouse.get(id, 0)),
		"shipments": m.shipments.values().filter(func(s): return s.item_id == id and s.status == "transit"),
		"procurement": c.duplicate(true) if c.get("status") == "open" else {},
		"rule": "需求登记不等于订单。现货买卖需双方资产；在途不可购买；可承接商行种子委托或出售自己的物品。基础作物可在风车选种，每个作物产2份种子。"}

func target(id: String) -> int:
	var state: Dictionary = market._items[id]
	var requested := 0
	for r in market.merchant.requests.values():
		if r.item_id == id and int(r.expires) > world.minute(): requested += int(r.quantity)
	var base := mini(20, int(state.target_stock)) if id in CORE else 0
	# Growth is minute based; use recent actual sales instead of assuming one crop/day.
	var demand := int(market.merchant.sales.get(id, 0))
	return mini(int(state.target_stock) * 2, maxi(base, maxi(mini(requested, int(state.target_stock)), demand)))

func advance() -> void:
	if world.get_tree().paused or market.merchant.is_empty() or not market.merchant.enabled or not market._can_direct_mutate(): return
	var m: Dictionary = market.merchant
	var now: int = world.minute()
	var elapsed := maxi(0, now - int(m.minute))
	m.minute = now
	for s in m.shipments.values():
		if s.status != "transit": continue
		if not world.environment.route_open():
			if int(s.delayed) == 0: _emit("ShipmentDelayed", {"item_id": s.item_id, "order_id": s.id, "reason": "route_blocked"})
			s.arrival = int(s.arrival) + elapsed
			s.delayed = int(s.delayed) + elapsed
		elif now >= int(s.arrival): _arrive(s.id)
	if now - int(m.last_check) < 60: return
	m.last_check = now
	if int(m.quota_day) != now / 1080:
		var days := maxi(1, now / 1080 - int(m.quota_day))
		m.quota_day = now / 1080; m.freight_used = 0; m.export_used = 0
		for id in m.supplier:
			m.supplier[id] = mini(int(market._items[id].target_stock) * 2, int(m.supplier[id]) + days * int(market._items[id].target_stock))
		for id in m.sales: m.sales[id] = int(m.sales[id]) / 2
		_emit("ExternalSeedProduction", {"days": days})
	for key in m.requests.keys():
		if int(m.requests[key].expires) <= now: m.requests.erase(key)
	var ids: Array = CORE.duplicate()
	for id in m.supplier:
		if id not in ids: ids.append(id)
	for id in world.environment.warehouse:
		if id not in ids and market._items.has(id) and market.get_stock(id) == 0: ids.append(id)
	for id in ids: _replenish(id)
	for id in EXPORTS: _export(id)
	_review_seed_reserves()
	var finished: Array = m.shipments.keys().filter(func(id): return m.shipments[id].status == "arrived")
	for id in finished.slice(0, maxi(0, finished.size() - 64)): m.shipments.erase(id)

func _review_seed_reserves() -> void:
	var runtime: Node = world.session.agent_runtime
	if runtime == null: return
	for actor in runtime.registry.get_agent_ids():
		var state = world.session.npc_economy.get_npc_state(actor)
		if state == null: continue
		for id in CORE:
			var wanted := int(state.reserve_targets.get(id, 0))
			var held := int(state.inventory.get(id, 0))
			var key: String = str(actor) + ":" + id
			if wanted <= held: _seed_alerts.erase(key); continue
			if int(_seed_alerts.get(key, -1)) == world.minute() / 1080: continue
			_seed_alerts[key] = world.minute() / 1080
			runtime.loop_state.record(actor, {"event_id": "seed-reserve:%s:%d" % [key, world.minute() / 1080], "kind": "SeedReserveLow", "game_minute": world.minute(), "payload": {"item_id": id, "held": held, "reserve_target": wanted, "rule": "请核对下一轮播种需要。可以购买种子、登记补货，或在风车将1份对应作物选为2份种子；由你决定是否采纳，尚未消费资产。"}})
			runtime.scheduler.notify_event(actor, 2, world.minute())

func _replenish(id: String) -> void:
	var m: Dictionary = market.merchant
	var p: Dictionary = m.procurements.get(id, {})
	var c: Dictionary = world.board.commissions.get(p.get("id", ""), {})
	if c.get("status") == "open" and world.minute() - int(p.opened) >= 60:
		world.board.release_unclaimed(ACTOR, c.id)
	var deficit := maxi(0, target(id) - market.get_stock(id) - incoming(id))
	if not m.supplier.has(id): deficit = 5 if market.get_stock(id) == 0 and incoming(id) == 0 else 0
	if deficit <= 0:
		m.shortages.erase(id)
		return
	# At a stocked counter, fund a real public procurement first; a zero-stock essential imports immediately.
	if m.supplier.has(id) and market.get_stock(id) > 0 and (p.is_empty() or world.minute() - int(p.opened) >= 1080):
		var key := "market-procure:%s:%d" % [id, world.minute()]
		var qty := mini(20, deficit)
		var reward: int = market.quote_sell(id, 1)
		var budget := int(m.cash) - (0 if id in CORE else int(m.seed_reserve))
		qty = mini(qty, maxi(0, budget) / maxi(1, reward))
		if qty > 0 and world.board.demand(key, ACTOR, id, qty):
			var result: Dictionary = world.board.publish(ACTOR, key, {"demand_id": key, "item_id": id, "quantity": qty, "unit_reward": reward, "kind": "purchase", "deadline_minutes": 1080, "max_claims": 3})
			if result.ok:
				m.procurements[id] = {"id": key, "opened": world.minute()}
				_emit("LocalProcurementOpened", {"item_id": id, "commission_id": key, "quantity": qty})
				return
	elif c.get("status") == "open" and world.minute() - int(p.opened) < 60: return
	_import(id, mini(100, deficit))

func _blocked(id: String, reason: String) -> void:
	if market.merchant.shortages.get(id) != reason:
		market.merchant.shortages[id] = reason
		_emit("MarketPurchaseBlocked", {"item_id": id, "reason": reason})

func _import(id: String, requested: int) -> void:
	var m: Dictionary = market.merchant
	if not world.environment.route_open(): _blocked(id, "route_blocked"); return
	var source: Dictionary = m.supplier if m.supplier.has(id) else world.environment.warehouse
	var pack := 10 if id.ends_with("_seed") else 1
	var used := int(m.freight_used)
	for old in world.environment.transports.values():
		if int(old.departure) / 1080 == world.minute() / 1080: used += int(old.quantity)
	var quantity := mini(requested, mini(int(source.get(id, 0)), maxi(0, 24 - used) * pack))
	if quantity <= 0: _blocked(id, "supplier_empty" if int(source.get(id, 0)) == 0 else "freight_capacity"); return
	var unit := maxi(1, floori(float(market._items[id].base_price) * .55))
	var funds := maxi(0, int(m.cash) - (0 if id in CORE else int(m.seed_reserve)))
	while quantity > 0 and quantity * unit + ceili(float(quantity) / pack) > funds: quantity -= 1
	if quantity == 0: _blocked(id, "merchant_insufficient_cash"); return
	var freight := ceili(float(quantity) / pack)
	var cost := quantity * unit + freight
	m.cash = int(m.cash) - cost; m.external_net = int(m.external_net) - cost
	source[id] = int(source[id]) - quantity
	if not m.supplier.has(id):
		world.environment.merchant_withdrawals[id] = int(world.environment.merchant_withdrawals.get(id, 0)) + quantity
	m.freight_used = int(m.freight_used) + freight
	var key := "import:%d" % (int(m.sequence) + 1)
	m.shipments[key] = {"id": key, "direction": "import", "status": "transit", "item_id": id, "quantity": quantity, "amount": cost, "cost_basis": cost, "departure": world.minute(), "arrival": world.minute() + (480 if world.environment.raining() else 180), "delayed": 0}
	m.shortages.erase(id)
	_emit("ImportOrdered", {"item_id": id, "quantity": quantity, "cost": cost, "order_id": key})

func _export(id: String) -> void:
	var m: Dictionary = market.merchant
	if not market._items.has(id) or not world.environment.route_open(): return
	var safety := maxi(12, int(market._items[id].target_stock) / 2)
	var used := int(m.freight_used)
	for old in world.environment.transports.values():
		if int(old.departure) / 1080 == world.minute() / 1080: used += int(old.quantity)
	var quantity := mini(12, mini(market.get_stock(id) - safety, mini(36 - int(m.export_used), 24 - used)))
	if quantity <= 0: return
	var unit := maxi(2, roundi(float(market._items[id].base_price) * .95))
	var net := quantity * (unit - 1)
	var basis := ceili(float(m.cost_basis.get(id, 0)) * quantity / maxi(1, market.get_stock(id)))
	if net <= basis and int(m.cash) > int(m.seed_reserve) * 2: return
	m.cost_basis[id] = maxi(0, int(m.cost_basis.get(id, 0)) - basis)
	market._items[id].stock = market.get_stock(id) - quantity
	m.freight_used = int(m.freight_used) + quantity; m.export_used = int(m.export_used) + quantity
	var key := "export:%d" % (int(m.sequence) + 1)
	m.shipments[key] = {"id": key, "direction": "export", "status": "transit", "item_id": id, "quantity": quantity, "amount": net, "cost_basis": basis, "departure": world.minute(), "arrival": world.minute() + 180, "delayed": 0}
	_emit("ExportDeparted", {"item_id": id, "quantity": quantity, "order_id": key, "net_receivable": net})
	market._emit_stock_changed(id, market.get_stock(id))

func _arrive(key: String) -> void:
	var m: Dictionary = market.merchant
	var s: Dictionary = m.shipments.get(key, {})
	if s.get("status") != "transit": return
	if s.direction == "import":
		if not market._can_add_safely(market.get_stock(s.item_id), int(s.quantity)): return
		market._items[s.item_id].stock = market.get_stock(s.item_id) + int(s.quantity)
		market._items[s.item_id].supply = int(market._items[s.item_id].supply) + int(s.quantity)
		m.cost_basis[s.item_id] = int(m.cost_basis.get(s.item_id, 0)) + int(s.cost_basis)
	else:
		if int(m.cash) > LIMIT - int(s.amount): return
		m.cash = int(m.cash) + int(s.amount); m.external_net = int(m.external_net) + int(s.amount)
	s.status = "arrived"
	_emit("ImportArrived" if s.direction == "import" else "ExportSettled", {"item_id": s.item_id, "quantity": s.quantity, "amount": s.amount, "order_id": key})
	if s.direction == "import": market._emit_stock_changed(s.item_id, market.get_stock(s.item_id))
