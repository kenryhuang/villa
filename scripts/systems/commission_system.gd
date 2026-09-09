extends RefCounted

const Recipes = preload("res://scripts/core/recipe_database.gd")
var world: Node
var demands: Dictionary = {}
var commissions: Dictionary = {}
var claims: Dictionary = {}
var receipts: Dictionary = {}
var proofs: Dictionary = {}
var sequence := 0
var _busy := false

func configure(owner: Node) -> void:
	world = owner
	world.session.production.service_order_changed.connect(_production_event)

func demand(id: String, actor: String, item: String, quantity: int) -> bool:
	if demands.has(id): return demands[id].actor_id == actor and demands[id].item_id == item and int(demands[id].total) == quantity
	if not world.assets.exists(actor) or quantity < 0 or quantity > 100 or world.session.market.get_item_state(item).is_empty(): return false
	demands[id] = {"id": id, "actor_id": actor, "item_id": item, "total": quantity, "satisfied": 0, "reserved": 0}
	return true

func available(id: String) -> int:
	if not demands.has(id): return 0
	var d: Dictionary = demands[id]
	return int(d.total) - int(d.satisfied) - int(d.reserved)

func procure(actor: String, id: String, quantity: int) -> Dictionary:
	if _busy or not demands.has(id) or demands[id].actor_id != actor or quantity <= 0 or quantity > available(id): return _error("demand_share_unavailable")
	var d: Dictionary = demands[id]
	var price: int = world.session.npc_economy.quote_agent_buy(d.item_id, quantity)
	if not world.assets.can_apply(actor, {}, -price): return _error("insufficient_funds")
	_busy = true
	var ok: bool = world.session.npc_economy.agent_buy(actor, d.item_id, quantity)
	if ok: d.satisfied = int(d.satisfied) + quantity
	_busy = false
	return {"ok": ok}

func publish(actor: String, id: String, terms: Dictionary) -> Dictionary:
	if _busy or not valid_terms(terms): return _error("invalid_commission")
	if commissions.has(id): return {"ok": commissions[id].actor_id == actor and commissions[id].terms == terms, "commission_id": id}
	var d: Dictionary = demands.get(terms.demand_id, {})
	if d.is_empty() or d.actor_id != actor or terms.item_id != d.item_id or int(terms.quantity) > available(d.id): return _error("demand_share_unavailable")
	var cost := int(terms.quantity) * int(terms.unit_reward)
	if not world.assets.apply(actor, {}, -cost): return _error("escrow_unaffordable")
	d.reserved = int(d.reserved) + int(terms.quantity)
	commissions[id] = {"id": id, "actor_id": actor, "terms": terms.duplicate(true), "escrow": cost, "delivered": 0, "claimed": 0, "deadline": world.minute() + int(terms.deadline_minutes), "status": "open", "version": 1}
	return {"ok": true, "commission_id": id, "message": "委托已发布，报酬已从发布者账户托管。"}

func claim(actor: String, id: String, commission_id: String, quantity: int) -> Dictionary:
	if claims.has(id): return {"ok": claims[id].actor_id == actor and claims[id].commission_id == commission_id and int(claims[id].quantity) == quantity, "claim_id": id}
	var available := check_claim(actor, commission_id, quantity)
	if not available.ok: return available
	var c: Dictionary = commissions[commission_id]
	sequence += 1
	claims[id] = {"id": id, "actor_id": actor, "commission_id": commission_id, "quantity": quantity, "delivered": 0, "status": "active", "sequence": sequence}
	c.claimed = int(c.claimed) + quantity
	c.version = int(c.version) + 1
	return {"ok": true, "claim_id": id, "version": c.version}

func check_claim(actor: String, commission_id: String, quantity: int, reserved_quantity := 0, reserved_slots := 0) -> Dictionary:
	var c: Dictionary = commissions.get(commission_id, {})
	if c.is_empty() or c.actor_id == actor or not world.assets.exists(actor) or c.status != "open" or world.minute() >= int(c.deadline): return _error("commission_unavailable")
	if world.interruptions != null and world.interruptions.load_count(actor) + reserved_slots >= world.interruptions.LIMIT: return _error("task_capacity")
	if quantity < 1 or quantity > int(c.terms.quantity) - int(c.delivered) - int(c.claimed) - reserved_quantity: return _error("claim_quota")
	var active := 0
	for old in claims.values():
		if old.commission_id == commission_id and old.status == "active": active += 1
	if active + reserved_slots >= int(c.terms.max_claims): return _error("claim_slots_full")
	return {"ok": true}

func deliver(actor: String, receipt_id: String, claim_id: String, quantity: int, version: int, order_id := "") -> Dictionary:
	var intent := {"actor_id": actor, "claim_id": claim_id, "quantity": quantity, "version": version, "order_id": order_id}
	if receipts.has(receipt_id): return {"ok": receipts[receipt_id] == intent, "duplicate": true}
	if _busy: return _error("transaction_busy")
	var task: Dictionary = claims.get(claim_id, {})
	if task.is_empty() or task.actor_id != actor or task.status != "active": return _error("claim_owner_or_status")
	var c: Dictionary = commissions[task.commission_id]
	if c.status != "open" or world.minute() >= int(c.deadline): return _error("deadline_passed")
	if version != int(c.version): return _error("terms_changed_reconfirm")
	if quantity <= 0 or quantity > int(task.quantity) - int(task.delivered): return _error("delivery_over_quota")
	var proof: Dictionary = {}
	if c.terms.kind == "processing":
		proof = proofs.get(order_id, {})
		if proof.is_empty() or proof.actor_id != actor or not proof.complete or int(proof.sequence) <= int(task.sequence) or int(proof.outputs.get(c.terms.item_id, 0)) - int(proof.used.get(c.terms.item_id, 0)) < quantity: return _error("new_production_proof_required")
	var pay := quantity * int(c.terms.unit_reward)
	if int(c.escrow) < pay or not world.assets.can_apply(actor, {c.terms.item_id: -quantity}, pay) or not world.assets.can_apply(c.actor_id, {c.terms.item_id: quantity}, 0): return _error("delivery_assets_or_capacity")
	_busy = true
	var before: Dictionary = world.assets.snapshot(actor)
	if not world.assets.apply(actor, {c.terms.item_id: -quantity}, pay) or not world.assets.apply(c.actor_id, {c.terms.item_id: quantity}, 0):
		world.assets.restore(actor, before)
		_busy = false
		return _error("delivery_failed")
	c.escrow = int(c.escrow) - pay
	c.delivered = int(c.delivered) + quantity
	c.claimed = int(c.claimed) - quantity
	c.version = int(c.version) + 1
	task.delivered = int(task.delivered) + quantity
	if int(task.delivered) == int(task.quantity): task.status = "completed"
	if int(c.delivered) == int(c.terms.quantity): c.status = "completed"
	var d: Dictionary = demands[c.terms.demand_id]
	d.reserved = int(d.reserved) - quantity
	d.satisfied = int(d.satisfied) + quantity
	if not proof.is_empty(): proof.used[c.terms.item_id] = int(proof.used.get(c.terms.item_id, 0)) + quantity
	receipts[receipt_id] = intent
	_busy = false
	return {"ok": true, "reward": pay, "message": "实物已交付，报酬 %d 金币到账。" % pay}

func cancel(actor: String, id: String) -> Dictionary:
	if not commissions.has(id) or commissions[id].actor_id != actor: return _error("not_publisher")
	var c: Dictionary = commissions[id]
	if c.status != "open": return {"ok": true}
	# Claimed work is protected until the agreed deadline.
	if int(c.claimed) > 0 and world.minute() < int(c.deadline): return _error("active_claims")
	return {"ok": _close(c, "cancelled")}

func abandon(actor: String, id: String) -> Dictionary:
	var task: Dictionary = claims.get(id, {})
	if task.is_empty() or task.actor_id != actor: return _error("not_claim_owner")
	if task.status != "active": return {"ok": true}
	var c: Dictionary = commissions[task.commission_id]
	c.claimed = int(c.claimed) - (int(task.quantity) - int(task.delivered))
	c.version = int(c.version) + 1
	task.status = "abandoned"
	return {"ok": true}

func _close(c: Dictionary, status: String) -> bool:
	if not world.assets.apply(c.actor_id, {}, int(c.escrow)): return false
	var d: Dictionary = demands[c.terms.demand_id]
	d.reserved = int(d.reserved) - (int(c.terms.quantity) - int(c.delivered))
	c.escrow = 0
	c.claimed = 0
	c.status = status
	c.version = int(c.version) + 1
	for task in claims.values():
		if task.commission_id == c.id and task.status == "active": task.status = "expired"
	return true

func advance() -> void:
	for c in commissions.values():
		if c.status == "open" and world.minute() >= int(c.deadline): _close(c, "expired")

func daily(day: int) -> void:
	var id := "inn-food-%d" % day
	if demands.has(id): return
	var needed := maxi(0, 4 - int(world.assets.available_items("village_inn").get("bread", 0)))
	if not demand(id, "village_inn", "bread", needed) or needed == 0: return
	var reward: int = ceili(world.session.market.quote_buy("bread", 1) * 1.05)
	publish("village_inn", id, {"demand_id": id, "item_id": "bread", "quantity": mini(2, needed), "unit_reward": reward, "kind": "purchase", "max_claims": 2, "deadline_minutes": 960})

func buy_inn_share(day: int) -> void:
	var id := "inn-food-%d" % day
	if available(id) > 0: procure("village_inn", id, available(id))
	var count := mini(4, int(world.assets.available_items("village_inn").get("bread", 0)))
	if count > 0 and world.assets.apply("village_inn", {"bread": -count}, 0): world.society._record("inn_food_consumed", "village_inn", 0, {"bread": -count}, id)

func _production_event(_building: BuildingInstance, record: Dictionary) -> void:
	var id := str(record.job.order_id)
	if record.stage == "queued" and not proofs.has(id):
		sequence += 1
		var outputs := {}
		for item in Recipes.get_recipe(record.job.recipe_id).outputs: outputs[item] = int(Recipes.get_recipe(record.job.recipe_id).outputs[item]) * int(record.job.batches)
		proofs[id] = {"actor_id": record.job.tenant_id, "sequence": sequence, "outputs": outputs, "used": {}, "complete": false}
	if record.stage in ["ready", "delivered"] and proofs.has(id): proofs[id].complete = true

func to_dict() -> Dictionary:
	return {"demands": demands.duplicate(true), "commissions": commissions.duplicate(true), "claims": claims.duplicate(true), "receipts": receipts.duplicate(true), "proofs": proofs.duplicate(true), "sequence": sequence}

func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != 6 or not world.integer(v.get("sequence")) or int(v.sequence) < 0: return false
	for key in ["demands", "commissions", "claims", "receipts", "proofs"]:
		if not v.get(key) is Dictionary: return false
	var reserved := {}
	for id in v.commissions:
		var c: Variant = v.commissions[id]
		if not c is Dictionary or c.get("id") != id or not valid_terms(c.get("terms")) or not v.demands.has(c.terms.demand_id) or c.get("actor_id") != v.demands[c.terms.demand_id].get("actor_id"): return false
		for key in ["escrow", "delivered", "claimed", "deadline", "version"]:
			if not world.integer(c.get(key)) or int(c[key]) < 0: return false
		if c.get("status") not in ["open", "completed", "cancelled", "expired"] or int(c.delivered) + int(c.claimed) > int(c.terms.quantity): return false
		var remaining := int(c.terms.quantity) - int(c.delivered)
		if int(c.escrow) != (remaining * int(c.terms.unit_reward) if c.status == "open" else 0): return false
		if c.status == "open": reserved[c.terms.demand_id] = int(reserved.get(c.terms.demand_id, 0)) + remaining
	for id in v.demands:
		var d: Variant = v.demands[id]
		if not d is Dictionary or d.get("id") != id or not world.assets.exists(str(d.get("actor_id", ""))) or not d.get("item_id") is String: return false
		for key in ["total", "satisfied", "reserved"]:
			if not world.integer(d.get(key)) or int(d[key]) < 0: return false
		if int(d.satisfied) + int(d.reserved) > int(d.total) or int(d.reserved) != int(reserved.get(id, 0)): return false
	var claimed := {}
	for id in v.claims:
		var task: Variant = v.claims[id]
		if not task is Dictionary or task.get("id") != id or not world.assets.exists(str(task.get("actor_id", ""))) or not v.commissions.has(task.get("commission_id")) or task.get("status") not in ["active", "completed", "abandoned", "expired"]: return false
		for key in ["quantity", "delivered", "sequence"]:
			if not world.integer(task.get(key)) or int(task[key]) < 0: return false
		if int(task.delivered) > int(task.quantity) or int(task.sequence) > int(v.sequence): return false
		if task.status == "active": claimed[task.commission_id] = int(claimed.get(task.commission_id, 0)) + int(task.quantity) - int(task.delivered)
	for c in v.commissions.values():
		if int(c.claimed) != int(claimed.get(c.id, 0)): return false
	var delivered := {}
	var proof_used := {}
	for receipt in v.receipts.values():
		if not receipt is Dictionary or receipt.size() != 5 or not v.claims.has(receipt.get("claim_id")): return false
		var task: Dictionary = v.claims[receipt.claim_id]
		if receipt.get("actor_id") != task.actor_id or not world.integer(receipt.get("quantity")) or int(receipt.quantity) <= 0 or not world.integer(receipt.get("version")) or int(receipt.version) < 1 or not receipt.get("order_id") is String: return false
		delivered[task.id] = int(delivered.get(task.id, 0)) + int(receipt.quantity)
		var c: Dictionary = v.commissions[task.commission_id]
		if c.terms.kind == "processing":
			if not v.proofs.has(receipt.order_id): return false
			var proof: Dictionary = v.proofs[receipt.order_id]
			if proof.get("actor_id") != task.actor_id or not proof.get("complete", false) or not world.integer(proof.get("sequence")) or int(proof.sequence) <= int(task.sequence): return false
			var used: Dictionary = proof_used.get(receipt.order_id, {})
			used[c.terms.item_id] = int(used.get(c.terms.item_id, 0)) + int(receipt.quantity)
			proof_used[receipt.order_id] = used
	var commissioned_delivery := {}
	for task in v.claims.values():
		if int(task.delivered) != int(delivered.get(task.id, 0)): return false
		commissioned_delivery[task.commission_id] = int(commissioned_delivery.get(task.commission_id, 0)) + int(task.delivered)
	for c in v.commissions.values():
		if int(c.delivered) != int(commissioned_delivery.get(c.id, 0)): return false
	for id in v.proofs:
		var proof: Variant = v.proofs[id]
		if not proof is Dictionary or proof.size() != 5 or not world.assets.exists(str(proof.get("actor_id", ""))) or not world.integer(proof.get("sequence")) or int(proof.sequence) < 1 or int(proof.sequence) > int(v.sequence) or not proof.get("complete") is bool or not proof.get("outputs") is Dictionary or not proof.get("used") is Dictionary: return false
		for item in proof.outputs:
			if not world.integer(proof.outputs[item]) or int(proof.outputs[item]) < 1: return false
		for item in proof.used:
			if not proof.outputs.has(item) or not world.integer(proof.used[item]) or int(proof.used[item]) < 0 or int(proof.used[item]) > int(proof.outputs[item]) or int(proof.used[item]) != int(proof_used.get(id, {}).get(item, 0)): return false
		for item in proof_used.get(id, {}):
			if int(proof.used.get(item, 0)) != int(proof_used[id][item]): return false
	return true

func restore(v: Dictionary) -> void:
	demands = v.demands.duplicate(true)
	commissions = v.commissions.duplicate(true)
	claims = v.claims.duplicate(true)
	receipts = v.receipts.duplicate(true)
	proofs = v.proofs.duplicate(true)
	sequence = int(v.sequence)

static func valid_terms(v: Variant) -> bool:
	if not v is Dictionary or v.size() != 7 or not v.get("demand_id") is String or not v.get("item_id") is String or v.get("kind") not in ["purchase", "processing"]: return false
	for key in ["quantity", "unit_reward", "max_claims", "deadline_minutes"]:
		if not (v.get(key) is int or v.get(key) is float) or not is_finite(float(v[key])) or floorf(float(v[key])) != float(v[key]) or int(v[key]) < 1: return false
	return int(v.quantity) <= 100 and int(v.unit_reward) <= 1000000 and int(v.max_claims) <= 10 and int(v.deadline_minutes) <= 10080

static func _error(code: String) -> Dictionary: return {"ok": false, "error": code}
