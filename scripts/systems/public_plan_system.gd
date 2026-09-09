extends RefCounted

const Actor := "village_public"
const Project = preload("res://scripts/systems/npc_project_system.gd")
const Context = preload("res://scripts/ai_agent/game_env_context.gd")
var world: Node
var plans: Dictionary = {}
var receipts: Dictionary = {}
var distributions: Dictionary = {}
var revision := 1
var mode := "execute"
var last_review := -1080
var last_plan := -180
var funding_source := "existing_public_account"
var opening_balance := 0
var registry := preload("res://scripts/ai_agent/agent_registry.gd").new()
var scheduler := preload("res://scripts/ai_agent/agent_scheduler.gd").new()
var validator: RefCounted
var observations: Array = []
var requests: Dictionary = {}
var _bound := false
var _sequence := 0
var _last_gap := 0
var _busy := false

func configure(owner: Node) -> void:
	world = owner
	registry.load_public_coordinator()
	validator = load("res://scripts/ai_agent/agent_action_validator.gd").new()
	opening_balance = int(world.session.npc_economy.get_npc_state(Actor).gold)

func bind_runtime() -> void:
	if _bound or world.session.agent_runtime == null: return
	_bound = true
	scheduler.configure(registry, world.session.agent_runtime.gateway, _request, _response, _stream, _failed)

func indicators() -> Dictionary:
	var gap := 0
	var no_food := 0
	for resident in world.society.residents.values():
		var items: Dictionary = world.assets.available_items(resident.id)
		var stock := 0
		for food in world.society.config.food_preferences: stock += int(items.get(food, 0))
		if stock > 0: continue
		no_food += 1
		var can_purchase := false
		for food in world.society.config.food_preferences:
			if world.session.market.can_buy(food, 1) and world.assets.can_apply(resident.id, {}, -int(world.session.npc_economy.quote_agent_buy(food, 1))): can_purchase = true
		if not can_purchase: gap += 1
	var incoming := 0
	var best_reward := 0
	for c in world.board.commissions.values():
		if c.status == "open" and c.terms.item_id == "bread": best_reward = maxi(best_reward, int(c.terms.unit_reward))
		if c.status == "open" and c.actor_id == Actor and c.terms.item_id in world.society.config.food_preferences: incoming += int(c.claimed)
	return {"bread_market_sell_one": world.session.market.quote_sell("bread", 1), "bread_market_buy_one": world.session.market.quote_buy("bread", 1), "highest_open_bread_reward": best_reward, "population": world.society.residents.size(), "without_food": no_food, "urgent_food_gap": gap, "funded_claimed_incoming": incoming, "public_bread_stock": int(world.assets.available_items(Actor).get("bread", 0)), "cooldown_remaining": maxi(0, last_plan + 180 - world.minute())}

func budget() -> Dictionary:
	var committed := 0
	var spent := 0
	var today := 0
	if world.environment != null: today += world.environment.public_cost_today()
	if world.social != null: today += world.social.public_cost_today()
	for p in plans.values():
		var c: Dictionary = world.board.commissions.get(p.commission_id, {})
		committed += int(c.get("escrow", 0))
		spent += int(c.get("delivered", 0)) * int(p.unit_reward)
		if int(p.created) / 1080 == world.minute() / 1080: today += int(c.get("escrow", 0)) + int(c.get("delivered", 0)) * int(p.unit_reward)
	return {"category": "basic_food", "source": funding_source, "opening_balance": opening_balance, "available": int(world.session.npc_economy.get_npc_state(Actor).gold), "committed": committed, "spent": spent, "daily_limit": 800, "daily_remaining": maxi(0, 800 - today)}

func public_plans() -> Array:
	var result := []
	for p in plans.values():
		var c: Dictionary = world.board.commissions.get(p.commission_id, {})
		result.append({"id": p.id, "reason": p.reason, "status": p.status, "quantity": p.quantity, "received": c.get("delivered", 0), "distributed": p.distributed, "escrow": c.get("escrow", 0), "commission_id": p.commission_id})
	return result.slice(-12)

static func valid_command(tool: String, a: Dictionary) -> bool:
	if not Project._count(a.get("expected_version"), 1, 1000000000) or not Project._id(a.get("reason")): return false
	if tool == "public_activity_plan": return a.size() == 3 and preload("res://scripts/systems/social_activity_system.gd").valid_terms(a.get("terms"))
	if tool in ["public_wait", "public_repair_plan"]: return a.size() == 2
	return tool == "public_food_plan" and a.size() == 5 and Project._count(a.get("quantity"), 1, 12) and Project._count(a.get("unit_reward"), 1, 200) and Project._count(a.get("deadline_minutes"), 60, 1080)

func command(actor: String, tool: String, a: Dictionary, key: String) -> Dictionary:
	if actor != Actor or not valid_command(tool, a): return _error("public_permission_denied")
	var intent := {"tool": tool, "arguments": a.duplicate(true)}
	if receipts.has(key): return {"ok": receipts[key].intent == intent, "duplicate": true}
	if _busy or world.get_tree().paused: return _error("world_paused_or_busy")
	if int(a.expected_version) != revision: return _error("public_plan_changed")
	if mode == "observe":
		observations.append(intent)
		return {"ok": true, "observed": true, "message": "观察模式：仅记录建议，未发布或支出。"}
	if tool == "public_wait":
		last_review = world.minute()
		receipts[key] = {"intent": intent, "minute": world.minute()}
		revision += 1
		return {"ok": true, "message": "公共协调者选择等待，未支出。"}
	if tool == "public_repair_plan":
		if world.minute() - last_plan < 180: return _error("public_cooldown")
		var result: Dictionary = world.environment.fund_repair(actor, key)
		if result.ok:
			receipts[key] = {"intent": intent, "minute": world.minute()}
			last_plan = world.minute(); last_review = world.minute(); revision += 1
		return result
	if tool == "public_activity_plan":
		if world.minute() - last_plan < 180: return _error("public_cooldown")
		var result: Dictionary = world.social.propose(actor, "public-event-" + key.sha256_text().substr(0, 20), a.terms)
		if result.ok:
			receipts[key] = {"intent": intent, "minute": world.minute()}
			last_plan = world.minute(); last_review = world.minute(); revision += 1
		return result
	var info := indicators()
	if int(info.cooldown_remaining) > 0: return _error("public_cooldown")
	if int(info.urgent_food_gap) <= int(info.funded_claimed_incoming) + int(info.public_bread_stock): return _error("supply_already_arranged")
	for p in plans.values():
		if world.board.commissions.get(p.commission_id, {}).get("status") == "open": return _error("existing_public_plan")
	if int(a.quantity) > int(info.urgent_food_gap) - int(info.funded_claimed_incoming): return _error("excess_public_purchase")
	var cost := int(a.quantity) * int(a.unit_reward)
	var funds := budget()
	if cost > int(funds.available) or cost > int(funds.daily_remaining): return _error("public_budget_insufficient")
	var id := "public-" + key.sha256_text().substr(0, 24)
	var terms := {"demand_id": id, "item_id": "bread", "quantity": int(a.quantity), "unit_reward": int(a.unit_reward), "kind": "purchase", "deadline_minutes": int(a.deadline_minutes), "max_claims": 3}
	_busy = true
	if not world.board.demand(id, Actor, "bread", int(a.quantity)):
		_busy = false
		return _error("public_demand_failed")
	var result: Dictionary = world.board.publish(Actor, id, terms)
	if not result.ok:
		world.board.demands.erase(id)
		_busy = false
		return result
	plans[id] = {"id": id, "commission_id": id, "created": world.minute(), "quantity": int(a.quantity), "unit_reward": int(a.unit_reward), "reason": a.reason, "status": "procurement", "distributed": 0}
	receipts[key] = {"intent": intent, "minute": world.minute(), "plan_id": id}
	last_plan = world.minute()
	last_review = world.minute()
	revision += 1
	_busy = false
	return {"ok": true, "plan_id": id, "message": "公共食品采购已托管并发布；居民可自主决定是否接单。"}

func advance() -> void:
	if _busy or world.get_tree().paused: return
	bind_runtime()
	_distribute()
	if world.session.agent_runtime == null or not world.session.agent_runtime.service_enabled: return
	var gap := int(indicators().urgent_food_gap)
	if world.minute() - last_review >= 180 and gap > _last_gap:
		scheduler.notify_event(Actor, 2, world.minute())
	_last_gap = gap
	scheduler.advance_to(world.minute())

func _distribute() -> void:
	for p in plans.values():
		var c: Dictionary = world.board.commissions.get(p.commission_id, {})
		var amount := int(c.get("delivered", 0)) - int(p.distributed)
		for resident in world.society.residents.values():
			if amount <= 0: break
			var key := "%s:%d" % [resident.id, world.minute() / 1080]
			if distributions.has(key): continue
			var stock: Dictionary = world.assets.available_items(resident.id)
			if world.society.config.food_preferences.any(func(food): return int(stock.get(food, 0)) > 0): continue
			if not world.assets.can_apply(resident.id, {"bread": 1}, 0) or not world.assets.can_apply(Actor, {"bread": -1}, 0): continue
			var before: Dictionary = world.assets.snapshot(Actor)
			if not world.assets.apply(Actor, {"bread": -1}, 0): continue
			if not world.assets.apply(resident.id, {"bread": 1}, 0):
				world.assets.restore(Actor, before)
				continue
			p.distributed = int(p.distributed) + 1
			amount -= 1
			distributions[key] = {"plan_id": p.id, "actor_id": resident.id, "minute": world.minute(), "item_id": "bread", "quantity": 1}
			revision += 1
		p.status = "procurement" if c.get("status") == "open" else ("stocked" if amount > 0 else ("completed" if int(p.distributed) > 0 else "expired"))

func _request(_actor: String, trigger: String, _minute: int, _dialogue: String) -> Dictionary:
	if world.get_tree().paused or world.minute() - last_review < 180: return {}
	_sequence += 1
	var id := "public-%s-%d" % [world.session.agent_runtime._request_namespace, _sequence]
	var request := Context.build(self, id, trigger)
	requests[id] = {"minute": world.minute(), "revision": revision, "epoch": world.session.agent_runtime.gateway.session_epoch, "mode": mode}
	return request

func _response(actor: String, response: Dictionary) -> void:
	var id := str(response.get("request_id", ""))
	var request: Dictionary = requests.get(id, {})
	requests.erase(id)
	if request.is_empty() or request.epoch != world.session.agent_runtime.gateway.session_epoch or request.revision != revision or request.mode != mode or response.get("expected_revision") != request.revision or world.minute() - int(request.minute) > 60 or world.get_tree().paused:
		observations.append({"error": "public_response_expired"})
		return
	var checked: Dictionary = validator.validate(response, registry, revision)
	if not checked.ok or response.agent_id != Actor or response.actions.size() > 1:
		observations.append({"error": "public_response_invalid"})
		return
	last_review = world.minute()
	for a in checked.value.actions:
		var result := command(actor, a.tool_name, a.arguments, a.idempotency_key)
		observations.append(result)
		world.session.agent_runtime.gateway.report_outcome(Actor, world.session.agent_runtime.session_id, {"protocol_version": 2, "decision_id": response.decision_id, "action_id": a.action_id, "idempotency_key": a.idempotency_key, "status": "completed" if result.ok else "failed", "failure_code": result.get("error", ""), "committed_revision": revision, "changed_entities": ["public_plans"] if result.ok and mode == "execute" else [], "resource_delta": {}, "hud_message": result.get("message", ""), "game_minute": world.minute()})

func _stream(_actor: String, event: Dictionary) -> void:
	world.session.agent_runtime.session_trace.accept_event(event)

func _failed(_actor: String, id: String, error: String) -> void:
	requests.erase(id)
	last_review = world.minute()
	observations.append({"error": error, "message": "保留已签公共订单，暂缓新规划。"})

func set_mode(value: String) -> void:
	if value not in ["observe", "execute"] or value == mode: return
	mode = value
	revision += 1
	requests.clear()
	last_review = -1080

func to_dict() -> Dictionary:
	return {"version": 1, "plans": plans.duplicate(true), "receipts": receipts.duplicate(true), "distributions": distributions.duplicate(true), "revision": revision, "mode": mode, "last_review": last_review, "last_plan": last_plan, "funding_source": funding_source, "opening_balance": opening_balance}

func validate(v: Variant, board_data: Dictionary) -> bool:
	if not v is Dictionary or v.size() != 10 or v.get("version") != 1 or v.get("mode") not in ["observe", "execute"] or v.get("funding_source") != "existing_public_account": return false
	if not Project._count(v.get("revision"), 1, 1000000000) or not Project._count(v.get("opening_balance"), 0, 1000000000) or not Project._count(v.get("last_review"), -1080, 9007199254740991) or not Project._count(v.get("last_plan"), -180, 9007199254740991): return false
	if not v.get("plans") is Dictionary or not v.get("receipts") is Dictionary or not v.get("distributions") is Dictionary: return false
	var publications := {}
	for key in v.receipts:
		var record: Variant = v.receipts[key]
		if not Project._id(key) or not record is Dictionary or not record.get("intent") is Dictionary or not record.intent.get("tool") is String or not record.intent.get("arguments") is Dictionary or not valid_command(record.intent.tool, record.intent.arguments) or not Project._count(record.get("minute"), 0, 9007199254740991): return false
		if record.intent.tool == "public_food_plan":
			var plan_id := str(record.get("plan_id", ""))
			if not v.plans.has(plan_id) or publications.has(plan_id): return false
			var plan: Dictionary = v.plans[plan_id]
			var a: Dictionary = record.intent.arguments
			if plan.get("quantity") != a.quantity or plan.get("unit_reward") != a.unit_reward or plan.get("created") != record.minute: return false
			publications[plan_id] = true
	var used := {}
	for key in v.distributions:
		var d: Variant = v.distributions[key]
		if not d is Dictionary or not v.plans.has(d.get("plan_id")) or not world.society.residents.has(d.get("actor_id")) or d.get("item_id") != "bread" or d.get("quantity") != 1 or not Project._count(d.get("minute"), 0, 9007199254740991): return false
		if key != "%s:%d" % [d.actor_id, int(d.minute) / 1080]: return false
		used[d.plan_id] = int(used.get(d.plan_id, 0)) + 1
	var daily_usage := {}
	for id in v.plans:
		var p: Variant = v.plans[id]
		if not p is Dictionary or p.get("id") != id or p.get("commission_id") != id or not p.get("reason") is String or p.get("status") not in ["procurement", "stocked", "completed", "expired"] or not Project._count(p.get("created"), 0, 9007199254740991): return false
		if not publications.has(id) or not Project._count(p.get("quantity"), 1, 12) or not Project._count(p.get("unit_reward"), 1, 200): return false
		var c: Dictionary = board_data.commissions.get(id, {})
		if c.get("actor_id") != Actor or c.get("terms", {}).get("item_id") != "bread" or c.terms.get("kind") != "purchase" or c.terms.get("quantity") != p.get("quantity") or c.terms.get("unit_reward") != p.get("unit_reward"): return false
		if not Project._count(p.get("distributed"), 0, int(c.delivered)) or int(p.distributed) != int(used.get(id, 0)): return false
		var day := int(p.created) / 1080
		daily_usage[day] = int(daily_usage.get(day, 0)) + int(c.escrow) + int(c.delivered) * int(p.unit_reward)
		if int(daily_usage[day]) > 800: return false
	return true

func restore(v: Dictionary) -> void:
	plans = v.get("plans", {}).duplicate(true)
	receipts = v.get("receipts", {}).duplicate(true)
	distributions = v.get("distributions", {}).duplicate(true)
	revision = int(v.get("revision", 1))
	mode = str(v.get("mode", "execute"))
	last_review = int(v.get("last_review", -1080))
	last_plan = int(v.get("last_plan", -180))
	opening_balance = int(v.get("opening_balance", world.session.npc_economy.get_npc_state(Actor).gold))
	requests.clear()
	scheduler._in_flight.clear()
	scheduler._pending.clear()
	scheduler._last_dispatched.clear()

func summary() -> String:
	var funds := budget()
	var info := indicators()
	var lines: Array[String] = ["村庄公共事务 · %s" % ("观察模式" if mode == "observe" else "执行模式"), "基础食品预算：可用 %d · 已承诺 %d · 已支出 %d 金币" % [funds.available, funds.committed, funds.spent], "资金来源：原公共账户；每日支出上限 800，无自动补款。", "急需食物 %d 人 · 已接补货 %d 份 · 公共面包 %d 份" % [info.urgent_food_gap, info.funded_claimed_incoming, info.public_bread_stock]]
	if not receipts.is_empty(): lines.append("最近公共决定：" + str(receipts.values()[-1].intent.arguments.reason))
	for p in public_plans(): lines.append("面包采购 · %s · 需求 %d / 收货 %d / 发放 %d\n%s" % [ {"procurement": "采购中", "stocked": "已入库，按需求发放", "completed": "已完成发放", "expired": "未成交，已结束"}.get(p.status, p.status), p.quantity, p.received, p.distributed, p.reason])
	return "\n".join(lines)

static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
