extends RefCounted

## Player-authorized cargo and wages stay in escrow, separate from NPC project goods.
## Only physical arrival may advance pickup/delivery. Closing a UI never cancels a job.
const Project = preload("res://scripts/systems/npc_project_system.gd")
const LIVE := ["queued", "pickup", "delivering", "returning", "refund_pending"]
const LIMIT := 3
var world: Node
var tasks: Dictionary = {}
var drafts: Dictionary = {}
var _busy := false

func configure(owner: Node) -> void:
	world = owner

static func valid_terms(a: Variant) -> bool:
	return a is Dictionary and a.size() == 9 and a.get("task_id") is String and a.task_id.length() <= 100 and Project._count(a.get("version"), 0, 1000000) and Project._id(a.get("recipient_id")) and Project._id(a.get("item_id")) and Project._count(a.get("quantity"), 1, 100) and Project._count(a.get("reward"), 0, 1000000) and Project._count(a.get("deadline_minutes"), 1, 1080) and a.get("schedule") in ["now", "after_step", "queue"] and a.get("note") is String and a.note.length() <= 500

func destinations() -> Array:
	# A shared public receiving counter is a real, reachable place in the current map.
	var pos: Vector3 = world.session.MarketSite.reachable_counter(world.session.grid, world.session.player.position, world.session.market_site)
	if not pos.is_finite(): return []
	return [{"recipient_id": "village_inn", "name": "旅店收货处（市场柜台）", "x": pos.x, "z": pos.z}]

func load_count(actor: String) -> int:
	var count := 0
	for t in tasks.values():
		if t.actor_id == actor and t.status in LIVE: count += 1
	for c in world.board.claims.values():
		if c.actor_id == actor and c.status == "active": count += 1
	return count

func running(actor: String) -> Dictionary:
	for t in tasks.values():
		if t.actor_id == actor and t.status in ["pickup", "delivering", "returning", "refund_pending"] and t.get("started", false): return t
	return {}

func context(actor: String) -> Dictionary:
	return {"tasks": tasks.values().filter(func(t): return t.actor_id == actor).slice(-8).duplicate(true), "destinations": destinations(), "available_slots": maxi(0, LIMIT - load_count(actor)), "minimum_travel_minutes": minimum_travel_minutes(actor), "rules": "Delivery is an optional NPC agreement. Ask for missing item, quantity, recipient, reward (zero allowed), deadline and schedule before propose_delivery. Player must confirm the card before any cargo or reward is escrowed. task_id empty/version 0 creates; use exact task version to renegotiate before pickup. now interrupts only safe steps; after_step waits for physical movement; queue waits for main project. Max one executing task and three accepted commitments including commission claims. Arrive at player for pickup then the named public receiving counter. Only actual delivery pays. Accepted jobs persist after dialogue closes; cancellation after pickup requires physically returning cargo. Do not use a new proposal to cancel an existing job. revise_project changes only uncommitted future steps with exact project version; existing contracts/orders remain binding."}

func propose(actor: String, id: String, terms: Dictionary) -> Dictionary:
	if not valid_terms(terms) or world.actor(actor) == null or actor == "player": return _error("invalid_delivery")
	if int(terms.deadline_minutes) < minimum_travel_minutes(actor): return _error("delivery_deadline_unreachable")
	if destinations().filter(func(d): return d.recipient_id == terms.recipient_id).is_empty() or world.session.market.get_item_state(terms.item_id).is_empty(): return _error("unknown_destination_or_item")
	if terms.task_id.is_empty():
		if int(terms.version) != 0 or load_count(actor) >= LIMIT: return _error("task_capacity")
	else:
		var old: Dictionary = tasks.get(terms.task_id, {})
		if old.get("actor_id") != actor or old.get("status") not in ["queued", "pickup"] or int(old.get("version", -1)) != int(terms.version): return _error("task_changed")
	if drafts.has(id): return {"ok": drafts[id].actor_id == actor and drafts[id].terms == terms, "draft_id": id}
	# One outstanding card per actor; a later negotiation invalidates the previous card.
	for old_id in drafts.keys():
		if drafts[old_id].actor_id == actor: drafts.erase(old_id)
	drafts[id] = {"id": id, "actor_id": actor, "terms": terms.duplicate(true), "expires": world.minute() + 180}
	return {"ok": true, "draft_id": id, "message": "配送条款已拟定，关闭对话后请核对确认。尚未收取货物或报酬。"}

func accept(id: String) -> Dictionary:
	if _busy: return _error("transaction_busy")
	# Receipt IDs survive reload and make repeated confirmation harmless.
	for t in tasks.values():
		if id in t.get("confirmations", []): return {"ok": true, "task_id": t.id, "duplicate": true}
	var draft: Dictionary = drafts.get(id, {})
	if draft.is_empty() or world.minute() >= int(draft.expires): return _error("draft_expired")
	var a: Dictionary = draft.terms
	if int(a.deadline_minutes) < minimum_travel_minutes(draft.actor_id): return _error("delivery_deadline_unreachable")
	var old: Dictionary = tasks.get(a.task_id, {})
	if not a.task_id.is_empty() and (old.get("actor_id") != draft.actor_id or old.get("status") not in ["queued", "pickup"] or int(old.get("version", -1)) != int(a.version)): return _error("task_changed")
	if a.task_id.is_empty() and load_count(draft.actor_id) >= LIMIT: return _error("task_capacity")
	var delta := {a.item_id: -int(a.quantity)}
	var gold := -int(a.reward)
	if not old.is_empty():
		delta[old.terms.item_id] = int(delta.get(old.terms.item_id, 0)) + int(old.cargo)
		gold += int(old.gold)
	_busy = true
	if not world.assets.apply("player", delta, gold):
		_busy = false
		return _error("delivery_assets_or_capacity")
	var task_id := "delivery-" + id.sha256_text().substr(0, 24) if old.is_empty() else str(old.id)
	var confirmations: Array = old.get("confirmations", []).duplicate()
	confirmations.append(id)
	var history: Array = old.get("history", []).duplicate(true)
	history.append({"minute": world.minute(), "source": "player_confirmation", "terms": a.duplicate(true)})
	var resume_id := str(old.get("resume_project", ""))
	var phase := str(old.get("status", "queued"))
	tasks[task_id] = {"id": task_id, "actor_id": draft.actor_id, "terms": a.duplicate(true), "status": phase, "version": int(old.get("version", 0)) + 1, "deadline": world.minute() + int(a.deadline_minutes), "created": world.minute(), "cargo": int(a.quantity), "gold": int(a.reward), "resume_project": resume_id, "reason": "", "confirmations": confirmations, "history": history, "movement": {}, "terminal_status": "cancelled", "started": old.get("started", false)}
	drafts.erase(id)
	_busy = false
	return {"ok": true, "task_id": task_id, "message": "配送已接受，货物和报酬已托管；恢复游戏后按约定时机出发。"}

func cancel(requester: String, id: String, version: int) -> Dictionary:
	var t: Dictionary = tasks.get(id, {})
	if _busy or t.is_empty() or requester not in ["player", t.actor_id]: return _error("not_task_party")
	if int(t.version) != version: return _error("task_changed")
	if t.status not in LIVE: return {"ok": true}
	t.version = int(t.version) + 1
	t.terminal_status = "cancelled"
	if t.status in ["delivering", "returning"]:
		t.status = "returning"
		t.movement = {}
	else: t.status = "refund_pending"
	return {"ok": true, "message": "取消请求已接受；已取货的配送需先返回玩家，货物与未付报酬随后退还。"}

func advance() -> void:
	if _busy or world.get_tree().paused: return
	_busy = true
	for id in drafts.keys():
		if int(drafts[id].expires) <= world.minute(): drafts.erase(id)
	for t in tasks.values():
		if t.status not in LIVE: continue
		if world.minute() >= int(t.deadline) and t.status in ["queued", "pickup", "delivering"]:
			t.terminal_status = "expired"
			t.status = "returning" if t.status == "delivering" else "refund_pending"
			t.movement = {}
		if t.status == "queued":
			if not running(t.actor_id).is_empty() or world.session.agent_runtime.farm_registry.has_pending_work(t.actor_id): continue
			var p: Dictionary = world.projects.active(t.actor_id)
			if not p.is_empty():
				if t.terms.schedule == "queue" or not _interruptible(p, t.terms.schedule): continue
				p.status = "suspended"
				p.version = int(p.get("version", 1)) + 1
				t.resume_project = p.id
			var body: Node3D = world.actor(t.actor_id)
			if body == null: continue
			body.stop_agent_work()
			t.status = "pickup"
			t.started = true
			t.version = int(t.version) + 1
		if t.status == "pickup":
			if _walk(t, world.session.player.position):
				t.status = "delivering"
				t.version = int(t.version) + 1
				t.movement = {}
		elif t.status == "delivering":
			var sites := destinations()
			if sites.is_empty(): t.reason = "no_route"; continue
			var site: Dictionary = sites[0]
			var target := Vector3(site.x, Farm3DTerrainProfile.surface_height(site.x, site.z), site.z)
			if _walk(t, target): _deliver(t)
		elif t.status == "returning":
			if _walk(t, world.session.player.position): t.status = "refund_pending"
		if t.status == "refund_pending":
			if world.assets.apply("player", {t.terms.item_id: int(t.cargo)}, int(t.gold)):
				t.cargo = 0
				t.gold = 0
				_finish(t, t.terminal_status)
			else: t.reason = "refund_capacity"
	_busy = false

func _interruptible(p: Dictionary, schedule: String) -> bool:
	for step in p.plan.steps:
		var state: Dictionary = p.steps[step.id]
		if state.status == "waiting" and step.capability == "move" and schedule == "after_step": return false
		if step.capability == "build" and state.status == "done":
			var b: BuildingInstance = world.building(state.result.get("building_id", ""))
			if b != null and not b.is_construction_complete(): return false
	return true

func _walk(t: Dictionary, target: Vector3) -> bool:
	var body: Node3D = world.actor(t.actor_id)
	if body == null: t.reason = "actor_unavailable"; return false
	if Vector2(body.position.x, body.position.z).distance_to(Vector2(target.x, target.z)) <= 1.5:
		body.stop_agent_work()
		t.reason = ""
		return true
	var last: Dictionary = t.movement
	if last.is_empty() or Vector2(last.x, last.z).distance_to(Vector2(target.x, target.z)) > 1.0 or not body.has_agent_work_target():
		if not body.begin_agent_work(target): t.reason = "no_route"; return false
		t.movement = {"x": target.x, "z": target.z}
	t.reason = "walking"
	return false

func _deliver(t: Dictionary) -> void:
	var recipient := str(t.terms.recipient_id)
	var items := {t.terms.item_id: int(t.cargo)}
	if not world.assets.can_apply(recipient, items, 0) or not world.assets.can_apply(t.actor_id, {}, int(t.gold)): t.reason = "recipient_capacity"; return
	var before: Dictionary = world.assets.snapshot(recipient)
	if not world.assets.apply(recipient, items, 0): return
	if not world.assets.apply(t.actor_id, {}, int(t.gold)):
		world.assets.restore(recipient, before)
		return
	t.delivery_receipt = {"id": t.id + ":delivery", "minute": world.minute(), "recipient_id": recipient, "items": items, "reward": t.gold}
	t.cargo = 0
	t.gold = 0
	_finish(t, "completed")

func _finish(t: Dictionary, status: String) -> void:
	t.status = status
	t.version = int(t.version) + 1
	t.reason = ""
	var body: Node3D = world.actor(t.actor_id)
	if body != null and t.started: body.stop_agent_work()
	var p: Dictionary = world.projects.projects.get(t.resume_project, {})
	if p.get("status") == "suspended":
		p.status = "active"
		p.version = int(p.get("version", 1)) + 1
		for step in p.plan.steps:
			if step.capability == "move" and p.steps[step.id].status == "waiting": p.steps[step.id].status = "pending"
		# projects.advance rechecks deadlines, commissions and committed production.

func to_dict() -> Dictionary:
	return {"version": 1, "tasks": tasks.duplicate(true)}

func validate(v: Variant, project_records: Dictionary) -> bool:
	v = preload("res://scripts/ai_agent/agent_protocol.gd")._normalize_json_numbers(v)
	if not v is Dictionary or v.size() != 2 or v.get("version") != 1 or not v.get("tasks") is Dictionary: return false
	var active := {}
	var suspended := {}
	var counts := {}
	for id in v.tasks:
		var t: Variant = v.tasks[id]
		if not t is Dictionary or t.get("id") != id or not Project._id(id) or t.get("actor_id") not in ["lao_li", "farmer_ahe", "xuezhe_lin"] or not valid_terms(t.get("terms")): return false
		if t.terms.recipient_id != "village_inn" or world.session.market.get_item_state(t.terms.item_id).is_empty(): return false
		if t.get("status") not in LIVE + ["completed", "cancelled", "expired"] or t.get("terminal_status") not in ["cancelled", "expired"]: return false
		if not Project._count(t.get("version"), 1, 1000000) or not Project._count(t.get("created"), 0, 9007199254740991) or not Project._count(t.get("deadline"), 0, 9007199254740991) or int(t.deadline) != int(t.created) + int(t.terms.deadline_minutes): return false
		if not t.get("started") is bool or (t.status == "queued" and t.started) or (t.status in ["pickup", "delivering", "returning", "completed"] and not t.started): return false
		if not t.get("resume_project") is String or not t.get("reason") is String or not t.get("movement") is Dictionary or not t.get("history") is Array or not t.get("confirmations") is Array or t.confirmations.is_empty(): return false
		if not t.movement.is_empty() and not world.position_valid(t.movement): return false
		if not Project._count(t.get("cargo"), 0, int(t.terms.quantity)) or not Project._count(t.get("gold"), 0, int(t.terms.reward)): return false
		if t.status in LIVE:
			if int(t.cargo) != int(t.terms.quantity) or int(t.gold) != int(t.terms.reward): return false
			counts[t.actor_id] = int(counts.get(t.actor_id, 0)) + 1
			if int(counts[t.actor_id]) > LIMIT: return false
			if t.started:
				if active.has(t.actor_id): return false
				active[t.actor_id] = true
			if not t.resume_project.is_empty():
				var p: Dictionary = project_records.get(t.resume_project, {})
				if p.get("actor_id") != t.actor_id or p.get("status") != "suspended" or suspended.has(t.resume_project): return false
				suspended[t.resume_project] = true
		elif int(t.cargo) != 0 or int(t.gold) != 0: return false
		if t.status == "completed":
			var r: Variant = t.get("delivery_receipt")
			if not r is Dictionary or r.get("id") != str(id) + ":delivery" or r.get("recipient_id") != t.terms.recipient_id or r.get("items") != {t.terms.item_id: int(t.terms.quantity)} or r.get("reward") != t.terms.reward: return false
	for p in project_records.values():
		if p.get("status") == "suspended" and not suspended.has(p.id): return false
	return true

func restore(v: Dictionary) -> void:
	tasks = v.get("tasks", {}).duplicate(true)
	drafts.clear()
	for t in tasks.values(): t.movement = {}

static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}


func minimum_travel_minutes(actor: String) -> int:
	var body: Node3D = world.actor(actor)
	var sites := destinations()
	if body == null or sites.is_empty(): return 1081
	var player: Vector3 = world.session.player.position
	var distance := Vector2(body.position.x, body.position.z).distance_to(Vector2(player.x, player.z)) + Vector2(player.x, player.z).distance_to(Vector2(sites[0].x, sites[0].z))
	return maxi(1, ceili(distance / maxf(.1, float(body.move_speed)) * SeasonSystem.MINUTES_PER_REAL_SECOND))
