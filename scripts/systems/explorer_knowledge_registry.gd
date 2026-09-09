extends RefCounted

const VERSION := 2
const Rules = preload("res://scripts/systems/npc_project_system.gd")
const SITES := {"creek": {"name": "河岸", "x": 28.5, "z": 18.5, "item": "stone"}, "forest": {"name": "西北林地", "x": -32.5, "z": -18.5, "item": "wood"}, "hills": {"name": "西部丘陵", "x": -45.5, "z": 32.5, "item": "stone"}}
const TOOLS := ["offer_intelligence", "buy_intelligence", "share_intelligence", "propose_investigation", "accept_investigation", "cancel_investigation"]
var _private: Dictionary = {}
var _public: Dictionary = {}
var world: Node
var reports: Dictionary = {}
var offers: Dictionary = {}
var grants: Dictionary = {}
var assignments: Dictionary = {}
var results: Dictionary = {}
var samples: Dictionary = {}
var seed := 42

func configure(owner: Node) -> void:
	world = owner
	world.session.agent_runtime.activity_system.completion_guard = physical_completion
	for a in world.session.agent_runtime.activity_system._activities.values():
		if a.status != "in_progress" or a.kind != "travel" or a.payload.get("physical", false) or not SITES.has(a.payload.get("region_id")): continue
		var target := site(a.payload.region_id)
		if target.is_finite(): a.payload.merge({"physical": true, "target": {"x": target.x, "z": target.z}, "worked": 0, "last_minute": world.minute(), "deadline": world.minute() + 1080}, true)


func discover(agent_id: String, discovery_id: String, region_id: String, game_minute: int) -> bool:
	if agent_id.is_empty() or discovery_id.is_empty() or region_id.is_empty() or game_minute < 0:
		return false
	if not _private.has(agent_id):
		_private[agent_id] = {}
	var memories: Dictionary = _private[agent_id]
	if memories.has(discovery_id):
		return false
	memories[discovery_id] = {"discovery_id": discovery_id, "region_id": region_id, "discovered_minute": game_minute, "published": false}
	return true


func publish(agent_id: String, discovery_id: String, game_minute: int) -> bool:
	if not _private.has(agent_id):
		return false
	var memories: Dictionary = _private[agent_id]
	if not memories.has(discovery_id) or _public.has(discovery_id):
		return false
	var record: Dictionary = memories[discovery_id]
	if reports.has(discovery_id):
		record.knowledge_kind = "fact"
		record.fact_basis = reports[discovery_id].evidence_id
	record.published = true
	record["published_minute"] = game_minute
	_public[discovery_id] = record.duplicate(true)
	return true


func is_public(discovery_id: String) -> bool:
	return _public.has(discovery_id)


func get_private(agent_id: String) -> Dictionary:
	return (_private.get(agent_id, {}) as Dictionary).duplicate(true)


func to_dict() -> Dictionary:
	return {"version": VERSION, "private": _private.duplicate(true), "public": _public.duplicate(true), "reports": reports.duplicate(true), "offers": offers.duplicate(true), "grants": grants.duplicate(true), "assignments": assignments.duplicate(true), "results": results.duplicate(true), "samples": samples.duplicate(true), "seed": seed}


func from_dict(value: Dictionary) -> bool:
	value = preload("res://scripts/ai_agent/agent_protocol.gd")._normalize_json_numbers(value)
	if value.get("version") not in [1, VERSION] or not value.get("private") is Dictionary or not value.get("public") is Dictionary:
		return false
	if value.version == VERSION and not validate_extended(value): return false
	_private = (value.private as Dictionary).duplicate(true)
	_public = (value.public as Dictionary).duplicate(true)
	reports = value.get("reports", {}).duplicate(true)
	offers = value.get("offers", {}).duplicate(true)
	grants = value.get("grants", {}).duplicate(true)
	assignments = value.get("assignments", {}).duplicate(true)
	results = value.get("results", {}).duplicate(true)
	samples = value.get("samples", {}).duplicate(true)
	seed = int(value.get("seed", 42))
	return true

func record_statement(source: String, target: String, key: String, text: String) -> void:
	if world == null or not world.assets.exists(source) or not world.assets.exists(target) or text.is_empty(): return
	var id := "statement:" + key
	if not _private.has(target): _private[target] = {}
	if _private[target].has(id): return
	_private[target][id] = {"discovery_id": id, "region_id": "village", "discovered_minute": world.minute(), "published": false, "knowledge_kind": "rumor", "source_actor": source, "expires": world.minute() + 1080, "text": text.left(1000)}
	# Verbatim free disclosure of a complete known report grants knowledge too.
	for report in reports.values():
		if known(source, report.id) and not known(target, report.id) and text.contains(report.text): grant(source, target, report.id, "disclosed:" + key + ":" + str(report.id), 0)

func typed_records(actor: String, full: bool) -> Array:
	var entries := []
	var own: Dictionary = _private.get(actor, {}).duplicate(true)
	own.merge(_public, true)
	for record in own.values():
		if record.get("knowledge_kind") not in ["rumor", "fact", "evidence", "observation"]: continue
		var entry: Dictionary = record.duplicate(true)
		entry.expired = world != null and world.minute() >= int(entry.get("expires", 9007199254740991))
		if not full: entry.erase("text")
		entries.append(entry)
	if world != null and world.environment != null:
		var forecast: Dictionary = world.environment.ensure_day(world.minute() / 1080 + 1).duplicate(true)
		forecast.source = "weather_forecast"; forecast.expires = int(forecast.end); forecast.verified = false
		entries.append(forecast)
	return entries.slice(maxi(0, entries.size() - 24))


func known(actor: String, id: String) -> bool:
	return is_public(id) or _private.get(actor, {}).has(id)

func fresh(id: String) -> bool:
	return reports.has(id) and world != null and world.minute() < int(reports[id].expires)

func site(region: String) -> Vector3:
	if not SITES.has(region) or world == null: return Vector3.INF
	var base := Vector2(SITES[region].x, SITES[region].z)
	var grid: GridSystem = world.session.grid
	var cell := grid.world_to_grid(base.x, base.y)
	for radius in range(4):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var at := cell + Vector2i(dx, dz)
				if not grid.is_navigation_cell_walkable(at): continue
				var point := grid.grid_to_world(at.x, at.y)
				return Vector3(point.x, Farm3DTerrainProfile.surface_height(point.x, point.y), point.y)
	return Vector3.INF

func begin_fieldwork(actor: String, kind: String, region: String, id: String, metadata: Dictionary, duration := 10) -> Dictionary:
	if world == null or kind not in ["travel", "survey"] or not SITES.has(region) or world.work.occupied(actor, str(metadata.get("assignment_id", ""))): return _error("fieldwork_schedule_or_region")
	var body: Node3D = world.actor(actor)
	var target := site(region)
	if body == null or not target.is_finite(): return _error("unreachable_site")
	var path: Array = world.work.paths.find_path_cells(world.session.grid.world_to_grid(body.position.x, body.position.z), world.session.grid.world_to_grid(target.x, target.z))
	if path.is_empty(): return _error("unreachable_site")
	if kind == "survey" and Vector2(body.position.x, body.position.z).distance_to(Vector2(target.x, target.z)) > 2.5: return _error("survey_requires_arrival")
	if kind == "survey" and known(actor, "survey-%s-%d" % [region, world.minute() / 1080]): return _error("already_surveyed_today")
	if kind == "survey" and not world.assets.apply(actor, {"bread": -1}, 0): return _error("survey_supplies_missing")
	var now: int = world.minute()
	var payload := metadata.duplicate(true)
	payload.merge({"physical": true, "region_id": region, "tool_name": kind, "target": {"x": target.x, "z": target.z}, "worked": 0, "last_minute": now, "deadline": now + 1080}, true)
	if not world.session.agent_runtime.activity_system.start(actor, kind, id, now, now + (20 if kind == "survey" else maxi(10, duration)), payload):
		if kind == "survey": world.assets.apply(actor, {"bread": 1}, 0)
		return _error("fieldwork_busy")
	return {"ok": true, "status": "in_progress", "activity_id": id, "message": "已开始实地调查行程；必须实际到达、投入时间才会得到报告。"}

func physical_completion(activity: Dictionary, minute: int) -> Dictionary:
	var p: Dictionary = activity.payload
	if minute >= int(p.deadline): return {"ready": true, "ok": false, "error": "fieldwork_deadline"}
	var target := Vector3(p.target.x, Farm3DTerrainProfile.surface_height(p.target.x, p.target.z), p.target.z)
	if not world.work.walk(p, activity.agent_id, target): p.last_minute = minute; return {"ready": false}
	if activity.kind == "survey":
		p.worked = int(p.worked) + maxi(0, minute - int(p.last_minute))
		p.last_minute = minute
		if int(p.worked) < 20: return {"ready": false}
		var result := _record_survey(activity)
		if not result.ok: return {"ready": true, "ok": false, "error": result.error}
		p.discovery_id = result.discovery_id
	return {"ready": true, "ok": true}

func advance() -> void:
	if world == null or world.get_tree().paused: return
	for a in world.session.agent_runtime.activity_system._activities.values():
		if a.status != "in_progress" or not a.payload.get("physical", false): continue
		var p: Dictionary = a.payload
		if a.kind == "travel": world.work.walk(p, a.agent_id, Vector3(p.target.x, Farm3DTerrainProfile.surface_height(p.target.x, p.target.z), p.target.z))
		elif a.kind == "survey":
			var body: Node3D = world.actor(a.agent_id)
			if body == null or Vector2(body.position.x, body.position.z).distance_to(Vector2(p.target.x, p.target.z)) > 2.5:
				p.worked = 0
				p.last_minute = world.minute()
	for offer in offers.values():
		if offer.status == "proposed" and world.minute() >= int(offer.expires): offer.status = "expired"
	for assignment in assignments.values(): _advance_assignment(assignment)

func _record_survey(activity: Dictionary) -> Dictionary:
	var region := str(activity.payload.region_id)
	var day := int(activity.started_minute) / 1080
	var id := "survey-%s-%d" % [region, day]
	if known(activity.agent_id, id): return _error("already_surveyed_today")
	var found := (absi(hash("%d:%s:%d" % [seed, region, day])) % 3) != 0
	var body: Node3D = world.actor(activity.agent_id)
	if not reports.has(id):
		reports[id] = {"id": id, "region_id": region, "kind": "observation", "source": activity.agent_id, "evidence_id": activity.activity_id, "minute": world.minute(), "expires": (day + 2) * 1080, "position": {"x": body.position.x, "z": body.position.z}, "item_id": str(SITES[region].item) if found else "", "found": found, "text": "%s现场检查：%s。" % [SITES[region].name, "确认有一份可采集的散落材料，采走后不再重复出现" if found else "本次未发现可用样本，地形观察已记录"]}
	discover(activity.agent_id, id, region, world.minute())
	_private[activity.agent_id][id].evidence_id = activity.activity_id
	_private[activity.agent_id][id].knowledge_kind = "observation"
	_private[activity.agent_id]["evidence:" + activity.activity_id] = {"discovery_id": "evidence:" + activity.activity_id, "region_id": region, "discovered_minute": world.minute(), "published": false, "knowledge_kind": "evidence", "source_actor": activity.agent_id, "evidence_id": activity.activity_id, "expires": int(reports[id].expires)}
	return {"ok": true, "discovery_id": id, "found": reports[id].found}

func collect(actor: String, id: String, key: String) -> Dictionary:
	if key.is_empty(): return _error("missing_idempotency_key")
	var args := {"discovery_id": id}
	if results.has(key): return _replay(key, actor, "collect_sample", args)
	if not fresh(id) or not known(actor, id) or not reports[id].found or samples.has(id): return _error("sample_unavailable")
	var report: Dictionary = reports[id]
	var body: Node3D = world.actor(actor)
	if body == null or Vector2(body.position.x, body.position.z).distance_to(Vector2(report.position.x, report.position.z)) > 3: return _error("sample_requires_arrival")
	if not world.assets.apply(actor, {report.item_id: 1}, 0): return _error("sample_capacity")
	samples[id] = {"actor_id": actor, "minute": world.minute(), "item_id": report.item_id, "key": key}
	var result := {"ok": true, "item_id": report.item_id, "quantity": 1, "message": "现场样本已采集；同一处证据不能重复领取。"}
	results[key] = {"actor_id": actor, "tool": "collect_sample", "arguments": args, "result": result.duplicate(true)}
	return result

func _replay(key: String, actor: String, tool: String, args: Dictionary) -> Dictionary:
	var r: Dictionary = results[key]
	if r.actor_id != actor or r.tool != tool or r.arguments != args: return _error("idempotency_conflict")
	return r.result.duplicate(true)

static func valid_command(tool: String, a: Dictionary) -> bool:
	match tool:
		"propose_investigation": return valid_investigation(a)
		"accept_investigation", "cancel_investigation": return a.size() == 2 and Rules._id(a.get("assignment_id")) and Rules._count(a.get("version"), 1, 1000000)
		"offer_intelligence": return a.size() == 4 and Rules._id(a.get("target_actor_id")) and Rules._id(a.get("discovery_id")) and Rules._count(a.get("price"), 1, 100000) and Rules._count(a.get("ttl"), 10, 1080)
		"buy_intelligence": return a.size() == 2 and Rules._id(a.get("offer_id")) and Rules._count(a.get("version"), 1, 1000000)
		"share_intelligence": return a.size() == 2 and Rules._id(a.get("target_actor_id")) and Rules._id(a.get("discovery_id"))
	return false

func command(actor: String, tool: String, a: Dictionary, key: String) -> Dictionary:
	if world == null or not world.assets.exists(actor) or not valid_command(tool, a) or key.is_empty(): return _error("invalid_knowledge_command")
	if results.has(key): return _replay(key, actor, tool, a)
	var result := _error("unknown_knowledge_command")
	match tool:
		"propose_investigation": result = propose_investigation(actor, "research-" + key.sha256_text().substr(0, 24), a)
		"accept_investigation": result = accept_investigation(actor, a.assignment_id, int(a.version))
		"cancel_investigation": result = cancel_investigation(actor, a.assignment_id, int(a.version))
		"offer_intelligence":
			if not fresh(a.discovery_id) or not known(actor, a.discovery_id) or not world.assets.exists(a.target_actor_id) or actor == a.target_actor_id: return _error("unknown_or_stale_report")
			if known(a.target_actor_id, a.discovery_id): return _error("already_known_or_public")
			var id := "intel-" + key.sha256_text().substr(0, 24)
			offers[id] = {"id": id, "seller": actor, "buyer": a.target_actor_id, "discovery_id": a.discovery_id, "price": int(a.price), "expires": mini(int(reports[a.discovery_id].expires), world.minute() + int(a.ttl)), "version": 1, "status": "proposed"}
			result = {"ok": true, "offer_id": id, "message": "已提出情报交易，仅展示概要；购买确认后才付款并授权报告。"}
			world.work._wake([actor, a.target_actor_id], actor)
		"buy_intelligence": result = purchase(actor, a.offer_id, int(a.version))
		"share_intelligence":
			if not fresh(a.discovery_id) or not known(actor, a.discovery_id) or not world.assets.exists(a.target_actor_id): return _error("unknown_or_stale_report")
			grant(actor, a.target_actor_id, a.discovery_id, "free:" + key, 0)
			result = {"ok": true, "message": "已免费分享报告和位置；对方已知的这份情报不能再收费。"}
	results[key] = {"actor_id": actor, "tool": tool, "arguments": a.duplicate(true), "result": result.duplicate(true)}
	return result

func purchase(actor: String, id: String, version: int) -> Dictionary:
	var offer: Dictionary = offers.get(id, {})
	if offer.is_empty() or offer.buyer != actor or int(offer.version) != version: return _error("stale_or_foreign_intelligence")
	if offer.status == "sold": return {"ok": true, "message": "已购买，无需重复付款。"}
	if offer.status != "proposed" or world.minute() >= int(offer.expires) or not fresh(offer.discovery_id): return _error("intelligence_expired")
	if known(actor, offer.discovery_id): offer.status = "already_known"; return {"ok": true, "price": 0, "message": "已经知道或已公开，无需付款。"}
	if not world.work.transfer({actor: {"items": {}, "gold": -int(offer.price)}, offer.seller: {"items": {}, "gold": int(offer.price)}}): return _error("intelligence_payment_failed")
	grant(offer.seller, actor, offer.discovery_id, id, int(offer.price))
	offer.status = "sold"
	return {"ok": true, "price": int(offer.price), "discovery_id": offer.discovery_id, "message": "情报已成交，报告和地图位置已解锁。"}

func grant(source: String, target: String, id: String, key: String, price: int) -> void:
	if grants.has(key): return
	discover(target, id, reports[id].region_id, world.minute())
	_private[target][id].knowledge_kind = reports[id].kind
	_private[target][id].source_actor = source
	grants[key] = {"source": source, "target": target, "discovery_id": id, "price": price, "minute": world.minute()}

func cards(actor: String, full := false) -> Dictionary:
	var known_reports := []
	for id in reports:
		if not known(actor, id): continue
		var r: Dictionary = reports[id]
		known_reports.append(r.duplicate(true) if full else {"id": id, "region_id": r.region_id, "kind": r.kind, "source": r.source, "minute": r.minute, "expires": r.expires, "summary": "实地材料调查，有实际到访凭据；可能没有发现样本"})
	var proposals := []
	for offer in offers.values():
		if actor not in [offer.seller, offer.buyer]: continue
		proposals.append(offer.duplicate(true).merged({"summary": "现场调查报告与地点，结果以实地记录为准", "known": known(actor, offer.discovery_id)}))
	return {"knowledge_records": typed_records(actor, full), "reports": known_reports, "offers": proposals, "assignments": assignments.values().filter(func(c): return actor in [c.terms.worker_id, c.terms.funder_id]).duplicate(true), "regions": SITES.keys(), "rules": "Reports are observation/evidence, never forecasts as facts. Survey requires arrival, one bread and 20 minutes. Samples are finite per seeded daily site; no-find reports are valid. Paid cards show only summary until purchase; never invent a result or promise new resources. Explicit share_intelligence grants free knowledge; already-known or public facts cannot be charged again."}

func pending_negotiation(actor: String) -> bool:
	return assignments.values().any(func(c): return c.status == "proposed" and actor in [c.terms.worker_id, c.terms.funder_id] and actor not in c.accepted_by) or offers.values().any(func(o): return o.status == "proposed" and o.buyer == actor and not known(actor, o.discovery_id))

static func validate_extended(v: Dictionary) -> bool:
	if v.size() != 10 or not Rules._count(v.get("seed"), 1, 2147483647): return false
	for key in ["private", "public", "reports", "offers", "grants", "assignments", "results", "samples"]:
		if not v.get(key) is Dictionary: return false
	var memories := [v.public]
	for actor in v.private:
		if not Rules._id(actor) or not v.private[actor] is Dictionary: return false
		memories.append(v.private[actor])
	for memory in memories:
		for id in memory:
			var m: Variant = memory[id]
			if not m is Dictionary or m.get("discovery_id") != id or not m.get("region_id") is String or not Rules._count(m.get("discovered_minute"), 0, 9007199254740991) or not m.get("published") is bool: return false
			if not m.has("knowledge_kind"): continue # Original v1 discoveries.
			if m.knowledge_kind not in ["rumor", "fact", "evidence", "observation"]: return false
			if m.has("expires") and not Rules._count(m.expires, int(m.discovered_minute) + 1, 9007199254740991): return false
			if m.knowledge_kind == "rumor" and (not Rules._id(m.get("source_actor")) or not m.get("text") is String or m.text.length() > 1000 or not m.has("expires")): return false
			if m.knowledge_kind in ["fact", "observation"] and not v.reports.has(id): return false
			if m.knowledge_kind == "fact" and (not m.published or m.get("fact_basis") != v.reports[id].get("evidence_id")): return false
			if m.knowledge_kind == "evidence" and (not Rules._id(m.get("evidence_id")) or not Rules._id(m.get("source_actor"))): return false
	for id in v.reports:
		var r: Variant = v.reports[id]
		if not r is Dictionary or r.get("id") != id or r.get("kind") not in ["observation", "evidence", "fact", "rumor", "forecast"] or not SITES.has(r.get("region_id")) or not Rules._id(r.get("source")) or not Rules._id(r.get("evidence_id")) or not Rules._count(r.get("minute"), 0, 9007199254740991) or not Rules._count(r.get("expires"), int(r.minute) + 1, 9007199254740991): return false
		if not r.get("position") is Dictionary or not Rules._number(r.position.get("x"), -176, 80) or not Rules._number(r.position.get("z"), -80, 144) or not r.get("found") is bool or not r.get("text") is String or not r.get("item_id") is String: return false
	for id in v.offers:
		var o: Variant = v.offers[id]
		if not o is Dictionary or o.get("id") != id or not v.reports.has(o.get("discovery_id")) or not Rules._id(o.get("seller")) or not Rules._id(o.get("buyer")) or o.seller == o.buyer or not Rules._count(o.get("price"), 1, 100000) or not Rules._count(o.get("version"), 1, 1000000) or not Rules._count(o.get("expires"), 0, 9007199254740991) or o.get("status") not in ["proposed", "sold", "expired", "already_known"]: return false
		if o.status == "sold" and not v.grants.has(id): return false
	for g in v.grants.values():
		if not g is Dictionary or not v.reports.has(g.get("discovery_id")) or not Rules._id(g.get("source")) or not Rules._id(g.get("target")) or not Rules._count(g.get("price"), 0, 100000) or not Rules._count(g.get("minute"), 0, 9007199254740991): return false
		if not v.private.get(g.target, {}).has(g.discovery_id): return false
	for id in v.samples:
		var r: Variant = v.samples[id]
		if not r is Dictionary or not v.reports.has(id) or not v.reports[id].found or r.get("item_id") != v.reports[id].item_id or not Rules._id(r.get("actor_id")) or not Rules._count(r.get("minute"), int(v.reports[id].minute), int(v.reports[id].expires) - 1) or not v.results.has(r.get("key")): return false
		var receipt: Dictionary = v.results[r.key]
		if receipt.get("actor_id") != r.actor_id or receipt.get("tool") != "collect_sample" or receipt.get("arguments") != {"discovery_id": id} or not receipt.get("result", {}).get("ok", false): return false
	for r in v.results.values():
		if not r is Dictionary or r.size() != 4 or not Rules._id(r.get("actor_id")) or not r.get("arguments") is Dictionary or not r.get("result") is Dictionary or not r.result.get("ok") is bool: return false
		if r.get("tool") != "collect_sample" and not valid_command(str(r.get("tool")), r.arguments): return false
	var busy := {}
	var paid_evidence := {}
	for id in v.assignments:
		var c: Variant = v.assignments[id]
		if not c is Dictionary or c.get("id") != id or not valid_investigation(c.get("terms")) or c.get("status") not in ["proposed", "queued", "traveling", "surveying", "returning", "refund_pending", "completed", "no_sample", "cancelled", "expired"]: return false
		if not Rules._count(c.get("version"), 1, 1000000) or not c.get("accepted_by") is Array or c.accepted_by.size() not in [1, 2] or not c.get("qualified") is bool: return false
		for actor in c.accepted_by:
			if actor not in [c.terms.worker_id, c.terms.funder_id] or c.accepted_by.count(actor) != 1: return false
		for field in ["created", "deadline", "gold", "bread", "consumed_bread", "paid", "refunded_gold", "refunded_bread"]:
			if not Rules._count(c.get(field), 0, 9007199254740991): return false
		for field in ["activity_id", "discovery_id", "evidence_id", "sample", "reason"]:
			if not c.get(field) is String: return false
		if not Rules._count(c.get("started"), -1, 9007199254740991): return false
		var funded: bool = c.accepted_by.size() == 2
		if int(c.gold) + int(c.paid) + int(c.refunded_gold) != (int(c.terms.reward) if funded else 0) or int(c.bread) + int(c.consumed_bread) + int(c.refunded_bread) != (2 if funded else 0): return false
		if funded != (int(c.started) >= 0) or int(c.deadline) != int(c.started if funded else c.created) + int(c.terms.deadline_minutes): return false
		if c.status in ["queued", "traveling", "surveying", "returning", "refund_pending"]:
			if not funded or busy.has(c.terms.worker_id) or int(c.paid) != 0: return false
			busy[c.terms.worker_id] = true
		if c.status in ["completed", "no_sample", "cancelled", "expired"] and (int(c.gold) != 0 or int(c.bread) != 0): return false
		if c.status in ["completed", "no_sample"]:
			if not v.reports.has(c.discovery_id) or not v.grants.has("report:" + id) or paid_evidence.has(c.evidence_id): return false
			paid_evidence[c.evidence_id] = true
			if c.qualified != (c.status == "completed") or int(c.paid) != (int(c.terms.reward) if c.qualified else 0): return false
			if c.qualified and c.terms.require_sample and (not v.samples.has(c.discovery_id) or v.samples[c.discovery_id].actor_id != c.terms.worker_id or c.sample != v.samples[c.discovery_id].item_id): return false
	for id in v.offers:
		var o: Dictionary = v.offers[id]
		if o.status == "sold":
			var g: Dictionary = v.grants[id]
			if g.source != o.seller or g.target != o.buyer or g.discovery_id != o.discovery_id or int(g.price) != int(o.price): return false
	return true

static func validate_proofs(agents: Dictionary) -> bool:
	var v: Dictionary = agents.get("knowledge", {})
	if int(v.get("version", 1)) < VERSION: return true
	if not validate_extended(v): return false
	var activities: Dictionary = agents.get("activities", {}).get("activities", {})
	for id in v.reports:
		var r: Dictionary = v.reports[id]
		var a: Dictionary = activities.get(r.evidence_id, {})
		if a.get("status") != "completed" or a.get("kind") != "survey" or a.get("agent_id") != r.source or a.get("completed_minute") != r.minute or a.get("payload", {}).get("discovery_id") != id or not a.payload.get("physical", false): return false
		# A field observation never becomes a forecast or an unqualified global fact on load.
		if r.kind != "observation" or r.region_id != a.payload.region_id or int(a.payload.worked) < 20: return false
		var day := int(a.started_minute) / 1080
		var found := absi(hash("%d:%s:%d" % [v.seed, r.region_id, day])) % 3 != 0
		if r.id != "survey-%s-%d" % [r.region_id, day] or r.found != found or r.item_id != (SITES[r.region_id].item if found else ""): return false
	for c in v.assignments.values():
		if c.status in ["traveling", "surveying", "returning"]:
			var a: Dictionary = activities.get(c.activity_id, {})
			if a.get("agent_id") != c.terms.worker_id or a.get("payload", {}).get("assignment_id") != c.id: return false
		if c.status in ["completed", "no_sample"] and not c.terms.allow_old_report:
			var a: Dictionary = activities.get(c.evidence_id, {})
			if a.get("agent_id") != c.terms.worker_id or a.get("status") != "completed" or a.get("kind") != "survey" or a.payload.get("assignment_id") != c.id or a.payload.get("discovery_id") != c.discovery_id or int(a.started_minute) < int(c.started): return false
	return true

static func _error(code: String) -> Dictionary: return {"ok": false, "error": code}

static func valid_investigation(a: Variant) -> bool:
	return a is Dictionary and a.size() == 7 and Rules._id(a.get("worker_id")) and Rules._id(a.get("funder_id")) and a.worker_id != a.funder_id and SITES.has(a.get("region_id")) and Rules._count(a.get("reward"), 0, 100000) and Rules._count(a.get("deadline_minutes"), 60, 10080) and a.get("allow_old_report") is bool and a.get("require_sample") is bool

func busy_assignment(actor: String, except_id := "") -> bool:
	return assignments.values().any(func(c): return c.id != except_id and c.terms.worker_id == actor and c.status in ["queued", "traveling", "surveying", "returning", "refund_pending"])

func propose_investigation(actor: String, id: String, terms: Dictionary) -> Dictionary:
	if not valid_investigation(terms) or assignments.has(id) or actor not in [terms.worker_id, terms.funder_id] or not world.assets.exists(terms.funder_id) or world.actor(terms.worker_id) == null or terms.worker_id == "player": return _error("invalid_investigation")
	assignments[id] = {"id": id, "terms": terms.duplicate(true), "accepted_by": [actor], "version": 1, "status": "proposed", "created": world.minute(), "started": -1, "deadline": world.minute() + int(terms.deadline_minutes), "gold": 0, "bread": 0, "consumed_bread": 0, "paid": 0, "refunded_gold": 0, "refunded_bread": 0, "activity_id": "", "discovery_id": "", "evidence_id": "", "sample": "", "qualified": false, "reason": ""}
	world.work._wake([terms.worker_id, terms.funder_id], actor)
	return {"ok": true, "assignment_id": id, "message": "调查资助提案等待另一方确认：托管2份面包及报酬，真实报告／样本交付后付款。"}

func accept_investigation(actor: String, id: String, version: int) -> Dictionary:
	var c: Dictionary = assignments.get(id, {})
	if c.is_empty() or c.status != "proposed" or int(c.version) != version or actor not in [c.terms.worker_id, c.terms.funder_id] or actor in c.accepted_by or world.minute() >= int(c.deadline): return _error("stale_or_foreign_investigation")
	if world.work.occupied(c.terms.worker_id) or busy_assignment(c.terms.worker_id): return _error("investigator_busy")
	if not world.assets.apply(c.terms.funder_id, {"bread": -2}, -int(c.terms.reward)): return _error("investigation_budget_missing")
	c.accepted_by.append(actor)
	c.gold = int(c.terms.reward)
	c.bread = 2
	c.status = "queued"
	c.started = world.minute()
	c.deadline = world.minute() + int(c.terms.deadline_minutes)
	c.version = version + 1
	return {"ok": true, "message": "补给与报酬已托管。未发现样本不保证成功，未用款项按约退回。"}

func cancel_investigation(actor: String, id: String, version: int) -> Dictionary:
	var c: Dictionary = assignments.get(id, {})
	if c.is_empty() or actor not in [c.terms.worker_id, c.terms.funder_id] or int(c.version) != version: return _error("stale_or_foreign_investigation")
	if c.status == "proposed": c.status = "cancelled"; return {"ok": true}
	if c.status in ["completed", "no_sample", "cancelled", "expired"]: return {"ok": true}
	c.status = "refund_pending"
	c.reason = "cancelled"
	c.version = version + 1
	return {"ok": true, "message": "已停止调查，消耗的补给不追回，未用补给与报酬退回。"}

func _advance_assignment(c: Dictionary) -> void:
	var now: int = world.minute()
	var a: Dictionary = c.terms
	if c.status == "proposed":
		if now >= int(c.deadline): c.status = "expired"
		return
	if c.status in ["completed", "cancelled", "expired", "no_sample"]: return
	if now >= int(c.deadline): c.status = "refund_pending"; c.reason = "deadline"
	var activity: Dictionary = world.session.agent_runtime.activity_system._activities.get(c.activity_id, {})
	if c.status == "refund_pending":
		if activity.get("status") == "in_progress":
			activity.payload.deadline = now
			activity.complete_at_minute = now
			return
		if world.assets.apply(a.funder_id, {"bread": int(c.bread)}, int(c.gold)):
			c.refunded_gold = int(c.gold); c.refunded_bread = int(c.bread); c.gold = 0; c.bread = 0
			c.status = "expired" if now >= int(c.deadline) else "cancelled"
		return
	if c.status == "queued":
		if a.allow_old_report and not a.require_sample:
			for id in reports:
				if reports[id].region_id == a.region_id and known(a.worker_id, id) and fresh(id) and _unused_report(a.worker_id, id):
					c.discovery_id = id
					c.evidence_id = str(_private.get(a.worker_id, {}).get(id, {}).get("evidence_id", reports[id].evidence_id))
					c.qualified = not a.require_sample
					_start_return(c)
					return
		var id := str(c.id) + ":travel"
		var result := begin_fieldwork(a.worker_id, "travel", a.region_id, id, {"assignment_id": c.id}, 10)
		if result.ok:
			c.activity_id = id; c.status = "traveling"; c.bread = int(c.bread) - 1; c.consumed_bread = int(c.consumed_bread) + 1
		else: c.reason = result.error; c.status = "refund_pending"
		return
	if activity.get("status") == "failed": c.reason = activity.payload.get("error", "fieldwork_failed"); c.status = "refund_pending"; return
	if activity.get("status") != "completed": return
	if c.status == "traveling":
		if not world.assets.apply(a.worker_id, {"bread": 1}, 0): c.reason = "supply_capacity"; return
		var id := str(c.id) + ":survey"
		var result := begin_fieldwork(a.worker_id, "survey", a.region_id, id, {"assignment_id": c.id})
		if result.ok:
			c.activity_id = id; c.status = "surveying"; c.bread = int(c.bread) - 1; c.consumed_bread = int(c.consumed_bread) + 1
		else:
			world.assets.apply(a.worker_id, {"bread": -1}, 0)
			c.reason = result.error; c.status = "refund_pending"
	elif c.status == "surveying":
		c.discovery_id = str(activity.payload.get("discovery_id", ""))
		c.evidence_id = str(activity.activity_id)
		c.qualified = not a.require_sample
		if a.require_sample and reports.get(c.discovery_id, {}).get("found", false):
			var sample := collect(a.worker_id, c.discovery_id, str(c.id) + ":sample")
			if sample.ok: c.sample = sample.item_id; c.qualified = true
		_start_return(c)
	elif c.status == "returning": _deliver_report(c)

func _start_return(c: Dictionary) -> void:
	var target: Vector3 = world.work.location(c.terms.funder_id, c.terms.worker_id)
	if not target.is_finite(): c.reason = "return_route_unavailable"; return
	var id := str(c.id) + ":return"
	var now: int = world.minute()
	var payload := {"physical": true, "assignment_id": c.id, "region_id": c.terms.region_id, "tool_name": "travel", "target": {"x": target.x, "z": target.z}, "worked": 0, "last_minute": now, "deadline": c.deadline}
	if world.session.agent_runtime.activity_system.start(c.terms.worker_id, "travel", id, now, now + 10, payload): c.activity_id = id; c.status = "returning"

func _unused_report(actor: String, id: String) -> bool:
	var evidence := str(_private.get(actor, {}).get(id, {}).get("evidence_id", reports[id].evidence_id))
	return not assignments.values().any(func(c): return c.evidence_id == evidence and c.status in ["completed", "no_sample"])

func _deliver_report(c: Dictionary) -> void:
	var target: Vector3 = world.work.location(c.terms.funder_id, c.terms.worker_id)
	if not target.is_finite() or not world.work.walk(c, c.terms.worker_id, target): c.reason = "awaiting_sponsor_arrival"; return
	if not reports.has(c.discovery_id) or not _unused_report(c.terms.worker_id, c.discovery_id): c.reason = "report_proof_already_used"; c.status = "refund_pending"; return
	var report: Dictionary = reports[c.discovery_id]
	if not c.terms.allow_old_report and (int(report.minute) < int(c.started) or str(c.evidence_id) != str(c.id) + ":survey"): c.reason = "new_field_report_required"; c.status = "refund_pending"; return
	var pay := int(c.gold) if c.qualified else 0
	var worker_goods := {}
	var funder_goods := {"bread": int(c.bread)}
	if c.qualified and c.terms.require_sample:
		worker_goods[c.sample] = -1
		funder_goods[c.sample] = 1
	if not world.work.transfer({c.terms.worker_id: {"items": worker_goods, "gold": pay}, c.terms.funder_id: {"items": funder_goods, "gold": int(c.gold) - pay}}): c.reason = "report_delivery_capacity"; return
	grant(c.terms.worker_id, c.terms.funder_id, c.discovery_id, "report:" + str(c.id), 0)
	c.paid = pay; c.refunded_gold = int(c.gold) - pay; c.refunded_bread = int(c.bread); c.gold = 0; c.bread = 0
	c.status = "completed" if c.qualified else "no_sample"
	c.version = int(c.version) + 1
	c.reason = "" if c.qualified else "调查完成但未取得要求的样本，报酬退回"
