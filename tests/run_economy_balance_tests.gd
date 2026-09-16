extends SceneTree

const Data = preload("res://scripts/core/game_data.gd")
const Balance = preload("res://scripts/core/economy_balance.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Economy balance checks require an isolated headless process")
		quit(1)
		return
	create_timer(90).timeout.connect(func(): push_error("Balance test timeout"); quit(1))
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://tmp/agent-refactor")
	var market := MarketSystem.new()
	market.configure(Data.get_market_items())
	market.enable_merchant(0)
	for recipe in RecipeDatabase.get_all_recipes():
		var reference := Balance.rental_reference(recipe)
		check(reference.default_fee > 0 and reference.tenant_profit > 0,"Both parties earn a positive reference return: " + recipe.id)
		check(float(reference.tenant_profit)/reference.sale_value >= .149,"Tenant keeps at least 15% reference margin: " + recipe.id)
		var cost := 0
		for id in recipe.inputs: cost += market.quote_buy(id,int(recipe.inputs[id]))
		if recipe.get("input_selectors",[]).is_empty(): check(cost == reference.input_cost,"Reference uses real market purchase spread: " + recipe.id)
		rows.append({"recipe":recipe.id,"reference":reference})
	var low := INF
	var high := 0.0
	for crop in CropCatalog.default_crop_definitions():
		var rate := float(market.quote_sell(crop.crop_id,4)-market.quote_buy(crop.plant_item_id,1))/crop.growth_duration_minutes
		low = minf(low,rate); high = maxf(high,rate)
		var plant := CropInstance.new()
		plant.crop_data = crop
		plant.advance_game_minutes(int(crop.growth_duration_minutes)-1)
		check(not plant.is_mature(),"Crop cannot mature before its configured duration: " + crop.crop_id)
		plant.advance_game_minutes(1)
		check(plant.is_mature(),"Crop matures at its configured duration: " + crop.crop_id)
	check(high/low < 1.6,"Equal-yield crop income per growing minute has no dominant 4x crop")
	# Passive low-cost buildings should not pay the same fixed gold fee as factories.
	check(Balance.maintenance("beehive").gold_cost < Balance.maintenance("food_workshop").gold_cost,"Maintenance scales with building value")
	# 28-day demand scenarios use finite paid batches, not continuous full capacity.
	for station in ["windmill","food_workshop"]:
		var recipes := ["flour","animal_feed"] if station == "windmill" else ["bread","honey_cake","fruit_jam","perfume"]
		var batches := 8
		var cost := Balance.reference_value(Data.get_building(station).cost,true)
		var upkeep := Balance.maintenance(station)
		var maintenance := int(upkeep.gold_cost)+Balance.reference_value(upkeep.materials,true)
		var fees := 0
		var tenant_profit := 0
		for i in batches:
			var price := Balance.rental_reference(RecipeDatabase.get_recipe(recipes[i%recipes.size()]))
			fees += int(price.default_fee); tenant_profit += int(price.tenant_profit)
		var payback := cost/(float(fees)-float(maintenance)/14)
		check(payback >= 14 and payback <= 28,"Moderate paid demand repays building in 14–28 days: "+station)
		check(fees*28-maintenance*2-cost > 0 and tenant_profit*28 > 0,"Owner and tenant both gain over 28 days: "+station)
		check(float(cost)/(float(fees)/4-float(maintenance)/14)>28,"Low demand cannot claim the moderate-demand payback: "+station)
		rows.append({"station":station,"batches_per_day":batches,"construction_cost":cost,"maintenance":maintenance,"fees_per_day":fees,"tenant_profit_per_day":tenant_profit,"payback_days":payback})
	# Full scene checks authority, legacy order prices and real save migration.
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	var s: Node = scene.farm_session
	scene.set_process(false);s.season.set_process(false);s.living_world.set_process(false);s.agent_runtime.set_process(false);s.agent_runtime.service_enabled=false
	check(not s.auto_save and not s.auto_restore,"Economy checks cannot change live save")
	s.player.position = s.grid.get_cell(42,31).world_position_3d()+Vector3.LEFT*1.2
	var made: Dictionary = s.buildings.try_place_building("windmill",42,31)
	check(made.placed,"A real production building can be built")
	if not made.placed: quit(1);return
	var b: BuildingInstance = made.instance
	b.restore_construction(3,9)
	var tenant: NpcEconomyState = s.npc_economy.get_npc_state("farmer_ahe")
	tenant.gold=1000;tenant.inventory.grain=12
	var quote: Dictionary = s.production.building_service.quote(b,"farmer_ahe","flour",1)
	check(quote.ok and quote.fee == Balance.rental_reference(RecipeDatabase.get_recipe("flour")).default_fee,"Actual default quote uses economic tariff")
	b.service_policy.fees.flour = 4
	var wallet: Node = root.get_node("GameState")
	var owner_before: int = wallet.gold
	check(s.production.start_rented_recipe(b,"farmer_ahe","flour",1,4,"legacy-fee").ok,"Explicit older owner tariff remains accepted")
	check(tenant.gold == 996 and wallet.gold == owner_before+4,"Paid rent transfers conserved gold from tenant to owner")
	b.service_policy.fees.clear()
	check(b.producer_state.jobs[0].rental_fee==4,"Already accepted order is never repriced")
	s.save_path="res://tmp/agent-refactor/economy-balance-save.json"
	check(s.save_game() and s.load_game(),"Running order and ownership survive actual save/load")
	var flour_before: int = s.npc_economy.get_npc_state("farmer_ahe").inventory.get("flour",0)
	s.production.advance_minutes(27)
	check(s.npc_economy.get_npc_state("farmer_ahe").inventory.get("flour",0)==flour_before+1,"Unchanged recipe delivers existing paid order")
	# An older catalog fixture is portable; optional real-save validation is read-only.
	var saved: Dictionary = market.to_dict()
	saved.items.grain_seed.base_price = 12
	saved.items.grain_seed.mid_price = 18
	saved.items.grain_seed.history = [12,18]
	check(market.restore_from_dict_with_current_catalog(saved),"Existing market and merchant ledger migrate to new catalog")
	check(market.to_dict().items.grain_seed.mid_price == 21,"Catalog migration preserves relative price pressure")
	for id in saved.items: check(market.get_stock(id)==int(saved.items[id].stock),"Catalog migration preserves stock: "+str(id))
	check(market.merchant.cash==int(saved.merchant.cash),"Catalog migration never grants merchant cash")
	var normalized := market.to_dict()
	check(market.restore_from_dict_with_current_catalog(normalized) and market.to_dict()==normalized,"Price rebasing is idempotent on repeated load")
	if preload("res://scripts/systems/resident_society_system.gd").expanded() and FileAccess.file_exists("res://data/farm_3d_save.json"):
		var original := FileAccess.get_file_as_string("res://data/farm_3d_save.json")
		var live: Dictionary = JSON.parse_string(original)
		check(market.restore_from_dict_with_current_catalog(live.market),"Real existing market can migrate without modifying its file")
		s.save_path = "res://tmp/agent-refactor/economy-live-copy.json"
		check(DirAccess.copy_absolute("res://data/farm_3d_save.json",s.save_path)==OK,"Existing save is copied into isolated test directory")
		check(s.load_game(),"Entire existing world loads under the new catalog")
		check(s.market.merchant.cash==int(live.market.merchant.cash),"Full world migration preserves merchant cash")
		check(s.save_game() and s.load_game(),"Migrated world can save and reload without touching original")
		check(FileAccess.get_file_as_string("res://data/farm_3d_save.json")==original,"Original live save stays byte-for-byte unchanged")
	FileAccess.open("res://tmp/agent-refactor/economy-balance-report.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	market.free();scene.queue_free();await process_frame
	print("Economy balance: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
