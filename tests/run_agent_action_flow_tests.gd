extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(75).timeout.connect(func(): push_error("Action flow tests timed out"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func intent(r: Node, actor: String, key: String, actions: Array, speech := "") -> Dictionary:
	var commands: Array = []
	for i in actions.size():
		commands.append({"action_id": "%s:%d" % [key, i], "idempotency_key": "%s:%d" % [key, i], "tool_version": 1, "tool_name": actions[i][0], "arguments": actions[i][1]})
	return {"protocol_version": 2, "request_id": key, "decision_id": key, "agent_id": actor, "expected_revision": r.executor.world_revision, "decision_summary": "test", "speech": speech, "actions": commands}

func run() -> void:
	# Headless main uses a fresh in-memory session; no live save load/write or Provider calls.
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var s: Node = scene.farm_session
	s.season.set_process(false)
	s.living_world.set_process(false)
	var r: Node = s.agent_runtime
	r.service_enabled = false
	r.set_process(false)
	check(r.registry.is_agent_managed("afu_shui") and r.registry.is_agent_managed("tiejiang_zhang"), "Expanded actors have real Agent executors")
	var farmer: Node3D = r.farm3d_actors.farmer_ahe
	var replies: Array[String] = []
	r.dialogue_ready.connect(func(_a, _id, speech): replies.append(speech))
	paused = true
	r._request_triggers["greeting"] = "dialogue"
	r._handle_response("farmer_ahe", intent(r, "farmer_ahe", "greeting", [], "你好，今天过得怎么样？"))
	check(replies[-1] == "你好，今天过得怎么样？" and r._deferred_responses.is_empty(), "Normal dialogue is not replaced with a queue receipt")
	var start := farmer.position
	r._request_triggers["requested-move"] = "dialogue"
	r._handle_response("farmer_ahe", intent(r, "farmer_ahe", "requested-move", [["move", {"x": start.x + 2, "z": start.z}]], "好，我过来看看。"))
	check(replies[-1].begins_with("好，我过来看看。") and r._deferred_responses.size() == 1, "Deferred action keeps NPC speech and appends an execution notice")
	check(farmer.position == start, "Paused dialogue cannot move the world")
	paused = false
	r._process(0)
	check(r._deferred_responses.is_empty() and r.activity_system.is_busy("farmer_ahe"), "Resuming starts the queued movement")
	await settle(r, "farmer_ahe", "requested-move:0")
	check(farmer.position.distance_to(start) > 1, "Dialogue-requested movement physically happens")

	var state: NpcEconomyState = s.npc_economy.get_npc_state("afu_shui")
	state.gold = 58
	s.market._items.bread.stock = 0
	s.market._items.bread.mid_price = 186
	var rejected: Array = r.executor.execute_batch(intent(r,"afu_shui","no-stock",[["prepare_supplies",{"item_id":"bread","quantity":2}],["travel",{"region_id":"creek","duration_minutes":60}]]),r._absolute_game_minute())
	check(rejected.size() == 1 and rejected[0].failure_code == "market_stock_unavailable", "Actual no-stock case is not mislabeled assets_reserved")
	check(rejected[0].failure_details.gold == 58 and rejected[0].failure_details.market_stock == 0, "Failure includes exact balance and stock")
	check(not r.activity_system.is_busy("afu_shui") and not r.executor.has_pending_continuation("afu_shui"), "Rejected supply purchase does not start travel or retain a continuation")
	s.market._items.bread.stock = 10
	var poor: Array = r.executor.execute_batch(intent(r,"afu_shui","no-gold",[["prepare_supplies",{"item_id":"bread","quantity":1}]]),r._absolute_game_minute())
	check(poor[0].failure_code == "insufficient_gold", "Insufficient money is distinguished from a reservation")
	state.gold = 1000
	check(r.interaction_system.reserve_assets("afu_shui","fixture-reservation",{"gold":950,"items":{}}), "Real reservation fixture")
	var reserved: Array = r.executor.execute_batch(intent(r,"afu_shui","reserved",[["prepare_supplies",{"item_id":"bread","quantity":1}]]),r._absolute_game_minute())
	check(reserved[0].failure_code == "assets_reserved", "Actual asset reservations remain enforced")
	r.interaction_system.release_reservation("fixture-reservation")
	var afu: Node3D = r.farm3d_actors.afu_shui
	afu.position = Vector3(-8, 0, -12)
	var afu_start := afu.position
	var goods_before := int(state.inventory.get("bread",0))
	var price: int = s.npc_economy.quote_agent_buy("bread",1)
	var batch := intent(r,"afu_shui","supply-walk",[["prepare_supplies",{"item_id":"bread","quantity":1}],["move",{"x":-4,"z":-12}]])
	var result: Array = r.executor.execute_batch(batch,r._absolute_game_minute())
	check(result.size() == 1 and result[0].status == "in_progress", "Valid supply purchase starts physical movement")
	await settle(r,"afu_shui","supply-walk:1")
	check(afu.position.distance_to(afu_start) > 2, "Afu physically moves and completes the next batch action")
	check(state.gold == 1000-price and int(state.inventory.bread) == goods_before+1, "Afu buys actual goods exactly once")
	check(r.executor.execute_batch(batch,r._absolute_game_minute())[0].status == "completed" and state.gold == 1000-price, "Replayed batch cannot spend again")
	var smith: Node3D = r.farm3d_actors.tiejiang_zhang
	smith.position = Vector3(-8,0,-12)
	var smith_start := smith.position
	var smith_state: NpcEconomyState = s.npc_economy.get_npc_state("tiejiang_zhang")
	smith_state.inventory.carp = 5
	var smith_gold := smith_state.gold
	r.executor.execute_batch(intent(r,"tiejiang_zhang","sell-walk",[["sell",{"item_id":"carp","quantity":1}]]),r._absolute_game_minute())
	await settle(r,"tiejiang_zhang","sell-walk:0")
	check(smith.position.distance_to(smith_start) > 2 and smith_state.inventory.carp == 4 and smith_state.gold > smith_gold, "Smith walks to the market and completes a real sale")
	scene.queue_free()
	await process_frame
	print("Agent action flow: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func settle(r: Node, actor: String, key: String) -> void:
	for frame in 3000:
		var outcomes: Array = r.executor.complete_due(r._absolute_game_minute()+1+int(frame/60))
		for outcome in outcomes: r._record_world_action_outcome(outcome)
		var result: Dictionary = r.executor._outcomes.get(key,{})
		if result.get("status") in ["completed","failed","rejected"]:
			check(result.status == "completed", "%s terminal action %s: %s" % [actor,key,result])
			return
		await physics_frame
	check(false,"Physical action timed out: "+key)
