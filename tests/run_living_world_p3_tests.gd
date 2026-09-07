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

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var s: Farm3DSession = scene.farm_session
	s.season.set_process(false)
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P3"), "P3 isolated formal world")
	var w: Node = s.living_world
	var projects: RefCounted = w.projects
	var mill: BuildingInstance = s.buildings.get_all_buildings()[0]
	var npc: NpcEconomyState = s.npc_economy.get_npc_state("lao_li")
	var original: Dictionary = npc.to_dict()
	var plan := {"goal": "购买谷物加工面粉后出售，积累创业资金", "budget": 300, "deadline_minutes": 500, "materials": {}, "steps": [
		step("buy", "buy", [], {"item_id": "grain", "quantity": 2, "limit": 296}),
		step("mill", "rent", ["buy"], {"building_id": mill.instance_id, "recipe_id": "flour", "batches": 1, "max_fee": 4}),
		step("ready", "wait_production", ["mill"], {"order_step": "mill"}),
		step("sell", "sell", ["ready"], {"item_id": "flour", "quantity": 1, "limit": 1})]}
	check(projects.submit("lao_li", "profit", plan).ok and npc.gold == 700, "Project budget debited once into escrow")
	check(projects.submit("lao_li", "profit", plan).ok and npc.gold == 700, "Duplicate proposal is idempotent")
	check(not projects.submit("lao_li", "other", plan).ok, "Only one primary project")
	var corrupt: Dictionary = plan.duplicate(true)
	corrupt.steps[0].depends_on = ["sell"]
	check(not projects.valid_plan(corrupt), "Cycles rejected")
	corrupt = plan.duplicate(true)
	corrupt.steps[0].capability = "create_money"
	check(not projects.valid_plan(corrupt), "Unsupported capabilities rejected")
	projects.advance()
	check(projects.projects.profit.steps.buy.status == "done" and int(projects.projects.profit.items.grain) == 2, "Purchase uses market and project materials escrow")
	var after_buy: Dictionary = s.market.to_dict()
	check(s.save_game() and s.load_game(), "Project cursor and escrow persist")
	npc = s.npc_economy.get_npc_state("lao_li")
	mill = s.buildings.get_all_buildings()[0]
	projects.advance()
	check(s.market.to_dict() == after_buy and mill.producer_state.jobs.size() == 1, "Reload does not duplicate purchase; queues actual production")
	projects.advance()
	check(projects.projects.profit.steps.ready.status == "waiting", "Waits for actual production")
	check(s.save_game() and s.load_game(), "In-flight rental project persists")
	mill = s.buildings.get_all_buildings()[0]
	s.production.advance_minutes(60)
	check(projects.projects.profit.steps.mill.result.delivered and int(projects.projects.profit.items.get("flour", 0)) == 1, "Production event captures only owned project output")
	for n in 4: projects.advance()
	check(projects.projects.profit.status == "completed" and int(projects.projects.profit.gold) == 0, "Accepted project completes independently of model")
	var receipt: Dictionary = projects.projects.profit
	var expected_gold := int(original.gold) - int(receipt.steps.buy.result.cost) - 4 + int(receipt.steps.sell.result.income)
	check(s.npc_economy.get_npc_state("lao_li").gold == expected_gold, "All project charges and sale income reconcile to restored actor wallet")
	check(s.save_game() and s.load_game(), "Completed project receipt persists")
	var completed: Dictionary = w.to_dict()
	projects.advance()
	check(w.to_dict() == completed, "Completed project cannot sell twice")
	var impossible: Dictionary = plan.duplicate(true)
	impossible.budget = 1000000
	check(not projects.submit("lao_li", "too-much", impossible).ok, "No overcommitment")
	var blocked := {"goal": "价格合适才采购", "budget": 5, "deadline_minutes": 60, "materials": {}, "steps": [step("buy", "buy", [], {"item_id": "grain", "quantity": 2, "limit": 1})]}
	check(projects.submit("lao_li", "blocked", blocked).ok, "Bounded price-limit project accepted")
	projects.advance()
	var attempts: int = projects.projects.blocked.steps.buy.attempts
	for n in 10: projects.advance()
	check(projects.projects.blocked.steps.buy.attempts == attempts, "Blocked step does not retry in a loop")
	check(projects.retry("lao_li", "blocked").ok, "Explicit new decision can revalidate")
	check(projects.cancel("lao_li", "blocked").ok, "Cancel releases unused budget")
	check(projects.suggest("lao_li", "暂缓高价采购", 30).ok, "Temporary behavioral suggestion recorded")
	s.season.advance_game_minutes(31)
	check(not projects.suggestions.has("lao_li"), "Suggestion expires without permanent goal overwrite")
	mill = s.buildings.get_all_buildings()[0]
	check(s.production.start_rented_recipe(mill, "farmer_ahe", "flour", 1, 4, "busy-1").ok and s.production.start_rented_recipe(mill, "farmer_ahe", "flour", 1, 4, "busy-2").ok, "Other customer occupies shared queue")
	var queued := {"goal": "容量释放后再加工", "budget": 4, "deadline_minutes": 120, "materials": {"grain": 2}, "steps": [step("rent", "rent", [], {"building_id": mill.instance_id, "recipe_id": "flour", "batches": 1, "max_fee": 4}), step("ready", "wait_production", ["rent"], {"order_step": "rent"})]}
	check(projects.submit("lao_li", "capacity", queued).ok, "Capacity-bound project escrows its own materials")
	projects.advance()
	check(projects.projects.capacity.steps.rent.status == "blocked", "Full queue waits without repeated mutations")
	s.production.advance_minutes(30)
	check(projects.projects.capacity.steps.rent.status == "pending", "Other customer's completion event wakes the correct queue dependency")
	projects.advance()
	check(projects.projects.capacity.steps.rent.status == "done", "Revalidated capacity allows one actual order")
	check(s.production.building_service.cancel(mill, "lao_li", "capacity:rent").ok, "Unstarted project order may be cancelled")
	check(int(projects.projects.capacity.items.grain) == 2 and int(projects.projects.capacity.gold) == 4, "Cancelled queue returns input and fee to project escrow")
	check(projects.cancel("lao_li", "capacity").ok, "Cancelled committed work no longer traps the project")
	check(s.save_game() and s.load_game(), "Cancelled project and production receipts recover together")
	print("P3: %d checks, %d failures" % [checks, failures])
	scene.free()
	quit(0 if failures == 0 else 1)

func step(id: String, cap: String, deps: Array, args: Dictionary) -> Dictionary:
	return {"id": id, "capability": cap, "depends_on": deps, "arguments": args}
