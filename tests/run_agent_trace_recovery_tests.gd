extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func step(id: String, capability: String, deps: Array, arguments: Dictionary) -> Dictionary:
	return {"id": id, "capability": capability, "depends_on": deps, "arguments": arguments}

func publish(board: RefCounted, id: String) -> bool:
	return board.demand(id, "player", "flour", 2) and board.publish("player", id, {"demand_id": id, "item_id": "flour", "quantity": 2, "unit_reward": 20, "max_claims": 2, "deadline_minutes": 60, "kind": "purchase"}).ok

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var s: Farm3DSession = scene.farm_session
	s.season.set_process(false)
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P5"), "Isolated formal farm fixture")
	s.save_path = "res://tmp/living-world/trace-recovery.json"
	var w: Node = s.living_world
	w.set_process(false)
	var board: RefCounted = w.board
	var projects: RefCounted = w.projects
	var npc: NpcEconomyState = s.npc_economy.get_npc_state("lao_li")
	var before: Dictionary = npc.to_dict()
	var plan := {"goal": "完成面粉委托", "budget": 100, "deadline_minutes": 300, "materials": {"grain": 2}, "steps": [
		step("buy", "buy", [], {"item_id": "grain", "quantity": 1, "limit": 90}),
		step("claim", "claim", [], {"commission_id": "stale", "quantity": 2})]}
	check(publish(board, "stale"), "Publish expiring commission")
	board.commissions.stale.deadline = w.minute()
	board.advance()
	var result: Dictionary = projects.submit("lao_li", "stale-plan", plan)
	check(not result.ok and result.error == "commission_unavailable" and result.step_id == "claim", "Stale commission rejected before escrow with actionable step")
	check(npc.to_dict() == before and not projects.projects.has("stale-plan"), "Rejected plan cannot debit money or materials")
	check(publish(board, "race"), "Publish race fixture")
	plan.steps[1].arguments.commission_id = "race"
	check(projects.submit("lao_li", "race-plan", plan).ok, "Currently available goal accepted")
	check(board.claim("farmer_ahe", "other-claim", "race", 2).ok, "Another actor claims quota before first project step")
	var market_before: Dictionary = s.market.to_dict()
	projects.advance()
	check(projects.projects["race-plan"].status == "cancelled" and npc.to_dict() == before, "Lost commission cancels safely and refunds escrow")
	check(s.market.to_dict() == market_before and projects.projects["race-plan"].steps.buy.status == "pending", "No independent purchase executes after goal becomes invalid")
	projects.advance()
	check(npc.to_dict() == before, "Cancellation refund is idempotent")
	check(publish(board, "quota"), "Publish aggregate quota fixture")
	var duplicate: Dictionary = plan.duplicate(true)
	duplicate.steps = [step("a", "claim", [], {"commission_id": "quota", "quantity": 2}), step("b", "claim", [], {"commission_id": "quota", "quantity": 1})]
	check(not projects.submit("lao_li", "duplicate-quota", duplicate).ok and npc.to_dict() == before, "Plan cannot overbook quota using multiple claim steps")
	check(publish(board, "in-flight"), "Publish in-flight production fixture")
	var mill: BuildingInstance = s.buildings.get_all_buildings()[0]
	plan.steps = [step("claim", "claim", [], {"commission_id": "in-flight", "quantity": 1}),
		step("mill", "rent", ["claim"], {"building_id": mill.instance_id, "recipe_id": "flour", "batches": 1, "max_fee": 4}),
		step("ready", "wait_production", ["mill"], {"order_step": "mill"}),
		step("deliver", "deliver", ["claim", "ready"], {"claim_step": "claim", "quantity": 1, "order_step": ""}),
		step("buy", "buy", [], {"item_id": "grain", "quantity": 1, "limit": 90})]
	check(projects.submit("lao_li", "in-flight-plan", plan).ok, "Production project accepted")
	projects.advance()
	projects.advance()
	check(projects.projects["in-flight-plan"].steps.mill.result.has("order_id"), "Real rental order committed before expiry")
	board.commissions["in-flight"].deadline = w.minute()
	board.advance()
	projects.advance()
	check(projects.projects["in-flight-plan"].status == "active" and projects.projects["in-flight-plan"].steps.buy.status == "pending", "Expired goal waits for committed goods without new spending")
	check(s.save_game() and s.load_game(), "Aborting in-flight project survives save and reload")
	s.production.advance_minutes(60)
	projects.advance()
	npc = s.npc_economy.get_npc_state("lao_li")
	check(projects.projects["in-flight-plan"].status == "cancelled" and npc.gold == int(before.gold) - 4, "Only actual processing fee is spent; unused budget returned")
	check(int(npc.inventory.get("grain", 0)) == int(before.inventory.grain) - 2 and int(npc.inventory.get("flour", 0)) == int(before.inventory.get("flour", 0)) + 1, "Completed flour returned once with exact consumed ingredients")
	check(s.save_game() and s.load_game(), "Final cancellation receipt and assets validate after reload")
	check(publish(board, "valid-delivery"), "Publish valid completion fixture")
	var fulfill := {"goal": "交货后出售剩余材料", "budget": 0, "deadline_minutes": 300, "materials": {"flour": 1, "grain": 1}, "steps": [
		step("claim", "claim", [], {"commission_id": "valid-delivery", "quantity": 1}),
		step("deliver", "deliver", ["claim"], {"claim_step": "claim", "quantity": 1, "order_step": ""}),
		step("sell", "sell", ["deliver"], {"item_id": "grain", "quantity": 1, "limit": 1})]}
	check(projects.submit("lao_li", "valid-delivery-plan", fulfill).ok, "Valid claim and delivery plan accepted")
	for n in 4: projects.advance()
	check(projects.projects["valid-delivery-plan"].status == "completed" and board.claims["valid-delivery-plan:claim"].status == "completed", "Fulfilled claim does not invalidate later legitimate sale steps")
	var abandon: Dictionary = fulfill.duplicate(true)
	abandon.materials = {}
	abandon.steps = [step("claim", "claim", [], {"commission_id": "valid-delivery", "quantity": 1})]
	check(projects.submit("lao_li", "abandon-plan", abandon).ok, "Remaining quota available for another project")
	projects.advance()
	check(projects.cancel("lao_li", "abandon-plan").ok and board.commissions["valid-delivery"].claimed == 0, "Cancelling releases owned claim quota")
	var runtime: Node = s.agent_runtime
	for reason in ["game_closed", "session_changed", "client_reconfigured", "replaced", "cancelled", "dialogue_closed"]:
		var id: String = "trace-" + reason
		runtime._request_triggers[id] = "schedule"
		runtime._handle_stream_failure("lao_li", id, reason)
		var trace: Dictionary = runtime.session_trace.get_request(id)
		check(trace.status == "cancelled" and trace.error.is_empty() and trace.cancellation.code == reason, "Normal cancellation retains reason: " + reason)
	runtime._handle_stream_failure("lao_li", "trace-timeout", "provider_timeout")
	check(runtime.session_trace.get_request("trace-timeout").status == "error", "Actual timeout remains an error")
	var client = preload("res://scripts/ai_agent/agent_stream_client.gd").new()
	client.configure("http://127.0.0.1:1", "", 1)
	var cancellations: Array[String] = []
	var finished := func(_ok: bool, _response: Dictionary, reason: String): cancellations.append(reason)
	var streamed := func(_event: Dictionary): pass
	for action in ["close", "epoch", "configure"]:
		client.request_decision("lao_li", {"request_id": action}, streamed, finished)
		if action == "close": client.cancel_all("game_closed")
		elif action == "epoch": client.set_epoch(2)
		else: client.configure("http://127.0.0.1:1", "", 3)
	check(cancellations == ["game_closed", "session_changed", "client_reconfigured"], "Actual stream client propagates distinct cancellation reasons")
	client.free()
	var request: Dictionary = runtime._build_request("lao_li", "schedule", runtime._absolute_game_minute(), "")
	var quote: Dictionary = request.market_view.grain.depth.quotes[1]
	check(quote.quantity == 2 and quote.buy_total == s.market.quote_buy("grain", 2) and quote.sell_total == s.market.quote_sell("grain", 2), "Projected market depth uses actual total transaction quotes")
	check(quote.buy_available == s.market.can_buy("grain", 2), "Depth reports real stock availability independently of indicative price")
	var explorer: Node3D = w.actor("xuezhe_lin")
	explorer.position = Vector3(7, 0, -12)
	var visit := {"goal": "到市场查看交易机会", "budget": 0, "deadline_minutes": 120, "materials": {}, "steps": [step("market", "move", [], {"x": s.market_site.x, "z": s.market_site.y})]}
	check(projects.submit("xuezhe_lin", "visit-market", visit).ok, "Explorer may plan a visit using published market coordinates")
	projects.advance()
	var move: Dictionary = projects.projects["visit-market"].steps.market
	check(move.status == "waiting" and move.result.has("target"), "Market center resolves to a reachable approach instead of no_route")
	if move.result.has("target"):
		var target: Dictionary = move.result.target
		check(target.z > s.market_site.y + 3 and target.z < s.market_site.y + 6 and absf(target.x - s.market_site.x) < 4, "Approach reaches the south trading counter outside the reserved footprint")
		explorer.position = Vector3(target.x, target.y, target.z)
		projects.advance()
		projects.advance()
		check(projects.projects["visit-market"].status == "completed", "Market visit completes at its reachable counter")
	print("TRACE RECOVERY: %d checks, %d failures" % [checks, failures])
	scene.free()
	quit(0 if failures == 0 else 1)
