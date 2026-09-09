extends RefCounted

## Work execution for the original agreement/dialogue system. Money and goods use
## ActorAssetAccess, production uses the existing rental queue, movement the actors.
const Rules = preload("res://scripts/systems/npc_project_system.gd")
const ACTIVE := ["queued", "pickup", "working", "delivery", "between", "refund_pending"]
const TOOLS := ["propose_work", "counter_work", "accept_work", "cancel_work", "start_learning", "start_leisure", "manage_building", "propose_joint_project", "accept_joint_project", "exit_joint_project"]
var world: Node
var contracts: Dictionary = {}
var activities: Dictionary = {}
var skills: Dictionary = {}
var receipts: Dictionary = {}
var ventures: Dictionary = {}
var _busy := false
var paths := GridPathfinder.new()

func configure(owner: Node) -> void:
	world = owner
	paths.configure(world.session.grid)
	world.session.production.building_service.output_receiver = capture_output
	world.session.production.building_service.equipment_contribution = contributes_equipment

static func valid_terms(a: Variant) -> bool:
	if not a is Dictionary or a.size() != 14: return false
	for field in ["worker_id", "recipient_id", "kind", "item_id", "building_id", "recipe_id", "parent_contract", "note"]:
		if not a.get(field) is String or a[field].length() > (300 if field == "note" else 100): return false
	return Rules._id(a.worker_id) and Rules._id(a.recipient_id) and a.kind in ["delivery", "processing", "supply"] and Rules._id(a.item_id) and Rules._count(a.get("quantity"), 1, 100) and Rules._count(a.get("wage"), 0, 100000) and Rules._count(a.get("max_fee"), 0, 100000) and Rules._count(a.get("deadline_minutes"), 30, 10080) and Rules._count(a.get("cycles"), 1, 7) and Rules._count(a.get("interval_minutes"), 0, 1080) and (a.cycles == 1 or a.interval_minutes >= 60) and (a.kind != "processing" or (Rules._id(a.building_id) and Rules._id(a.recipe_id)))

static func valid_command(tool: String, a: Dictionary) -> bool:
	match tool:
		"propose_joint_project": return valid_venture(a)
		"accept_joint_project", "exit_joint_project": return a.size() == 2 and Rules._id(a.get("venture_id")) and Rules._count(a.get("version"), 1, 1000000)
		"propose_work": return valid_terms(a)
		"counter_work": return a.size() == 3 and Rules._id(a.get("contract_id")) and Rules._count(a.get("version"), 1, 1000000) and valid_terms(a.get("terms"))
		"accept_work", "cancel_work": return a.size() == 2 and Rules._id(a.get("contract_id")) and Rules._count(a.get("version"), 1, 1000000)
		"start_learning": return a.size() == 1 and a.get("skill_id") == "ingredient_selection"
		"start_leisure": return a.size() == 2 and a.get("activity") in ["visit", "rest"] and Rules._id(a.get("partner_id"))
		"manage_building": return a.size() == 4 and Rules._id(a.get("building_id")) and a.get("operation") in ["maintain", "pricing", "open", "close"] and Rules._count(a.get("fee"), 0, 1000000) and Rules._count(a.get("version"), 1, 1000000)
	return false

func command(actor: String, tool: String, a: Dictionary, key: String) -> Dictionary:
	if key.is_empty() or not valid_command(tool, a) or not world.assets.exists(actor): return _error("invalid_work_command")
	if receipts.has(key):
		var old: Dictionary = receipts[key]
		return old.result.duplicate(true) if old.actor == actor and old.tool == tool and old.arguments == a else _error("idempotency_conflict")
	var result := _error("unknown_work_command")
	match tool:
		"propose_joint_project": result = propose_venture(actor, "joint-" + key.sha256_text().substr(0, 24), a)
		"accept_joint_project": result = accept_venture(actor, a.venture_id, int(a.version))
		"exit_joint_project": result = exit_venture(actor, a.venture_id, int(a.version))
		"propose_work": result = propose(actor, "work-" + key.sha256_text().substr(0, 24), a)
		"counter_work": result = counter(actor, a.contract_id, int(a.version), a.terms)
		"accept_work": result = accept(actor, a.contract_id, int(a.version))
		"cancel_work": result = cancel(actor, a.contract_id, int(a.version))
		"start_learning": result = start_activity(actor, "learn-" + key.sha256_text().substr(0, 24), "learning", "village_inn")
		"start_leisure": result = start_activity(actor, "leisure-" + key.sha256_text().substr(0, 24), a.activity, a.partner_id)
		"manage_building":
			var b: BuildingInstance = world.building(a.building_id)
			if b == null or b.owner_id != actor: return _error("not_owner")
			if int(b.service_policy.version) != int(a.version): return _error("policy_changed")
			if a.operation == "maintain": result = world.session.production.building_service.maintain(b, actor)
			else:
				var policy := b.service_policy.duplicate(true)
				if a.operation == "pricing":
					policy.fees = {}
					for row in world.session.production.get_rental_fee_table(b): policy.fees[row.recipe_id] = int(a.fee)
				else: policy.open = a.operation == "open"
				result = world.session.production.building_service.set_policy(b, actor, policy, int(a.version))
	receipts[key] = {"actor": actor, "tool": tool, "arguments": a.duplicate(true), "result": result.duplicate(true)}
	return result

func propose(actor: String, id: String, a: Dictionary) -> Dictionary:
	if not valid_terms(a) or contracts.has(id) or not Rules._id(id) or actor == a.worker_id or not world.assets.exists(actor) or not world.assets.exists(a.worker_id) or not world.assets.exists(a.recipient_id): return _error("invalid_work_terms")
	if world.session.market.get_item_state(a.item_id).is_empty() or contracts.size() >= 2048: return _error("unknown_item_or_contract_limit")
	if world.actor(a.worker_id) == null or a.worker_id == "player": return _error("worker_unavailable")
	if not a.parent_contract.is_empty():
		var parent: Dictionary = contracts.get(a.parent_contract, {})
		if parent.get("terms", {}).get("worker_id") != actor or parent.get("status") not in ACTIVE: return _error("invalid_parent_contract")
		var chain := [actor, str(a.worker_id)]
		while not parent.is_empty():
			if parent.employer in chain: return _error("subcontract_cycle")
			chain.append(parent.employer)
			parent = contracts.get(parent.terms.parent_contract, {})
	contracts[id] = {"id": id, "employer": actor, "terms": a.duplicate(true), "version": 1, "status": "proposed", "accepted_by": [actor], "created": world.minute(), "deadline": world.minute() + int(a.deadline_minutes), "gold": 0, "items": {}, "cycle": 0, "next_start": world.minute(), "order_id": "", "movement": {}, "reason": "", "deliveries": [], "history": [], "rental_payments": {}, "refunded_gold": 0}
	contracts[id].captured_orders = []
	contracts[id].returned_items = {}
	_wake([actor, a.worker_id], actor)
	return {"ok": true, "contract_id": id, "message": "分工提案已发送，等待对方接受，尚未扣款或开始工作。"}

func counter(actor: String, id: String, version: int, a: Dictionary) -> Dictionary:
	var c: Dictionary = contracts.get(id, {})
	if c.is_empty() or actor not in [c.employer, c.terms.worker_id] or c.status != "proposed" or int(c.version) != version or not valid_terms(a): return _error("stale_or_foreign_contract")
	if a.worker_id != c.terms.worker_id or a.parent_contract != c.terms.parent_contract: return _error("contract_participants_changed")
	if not world.assets.exists(a.recipient_id) or world.session.market.get_item_state(a.item_id).is_empty() or world.minute() >= int(c.deadline): return _error("invalid_work_terms")
	c.history.append({"version": c.version, "terms": c.terms.duplicate(true), "actor": actor})
	c.terms = a.duplicate(true)
	c.version = version + 1
	c.accepted_by = [actor]
	c.deadline = world.minute() + int(a.deadline_minutes)
	_wake([c.employer, a.worker_id], actor)
	return {"ok": true, "contract_id": id, "message": "已还价，需要另一方确认新版条款。"}

func accept(actor: String, id: String, version: int) -> Dictionary:
	var c: Dictionary = contracts.get(id, {})
	if c.is_empty() or actor not in [c.employer, c.terms.worker_id] or c.status != "proposed" or int(c.version) != version or actor in c.accepted_by or world.minute() >= int(c.deadline): return _error("stale_or_foreign_contract")
	if occupied(c.terms.worker_id): return _error("worker_schedule_conflict")
	var a: Dictionary = c.terms
	var inputs := {a.item_id: int(a.quantity) * int(a.cycles)} if a.kind == "delivery" else {}
	if a.kind == "processing":
		var recipe := preload("res://scripts/core/recipe_database.gd").get_recipe(a.recipe_id)
		if recipe.is_empty() or not recipe.get("input_selectors", []).is_empty(): return _error("explicit_recipe_required")
		if not recipe.outputs.has(a.item_id): return _error("recipe_output_mismatch")
		for item in recipe.inputs: inputs[item] = int(recipe.inputs[item]) * int(a.quantity) * int(a.cycles)
	var debit := {}
	for item in inputs: debit[item] = -int(inputs[item])
	var budget := (int(a.wage) + (int(a.max_fee) if a.kind == "processing" else 0)) * int(a.cycles)
	if not world.assets.apply(c.employer, debit, -budget): return _error("work_budget_unavailable")
	c.items = inputs
	c.gold = budget
	c.accepted_by.append(actor)
	c.status = "queued"
	c.version = version + 1
	return {"ok": true, "contract_id": id, "message": "合同已接受，报酬和原料已托管，按实际交付结算。"}

func occupied(actor: String, except_id := "") -> bool:
	if world.social != null and world.social.busy(actor): return true
	if world.environment != null and world.environment.busy(actor): return true
	if world.knowledge != null and world.knowledge.busy_assignment(actor, except_id): return true
	if world.session.agent_runtime != null and world.session.agent_runtime.activity_system.is_busy(actor): return true
	for c in contracts.values():
		if c.id != except_id and c.terms.worker_id == actor and c.status in ACTIVE: return true
	for a in activities.values():
		if a.actor_id == actor and a.status in ["traveling", "working"]: return true
	if not world.interruptions.running(actor).is_empty() or not world.projects.active(actor).is_empty(): return true
	for shift in world.society.shifts.values():
		if shift.actor_id == actor and shift.status in ["traveling", "working"]: return true
	return world.session.agent_runtime != null and world.session.agent_runtime.farm_registry.has_pending_work(actor)

func owns_schedule(actor: String) -> bool:
	if world.social != null and world.social.busy(actor): return true
	if world.environment != null and world.environment.busy(actor): return true
	if world.knowledge != null and world.knowledge.busy_assignment(actor): return true
	if world.session.agent_runtime != null and world.session.agent_runtime.activity_system.is_busy(actor): return true
	for c in contracts.values():
		if c.terms.worker_id == actor and c.status in ACTIVE: return true
	for a in activities.values():
		if a.actor_id == actor and a.status in ["traveling", "working"]: return true
	return false

func pending_negotiation(actor: String) -> bool:
	if world.social != null and world.social.pending(actor): return true
	if world.knowledge != null and world.knowledge.pending_negotiation(actor): return true
	return contracts.values().any(func(c): return c.status == "proposed" and actor in [c.employer, c.terms.worker_id] and actor not in c.accepted_by) or ventures.values().any(func(v): return v.status == "proposed" and v.terms.partner_id == actor)

func location(actor: String, traveler := "") -> Vector3:
	var body: Node3D = world.actor(actor)
	var start: Node3D = world.actor(traveler)
	if body != null:
		if start != null and not world.session.grid.is_navigation_cell_walkable(world.session.grid.world_to_grid(body.position.x, body.position.z)):
			var path := paths.find_path_to_interaction(start.position, body, 1.5)
			return path.back() if not path.is_empty() else Vector3.INF
		return body.position
	return world.session.MarketSite.reachable_counter(world.session.grid, start.position if start != null else world.session.player.position, world.session.market_site)

func walk(record: Dictionary, actor: String, target: Vector3) -> bool:
	var body: Node3D = world.actor(actor)
	if body == null: record.reason = "actor_unavailable"; return false
	if not target.is_finite(): record.reason = "no_route"; return false
	if Vector2(body.position.x, body.position.z).distance_to(Vector2(target.x, target.z)) <= 1.5:
		body.stop_agent_work()
		return true
	var prior: Dictionary = record.get("movement", {})
	if prior.is_empty() or Vector2(prior.x, prior.z).distance_to(Vector2(target.x, target.z)) > .5 or not body.has_agent_work_target():
		if not body.begin_agent_work(target): record.reason = "no_route"; return false
		record.movement = {"x": target.x, "z": target.z}
	record.reason = "walking"
	return false

func advance() -> void:
	if _busy or world.get_tree().paused: return
	_busy = true
	for c in contracts.values():
		if c.status == "proposed" and world.minute() >= int(c.deadline): c.status = "expired"
		if c.status not in ACTIVE: continue
		if world.minute() >= int(c.deadline) and c.status != "refund_pending":
			c.status = "refund_pending"
			c.reason = "deadline"
		if c.status == "refund_pending": _refund(c); continue
		var a: Dictionary = c.terms
		if c.status in ["queued", "between"]:
			if world.minute() < int(c.next_start): continue
			c.status = "pickup"
		if c.status == "pickup":
			if not walk(c, a.worker_id, location(c.employer, a.worker_id)): continue
			c.status = "working" if a.kind == "processing" else "delivery"
		if c.status == "working":
			_process_order(c)
			continue
		if c.status == "delivery" and walk(c, a.worker_id, location(a.recipient_id, a.worker_id)):
			_deliver(c)
	for activity in activities.values(): _advance_activity(activity)
	for venture in ventures.values():
		if venture.status == "proposed" and world.minute() >= int(venture.deadline): venture.status = "expired"
	_busy = false

func _process_order(c: Dictionary) -> void:
	var a: Dictionary = c.terms
	var b: BuildingInstance = world.building(a.building_id)
	if b == null: c.reason = "building_missing"; return
	var body: Node3D = world.actor(a.worker_id)
	if body == null: c.reason = "actor_unavailable"; return
	var route := paths.find_path_to_interaction(body.position, b, 2.6)
	if route.is_empty(): c.reason = "no_route"; return
	if not walk(c, a.worker_id, route.back()): return
	if c.order_id.is_empty():
		var recipe := preload("res://scripts/core/recipe_database.gd").get_recipe(a.recipe_id)
		var inputs := {}
		for item in recipe.inputs: inputs[item] = int(recipe.inputs[item]) * int(a.quantity)
		for item in inputs:
			if int(c.items.get(item, 0)) < int(inputs[item]): c.reason = "escrow_inputs_missing"; return
		var before: Dictionary = world.assets.snapshot(c.employer)
		if not world.assets.apply(c.employer, inputs, int(a.max_fee)): c.reason = "capacity"; return
		var order := str(c.id) + ":" + str(c.cycle)
		var result: Dictionary = world.session.production.start_rented_recipe(b, c.employer, a.recipe_id, int(a.quantity), int(a.max_fee), order, c.id)
		if not result.ok:
			world.assets.restore(c.employer, before)
			c.reason = str(result.get("error", "production_failed"))
			return
		for item in inputs: c.items[item] = int(c.items[item]) - int(inputs[item])
		var job: Dictionary = b.producer_state.service_records[order].job
		var unused := int(a.max_fee) - int(job.rental_fee)
		world.assets.apply(c.employer, {}, -unused)
		c.gold = int(c.gold) - int(job.rental_fee)
		c.rental_payments[order] = int(job.rental_fee)
		c.order_id = order
	var service: Dictionary = b.producer_state.service_records.get(c.order_id, {})
	if service.get("stage") == "delivered": c.status = "delivery"

func capture_output(_building: BuildingInstance, job: Dictionary, outputs: Dictionary) -> Dictionary:
	var c: Dictionary = contracts.get(str(job.get("request_id", "")), {})
	if c.is_empty() or c.terms.kind != "processing" or c.order_id != job.order_id or c.employer != job.tenant_id: return {"handled": false}
	if c.status not in ACTIVE: return {"handled": true, "ok": false}
	if job.order_id in c.captured_orders: return {"handled": true, "ok": true}
	for item in outputs: c.items[item] = int(c.items.get(item, 0)) + int(outputs[item])
	c.captured_orders.append(job.order_id)
	return {"handled": true, "ok": true}

func _deliver(c: Dictionary) -> void:
	var a: Dictionary = c.terms
	var amount := int(a.quantity)
	if a.kind == "processing": amount *= int(preload("res://scripts/core/recipe_database.gd").get_recipe(a.recipe_id).outputs[a.item_id])
	var source := str(a.worker_id) if a.kind == "supply" else str(c.employer)
	var goods := {a.item_id: amount}
	var debit := {a.item_id: -amount}
	var deltas := {}
	if a.kind == "supply": deltas[source] = {"items": debit, "gold": 0}
	else:
		if int(c.items.get(a.item_id, 0)) < amount: c.reason = "escrow_inputs_missing"; return
	_merge_delta(deltas, a.recipient_id, goods, 0)
	_merge_delta(deltas, a.worker_id, {}, int(a.wage))
	if not transfer(deltas): c.reason = "delivery_assets_unavailable"; return
	if a.kind != "supply": c.items[a.item_id] = int(c.items[a.item_id]) - amount
	c.gold = int(c.gold) - int(a.wage)
	c.deliveries.append({"id": str(c.id) + ":delivery:" + str(c.cycle), "minute": world.minute(), "items": goods, "wage": int(a.wage), "order_id": c.order_id})
	c.cycle = int(c.cycle) + 1
	c.order_id = ""
	c.reason = ""
	c.version = int(c.version) + 1
	if int(c.cycle) >= int(a.cycles):
		c.status = "refund_pending"
		_refund(c)
	else:
		c.status = "between"
		c.next_start = world.minute() + int(a.interval_minutes)

func cancel(actor: String, id: String, version: int) -> Dictionary:
	var c: Dictionary = contracts.get(id, {})
	if c.is_empty() or actor not in [c.employer, c.terms.worker_id] or int(c.version) != version: return _error("stale_or_foreign_contract")
	if c.status in ["completed", "cancelled", "expired"]: return {"ok": true}
	if c.status == "proposed": c.status = "cancelled"
	else: c.status = "refund_pending"
	c.version = int(c.version) + 1
	return {"ok": true, "message": "停止后续周期，已交付报酬不追回；已开始生产等待结算后退还余款。"}

func _refund(c: Dictionary) -> void:
	if not c.order_id.is_empty():
		var b: BuildingInstance = world.building(c.terms.building_id)
		if b == null or b.producer_state.service_records.get(c.order_id, {}).get("stage") != "delivered": return
		c.order_id = ""
	if not c.movement.is_empty() and int(c.cycle) < int(c.terms.cycles) and c.items.values().any(func(count): return int(count) > 0) and not walk(c, c.terms.worker_id, location(c.employer, c.terms.worker_id)): return
	if world.assets.apply(c.employer, c.items, int(c.gold)):
		c.refunded_gold = int(c.gold)
		c.returned_items = c.items.duplicate(true)
		c.items = {}
		c.gold = 0
		c.status = "completed" if int(c.cycle) == int(c.terms.cycles) else ("expired" if world.minute() >= int(c.deadline) else "cancelled")
		var body: Node3D = world.actor(c.terms.worker_id)
		if body != null: body.stop_agent_work()
		_relationship(c, [c.employer, c.terms.worker_id], 2 if c.status == "completed" else 0)

static func _merge_delta(deltas: Dictionary, actor: String, items: Dictionary, gold: int) -> void:
	if not deltas.has(actor): deltas[actor] = {"items": {}, "gold": 0}
	deltas[actor].gold = int(deltas[actor].gold) + gold
	for item in items: deltas[actor].items[item] = int(deltas[actor].items.get(item, 0)) + int(items[item])

func transfer(deltas: Dictionary) -> bool:
	var snapshots := {}
	for actor in deltas:
		if not world.assets.can_apply(actor, deltas[actor].items, int(deltas[actor].gold)): return false
		snapshots[actor] = world.assets.snapshot(actor)
	for actor in deltas:
		if not world.assets.apply(actor, deltas[actor].items, int(deltas[actor].gold)):
			for id in snapshots: world.assets.restore(id, snapshots[id])
			return false
	return true

func start_activity(actor: String, id: String, kind: String, partner: String) -> Dictionary:
	if not Rules._id(id) or activities.has(id) or kind not in ["learning", "visit", "rest"]: return _error("invalid_activity")
	if occupied(actor) or world.actor(actor) == null: return _error("schedule_conflict")
	if kind == "learning" and has_skill(actor, "ingredient_selection"): return _error("already_learned")
	if not world.assets.exists(partner): return _error("unknown_partner")
	var fee := 30 if kind == "learning" else 0
	if not world.assets.apply(actor, {}, -fee): return _error("learning_fee_unavailable")
	activities[id] = {"id": id, "actor_id": actor, "kind": kind, "partner": partner, "fee": fee, "status": "traveling", "worked": 0, "last_minute": world.minute(), "deadline": world.minute() + 540, "reason": ""}
	return {"ok": true, "activity_id": id, "message": "已安排学习／休闲，需要实际到访并花费时间。"}

func _advance_activity(a: Dictionary) -> void:
	if a.status not in ["traveling", "working"]: return
	var elapsed := maxi(0, world.minute() - int(a.last_minute))
	a.last_minute = world.minute()
	if world.minute() >= int(a.deadline):
		if world.assets.apply(a.actor_id, {}, int(a.fee)): a.fee = 0; a.status = "cancelled"
		return
	if not walk(a, a.actor_id, location(a.partner, a.actor_id)): a.status = "traveling"; return
	if a.status == "traveling": a.status = "working"; return
	a.worked = int(a.worked) + elapsed
	if int(a.worked) < (120 if a.kind == "learning" else 60): return
	if a.kind == "learning":
		if not world.assets.apply(a.partner, {}, int(a.fee)): return
		if not skills.has(a.actor_id): skills[a.actor_id] = {}
		skills[a.actor_id].ingredient_selection = {"activity_id": a.id, "minute": world.minute()}
	a.fee = 0
	a.status = "completed"
	if a.kind == "visit" and a.partner != a.actor_id: _relationship(a, [a.actor_id, a.partner], 1)

func _relationship(record: Dictionary, participants: Array, delta: int) -> void:
	if delta == 0 or record.get("relationship_recorded", false) or world.session.agent_runtime == null: return
	var agreements: AgentAgreementSystem = world.session.agent_runtime.agreement_system
	var key := str(record.id) + ":relationship"
	var result := agreements._commit(agreements._relationship_events(participants, delta, world.minute(), key), key)
	if result.ok:
		agreements._adjust_all_relationships(participants, delta, world.minute())
		record.relationship_recorded = true

func _wake(participants: Array, exclude: String) -> void:
	if world.session.agent_runtime != null:
		world.session.agent_runtime.agreement_system._wake_participants(participants, exclude, world.minute())

func has_skill(actor: String, skill: String) -> bool: return skills.get(actor, {}).has(skill)

func activity_label(actor: String) -> String:
	if world.social != null and world.social.busy(actor): return "参加公共活动"
	if world.environment != null and world.environment.busy(actor): return "修复商道"
	for a in world.session.agent_runtime.activity_system._activities.values():
		if a.agent_id == actor and a.status == "in_progress": return "实地调查中" if a.kind == "survey" else "前往调查地点"
	for c in contracts.values():
		if c.terms.worker_id == actor and c.status in ACTIVE:
			return str({"queued": "等待开工", "pickup": "前往取货", "working": "加工中", "delivery": "运送货物", "between": "等待下次供货", "refund_pending": "退还余料"}[c.status])
	for a in activities.values():
		if a.actor_id == actor and a.status in ["traveling", "working"]:
			return "前往学习／休闲" if a.status == "traveling" else str({"learning": "学习配料", "visit": "拜访朋友", "rest": "休息中"}[a.kind])
	return "休息"

func context(actor: String) -> Dictionary:
	var result := _context(actor).duplicate(true)
	for c in result.contracts:
		c.can_counter = c.status == "proposed"
		c.next_job_rule = "Completed/cancelled/expired contracts are immutable history. To hire again, propose_work creates a NEW contract; counter_work only changes a PROPOSED contract."
		c.cargo_provider = c.terms.worker_id if c.terms.kind == "supply" else c.employer
		c.escrow_explanation = "Proposal only: assets are deliberately NOT reserved yet. On acceptance employer supplies all delivery cargo (or processing ingredients) plus wages. Delivery worker contributes time, not their own goods. Only supply kind consumes worker-owned goods." if c.status == "proposed" else "Accepted contract escrow contains employer funds and cargo; payment follows actual delivery."
	var candidates := []
	for id in ["farmer_ahe", "lao_li", "xuezhe_lin"]:
		if id == actor: continue
		var together: Array = contracts.values().filter(func(c): return actor in [c.employer, c.terms.worker_id] and id in [c.employer, c.terms.worker_id] and c.accepted_by.size() == 2)
		candidates.append({"actor_id": id, "name": world.actor_name(id), "busy": occupied(id), "relationship": world.session.agent_runtime.agreement_system.get_relationship(actor, id), "completed_together": together.filter(func(c): return c.status == "completed").size(), "failed_together": together.filter(func(c): return c.status == "expired").size()})
	result.candidates = candidates
	return result

func _context(actor: String) -> Dictionary:
	return {"ventures": ventures.values().filter(func(v): return actor in [v.owner, v.terms.partner_id]), "contracts": contracts.values().filter(func(c): return actor in [c.employer, c.terms.worker_id, c.terms.recipient_id]), "activities": activities.values().filter(func(a): return a.actor_id == actor), "skills": skills.get(actor, {}).duplicate(true), "training": {"skill_id": "ingredient_selection", "fee": 30, "minutes": 120, "provider": "village_inn", "unlocks": "project production with tagged ingredients"}, "rules": "Work is voluntary and negotiable. Propose exact terms; the other party must accept the current version. Wages and employer ingredients are escrowed; delivery/processing/supply pays per actual delivery. Processing quantity means recipe batches, delivery/supply means units. Recipient receives goods. Cycles are prepaid and stop on cancellation; completed wages are final. Training and visits occupy real time. No authority to accept for player. Contract failure never completes the employer's primary commission. Joint project: proposer operates and owns any built facilities; partner contributes exact gold/materials, may refuse. Actual remaining capital returns proportionally, realized surplus splits by partner_profit_percent. Unused contributed materials return to partner first; consumed contributions bear loss. No expected profit is paid."}

func to_dict() -> Dictionary: return {"version": 1, "ventures": ventures.duplicate(true), "contracts": contracts.duplicate(true), "activities": activities.duplicate(true), "skills": skills.duplicate(true), "receipts": receipts.duplicate(true)}

func restore(v: Dictionary) -> void:
	contracts = v.get("contracts", {}).duplicate(true)
	activities = v.get("activities", {}).duplicate(true)
	skills = v.get("skills", {}).duplicate(true)
	receipts = v.get("receipts", {}).duplicate(true)
	ventures = v.get("ventures", {}).duplicate(true)

func validate(v: Variant) -> bool:
	v = preload("res://scripts/ai_agent/agent_protocol.gd")._normalize_json_numbers(v)
	if not v is Dictionary or v.size() != 6 or v.get("version") != 1: return false
	for field in ["contracts", "activities", "skills", "receipts", "ventures"]:
		if not v.get(field) is Dictionary: return false
	var schedules := {}
	for id in v.contracts:
		var c: Variant = v.contracts[id]
		if not c is Dictionary or c.get("id") != id or not valid_terms(c.get("terms")) or not world.assets.exists(str(c.get("employer", ""))): return false
		if not world.assets.exists(c.terms.worker_id) or not world.assets.exists(c.terms.recipient_id) or c.employer == c.terms.worker_id or world.session.market.get_item_state(c.terms.item_id).is_empty(): return false
		if c.get("status") not in ACTIVE + ["proposed", "completed", "cancelled", "expired"] or not c.get("items") is Dictionary or not c.get("deliveries") is Array or not c.get("accepted_by") is Array or not c.get("order_id") is String or not c.get("rental_payments") is Dictionary or not c.get("history") is Array or not c.get("reason") is String or not c.get("movement") is Dictionary: return false
		for field in ["version", "created", "deadline", "gold", "cycle", "next_start", "refunded_gold"]:
			if not Rules._count(c.get(field), 0, 9007199254740991): return false
		if int(c.cycle) != c.deliveries.size() or int(c.cycle) > int(c.terms.cycles): return false
		if c.accepted_by.size() not in [1, 2] or c.accepted_by.any(func(actor): return actor not in [c.employer, c.terms.worker_id]) or (c.accepted_by.size() == 2 and c.accepted_by[0] == c.accepted_by[1]): return false
		var funded: bool = c.accepted_by.size() == 2
		if not c.get("captured_orders") is Array or not c.get("returned_items") is Dictionary: return false
		if not _valid_goods(c, funded): return false
		var chain := [id]
		var parent_id := str(c.terms.parent_contract)
		var child: Dictionary = c
		while not parent_id.is_empty():
			if parent_id in chain or not v.contracts.has(parent_id): return false
			var parent: Dictionary = v.contracts[parent_id]
			if not valid_terms(parent.get("terms")) or parent.terms.worker_id != child.employer: return false
			chain.append(parent_id)
			child = parent
			parent_id = parent.terms.parent_contract
		var budget := (int(c.terms.wage) + (int(c.terms.max_fee) if c.terms.kind == "processing" else 0)) * int(c.terms.cycles) if funded else 0
		var spent := int(c.cycle) * int(c.terms.wage)
		if c.rental_payments.size() > int(c.cycle) + 1 or c.rental_payments.size() > int(c.terms.cycles): return false
		for index in c.rental_payments.size():
			var order := str(id) + ":" + str(index)
			if c.terms.kind != "processing" or not Rules._count(c.rental_payments.get(order), 0, int(c.terms.max_fee)): return false
			spent += int(c.rental_payments[order])
		if budget != int(c.gold) + spent + int(c.refunded_gold): return false
		if c.status in ["completed", "cancelled", "expired", "proposed"] and (int(c.gold) != 0 or not c.items.is_empty()): return false
		if c.status == "completed" and int(c.cycle) != int(c.terms.cycles): return false
		if c.status in ACTIVE and (not funded or int(c.refunded_gold) != 0): return false
		for index in c.deliveries.size():
			var proof: Variant = c.deliveries[index]
			if not proof is Dictionary or proof.get("id") != str(id) + ":delivery:" + str(index) or proof.get("wage") != c.terms.wage or not Rules._count(proof.get("minute"), int(c.created), int(c.deadline)) or not proof.get("items") is Dictionary: return false
			var quantity := int(c.terms.quantity)
			if c.terms.kind == "processing":
				var recipe := preload("res://scripts/core/recipe_database.gd").get_recipe(c.terms.recipe_id)
				if not recipe.get("outputs", {}).has(c.terms.item_id) or proof.get("order_id") != str(id) + ":" + str(index): return false
				quantity *= int(recipe.outputs[c.terms.item_id])
			if proof.items != {c.terms.item_id: quantity}: return false
		if c.status in ACTIVE:
			if schedules.has(c.terms.worker_id): return false
			schedules[c.terms.worker_id] = true
		for item in c.items:
			if not Rules._id(item) or not Rules._count(c.items[item], 0, 1000000): return false
	for id in v.activities:
		var a: Variant = v.activities[id]
		if not a is Dictionary or a.get("id") != id or not world.assets.exists(str(a.get("actor_id", ""))) or a.get("kind") not in ["learning", "visit", "rest"] or a.get("status") not in ["traveling", "working", "completed", "cancelled"]: return false
		for field in ["fee", "worked", "last_minute", "deadline"]:
			if not Rules._count(a.get(field), 0, 9007199254740991): return false
		if not world.assets.exists(str(a.get("partner", ""))) or not a.get("reason") is String: return false
		if a.status in ["completed", "cancelled"] and int(a.fee) != 0: return false
		if a.status in ["traveling", "working"] and int(a.fee) != (30 if a.kind == "learning" else 0): return false
		if a.status == "completed" and int(a.worked) < (120 if a.kind == "learning" else 60): return false
		if a.status in ["traveling", "working"]:
			if schedules.has(a.actor_id): return false
			schedules[a.actor_id] = true
	for actor in v.skills:
		if not world.assets.exists(actor) or not v.skills[actor] is Dictionary: return false
		for skill in v.skills[actor]:
			if skill != "ingredient_selection": return false
			var proof: Variant = v.skills[actor][skill]
			if not proof is Dictionary or not v.activities.has(proof.get("activity_id")): return false
			var a: Dictionary = v.activities[proof.activity_id]
			if a.actor_id != actor or a.kind != "learning" or a.status != "completed" or int(a.worked) < 120: return false
	for id in v.ventures:
		var venture: Variant = v.ventures[id]
		if not venture is Dictionary or venture.get("id") != id or not valid_venture(venture.get("terms")) or not world.assets.exists(str(venture.get("owner", ""))) or venture.get("status") not in ["proposed", "active", "completed", "cancelled", "expired"] or not venture.get("settlement") is Dictionary: return false
		if not world.assets.exists(venture.terms.partner_id) or venture.owner == venture.terms.partner_id or not Rules._count(venture.get("version"), 1, 1000000) or not Rules._count(venture.get("deadline"), 0, 9007199254740991): return false
		if not venture.settlement.is_empty():
			var settlement: Dictionary = venture.settlement
			for field in ["minute", "cash", "realized_surplus", "partner_gold", "owner_gold"]:
				if not Rules._count(settlement.get(field), 0, 9007199254740991): return false
			if int(settlement.partner_gold) + int(settlement.owner_gold) != int(settlement.cash) or int(settlement.realized_surplus) != maxi(0, int(settlement.cash) - int(venture.terms.plan.budget)): return false
			if venture.status in ["proposed", "active"]: return false
	for key in v.receipts:
		var r: Variant = v.receipts[key]
		if not r is Dictionary or not r.get("arguments") is Dictionary or not r.get("result") is Dictionary or not world.assets.exists(str(r.get("actor", ""))) or not valid_command(str(r.get("tool", "")), r.arguments): return false
	return true

static func valid_venture(a: Variant) -> bool:
	if not a is Dictionary or (a.size() != 5 and not (a.size() == 6 and Rules._id(a.get("equipment_id")))) or not Rules._id(a.get("partner_id")) or not a.get("plan") is Dictionary or not Rules.valid_plan(a.plan) or not Rules._count(a.get("partner_gold"), 0, int(a.plan.budget)) or not Rules._count(a.get("partner_profit_percent"), 1, 99) or not a.get("partner_materials") is Dictionary: return false
	if a.has("equipment_id") and not a.plan.steps.any(func(step): return step.capability == "rent" and step.arguments.building_id == a.equipment_id): return false
	for item in a.partner_materials:
		if not a.plan.materials.has(item) or not Rules._count(a.partner_materials[item], 1, int(a.plan.materials[item])): return false
	return true

func _valid_goods(c: Dictionary, funded: bool) -> bool:
	var expected := {}
	var a: Dictionary = c.terms
	if c.captured_orders.size() > c.rental_payments.size(): return false
	for index in c.captured_orders.size():
		if c.captured_orders[index] != str(c.id) + ":" + str(index): return false
	if funded:
		if a.kind == "delivery": expected[a.item_id] = (int(a.cycles) - int(c.cycle)) * int(a.quantity)
		if a.kind == "processing":
			var recipe := preload("res://scripts/core/recipe_database.gd").get_recipe(a.recipe_id)
			if recipe.is_empty() or not recipe.get("input_selectors", []).is_empty() or not recipe.outputs.has(a.item_id): return false
			for item in recipe.inputs: expected[item] = int(recipe.inputs[item]) * int(a.quantity) * (int(a.cycles) - c.rental_payments.size())
			for item in recipe.outputs:
				expected[item] = int(expected.get(item, 0)) + int(recipe.outputs[item]) * int(a.quantity) * c.captured_orders.size()
			expected[a.item_id] = int(expected.get(a.item_id, 0)) - int(recipe.outputs[a.item_id]) * int(a.quantity) * int(c.cycle)
	var held: Dictionary = c.items.duplicate(true)
	if c.status in ACTIVE and not c.returned_items.is_empty(): return false
	for item in c.returned_items:
		if not Rules._count(c.returned_items[item], 0, 1000000): return false
		held[item] = int(held.get(item, 0)) + int(c.returned_items[item])
	for item in held.keys():
		if held[item] == 0: held.erase(item)
	for item in expected.keys():
		if expected[item] == 0: expected.erase(item)
	return held == expected

func propose_venture(actor: String, id: String, a: Dictionary) -> Dictionary:
	if not valid_venture(a) or ventures.has(id) or actor == a.partner_id or actor == "player" or not world.assets.exists(a.partner_id): return _error("invalid_venture")
	ventures[id] = {"id": id, "owner": actor, "terms": a.duplicate(true), "version": 1, "status": "proposed", "deadline": world.minute() + int(a.plan.deadline_minutes), "settlement": {}}
	_wake([actor, a.partner_id], actor)
	return {"ok": true, "venture_id": id, "message": "合作投入方案已提出；经营者拥有建筑，伙伴按约承担成本并分享实际收益，等待确认。"}

func accept_venture(actor: String, id: String, version: int) -> Dictionary:
	var v: Dictionary = ventures.get(id, {})
	if v.is_empty() or actor != v.terms.partner_id or int(v.version) != version or v.status != "proposed" or world.minute() >= int(v.deadline): return _error("stale_or_foreign_venture")
	var a: Dictionary = v.terms
	if a.has("equipment_id"):
		var b: BuildingInstance = world.building(a.equipment_id)
		if b == null or b.owner_id != actor or not b.is_construction_complete(): return _error("equipment_unavailable")
	var delta := {}
	for item in a.partner_materials: delta[item] = -int(a.partner_materials[item])
	var snapshots := {actor: world.assets.snapshot(actor), v.owner: world.assets.snapshot(v.owner)}
	if not transfer({actor: {"items": delta, "gold": -int(a.partner_gold)}, v.owner: {"items": a.partner_materials, "gold": int(a.partner_gold)}}): return _error("contribution_unavailable")
	var result: Dictionary = world.projects.submit(v.owner, id, a.plan)
	if not result.ok:
		for who in snapshots: world.assets.restore(who, snapshots[who])
		return result
	v.status = "active"
	v.version = version + 1
	return {"ok": true, "venture_id": id, "message": "双方投入已进入原项目托管，按真实项目执行。"}

func contributes_equipment(b: BuildingInstance, actor: String, request_id: String) -> bool:
	var v: Dictionary = ventures.get(request_id, {})
	return not v.is_empty() and v.status == "active" and v.owner == actor and v.terms.partner_id == b.owner_id and v.terms.get("equipment_id", "") == b.instance_id

func exit_venture(actor: String, id: String, version: int) -> Dictionary:
	var v: Dictionary = ventures.get(id, {})
	if v.is_empty() or actor not in [v.owner, v.terms.partner_id] or int(v.version) != version: return _error("stale_or_foreign_venture")
	if v.status == "proposed": v.status = "cancelled"; return {"ok": true}
	if v.status != "active": return {"ok": true}
	return world.projects.cancel(v.owner, id)

func settle_project(p: Dictionary, status: String) -> bool:
	var v: Dictionary = ventures.get(p.id, {})
	if v.is_empty(): return false
	if not v.settlement.is_empty(): return true
	var a: Dictionary = v.terms
	var cash := int(p.gold)
	var capital := mini(cash, int(a.plan.budget))
	var profit := maxi(0, cash - int(a.plan.budget))
	var partner_cash := int(float(capital) * int(a.partner_gold) / maxi(1, int(a.plan.budget))) + int(float(profit) * int(a.partner_profit_percent) / 100.0)
	var partner_items := {}
	var owner_items: Dictionary = p.items.duplicate(true)
	for item in a.partner_materials:
		var count := mini(int(a.partner_materials[item]), int(owner_items.get(item, 0)))
		if count > 0: partner_items[item] = count; owner_items[item] = int(owner_items[item]) - count
	if not transfer({a.partner_id: {"items": partner_items, "gold": partner_cash}, v.owner: {"items": owner_items, "gold": cash - partner_cash}}): return false
	v.settlement = {"minute": world.minute(), "cash": cash, "realized_surplus": profit, "partner_gold": partner_cash, "owner_gold": cash - partner_cash, "partner_items": partner_items, "owner_items": owner_items}
	v.status = status
	v.version = int(v.version) + 1
	p.gold = 0
	p.items = {}
	_relationship(v, [v.owner, a.partner_id], 2 if status == "completed" else 0)
	return true

static func _error(code: String) -> Dictionary: return {"ok": false, "error": code}
