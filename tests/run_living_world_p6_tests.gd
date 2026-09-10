extends SceneTree

var checks := 0
var failures := 0
var scene: Node
var s: Farm3DSession
var w: Node

func _initialize() -> void:
	create_timer(100).timeout.connect(func(): push_error("P6 timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func terms(schedule := "now") -> Dictionary:
	return {"task_id": "", "version": 0, "recipient_id": "village_inn", "item_id": "grain", "quantity": 2, "reward": 5, "deadline_minutes": 180, "schedule": schedule, "note": "先配送这批现货，再继续加工"}

func step(id: String, cap: String, deps: Array, args: Dictionary) -> Dictionary:
	return {"id": id, "capability": cap, "depends_on": deps, "arguments": args}

func until(id: String, status: String) -> bool:
	for n in 1800:
		w.interruptions.advance()
		w.projects.advance()
		if w.interruptions.tasks[id].status == status: return true
		await physics_frame
	return false

func run() -> void:
	scene = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	s = scene.farm_session
	s.season.set_process(false)
	s.player.set_physics_process(false)
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P6"), "P6 isolated official scene")
	w = s.living_world
	w.set_process(false)
	var jobs: RefCounted = w.interruptions
	var p: RefCounted = w.projects
	var body: Node3D = w.actor("lao_li")
	# Only initial fixture positions are assigned. Task movement below uses actual physics/pathfinding.
	s.player.position = Vector3(-12.5, 0, 22.5)
	body.position = Vector3(-11.5, 0, 22.5)
	body.move_speed = 8
	var mill: BuildingInstance = s.buildings.get_all_buildings()[0]
	var plan := {"goal": "加工一份面粉后出售", "budget": 4, "materials": {"grain": 2}, "deadline_minutes": 500, "steps": [step("mill", "rent", [], {"building_id": mill.instance_id, "recipe_id": "flour", "batches": 1, "max_fee": 4}), step("ready", "wait_production", ["mill"], {"order_step": "mill"}), step("sale", "sell", ["ready"], {"item_id": "flour", "quantity": 1, "limit": 1})]}
	check(p.submit("lao_li", "original", plan).ok, "Original production accepted")
	check(await preload("res://tests/physical_project_step.gd").complete(self, p, "original", "mill"), "Original rental walks to its processing building")
	p.advance()
	p.advance()
	check(p.projects.original.steps.ready.status == "waiting", "Actual order is waiting")
	var before: Dictionary = w.assets.snapshot("player")
	var bad := terms()
	bad.erase("quantity")
	check(not jobs.propose("lao_li", "bad", bad).ok, "Missing quantity cannot sign a task")
	var impossible := terms()
	impossible.deadline_minutes = 1
	check(not jobs.propose("lao_li", "impossible", impossible).ok, "Physically impossible deadline rejected before any escrow")
	check(jobs.propose("lao_li", "offer", terms()).ok and w.assets.snapshot("player") == before, "NPC agreement alone cannot spend player resources")
	var ui: Control = scene.get_node("FarmInteraction").hud.commission_view
	ui.offer_delivery_draft("lao_li")
	check(paused and ui.confirm.visible, "Typed delivery card visible and game paused")
	ui.confirm.confirmed.emit()
	var id: String = jobs.tasks.keys()[0]
	check(jobs.tasks[id].status == "queued", "UI confirmation only accepts; no movement while paused")
	var escrowed: Dictionary = w.assets.snapshot("player")
	check(jobs.accept("offer").ok and w.assets.snapshot("player") == escrowed, "Repeated confirmation does not debit twice")
	jobs.advance()
	check(p.projects.original.status == "active", "Paused acceptance does not suspend or advance a project")
	ui.close_panel()
	check(not paused and not s.player._dialogue_input_blocked, "Closing task UI restores input and time")
	jobs.advance()
	check(await until(id, "delivering") and p.projects.original.status == "suspended", "Physical pickup suspends main project without cancelling order")
	var receiver_before: int = s.npc_economy.get_npc_state("village_inn").inventory.get("grain", 0)
	jobs.advance()
	check(jobs.tasks[id].status == "delivering", "A timer/tick cannot deliver from far away")
	check(s.save_game() and s.load_game(), "Cargo escrow and suspended cursor reload together")
	check(jobs.accept("offer").ok and w.assets.snapshot("player") == escrowed, "Confirmation receipt survives reload")
	mill = s.buildings.get_all_buildings()[0]
	s.production.advance_minutes(60)
	check(p.projects.original.steps.mill.result.delivered and int(p.projects.original.items.flour) == 1, "Suspended project still receives its own machine output")
	check(await until(id, "completed"), "Courier physically walks to real receiving counter")
	check(s.npc_economy.get_npc_state("village_inn").inventory.get("grain", 0) == receiver_before + 2, "Receiver obtains exactly the authorized cargo")
	check(await preload("res://tests/physical_project_step.gd").complete(self, p, "original", "sale"), "Resumed sale walks to the real market")
	for n in 4: p.advance()
	check(p.projects.original.status == "completed" and mill.producer_state.jobs.is_empty(), "Original project resumes and sells without repeating production")
	check(s.save_game() and s.load_game(), "Completed delivery and main project receipts recover")
	var final_assets: Dictionary = w.assets.snapshot("lao_li")
	for n in 5: jobs.advance(); p.advance()
	check(w.assets.snapshot("lao_li") == final_assets, "No repeated wages or sales")
	# Goal revision changes real uncommitted behavior and checks the captured version.
	var future := {"goal": "小规模采购", "budget": 300, "materials": {}, "deadline_minutes": 180, "steps": [step("buy", "buy", [], {"item_id": "grain", "quantity": 4, "limit": 300})]}
	check(p.submit("lao_li", "revise", future).ok, "New future project accepted")
	var smaller: Dictionary = future.duplicate(true)
	smaller.steps[0].arguments.quantity = 1
	check(p.revise("lao_li", "revise", 1, smaller, "dialogue").ok, "Optional dialogue suggestion accepted as a versioned concrete revision")
	check(not p.revise("lao_li", "revise", 1, future, "dialogue").ok, "Old response cannot overwrite new plan")
	p.advance()
	check(int(p.projects.revise.items.grain) == 1 and p.projects.revise.changes[0].source == "dialogue", "Revised purchase actually buys one, with source history")
	check(not p.revise("lao_li", "revise", 2, future, "self_review").ok, "Committed purchase cannot be rewritten")
	p.advance()
	# Bounded queue; cancellations affect only the named task and preserve money.
	for n in 3:
		check(jobs.propose("lao_li", "queue%d" % n, terms("queue")).ok and jobs.accept("queue%d" % n).ok, "Bounded candidate accepted %d" % n)
	check(not jobs.propose("lao_li", "overflow", terms()).ok, "Infinite interruptions rejected")
	var queued: Array = jobs.tasks.values().filter(func(t): return t.status == "queued")
	var t: Dictionary = queued[0]
	var amendment := terms("queue")
	amendment.task_id = t.id
	amendment.version = t.version
	amendment.quantity = 1
	check(jobs.propose("lao_li", "amend", amendment).ok and jobs.accept("amend").ok, "Renegotiated unpicked cargo requires another explicit confirmation")
	check(not jobs.cancel("player", t.id, int(t.version)).ok, "Old task version cannot cancel revised agreement")
	for record in jobs.tasks.values():
		if record.status == "queued": check(jobs.cancel("player", record.id, int(record.version)).ok, "Cancel only the requested queued task")
	jobs.advance()
	check(jobs.load_count("lao_li") == 0, "All queued cancellations refunded and release capacity")
	check(s.save_game() and s.load_game(), "Amendments and refund receipts reload")
	# Return trip on cancellation after pickup, no remote goods teleportation.
	check(jobs.propose("lao_li", "return", terms()).ok and jobs.accept("return").ok, "Return scenario accepts funded task")
	id = jobs.tasks.keys()[-1]
	check(await until(id, "delivering"), "Courier really returns to player for next pickup")
	for n in 30: jobs.advance(); await physics_frame
	var cash_before: Dictionary = w.assets.snapshot("player")
	check(jobs.cancel("player", id, int(jobs.tasks[id].version)).ok, "Picked-up task enters return state")
	check(w.assets.snapshot("player") == cash_before, "Cancellation does not remotely return cargo")
	check(s.save_game() and s.load_game(), "Return journey reloads")
	check(await until(id, "cancelled"), "Return arrival refunds cargo and unpaid wage")
	check(s.save_game() and s.load_game(), "Final refund survives reload")
	# after_step waits for a real movement boundary; queue waits for the primary project.
	var move_plan := {"goal": "先走到市场附近", "budget": 0, "materials": {}, "deadline_minutes": 60, "steps": [step("walk", "move", [], {"x": -10.5, "z": 26.5})]}
	check(p.submit("lao_li", "walking", move_plan).ok, "Movement primary accepted")
	p.advance()
	check(jobs.propose("lao_li", "after-step", terms("after_step")).ok and jobs.accept("after-step").ok, "After-step alternative accepted")
	var after_id: String = jobs.tasks.keys()[-1]
	jobs.advance()
	check(jobs.tasks[after_id].status == "queued" and p.projects.walking.status == "active", "Current physical movement cannot be interrupted by after-step request")
	check(await until(after_id, "pickup"), "After-step task starts only after movement boundary")
	check(jobs.cancel("player", after_id, int(jobs.tasks[after_id].version)).ok, "Cancel pickup without cancelling original project")
	jobs.advance()
	for n in 3: p.advance()
	check(p.projects.walking.status == "completed", "Original cursor finishes without repeated movement")
	var blocked := {"goal": "等到价格合适才买", "budget": 1, "materials": {}, "deadline_minutes": 60, "steps": [step("buy", "buy", [], {"item_id": "grain", "quantity": 2, "limit": 1})]}
	check(p.submit("lao_li", "expiry", blocked).ok, "Deadline fixture uses a real price-blocked project")
	p.advance()
	var short := terms("queue")
	short.deadline_minutes = 30
	check(jobs.propose("lao_li", "queued-expiry", short).ok and jobs.accept("queued-expiry").ok, "Queue alternative does not discard main obligation")
	var expiry_id: String = jobs.tasks.keys()[-1]
	jobs.advance()
	check(jobs.tasks[expiry_id].status == "queued", "Queued job cannot preempt primary")
	s.season.advance_game_minutes(31)
	check(jobs.tasks[expiry_id].status == "expired" and p.projects.expiry.status == "active", "Expired queue refunds only its own escrow")
	check(jobs.propose("lao_li", "suspended-expiry", terms()).ok and jobs.accept("suspended-expiry").ok, "Interruptible blocked main can accept now alternative")
	var suspended_id: String = jobs.tasks.keys()[-1]
	jobs.advance()
	check(p.projects.expiry.status == "suspended", "Blocked primary suspended at safe boundary")
	s.season.advance_game_minutes(61)
	check(await until(suspended_id, "completed"), "Delivery continues under its independent deadline")
	for n in 3: p.advance()
	check(p.projects.expiry.status == "expired", "Resumed original deadline is revalidated, not extended")
	check(s.save_game() and s.load_game(), "Expiry and resumed-reference history persist")
	# v7 is migrated without reinitializing assets; malformed new liabilities are rejected.
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(s.save_path))
	legacy.version = 7
	legacy.living_world.version = 1
	legacy.living_world.erase("interruptions")
	legacy.living_world.erase("public_plans")
	legacy.living_world.erase("work")
	legacy.living_world.erase("environment")
	legacy.living_world.erase("social")
	legacy.living_world.erase("planning")
	check(s._valid_save(legacy), "Old v7 worlds without new tasks remain readable")
	var corrupt: Dictionary = w.to_dict()
	corrupt.interruptions.tasks[id].gold = 100
	check(not w.validate(corrupt), "Corrupt paid/refunded task escrow rejected")
	print("P6: %d checks, %d failures" % [checks, failures])
	scene.free()
	quit(0 if failures == 0 else 1)
