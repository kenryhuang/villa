extends RefCounted

const Recipes = preload("res://scripts/core/recipe_database.gd")
const CAPABILITIES := ["buy", "sell", "move", "rent", "wait_production", "reserve_plot", "build", "wait_construction", "set_policy", "claim", "deliver"]
var world: Node
var projects: Dictionary = {}
var suggestions: Dictionary = {}
var _busy := false

func configure(owner: Node) -> void:
	world = owner
	world.session.production.service_order_changed.connect(_production_event)
	world.get_node("/root/EventBus").production_job_completed.connect(_capacity_changed)
	world.get_node("/root/EventBus").production_output_changed.connect(_capacity_changed)

static func valid_plan(plan: Variant) -> bool:
	if not plan is Dictionary or plan.size() != 5: return false
	if not plan.get("goal") is String or plan.goal.is_empty() or plan.goal.length() > 500: return false
	if not _count(plan.get("budget"), 0, 1000000) or not _count(plan.get("deadline_minutes"), 60, 10080): return false
	if not _items(plan.get("materials")) or not plan.get("steps") is Array or plan.steps.is_empty() or plan.steps.size() > 12: return false
	var seen := {}
	for step in plan.steps:
		if not step is Dictionary or step.size() != 4 or not step.get("id") is String or step.id.is_empty() or step.id.length() > 40 or seen.has(step.id): return false
		if step.get("capability") not in CAPABILITIES or not step.get("depends_on") is Array or not step.get("arguments") is Dictionary: return false
		for dep in step.depends_on:
			if not seen.has(dep): return false # Topological order, no cycles or dangling references.
		if not valid_step(step.capability, step.arguments): return false
		var refs := {"wait_production": {"order_step": "rent"}, "build": {"lease_step": "reserve_plot"}, "wait_construction": {"build_step": "build"}, "set_policy": {"build_step": "build"}, "deliver": {"claim_step": "claim", "order_step": "rent"}}
		var ancestors := {}
		for dep in step.depends_on:
			ancestors[dep] = true
			ancestors.merge(seen[dep].ancestors)
		for field in refs.get(step.capability, {}):
			var reference := str(step.arguments[field])
			if field == "order_step" and reference.is_empty() and step.capability == "deliver": continue
			if not ancestors.has(reference) or seen[reference].capability != refs[step.capability][field]: return false
		if step.capability == "rent" and str(step.arguments.building_id).begins_with("@"):
			var ref := str(step.arguments.building_id).trim_prefix("@")
			if not ancestors.has(ref) or seen[ref].capability != "build": return false
		seen[step.id] = {"capability": step.capability, "ancestors": ancestors}
	return true

static func valid_step(cap: String, a: Dictionary) -> bool:
	match cap:
		"buy", "sell": return a.size() == 3 and _id(a.get("item_id")) and _count(a.get("quantity"), 1, 100) and _count(a.get("limit"), 0, 1000000)
		"move": return a.size() == 2 and _number(a.get("x"), -176, 80) and _number(a.get("z"), -80, 144)
		"rent": return a.size() == 4 and _id(a.get("building_id")) and _id(a.get("recipe_id")) and _count(a.get("batches"), 1, 100) and _count(a.get("max_fee"), 0, 1000000)
		"wait_production": return a.size() == 1 and _id(a.get("order_step"))
		"reserve_plot": return a.size() == 2 and _count(a.get("gx"), -1024, 1024) and _count(a.get("gz"), -1024, 1024)
		"build": return a.size() == 1 and _id(a.get("lease_step"))
		"wait_construction": return a.size() == 1 and _id(a.get("build_step"))
		"set_policy": return a.size() == 3 and _id(a.get("build_step")) and a.get("open") is bool and _count(a.get("fee"), 0, 1000000)
		"claim": return a.size() == 2 and _id(a.get("commission_id")) and _count(a.get("quantity"), 1, 100)
		"deliver": return a.size() == 3 and _id(a.get("claim_step")) and _count(a.get("quantity"), 1, 100) and a.get("order_step") is String
	return false

func submit(actor: String, id: String, plan: Dictionary) -> Dictionary:
	if not valid_plan(plan) or not world.assets.exists(actor) or actor == "player": return _error("invalid_project")
	if projects.has(id): return {"ok": projects[id].actor_id == actor and projects[id].plan == plan, "project_id": id}
	if not active(actor).is_empty() or projects.values().any(func(p): return p.actor_id == actor and p.status == "suspended") or not world.interruptions.running(actor).is_empty(): return _error("primary_project_exists")
	var commission_check := _check_commissions(actor, plan)
	if not commission_check.ok: return commission_check
	for item in plan.materials:
		if world.session.market.get_item_state(item).is_empty(): return _error("unknown_material")
	var debit := {}
	for item in plan.materials: debit[item] = -int(plan.materials[item])
	if not world.assets.apply(actor, debit, -int(plan.budget)): return _error("project_resources_unavailable")
	var steps := {}
	for step in plan.steps: steps[step.id] = {"status": "pending", "result": {}, "error": "", "attempts": 0}
	projects[id] = {"id": id, "actor_id": actor, "plan": plan.duplicate(true), "status": "active", "deadline": world.minute() + int(plan.deadline_minutes), "gold": int(plan.budget), "items": plan.materials.duplicate(true), "steps": steps, "reason": "", "created": world.minute(), "version": 1, "changes": []}
	return {"ok": true, "project_id": id, "message": "自主项目已接受并托管预算，按依赖执行；尚未完成。"}

func active(actor: String) -> Dictionary:
	for p in projects.values():
		if p.actor_id == actor and p.status == "active": return p
	return {}

func _check_commissions(actor: String, plan: Dictionary, states: Dictionary = {}) -> Dictionary:
	var reserved := {}
	for step in plan.steps:
		var state: Dictionary = states.get(step.id, {})
		if step.capability == "claim" and state.get("status") != "done":
			var id: String = step.arguments.commission_id
			var counts: Vector2i = reserved.get(id, Vector2i.ZERO)
			var result: Dictionary = world.board.check_claim(actor, id, int(step.arguments.quantity), counts.x, counts.y)
			if not result.ok:
				result.merge({"step_id": step.id, "commission_id": id, "message": "委托条件已变化，未继续采购；请根据当前委托重新规划。"})
				return result
			reserved[id] = counts + Vector2i(int(step.arguments.quantity), 1)
		elif step.capability == "deliver" and state.get("status") != "done":
			var claim_state: Dictionary = states.get(step.arguments.claim_step, {})
			if claim_state.get("status") != "done": continue
			var task: Dictionary = world.board.claims.get(claim_state.get("result", {}).get("claim_id", ""), {})
			var commission: Dictionary = world.board.commissions.get(task.get("commission_id", ""), {})
			if task.get("actor_id") != actor or task.get("status") != "active" or commission.get("status") != "open" or world.minute() >= int(commission.get("deadline", 0)):
				return {"ok": false, "error": "commission_unavailable", "step_id": step.id, "commission_id": task.get("commission_id", "")}
	return {"ok": true}

func suggest(actor: String, text: String, ttl: int) -> Dictionary:
	if not world.assets.exists(actor) or text.is_empty() or text.length() > 500 or ttl < 1 or ttl > 1080: return _error("invalid_suggestion")
	suggestions[actor] = {"text": text, "expires": world.minute() + ttl}
	return {"ok": true, "message": "建议已记录，NPC 会在下次决策评估，不保证接受。"}

func cancel(actor: String, id: String) -> Dictionary:
	if not projects.has(id) or projects[id].actor_id != actor: return _error("not_project_owner")
	var p: Dictionary = projects[id]
	if p.status not in ["active", "suspended"]: return {"ok": true}
	for step in p.steps.values():
		if step.result.has("order_id") and not step.result.get("delivered", false) and not step.result.get("cancelled", false): return _error("wait_for_committed_work")
	return {"ok": _finish(p, "cancelled")}

func advance() -> void:
	if _busy or world.get_tree().paused: return
	_busy = true
	for actor in suggestions.keys():
		if world.minute() >= int(suggestions[actor].expires): suggestions.erase(actor)
	for p in projects.values():
		if p.status != "active" or not world.interruptions.running(p.actor_id).is_empty(): continue
		var waiting := false
		for state in p.steps.values(): waiting = waiting or (state.result.has("order_id") and not state.result.get("delivered", false) and not state.result.get("cancelled", false))
		var commission_check := _check_commissions(p.actor_id, p.plan, p.steps)
		if not commission_check.ok:
			p.reason = str(commission_check.error)
			# Preserve already committed production until its actual goods return.
			# No new purchases or rentals may run against an invalid goal.
			if not waiting: _finish(p, "cancelled")
			continue
		if world.minute() >= int(p.deadline):
			if not waiting: _finish(p, "expired")
			continue
		var complete := true
		for step in p.plan.steps:
			var state: Dictionary = p.steps[step.id]
			if state.status == "done": continue
			complete = false
			if state.status == "blocked": continue # Decision/event revalidation, no blind repeated buys.
			var ready := true
			for dep in step.depends_on: ready = ready and p.steps[dep].status == "done"
			if not ready: continue
			var result := _execute(p, step, state)
			if state.status != "waiting": state.attempts = int(state.attempts) + 1
			state.error = str(result.get("error", ""))
			state.status = "done" if result.get("ok", false) else ("waiting" if result.get("waiting", false) else "blocked")
			state.result = result.duplicate(true)
			p.reason = state.error
			break
		if complete: _finish(p, "completed")
	_busy = false

func retry(actor: String, id: String) -> Dictionary:
	if not projects.has(id) or projects[id].actor_id != actor or projects[id].status != "active": return _error("unknown_project")
	for state in projects[id].steps.values():
		if state.status == "blocked": state.status = "pending"
	return {"ok": true}

func _execute(p: Dictionary, step: Dictionary, state: Dictionary) -> Dictionary:
	var a: Dictionary = step.arguments
	var key := str(p.id) + ":" + str(step.id)
	match step.capability:
		"buy":
			var price: int = world.session.npc_economy.quote_agent_buy(a.item_id, int(a.quantity))
			if price <= 0 or price > int(a.limit) or price > int(p.gold): return _error("purchase_budget_or_price")
			if not world.assets.apply(p.actor_id, {}, price): return _error("account_capacity")
			p.gold = int(p.gold) - price
			var ok: bool = world.session.npc_economy.agent_buy(p.actor_id, a.item_id, int(a.quantity))
			if not ok:
				world.assets.apply(p.actor_id, {}, -price)
				p.gold = int(p.gold) + price
				return _error("market_shortage")
			world.assets.apply(p.actor_id, {a.item_id: -int(a.quantity)}, 0)
			p.items[a.item_id] = int(p.items.get(a.item_id, 0)) + int(a.quantity)
			return {"ok": true, "cost": price}
		"sell":
			var price: int = world.session.market.quote_sell(a.item_id, int(a.quantity))
			if price < int(a.limit) or int(p.items.get(a.item_id, 0)) < int(a.quantity): return {"ok": false, "error": "sale_price_or_stock", "current_total_quote": price, "project_stock": int(p.items.get(a.item_id, 0))}
			world.assets.apply(p.actor_id, {a.item_id: int(a.quantity)}, 0)
			if not world.session.npc_economy.agent_sell(p.actor_id, a.item_id, int(a.quantity)):
				world.assets.apply(p.actor_id, {a.item_id: -int(a.quantity)}, 0)
				return _error("sale_failed")
			p.items[a.item_id] = int(p.items[a.item_id]) - int(a.quantity)
			world.assets.apply(p.actor_id, {}, -price)
			p.gold = int(p.gold) + price
			return {"ok": true, "income": price}
		"move":
			var actor: Node = world.actor(p.actor_id)
			if actor == null: return _error("actor_unavailable")
			var target := Vector3(float(a.x), Farm3DTerrainProfile.surface_height(float(a.x), float(a.z)), float(a.z))
			if state.result.has("target"):
				target = Vector3(state.result.target.x, state.result.target.y, state.result.target.z)
			elif world.session.MarketSite.contains(world.session.market_site, Vector2(a.x, a.z)):
				target = world.session.MarketSite.reachable_counter(world.session.grid, actor.position, world.session.market_site)
				if not target.is_finite(): return _error("no_route")
			else:
				for b in world.session.buildings.get_all_buildings():
					var cell: GridCell = world.session.grid.get_cell(b.grid_x, b.grid_z)
					if Rect2(cell.world_position() - Vector2(.5, .5), Vector2(b.data.footprint)).grow(.2).has_point(Vector2(a.x, a.z)):
						var finder := GridPathfinder.new()
						finder.configure(world.session.grid)
						var route := finder.find_path_to_interaction(actor.position, b, 2.6)
						if route.is_empty(): return _error("no_route")
						target = route.back()
						break
			if Vector2(actor.position.x, actor.position.z).distance_to(Vector2(target.x, target.z)) < .65: return {"ok": true}
			if (state.status != "waiting" or not actor.has_agent_work_target()) and not actor.begin_agent_work(target): return _error("no_route")
			return {"waiting": true, "error": "walking", "target": {"x": target.x, "y": target.y, "z": target.z}}
		"rent":
			var building_id := str(a.building_id)
			if building_id.begins_with("@"): building_id = str(p.steps[building_id.trim_prefix("@")].result.get("building_id", ""))
			var building: BuildingInstance = world.building(building_id)
			if building == null: return _error("building_missing")
			var recipe := Recipes.get_recipe(a.recipe_id)
			if recipe.is_empty(): return _error("unknown_recipe")
			if not recipe.get("input_selectors", []).is_empty(): return _error("project_requires_explicit_ingredients")
			var inputs := {}
			for item in recipe.inputs: inputs[item] = int(recipe.inputs[item]) * int(a.batches)
			if not _release(p, inputs, int(a.max_fee)): return _error("project_materials_or_fee")
			var result: Dictionary = world.session.production.start_rented_recipe(building, p.actor_id, a.recipe_id, int(a.batches), int(a.max_fee), key, str(p.id))
			if not result.ok:
				_hold(p, inputs, int(a.max_fee))
				return result
			var fee := int(building.producer_state.service_records[key].job.rental_fee)
			_hold(p, {}, int(a.max_fee) - fee)
			return {"ok": true, "order_id": key, "building_id": building.instance_id, "rental_fee": fee, "delivered": false}
		"wait_production":
			var order: Dictionary = p.steps.get(a.order_step, {}).get("result", {})
			if order.get("cancelled", false): return _error("production_cancelled")
			return {"ok": true} if order.get("delivered", false) else {"waiting": true, "error": "production"}
		_:
			return world.execute_project_step(p, step, state, key)

func _production_event(building: BuildingInstance, record: Dictionary) -> void:
	if record.stage in ["delivered", "cancelled"]: _capacity_changed(building, "", {})
	if record.stage not in ["delivered", "cancelled"]: return
	for p in projects.values():
		if p.status not in ["active", "suspended"] or p.actor_id != record.job.tenant_id: continue
		for state in p.steps.values():
			if state.result.get("order_id", "") != record.job.order_id or state.result.get("delivered", false) or state.result.get("cancelled", false): continue
			if record.stage == "cancelled":
				if _hold(p, record.job.service_inputs, int(record.job.rental_fee)): state.result.cancelled = true
				continue
			var outputs := {}
			for item in Recipes.get_recipe(record.job.recipe_id).outputs: outputs[item] = int(Recipes.get_recipe(record.job.recipe_id).outputs[item]) * int(record.job.batches)
			if _hold(p, outputs, 0):
				state.result.delivered = true
				state.result.building_id = building.instance_id

func _capacity_changed(building: BuildingInstance, _item: String, _amount: Variant) -> void:
	for p in projects.values():
		if p.status not in ["active", "suspended"]: continue
		for step in p.plan.steps:
			var state: Dictionary = p.steps[step.id]
			if step.capability != "rent" or state.status != "blocked" or state.error not in ["queue_full", "reserved_capacity", "output_full", "output_capacity"]: continue
			var id := str(step.arguments.building_id)
			if id.begins_with("@"): id = str(p.steps[id.trim_prefix("@")].result.get("building_id", ""))
			if id in [building.instance_id, EconomyProgressionSystem.building_key(building)]: state.status = "pending"

func _release(p: Dictionary, items: Dictionary, gold: int) -> bool:
	if int(p.gold) < gold: return false
	for item in items:
		if int(p.items.get(item, 0)) < int(items[item]): return false
	if not world.assets.apply(p.actor_id, items, gold): return false
	p.gold = int(p.gold) - gold
	for item in items: p.items[item] = int(p.items[item]) - int(items[item])
	return true

func _hold(p: Dictionary, items: Dictionary, gold: int) -> bool:
	var debit := {}
	for item in items: debit[item] = -int(items[item])
	if not world.assets.apply(p.actor_id, debit, -gold): return false
	p.gold = int(p.gold) + gold
	for item in items: p.items[item] = int(p.items.get(item, 0)) + int(items[item])
	return true

func _finish(p: Dictionary, status: String) -> bool:
	if not _release(p, p.items.duplicate(), int(p.gold)): return false
	if status != "completed":
		for step in p.plan.steps:
			if step.capability == "claim" and p.steps[step.id].result.has("claim_id"):
				world.board.abandon(p.actor_id, str(p.steps[step.id].result.claim_id))
	var body: Node = world.actor(p.actor_id)
	if body != null and p.status != "suspended": body.stop_agent_work()
	p.status = status
	p.version = int(p.get("version", 1)) + 1
	# Cancelling a suspended original goal does not cancel its independent delivery.
	for task in world.interruptions.tasks.values():
		if task.get("resume_project") == p.id: task.resume_project = ""
	return true

func to_dict() -> Dictionary:
	return {"projects": projects.duplicate(true), "suggestions": suggestions.duplicate(true)}

func validate(v: Variant) -> bool:
	if not v is Dictionary or v.size() != 2 or not v.get("projects") is Dictionary or not v.get("suggestions") is Dictionary: return false
	var actors := {}
	for id in v.projects:
		var p: Variant = v.projects[id]
		if not p is Dictionary or p.get("id") != id or not world.assets.exists(str(p.get("actor_id", ""))) or not valid_plan(p.get("plan")): return false
		if p.get("status") not in ["active", "suspended", "completed", "cancelled", "expired"] or not _count(p.get("gold"), 0, 1000000000) or not _items(p.get("items"), true) or not _count(p.get("deadline"), 0, 9007199254740991) or not _count(p.get("created"), 0, 9007199254740991): return false
		if not p.get("steps") is Dictionary or p.steps.size() != p.plan.steps.size(): return false
		if p.status in ["active", "suspended"]:
			if actors.has(p.actor_id): return false
			actors[p.actor_id] = true
		elif int(p.gold) != 0 or p.items.values().any(func(n): return int(n) != 0): return false
		for step in p.plan.steps:
			var state: Variant = p.steps.get(step.id)
			if not state is Dictionary or state.get("status") not in ["pending", "waiting", "blocked", "done"] or not state.get("result") is Dictionary or not state.get("error") is String or not _count(state.get("attempts"), 0, 9007199254740991): return false
			if p.status == "completed" and state.status != "done": return false
			if state.status != "pending":
				for dep in step.depends_on:
					if p.steps.get(dep, {}).get("status") != "done": return false
			if state.status == "done" and state.result.get("ok") != true: return false
			if state.status == "waiting" and step.capability not in ["move", "wait_production", "wait_construction", "set_policy"]: return false
		if int(p.deadline) != int(p.created) + int(p.plan.deadline_minutes): return false
		if not _count(p.get("version", 1), 1, 1000000) or not p.get("changes", []) is Array: return false
	for actor in v.suggestions:
		var entry: Variant = v.suggestions[actor]
		if not world.assets.exists(actor) or not entry is Dictionary or not entry.get("text") is String or entry.text.length() > 500 or not _count(entry.get("expires"), 0, 9007199254740991): return false
	return true

func restore(v: Dictionary) -> void:
	projects = v.projects.duplicate(true)
	suggestions = v.suggestions.duplicate(true)
	for p in projects.values():
		for step in p.plan.steps:
			if step.capability == "move" and p.steps[step.id].status == "waiting": p.steps[step.id].status = "pending"

static func _id(v: Variant) -> bool: return v is String and not v.is_empty() and v.length() <= 100
static func _number(v: Variant, lo: float, hi: float) -> bool: return (v is int or v is float) and is_finite(float(v)) and v >= lo and v <= hi
static func _count(v: Variant, lo: int, hi: int) -> bool: return _number(v, lo, hi) and floorf(float(v)) == float(v)
static func _items(v: Variant, zero := false) -> bool:
	if not v is Dictionary or v.size() > 32: return false
	for id in v:
		if not _id(id) or not _count(v[id], 0 if zero else 1, 1000000): return false
	return true
static func _error(code: String) -> Dictionary: return {"ok": false, "error": code}


func revise(actor: String, id: String, version: int, plan: Dictionary, source: String) -> Dictionary:
	var p: Dictionary = projects.get(id, {})
	if p.get("actor_id") != actor or p.get("status") not in ["active", "suspended"] or int(p.get("version", 1)) != version: return _error("project_changed")
	if not valid_plan(plan) or source not in ["dialogue", "self_review"]: return _error("invalid_project")
	if plan.budget != p.plan.budget or plan.materials != p.plan.materials: return _error("escrow_change_requires_new_project")
	if int(p.created) + int(plan.deadline_minutes) <= world.minute(): return _error("deadline_passed")
	var next := {}
	for step in plan.steps: next[step.id] = step
	for step in p.plan.steps:
		var state: Dictionary = p.steps[step.id]
		if state.status in ["done", "waiting"] or step.capability in ["claim", "deliver"]:
			if next.get(step.id) != step: return _error("committed_step_immutable")
	var states := {}
	for step in plan.steps:
		var same: bool = p.plan.steps.any(func(old): return old == step)
		states[step.id] = p.steps[step.id].duplicate(true) if same else {"status": "pending", "result": {}, "error": "", "attempts": 0}
	var checked := _check_commissions(actor, plan, states)
	if not checked.ok: return checked
	if not p.has("changes"): p.changes = []
	p.changes.append({"version": int(p.get("version", 1)), "source": source, "minute": world.minute(), "previous_plan": p.plan.duplicate(true)})
	p.version = int(p.get("version", 1)) + 1
	p.plan = plan.duplicate(true)
	p.steps = states
	p.deadline = int(p.created) + int(plan.deadline_minutes)
	return {"ok": true, "project_id": id, "version": p.version, "message": "后续计划已修改，已承诺的订单与合同保持有效。"}
