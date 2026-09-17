extends RefCounted

const GolfCourse = preload("res://scripts/farm3d/golf_course_data.gd")

var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/agents/query_catalog.json"))
var SECTIONS: Dictionary = {}

func _init() -> void:
	for domain in catalog: SECTIONS[domain] = catalog[domain].sections

func read(runtime: Node, actor: String, name: String, args: Dictionary) -> Dictionary:
	var minute: int = runtime._absolute_game_minute()
	if name == "inspect_self_resources":
		return {"ok": true, "resources": runtime.loop_state.snapshot(runtime, actor), "observed_game_minute": minute}
	if name != "query_world": return {"ok": false, "error": "unknown_read_tool"}
	var domain := str(args.get("domain", ""))
	var section := str(args.get("section", ""))
	if not SECTIONS.has(domain): return {"ok": false, "error": "unknown_domain"}
	if section.is_empty():
		section = "detail" if (args.has("id") or args.has("ids")) and "detail" in SECTIONS[domain] else str(catalog[domain].default_section) if args.has("query") or args.has("id") or args.has("ids") else "overview"
	if domain == "market" and section in ["list", "price", "prices"]: section = "detail" if args.has("id") or args.has("ids") else "items"
	if actor == "village_public" and domain not in ["public", "environment", "social"]: return {"ok": false, "error": "unauthorized_domain"}
	if actor != "village_public" and domain == "public": return {"ok": false, "error": "unauthorized_domain"}
	var result := {"ok": true, "observation_id": "%s:%s:%d" % [actor, domain, Time.get_ticks_usec()], "observed_game_minute": minute, "domain_revision": runtime.executor.world_revision, "domain": domain, "section": section}
	if section == "overview":
		result.sections = SECTIONS[domain]
		result.rule = catalog[domain].hint
		result.default_section = catalog[domain].default_section
		return result
	if section not in SECTIONS[domain]: return {"ok": false, "error": "unknown_section", "sections": SECTIONS[domain]}
	if args.has("ids"):
		if not args.ids is Array or args.ids.is_empty() or args.ids.size() > 10 or args.has("id") or section != "detail" or domain != "market":
			return {"ok": false, "error": "ids_requires_market_detail", "hint": "Use up to 10 exact item IDs; do not mix id and ids."}
		for item in args.ids:
			if not item is String or item.is_empty() or args.ids.count(item) != 1: return {"ok": false, "error": "invalid_item_ids"}
	if section in ["detail", "quote"] and domain in ["market", "buildings"] and str(args.get("id", "")).is_empty() and not args.has("ids"):
		return {"ok": false, "error": "id_required", "domain": domain, "section": section, "hint": "Use exact id or ids; search the list first. Empty data is not a quote."}
	if section == "quote":
		var batches: Variant = args.get("batches")
		if str(args.get("recipe_id", "")).is_empty() or not (batches is float or batches is int):
			return {"ok": false, "error": "quote_arguments_required", "hint": "Supply building id, recipe_id and integer batches (1..100)."}
		if float(batches) != int(batches) or int(batches) < 1 or int(batches) > 100:
			return {"ok": false, "error": "invalid_batches"}
	var value: Variant = _query(runtime, actor, domain, section, args)
	if value is Dictionary and value.has("error"):
		result.merge(value, true)
		result.ok = false
		return result
	if value is Array:
		var id := str(args.get("id", ""))
		var query := str(args.get("query", "")).to_lower()
		if not id.is_empty(): value = value.filter(func(row): return row is Dictionary and [row.get("id"), row.get("actor_id"), row.get("goal_id"), row.get("building_id"), row.get("instance_id"), row.get("offer_id"), row.get("agreement_id"), row.get("discovery_id")].has(id))
		if not query.is_empty() and section not in ["detail", "quote"]:
			var terms := query.replace(",", " ").replace("，", " ").split(" ", false)
			value = value.filter(func(row): return Array(terms).any(func(term): return JSON.stringify(row).to_lower().contains(term)))
		var start := maxi(0, int(args.get("cursor", 0)))
		var limit := clampi(int(args.get("limit", 10 if domain == "map" else 5)), 1, 10)
		result.items = value.slice(start, start + limit)
		result.total_matches = value.size()
		if value.is_empty(): result.hint = "No matching authorized results. Try one exact ID or a shorter search term; no match does not prove a whole activity is unavailable."
		result.next_cursor = start + limit if value.size() > start + limit else -1
	else: result.data = value
	return result

func _query(r: Node, actor: String, domain: String, section: String, a: Dictionary) -> Variant:
	var world: Node = r.farm3d_session.living_world
	match domain:
		"self":
			var activity: Dictionary = r.world_projector.get_actor(actor).get("current_public_state", {}).duplicate(true)
			activity.reported_region_id = activity.get("region_id", "")
			activity.erase("region_id")
			activity.status = "busy" if world.work.occupied(actor) else "idle"
			var body: Node3D = world.actor(actor)
			activity.position = {"x": body.position.x, "z": body.position.z} if body != null else {}
			return {"activity": activity, "field_sites": _field_sites(world, actor), "arrival_rule": "Only field_sites.arrived proves physical arrival. reported_region_id is a public projection, not an arrival check.", "project": world.projects.active(actor), "work_busy": world.work.occupied(actor), "delivery": world.interruptions.running(actor)}
		"goals": return r.loop_state.goals.values().filter(func(g): return g.actor_id == actor)
		"map": return _field_sites(world, actor) + [{"id": "farm", "description": "中央农场"}, {"id": "lake", "description": "南部湖泊，无通用survey点，可查询社交活动"}, {"id": "market", "x": r.farm3d_session.market_site.x, "z": r.farm3d_session.market_site.y, "description": "市场，buy/sell自动前往"}, _golf_place(world, actor)]
		"farm":
			if section == "crops": return r._build_crop_options(actor)
			return r.farm_registry.get_snapshot(actor, r._absolute_game_minute())
		"market":
			if section == "supply": return world.merchant.supply_view(str(a.get("id", "")))
			if section == "detail":
				if a.has("ids"):
					var details: Array = []
					for item_id in a.ids:
						var detail: Dictionary = r._market.get_agent_item_view(str(item_id))
						details.append(detail if not detail.is_empty() else {"id": item_id, "ok": false, "error": "item_not_found"})
					return details
				var detail: Dictionary = r._market.get_agent_item_view(str(a.get("id", "")))
				return detail if not detail.is_empty() else {"error": "item_not_found"}
			# List rows carry live counter state: merchant stock and mid price, plus
			# confirmed incoming supply (transit/imports/claimed procurement) so agents
			# can tell "sold out" from "restocking" in one read. Rows are built for all
			# items before pagination, so only cheap bounded calls belong here; quotes,
			# max sell quantity and full procurement depth stay in "detail"/"supply".
			var merchant_live: bool = not r._market.merchant.is_empty()
			return r.GameDataScript.get_market_items().map(func(item):
				var item_id := str(item.id)
				var row := {"id": item_id, "name": item.get("name", item.get("display_name", item_id)), "category": item.get("category", ""),
					"mid_price": r._market.get_mid_price(item_id), "stock": r._market.get_stock(item_id)}
				if merchant_live: row.incoming = world.merchant.incoming(item_id)
				return row)
		"buildings":
			if section == "sites": return {"windmill": world.construction.sites(actor), "food_workshop": world.construction.sites(actor, "food_workshop")}
			var rows: Array = []
			for building in r.farm3d_session.buildings.get_all_buildings():
				var id: String = EconomyProgressionSystem.building_key(building)
				var record := {"building_id": id, "instance_id": building.instance_id, "name": building.data.display_name, "owner_id": building.owner_id, "type": building.building_id, "position": {"x": building.position.x, "z": building.position.z}, "construction_complete": building.is_construction_complete()}
				if section in ["detail", "quote"]:
					if str(a.get("id", "")) not in [id, building.instance_id]: continue
					if section == "quote":
						var quote: Dictionary = r.farm3d_session.production.building_service.quote(building, actor, str(a.recipe_id), int(a.batches))
						quote.merge({"building_id": id, "recipe_id": a.recipe_id, "batches": int(a.batches), "position": record.position, "recipe_terms": r.farm3d_session.production.get_rental_fee_table(building).filter(func(row): return row.recipe_id == a.recipe_id), "service_policy": building.service_policy.duplicate(true)}, true)
						if quote.ok: quote.action = {"tool_name": "rent_production", "arguments": {"building_id": id, "recipe_id": a.recipe_id, "batches": int(a.batches), "max_fee": int(quote.fee)}}
						return quote
					record.production = _production_summary(r.farm3d_session.production, building, actor)
					record.rental_fees = r.farm3d_session.production.get_rental_fee_table(building)
					record.service_policy = building.service_policy.duplicate(true)
				rows.append(record)
			if section in ["detail", "quote"] and rows.is_empty(): return {"error": "building_not_found"}
			return rows
		"tasks":
			match section:
				"projects": return world.projects.projects.values().filter(func(p): return p.actor_id == actor)
				"commissions": return world.board.commissions.values().filter(func(c): return c.status == "open")
				"claims": return world.board.claims.values().filter(func(c): return c.actor_id == actor)
				"contracts", "ventures", "training", "candidates": return world.work.context(actor).get(section, [])
				"deliveries": return world.interruptions.context(actor)
				"rules": return {"capabilities": world.projects.CAPABILITIES, "rules": world.context(actor).rules, "work_rules": world.work.context(actor).rules}
		"actors":
			match section:
				"offers": return r.interaction_system.list_offers(actor)
				"agreements": return r.agreement_system.list_agreements(actor)
				"relationship": return r.agreement_system.get_relationship(actor, str(a.get("id", "")))
				"roles": return r.registry.get_role_ids().map(func(id): return r.registry.get_role(id))
				"list": return r.world_projector.known_actors(actor).map(func(row): return {"actor_id": row.actor_id, "display_name": row.display_name, "public_role": row.public_role, "region_id": row.region_id, "observable_status": row.observable_status})
		"knowledge": return r.knowledge_registry.cards(actor, true).get(section, [])
		"social": return world.social.context().get(section, [])
		"environment":
			if section == "society": return world.society.summary()
			if section == "weather": return {"current": world.environment.days.get(str(world.minute() / 1080), {}), "forecast": world.environment.days.get(str(world.minute() / 1080 + 1), {})}
			if section == "route": return {"event": world.environment.event.duplicate(true), "route_open": world.environment.route_open(), "repair_site": {"x": world.environment.SITE.x, "z": world.environment.SITE.z}, "required_materials": world.environment.REPAIR, "required_labor": 60}
			return world.environment.transports.values().map(func(t): return {"id": t.id, "item_id": t.item_id, "quantity": t.quantity, "arrival": t.arrival, "status": t.status})
		"public":
			match section:
				"indicators": return world.public_plans.indicators()
				"budget": return world.public_plans.budget()
				"plans": return world.public_plans.public_plans()
				"rules": return {"version": world.public_plans.revision, "rules": "Only actual public funds. Daily ceiling 800 gold. Purchase at most 12 bread; unit reward at most 200. Existing funded plans remain binding. Read indicators/budget/plans before spending; use expected_version. May wait or decline."}
	return {"error": "unavailable"}

func _field_sites(world: Node, actor: String) -> Array:
	var result: Array = []
	for region in world.knowledge.SITES:
		result.append(world.knowledge.field_status(actor, region))
	return result

func _golf_place(world: Node, actor: String) -> Dictionary:
	var entrance: Vector2 = GolfCourse.ENTRANCE
	var event_site: Vector2 = world.social.SITES.golf
	var body: Node3D = world.actor(actor)
	var distance := Vector2(body.position.x, body.position.z).distance_to(entrance) if body != null else -1.0
	return {"id": "golf", "name": "湖西高尔夫球场", "aliases": ["golf_course", "高尔夫", "球场"], "kind": "recreation",
		"position": {"x": entrance.x, "z": entrance.y}, "distance": distance, "arrived": body != null and distance <= 2.5,
		"description": "七洞高尔夫球场。NPC可前往、组织活动、报名观赛；挥杆和比赛成绩由玩家实际操作产生。此处不是travel/survey调查点。",
		"holes": GolfCourse.HOLES.size(), "par": GolfCourse.total_par(),
		"navigation_action": {"tool_name": "move", "arguments": {"x": entrance.x, "z": entrance.y}},
		"activity_kind": "golf", "spectator_position": {"x": event_site.x, "z": event_site.y},
		"activity_queries": [{"domain": "social", "section": "events", "query": "golf"}, {"domain": "social", "section": "rules"}],
		"activity_rule": "Discover social tools, inspect event rules and current enrollment terms before propose_activity/enroll_activity. Entrance and spectator site differ; enrollment handles attendance. No NPC swing or score-submission tool exists."}

func _production_summary(production: Node, building: BuildingInstance, actor: String) -> Dictionary:
	var snapshot: Dictionary = production.get_building_snapshot(building)
	var result := {}
	for key in ["station_id", "max_queue_slots", "output_capacity", "storage_quantity_capacity", "inputs", "outputs", "beehive_cycle", "maintenance_state", "maintenance_due_day", "maintenance_days_remaining", "maintenance_paused", "repair_remaining_seconds"]:
		if snapshot.has(key): result[key] = snapshot[key]
	result.queue = snapshot.get("jobs", []).map(func(job): return {"recipe_id": job.get("recipe_id", ""), "status": job.get("status", ""), "remaining_minutes": job.get("remaining_minutes", 0)})
	result.queued_count = result.queue.size()
	result.own_customer_outputs = snapshot.get("customer_outputs", {}).get(actor, {}).duplicate(true)
	if building.building_id == "greenhouse":
		result.greenhouse = production.get_greenhouse_snapshot(building,actor)
	if building.building_id == "waterwheel":
		result.waterwheel = production.get_waterwheel_snapshot(building)
	if building.building_id == "beehive":
		var honey: Dictionary = production.get_beehive_snapshot(building)
		result.beehive = {}
		for key in ["status", "flower_count", "owners", "hive_owner", "honey_share", "duration_minutes", "remaining_minutes", "next_output", "next_owners"]:
			result.beehive[key] = honey[key]
	return result
