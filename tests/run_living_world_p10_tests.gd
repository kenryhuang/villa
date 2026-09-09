extends SceneTree
var scene: Node
var s: Farm3DSession
var w: Node
var env: RefCounted
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("P10 timeout"); quit(1))
	run.call_deferred()
func check(value: bool, name: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(name)

func run() -> void:
	scene = load("res://scenes/farm3d/main.tscn").instantiate(); root.add_child(scene)
	s = scene.farm_session; w = s.living_world; env = w.environment
	scene.set_process(false); w.set_process(false); s.season.set_process(false); s.player.set_physics_process(false)
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P10"), "Isolated P10 formal scene")
	for seed in range(1, 100):
		if absi(hash("weather:%d:0" % seed)) % 4 == 0: env.seed = seed; env.days.clear(); break
	var forecast: Dictionary = env.ensure_day(0).duplicate(true)
	check(forecast.rain and forecast.kind == "forecast" and not env.raining(), "Forecast is issued before observed rain")
	var stock: int = s.market.get_stock("bread")
	check(env.dispatch_import("lao_li", "bread", 4, 40, 1), "Prepaid finite origin shipment starts")
	check(s.market.get_stock("bread") == stock and int(env.warehouse.bread) == 56, "Transit goods do not appear early in market")
	check(not env.dispatch_import("lao_li", "grain", 24, 40, 1), "Daily 24-unit capacity includes already dispatched goods")
	check(s.save_game() and s.load_game(), "Shipment/seed persists before rain")
	s.season.advance_game_minutes(180)
	check(env.raining() and not env.route_open(), "Forecasted rain physically blocks outside transport")
	check(env.ensure_day(0) == forecast and s.market.get_stock("bread") == stock, "Reload cannot reroll weather or deliver blocked cargo")
	check(is_equal_approx(s.fishing.bite_chance(), .82), "Rain raises real bite probability")
	check(not env.dispatch_import("lao_li", "grain", 4, 40, 1), "Blocked road cannot start a new shipment")
	var event_id: String = env.event.id
	check(not env.command("player", "contribute_route_repair", {"event_id": event_id, "materials": {"wood": 1}, "labor_minutes": 0}, "remote").ok, "Remote repair cannot donate or count labor")
	s.player.position = env.SITE
	s.inventory.add_item("wood", 6); s.inventory.add_item("stone", 4)
	var before: int = root.get_node("GameState").gold
	check(w.public_plans.command("village_public", "public_repair_plan", {"expected_version": w.public_plans.revision, "reason": "商道受阻，采购真实材料并补贴劳动"}, "public-repair").ok, "Public coordinator escrows bounded materials and labor funding")
	check(w.public_plans.budget().daily_remaining == 540, "Food and repair share original daily ceiling")
	var fund: Dictionary = env.public_funding[event_id]
	for id in fund.commissions:
		var c: Dictionary = w.board.commissions[id]
		check(w.board.claim("player", "claim:" + id, id, int(c.terms.quantity)).ok, "Player voluntarily accepts repair procurement")
		var claim: Dictionary = w.board.claims["claim:" + id]
		# The original commission executes at the owner's reachable delivery position.
		s.player.position = w.work.location("village_public", "player")
		check(w.board.deliver("player", "deliver:" + id, claim.id, int(c.terms.quantity), int(c.version)).ok, "Actual materials delivered through original commission escrow")
	env.advance_to(w.minute())
	check(env.event.materials == {"wood": 6, "stone": 4} and not env.route_open(), "Purchased materials consumed but labor still required")
	s.player.position = env.SITE
	var args := {"event_id": event_id, "materials": {}, "labor_minutes": 60}
	check(env.command("player", "contribute_route_repair", args, "labor").ok, "Actual labor begins at repair site")
	s.season.advance_game_minutes(30)
	check(int(env.event.labor) == 30, "Partial labor does not finish repair")
	check(s.save_game() and s.load_game(), "Half-completed repair/public escrow restores")
	s.player.position = env.SITE + Vector3(10, 0, 0)
	s.season.advance_game_minutes(20)
	check(int(env.event.labor) == 30, "Time away from site earns no labor credit")
	s.player.position = env.SITE
	s.season.advance_game_minutes(30)
	check(env.route_open() and env.event.resolution == "materials_and_labor", "Real materials and 60 labor minutes restore route")
	check(root.get_node("GameState").gold == before + 260, "Only delivered materials and actual labor receive public funds")
	check(env.command("player", "contribute_route_repair", args, "labor").ok and root.get_node("GameState").gold == before + 260, "Duplicate labor receipt cannot claim subsidy again")
	s.season.advance_game_minutes(2)
	check(s.market.get_stock("bread") == stock + 4 and env.transports["import-1-bread"].status == "arrived", "Recovery delivers retained cargo through original stock/supply transaction")
	check(s.save_game() and s.load_game(), "Arrival, repair contributions and subsidy survive reload")
	var bad: Dictionary = env.to_dict(); bad.warehouse.bread += 1
	check(not env.validate(bad), "Forged origin stock breaks conservation")
	bad = env.to_dict(); bad.days["0"].rain = false
	check(not env.validate(bad), "Forged weather cannot replace seeded timeline")
	# No player participation: same physical event retains goods until natural drainage.
	env.event = {"id": "road-natural", "status": "blocked", "started": w.minute(), "natural_recovery": w.minute() + 1080, "materials": {"wood": 0, "stone": 0}, "labor": 0, "recovered": -1, "cause": "test isolated second obstruction"}
	s.season.advance_game_minutes(1080)
	check(env.route_open() and env.event.resolution == "natural_drainage", "Skipping a day includes natural recovery without mandatory player work")
	print("P10: %d checks, %d failures" % [checks, failures])
	scene.queue_free(); await process_frame; quit(0 if failures == 0 else 1)
