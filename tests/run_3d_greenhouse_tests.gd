extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	if not "--farm-test" in OS.get_cmdline_user_args(): quit(1); return
	create_timer(90).timeout.connect(func(): push_error("Greenhouse test timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	var s: Farm3DSession = scene.farm_session
	scene.set_process(false); s.season.set_process(false); s.living_world.set_process(false)
	s.agent_runtime.set_process(false); s.agent_runtime.service_enabled = false; s.player.set_physics_process(false)
	check(not s.auto_save and not s.auto_restore,"Official scene is isolated from player save")
	s.player.position = s.grid.get_cell(32,31).world_position_3d()+Vector3.LEFT*1.2
	var candidate_bed := s.grid.get_cell(32,30)
	var bed_before := candidate_bed.state
	var glass_before := s.inventory.get_item_count("glass")
	candidate_bed.state = GridCell.State.BUILDING
	check(not s.buildings.try_place_building("greenhouse",32,31).placed,"Blocked external planting bed prevents construction")
	check(s.inventory.get_item_count("glass")==glass_before,"Failed placement never consumes glass")
	candidate_bed.state = bed_before
	var reserved: Array[Vector2i] = [Vector2i(32,30)]
	check(s.grid.reserve_cells("greenhouse-test-owner",reserved),"Reserve a bed for another actor")
	check(not s.buildings.diagnose_placement("greenhouse",32,31).allowed,"Greenhouse cannot annex somebody else's bed")
	s.grid.release_cells("greenhouse-test-owner")
	var placement := s.buildings.try_place_building("greenhouse",32,31)
	check(placement.placed,"Build real greenhouse with catalog materials: "+str(placement.get("reason","")))
	if not placement.placed: quit(1); return
	var b: BuildingInstance = placement.instance
	var locations := s.production.get_greenhouse_cells(b)
	check(locations.size()==8,"Eight growing beds")
	var model: Node3D = b.get_node("VisualRoot/Model")
	check(model.get_node("Foundation").visible and not model.get_node("Roof").visible,"Foundation construction stage")
	check(not s.farming.is_greenhouse_cell(s.grid.get_cell(locations[0].x,locations[0].y)),"Incomplete greenhouse grants no protection")
	b.complete_construction()
	check(model.get_node("Roof").visible,"Completed glass roof is visible")
	for i in locations.size():
		var cell := s.grid.get_cell(locations[i].x,locations[i].y)
		var cold_frame: Node3D = model.get_node("Details/ColdFrame%d" % (i+1))
		var difference := Vector2(cold_frame.global_position.x-cell.world_position_3d().x,cold_frame.global_position.z-cell.world_position_3d().z)
		check(difference.length()<.01,"Visible cold frame matches real planting cell %d" % i)
		check(s.farming.is_greenhouse_cell(cell),"Completed greenhouse protects bed %d" % i)
		check(not s.buildings.diagnose_placement("beehive",cell.gx,cell.gz,"player",false).allowed,"Other buildings cannot occupy a protected growing bed")
	var transparent := 0
	for entry in b._model_materials:
		if entry.color.a < 1:
			transparent += 1
			check(entry.material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,"Glass remains translucent after construction tint")
	check(transparent>20,"Native model has individual glass panes")
	var old_season := s.season.current_season
	s.season.current_season = SeasonSystem.Season.WINTER
	var plot := s.grid.get_cell(locations[0].x,locations[0].y)
	var carrot: CropData = root.get_node("GameData").get_crop("carrot")
	var outdoors := s.grid.get_cell(40,30)
	var original_state := outdoors.state
	outdoors.state = GridCell.State.FARMLAND
	check(not s.farming.can_plant(outdoors,carrot),"Carrots cannot be planted outdoors in winter")
	for season in [SeasonSystem.Season.SPRING,SeasonSystem.Season.SUMMER,SeasonSystem.Season.AUTUMN,SeasonSystem.Season.WINTER]:
		s.season.current_season=season
		plot.state=GridCell.State.FARMLAND
		check(s.farming.preview_plant(plot,"carrot_seed").ok,"Greenhouse accepts seed in every season")
	plot.state=GridCell.State.WASTELAND
	s.season.current_season=SeasonSystem.Season.WINTER
	outdoors.state = original_state
	s.player.position = plot.world_position_3d()+Vector3.LEFT
	var seeds_before := s.inventory.get_item_count("carrot_seed")
	check(s.act(plot,"hoe").ok,"Tilling uses the real action")
	check(s.act(plot,"seed","carrot_seed").ok,"Winter planting succeeds in protected bed")
	check(s.inventory.get_item_count("carrot_seed")==seeds_before-1,"Planting consumes one seed")
	var dry_snapshot := s.production.get_greenhouse_snapshot(b)
	check(dry_snapshot.plots[0].remaining_minutes==270 and dry_snapshot.plots[0].growth_multiplier==1.0,"Dry greenhouse uses baseline growth duration")
	var yield_before_water := s.farming.get_crop_yield_snapshot(plot)
	check(s.act(plot,"water").ok,"Watering uses the real action")
	var snapshot := s.production.get_greenhouse_snapshot(b)
	check(snapshot.planted==1 and snapshot.plots[0].remaining_minutes==180,"Snapshot uses actual minute growth, not old nominal days")
	check(snapshot.plots[0].growth_multiplier==1.5,"Panel and simulation share irrigated speed")
	check(s.farming.get_crop_yield_snapshot(plot)==yield_before_water,"Watering increases speed independently of yield bonus")
	var saved_seed: int=root.get_node("GameState").harvest_seed
	var different_quantities := {}
	for seed in range(16):
		root.get_node("GameState").harvest_seed=seed
		var estimate := s.farming.get_crop_yield_snapshot(plot)
		check(estimate.expected_yield>=ceili(estimate.outdoor_yield*1.5) and estimate.expected_yield<=estimate.outdoor_yield*2,"Greenhouse real quantity bounded by 1.5x and 2x")
		different_quantities[estimate.expected_yield]=true
	check(different_quantities.size()>1,"Seeded outcomes vary rather than a fixed double yield")
	root.get_node("GameState").harvest_seed=saved_seed
	var outdoor_crop := CropInstance.new();outdoor_crop.crop_data=carrot
	outdoors.crop_instance=outdoor_crop
	var outdoor_estimate := s.farming.get_crop_yield_snapshot(outdoors)
	check(outdoor_estimate.expected_yield==outdoor_estimate.outdoor_yield and not outdoor_estimate.greenhouse_bonus,"Outdoor crop yield is unchanged")
	outdoors.crop_instance=null
	s.farming.advance_growth_minutes(179)
	check(not plot.crop_instance.is_mature(),"Watered carrot does not mature early")
	s.farming.advance_growth_minutes(1)
	check(plot.crop_instance.is_mature(),"Watered carrot matures at 180 game minutes")
	var harvest_preview := s.farming.preview_harvest(plot)
	check(harvest_preview.items.carrot==snapshot.plots[0].expected_yield,"Preview agrees with shown expected yield")
	check(harvest_preview==s.farming.preview_harvest(plot),"Repeated preview never rerolls")
	var old_due := s.production.get_maintenance_due_day(b)
	s.production.set_maintenance_due_day(b,0)
	check(not s.farming.get_crop_yield_snapshot(plot).greenhouse_bonus,"Overdue greenhouse suspends yield bonus")
	check(s.farming.commit_harvest(plot,harvest_preview).is_empty(),"Stale enhanced harvest is rejected after maintenance state changes")
	check(plot.crop_instance.is_mature(),"Rejected harvest preserves crop")
	s.production.set_maintenance_due_day(b,old_due)
	check(s.farming.preview_harvest(plot)==harvest_preview,"Restored environment retains the same seeded yield")
	var carrots_before := s.inventory.get_item_count("carrot")
	check(s.act(plot,"harvest").ok,"Protected crop harvested through normal authority")
	check(s.inventory.get_item_count("carrot")-carrots_before==int(harvest_preview.items.carrot),"Actual inventory receives the complete greenhouse yield")
	check(s.act(plot,"seed","carrot_seed").ok,"A fresh growing crop can be replanted")
	var hud: Node = scene.get_node("FarmInteraction").hud
	check(hud.open_windmill(b) and hud.greenhouse_view.visible and paused,"Greenhouse status panel opens and pauses")
	check("8" in hud.greenhouse_view.details.text and "种植位" in hud.greenhouse_view.details.text,"Panel explains real planting slots")
	hud.close_panels()
	check(not paused and not hud.is_modal_open(),"Closing panel restores time and input")
	DirAccess.make_dir_recursive_absolute("res://tmp/agent-refactor")
	s.save_path = "res://tmp/agent-refactor/greenhouse-save.json"
	var yield_before_save := s.farming.get_crop_yield_snapshot(plot)
	check(s.save_game() and s.load_game(),"Modeled greenhouse and living crop survive save/load")
	b = s.buildings.get_all_buildings().filter(func(item): return item.building_id=="greenhouse")[0]
	plot = s.grid.get_cell(locations[0].x,locations[0].y)
	check(s.farming.get_crop_yield_snapshot(plot)==yield_before_save,"Loading does not reroll greenhouse production")
	var progress: float = plot.crop_instance.growth_progress
	s.production.set_maintenance_due_day(b,1)
	s.production.begin_day(2)
	check(s.production.get_greenhouse_snapshot(b).status=="maintenance","Overdue maintenance is visible")
	s.farming.advance_growth_minutes(400)
	check(plot.crop_instance.growth_progress==progress,"Overdue greenhouse pauses growth without removing crops")
	var upkeep := s.production.get_maintenance_quote(b)
	var gold_before: int = root.get_node("GameState").gold
	check(s.production.building_service.maintain(b,"player").ok,"Owner can pay quoted maintenance")
	check(root.get_node("GameState").gold==gold_before-int(upkeep.gold_cost),"Maintenance debits real owner gold")
	s.production.advance_repair_time(ProductionSystem.REPAIR_DURATION_SECONDS)
	s.farming.advance_growth_minutes(10)
	check(plot.crop_instance.growth_progress>progress,"Paid repair restores growing service")
	var query := preload("res://scripts/ai_agent/agent_world_query_router.gd").new()
	var report: Dictionary = query._production_summary(s.production,b,"player")
	check(report.greenhouse.total==8 and not report.greenhouse.rental_available,"Discover returns useful data without advertising unimplemented rent")
	check(report.greenhouse.yield_multiplier_min==1.5 and report.greenhouse.yield_multiplier_max==2.0 and report.greenhouse.plots[0].expected_yield>report.greenhouse.plots[0].outdoor_yield,"Agent discovery reports new economic benefit")
	var economy := {"capital_reference_cost":snapshot.capital_reference_cost,"maintenance_reference_cost":snapshot.maintenance_reference_cost,"lease_design_only":true,"lease_gold_per_bed_day":10,"lease_days":2,"scenarios":[],"tenant_examples":[]}
	for occupied in [2,4,8]:
		var daily_net: float = occupied*10.0-float(snapshot.maintenance_reference_cost)/14
		economy.scenarios.append({"occupied_beds":occupied,"owner_daily_net":daily_net,"payback_days":float(snapshot.capital_reference_cost)/daily_net})
	var reference_market := MarketSystem.new()
	reference_market.configure(preload("res://scripts/core/game_data.gd").get_market_items())
	for crop_id in ["carrot","strawberry","lemon","potato"]:
		var definition: CropData = root.get_node("GameData").get_crop(crop_id)
		var seed_cost := reference_market.quote_buy(definition.plant_item_id,1)
		var sale := reference_market.quote_sell(crop_id,4)
		economy.tenant_examples.append({"crop":crop_id,"seed_cost":seed_cost,"sale":sale,"lease_fee":20,"profit":sale-seed_cost-20})
	FileAccess.open("res://tmp/agent-refactor/greenhouse-economy.json",FileAccess.WRITE).store_string(JSON.stringify(economy,"  "))
	reference_market.free()
	s.season.current_season = old_season
	scene.queue_free(); await process_frame
	print("3D GREENHOUSE: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
