extends SceneTree
var scene: Node
var s: Farm3DSession
var w: Node
var social: RefCounted
var failures := 0
var checks := 0
func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("P11 timeout"); quit(1))
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func run() -> void:
	scene = load("res://scenes/farm3d/main.tscn").instantiate(); root.add_child(scene)
	s = scene.farm_session; w = s.living_world; social = w.social
	scene.set_process(false); w.set_process(false); s.season.set_process(false); s.player.set_physics_process(false)
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P11"), "Isolated P11 formal scene")
	for r in w.society.residents.values():
		if r.id not in ["lao_li", "farmer_ahe", "xuezhe_lin"]: s.npc_economy.get_npc_state(r.id).gold = 0
	var terms := {"kind": "fishing", "starts_in": 60, "duration": 180, "capacity": 4, "minimum": 1, "ticket": 5, "sponsor": 100, "reward": 20, "food_quantity": 2, "food_price": 20}
	var bad := terms.duplicate(true); bad.sponsor = 0
	check(not social.propose("lao_li", "unfunded", bad).ok, "Expected ticket income cannot finance proposed activity")
	check(social.propose("lao_li", "p11-fishing", terms).ok, "Owner prepays real sponsor and original food procurement")
	var e: Dictionary = social.events["p11-fishing"]
	check(not social.propose("player", "venue-conflict", terms).ok, "Overlapping venue/time reservation rejected")
	check(social.command("player", "enroll_activity", {"event_id": e.id, "version": e.version}, "join").ok, "Player confirms ticket and enrollment")
	check(not social.command("player", "enroll_activity", {"event_id": e.id, "version": e.version}, "join-other").ok, "No duplicate enrollment")
	check(social.command("farmer_ahe", "enroll_activity", {"event_id": e.id, "version": e.version}, "ahe-join").ok, "Named NPC independently enrolls as spectator")
	check(e.participants.farmer_ahe.role == "spectator", "NPC has no competitive score executor")
	w.actor("farmer_ahe").position = Vector3(social.SITES.fishing.x, 0, social.SITES.fishing.y)
	s.inventory.add_item("bread", 2)
	check(w.board.claim("player", "food-claim", e.id, 2).ok, "Player voluntarily supplies actual event food")
	check(w.board.deliver("player", "food-delivery", "food-claim", 2, int(w.board.commissions[e.id].version)).ok, "Original commission pays supplier on actual food delivery")
	social.advance()
	check(int(e.food) == 2 and int(e.received) == 2, "Only commissioned delivered food enters event stock")
	var old_proof: String = social.begin_gameplay("fishing")
	check(s.save_game() and s.load_game(), "Enrollment and funded food persist before opening")
	e = social.events["p11-fishing"]
	s.player.position = Vector3(-40, Farm3DTerrainProfile.surface_height(-40, 108), 108)
	w.actor("farmer_ahe").position = Vector3(social.SITES.fishing.x, 0, social.SITES.fishing.y)
	s.season.advance_game_minutes(60); social.advance()
	check(e.status == "live" and e.participants.player.state == "attended" and int(e.served) == 2, "Actual player/NPC arrivals consume food once")
	social.advance(); check(int(e.served) == 2, "Repeated update does not duplicate food consumption")
	var cash: int = root.get_node("GameState").gold
	social.finish_gameplay(old_proof, "fishing", {"item_id": "carp", "quantity": 1})
	check(root.get_node("GameState").gold == cash and int(e.paid_reward) == 0, "Pre-event catch cannot earn event reward")
	s.player.position.y += .2
	s.player.set_physics_process(true)
	for frame in 35: await physics_frame
	s.player.set_physics_process(false)
	s.fishing.refresh_location()
	check(s.fishing.equip(), "Real lake fishing location can participate")
	check(s.fishing.act().ok, "Actual cast creates unique gameplay session")
	var proof_id: String = s.fishing.gameplay_id
	s.fishing._will_bite = true
	s.fishing.advance(2); s.fishing.advance(10)
	check(s.fishing.act().ok, "Player reels actual bite")
	s.fishing.advance(2); s.fishing.advance(2)
	check(social.gameplay[proof_id].status == "completed" and int(e.paid_reward) == 20 and root.get_node("GameState").gold == cash + 20, "Original landed-fish inventory commit produces one real reward proof")
	social.finish_gameplay(proof_id, "fishing", {"item_id": "carp", "quantity": 1})
	check(root.get_node("GameState").gold == cash + 20, "Duplicate catch proof cannot award twice")
	s.fishing.cancel()
	check(s.save_game() and s.load_game(), "Completed gameplay proof and reward restore")
	e = social.events["p11-fishing"]
	s.season.advance_game_minutes(180); social.advance()
	check(e.status == "finished" and int(e.cash) == 0 and int(e.owner_return) > 0, "Closing returns only real remaining funds to organizer")
	var snapshot: Dictionary = social.to_dict(); snapshot.events[e.id].paid_reward += 1
	check(not social.validate(snapshot, w.board.to_dict()), "Forged event reward breaks escrow conservation")
	terms.kind = "golf"; terms.minimum = 4
	check(social.propose("lao_li", "p11-empty", terms).ok, "Another activity can open independently")
	var empty: Dictionary = social.events["p11-empty"]
	check(social.enroll("player", empty).ok, "Single participant prepays ticket")
	var before: int = root.get_node("GameState").gold
	s.season.advance_game_minutes(60); social.advance()
	check(empty.status == "cancelled" and root.get_node("GameState").gold == before + 5, "Low enrollment cancels and refunds actual ticket")
	check(s.save_game() and s.load_game(), "Cancelled/finished activity final ledger reloads")
	terms.minimum = 1; terms.food_quantity = 1
	check(social.propose("lao_li", "p11-golf", terms).ok, "Funded golf event can start after cancellation")
	var golf_event: Dictionary = social.events["p11-golf"]
	check(social.enroll("player", golf_event).ok, "Golfer enrolls voluntarily")
	s.inventory.add_item("bread", 1)
	check(w.board.claim("player", "golf-food", golf_event.id, 1).ok and w.board.deliver("player", "golf-food-delivery", "golf-food", 1, int(w.board.commissions[golf_event.id].version)).ok, "Golf catering follows original paid commission")
	s.player.position = Vector3(social.SITES.golf.x, 0, social.SITES.golf.y)
	s.season.advance_game_minutes(60); social.advance()
	var golf: Node = s.golf
	s.player.position = Vector3(golf.Course.ENTRANCE.x, Farm3DTerrainProfile.surface_height(golf.Course.ENTRANCE.x, golf.Course.ENTRANCE.y), golf.Course.ENTRANCE.y)
	check(golf.start_round(), "Original golf entry starts the event gameplay proof")
	var golf_id: String = golf.round_state.gameplay_id
	for hole in 7:
		var cup: Vector2 = golf.Course.HOLES[hole].cup
		golf.ball.place(cup + Vector2(0, .02)); golf.ball.strike(Vector3.FORWARD, .05, 2)
		golf.phase = golf.Phase.FLIGHT
		for frame in 300:
			golf.ball.advance(1.0 / 60, cup)
			if not golf.ball.moving: break
		check(golf.ball.result == "holed", "Physical ball detector captures hole %d" % (hole + 1))
		golf._settle()
		if hole < 6:
			var tee: Vector2 = golf.Course.HOLES[hole + 1].tee
			s.player.position = Vector3(tee.x, Farm3DTerrainProfile.surface_height(tee.x, tee.y), tee.y)
			check(golf.next_hole(), "Original transition advances only after capture")
	check(social.gameplay[golf_id].status == "completed" and int(golf_event.paid_reward) == 20, "Seven original captures produce one funded golf award")
	check(s.save_game() and s.load_game(), "Golf round and social award restore together")
	print("P11: %d checks, %d failures" % [checks, failures])
	scene.queue_free(); await process_frame; quit(0 if failures == 0 else 1)
