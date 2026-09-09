extends SceneTree

var scene: Node
var s: Farm3DSession
var w: Node
var k: RefCounted
var failures := 0
var checks := 0

func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("P9 timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	scene = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	s = scene.farm_session
	w = s.living_world
	k = w.knowledge
	scene.set_process(false); w.set_process(false); s.season.set_process(false); s.player.set_physics_process(false)
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P9"), "P9 fixture is isolated")
	check(not s.auto_restore and not s.auto_save and s.save_path.begins_with("res://tmp/"), "Real player save cannot be used")
	for candidate in range(1, 100):
		if absi(hash("%d:creek:0" % candidate)) % 3 != 0 and absi(hash("%d:forest:0" % candidate)) % 3 == 0: k.seed = candidate; break
	var body: Node3D = w.actor("xuezhe_lin")
	var shore: Vector3 = k.site("creek")
	check(shore.is_finite(), "Current-map river site uses actual walkable terrain")
	body.position = shore + Vector3(-5, 0, 0); body.move_speed = 8
	check(not k.begin_fieldwork("xuezhe_lin", "survey", "creek", "remote-survey", {}).ok, "Remote survey cannot discover anything")
	check(k.begin_fieldwork("xuezhe_lin", "travel", "creek", "p9-travel", {}).ok, "Original activity system starts physical travel")
	for frame in 240:
		k.advance()
		if frame % 6 == 0: s.season.advance_game_minutes(1)
		await physics_frame
		if s.agent_runtime.activity_system._activities["p9-travel"].status == "completed": break
	check(s.agent_runtime.activity_system._activities["p9-travel"].status == "completed" and body.position.distance_to(shore) < 3, "Travel outcome requires actual arrival and time")
	var bread: int = w.assets.available_items("xuezhe_lin").get("bread", 0)
	w.assets.apply("xuezhe_lin", {"bread": -bread}, 0)
	check(not k.begin_fieldwork("xuezhe_lin", "survey", "creek", "no-supplies", {}).ok, "Survey without supplies fails")
	w.assets.apply("xuezhe_lin", {"bread": 4}, 0)
	check(k.begin_fieldwork("xuezhe_lin", "survey", "creek", "p9-survey", {}).ok, "Survey consumes actual bread")
	check(int(w.assets.available_items("xuezhe_lin").get("bread", 0)) == 3, "One bread pays for actual fieldwork")
	s.season.advance_game_minutes(9)
	check(k.reports.is_empty(), "Partial survey does not grant a report")
	check(save_reload(), "Physical activity and private registry survive mid-survey reload")
	s.season.advance_game_minutes(11)
	check(k.reports.has("survey-creek-0") and k.known("xuezhe_lin", "survey-creek-0"), "Completed survey creates sourced observation proof")
	if not k.reports.has("survey-creek-0"): finish(); return
	var report: Dictionary = k.reports["survey-creek-0"]
	check(report.kind == "observation" and report.found, "Fixed seed yields actual finite sample observation")
	check(not k.known("player", report.id) and k.cards("player", true).reports.is_empty(), "Player cannot inspect private reports")
	var offer: Dictionary = k.command("xuezhe_lin", "offer_intelligence", {"target_actor_id": "player", "discovery_id": report.id, "price": 30, "ttl": 180}, "p9-offer")
	check(offer.ok and not k.cards("player").offers[0].has("position") and not k.cards("player").offers[0].has("text"), "Offer card reveals summary without protected content/coordinates")
	root.get_node("GameState").gold = 0
	check(not k.purchase("player", offer.offer_id, 1).ok and not k.known("player", report.id), "Failed payment cannot grant knowledge")
	root.get_node("GameState").gold = 100
	check(k.purchase("player", offer.offer_id, 1).ok and k.known("player", report.id), "Actual payment atomically grants private report")
	check(root.get_node("GameState").gold == 70 and k.cards("player", true).reports[0].position == report.position, "Purchased report unlocks its real map position")
	check(k.purchase("player", offer.offer_id, 1).ok and root.get_node("GameState").gold == 70, "Repeated purchase does not charge again")
	check(k.command("xuezhe_lin", "share_intelligence", {"target_actor_id": "farmer_ahe", "discovery_id": report.id}, "p9-free").ok, "Free disclosure grants usable knowledge")
	check(not k.command("xuezhe_lin", "offer_intelligence", {"target_actor_id": "farmer_ahe", "discovery_id": report.id, "price": 10, "ttl": 180}, "p9-charge-free").ok, "Already disclosed facts cannot be charged later")
	var public_offer: Dictionary = k.command("xuezhe_lin", "offer_intelligence", {"target_actor_id": "lao_li", "discovery_id": report.id, "price": 20, "ttl": 180}, "p9-public-offer")
	check(public_offer.ok and k.publish("xuezhe_lin", report.id, w.minute()), "Original registry publishes verified observation")
	var before: int = w.assets.current().available_gold("lao_li")
	check(k.purchase("lao_li", public_offer.offer_id, 1).ok and w.assets.current().available_gold("lao_li") == before, "Public information cannot be sold as exclusive")
	check(k.collect("xuezhe_lin", report.id, "p9-sample").ok, "Physical investigator collects one real sample")
	check(not k.collect("xuezhe_lin", report.id, "p9-sample-again").ok, "Same evidence cannot mint repeated samples")
	check(save_reload(), "Paid/free/public knowledge and finite sample receipts reload")
	check(not k.collect("lao_li", report.id, "p9-sample").ok, "Cross-actor sample idempotency key cannot replay another receipt")
	check(not k.command("player", "share_intelligence", {"target_actor_id": "lao_li", "discovery_id": report.id}, "p9-free").ok, "Knowledge receipt binds actor and arguments")
	var snapshot: Dictionary = s.agent_runtime.to_dict()
	var forged := snapshot.duplicate(true)
	forged.knowledge.reports[report.id].kind = "fact"
	check(not k.validate_proofs(forged), "Observed evidence cannot be relabeled as a global fact")
	forged = snapshot.duplicate(true)
	forged.activities.activities.erase("p9-survey")
	check(not k.validate_proofs(forged), "Report without physical survey proof cannot load")
	k.record_statement("lao_li", "player", "p9-rumor", "听说林地最近有新的材料。")
	var records: Array = k.typed_records("player", true)
	check(records.any(func(r): return r.get("knowledge_kind") == "rumor" and r.get("source_actor") == "lao_li"), "Dialogue claims retain their speaker and rumor status")
	check(records.any(func(r): return r.get("kind") == "forecast" and r.get("verified") == false), "Weather prediction is labeled unverified with expiry")
	check(records.any(func(r): return r.get("knowledge_kind") == "fact" and r.get("fact_basis") == "p9-survey"), "Published observation points back to its physical evidence")
	check(not k.typed_records("farmer_ahe", true).any(func(r): return r.get("discovery_id") == "statement:p9-rumor"), "Private dialogue rumor does not leak into other actors' knowledge")
	check(save_reload(), "Typed dialogue claims, evidence and forecast survive reload")
	var bad_memory: Dictionary = k.to_dict()
	bad_memory.private.player["statement:p9-rumor"].knowledge_kind = "fact"
	check(not k.validate_extended(bad_memory), "Unproven dialogue cannot be promoted to fact by editing a save")
	await investigation()
	await success_and_cancel()
	finish()

func investigation() -> void:
	var body: Node3D = w.actor("xuezhe_lin")
	var forest: Vector3 = k.site("forest")
	body.position = forest + Vector3(1, 0, 0); body.move_speed = 10
	s.player.position = Vector3(-12.5, 0, 22.5)
	s.inventory.add_item("bread", 6)
	var a := {"worker_id": "xuezhe_lin", "funder_id": "player", "region_id": "forest", "reward": 50, "deadline_minutes": 500, "allow_old_report": false, "require_sample": true}
	check(k.propose_investigation("player", "p9-funded", a).ok, "Player proposes optional funded investigation")
	var before: int = root.get_node("GameState").gold
	check(k.accept_investigation("xuezhe_lin", "p9-funded", 1).ok, "Investigator independently accepts funded work")
	check(root.get_node("GameState").gold == before - 50, "Investigation budget is actual escrow")
	var reloaded := false
	for frame in 1200:
		k.advance()
		if frame % 4 == 0: s.season.advance_game_minutes(1)
		await physics_frame
		var c: Dictionary = k.assignments["p9-funded"]
		if c.status == "surveying" and not reloaded:
			reloaded = true
			check(save_reload(), "Funded investigation resumes after reload at site")
			w.actor("xuezhe_lin").move_speed = 10
		if c.status in ["completed", "no_sample", "expired", "cancelled"]: break
	var c: Dictionary = k.assignments["p9-funded"]
	if c.status != "no_sample": print("RESEARCH DIAG ", c, " activities ", s.agent_runtime.activity_system.to_dict())
	check(c.status == "no_sample" and int(c.consumed_bread) == 2, "No-find report honestly records consumed expedition supplies")
	check(int(c.paid) == 0 and root.get_node("GameState").gold == before, "Required missing sample refunds reward without fabricated success")
	check(k.known("player", "survey-forest-0"), "Honest no-find report is physically returned to sponsor")
	check(save_reload(), "Final investigation proof and refund survive reload")
	var corrupt: Dictionary = k.to_dict()
	corrupt.assignments["p9-funded"].refunded_gold += 1
	check(not k.validate_extended(corrupt), "Forged research refund cannot load")

func success_and_cancel() -> void:
	var terms := {"worker_id": "xuezhe_lin", "funder_id": "player", "region_id": "hills", "reward": 20, "deadline_minutes": 500, "allow_old_report": false, "require_sample": false}
	var target: Vector3 = k.site("hills")
	w.actor("xuezhe_lin").position = target; w.actor("xuezhe_lin").move_speed = 10
	check(k.propose_investigation("player", "p9-paid-report", terms).ok and k.accept_investigation("xuezhe_lin", "p9-paid-report", 1).ok, "New report contract funds actual work")
	for frame in 1600:
		k.advance()
		if frame % 4 == 0: s.season.advance_game_minutes(1)
		await physics_frame
		if k.assignments["p9-paid-report"].status in ["completed", "cancelled", "expired"]: break
	var c: Dictionary = k.assignments["p9-paid-report"]
	check(c.status == "completed" and int(c.paid) == 20 and k.known("player", c.discovery_id), "Actual new report returned and funded reward paid once")
	terms.allow_old_report = true
	check(k.propose_investigation("player", "p9-old-report", terms).ok and k.accept_investigation("xuezhe_lin", "p9-old-report", 1).ok, "Explicit old-report terms remain subject to evidence uniqueness")
	k.advance(); s.season.advance_game_minutes(10); k.advance(); k.advance()
	check(k.assignments["p9-old-report"].status != "completed", "Already paid evidence cannot settle a second contract")
	var pending: Dictionary = k.assignments["p9-old-report"]
	k.cancel_investigation("player", pending.id, int(pending.version))
	for step in 3: k.advance(); s.season.advance_game_minutes(1)
	check(int(pending.gold) == 0 and int(pending.paid) == 0, "Cancelled duplicate research returns unused budget")
	check(save_reload(), "Completed and cancelled research receipts persist together")

func save_reload() -> bool:
	if not s.save_game(): return false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(s.save_path))
	if not s._valid_save(data): print("SAVE DIAG world=", w.validate_save(data), " agents=", s.agent_runtime.validate_dict(data.agents), " executor=", s.agent_runtime.executor.validate_dict(data.agents.executor), " knowledge=", k.validate_extended(data.agents.knowledge), " events=", s.agent_runtime._validate_event_sourced_state(data.agents))
	if not s.agent_runtime.validate_dict(data.agents):
		print("COMPONENT DIAG activities=", preload("res://scripts/systems/npc_activity_system.gd").new().from_dict(data.agents.activities), " knowledge=", preload("res://scripts/systems/explorer_knowledge_registry.gd").new().from_dict(data.agents.knowledge), " farm=", s.agent_runtime.farm_registry.validate_dict(data.agents.farm))
	return s.load_game()

func finish() -> void:
	print("P9: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
