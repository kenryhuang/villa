extends RefCounted

const Rules = preload("res://scripts/systems/npc_project_system.gd")
const SITES := {"fishing": Vector2(-39.5, 106.5), "golf": Vector2(-98.5, 103.5)}
const TOOLS := ["propose_activity", "enroll_activity", "leave_activity", "cancel_activity"]
var world: Node
var events := {}
var receipts := {}
var gameplay := {}
var sequence := 0

func configure(owner: Node) -> void: world = owner

static func valid_terms(a: Variant) -> bool:
	return a is Dictionary and a.size() == 10 and a.get("kind") in SITES and Rules._count(a.get("starts_in"), 60, 1080) and Rules._count(a.get("duration"), 120, 1080) and Rules._count(a.get("capacity"), 2, 16) and Rules._count(a.get("minimum"), 1, int(a.capacity)) and Rules._count(a.get("ticket"), 0, 50) and Rules._count(a.get("sponsor"), 0, 1000) and Rules._count(a.get("reward"), 0, 100) and Rules._count(a.get("food_quantity"), 1, int(a.capacity)) and Rules._count(a.get("food_price"), 1, 100)

static func valid_command(tool: String, a: Dictionary) -> bool:
	if tool == "propose_activity": return valid_terms(a)
	return tool in ["enroll_activity", "leave_activity", "cancel_activity"] and a.size() == 2 and Rules._id(a.get("event_id")) and Rules._count(a.get("version"), 1, 1000000)

func command(actor: String, tool: String, a: Dictionary, key: String) -> Dictionary:
	if not world.assets.exists(actor) or key.is_empty() or not valid_command(tool, a): return _error("invalid_activity_command")
	var intent := {"actor": actor, "tool": tool, "arguments": a.duplicate(true)}
	if receipts.has(key): return receipts[key].result.duplicate(true) if receipts[key].intent == intent else _error("idempotency_conflict")
	var result := _error("activity_unavailable")
	if tool == "propose_activity": result = propose(actor, "event-" + key.sha256_text().substr(0, 20), a)
	else:
		var e: Dictionary = events.get(a.event_id, {})
		if e.is_empty() or int(e.version) != int(a.version): return _error("activity_changed")
		match tool:
			"enroll_activity": result = enroll(actor, e)
			"leave_activity": result = leave(actor, e)
			"cancel_activity":
				if actor == e.owner and e.status in ["enrolling", "live"]: _close(e, "cancelled"); result = {"ok": true, "message": "活动取消，剩余资金和物资按条款退还。"}
	receipts[key] = {"intent": intent, "result": result.duplicate(true)}
	return result

func propose(actor: String, id: String, a: Dictionary) -> Dictionary:
	if not valid_terms(a) or events.has(id): return _error("invalid_activity")
	var start: int = world.minute() + int(a.starts_in)
	var end := start + int(a.duration)
	if events.values().any(func(e): return e.terms.kind == a.kind and e.status in ["enrolling", "live"] and start < int(e.end) and end > int(e.start)): return _error("venue_reserved")
	var procurement := int(a.food_quantity) * int(a.food_price)
	if int(a.sponsor) < procurement + int(a.reward) or not world.assets.can_apply(actor, {}, -int(a.sponsor)): return _error("activity_requires_actual_funding")
	if actor == "village_public" and (int(a.sponsor) > 500 or world.public_plans.budget().daily_remaining < int(a.sponsor)): return _error("public_activity_budget")
	world.board.demand(id, actor, "bread", int(a.food_quantity))
	var result: Dictionary = world.board.publish(actor, id, {"demand_id": id, "item_id": "bread", "quantity": int(a.food_quantity), "unit_reward": int(a.food_price), "kind": "purchase", "deadline_minutes": int(a.starts_in), "max_claims": 4})
	if not result.ok: world.board.demands.erase(id); return result
	if not world.assets.apply(actor, {}, -(int(a.sponsor) - procurement)):
		world.board.cancel(actor, id); return _error("activity_budget_changed")
	events[id] = {"id": id, "owner": actor, "terms": a.duplicate(true), "version": 1, "created": world.minute(), "start": start, "end": end, "status": "enrolling", "cash": int(a.sponsor) - procurement, "procurement": procurement, "received": 0, "food": 0, "served": 0, "food_returned": 0, "paid_reward": 0, "owner_return": 0, "participants": {}, "reason": "", "winner_proof": ""}
	for npc in world.session.agent_runtime.registry.get_agent_ids(): world.work._wake([actor, npc], actor)
	return {"ok": true, "event_id": id, "message": "场地已预约，赞助款与食品采购已托管；报名由每位参与者自己确认，门票未售出前不能支出。"}

func enroll(actor: String, e: Dictionary) -> Dictionary:
	if e.status != "enrolling" or world.minute() >= int(e.start): return _error("enrollment_closed")
	if e.participants.has(actor): return _error("already_enrolled")
	if e.participants.size() >= int(e.terms.capacity): return _error("activity_full")
	if actor != "player" and not world.society.residents.has(actor): return _error("resident_required")
	if world.work.occupied(actor): return _error("participant_busy")
	if not world.assets.apply(actor, {}, -int(e.terms.ticket)): return _error("ticket_unaffordable")
	e.cash = int(e.cash) + int(e.terms.ticket)
	e.participants[actor] = {"actor": actor, "joined": world.minute(), "ticket": int(e.terms.ticket), "refunded": 0, "state": "enrolled", "arrived": -1, "consumed": false, "last_minute": world.minute(), "role": "participant" if actor == "player" else "spectator"}
	e.version = int(e.version) + 1
	return {"ok": true, "message": "已报名；请按时到场。NPC 仅观赛，不生成比赛成绩。活动取消或未到场时退票。"}

func leave(actor: String, e: Dictionary) -> Dictionary:
	var p: Dictionary = e.participants.get(actor, {})
	if p.is_empty() or p.state != "enrolled" or e.status != "enrolling": return _error("cannot_withdraw_after_attendance")
	if not world.assets.apply(actor, {}, int(p.ticket)): return _error("ticket_refund_failed")
	e.cash = int(e.cash) - int(p.ticket); p.refunded = int(p.ticket); p.state = "withdrawn"; e.version = int(e.version) + 1
	return {"ok": true, "message": "已退出并退还门票。"}

func advance() -> void:
	if world.get_tree().paused: return
	for e in events.values():
		if e.status not in ["enrolling", "live"]: continue
		var c: Dictionary = world.board.commissions[e.id]
		var incoming := int(c.delivered) - int(e.received)
		if incoming > 0 and world.assets.apply(e.owner, {"bread": -incoming}, 0): e.received = int(e.received) + incoming; e.food = int(e.food) + incoming
		if e.status == "enrolling":
			_resident_choices(e)
			if world.minute() >= int(e.start):
				var count: int = e.participants.values().filter(func(p): return p.state == "enrolled").size()
				if count < int(e.terms.minimum) or int(e.food) < mini(count, int(e.terms.food_quantity)): _close(e, "cancelled"); e.reason = "报名不足或食品未按时交付"; continue
				e.status = "live"; e.version = int(e.version) + 1
		for p in e.participants.values(): _visit(e, p)
		if world.minute() >= int(e.end): _close(e, "finished")

func _resident_choices(e: Dictionary) -> void:
	# Named agents decide through their own model. Ordinary residents use their own
	# interest, affordability, distance and competing schedules, preserving identity.
	if world.minute() >= int(e.start) - 10: return
	for r in world.society.residents.values():
		if r.id in world.society.focus or e.participants.has(r.id): continue
		if absi(hash(str(r.id) + ":" + str(e.id))) % 4 != 0: continue
		var distance := Vector2(r.position.x, r.position.z).distance_to(SITES[e.terms.kind])
		if distance > 150 or world.assets.current().available_gold(r.id) < int(e.terms.ticket) + 60: continue
		enroll(r.id, e)

func busy(actor: String) -> bool:
	return events.values().any(func(e): return e.status in ["enrolling", "live"] and e.participants.get(actor, {}).get("state") in ["enrolled", "attended"])

func pending(actor: String) -> bool:
	return events.values().any(func(e): return e.status == "enrolling" and not e.participants.has(actor) and e.owner != actor)

func _visit(e: Dictionary, p: Dictionary) -> void:
	if p.state not in ["enrolled", "attended"] or world.minute() < int(e.start) - 60: return
	var target: Vector2 = SITES[e.terms.kind]
	var body: Node3D = world.actor(p.actor)
	var arrived := false
	if p.actor == "player": arrived = Vector2(body.position.x, body.position.z).distance_to(target) <= 6
	elif body != null: arrived = world.work.walk(p, p.actor, Vector3(target.x, Farm3DTerrainProfile.surface_height(target.x, target.y), target.y))
	else:
		var r: Dictionary = world.society.residents[p.actor]
		var current := Vector2(r.position.x, r.position.z)
		var elapsed := mini(180, maxi(0, world.minute() - int(p.last_minute)))
		for minute in elapsed:
			if current.distance_to(target) <= 2: break
			var grid: GridSystem = world.session.grid
			var path: Array = world.society.paths.find_path_cells(grid.world_to_grid(current.x, current.y), grid.world_to_grid(target.x, target.y))
			if path.is_empty(): break
			current = current.move_toward(target if path.size() < 2 else grid.grid_to_world(path[1].x, path[1].y), 1.5)
			r.position = {"x": current.x, "z": current.y}
		arrived = current.distance_to(target) <= 2
		r.state = "活动观众" if arrived else "前往活动场地"
	p.last_minute = world.minute()
	if not arrived or e.status != "live" or p.state == "attended": return
	p.state = "attended"; p.arrived = world.minute()
	if int(e.food) > 0:
		e.food = int(e.food) - 1; e.served = int(e.served) + 1; p.consumed = true
	if p.actor != "player": world.work._relationship({"id": "social:" + str(e.id) + ":" + str(p.actor)}, [p.actor, e.owner], 1)

func begin_gameplay(kind: String) -> String:
	sequence += 1
	var id := "%s-%d" % [kind, sequence]
	gameplay[id] = {"id": id, "kind": kind, "started": world.minute(), "completed": -1, "result": {}, "status": "started"}
	return id

func finish_gameplay(id: String, kind: String, result: Dictionary) -> void:
	var proof: Dictionary = gameplay.get(id, {})
	if proof.is_empty() or proof.status != "started" or proof.kind != kind: return
	if kind == "golf" and (not result.get("scores") is Array or result.scores.size() != 7 or result.scores.any(func(n): return not Rules._count(n, 1, 100000))): return
	if kind == "fishing" and (not Rules._id(result.get("item_id")) or result.get("quantity") != 1): return
	proof.status = "completed"; proof.completed = world.minute(); proof.result = result.duplicate(true)
	for e in events.values():
		var p: Dictionary = e.participants.get("player", {})
		if e.status != "live" or e.terms.kind != kind or p.get("state") != "attended" or int(proof.started) < int(e.start) or int(proof.completed) >= int(e.end) or not e.winner_proof.is_empty(): continue
		if int(e.cash) < int(e.terms.reward) or not world.assets.apply("player", {}, int(e.terms.reward)): continue
		e.cash = int(e.cash) - int(e.terms.reward); e.paid_reward = int(e.terms.reward); e.winner_proof = id

func _close(e: Dictionary, status: String) -> void:
	world.board.cancel(e.owner, e.id)
	for p in e.participants.values():
		if p.state == "withdrawn" or int(p.refunded) > 0: continue
		if status == "cancelled" or p.state != "attended":
			if world.assets.apply(p.actor, {}, int(p.ticket)): e.cash = int(e.cash) - int(p.ticket); p.refunded = int(p.ticket); p.state = "refunded"
	if not world.assets.apply(e.owner, {"bread": int(e.food)}, int(e.cash)): return
	e.owner_return = int(e.cash); e.cash = 0; e.food_returned = int(e.food); e.food = 0; e.status = status; e.version = int(e.version) + 1

func public_cost_today() -> int:
	var total := 0
	for e in events.values():
		if e.owner == "village_public" and int(e.created) / 1080 == world.minute() / 1080: total += int(e.terms.sponsor) - int(e.owner_return) - int(world.board.commissions.get(e.id, {}).get("refunded", 0))
	return maxi(0, total)

func context() -> Dictionary:
	return {"events": events.values().filter(func(e): return e.status in ["enrolling", "live"]).map(func(e): return {"id": e.id, "owner": e.owner, "terms": e.terms, "start": e.start, "end": e.end, "version": e.version, "status": e.status, "food_ready": e.food, "enrolled": e.participants.keys(), "site": {"x": SITES[e.terms.kind].x, "z": SITES[e.terms.kind].y}}), "rules": "Events are voluntary. Own sponsor cash funds procurement and one participation reward; never spend projected ticket income. Capacity and site are exclusive in time. NPCs may independently enroll as spectators only, decline or leave before start. Busy actors cannot enroll. Walk to the site; only actual arrival consumes food. Player reward requires an actual completed seven-hole round or landed fish begun during the event; no tool can submit a score. Insufficient enrollment or food cancels/refunds; fulfilled supplier deliveries are not clawed back."}

func to_dict() -> Dictionary: return {"version": 1, "events": events.duplicate(true), "receipts": receipts.duplicate(true), "gameplay": gameplay.duplicate(true), "sequence": sequence}
func restore(v: Dictionary) -> void:
	events = v.get("events", {}).duplicate(true); receipts = v.get("receipts", {}).duplicate(true); gameplay = v.get("gameplay", {}).duplicate(true); sequence = int(v.get("sequence", 0))

func validate(v: Variant, board: Dictionary) -> bool:
	if not v is Dictionary or v.size() != 5 or v.get("version") != 1 or not v.get("events") is Dictionary or not v.get("receipts") is Dictionary or not v.get("gameplay") is Dictionary or not Rules._count(v.get("sequence"), 0, 9007199254740991): return false
	for proof in v.gameplay.values():
		if not proof is Dictionary or proof.get("kind") not in SITES or proof.get("status") not in ["started", "completed"] or not Rules._count(proof.get("started"), 0, 9007199254740991) or not proof.get("result") is Dictionary: return false
		if proof.status == "completed" and not Rules._count(proof.get("completed"), int(proof.started), 9007199254740991): return false
		if proof.status == "completed":
			if proof.kind == "golf" and (not proof.result.get("scores") is Array or proof.result.scores.size() != 7 or proof.result.scores.any(func(n): return not Rules._count(n, 1, 100000))): return false
			if proof.kind == "fishing" and (proof.result.get("quantity") != 1 or not Rules._id(proof.result.get("item_id"))): return false
		elif not proof.result.is_empty() or proof.get("completed") != -1: return false
	var awarded := {}
	for e in v.events.values():
		if not e is Dictionary or not valid_terms(e.get("terms")) or not Rules._id(e.get("owner")) or not board.commissions.has(e.get("id")) or e.get("status") not in ["enrolling", "live", "finished", "cancelled"] or not e.get("participants") is Dictionary: return false
		for field in ["created", "start", "end", "version", "cash", "procurement", "received", "food", "served", "food_returned", "paid_reward", "owner_return"]:
			if not Rules._count(e.get(field), 0, 9007199254740991): return false
		if int(e.start) != int(e.created) + int(e.terms.starts_in) or int(e.end) != int(e.start) + int(e.terms.duration) or e.participants.size() > int(e.terms.capacity): return false
		var tickets := 0; var consumed := 0
		for p in e.participants.values():
			if not p is Dictionary or p.get("state") not in ["enrolled", "attended", "withdrawn", "refunded"] or p.get("ticket") != e.terms.ticket or not Rules._count(p.get("refunded"), 0, int(p.ticket)) or not p.get("consumed") is bool: return false
			tickets += int(p.ticket) - int(p.refunded); consumed += int(p.consumed)
			if p.get("role") != ("participant" if p.get("actor") == "player" else "spectator"): return false
		if int(e.cash) + int(e.paid_reward) + int(e.owner_return) != int(e.terms.sponsor) - int(e.procurement) + tickets or int(e.food) + int(e.served) + int(e.food_returned) != int(e.received) or consumed != int(e.served): return false
		var c: Dictionary = board.commissions[e.id]
		if c.actor_id != e.owner or c.terms.item_id != "bread" or int(c.terms.quantity) != int(e.terms.food_quantity) or int(e.procurement) != int(e.terms.food_quantity) * int(e.terms.food_price) or int(e.received) > int(c.delivered): return false
		if int(e.paid_reward) > 0:
			var proof: Dictionary = v.gameplay.get(e.get("winner_proof"), {})
			if proof.get("status") != "completed" or proof.kind != e.terms.kind or int(proof.started) < int(e.start) or int(proof.completed) >= int(e.end) or int(e.paid_reward) != int(e.terms.reward): return false
			if awarded.has(e.winner_proof) or not e.participants.has("player") or e.participants.player.get("arrived", -1) < int(e.start): return false
			awarded[e.winner_proof] = true
	return true

static func _error(code: String) -> Dictionary: return {"ok": false, "error": code}
