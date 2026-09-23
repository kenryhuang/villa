extends SceneTree

const Router = preload("res://scripts/ai_agent/agent_event_router.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(40).timeout.connect(func(): push_error("Event routing timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	if "--farm-test" not in OS.get_cmdline_user_args(): quit(2); return
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var session: Node = scene.farm_session
	session.season.set_process(false)
	var runtime: Node = session.agent_runtime
	runtime.set_process(false)
	runtime.get_node("AgentEventReceiver").set_process(false)
	var society: RefCounted = session.living_world.society
	society.focus = ["farmer_ahe", "lao_li", "xuezhe_lin"]
	var minute: int = runtime._absolute_game_minute()
	for actor in society.focus:
		var state = session.npc_economy.get_npc_state(actor)
		state.inventory = {}
		state.reserve_targets = {}
	runtime.loop_state.goals.clear()
	session.market.merchant.requests.clear()
	var farmer = session.npc_economy.get_npc_state("farmer_ahe")
	var merchant = session.npc_economy.get_npc_state("lao_li")
	farmer.inventory.grain = 2
	merchant.reserve_targets.grain = 4
	check(Router.recipients(runtime, "market_price", {"item_id":"grain"}, minute) == ["farmer_ahe", "lao_li"], "Market item routes to holders and reserve owners, not everyone")
	check(Router.recipients(runtime, "market_stock", {"item_id":"wood"}, minute).is_empty(), "Merchant role alone does not subscribe to every item")
	session.market.merchant.requests.test = {"actor":"xuezhe_lin", "item_id":"wood", "expires":minute+60}
	check(Router.recipients(runtime, "market_stock", {"item_id":"wood"}, minute) == ["xuezhe_lin"], "Valid supply request subscribes its requester")
	session.market.merchant.requests.test.expires = minute
	check(Router.recipients(runtime, "market_stock", {"item_id":"wood"}, minute).is_empty(), "Expired supply request does not wake an NPC")
	runtime.interaction_system._offers["test-offer"] = {"offer_id":"test-offer","proposer_id":"farmer_ahe","recipient_id":"xuezhe_lin","status":"open","expires_game_minute":minute+60,"proposer_gives":{"items":{"wood":1},"gold":0},"proposer_receives":{"items":{},"gold":2}}
	check(Router.recipients(runtime, "market_price", {"item_id":"wood"}, minute) == ["farmer_ahe", "xuezhe_lin"], "Open trade routes item changes to both participants")
	runtime.interaction_system._offers["test-offer"].status = "settled"
	check(Router.recipients(runtime, "market_price", {"item_id":"wood"}, minute).is_empty(), "Finished trade does not leave a subscription")
	runtime.interaction_system._offers.clear()
	runtime.loop_state.goals.test = {"actor_id":"xuezhe_lin","status":"active","expires_at":minute+60,"success_condition":{"kind":"inventory_at_least","id":"stone","quantity":2}}
	check(Router.recipients(runtime, "market_pressure", {"item_id":"stone"}, minute) == ["xuezhe_lin"], "Typed active goal subscribes to its required item")
	check(Router.recipients(runtime, "weather", {}, minute) == ["farmer_ahe", "xuezhe_lin"], "Weather routes by current farmer/explorer role")
	check(Router.recipients(runtime, "season", {}, minute) == ["farmer_ahe"], "Season routes only to farmers")
	check(Router.recipients(runtime, "day", {}, minute).is_empty(), "Calendar change does not broadcast a decision")
	check(Router.recipients(runtime, "environment", {}, minute).is_empty(), "Untargeted environmental facts never broadcast")
	check(Router.recipients(runtime, "environment", {"affected_actor_ids":["lao_li","player","missing"]}, minute) == ["lao_li"], "Environment intersects explicit recipients with eligible NPCs")
	# Exercise actual signal handlers and queue, with no network/model execution.
	runtime.service_enabled = true
	paused = true
	runtime.scheduler.restore_queue({})
	runtime._on_market_price_changed("grain", 10)
	check(runtime.scheduler.event_queue.messages.size() == 2, "Real market handler queues only two related NPCs")
	var first_ids: Array = runtime.scheduler.event_queue.messages.map(func(e): return e.event_id)
	runtime._on_market_price_changed("grain", 11)
	check(runtime.scheduler.event_queue.messages.size() == 2 and runtime.scheduler.event_queue.messages.all(func(e): return e.event_id not in first_ids), "Waiting public updates coalesce by recipient and subject to latest value")
	var second_ids: Array = runtime.scheduler.event_queue.messages.map(func(e): return e.event_id)
	runtime._on_market_price_changed("grain", 10)
	check(runtime.scheduler.event_queue.messages.size() == 2 and runtime.scheduler.event_queue.messages.all(func(e): return e.event_id not in first_ids + second_ids), "A-B-A price reversal in the same minute retains the latest observation")
	check(runtime.scheduler.event_queue.messages.all(func(e): return e.source == "ambient:market_price:grain"), "Trigger context names exact public topic and item")
	var before_fact: int = runtime.event_store.get_last_sequence()
	runtime._on_market_stock_changed("grain", 10)
	check(runtime.scheduler.event_queue.messages.size() == 2, "Normal market stock updates knowledge without waking NPCs")
	check(runtime.event_store.get_last_sequence() > before_fact, "Unrouted market fact is still recorded in shared world knowledge")
	runtime._on_market_stock_changed("grain", 2)
	check(runtime.scheduler.event_queue.messages.size() == 4, "Critical stock wakes only actors interested in that item")
	runtime.scheduler.restore_queue({})
	runtime._on_day_changed(session.season.total_days)
	check(runtime.scheduler.event_queue.messages.is_empty(), "Real day handler does not queue global decisions")
	runtime._on_weather_changed("rain")
	check(runtime.scheduler.event_queue.messages.map(func(e): return e.agent_id) == ["farmer_ahe", "xuezhe_lin"], "Real weather handler uses scoped role recipients")
	# Demotion removes incidental work, while retaining directed obligations.
	runtime.scheduler.notify_event("lao_li", 2, minute, "interaction_changed", "agreement-directed")
	runtime.scheduler.notify_event("lao_li", 2, minute, "chat_intent_extracted", "chat-directed", "dialogue")
	society.focus = ["farmer_ahe"]
	runtime.sync_focus_actors()
	check(runtime.scheduler.event_queue.messages.size() == 3, "Demotion drops unrelated ambient event but keeps trade and dialogue obligations")
	check(not runtime.scheduler.notify_event("lao_li", 2, minute, "ambient:seed_reserve:grain"), "Nonfocus reserve alerts never enter execution queue")
	check(not runtime.scheduler.notify_event("lao_li", 2, minute), "Legacy unspecified world broadcasts cannot accumulate for nonfocus actors")
	runtime.scheduler.restore_queue({})
	runtime.scheduler.clock_source.publish(runtime.scheduler, minute+600)
	check(runtime.scheduler.event_queue.messages.size() == 1 and runtime.scheduler.event_queue.messages[0].agent_id == "farmer_ahe", "Clock producer skips nonfocus actors before enqueue")
	# Pending directed messages are not collapsed as if they were world refreshes.
	runtime.scheduler.notify_event("farmer_ahe", 2, minute, "interaction_changed", "direct-one")
	runtime.scheduler.notify_event("farmer_ahe", 2, minute, "interaction_changed", "direct-two")
	check(runtime.scheduler.event_queue.messages.size() == 3, "Distinct directed events remain distinct")
	runtime.service_enabled = false
	runtime.loop_state.goals.clear()
	paused = false
	scene.queue_free()
	await process_frame
	print("Agent event routing: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
