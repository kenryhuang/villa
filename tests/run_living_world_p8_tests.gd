extends SceneTree

var checks := 0
var failures: Array[String] = []
var scene: Node
var session: Node
var world: Node

func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("P8 timeout"); quit(1))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func terms(worker := "lao_li") -> Dictionary:
	return {"worker_id": worker, "recipient_id": "village_inn", "kind": "delivery", "item_id": "grain", "quantity": 2, "wage": 20, "building_id": "", "recipe_id": "", "max_fee": 0, "deadline_minutes": 500, "cycles": 1, "interval_minutes": 0, "parent_contract": "", "note": "Deliver real grain"}

func _run() -> void:
	scene = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	session = scene.get_node("FarmSession")
	world = session.living_world
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P8"), "P8 isolated fixture uses original modeled windmill")
	session.season.set_process(false)
	scene.set_process(false)
	session.player.set_physics_process(false)
	world.set_process(false)
	check(not session.auto_save and not session.auto_restore, "P8 cannot touch real player save")
	var work = world.work
	session.inventory.add_item("grain", 20)
	root.get_node("GameState").gold = 2000
	var worker: Node3D = world.actor("lao_li")
	session.player.position = Vector3(-12.5, 0, 22.5)
	worker.position = Vector3(-11.5, 0, 22.5)
	worker.move_speed = 8
	var original_gold: int = world.assets.current().available_gold("player")
	var worker_gold: int = world.assets.current().available_gold("lao_li")
	var receiver_grain: int = world.assets.available_items("village_inn").get("grain", 0)
	check(work.propose("player", "p8-delivery", terms()).ok, "Player proposes paid delivery without forced NPC acceptance")
	check(int(world.assets.current().available_gold("player")) == original_gold, "Proposal does not spend funds")
	var revised := terms()
	revised.wage = 25
	check(work.counter("lao_li", "p8-delivery", 1, revised).ok, "NPC can counter with a higher wage")
	check(not work.accept("player", "p8-delivery", 1).ok, "Old quoted version cannot be accepted")
	check(work.accept("player", "p8-delivery", 2).ok, "Player accepts NPC counteroffer")
	check(original_gold - int(world.assets.current().available_gold("player")) == 25, "Only accepted wage is escrowed")
	check(work.propose("player", "p8-overlap", terms()).ok and not work.accept("lao_li", "p8-overlap", 1).ok, "Worker cannot accept overlapping jobs")
	var saved: Dictionary = work.to_dict()
	check(work.validate(saved), "Active work validates for save")
	var corrupt := saved.duplicate(true)
	corrupt.contracts["p8-delivery"].gold += 1
	check(not work.validate(corrupt), "Forged escrow money is rejected")
	check(session.save_game() and session.load_game(), "Full v10 save reload preserves active work")
	worker = world.actor("lao_li")
	work.restore(saved)
	check(work.owns_schedule("lao_li"), "Reload retains occupied schedule")
	for frame in 1400:
		work.advance()
		await physics_frame
		if work.contracts["p8-delivery"].status == "completed": break
	if work.contracts["p8-delivery"].status != "completed": print("WORK DIAG ", work.contracts["p8-delivery"], " position ", worker.position, " target ", work.location("village_inn"))
	check(work.contracts["p8-delivery"].status == "completed", "Worker physically visits pickup and delivery locations")
	check(int(world.assets.available_items("village_inn").get("grain", 0)) == receiver_grain + 2, "Recipient receives actual escrowed grain")
	check(int(world.assets.current().available_gold("lao_li")) == worker_gold + 25, "Wage paid only on actual delivery")
	work.advance()
	check(int(world.assets.current().available_gold("lao_li")) == worker_gold + 25, "Repeated tick cannot pay twice")
	check(work.propose("player", "p8-cancel", terms()).ok and work.accept("lao_li", "p8-cancel", 1).ok, "A second funded contract can start after completion")
	var money_after_accept: int = world.assets.current().available_gold("player")
	check(work.cancel("player", "p8-cancel", 2).ok, "Accepted work can be cancelled")
	work.advance()
	check(int(world.assets.current().available_gold("player")) == money_after_accept + 20 and work.contracts["p8-cancel"].status == "cancelled", "Unspent wage is refunded exactly once")
	work.propose("player", "p8-insolvent", terms())
	root.get_node("GameState").gold = 0
	check(not work.accept("lao_li", "p8-insolvent", 1).ok, "Unfunded employer cannot hire")
	root.get_node("GameState").gold = 2000
	_subcontracts(work)
	var trainee: Node3D = world.actor("xuezhe_lin")
	trainee.position = work.location("village_inn") + Vector3(1, 0, 0)
	world.board.daily(1)
	var school_gold: int = world.assets.current().available_gold("village_inn") + world.society.wage_escrow()
	check(work.start_activity("xuezhe_lin", "p8-learning", "learning", "village_inn").ok, "Training reserves actual fee")
	work.advance()
	session.season.advance_game_minutes(60)
	work.advance()
	check(not work.has_skill("xuezhe_lin", "ingredient_selection"), "Partial study does not unlock ability")
	check(work.validate(work.to_dict()), "Training can be saved midway")
	work.restore(work.to_dict())
	session.season.advance_game_minutes(60)
	work.advance()
	check(work.has_skill("xuezhe_lin", "ingredient_selection"), "Training resumes and unlocks skill after full study time")
	check(int(world.assets.current().available_gold("village_inn")) + world.society.wage_escrow() == school_gold + 30, "Training provider receives actual fee")
	check(not work.start_activity("xuezhe_lin", "p8-repeat", "learning", "village_inn").ok, "Already learned skill cannot charge twice")
	check(not work.start_activity("xuezhe_lin", "p8-learning", "rest", "village_inn").ok, "Existing activity proof cannot be overwritten")
	var bad: Dictionary = work.to_dict()
	bad.activities["p8-learning"].worked = 0
	check(not work.validate(bad), "A fabricated training completion is rejected")
	var sites: Array = world.construction.sites("lao_li", "food_workshop")
	check(not sites.is_empty(), "Food workshop has real legal sites and costs")
	if not sites.is_empty():
		var site: Dictionary = sites[0]
		check(world.construction.reserve("lao_li", "p8-workshop", site.gx, site.gz, 360, "food_workshop").ok, "NPC reserves a food workshop footprint")
		world.assets.apply("lao_li", world.construction.cost("food_workshop"), 0)
		worker.position = Vector3(site.approach.x, 0, site.approach.z)
		var built: Dictionary = world.construction.start("lao_li", "p8-build", "p8-workshop")
		check(built.ok, "NPC builds food workshop using original placement and materials")
		if built.ok:
			var building: BuildingInstance = world.building(built.building_id)
			check(building.owner_id == "lao_li" and building.building_id == "food_workshop", "Food workshop model and ownership are preserved")
			check(not work.command("xuezhe_lin", "manage_building", {"building_id": building.instance_id, "operation": "pricing", "fee": 4, "version": 1}, "p8-theft").ok, "Foreign actor cannot change owner pricing")
			building._process(20.0)
			check(work.command("lao_li", "manage_building", {"building_id": building.instance_id, "operation": "open", "fee": 0, "version": 1}, "p8-open").ok, "Owner can open completed workshop to customers")
			world.assets.apply("xuezhe_lin", {"creek_crucian": 2, "salt": 1}, 100)
			var learned_plan := {"goal": "Use learned ingredient selection to cook actual fish", "budget": 50, "deadline_minutes": 360, "materials": {"creek_crucian": 2, "salt": 1}, "steps": [{"id": "cook", "capability": "rent", "depends_on": [], "arguments": {"building_id": building.instance_id, "recipe_id": "grilled_fish", "batches": 1, "max_fee": 50}}, {"id": "ready", "capability": "wait_production", "depends_on": ["cook"], "arguments": {"order_step": "cook"}}]}
			check(world.projects.submit("xuezhe_lin", "p8-trained-cook", learned_plan).ok, "Trained NPC starts actual tagged-ingredient project")
			world.projects.advance()
			if building.producer_state.jobs.is_empty(): print("COOK DIAG ", world.projects.projects.get("p8-trained-cook"))
			check(not building.producer_state.jobs.is_empty(), "Learned ability resolves real fish inputs into production queue")
			session.production.advance_minutes(180)
			world.projects.advance()
			world.projects.advance()
			check(int(world.assets.available_items("xuezhe_lin").get("grilled_fish", 0)) >= 2, "Training produces usable food through original recipe executor")
	check(world.construction.validate(world.construction.to_dict()), "Generalized construction saves validate")
	var venture_plan := {"goal": "Sell pooled grain and split actual proceeds", "budget": 0, "deadline_minutes": 180, "materials": {"grain": 4}, "steps": [{"id": "sell", "capability": "sell", "depends_on": [], "arguments": {"item_id": "grain", "quantity": 4, "limit": 1}}]}
	world.assets.apply("lao_li", {"grain": 4}, 0)
	world.assets.apply("farmer_ahe", {"grain": 2}, 0)
	var joint := {"partner_id": "farmer_ahe", "plan": venture_plan, "partner_gold": 0, "partner_materials": {"grain": 2}, "partner_profit_percent": 50}
	check(work.propose_venture("lao_li", "p8-joint", joint).ok, "Private joint investment carries exact contributions and profit split")
	check(not work.accept_venture("xuezhe_lin", "p8-joint", 1).ok, "Nonparticipant cannot accept investment")
	var partner_before: int = world.assets.current().available_gold("farmer_ahe")
	var owner_before: int = world.assets.current().available_gold("lao_li")
	check(work.accept_venture("farmer_ahe", "p8-joint", 1).ok, "Partner contribution enters original project escrow")
	check(world.assets.current().available_gold("farmer_ahe") == partner_before, "Expected sale does not pay advance profit")
	world.projects.advance()
	world.projects.advance()
	var v: Dictionary = work.ventures["p8-joint"]
	check(v.status == "completed" and not v.settlement.is_empty(), "Joint project settles after actual market sale")
	if not v.settlement.is_empty():
		check(world.assets.current().available_gold("farmer_ahe") - partner_before == int(v.settlement.partner_gold), "Partner receives contracted share of actual proceeds")
		check(world.assets.current().available_gold("lao_li") - owner_before == int(v.settlement.owner_gold), "Operator receives remaining actual proceeds")
		var pair_income: int = world.assets.current().available_gold("lao_li") + world.assets.current().available_gold("farmer_ahe") - owner_before - partner_before
		check(pair_income == int(v.settlement.cash), "No cooperation template reward is minted")
		world.projects.advance()
		check(world.assets.current().available_gold("lao_li") + world.assets.current().available_gold("farmer_ahe") - owner_before - partner_before == pair_income, "Joint proceeds are distributed only once")
	check(work.validate(work.to_dict()), "Work and investment save validates after settlement")
	await _processing(work)
	_equipment(work)
	var save: Dictionary = world.to_dict()
	check(world.validate(save), "Extended living world validates with prior P0-P7 state")
	print("P8: %d checks, %d failures" % [checks, failures.size()])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _processing(work: RefCounted) -> void:
	var mill: BuildingInstance = session.buildings.get_all_buildings()[0]
	var worker: Node3D = world.actor("farmer_ahe")
	var finder := GridPathfinder.new()
	finder.configure(session.grid)
	var path := finder.find_path_to_interaction(session.player.position, mill, 2.6)
	check(not path.is_empty(), "Processing fixture has a reachable workshop")
	if path.is_empty(): return
	worker.position = path.back()
	session.player.position = path.back() + Vector3(.2, 0, .2)
	worker.move_speed = 12
	var args := terms("farmer_ahe")
	args.kind = "processing"
	args.item_id = "flour"
	args.quantity = 1
	args.building_id = mill.instance_id
	args.recipe_id = "flour"
	args.max_fee = 10
	var before: int = world.assets.available_items("village_inn").get("flour", 0)
	check(work.propose("player", "p8-processing", args).ok and work.accept("farmer_ahe", "p8-processing", 1).ok, "Player can fund NPC processing with real grain")
	for frame in 60:
		work.advance()
		await physics_frame
		if not work.contracts["p8-processing"].order_id.is_empty(): break
	check(not work.contracts["p8-processing"].order_id.is_empty(), "Worker arrives and starts original processing order")
	var saved: bool = session.save_game()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.save_path))
	if not session._valid_save(data): print("SAVE DIAG world=", world.validate_save(data), " agents=", session.agent_runtime.validate_dict(data.agents))
	check(saved and session.load_game(), "Contract and linked production survive full reload")
	world.actor("farmer_ahe").move_speed = 12
	session.production.advance_minutes(120)
	check(int(work.contracts["p8-processing"].items.get("flour", 0)) == 1, "Player employer output remains reserved for physical delivery")
	for frame in 2400:
		work.advance()
		await physics_frame
		if work.contracts["p8-processing"].status == "completed": break
	check(work.contracts["p8-processing"].status == "completed", "NPC completes physical processed-goods delivery")
	check(int(world.assets.available_items("village_inn").get("flour", 0)) == before + 1, "Recipient receives exactly the contracted output")
	check(work.validate(work.to_dict()), "Processing conservation and receipts validate")

func _equipment(work: RefCounted) -> void:
	var mill: BuildingInstance = session.buildings.get_all_buildings()[0]
	world.assets.apply("lao_li", {"grain": 2}, 0)
	var plan := {"goal": "Equipment owner shares realized flour sales", "budget": 0, "deadline_minutes": 500, "materials": {"grain": 2}, "steps": [{"id": "mill", "capability": "rent", "depends_on": [], "arguments": {"building_id": mill.instance_id, "recipe_id": "flour", "batches": 1, "max_fee": 0}}, {"id": "ready", "capability": "wait_production", "depends_on": ["mill"], "arguments": {"order_step": "mill"}}, {"id": "sale", "capability": "sell", "depends_on": ["ready"], "arguments": {"item_id": "flour", "quantity": 1, "limit": 1}}]}
	var a := {"partner_id": "player", "plan": plan, "partner_gold": 0, "partner_materials": {}, "partner_profit_percent": 30, "equipment_id": mill.instance_id}
	check(work.propose_venture("lao_li", "p8-equipment", a).ok, "NPC proposes equipment use for actual revenue share")
	check(not work.contributes_equipment(mill, "lao_li", "p8-equipment"), "Unaccepted equipment proposal grants no access")
	check(work.accept_venture("player", "p8-equipment", 1).ok, "Actual equipment owner consents to defined project use")
	check(not work.contributes_equipment(mill, "lao_li", "unrelated"), "Equipment contribution cannot waive fees on unrelated jobs")
	var before: int = world.assets.current().available_gold("player")
	world.projects.advance()
	check(not mill.producer_state.jobs.is_empty() and int(mill.producer_state.jobs[0].rental_fee) == 0, "Equipment replaces rental fee only in accepted project")
	check(world.assets.current().available_gold("player") == before, "No expected sales paid to equipment contributor")
	session.production.advance_minutes(120)
	for tick in 4: world.projects.advance()
	var v: Dictionary = work.ventures["p8-equipment"]
	check(v.status == "completed" and world.assets.current().available_gold("player") - before == int(v.settlement.get("partner_gold", -1)), "Equipment contributor receives share after actual market receipts")
	check(not work.contributes_equipment(mill, "lao_li", "p8-equipment"), "Completed project cannot keep using contributed equipment free")
	check(session.save_game() and session.load_game(), "Equipment settlement and exact project proof survive full reload")

func _subcontracts(work: RefCounted) -> void:
	var parent := terms("farmer_ahe")
	check(work.propose("lao_li", "p8-prime", parent).ok and work.accept("farmer_ahe", "p8-prime", 1).ok, "Prime contractor has an actual funded obligation")
	var child := terms("xuezhe_lin")
	child.parent_contract = "p8-prime"
	check(work.propose("farmer_ahe", "p8-child", child).ok and work.accept("xuezhe_lin", "p8-child", 1).ok, "Prime worker can fund a separate voluntary subcontract")
	var loop := terms("lao_li")
	loop.parent_contract = "p8-child"
	check(not work.propose("xuezhe_lin", "p8-cycle", loop).ok, "Subcontract chain cannot cycle back to an ancestor")
	check(work.cancel("farmer_ahe", "p8-child", 2).ok and work.contracts["p8-prime"].status == "queued", "Subcontract cancellation never marks prime obligation delivered")
	work.cancel("lao_li", "p8-prime", 2)
	work.advance()
	check(work.contracts["p8-child"].status == "cancelled" and work.contracts["p8-prime"].status == "cancelled", "Each cancelled contract returns its own unspent assets")
	check(work.validate(work.to_dict()), "Subcontract proof chain survives validation")
