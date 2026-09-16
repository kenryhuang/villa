extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(45).timeout.connect(func(): push_error("Physical build test timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	var s: Node = scene.farm_session
	var r: Node = s.agent_runtime
	scene.set_process(false); s.season.set_process(false); s.living_world.set_process(false)
	r.set_process(false); r.service_enabled = false
	check(not s.auto_save and not s.auto_restore, "Isolated new world never writes player save")
	var actor := "tiejiang_zhang"
	check("build" in r._build_loop_request(actor, "build-menu", "schedule", s.living_world.minute(), "").allowed_command_tools, "Merchant can discover physical build in 3D")
	var sites: Dictionary = r.world_queries.read(r, actor, "query_world", {"domain": "buildings", "section": "sites"})
	check(sites.ok and not sites.data.windmill.is_empty(), "Real legal construction sites available")
	if sites.data.windmill.is_empty(): quit(1); return
	var site: Dictionary = sites.data.windmill[0]
	var npc: NpcEconomyState = s.npc_economy.get_npc_state(actor)
	# The fixture explicitly funds one building; production uses the real cost.
	for item in site.cost: npc.inventory[item] = int(site.cost[item]) * 2
	var before: Dictionary = npc.inventory.duplicate(true)
	var before_gold := npc.gold
	var body: Node3D = s.living_world.actor(actor)
	body.move_speed = 40
	var before_position := body.position
	var intent := {"protocol_version": 2, "request_id": "physical-build", "decision_id": "physical-build", "agent_id": actor, "expected_revision": r.executor.world_revision,
		"decision_summary": "建造实体风车", "actions": [{"action_id": "build-action", "idempotency_key": "build-action", "tool_version": 1, "tool_name": "build", "arguments": site.build_action.arguments}]}
	intent.actions.append({"action_id": "after-build", "idempotency_key": "after-build", "tool_version": 1, "tool_name": "speak", "arguments": {"text": "风车已建好。", "target_actor_id": "player"}})
	var valid: Dictionary = r.validator.validate(intent, r.registry, r.executor.world_revision, r.role_system)
	check(valid.ok, "Physical build arguments pass real role validator: " + str(valid.get("error", "")))
	if not valid.ok: quit(1); return
	var result: Dictionary = r.executor.execute_batch(valid.value, s.living_world.minute())[0]
	check(result.status == "in_progress", "Build is not reported complete when merely submitted")
	for item in site.cost: check(npc.inventory[item] == int(before[item]) - int(site.cost[item]), "Own materials escrow exactly once: " + item)
	check(npc.gold == before_gold, "Zero-fee land does not invent a gold charge")
	var held := npc.inventory.duplicate(true)
	r.executor.execute_batch(valid.value, s.living_world.minute())
	check(held == npc.inventory, "Duplicate build does not charge materials twice")
	check(r.validate_dict(r.to_dict()), "In-progress build serializes and validates")
	var project_id: String = r.executor._build_project_id("build-action")
	check(s.living_world.projects.projects.has(project_id), "Build uses existing persistent physical project")
	s.save_path = "res://tmp/agent-refactor/physical-build-save.json"
	check(s.save_game() and s.load_game(), "Build escrow and ordered continuation survive actual save/load")
	npc = s.npc_economy.get_npc_state(actor)
	body = s.living_world.actor(actor)
	body.move_speed = 40
	for frame in 900:
		s.living_world.projects.advance()
		r.executor.complete_due(s.living_world.minute())
		if r.executor._outcomes["build-action"].status != "in_progress": break
		await physics_frame
	var final: Dictionary = r.executor._outcomes["build-action"]
	check(r.executor._outcomes.get("after-build", {}).get("status") == "completed", "Ordered action resumes only after physical build completion")
	check(final.status == "completed", "Walk and actual construction complete: " + str(final.get("failure_details", {})))
	var project: Dictionary = s.living_world.projects.projects[project_id]
	var building: BuildingInstance = s.living_world.building(str(project.steps.construct.result.get("building_id", "")))
	check(building != null and building.owner_id == actor and building.is_construction_complete(), "Real completed building belongs to NPC")
	check(body.position.distance_to(before_position) > 1, "NPC physically walked to construction")
	check(s.living_world.projects.validate(s.living_world.projects.to_dict()), "Construction project remains save-compatible")
	check(r.validate_dict(r.to_dict()), "Completed physical build validates in runtime save")
	var stolen := intent.duplicate(true)
	stolen.request_id = "occupied-build"; stolen.decision_id = "occupied-build"
	stolen.actions[0].action_id = "occupied-build"; stolen.actions[0].idempotency_key = "occupied-build"
	var rejected: Dictionary = r.executor.execute_batch(stolen, s.living_world.minute())[0]
	check(rejected.status == "rejected" and rejected.failure_code == "land_unavailable", "Occupied plot rejects duplicate construction")
	check(npc.inventory == held, "No extra material debit after actual completion or occupied rejection")
	var next_sites: Array = s.living_world.construction.sites(actor, "food_workshop")
	check(not next_sites.is_empty(), "Food workshop has legal sites too")
	if not next_sites.is_empty():
		npc.inventory = {}
		var poor_result: Dictionary = r.executor._begin_build_project(actor, next_sites[0].build_action.arguments, "unfunded-build")
		check(not poor_result.ok and poor_result.error == "project_resources_unavailable", "Insufficient own materials cannot produce a free building")
		check(not s.living_world.projects.projects.has(r.executor._build_project_id("unfunded-build")), "Rejected build creates no project or escrow")
	scene.queue_free(); await process_frame
	print("Physical Agent build: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
