extends SceneTree

var checks := 0
var failures := 0
var s: Farm3DSession

func _initialize() -> void:
	if not "--farm-test" in OS.get_cmdline_user_args():quit(1);return
	create_timer(90).timeout.connect(func():push_error("Well timeout");quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)

func place(id: String, x: int, z: int) -> BuildingInstance:
	s.player.position=s.grid.get_cell(x,z).world_position_3d()+Vector3.LEFT*1.2
	var result := s.buildings.try_place_building(id,x,z)
	check(result.placed,"Place %s at %d,%d: %s"%[id,x,z,result])
	return result.get("instance")

func run() -> void:
	var scene: Node=load("res://scenes/farm3d/main.tscn").instantiate();root.add_child(scene)
	s=scene.farm_session
	scene.set_process(false);s.season.set_process(false);s.living_world.set_process(false);s.agent_runtime.set_process(false)
	s.agent_runtime.service_enabled=false;s.player.set_physics_process(false)
	s.save_path="user://well-irrigation-test.json"
	check(not s.auto_save and not s.auto_restore,"Test never touches the player save")
	var origin := Vector2i(32,31)
	check(not s.buildings.diagnose_placement("waterwheel",origin.x,origin.y,"player",false).allowed,"Inland wheel requires a source")
	var wood_before := s.inventory.get_item_count("wood")
	var stone_before := s.inventory.get_item_count("stone")
	var well := place("well",34,31)
	if well==null:scene.free();quit(1);return
	check(s.inventory.get_item_count("wood")==wood_before-10 and s.inventory.get_item_count("stone")==stone_before-20,"Well consumes real construction materials")
	check(not s.buildings.diagnose_placement("waterwheel",32,31,"player",false).allowed,"Incomplete well cannot enable pumping")
	well.complete_construction()
	for offset in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
		s.player.position=well.position+offset*1.5
		check(well.can_operate(s.player),"Well can be used from any side")
	check(s.production.get_well_snapshot(well).water_available,"Completed well is registered as a maintained source")
	check(not s.buildings.diagnose_placement("waterwheel",32,29,"player",false).allowed,"Diagonal-only well contact does not count")
	check(s.buildings.diagnose_placement("waterwheel",32,31,"player",false).allowed,"Edge-adjacent well enables inland placement")
	var wheel := place("waterwheel",32,31)
	if wheel==null:scene.free();quit(1);return
	check(s.production.get_waterwheel_snapshot(wheel).status=="construction","Unfinished wheel cannot irrigate")
	wheel.complete_construction()
	var greenhouse := place("greenhouse",27,32)
	if greenhouse==null:scene.free();quit(1);return
	greenhouse.complete_construction()
	var beds := s.production.get_greenhouse_cells(greenhouse)
	for bed in beds:check(s.farming.is_automatically_irrigated_cell(s.grid.get_cell(bed.x,bed.y)),"Inland irrigation reaches bed "+str(bed))
	var info := s.production.get_waterwheel_snapshot(wheel)
	check(info.water_source.kind=="well" and info.water_source.building_id==well.instance_id,"Live source identifies the actual well")
	check(info.greenhouses.size()==1,"Well-powered wheel supplies one greenhouse")
	wheel._process(1.1)
	check(wheel.running and wheel.get_node("VisualRoot/Model/WellPump").visible and not wheel.get_node("VisualRoot/Model/Rotor").visible,"Inland installation uses compact pump geometry")
	check(wheel.get_node("SupplyPipes").get_child_count()==32,"Visible intake and greenhouse pipes are both present")
	var rotor: Node3D=wheel.get_node("VisualRoot/Model/WellPump/Rotor")
	var angle := rotor.rotation.x;wheel._process(.2)
	check(rotor.rotation.x!=angle,"Well pump animates while working")
	var plot := s.grid.get_cell(beds[0].x,beds[0].y)
	s.grid.set_cell_state(plot.gx,plot.gz,GridCell.State.FARMLAND)
	s.farming.plant(plot,root.get_node("GameData").get_crop("carrot"))
	s.farming.advance_growth_minutes(180)
	check(plot.crop_instance.is_mature(),"Well supply drives real 1.5x watered crop growth")
	s.player.position=well.position+Vector3.RIGHT*1.5
	var hud: Node=scene.get_node("FarmInteraction").hud
	check(well.can_operate(s.player) and hud.open_windmill(well) and paused,"Well panel opens from nearby side")
	check(hud.well_view.details.text.contains("正在从本井取水"),"Well panel reports the actual attached pump")
	hud.close_panels();check(not paused,"Closing well panel restores simulation")
	var outdoor := s.grid.get_cell(32,37)
	check(s.grid.set_cell_state(32,37,GridCell.State.FARMLAND),"Nearby land can be tilled after installing pump")
	s.farming.plant(outdoor,root.get_node("GameData").get_crop("carrot"))
	check(s.farming.is_automatically_irrigated_cell(outdoor),"New outdoor plot inherits existing pump coverage")
	s.season.current_season=SeasonSystem.Season.WINTER
	s.farming.on_day_changed(2)
	check(outdoor.crop_instance.lifecycle_state==CropInstance.LifecycleState.DORMANT,"Supplied outdoor crop survives winter dormant")
	check(s.save_game() and s.load_game(),"Well/pump/greenhouse persist together")
	outdoor=s.grid.get_cell(32,37)
	check(outdoor.crop_instance.lifecycle_state==CropInstance.LifecycleState.DORMANT and s.farming.is_automatically_irrigated_cell(outdoor),"Winter save reconstructs irrigation before reassessing crop survival")
	var reverse_save := s.snapshot_save_data()
	reverse_save.buildings.reverse()
	check(s.restore_save_data(reverse_save,false),"Restore accepts pump before its well in save order")
	well=s.buildings.get_all_buildings().filter(func(b):return b.building_id=="well")[0]
	wheel=s.buildings.get_all_buildings().filter(func(b):return b.building_id=="waterwheel")[0]
	greenhouse=s.buildings.get_all_buildings().filter(func(b):return b.building_id=="greenhouse")[0]
	check(s.production.is_greenhouse_water_connected(greenhouse),"Supply is reconstructed after loading")
	check(s.grid.get_cell(32,37).crop_instance.lifecycle_state==CropInstance.LifecycleState.DORMANT,"Reverse building restore order preserves dormant outdoor crop")
	var query := preload("res://scripts/ai_agent/agent_world_query_router.gd").new()
	check(query._production_summary(s.production,well,"player").well.waterwheels.size()==1,"Agent discovery includes well connections")
	s.production.set_maintenance_due_day(well,1);s.production.begin_day(2)
	s.farming.on_day_changed(3)
	check(s.grid.get_cell(32,37).crop_instance.lifecycle_state==CropInstance.LifecycleState.WITHERED,"Actual well outage removes outdoor winter protection")
	check(not s.production.is_greenhouse_water_connected(greenhouse),"Overdue well stops downstream irrigation")
	for bed in beds:
		var cell := s.grid.get_cell(bed.x,bed.y)
		check(not s.farming.is_automatically_irrigated_cell(cell) and s.farming.is_greenhouse_cell(cell),"Well outage clears irrigation but keeps season protection")
	check(s.save_game() and s.load_game(),"Disconnected wheel remains a valid save")
	well=s.buildings.get_all_buildings().filter(func(b):return b.building_id=="well")[0]
	wheel=s.buildings.get_all_buildings().filter(func(b):return b.building_id=="waterwheel")[0]
	greenhouse=s.buildings.get_all_buildings().filter(func(b):return b.building_id=="greenhouse")[0]
	wheel._process(1.1)
	check(not wheel.running and wheel.get_node("VisualRoot/Model/WellPump").visible and wheel.get_node("SupplyPipes").get_child_count()==32,"Restored offline well keeps its stopped pump and disconnected pipes")
	check(s.production.building_service.maintain(well,"player").ok,"Owner can pay to repair the well")
	check(not s.production.is_greenhouse_water_connected(greenhouse),"Repair in progress does not supply water")
	s.production.advance_repair_time(ProductionSystem.REPAIR_DURATION_SECONDS)
	check(s.production.is_greenhouse_water_connected(greenhouse),"Completed well repair restores all supply")
	check(s.buildings.remove_building(well),"Well can be demolished independently")
	check(not s.production.is_greenhouse_water_connected(greenhouse),"Demolition immediately disconnects irrigation")
	check(s.save_game() and s.load_game(),"Orphaned inland pump survives save/load without a well")
	check(s.buildings.get_all_buildings().any(func(b):return b.building_id=="waterwheel"),"Loading does not silently delete the disconnected pump")
	well=place("well",34,31);well.complete_construction()
	greenhouse=s.buildings.get_all_buildings().filter(func(b):return b.building_id=="greenhouse")[0]
	check(s.production.is_greenhouse_water_connected(greenhouse),"Rebuilt well reconnects the existing installation")
	var backup := place("well",32,30)
	if backup==null:scene.free();quit(1);return
	backup.complete_construction()
	s.production.set_maintenance_due_day(well,s.production.get_current_day())
	wheel=s.buildings.get_all_buildings().filter(func(b):return b.building_id=="waterwheel")[0]
	check(s.production.get_waterwheel_snapshot(wheel).water_source.building_id==backup.instance_id and s.production.is_greenhouse_water_connected(greenhouse),"Unavailable primary well automatically switches to an available adjacent backup")
	check(s.buildings.remove_building(backup) and not s.production.is_greenhouse_water_connected(greenhouse),"Removing the last usable source does not fall back to an overdue well")
	print("WELL ECONOMY ",s.production.get_well_snapshot(well))
	scene.free()
	print("3D WELL: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
