extends SceneTree

const Merchant = preload("res://scripts/systems/merchant_system.gd")
var checks := 0
var failures := 0
var s: Node
var w: Node
var m: Node

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Merchant tests timed out"); quit(1))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func cash(value: int) -> void:
	m.merchant.asset_net += value - int(m.merchant.cash)
	m.merchant.cash = value

func tick(minute: int) -> void:
	s.season.total_days = minute / 1080 + 1
	s.season.hour = 6 + (minute % 1080) / 60
	s.season.minute = minute % 60
	w.merchant.advance()

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	s = scene.farm_session; w = s.living_world; m = s.market
	scene.set_process(false); s.season.set_process(false); w.set_process(false)
	s.agent_runtime.service_enabled = false; s.agent_runtime.set_process(false)
	s.save_path = "res://tmp/agent-refactor/merchant-fixture.json"
	check(Merchant.valid(m.merchant, m._items), "Merchant initial state validates: " + str(m.merchant.size()))
	check(w.assets.exists(Merchant.ACTOR), "Merchant is a real asset counterparty")
	var initial: Dictionary = m.to_dict()
	var actor = s.npc_economy.get_npc_state("farmer_ahe")
	actor.gold = 1000
	var price: int = m.quote_buy("grain_seed", 1)
	var gold: int = m.merchant.cash
	var stock: int = m.get_stock("grain_seed")
	check(s.npc_economy.agent_buy("farmer_ahe", "grain_seed", 1), "NPC buys actual seed")
	check(actor.gold == 1000 - price and m.merchant.cash == gold + price and m.get_stock("grain_seed") == stock - 1, "Seed purchase transfers exact money and stock")
	var sale: int = m.quote_sell("grain_seed", 1)
	check(s.npc_economy.agent_sell("farmer_ahe", "grain_seed", 1), "NPC can supply seeds back to merchant")
	check(m.merchant.cash == gold + price - sale and actor.gold == 1000 - price + sale, "Merchant pays its own cash for NPC goods")
	var before: Dictionary = m.to_dict()
	var tx: Variant = m.begin_atomic_transaction()
	check(m.stage_buy(tx, "grain_seed", 2), "Trade stages both cash and stock")
	check(m.rollback_atomic_transaction(tx) and m.to_dict() == before, "Rollback restores merchant cash, ledger, cost and inventory")
	cash(0)
	actor.inventory.grain = 5
	before = m.to_dict()
	var actor_before: Dictionary = actor.to_dict()
	check(not s.npc_economy.agent_sell("farmer_ahe", "grain", 1), "Merchant cannot buy without funds")
	check(m.to_dict() == before and actor.to_dict() == actor_before, "Failed sale leaves both sides unchanged")
	check(m.merchant_trade_error("grain", 1) == "merchant_insufficient_cash", "Actionable cash failure")
	cash(2010)
	check(not m.merchant_trade_error("grain", 1).is_empty(), "Ordinary purchase preserves seed funds")
	check(m.merchant_trade_error("grain_seed", 1).is_empty(), "Core seed procurement can spend the seed reserve")
	check(m.from_dict(initial), "Restore initial merchant snapshot")
	var legacy := initial.duplicate(true); legacy.erase("merchant")
	check(m.from_dict(legacy) and int(m.merchant.cash) == 10000, "Old market save migrates opening capital")
	var migrated: Dictionary = m.to_dict()
	check(m.from_dict(migrated) and m.to_dict() == migrated, "Repeated new save load does not reinject capital")
	var broken := migrated.duplicate(true); broken.merchant.cash += 1
	check(not m.from_dict(broken) and m.to_dict() == migrated, "Unbalanced account save rejected atomically")
	for id in Merchant.CORE: m._items[id].stock = 0
	w.environment.event = {}
	tick(0)
	check(m.get_stock("grain_seed") == 0 and w.merchant.incoming("grain_seed") > 0, "Shortage orders physical seeds but cannot sell in-transit goods")
	var shipment_count: int = m.merchant.shipments.size()
	var spent: int = m.merchant.cash
	tick(0); tick(60)
	check(m.merchant.shipments.size() == shipment_count and m.merchant.cash == spent, "Repeated checks subtract in-transit goods and do not order twice")
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(m.to_dict()))
	check(m.from_dict(loaded), "In-transit orders and accounts survive JSON round trip")
	w.environment.event = {"status": "blocked"}
	tick(180)
	check(m.get_stock("grain_seed") == 0, "Closed route delays physical arrival")
	w.environment.event = {}
	tick(300)
	check(m.get_stock("grain_seed") > 0, "Route recovery delivers purchased seeds")
	var delivered: int = m.get_stock("grain_seed")
	var order_id: String = m.merchant.shipments.keys()[0]
	w.merchant._arrive(order_id); tick(300)
	check(m.get_stock("grain_seed") == delivered, "Arrival replay never duplicates goods")
	check(Merchant.valid(m.merchant, m._items), "Account remains balanced after arrivals")
	check(w.merchant.request_supply("farmer_ahe", {"item_id": "rose_seed", "quantity": 4}, "supply-1").ok, "NPC can request non-core seeds")
	var n: int = m.merchant.requests.size()
	check(w.merchant.request_supply("farmer_ahe", {"item_id": "rose_seed", "quantity": 4}, "supply-1").ok and m.merchant.requests.size() == n, "Supply registration is idempotent")
	check(not w.merchant.request_supply("farmer_ahe", {"item_id": "rose_seed", "quantity": 5}, "supply-1").ok, "Conflicting request replay is rejected")
	w.merchant.request_supply("farmer_ahe", {"item_id": "rose_seed", "quantity": 5}, "supply-2")
	check(m.merchant.requests.size() == n, "Same actor/item updates demand instead of multiplying it")
	m._items.rose_seed.stock = 0
	tick(360)
	check(w.merchant.incoming("rose_seed") == 5, "Seasonal seed requested through the supplier catalog")
	# Real funded local commission, partial claim, release only the unclaimed share.
	m.from_dict(migrated); w.board.commissions.clear(); w.board.demands.clear(); w.board.claims.clear()
	tick(1080)
	m._items.grain_seed.stock = 5
	m.merchant.last_check = 1020
	w.merchant.advance()
	var procurement: Dictionary = m.merchant.procurements.get("grain_seed", {})
	check(not procurement.is_empty(), "Nonempty local seed counter posts funded procurement first")
	if not procurement.is_empty():
		var cid: String = procurement.id
		check(w.board.claim("farmer_ahe", "seed-claim", cid, 2).ok, "Farmer voluntarily accepts local seed order")
		var c: Dictionary = w.board.commissions[cid]
		var escrow: int = c.escrow
		tick(1140)
		check(c.claimed == 2 and c.terms.quantity == 2 and c.escrow < escrow, "Unclaimed quota refunded; signed claim remains funded")
		check(w.merchant.incoming("grain_seed") + m.get_stock("grain_seed") == w.merchant.target("grain_seed"), "Local claimed amount and imports together cover only actual shortage")
		actor.inventory.grain_seed = 2
		var old_money: int = actor.gold
		check(w.board.deliver("farmer_ahe", "seed-delivery", "seed-claim", 2, int(c.version)).ok, "Local seed delivery settles original escrow")
		check(actor.gold == old_money + 2 * int(c.terms.unit_reward) and m.get_stock("grain_seed") == 7, "Supplied seeds enter merchant stock with exact farmer payment")
		check(w.board.validate(w.board.to_dict()), "Local commission state validates after quota reduction")
	# Export uses goods already held, pays only after arrival, then supplier replenishes next day.
	m.from_dict(migrated); m.merchant.minute = 2160; m.merchant.last_check = 2160
	m.merchant.quota_day = 2; m.merchant.freight_used = 0
	m._items.grain.stock = 100; m.merchant.cost_basis.grain = 100
	tick(2160)
	var old_cash: int = m.merchant.cash
	w.merchant._export("grain")
	check(m.get_stock("grain") < 100 and m.merchant.cash == old_cash, "Export moves actual stock into transit without early cash")
	tick(2340)
	check(m.merchant.cash > old_cash, "Export arrival recovers money from outside buyer")
	m.merchant.supplier.grain_seed = 0
	tick(3240)
	check(m.merchant.supplier.grain_seed > 0, "Outside seed supplier has renewable daily production")
	check(Merchant.valid(m.merchant, m._items), "External and local ledger reconcile")
	var warehouse_before: int = w.environment.warehouse.salt
	w.merchant._import("salt", 1)
	check(w.environment.warehouse.salt == warehouse_before - 1 and w.environment.merchant_withdrawals.salt == 1, "Merchant food import records finite origin withdrawal")
	var env_save: Dictionary = JSON.parse_string(JSON.stringify(w.environment.to_dict()))
	check(w.environment.validate(env_save), "Origin conservation includes merchant and legacy shipments")
	w.environment.restore(env_save)
	check(w.environment.validate(w.environment.to_dict()), "Origin withdrawal survives save/load")
	env_save.merchant_withdrawals.salt = 0
	check(not w.environment.validate(env_save), "Unexplained origin stock loss is rejected")
	check(not Merchant.valid_request({"item_id": "grain_seed", "quantity": 101}), "Supply request is quantity bounded")
	var runtime: Node = s.agent_runtime
	var command := {"protocol_version": 2, "request_id": "merchant-action", "decision_id": "merchant-action", "agent_id": "farmer_ahe", "expected_revision": runtime.executor.world_revision, "decision_summary": "登记种子补货", "actions": [{"action_id": "merchant-action", "idempotency_key": "merchant-action", "tool_version": 1, "tool_name": "request_supply", "arguments": {"item_id": "grain_seed", "quantity": 4}}]}
	var validated: Dictionary = runtime.validator.validate(command, runtime.registry, runtime.executor.world_revision, runtime.role_system)
	check(validated.ok, "Supply action authorized by real Godot validator")
	if validated.ok:
		var before_actor: Dictionary = actor.to_dict()
		var outcomes: Array = runtime.executor.execute_batch(validated.value, w.minute())
		check(outcomes.size() == 1 and outcomes[0].status == "completed", "Supply action executes through actual Agent router")
		check(actor.to_dict() == before_actor and m.merchant.requests.has("farmer_ahe:grain_seed"), "Agent registers demand without pretending to purchase")
		var registrations: int = m.merchant.requests.size()
		check(runtime.executor.execute_batch(validated.value, w.minute())[0].status == "completed" and m.merchant.requests.size() == registrations, "Agent receipt replay cannot duplicate supply requests")
	# Real registered windmill, real queue and actor output delivery, three replanting cycles per crop.
	var b: BuildingInstance = load("res://scenes/farm3d/buildings/windmill.tscn").instantiate()
	b.configure(BuildingData.from_dictionary(DataSource.get_building("windmill")), -20, -20, [])
	s.add_child(b)
	s.production.register_building(b)
	var farm: Node = s.agent_runtime.farm_registry
	var plot := 0
	for candidate in farm.get_plot_count("farmer_ahe"):
		if farm.get_plot_cell("farmer_ahe", candidate).crop_instance == null:
			plot = candidate
			break
	var cell: GridCell = farm.get_plot_cell("farmer_ahe", plot)
	for crop in ["grain", "carrot", "potato"]:
		var seed_id: String = crop + "_seed"
		actor.inventory[seed_id] = 1; actor.inventory[crop] = 0; actor.gold = 1000
		for cycle in 3:
			if cell.state == GridCell.State.WASTELAND: farm._commit_action({"tool_name": "till", "arguments": {"plot": plot}})
			check(farm._commit_plant({"arguments": {"seed_item_id": seed_id}}, cell, plot).ok, "Real seed consumed by planting: " + crop)
			s.farming.water(cell)
			s.farming.advance_growth_minutes(1080)
			check(farm._commit_harvest(cell, plot).ok, "Real mature crop harvested: " + crop)
			var result: Dictionary = s.production.start_rented_recipe(b, "farmer_ahe", crop + "_seed_selection", 1, 100, "%s-cycle-%d" % [crop, cycle])
			check(result.ok, "Selection order accepted: " + crop)
			s.production.advance_minutes(18)
			check(int(actor.inventory.get(seed_id, 0)) >= 1 and int(actor.inventory[crop]) >= (cycle + 1) * 2, "Selection sustains next planting and surplus: " + crop)
	check(Merchant.valid(m.merchant, m._items), "Final merchant snapshot validates")
	print("Merchant loop: %d checks, %d failures" % [checks, failures])
	scene.queue_free(); await process_frame
	quit(1 if failures else 0)

const DataSource = preload("res://scripts/core/game_data.gd")
