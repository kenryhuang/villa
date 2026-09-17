extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void:
	if not "--farm-test" in OS.get_cmdline_user_args():quit(1);return
	create_timer(90).timeout.connect(func():push_error("Waterwheel timeout");quit(1))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func run() -> void:
	var scene: Node=load("res://scenes/farm3d/main.tscn").instantiate();root.add_child(scene)
	var s: Farm3DSession=scene.farm_session
	scene.set_process(false);s.season.set_process(false);s.living_world.set_process(false);s.agent_runtime.set_process(false)
	s.agent_runtime.service_enabled=false;s.player.set_physics_process(false)
	check(not s.auto_save and not s.auto_restore,"Isolated from real save")
	check(not s.buildings.diagnose_placement("waterwheel",32,31,"player",false).allowed,"Dry interior rejects wheel")
	check(s.buildings.diagnose_placement("waterwheel",42,-10,"player",false).allowed,"Real natural river bank accepts special stone piers")
	check(not s.buildings.diagnose_placement("beehive",42,-10,"player",false).allowed,"Bank exception does not loosen normal buildings")
	s.player.position=s.grid.get_cell(42,-10).world_position_3d()+Vector3.LEFT*1.2
	check(s.buildings.enter_preview_mode("waterwheel"),"Native preview opens")
	check(s.buildings.update_preview_grid(42,-10),"Bank preview accepts current position")
	check(is_equal_approx(s.buildings._visual_proxy.get_child(0).get_node("VisualRoot/Model").rotation.y,PI*.5),"Preview faces actual water")
	s.buildings.exit_preview_mode()
	var revision := s.grid.get_navigation_revision()
	check(s.grid.set_cell_state(42,-10,GridCell.State.BUILDING),"Bank transaction supported")
	check(s.grid.get_navigation_revision()>revision,"Bank construction invalidates navigation")
	check(s.grid.set_cell_state(42,-10,GridCell.State.DECORATION),"Bank transaction rolls back original state")
	check(not s.grid.can_support_waterwheel_bank(s.grid.get_cell(54,32)),"Bridge remains protected")
	var placed := s.buildings.try_place_building("waterwheel",42,-10)
	check(placed.placed,"Build native wheel through authority: "+str(placed))
	if not placed.placed:quit(1);return
	var wheel: BuildingInstance=placed.instance
	check(s.production.get_waterwheel_snapshot(wheel).status=="construction","Incomplete wheel cannot run")
	wheel.complete_construction()
	s.player.position=s.grid.get_cell(37,-8).world_position_3d()+Vector3.LEFT*1.2
	placed=s.buildings.try_place_building("greenhouse",37,-8)
	check(placed.placed,"A real greenhouse can fit near bank wheel: "+str(placed))
	if not placed.placed:quit(1);return
	var greenhouse: BuildingInstance=placed.instance
	greenhouse.complete_construction()
	var beds := s.production.get_greenhouse_cells(greenhouse)
	var outside := 0
	for bed in beds:
		var cell := s.grid.get_cell(bed.x,bed.y)
		check(s.farming.is_automatically_irrigated_cell(cell),"Whole-house supply includes bed "+str(bed))
		if bed not in s.production.get_waterwheel_covered_cells(wheel):outside+=1
	check(outside>0,"Regression exercises beds outside direct radius")
	var info := s.production.get_waterwheel_snapshot(wheel)
	check(info.greenhouses.size()==1 and info.connections[0].beds==8,"Snapshot links entire greenhouse")
	wheel._process(.1)
	check(wheel.running and wheel.get_node("SupplyPipes").get_child_count()==16,"Running wheel has actual connecting pipe")
	var colored := 0
	for entry in wheel._model_materials:
		if entry.color != Color.WHITE:colored+=1
	check(colored>150,"Wood, stone and iron retain authored material colors")
	var rotor: Node3D=wheel.get_node("VisualRoot/Model/Rotor")
	var angle := rotor.rotation.x;wheel._process(.2)
	check(rotor.rotation.x!=angle,"Rotor animates when supplied")
	check(is_equal_approx(wheel.get_node("VisualRoot/Model").rotation.y,PI*.5),"Intake faces the east river")
	var plot := s.grid.get_cell(beds[0].x,beds[0].y)
	s.grid.set_cell_state(plot.gx,plot.gz,GridCell.State.FARMLAND)
	var crop: CropData=root.get_node("GameData").get_crop("carrot")
	s.farming.plant(plot,crop)
	s.farming.advance_growth_minutes(180)
	check(plot.crop_instance.is_mature(),"Automatic supply produces real watered growth at 1.5x")
	var hud: Node=scene.get_node("FarmInteraction").hud
	check(hud.open_windmill(wheel) and hud.waterwheel_view.visible and paused,"Waterwheel panel is accessible")
	check("8/8" in hud.waterwheel_view.details.text,"Panel explains whole-house delivery")
	hud.close_panels();check(not paused,"Panel restores time")
	s.production.set_maintenance_due_day(wheel,1);s.production.begin_day(2)
	wheel._process(1.1);angle=rotor.rotation.x;wheel._process(.2)
	check(not wheel.running and rotor.rotation.x==angle,"Maintenance stops rotation")
	for bed in beds:
		var cell := s.grid.get_cell(bed.x,bed.y)
		check(not s.farming.is_automatically_irrigated_cell(cell),"Maintenance disconnects automatic water")
		check(s.farming.is_greenhouse_cell(cell),"Water outage preserves seasonal protection")
	check(s.production.building_service.maintain(wheel,"player").ok,"Owner pays real repair cost")
	s.production.advance_repair_time(ProductionSystem.REPAIR_DURATION_SECONDS)
	check(s.production.is_greenhouse_water_connected(greenhouse),"Repair restores full supply")
	DirAccess.make_dir_recursive_absolute("res://tmp/agent-refactor")
	s.save_path="res://tmp/agent-refactor/waterwheel-save.json"
	check(s.save_game() and s.load_game(),"Bank decoration snapshots and automatic links survive save/load")
	wheel=s.buildings.get_all_buildings().filter(func(b):return b.building_id=="waterwheel")[0]
	greenhouse=s.buildings.get_all_buildings().filter(func(b):return b.building_id=="greenhouse")[0]
	check(s.production.get_greenhouse_water_sources(greenhouse).size()==1,"Sources derived after restoration")
	var query := preload("res://scripts/ai_agent/agent_world_query_router.gd").new()
	check(query._production_summary(s.production,wheel,"player").waterwheel.greenhouses.size()==1,"Agent discovery reports working irrigation")
	# Remove natural water in an isolated fixture, then restore it at the next
	# deterministic daily refresh. Farmland watering is never treated as a source.
	var water_cells: Array=[]
	for x in range(41,45):
		for z in range(-11,-7):
			var cell := s.grid.get_cell(x,z)
			if cell.state==GridCell.State.WATER:water_cells.append(cell);cell.state=GridCell.State.WASTELAND
	s.production.apply_daily_effects(3)
	check(s.production.get_waterwheel_snapshot(wheel).status=="no_water","Lost natural source stops service")
	check(not s.farming.is_automatically_irrigated_cell(s.grid.get_cell(beds[0].x,beds[0].y)),"Lost source clears delivery")
	for cell in water_cells:cell.state=GridCell.State.WATER
	s.production.apply_daily_effects(4)
	check(s.production.is_greenhouse_water_connected(greenhouse),"Natural water return restores delivery")
	print("WATERWHEEL ECONOMY ",s.production.get_waterwheel_snapshot(wheel))
	check(s.buildings.remove_building(wheel),"Owner removes wheel")
	check(s.grid.get_cell(42,-10).state==GridCell.State.DECORATION,"Removal restores original natural bank")
	check(not s.production.is_greenhouse_water_connected(greenhouse),"Removal disconnects greenhouse")
	for bed in beds:check(not s.farming.is_automatically_irrigated_cell(s.grid.get_cell(bed.x,bed.y)),"No stale irrigation after demolition")
	scene.queue_free();await process_frame
	print("3D WATERWHEEL: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)

