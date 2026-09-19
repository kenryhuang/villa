extends SceneTree

const Needs = preload("res://scripts/systems/resident_needs.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Resident needs timeout"); quit(1))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func run() -> void:
	if "--living-world-scenario=P12" not in OS.get_cmdline_user_args(): quit(1); return
	var scene = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	var s: Farm3DSession = scene.farm_session
	var w: Node = s.living_world
	if w == null: scene.free(); quit(1); return
	scene.set_process(false); s.season.set_process(false); w.set_process(false)
	s.save_path = "user://resident_needs_test.json"
	var runtime: Node = s.agent_runtime
	var farms = runtime.farm_registry
	# P12 deliberately replaces inventories for its trade scenario. Restore the
	# authored startup packages here to test this feature's actual starting state.
	for profile in w.society.economy_profiles():
		var state: NpcEconomyState = s.npc_economy.get_npc_state(profile.id)
		state.inventory = profile.inventory.duplicate(true)
	check(w.society.focus.size() == 8 and runtime.farm3d_actors.size() == 8,"Eight focus actors")
	var coordinates := {}
	for actor in ["farmer_ahe","xiao_hua","afu_shui","resident_shan"]:
		check(runtime.role_system.get_active_role(actor) == "farmer","Farmer role: "+actor)
		var plots: Array = farms.get_snapshot(actor)
		check(plots.size() == 20,"Own real plots: "+actor)
		for plot in plots:
			check(not coordinates.has(plot.coordinate) and plot.owner_id == actor,"Distinct owned farmland")
			coordinates[plot.coordinate] = true
		check(int(s.npc_economy.get_npc_state(actor).inventory.get("carrot_seed",0)) >= 24,"Starter seeds")
		var farm: VisibleNpcFarmSystem = farms.for_actor(actor)
		var body: Node3D = w.actor(actor)
		var controller: Node = body.get_children().filter(func(c): return c is NpcFarmActionController)[0]
		check(controller._farm == farm,"Each controller uses its own queue")
		var plot: GridCell = farm.get_plot_cell(actor,0)
		# Exercise the same commit path used after actual arrival, with ownership
		# and inventory checks intact. Queuing/routing is checked independently.
		check(farm._commit_action({"tool_name":"till","arguments":{"plot":0}}).ok,"Till own farm")
		var seeds: int = s.npc_economy.get_npc_state(actor).inventory.carrot_seed
		check(farm._commit_action({"tool_name":"plant","arguments":{"plot":0,"seed_item_id":"carrot_seed"}}).ok,"Plant own farm")
		check(plot.crop_instance != null and s.npc_economy.get_npc_state(actor).inventory.carrot_seed == seeds-1,"Crop and seed update only owning actor")
		var target: GridCell = farm.get_plot_cell(actor,1)
		body.global_position = target.world_position_3d()+Vector3(-.6,0,0)
		var queued: Array = runtime.executor.execute_batch({"agent_id":actor,"decision_id":"multi-farm-"+actor,"request_id":"multi-farm-"+actor,"expected_revision":runtime.executor.world_revision,"actions":[{"tool_name":"till","action_id":"till-"+actor,"idempotency_key":"till-"+actor,"arguments":{"plot":1}}]},w.minute())
		check(not queued.is_empty() and queued[0].status == "in_progress","Each farmer starts real queued work")
	for frame in 240:
		if not ["farmer_ahe","xiao_hua","afu_shui","resident_shan"].any(func(id): return farms.has_pending_work(id)): break
		await physics_frame
	for actor_id in ["farmer_ahe","xiao_hua","afu_shui","resident_shan"]:
		check(farms.get_plot_cell(actor_id,1).state == GridCell.State.FARMLAND and runtime.executor._outcomes["till-"+actor_id].status == "completed","Real movement and work complete independently: "+actor_id)
	var n := Needs.initial("test",0)
	Needs.advance(n,"test",600)
	var advanced := n.duplicate(true)
	Needs.advance(n,"test",600)
	check(n == advanced,"Time advancement is idempotent")
	check(Needs.valid(n,600) and n.thirst > n.companionship,"Physical needs develop faster than companionship")
	check(not Needs.valid({"hunger":NAN},600),"Malformed needs rejected")
	var actor := "xiao_hua"
	var resident: Dictionary = w.society.residents[actor]
	resident.needs.hunger = 90.0
	var read: Dictionary = runtime.world_queries.read(runtime,actor,"query_world",{"domain":"self","section":"needs"})
	check(read.ok and read.data.levels.hunger == 90,"Lazy query returns live needs")
	check(runtime.world_queries.read(runtime,actor,"query_world",{"domain":"self","section":"needs","id":"lao_li"}).data.levels.hunger == 90,"Self query cannot expose another actor's private needs")
	var stock: Dictionary = w.assets.available_items(actor)
	var food := str(w.society.config.food_preferences.filter(func(id): return int(stock.get(id,0)) > 0)[0])
	var count := int(stock[food])
	check(w.work.command(actor,"start_leisure",{"activity":"eat","partner_id":actor},"eat-test").ok,"Schedule eating")
	var activity: Dictionary = w.work.activities.values()[-1]
	check(resident.needs.hunger == 90 and int(w.assets.available_items(actor)[food]) == count,"Scheduling is not consumption")
	activity.status = "working"; activity.worked = 15
	w.work._advance_activity(activity)
	check(activity.status == "completed" and resident.needs.hunger == 25,"Eating completes and relieves hunger")
	check(int(w.assets.available_items(actor)[food]) == count-1,"Eating consumes actual inventory")
	w.work._advance_activity(activity)
	w.work.command(actor,"start_leisure",{"activity":"eat","partner_id":actor},"eat-test")
	check(int(w.assets.available_items(actor)[food]) == count-1,"Retry and repeated advance cannot double-consume")
	check(not w.work.command(actor,"start_leisure",{"activity":"sleep","partner_id":"lao_li"},"bad-sleep").ok,"Cannot sleep on someone else's schedule")
	check(not w.work.command(actor,"start_leisure",{"activity":"drink","partner_id":actor},"bad-drink").ok,"Drinking needs actual water service destination")
	resident.needs.fatigue = 90.0
	check(w.work.command(actor,"start_leisure",{"activity":"sleep","partner_id":actor},"sleep-test").ok,"Schedule sleep")
	activity = w.work.activities.values()[-1]
	activity.status = "working"; activity.worked = 180
	w.work._advance_activity(activity)
	check(activity.status == "completed" and resident.needs.fatigue == 5,"Sleep takes time and restores fatigue")
	resident.needs.thirst = 90.0
	check(w.work.command(actor,"start_leisure",{"activity":"drink","partner_id":"village_inn"},"drink-test").ok,"Schedule travel to drinking-water service")
	activity = w.work.activities.values()[-1]
	w.actor(actor).global_position = w.work.location("village_inn",actor)
	activity.status = "working"; activity.worked = 10
	w.work._advance_activity(activity)
	check(activity.status == "completed" and resident.needs.thirst == 10,"Drink only relieves thirst after actual arrival and time")
	check(not w.work.command(actor,"start_leisure",{"activity":"visit","partner_id":actor},"self-visit").ok,"Self visits cannot farm social rewards")
	resident.needs.social = 90.0; resident.needs.companionship = 90.0
	runtime.agreement_system._adjust_all_relationships([actor,"farmer_ahe"],3,w.minute())
	check(w.work.command(actor,"start_leisure",{"activity":"visit","partner_id":"farmer_ahe"},"visit-test").ok,"Arrange actual visit to an available trusted friend")
	activity = w.work.activities.values()[-1]
	w.actor(actor).global_position = w.work.location("farmer_ahe",actor)
	activity.status = "working"; activity.worked = 60
	w.work._advance_activity(activity)
	check(activity.status == "completed" and resident.needs.social == 45 and resident.needs.companionship == 60,"Trusted visit satisfies social and companionship needs")
	var before: Dictionary = farms.to_dict()
	# Completed receipts live in executor state; farm copies intentionally omit
	# duplicate finished receipts when compacting a save.
	before.finished = {}
	for farm in before.additional_farms.values(): farm.finished = {}
	var balance: Dictionary = w.assets.snapshot(actor)
	check(s.save_game() and s.load_game(),"Expanded save restores farms, needs, careers and activities")
	check(runtime.farm_registry.to_dict() == before and w.assets.snapshot(actor) == balance,"Reload does not reset crops or mint resources")
	check(w.society.residents[actor].needs.fatigue == 5,"Needs survive reload")
	var old: Dictionary = w.society.to_dict()
	for row in old.residents.values(): row.erase("needs")
	old.residents.xiao_hua.occupation = "花艺师"
	old.focus.erase("xiao_hua"); old.focus.erase("resident_shan")
	check(w.society.validate(old),"Previous resident save remains valid")
	w.society.restore(old)
	check("xiao_hua" in w.society.focus and w.society.residents.xiao_hua.has("needs"),"Old save gains new focus farmers and personal needs")
	var migrated: Dictionary = w.assets.snapshot(actor)
	w.society.restore(w.society.to_dict())
	check(w.assets.snapshot(actor) == migrated,"Migration grant is not repeated after saving")
	var roles: Dictionary = runtime.role_system.to_dict()
	for role in roles.roles:
		if role.agent_id == actor: role.active_role_id = "merchant"; role.history = ["merchant"]; role.last_changed_minute = -1
	check(runtime.role_system.from_dict(roles) and runtime.role_system.get_active_role(actor) == "farmer","Untouched old merchant default migrates to farmer")
	for role in roles.roles:
		if role.agent_id == actor: role.last_changed_minute = 10
	check(runtime.role_system.from_dict(roles) and runtime.role_system.get_active_role(actor) == "merchant","Intentional career changes are preserved")
	if "--check-existing-save" in OS.get_cmdline_user_args():
		# Read the real save, but restore and rewrite only this isolated copy.
		var content := FileAccess.get_file_as_string("res://data/farm_3d_save.json")
		s.save_path = "user://resident_existing_save_test.json"
		var file := FileAccess.open(s.save_path,FileAccess.WRITE)
		file.store_string(content); file.close()
		check(s.load_game(),"Actual existing save migrates without resetting the world")
		check(runtime.role_system.get_active_role("afu_shui") == "farmer" and "xiao_hua" in w.society.focus,"Actual save enables new farmers")
		var assets: Dictionary = w.assets.snapshot("xiao_hua")
		check(s.save_game() and s.load_game(),"Migrated real save copy reloads")
		check(w.assets.snapshot("xiao_hua") == assets,"Real save copy migration is idempotent")
	scene.free()
	print("RESIDENT NEEDS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

