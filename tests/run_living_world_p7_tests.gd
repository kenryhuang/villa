extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var s: Farm3DSession = scene.farm_session
	s.season.set_process(false)
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P7"), "Official isolated P7 world")
	var w: Node = s.living_world
	w.set_process(false)
	var env: RefCounted = w.public_plans
	for resident in w.society.residents.values():
		var npc: NpcEconomyState = s.npc_economy.get_npc_state(resident.id)
		npc.inventory = {}
		npc.gold = 0
	s.npc_economy.get_npc_state("lao_li").inventory = {"bread": 4}
	check(int(env.indicators().urgent_food_gap) == 11, "Unmet food access derives from actual goods and purchasing power")
	var wallet_before: Dictionary = w.assets.snapshot("player")
	var public_before := int(s.npc_economy.get_npc_state("village_public").gold)
	var args := {"expected_version": env.revision, "reason": "居民无粮且买不起，采购两份面包提供基本保障", "quantity": 2, "unit_reward": 100, "deadline_minutes": 180}
	check(not env.command("lao_li", "public_food_plan", args, "private").ok, "Private NPC cannot authorize public spending")
	check(not env.command("village_public", "set_price", args, "price").ok, "Public agent cannot set prices or invent assets")
	var request: Dictionary = preload("res://scripts/ai_agent/game_env_context.gd").build(env, "projection", "event")
	check(request.allowed_command_tools == ["public_food_plan", "public_wait"] and request.allowed_read_tools.is_empty(), "Public capability set is separate from private tools")
	check(not request.actor_context.has("self") and request.known_actors.is_empty() and request.agreement_view.is_empty() and not JSON.stringify(request).contains("xuezhe_lin"), "Public projection omits private inventories, memories, projects and knowledge")
	env.set_mode("observe")
	args.expected_version = env.revision
	var observed: Dictionary = w.to_dict()
	check(env.command("village_public", "public_food_plan", args, "observe").ok and w.to_dict() == observed, "Observe mode creates no plan, escrow or economic mutation")
	env.set_mode("execute")
	args.expected_version = env.revision
	paused = true
	check(not env.command("village_public", "public_food_plan", args, "paused").ok, "Paused game cannot launch background measures")
	paused = false
	check(env.command("village_public", "public_food_plan", args, "procure").ok, "Funded public procurement publishes through original commission system")
	check(s.npc_economy.get_npc_state("village_public").gold == public_before - 200 and int(env.budget().committed) == 200, "Public account funds escrow exactly once")
	check(env.command("village_public", "public_food_plan", args, "procure").ok and s.npc_economy.get_npc_state("village_public").gold == public_before - 200, "Idempotent replay cannot double-spend")
	check(not env.command("village_public", "public_food_plan", args, "stale").ok, "Old intervention version rejected")
	args.expected_version = env.revision
	check(not env.command("village_public", "public_food_plan", args, "duplicate-plan").ok, "Cooldown rejects duplicate measures")
	check(w.assets.snapshot("player") == wallet_before, "No private player assets used")
	var id: String = env.plans.keys()[0]
	check(w.board.claim("lao_li", "supplier", id, 2).ok, "Supplier voluntarily claims the public order")
	check(int(env.indicators().funded_claimed_incoming) >= 2, "Funded incoming supply is visible")
	check(s.save_game() and s.load_game(), "Public budget and accepted order survive reload")
	env.set_mode("observe")
	check(w.board.deliver("lao_li", "food-receipt", "supplier", 2, int(w.board.commissions[id].version)).ok, "Existing commitments deliver while new public planning is disabled")
	check(int(s.npc_economy.get_npc_state("village_public").inventory.get("bread", 0)) == 2 and int(env.budget().spent) == 200, "Actual delivered bread belongs to public organization before allocation")
	env.advance()
	check(int(env.plans[id].distributed) == 2 and env.distributions.size() == 2, "Two actual recipients receive one food each with procurement references")
	check(int(env.indicators().urgent_food_gap) == 9 and int(env.budget().committed) == 0, "Public plan improves real reserves; settled escrow is zero")
	var distributed: Dictionary = w.to_dict()
	env.advance()
	check(w.to_dict() == distributed, "Repeated ticks cannot distribute or pay twice")
	check(s.save_game() and s.load_game(), "Distribution receipts persist alongside original economic state")
	var corrupt: Dictionary = w.to_dict()
	corrupt.public_plans.plans[id].distributed = 100
	check(not w.validate(corrupt), "Corrupt distributions rejected")
	corrupt = w.to_dict()
	corrupt.public_plans.receipts.procure.intent.arguments.quantity = 1
	check(not w.validate(corrupt), "Saved purchase cannot contradict its authorized decision receipt")
	# Domain meal settlement consumes the procured food; it is not just a UI counter.
	w.society._feed_day(1)
	check(int(w.society.day_reports["1"].consumed.get("bread", 0)) >= 2, "Procured bread supports real food consumption")
	check(s.save_game() and s.load_game(), "Consumption and public evidence reload")
	env.set_mode("execute")
	s.npc_economy.get_npc_state("village_public").gold = 0
	s.season.advance_game_minutes(181)
	args.expected_version = env.revision
	check(not env.command("village_public", "public_food_plan", args, "no-budget").ok, "No budget cannot publish another procurement")
	check(env.command("village_public", "public_wait", {"expected_version": env.revision, "reason": "预算不足，保留已签承诺并等待"}, "wait").ok, "Explicit no-intervention decision remains available")
	# Captured replies cannot execute after a mode change, timeout, load or pause.
	env.last_review = -1080
	var pending: Dictionary = env._request("village_public", "event", w.minute(), "")
	env.set_mode("observe")
	env._response("village_public", {"request_id": pending.request_id})
	check(env.observations[-1].error == "public_response_expired", "Mode change invalidates in-flight reply before any action")
	env._failed("village_public", "offline", "provider_timeout")
	check(env.plans.has(id) and int(env.plans[id].distributed) == 2, "Service outage preserves accepted measures and evidence")
	var ui: Control = scene.get_node("FarmInteraction").hud.commission_view
	ui.open_panel()
	check(ui.lists[4].get_child_count() > 0, "Normal public affairs tab exposes budget, orders and outcomes")
	ui.close_panel()
	print("P7: %d checks, %d failures" % [checks, failures])
	scene.free()
	quit(0 if failures == 0 else 1)
