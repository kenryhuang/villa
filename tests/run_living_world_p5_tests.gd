extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): quit(1))
	run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func terms(id: String, kind := "purchase", item := "bread", count := 2) -> Dictionary:
	return {"demand_id": id, "item_id": item, "quantity": count, "unit_reward": 100, "max_claims": 1, "deadline_minutes": 60, "kind": kind}
func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var s: Farm3DSession = scene.farm_session
	s.season.set_process(false)
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P5"), "P5 formal world")
	var w: Node = s.living_world
	var board: RefCounted = w.board
	var wallet: Node = root.get_node("GameState")
	check(board.demand("need", "player", "bread", 4), "Same-source demand created")
	var gold: int = wallet.gold
	check(board.publish("player", "purchase", terms("need")).ok and wallet.gold == gold - 200, "Publisher funds escrow")
	check(board.publish("player", "purchase", terms("need")).ok and wallet.gold == gold - 200, "Duplicate publish does not debit twice")
	check(board.available("need") == 2, "Commission reserves only its demand share")
	check(board.claim("lao_li", "claim", "purchase", 2).ok, "NPC claims available quantity")
	check(not board.claim("farmer_ahe", "race", "purchase", 1).ok, "Last quota cannot be claimed twice")
	check(not board.cancel("player", "purchase").ok, "Publisher cannot revoke active work before deadline")
	w.assets.apply("lao_li", {"bread": 3}, 0)
	var npc_gold: int = s.npc_economy.get_npc_state("lao_li").gold
	var version: int = board.commissions.purchase.version
	check(not board.deliver("farmer_ahe", "theft", "claim", 1, version).ok, "Foreign claim delivery rejected")
	check(not board.deliver("lao_li", "over", "claim", 3, version).ok, "Over-delivery rejected without implicit term changes")
	check(not board.deliver("lao_li", "stale", "claim", 1, version - 1).ok, "Stale preview requires reconfirmation")
	check(board.deliver("lao_li", "delivery", "claim", 1, version).ok, "Actual inventory delivered for escrow payment")
	check(s.npc_economy.get_npc_state("lao_li").gold == npc_gold + 100 and s.inventory.get_item_count("bread") == 1, "Both sides receive exact goods and money")
	check(s.save_game() and s.load_game(), "Partial delivery and escrow persist")
	check(board.deliver("lao_li", "delivery", "claim", 1, version).ok and s.npc_economy.get_npc_state("lao_li").gold == npc_gold + 100, "Repeated receipt after load cannot pay again")
	check(not board.deliver("lao_li", "delivery", "claim", 2, version).ok, "Idempotency key rejects altered content")
	s.season.advance_game_minutes(60)
	check(board.commissions.purchase.status == "expired" and wallet.gold == gold - 100, "Expiry returns only unused reward")
	check(not board.deliver("lao_li", "late", "claim", 1, int(board.commissions.purchase.version)).ok, "Expiry wins over late delivery")
	check(board.available("need") == 3, "Expired quota returns to same demand")
	var mill: BuildingInstance = s.buildings.get_all_buildings()[0]
	check(s.production.start_rented_recipe(mill, "lao_li", "flour", 1, 4, "old-flour").ok, "Old goods proof fixture")
	s.production.advance_minutes(60)
	check(board.demand("processing", "player", "flour", 1) and board.publish("player", "processing", terms("processing", "processing", "flour", 1)).ok, "Player funds processing commission")
	check(board.claim("lao_li", "process-claim", "processing", 1).ok, "Processing claim accepted")
	version = int(board.commissions.processing.version)
	check(not board.deliver("lao_li", "old-proof", "process-claim", 1, version, "old-flour").ok, "Existing stock and older work cannot satisfy processing")
	check(s.production.start_rented_recipe(mill, "lao_li", "flour", 1, 4, "new-flour").ok, "New processing starts after claim")
	check(not board.deliver("lao_li", "not-ready", "process-claim", 1, version, "new-flour").ok, "Queued work is not completed output")
	s.production.advance_minutes(60)
	check(board.deliver("lao_li", "processed", "process-claim", 1, version, "new-flour").ok, "Actual new job proof and goods settle processing reward")
	check(int(board.proofs["new-flour"].used.flour) == 1, "Proof quota consumed")
	check(s.save_game() and s.load_game(), "New work proof usage persists")
	var saved: Dictionary = w.to_dict()
	board.daily(1)
	check(w.to_dict() == saved, "Daily need and board publish deduplicate after reload")
	check(board.available("inn-food-1") == 2, "Inn direct procurement has separate unreserved share")
	check(not board.procure("village_inn", "inn-food-1", 3).ok, "Background procurement cannot take commissioned share")
	var ui: Node = scene.get_node("FarmInteraction").hud.commission_view
	ui.open_panel()
	gold = wallet.gold
	ui._publish()
	check(ui.confirm.visible and wallet.gold == gold, "UI requires concrete terms confirmation before any debit")
	ui.confirm.confirmed.emit()
	check(wallet.gold == gold - 500, "Confirmed UI uses same prepaid domain transaction")
	ui.close_panel()
	check(not paused and not s.player._dialogue_input_blocked, "Board close restores clock and input")
	check(is_equal_approx(scene.get_node("FarmInteraction").commission_board.position.x, s.market_site.x + 3.1), "Physical board follows actual market location")
	gold = wallet.gold
	check(w.command("lao_li", "propose_player_commission", terms("draft", "purchase", "bread", 2), "npc-draft").ok and wallet.gold == gold, "NPC dialogue draft cannot spend player funds")
	ui.offer_draft()
	check(ui.confirm.visible and wallet.gold == gold, "Draft presents full confirmation after dialogue")
	ui.confirm.confirmed.emit()
	check(wallet.gold == gold - 200, "Explicit player confirmation funds proposed commission")
	ui.close_panel()
	var corrupt: Dictionary = w.to_dict()
	corrupt.board.proofs["new-flour"].used.flour = -1
	check(not w.validate(corrupt), "Negative/reused proof quantities rejected on load")
	print("P5: %d checks, %d failures" % [checks, failures])
	scene.free()
	quit(0 if failures == 0 else 1)
