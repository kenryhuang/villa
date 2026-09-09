extends Node

const Society = preload("res://scripts/systems/resident_society_system.gd")
var session: Farm3DSession
var assets: RefCounted
var society: RefCounted
var projects: RefCounted
var construction: RefCounted
var board: RefCounted
var interruptions: RefCounted
var public_plans: RefCounted
var _tick := 0.0
var saved_positions: Dictionary = {}
var pending_player_terms: Dictionary = {}
var resident_visuals: Dictionary = {}
var _bound := false

func configure(farm: Farm3DSession) -> void:
	session = farm
	assets = session.production.actor_assets
	society = Society.new()
	society.configure(self)
	projects = preload("res://scripts/systems/npc_project_system.gd").new()
	projects.configure(self)
	construction = preload("res://scripts/systems/npc_construction_system.gd").new()
	construction.configure(self)
	board = preload("res://scripts/systems/commission_system.gd").new()
	board.configure(self)
	interruptions = preload("res://scripts/systems/npc_interruption_system.gd").new()
	interruptions.configure(self)
	public_plans = preload("res://scripts/systems/public_plan_system.gd").new()
	public_plans.configure(self)
	get_node("/root/EventBus").time_changed.connect(func(_hour: int, _minute: int): advance())
	session.state_loaded.connect(_after_load)

func minute() -> int:
	return maxi(0, session.season.total_days - 1) * 1080 + maxi(0, session.season.hour - 6) * 60 + session.season.minute

func advance() -> void:
	society.advance_to(minute())
	board.advance()
	construction.advance()
	interruptions.advance()
	projects.advance()
	public_plans.advance()

func _process(_delta: float) -> void:
	if not _bound or get_tree().paused: return
	_tick += _delta
	if _tick >= .25:
		_tick = 0
		construction.advance()
		interruptions.advance()
		projects.advance()
		public_plans.advance()
	for actor_id in ["farmer_ahe", "lao_li", "xuezhe_lin"]:
		var body: Node3D = actor(actor_id)
		if body == null or body.nameplate == null: continue
		var task: Dictionary = interruptions.running(actor_id)
		body.nameplate.text = actor_name(actor_id) if task.is_empty() else actor_name(actor_id) + " · " + str({"pickup": "前来取货", "delivering": "配送中", "returning": "返回退货", "refund_pending": "等待退还"}.get(task.status, "配送中"))
	for id in resident_visuals:
		var record: Dictionary = society.residents[id]
		var pos := Vector2(record.position.x, record.position.z)
		resident_visuals[id].position = Vector3(pos.x, Farm3DTerrainProfile.surface_height(pos.x, pos.y), pos.y)
		resident_visuals[id].get_node("Name").text = str(record.name) + " · " + str(record.state)

func bind_scene() -> void:
	if _bound: return
	_bound = true
	for id in ["resident_mei", "resident_zhou", "resident_chen"]:
		var visual := Node3D.new()
		var mesh := MeshInstance3D.new()
		var shape := CapsuleMesh.new()
		shape.radius = .23
		shape.height = 1.3
		mesh.mesh = shape
		mesh.position.y = .65
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("758b60") if id == "resident_mei" else Color("a08762")
		mesh.material_override = material
		visual.add_child(mesh)
		var label := Label3D.new()
		label.name = "Name"
		label.position.y = 1.7
		label.font_size = 26
		label.pixel_size = .01
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		visual.add_child(label)
		add_child(visual)
		resident_visuals[id] = visual
	_after_load()

func _after_load() -> void:
	for id in saved_positions:
		var body: Node3D = actor(id)
		if body != null: body.position = Vector3(saved_positions[id].x, Farm3DTerrainProfile.surface_height(saved_positions[id].x, saved_positions[id].z), saved_positions[id].z)
	_process(0)

func to_dict() -> Dictionary:
	for id in ["farmer_ahe", "lao_li", "xuezhe_lin"]:
		var body: Node3D = actor(id)
		if body != null: saved_positions[id] = {"x": body.position.x, "z": body.position.z}
	return {"version": 3, "public_plans": public_plans.to_dict(), "interruptions": interruptions.to_dict(), "society": society.to_dict(), "projects": projects.to_dict(), "construction": construction.to_dict(), "board": board.to_dict(), "positions": saved_positions.duplicate(true)}

func validate(value: Variant) -> bool:
	if not value is Dictionary or not integer(value.get("version")) or int(value.version) not in [1, 2, 3] or value.size() != (5 + int(value.version)) or not society.validate(value.get("society")) or not projects.validate(value.get("projects")) or not construction.validate(value.get("construction")) or not board.validate(value.get("board")) or not value.get("positions") is Dictionary: return false
	if value.version >= 2 and not interruptions.validate(value.get("interruptions"), value.projects.projects): return false
	if value.version == 1 and value.projects.projects.values().any(func(p): return p.status == "suspended"): return false
	if value.version >= 2:
		var counts := {}
		for t in value.interruptions.tasks.values():
			if t.status in interruptions.LIVE: counts[t.actor_id] = int(counts.get(t.actor_id, 0)) + 1
		for actor_id in counts:
			for claim in value.board.claims.values():
				if claim.actor_id == actor_id and claim.status == "active": counts[actor_id] = int(counts[actor_id]) + 1
			if int(counts[actor_id]) > interruptions.LIMIT: return false
	if value.version >= 3 and not public_plans.validate(value.get("public_plans"), value.board): return false
	for id in value.positions:
		if id not in ["farmer_ahe", "lao_li", "xuezhe_lin"] or not position_valid(value.positions[id]): return false
	return true

func restore(value: Dictionary) -> void:
	pending_player_terms.clear()
	value = preload("res://scripts/ai_agent/agent_protocol.gd")._normalize_json_numbers(value)
	society.restore(value.society)
	projects.restore(value.projects)
	construction.restore(value.construction)
	board.restore(value.board)
	interruptions.restore(value.get("interruptions", {}))
	public_plans.restore(value.get("public_plans", {}))
	saved_positions = value.positions.duplicate(true)

func debug_text() -> String:
	var lines: Array[String] = [society.summary(), "", public_plans.summary(), ""]
	for record in society.residents.values():
		var state: NpcEconomyState = session.npc_economy.get_npc_state(record.id)
		lines.append("%s · %s · %d 金币 · %s" % [record.name, record.occupation, state.gold, record.state])
	for org in society.config.organizations:
		lines.append("%s · %d 金币" % [org.name, session.npc_economy.get_npc_state(org.id).gold])
	lines.append("\n近期账目（工资托管与市场外部边界分别记录）")
	for entry in society.ledger.slice(maxi(0, society.ledger.size() - 30)):
		lines.append("%s %s %s 金币 %+d" % [entry.minute, entry.actor_id, entry.kind, int(entry.gold)])
	lines.append("\n自主项目（预算与材料托管）")
	for p in projects.projects.values():
		lines.append("%s · %s · %s · 剩余预算 %d · %s" % [p.actor_id, p.plan.goal, p.status, int(p.gold), p.reason])
		for step in p.plan.steps: lines.append("  %s %s · %s" % [step.id, step.capability, p.steps[step.id].status])
	return "\n".join(lines)

static func integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 9007199254740991.0 and floorf(float(value)) == float(value)

static func position_valid(value: Variant) -> bool:
	return value is Dictionary and value.size() == 2 and (value.get("x") is float or value.get("x") is int) and (value.get("z") is float or value.get("z") is int) and is_finite(float(value.x)) and is_finite(float(value.z)) and float(value.x) >= Farm3DTerrainProfile.WORLD_MIN.x and float(value.x) <= Farm3DTerrainProfile.WORLD_MAX.x and float(value.z) >= Farm3DTerrainProfile.WORLD_MIN.y and float(value.z) <= Farm3DTerrainProfile.WORLD_MAX.y


func actor(id: String) -> Node3D:
	if id == "player": return session.player
	return session.agent_runtime.farm3d_actors.get(id) if session.agent_runtime != null else null

func building(id: String) -> BuildingInstance:
	for b in session.buildings.get_all_buildings():
		if b.instance_id == id or EconomyProgressionSystem.building_key(b) == id: return b
	return null

func execute_project_step(p: Dictionary, step: Dictionary, _state: Dictionary, key: String) -> Dictionary:
	var a: Dictionary = step.arguments
	match step.capability:
		"reserve_plot": return construction.reserve(p.actor_id, key, int(a.gx), int(a.gz), mini(1080, maxi(1, int(p.deadline) - minute())))
		"build":
			var lease: String = str(p.steps.get(a.lease_step, {}).get("result", {}).get("lease_id", ""))
			var materials := {"plank": 12, "stone_brick": 8, "rope": 2}
			if not projects._release(p, materials, 0): return {"ok": false, "error": "construction_materials"}
			var result: Dictionary = construction.start(p.actor_id, key, lease)
			if not result.ok: projects._hold(p, materials, 0)
			return result
		"wait_construction", "set_policy":
			var b: BuildingInstance = building(str(p.steps.get(a.build_step, {}).get("result", {}).get("building_id", "")))
			if b == null: return {"ok": false, "error": "building_missing"}
			if not b.is_construction_complete(): return {"waiting": true, "error": "construction"}
			if step.capability == "wait_construction": return {"ok": true}
			var policy := b.service_policy.duplicate(true)
			policy.open = a.open
			policy.fees = {"flour": int(a.fee)}
			return session.production.building_service.set_policy(b, p.actor_id, policy, int(b.service_policy.version))
		"claim": return board.claim(p.actor_id, key, a.commission_id, int(a.quantity))
		"deliver":
			var claim_id := str(p.steps.get(a.claim_step, {}).get("result", {}).get("claim_id", ""))
			if not board.claims.has(claim_id): return {"ok": false, "error": "unknown_claim"}
			var c: Dictionary = board.commissions[board.claims[claim_id].commission_id]
			var order_id := str(p.steps.get(a.order_step, {}).get("result", {}).get("order_id", ""))
			var items := {c.terms.item_id: int(a.quantity)}
			if not projects._release(p, items, 0): return {"ok": false, "error": "delivery_stock"}
			var result: Dictionary = board.deliver(p.actor_id, key, claim_id, int(a.quantity), int(c.version), order_id)
			if result.ok: projects._hold(p, {}, int(result.get("reward", 0)))
			else: projects._hold(p, items, 0)
			return result
	return {"ok": false, "error": "unsupported_capability"}

func context(actor_id: String) -> Dictionary:
	return {"interruptions": interruptions.context(actor_id), "society": society.summary(), "recent_projects": projects.projects.values().filter(func(p): return p.actor_id == actor_id and p.status != "active").slice(-3), "own_claims": board.claims.values().filter(func(c): return c.actor_id == actor_id and c.status == "active"), "project": _current_project(actor_id), "suggestion": projects.suggestions.get(actor_id, {}), "legal_windmill_sites": construction.sites(actor_id), "commissions": board.commissions.values().filter(func(c): return c.status == "open"), "capabilities": projects.CAPABILITIES,
		"rules": "For a blocked project, inspect step.result including current_total_quote. You can cancel_project to release unused escrow, then submit_project with a revised plan using returned materials; never resubmit already completed production. Sell limits are TOTAL proceeds including market depth/slippage, not unit price multiplied by quantity. move to a building coordinate approaches its reachable edge. Choose your own goal and a topologically ordered project DAG, or decline if unprofitable. submit_project escrows budget and materials; one primary project. Each step: id, capability, depends_on, arguments. buy/sell arguments item_id,quantity,limit (TOTAL max cost/min proceeds); move x,z; rent building_id,recipe_id,batches,max_fee; wait_production order_step; reserve_plot gx,gz; build lease_step; wait_construction build_step; set_policy build_step,open,fee; claim commission_id,quantity; deliver claim_step,quantity,order_step (empty for procurement). IDs referring to steps must be earlier dependencies. Inputs/outputs stay in project escrow until completion. Project rental recipes currently require explicit ingredients (such as flour or bread), not tagged input_selectors. rent.building_id can be @buildStepId to refer to a prior build step in its ancestors; the engine resolves the new instance ID, so do not invent one. Building construction takes 9 real simulation seconds (paused with game). A project may stop after build/wait_construction/set_policy then decide production separately. Empty allowed_recipes means ALL station recipes, not none. Build only after moving to the legal site's approach; no player materials or positions. Leases expire; build is a real windmill costing plank12,stone_brick8,rope2. Processing commissions require a new rental order after claiming. Suggestions are optional, never authorization to spend player funds. Rejected/blocked steps require retry_project or cancel_project and a new plan; no fabricated completion."}


func command(actor_id: String, tool: String, a: Dictionary, key: String) -> Dictionary:
	var result := {"ok": false, "error": "unknown_command"}
	match tool:
		"propose_delivery": result = interruptions.propose(actor_id, key, a)
		"cancel_delivery": result = interruptions.cancel(actor_id, a.task_id, int(a.version))
		"revise_project":
			result = projects.revise(actor_id, a.project_id, int(a.version), a.plan, a.source)
			if result.ok: projects.projects[a.project_id].changes[-1].action_key = key
		"submit_project": result = projects.submit(actor_id, "project-" + key.sha256_text().substr(0, 24), a)
		"retry_project": result = projects.retry(actor_id, a.project_id)
		"cancel_project": result = projects.cancel(actor_id, a.project_id)
		"suggest_behavior": result = projects.suggest(actor_id, a.text, int(a.ttl))
		"propose_player_commission":
			if not board.valid_terms(a): return {"ok": false, "error": "invalid_commission"}
			pending_player_terms = {"id": key, "actor_id": actor_id, "terms": a.duplicate(true), "expires": minute() + 180}
			result = {"ok": true, "message": "委托草稿已拟好。关闭对话后核对条款，只有你确认后才会扣款发布。"}
		"publish_commission":
			if board.demand(a.demand_id, actor_id, a.item_id, int(a.quantity)): result = board.publish(actor_id, "commission-" + key.sha256_text().substr(0, 24), a)
		"claim_commission": result = board.claim(actor_id, "claim-" + key.sha256_text().substr(0, 24), a.commission_id, int(a.quantity))
		"deliver_commission": result = board.deliver(actor_id, key, a.claim_id, int(a.quantity), int(a.version), a.order_id)
	if result.ok: result.mutated = true
	return result


func reset_for_legacy() -> void:
	projects.restore({"projects": {}, "suggestions": {}})
	interruptions.restore({})
	public_plans.restore({})
	construction.restore({"leases": {}, "builds": {}})
	board.restore({"demands": {}, "commissions": {}, "claims": {}, "receipts": {}, "proofs": {}, "sequence": 0})
	saved_positions.clear()
	society.reset(minute())

func validate_save(data: Dictionary) -> bool:
	if not validate(data.get("living_world")): return false
	var value: Dictionary = data.living_world
	if not data.get("season") is Dictionary: return false
	for field in ["total_days", "hour", "minute"]:
		if not integer(data.season.get(field)): return false
	var clock := maxi(0, int(data.season.total_days) - 1) * 1080 + maxi(0, int(data.season.hour) - 6) * 60 + int(data.season.minute)
	if int(value.society.last_minute) != clock: return false
	var buildings := {}
	var orders := {}
	for b in data.get("buildings", []):
		if not b is Dictionary or not b.get("producer_state", {}) is Dictionary or not b.get("producer_state", {}).get("service_records", {}) is Dictionary: return false
		buildings[str(b.get("instance_id", ""))] = b
		for id in b.get("producer_state", {}).get("service_records", {}):
			orders[id] = b.producer_state.service_records[id]
	for record in value.construction.builds.values():
		if record.status in ["cancelled", "demolished"]:
			if buildings.has(record.building_id): return false
			continue
		if not buildings.has(record.building_id) or buildings[record.building_id].get("owner_id") != record.actor_id: return false
		var b: Dictionary = buildings[record.building_id]
		var lease: Dictionary = value.construction.leases[record.lease_id]
		if int(b.gx) != int(lease.gx) or int(b.gz) != int(lease.gz) or b.building_id != "windmill": return false
	for p in value.projects.projects.values():
		for state in p.steps.values():
			if state.status != "done" or not state.result.has("order_id"): continue
			var order: Dictionary = orders.get(state.result.order_id, {})
			if order.is_empty():
				if not state.result.get("delivered", false): return false
				continue
			if not order.get("job") is Dictionary or order.job.get("tenant_id") != p.actor_id: return false
			if state.result.get("delivered", false) != (order.stage == "delivered"): return false
	for id in value.board.proofs:
		var proof: Dictionary = value.board.proofs[id]
		var order: Dictionary = orders.get(id, {})
		if order.is_empty():
			if not proof.complete: return false
			continue
		if not order.get("job") is Dictionary or order.job.get("tenant_id") != proof.actor_id or proof.complete != (order.get("stage") in ["ready", "delivered"]): return false
		if not order.job.get("recipe_id") is String or not integer(order.job.get("batches")): return false
		var recipe: Dictionary = preload("res://scripts/core/recipe_database.gd").get_recipe(order.job.recipe_id)
		if recipe.is_empty() or recipe.outputs.size() != proof.outputs.size(): return false
		for item in recipe.outputs:
			if int(proof.outputs.get(item, 0)) != int(recipe.outputs[item]) * int(order.job.batches): return false
	return true


func actor_name(id: String) -> String:
	if id == "player": return "玩家"
	if society.residents.has(id): return str(society.residents[id].name)
	for org in society.config.organizations:
		if org.id == id: return str(org.name)
	return id


func _current_project(actor_id: String) -> Dictionary:
	for p in projects.projects.values():
		if p.actor_id == actor_id and p.status in ["active", "suspended"]: return p.duplicate(true)
	return {}
