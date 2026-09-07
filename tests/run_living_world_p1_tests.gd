extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("P1 timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	root.size = Vector2i(1440, 960)
	var scene := load("res://scenes/farm3d/main.tscn").instantiate() as Node
	root.add_child(scene)
	scene.set_process(false)
	var s: Farm3DSession = scene.farm_session
	s.season.set_process(false)
	s.player.set_physics_process(false)
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P1"), "Two real owned windmills fixture initializes")
	var owned: BuildingInstance = s.buildings.get_all_buildings()[0]
	var rented: BuildingInstance = s.buildings.get_all_buildings()[1]
	var service: RefCounted = s.production.building_service
	var wallet: Node = root.get_node("GameState")
	var owner: NpcEconomyState = s.npc_economy.get_npc_state("lao_li")
	var farmer: NpcEconomyState = s.npc_economy.get_npc_state("farmer_ahe")
	var initial_gold: int = wallet.gold
	var initial_grain := s.inventory.get_item_count("grain")
	paused = true
	var order: Dictionary = s.production.start_rented_recipe(rented, "player", "flour", 1, 4, "p1-player-order", "p1-request")
	check(order.ok and wallet.gold == initial_gold - 4 and owner.gold == 1000, "Paused player order escrows fee without paying owner")
	check(s.inventory.get_item_count("grain") == initial_grain - 2 and rented.producer_state.jobs[0].status == "queued", "Actual ingredients enter queue")
	check(not s.production.start_recipe(rented, "flour", 1, s.inventory), "Cannot bypass foreign building fee")
	check(not s.buildings.remove_building(rented), "Player cannot demolish NPC property")
	check(not s.buildings.remove_building(rented, "lao_li"), "Owner cannot demolish customer work")
	check(not service.cancel(rented, "lao_li", "p1-player-order").ok, "Building owner cannot cancel another customer's order")
	check(not service.set_policy(rented, "player", rented.service_policy, 1).ok, "Foreign user cannot edit prices")
	var policy := rented.service_policy.duplicate(true)
	policy.fees = {"flour": 9}
	check(service.set_policy(rented, "lao_li", policy, 1).ok, "Owner updates price")
	check(not service.set_policy(rented, "lao_li", policy, 1).ok, "Stale policy version rejected")
	check(rented.producer_state.jobs[0].rental_fee == 4, "Existing order retains accepted price")
	check(s.save_game() and s.load_game(), "Escrow and ownership survive full save reload")
	rented = s.buildings.get_all_buildings()[1]
	owned = s.buildings.get_all_buildings()[0]
	owner = s.npc_economy.get_npc_state("lao_li")
	farmer = s.npc_economy.get_npc_state("farmer_ahe")
	check(rented.owner_id == "lao_li" and rented.instance_id == "living-world-P1-1", "Stable identity and owner survive")
	check(s.production.start_rented_recipe(rented, "player", "flour", 1, 4, "p1-player-order", "p1-request").ok and wallet.gold == initial_gold - 4, "Order retry after reload charges nothing")
	check(not s.production.start_rented_recipe(rented, "player", "flour", 2, 4, "p1-player-order").ok, "Same order id with changed content rejected")
	check(service.cancel(rented, "player", "p1-player-order").ok, "Customer cancels queued order")
	check(wallet.gold == initial_gold and owner.gold == 1000 and s.inventory.get_item_count("grain") == initial_grain, "Cancellation restores exact fee and materials")
	check(service.cancel(rented, "player", "p1-player-order").ok and wallet.gold == initial_gold, "Repeated cancellation cannot refund twice")
	check(s.save_game() and s.load_game(), "Cancelled receipt reloads")
	rented = s.buildings.get_all_buildings()[1]
	owned = s.buildings.get_all_buildings()[0]
	owner = s.npc_economy.get_npc_state("lao_li")
	farmer = s.npc_economy.get_npc_state("farmer_ahe")
	check(not s.production.start_rented_recipe(rented, "player", "flour", 1, 4).ok, "New order rechecks raised fee")
	var view: Node = scene.get_node("FarmInteraction").hud.windmill_view
	check(view.open_for(rented), "Actual NPC windmill panel opens")
	view.controller.select_recipe("flour")
	view.controller.set_batches(1)
	view.start_button.pressed.emit()
	check(rented.producer_state.jobs.size() == 1 and wallet.gold == initial_gold - 9, "Actual UI submits paid player order")
	check(view._owner_label.text.contains("老李") and not view._policy_button.visible and view.maintenance_button.disabled, "Customer panel shows owner and restricts management")
	view.close_panel()
	paused = false
	s.production.advance_minutes(1)
	check(owner.gold == 1009 and rented.producer_state.jobs[0].payment_state == "paid", "Fee reaches actual NPC owner on start")
	var running_id := str(rented.producer_state.jobs[0].order_id)
	check(not service.cancel(rented, "player", running_id).ok, "Running order cannot refund")
	check(s.save_game() and s.load_game(), "Running order reloads")
	rented = s.buildings.get_all_buildings()[1]
	owned = s.buildings.get_all_buildings()[0]
	owner = s.npc_economy.get_npc_state("lao_li")
	farmer = s.npc_economy.get_npc_state("farmer_ahe")
	s.production.advance_minutes(60)
	check(owner.gold == 1009 and rented.producer_state.customer_outputs.get("player", {}).get("flour", 0) == 1, "Output awaits correct customer without duplicate fee")
	check(not service.collect(rented, "farmer_ahe").ok, "Other customer cannot take player output")
	check(not s.buildings.remove_building(rented, "lao_li"), "Uncollected goods prevent demolition")
	check(s.save_game() and s.load_game(), "Ready goods reload")
	rented = s.buildings.get_all_buildings()[1]
	owned = s.buildings.get_all_buildings()[0]
	owner = s.npc_economy.get_npc_state("lao_li")
	farmer = s.npc_economy.get_npc_state("farmer_ahe")
	var flour_before := s.inventory.get_item_count("flour")
	check(s.production.collect_all(rented, s.inventory) and s.inventory.get_item_count("flour") == flour_before + 1, "Player collects paid goods through original production path")
	check(not s.production.collect_all(rented, s.inventory), "No double collection")
	check(rented.producer_state.service_records[running_id].stage == "delivered", "Persistent receipt reports actual delivery")
	var total_before: int = wallet.gold + owner.gold + farmer.gold
	var npc_order: Dictionary = s.production.start_rented_recipe(owned, "lao_li", "flour", 1, 4, "p1-npc-player")
	check(npc_order.ok and wallet.gold == initial_gold - 5, "NPC pays player building owner")
	check(s.production.start_rented_recipe(rented, "farmer_ahe", "flour", 1, 9, "p1-npc-npc").ok, "NPC hires another NPC's real building")
	check(wallet.gold + owner.gold + farmer.gold == total_before, "Transfers conserve total actor gold")
	s.production.advance_minutes(60)
	check(owner.inventory.get("flour", 0) == 1 and farmer.inventory.get("flour", 0) == 1, "Both NPC customers receive their actual outputs")
	var owner_gold: int = owner.gold
	check(s.production.start_rented_recipe(rented, "lao_li", "flour", 1, 0, "p1-self").ok and owner.gold == owner_gold, "Owner self-use never transfers money")
	s.production.advance_minutes(60)
	check(owner.inventory.get("flour", 0) == 2 and owner.gold == owner_gold, "Self-use still consumes ingredients and produces goods")
	policy = rented.service_policy.duplicate(true)
	policy.open = false
	check(service.set_policy(rented, "lao_li", policy, int(policy.version)).ok, "Owner closes external service")
	check(not s.production.start_rented_recipe(rented, "player", "flour", 1, 100).ok, "Closed service rejects customers")
	check(s.production.start_rented_recipe(rented, "lao_li", "flour", 1, 0).ok, "Closed service retains self-use")
	s.production.advance_minutes(60)
	policy = rented.service_policy.duplicate(true)
	policy.open = true
	policy.reserved_slots = 2
	check(service.set_policy(rented, "lao_li", policy, int(policy.version)).ok and not service.quote(rented, "player", "flour", 1).ok, "All owner-reserved slots block external enqueue")
	policy = rented.service_policy.duplicate(true)
	policy.reserved_slots = 0
	policy.allowed_recipes = ["flour"]
	check(service.set_policy(rented, "lao_li", policy, int(policy.version)).ok and not service.quote(rented, "farmer_ahe", "animal_feed", 1).ok, "Per-building recipe access is enforced")
	farmer.gold = 0
	var farmer_before := farmer.to_dict()
	check(not s.production.start_rented_recipe(rented, "farmer_ahe", "flour", 1, 100).ok and farmer.to_dict() == farmer_before, "Poor NPC rejection is atomic")
	paused = true
	check(s.production.start_rented_recipe(rented, "player", "flour", 1, 9, "refund-capacity").ok, "Queue refundable player order")
	var slots_before := s.inventory.slots.duplicate(true)
	var mappings_before := s.inventory.quick_slot_mappings.duplicate()
	for index in s.inventory.slots.size(): s.inventory.slots[index] = {"item_id": "stone", "quantity": 99}
	var refund_gold: int = wallet.gold
	check(not service.cancel(rented, "player", "refund-capacity").ok and wallet.gold == refund_gold and rented.producer_state.jobs.size() == 1, "Full inventory blocks refund without losing order or paying money")
	s.inventory.restore_state(slots_before, mappings_before)
	check(service.cancel(rented, "player", "refund-capacity").ok, "Refund succeeds after inventory space is restored")
	check(s.production.start_rented_recipe(rented, "player", "flour", 1, 9, "collect-capacity").ok, "Queue next customer order")
	paused = false
	s.production.advance_minutes(60)
	slots_before = s.inventory.slots.duplicate(true)
	mappings_before = s.inventory.quick_slot_mappings.duplicate()
	for index in s.inventory.slots.size(): s.inventory.slots[index] = {"item_id": "stone", "quantity": 99}
	check(not s.production.collect_all(rented, s.inventory) and rented.producer_state.customer_outputs.player.flour == 1, "Full inventory preserves uncollected paid goods")
	s.inventory.restore_state(slots_before, mappings_before)
	check(s.production.collect_all(rented, s.inventory), "Collection resumes after inventory space is restored")
	var legacy_gold: int = wallet.gold
	var legacy_flour := int(owner.inventory.get("flour", 0))
	check(owned.producer_state.enqueue_job({"recipe_id": "flour", "batches": 1, "remaining_minutes": 1, "status": "running", "tenant_id": "lao_li", "rental_fee": 4}), "Legacy prepaid queue is accepted")
	s.production.advance_minutes(1)
	check(wallet.gold == legacy_gold and owner.inventory.get("flour", 0) == legacy_flour + 1, "Legacy prepaid completion delivers once without crediting owner again")
	check(s.production.set_maintenance_due_day(rented, s.season.total_days), "Set due maintenance fixture")
	check(not s.production.maintain(rented, wallet, s.inventory), "Player cannot maintain someone else's property")
	owner_gold = owner.gold
	check(service.maintain(rented, "lao_li").ok and owner.gold == owner_gold - 25, "NPC owner pays maintenance from own wallet and materials")
	s.production.advance_repair_time(4)
	check(s.production.get_maintenance_state(rented) == "normal", "Original repair completion restores service")
	var corrupt := rented.producer_state.to_dict()
	corrupt.customer_outputs = {"player": 7}
	check(not ProducerState.new().from_dict(corrupt), "Malformed customer storage rejects cleanly")
	var legacy := owned.to_dict()
	for field in ["instance_id", "owner_id", "service_policy"]: legacy.erase(field)
	var migrated := BuildingInstance.new()
	check(migrated.from_dict(legacy) and migrated.owner_id == "player" and migrated.instance_id.begins_with("legacy-"), "Legacy building defaults to player with deterministic identity")
	migrated.free()
	check(s.save_game() and s.load_game(), "Final receipts and policies reload")
	if "--capture-living-world" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		paused = false
		for frame in 4: await physics_frame
		var center: Vector3 = (s.buildings.get_all_buildings()[0].global_position + s.buildings.get_all_buildings()[1].global_position) * 0.5
		scene.overview_camera.position = center + Vector3(16, 18, 22)
		scene.overview_camera.look_at(center, Vector3.UP)
		scene.overview_camera.current = true
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/living-world/P1-buildings.png")
		view.open_for(s.buildings.get_all_buildings()[1])
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/living-world/P1-customer.png")
		view.close_panel()
		view.open_for(s.buildings.get_all_buildings()[0])
		view._open_policy()
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/living-world/P1-owner-policy.png")
		view.close_panel()
		var dialogue: Node = scene.get_node("FarmInteraction").hud.dialogue_ui
		dialogue.open_agent_dialogue("lao_li", "老李")
		dialogue.set_agent_interactions("lao_li", s.agent_runtime.get_player_interactions("lao_li"))
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/living-world/P0-trade-card.png")
	print("P1: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
