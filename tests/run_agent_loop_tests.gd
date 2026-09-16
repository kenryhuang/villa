extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(45).timeout.connect(func(): push_error("Agent Loop tests timed out"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var session: Node = scene.farm_session
	session.season.set_process(false)
	var r: Node = session.agent_runtime
	r.set_process(false)
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P1"), "Isolated 3D fixture")
	var request: Dictionary = r._build_loop_request("farmer_ahe", "loop-test", "dialogue", r._absolute_game_minute(), "今天可以种点什么？")
	check(request.protocol_version == 3, "Compact v3 request")
	for forbidden in ["actor_context", "market_view", "market_summary", "known_actors", "public_world_state"]:
		check(not request.has(forbidden), "No eager " + forbidden)
	check(request.resources.gold == session.npc_economy.get_npc_state("farmer_ahe").gold, "Exact gold in header")
	var revision := int(request.resources.resource_revision)
	session.npc_economy.get_npc_state("farmer_ahe").gold += 1
	check(int(r.loop_state.snapshot(r, "farmer_ahe").resource_revision) == revision + 1, "Resource version changes with authority")
	paused = true
	for domain in r.world_queries.SECTIONS:
		if domain == "public": continue
		var overview: Dictionary = r.world_queries.read(r, "farmer_ahe", "query_world", {"domain": domain})
		check(overview.ok and not overview.has("items"), "Lazy overview " + domain)
		for section in overview.sections:
			var value: Dictionary = r.world_queries.read(r, "farmer_ahe", "query_world", {"domain": domain, "section": section, "id": "grain" if domain == "market" else "", "limit": 2})
			if domain == "buildings" and section in ["detail", "quote"]:
				check(not value.ok and value.error == "id_required", "Missing building ID is an explicit error")
			else: check(value.get("ok", false), "Paused domain query " + domain + ":" + str(section))
			if value.has("items"): check(value.items.size() <= 2, "Pagination " + domain)
	check(not r.world_queries.read(r, "village_public", "query_world", {"domain": "goals"}).ok, "Public cannot inspect private goals")
	# Exploration reads must expose live market state, not catalog constants.
	check(session.market.settle_day(session.market.last_settled_day + 1), "Market settles a day for the liveness probe")
	var live_items: Dictionary = r.world_queries.read(r, "farmer_ahe", "query_world", {"domain": "market", "section": "items", "query": "grain", "limit": 10})
	var grain_rows: Array = live_items.get("items", []).filter(func(row): return str(row.get("id", "")) == "grain")
	check(grain_rows.size() == 1, "Market list exposes the grain row")
	if grain_rows.size() == 1:
		check(int(grain_rows[0].mid_price) == session.market.get_mid_price("grain"), "Market list mid_price is live")
		check(int(grain_rows[0].stock) == session.market.get_stock("grain"), "Market list stock is live")
		check(int(grain_rows[0].mid_price) != int(r.GameDataScript.get_item("grain").base_price), "Market list is not the catalog constant")
		# Merchant-era liveness: rows expose confirmed incoming supply and track shipment changes.
		var merchant: RefCounted = session.living_world.merchant
		var base_incoming: int = merchant.incoming("grain")
		check(int(grain_rows[0].get("incoming", -1)) == base_incoming, "Market list incoming matches merchant state")
		session.market.merchant.shipments["liveness-probe"] = {"id": "liveness-probe", "direction": "import", "item_id": "grain", "status": "transit", "quantity": 7}
		var moved: Dictionary = r.world_queries.read(r, "farmer_ahe", "query_world", {"domain": "market", "section": "items", "query": "grain", "limit": 10})
		var moved_rows: Array = moved.get("items", []).filter(func(row): return str(row.get("id", "")) == "grain")
		check(moved_rows.size() == 1 and int(moved_rows[0].get("incoming", -1)) == base_incoming + 7, "Market list incoming tracks merchant shipments")
		session.market.merchant.shipments.erase("liveness-probe")
	# Trace regressions: multi-item searches, exact batch quotes, physical arrival.
	var multiple: Dictionary = r.world_queries.read(r, "farmer_ahe", "query_world", {"domain": "market", "query": "iron_ingot iron_ore coal", "limit": 10})
	for item in ["iron_ingot", "iron_ore", "coal"]:
		check(multiple.items.any(func(row): return row.id == item), "Multi-term market search finds " + item)
	var batch: Dictionary = r.world_queries.read(r, "farmer_ahe", "query_world", {"domain": "market", "ids": ["iron_ingot", "coal"], "limit": 10})
	check(batch.ok and batch.items.size() == 2, "Exact market detail batch does not consume one read per item")
	var missing: Dictionary = r.world_queries.read(r, "farmer_ahe", "query_world", {"domain": "market", "section": "detail", "query": "bread flour egg"})
	check(not missing.ok and missing.error == "id_required", "Missing ID is an error, never an empty successful quote")
	var alias: Dictionary = r.world_queries.read(r, "farmer_ahe", "query_world", {"domain": "market", "section": "prices", "query": "coal"})
	check(alias.ok and not alias.items.is_empty(), "Legacy price section yields a useful current search")
	var body: Node3D = session.living_world.actor("xuezhe_lin")
	var original_position := body.position
	body.position = Vector3.ZERO
	var self_view: Dictionary = r.world_queries.read(r, "xuezhe_lin", "query_world", {"domain": "self", "section": "activity"})
	check(not self_view.data.activity.has("region_id"), "Public region is no longer represented as physical arrival")
	check(self_view.data.field_sites.all(func(row): return not row.arrived), "Distant body reports not arrived")
	check(self_view.data.field_sites.all(func(row): return row.next_action == "survey"), "Distant sites expose survey including travel")
	body.position = session.living_world.knowledge.site("creek")
	var map_view: Dictionary = r.world_queries.read(r, "xuezhe_lin", "query_world", {"domain": "map", "section": "regions", "id": "creek"})
	check(map_view.items.size() == 1 and map_view.items[0].arrived and map_view.items[0].next_action == "survey", "Arrival uses the executor site and distance threshold")
	body.position = original_position
	var map_places: Dictionary = r.world_queries.read(r, "xuezhe_lin", "query_world", {"domain": "map", "section": "regions"})
	check(map_places.items.any(func(row): return row.id == "golf") and map_places.next_cursor == -1, "Default map page includes golf without requiring another page")
	var golf: Dictionary = r.world_queries.read(r, "xuezhe_lin", "query_world", {"domain": "map", "query": "高尔夫"})
	check(golf.ok and golf.items.size() == 1 and golf.items[0].id == "golf", "Chinese golf search discovers the real course")
	var by_id: Dictionary = r.world_queries.read(r, "xuezhe_lin", "query_world", {"domain": "map", "id": "golf"})
	check(by_id.ok and by_id.items.size() == 1, "Map ID lookup defaults to regions rather than returning overview")
	if golf.items.size() == 1:
		var course: Dictionary = golf.items[0]
		var entrance: Vector2 = preload("res://scripts/farm3d/golf_course_data.gd").ENTRANCE
		check(Vector2(course.position.x, course.position.z) == entrance and course.holes == 7, "Map uses authoritative course entrance and holes")
		check(Vector2(course.spectator_position.x, course.spectator_position.z) == session.living_world.social.SITES.golf, "Spectator site matches actual social activity destination")
		check(course.navigation_action.tool_name == "move" and course.activity_queries[0].query == "golf", "Golf routes through movement and social discovery, not field survey")
		var path: Array = session.living_world.work.paths.find_path_cells(session.grid.world_to_grid(body.position.x, body.position.z), session.grid.world_to_grid(entrance.x, entrance.y))
		check(not path.is_empty(), "Course entrance is reachable on actual navigation grid")
	var mill: BuildingInstance = session.buildings.get_all_buildings()[0]
	var building_id: String = EconomyProgressionSystem.building_key(mill)
	var detail: Dictionary = r.world_queries.read(r, "lao_li", "query_world", {"domain": "buildings", "section": "detail", "id": building_id})
	check(detail.ok and not detail.items[0].production.has("service_records") and detail.items[0].has("rental_fees"), "Building read contains current terms, not historical customer orders")
	var before: Dictionary = session.npc_economy.to_dict()
	var quote: Dictionary = r.world_queries.read(r, "lao_li", "query_world", {"domain": "buildings", "section": "quote", "id": building_id, "recipe_id": "flour", "batches": 2})
	check(quote.ok and quote.data.ok and quote.data.fee > 0 and quote.data.action.arguments.max_fee == quote.data.fee, "Paid quote supplies total fee and actionable arguments")
	check(before == session.npc_economy.to_dict() and mill.producer_state.jobs.is_empty(), "Quote neither charges nor starts production")
	if quote.ok:
		var a: Dictionary = quote.data.action.arguments
		var placed: Dictionary = session.production.start_rented_recipe(mill, "lao_li", a.recipe_id, a.batches, a.max_fee, "query-quote-regression")
		check(placed.ok, "Authoritative quote executes without rental_price_changed")
		check(session.npc_economy.get_npc_state("lao_li").gold == int(before.npc_states.filter(func(n): return n.npc_id == "lao_li")[0].gold) - int(quote.data.fee), "Actual order debits exactly the quoted fee")
	paused = false
	var args := {"description": "核实面包需求", "source_event_ids": [], "ttl_minutes": 600, "review_in_minutes": 30}
	check(preload("res://scripts/ai_agent/agent_loop_state.gd").valid_goal("adopt_short_term_goal", args), "Goal contract")
	var command := {"protocol_version": 2, "request_id": "goal-loop", "decision_id": "goal-loop", "agent_id": "farmer_ahe", "expected_revision": r.executor.world_revision, "decision_summary": "核实需求", "actions": [{"action_id": "goal-action", "idempotency_key": "goal-action", "tool_version": 1, "tool_name": "adopt_short_term_goal", "arguments": args}]}
	var validated: Dictionary = r.validator.validate(command, r.registry, r.executor.world_revision, r.role_system)
	check(validated.ok, "Goal authorized by real validator")
	if validated.ok:
		var outcomes: Array = r.executor.execute_batch(validated.value, r._absolute_game_minute())
		check(outcomes.size() == 1 and outcomes[0].status == "completed", "Goal executes as real action")
		check(r.executor.execute_batch(validated.value, r._absolute_game_minute())[0].status == "completed" and r.loop_state.goals.size() == 1, "Goal action idempotent")
	r.scheduler._pending["farmer_ahe"] = {"trigger": "event", "game_minute": 0, "dialogue": "", "priority": 2}
	var saved: Dictionary = r.to_dict()
	check(r.validate_dict(saved), "Runtime snapshot validates Loop state")
	check(r.from_dict(saved), "Runtime reloads Loop state")
	check(r.loop_state.goals.size() == 1, "Short goal survives restore")
	check(r.scheduler._pending.has("farmer_ahe"), "Coalesced event trigger survives restore")
	var condition_args := args.duplicate(true)
	condition_args.success_condition = {"kind": "inventory_at_least", "id": "grain", "quantity": 2}
	check(r.loop_state.command("farmer_ahe", "adopt_short_term_goal", condition_args, "conditional", r._absolute_game_minute()).ok, "Goal has a typed completion condition")
	var goal: Dictionary = r.loop_state.goals.values().filter(func(g): return not g.get("success_condition", {}).is_empty())[0]
	session.npc_economy.get_npc_state("farmer_ahe").inventory.grain = 2
	r.loop_state.evaluate_goals(r, r._absolute_game_minute())
	check(goal.status == "completed", "Only authoritative inventory completes goal")
	check(r.loop_state.command("farmer_ahe", "adopt_short_term_goal", condition_args, "expired", r._absolute_game_minute()).ok, "Second conditional goal accepted")
	var expiring: Dictionary = r.loop_state.goals.values().filter(func(g): return g.status == "active" and not g.get("success_condition", {}).is_empty())[0]
	r.loop_state.evaluate_goals(r, int(expiring.expires_at))
	check(expiring.status == "expired", "Expiry takes precedence over late goal completion")
	r.loop_state.loops["receipt-test"] = {"agent_id": "farmer_ahe", "trigger": "schedule", "state": "executing", "action_ids": ["rejected-action", "skipped-action"], "receipts": {"rejected-action": {"action_id": "rejected-action", "status": "rejected", "tool_name": "plant"}}}
	r.loop_state.finish_batches(r, r._absolute_game_minute())
	check(r.loop_state.loops["receipt-test"].state == "closed", "Rejected first action closes batch with skipped remainder")
	check(r.loop_state.feedback.farmer_ahe.pending, "Failed action schedules bounded follow-up")
	r.session_trace.finish_error("farmer_ahe", "receipt-test", "fixture")
	var receipt := {"agent_id": "farmer_ahe", "action_id": "rejected-action", "idempotency_key": "rejected-action", "status": "rejected", "tool_name": "plant", "failure_code": "insufficient_inventory"}
	r._record_world_action_outcome(receipt)
	r._record_world_action_outcome(receipt)
	var recorded: Array = r.session_trace.get_request("receipt-test").action_events
	check(recorded.size() == 1 and recorded[0].metadata.failure_code == "insufficient_inventory", "Runtime traces action outcomes once, including failures")
	var pending: Array = r.loop_state.events("farmer_ahe")
	check(not pending.is_empty(), "Events survive restore before acknowledgement")
	if not pending.is_empty():
		r.loop_state.acknowledge("farmer_ahe", [pending[0].event_id])
		check(r.loop_state.events("farmer_ahe").size() == pending.size()-1, "Only acknowledged events removed")
	var file := FileAccess.open("res://tmp/agent-refactor/game-request.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(request))
	file.close()
	scene.queue_free()
	await process_frame
	print("Agent Loop: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
