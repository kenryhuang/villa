extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("P0 timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func response(id: String, building: BuildingInstance, revision: int) -> Dictionary:
	return {"protocol_version": 2, "agent_id": "farmer_ahe", "request_id": id, "decision_id": id,
		"expected_revision": revision, "decision_summary": "加工面粉", "speech": "面粉已经做好了！",
		"actions": [{"action_id": id + "-action", "idempotency_key": id + "-order", "tool_name": "rent_production", "tool_version": 1,
			"arguments": {"building_id": building.instance_id, "recipe_id": "flour", "batches": 1, "max_fee": 4}}]}

func run() -> void:
	var scene := load("res://scenes/farm3d/main.tscn").instantiate() as Node
	root.add_child(scene)
	scene.set_process(false)
	var s: Farm3DSession = scene.farm_session
	s.season.set_process(false)
	s.player.set_physics_process(false)
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P0"), "Formal isolated P0 world initializes")
	var runtime: Node = s.agent_runtime
	var json_response := {"protocol_version": 2, "agent_id": "farmer_ahe", "request_id": "json-trade", "decision_id": "json-decision", "expected_revision": 0, "decision_summary": "报价", "actions": [{"tool_name": "propose_trade", "tool_version": 1, "action_id": "json-action", "idempotency_key": "json-offer", "arguments": {"target_actor_id": "player", "give": {"items": {"grain": 1}, "gold": 0}, "receive": {"items": {}, "gold": 2}, "expires_in_minutes": 60, "note": "JSON boundary"}}]}
	var checked: Dictionary = runtime.validator.validate(JSON.parse_string(JSON.stringify(json_response)), runtime.registry, 0, runtime.role_system)
	check(checked.ok and typeof(checked.value.actions[0].arguments.give.gold) == TYPE_INT, "Wire JSON integers normalize before domain transactions")
	var wire_outcomes: Array = runtime.executor.execute_batch(checked.value, runtime._absolute_game_minute())
	check(wire_outcomes[0].status == "completed", "Real JSON-shaped trade reaches original transaction system")
	var dialogue: Node = scene.get_node("FarmInteraction").hud.dialogue_ui
	dialogue.open_agent_dialogue("lao_li", "老李")
	dialogue.set_agent_interactions("lao_li", runtime.get_player_interactions("lao_li"))
	var cards: Node = dialogue.interaction_cards
	check(paused and s.player.ui_blocked, "Dialogue pauses world and blocks player input")
	var card: Node = cards.get_child(0)
	var terms := str(card.find_child("TermsLabel", true, false).text)
	check(terms.contains("你提供") and terms.contains("胡萝卜") and terms.contains("盐") and not terms.contains("proposer_gives"), "Actual offer UI shows named goods and sides without JSON")
	var old_offer := str(runtime.get_player_interactions("lao_li")[0].offer_id)
	card.find_child("CounterButton", true, false).pressed.emit()
	check(card.find_child("CounterEditor", true, false).visible, "Counteroffer editor opens")
	card.find_child("CounterGiveGold", true, false).value = 1
	card.find_child("SubmitCounterButton", true, false).pressed.emit()
	check(not runtime.respond_to_player_interaction("lao_li", old_offer, "accept").ok, "Counteroffer invalidates old quote")
	var counter_id := ""
	for offer in runtime.get_player_interactions("lao_li"):
		if offer.status == "open": counter_id = str(offer.offer_id)
	check(not counter_id.is_empty(), "Counter creates a distinct persistent proposal")
	var before_carrots := s.inventory.get_item_count("carrot")
	var before_salt := s.inventory.get_item_count("salt")
	var before_gold: int = root.get_node("GameState").gold
	var command := {"agent_id": "lao_li", "tool_name": "accept_trade", "arguments": {"offer_id": counter_id}, "idempotency_key": "p0-counter-accept", "action_id": "p0-counter-action", "decision_id": "p0-counter-request"}
	check(runtime.interaction_system.execute(command, runtime._absolute_game_minute()).ok, "NPC accepts explicitly confirmed player counteroffer while paused")
	check(s.inventory.get_item_count("carrot") == before_carrots - 2 and s.inventory.get_item_count("salt") == before_salt + 1 and root.get_node("GameState").gold == before_gold - 1, "Trade commits exact goods and edited gold")
	runtime.interaction_system.execute(command, runtime._absolute_game_minute())
	check(root.get_node("GameState").gold == before_gold - 1, "Repeated confirmation never settles twice")
	dialogue.close()
	check(not paused and not s.player.ui_blocked, "Closing dialogue restores world input")
	check(s.save_game() and s.load_game(), "Trade and idempotency survive full scene reload")
	check(runtime.interaction_system.execute(command, runtime._absolute_game_minute()).ok and root.get_node("GameState").gold == before_gold - 1, "Repeated confirmation after reload is harmless")
	var building: BuildingInstance = s.buildings.get_all_buildings()[0]
	var npc: NpcEconomyState = s.npc_economy.get_npc_state("farmer_ahe")
	var npc_gold: int = npc.gold
	var facts: Array[String] = []
	runtime.dialogue_ready.connect(func(_agent: String, _request: String, speech: String): facts.append(speech))
	var cancelled := response("p0-cancelled", building, runtime.executor.world_revision)
	runtime._request_triggers[cancelled.request_id] = "dialogue"
	runtime.cancel_dialogue("farmer_ahe", cancelled.request_id)
	runtime._handle_response("farmer_ahe", cancelled)
	check(building.producer_state.jobs.is_empty() and npc.gold == npc_gold, "Late response after dialogue cancellation cannot mutate world")
	var pending := response("p0-deferred", building, runtime.executor.world_revision)
	runtime._request_triggers[pending.request_id] = "dialogue"
	paused = true
	runtime._handle_response("farmer_ahe", pending)
	check(building.producer_state.jobs.is_empty() and npc.gold == npc_gold and runtime._deferred_responses.size() == 1, "Paused background action waits without spending")
	check(not facts.back().contains("面粉已经做好"), "Premature model success is not displayed")
	paused = false
	runtime._process(0)
	check(building.producer_state.jobs.size() == 1 and npc.gold == npc_gold - 4, "Resume revalidates and enqueues actual order")
	check(not facts.back().contains("面粉已经做好") and facts.back().contains("加工订单已接受"), "Dialogue reports acceptance rather than invented finished goods")
	check(runtime.executor._outcomes["p0-deferred-order"].status == "in_progress", "Action remains in progress until actual delivery")
	s.production.advance_minutes(10)
	var saved := s.save_game()
	var loaded := saved and s.load_game()
	if not loaded: print("P0 persistence failure saved=", saved, " error=", s.save_error)
	check(saved and loaded, "Processing order saves and reloads with runtime outcome")
	building = s.buildings.get_all_buildings()[0]
	npc = s.npc_economy.get_npc_state("farmer_ahe")
	s.production.advance_minutes(60)
	check(npc.inventory.get("flour", 0) == 1 and runtime.executor._outcomes["p0-deferred-order"].status == "completed", "Actual completion delivers goods and resolves original action")
	var record: Dictionary = building.producer_state.service_records["p0-deferred-order"]
	check(record.job.request_id == "p0-deferred" and record.stage == "delivered" and record.events.size() == 3, "Persistent request/order links retain queued, running and delivered facts")
	check(s.save_game() and s.load_game(), "Terminal receipt and action outcome reload together")
	building = s.buildings.get_all_buildings()[0]
	npc = s.npc_economy.get_npc_state("farmer_ahe")
	npc.inventory = {}
	var failed := response("p0-failed", building, runtime.executor.world_revision)
	runtime._request_triggers[failed.request_id] = "dialogue"
	runtime._handle_response("farmer_ahe", failed)
	check(building.producer_state.jobs.is_empty() and facts.back().contains("未全部完成"), "Missing ingredients shows actual failure without enqueue")
	for mode in ["silent", "spoken", "whitespace"]:
		var reply := {"protocol_version": 2, "agent_id": "farmer_ahe", "request_id": "p0-reply-"+mode, "decision_id": "p0-reply-"+mode,
			"expected_revision": runtime.executor.world_revision, "decision_summary": "Selected speak from current context", "actions": []}
		if mode != "silent":
			reply.actions = [{"action_id": "p0-speak-"+mode, "idempotency_key": "p0-speak-"+mode, "tool_name": "speak", "tool_version": 1, "arguments": {"target_actor_id": "player", "text": "今天可以去湖边钓鱼。"}}]
		if mode == "whitespace": reply.speech = "  "
		runtime._request_triggers[reply.request_id] = "dialogue"
		runtime._handle_response("farmer_ahe", reply)
		check(not facts.back().contains("current context"), "Diagnostic summary never becomes dialogue: "+mode)
		check(facts.back().contains("暂时没有回应") if mode == "silent" else facts.back().contains("今天可以去湖边钓鱼"), "Missing content resolves to actual speak text or an honest empty response: "+mode)
	print("P0: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
