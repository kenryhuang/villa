extends SceneTree

var checks := 0
var failures: Array[String] = []
var session: Farm3DSession

func _initialize() -> void:
	create_timer(75).timeout.connect(func(): push_error("Beehive tests timed out"); quit(1))
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _frames(count := 3) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _flower(x: int, z: int, id := "rose", mature := true) -> GridCell:
	var cell := session.grid.get_cell(x,z)
	cell.state = GridCell.State.PLANTED
	cell.crop_instance = CropInstance.new()
	cell.crop_instance.crop_data = root.get_node("GameData").get_crop(id)
	if mature: cell.crop_instance.advance_game_minutes(cell.crop_instance.crop_data.growth_duration_minutes)
	session.farming._index_cell(x,z,cell.state)
	return cell

func _day(day: int) -> void:
	session.season.total_days = day
	session.season.current_day = (day-1)%SeasonSystem.DAYS_PER_SEASON+1
	session.season.current_season = ((day-1)/SeasonSystem.DAYS_PER_SEASON)%4
	session.production.finish_daily_outputs(day)

func _batch(hive: BuildingInstance) -> void:
	var snapshot := session.production.get_beehive_snapshot(hive)
	session.production.advance_minutes(int(snapshot.remaining_minutes))

func _run() -> void:
	root.size = Vector2i(1440,960)
	var farm := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	farm.set_process(false)
	session = farm.farm_session
	_check(not session.auto_save and not session.auto_restore,"Isolated farm does not read or overwrite player save")
	session.save_path = "res://tmp/beehive-test-save.json"
	session.season.set_process(false)
	session.agent_runtime.set_process(false)
	var interaction = farm.get_node("FarmInteraction")
	var hud = interaction.hud
	var view = hud.beehive_view
	var player = session.player
	player.set_physics_process(false)
	player.position = session.grid.get_cell(32,31).world_position_3d()+Vector3.LEFT*1.2
	var wood := session.inventory.get_item_count("wood")
	var placed := session.buildings.try_place_building("beehive",32,31)
	_check(placed.placed,"Hive builds through original cost and placement rules")
	if not placed.placed: quit(1); return
	var hive: BuildingInstance = placed.instance
	_check(session.inventory.get_item_count("wood") == wood-15,"Original fifteen wood cost charged exactly once")
	_check(not interaction.open_windmill(hive),"Incomplete hive cannot be opened")
	_check(not hive.has_node("ProductionYard"),"Modeled hive has no legacy textured ground yard")
	var model := hive.get_node("VisualRoot/Model")
	for stage in 4:
		hive.restore_construction(stage,stage*3)
		_check(model.get_node("Walls").visible == (stage>=2) and model.get_node("Roof").visible == (stage==3),"Native model follows construction stage %d" % stage)
	_check(model.find_children("*","MeshInstance3D",true,false).size()>40,"Hive and bees are real 3D geometry")
	_check(session.production.get_beehive_snapshot(hive).status == "no_flowers","No flowers means no production")
	_day(2)
	_check(hive.producer_state.outputs.is_empty(),"Hive cannot produce from empty land")
	var near := _flower(31,32,"rose",false)
	var far := _flower(7,32)
	_day(4)
	session.production.advance_minutes(8000)
	_check(hive.producer_state.outputs.is_empty(),"Immature and distant flowers do not generate honey")
	near.crop_instance.advance_game_minutes(near.crop_instance.crop_data.growth_duration_minutes)
	_batch(hive)
	_check(hive.producer_state.outputs == {"honey":1},"One nearby mature flower yields one honey")
	_check(near.crop_instance.is_mature() and near.state == GridCell.State.PLANTED,"Nectar gathering preserves the flowering plant")
	_day(6)
	_check(hive.producer_state.outputs == {"honey":1},"Repeated daily callback never duplicates honey")
	var second := _flower(31,33,"lavender")
	_batch(hive)
	_check(hive.producer_state.outputs == {"honey":3},"Two flower species retain original two-honey yield")
	hive._process(1.1)
	_check(model.bees[0].visible,"Mature nearby flowers enable bee flight")
	var before: Vector3 = model.bees[0].position
	hive._process(.4)
	_check(model.bees[0].position.distance_to(before)>.01,"Bee moves along a flower-bound flight arc")
	_check(hive.bee_round_trip_seconds(Vector3(12,.5,0)) > hive.bee_round_trip_seconds(Vector3(2,.5,0)),"Far bee flights take longer instead of accelerating to a fixed animation time")
	hive.set_preview_mode(true)
	hive._process(.1)
	_check(not model.bees[0].visible and hive.get_node("Collision").collision_layer==0,"Build preview has no working bees or physical collision")
	hive.set_preview_mode(false)
	hive._process(1.1)
	_check(hive.get_node("BuildingOutputDisplay").get_pile_count()==1,"Honey appears as a collectible 3D jar")
	player.position = hive.position+Vector3.BACK*2
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.position = hive.position+Vector3(3,2.8,5)
	camera.look_at(hive.position+Vector3.UP*.8)
	camera.make_current()
	await _frames()
	var pointer := camera.unproject_position(hive.position+Vector3.UP)
	_check(interaction.windmill_at_pointer(pointer).get("building")==hive,"Pointer ray recognizes the modeled hive")
	_check(interaction.open_windmill(hive),"Nearby player can open the hive")
	_check(view.visible and paused and player.ui_blocked,"Hive panel pauses time and blocks player input")
	_check(view.details.text.contains("2 株") and view.details.text.contains("剩余") and view.details.text.contains("我的待收取"),"Panel shows real flower count and player goods")
	root.content_scale_size = Vector2i(900,720)
	root.size = Vector2i(900,720)
	await _frames()
	_check(view.collect_button.get_global_rect().end.y < 720 and view.maintenance_button.get_global_rect().end.y < 720,"Distance details scroll while hive actions stay reachable in a small window")
	root.content_scale_size = Vector2i(1440,960)
	root.size = Vector2i(1440,960)
	await _frames()
	var blocked_key := InputEventKey.new()
	blocked_key.keycode = KEY_D
	blocked_key.physical_keycode = KEY_D
	blocked_key.pressed = true
	root.push_input(blocked_key,true)
	_check(not Input.is_action_pressed("move_right"),"Movement keys are disarmed while hive panel is open")
	var inventory_before := session.inventory.get_item_count("honey")
	var slots := session.inventory.slots.duplicate(true)
	for index in session.inventory.slots.size(): session.inventory.slots[index] = {"item_id":"stone","quantity":999}
	view._collect()
	_check(hive.producer_state.outputs=={"honey":3},"A full backpack leaves all honey safely stored")
	session.inventory.slots = slots
	view._collect()
	_check(session.inventory.get_item_count("honey")==inventory_before+3 and hive.producer_state.outputs.is_empty(),"Panel collects honey into original backpack")
	view._collect()
	_check(session.inventory.get_item_count("honey")==inventory_before+3,"Repeated collection cannot duplicate honey")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape,true)
	_check(not view.visible and not paused and not player.ui_blocked,"Escape restores time and player control")
	_check(not Input.is_action_pressed("move_right") and not player._dialogue_input_blocked,"Closing with a movement key held does not leave the player walking")
	# A real registered NPC owns the second flower; both owners receive exactly one unit.
	_check(session.grid.reserve_cells("farmer_ahe",[Vector2i(31,33)]),"Flower plot can belong to the real NPC economy")
	var npc_before := int(session.npc_economy.get_npc_state("farmer_ahe").inventory.get("honey",0))
	_batch(hive)
	_check(hive.producer_state.outputs == {"honey":1},"Player receives only the share from their own flower")
	_check(int(session.npc_economy.get_npc_state("farmer_ahe").inventory.get("honey",0))==npc_before+1,"NPC flower honey goes to the NPC inventory")
	_check(hive.producer_state.customer_outputs.is_empty(),"Successful NPC delivery clears escrow")
	# Hold original transaction service busy: output remains safely attributed and persisted.
	session.production.building_service.busy = true
	_batch(hive)
	_check(hive.producer_state.customer_outputs.get("farmer_ahe",{}) == {"honey":1},"Unavailable NPC transaction keeps their honey in escrow")
	var state := hive.producer_state.to_dict()
	var restored := ProducerState.new()
	_check(restored.from_dict(JSON.parse_string(JSON.stringify(state))) and restored.customer_outputs == hive.producer_state.customer_outputs,"Original producer serialization preserves owner-specific honey")
	_check(session.production.collect_outputs(hive,session.inventory).ok,"Player collects own honey while NPC goods remain protected")
	_check(hive.producer_state.customer_outputs.get("farmer_ahe",{}) == {"honey":1},"Player collection cannot take NPC honey")
	session.production.building_service.busy = false
	session.production.advance_minutes(1)
	_check(hive.producer_state.customer_outputs.is_empty() and int(session.npc_economy.get_npc_state("farmer_ahe").inventory.get("honey",0))==npc_before+2,"Retry delivers pending honey exactly once")
	session.production.advance_minutes(1)
	_check(int(session.npc_economy.get_npc_state("farmer_ahe").inventory.get("honey",0))==npc_before+2,"Retry cannot redeliver cleared escrow")
	# Full capacity counts both personal and NPC storage, not just player jars.
	hive.producer_state.outputs = {"honey":4}
	hive.producer_state.customer_outputs = {"farmer_ahe":{"honey":2}}
	session.production.building_service.busy = true
	session.production.set_maintenance_due_day(hive,100)
	_batch(hive)
	_check(hive.producer_state.outputs == {"honey":4} and hive.producer_state.customer_outputs.farmer_ahe.honey==2,"Full mixed storage blocks the entire next harvest")
	hive._process(1.1)
	_check(not model.bees[0].visible,"Full storage stops bee activity")
	session.production.building_service.busy = false
	session.production.advance_minutes(1)
	session.production.collect_outputs(hive,session.inventory)
	# Reallocation is independent of hive ownership.
	hive.owner_id = "farmer_ahe"
	_batch(hive)
	_check(hive.producer_state.outputs.is_empty() and hive.producer_state.customer_outputs.get("player",{}) == {"honey":1},"Player flower yields stay theirs even at an NPC-owned hive")
	_check(session.production.collect_outputs(hive,session.inventory).ok,"Player can collect their own share from an NPC-owned hive")
	hive.owner_id = "player"
	# Four flowers, two species: original bonus wax and fair integer allocation.
	var third := _flower(32,30)
	var fourth := _flower(33,30)
	var flowers := [near,second,third,fourth]
	var allocated := {"player":0,"farmer_ahe":0}
	for day in [2,4]:
		var shares: Dictionary = session.production._beehive_output_owners(flowers,{"honey":2},day)
		for owner in shares: allocated[owner] += int(shares[owner].honey)
	_check(allocated=={"player":3,"farmer_ahe":1},"Integer shares are proportional across successive cycles")
	_batch(hive)
	var wax := hive.producer_state.get_output_count("beeswax") + int(session.npc_economy.get_npc_state("farmer_ahe").inventory.get("beeswax",0))
	_check(wax>=1,"Four mature flowers of two species produce original bonus wax")
	session.production.set_maintenance_due_day(hive,18)
	var maintenance_outputs := hive.producer_state.to_dict()
	_day(20)
	_check(hive.producer_state.to_dict()==maintenance_outputs,"Overdue maintenance pauses passive honey production")
	_batch(hive)
	_check(hive.producer_state.to_dict()==maintenance_outputs,"Maintenance preserves partial-cycle time without producing")
	# All nearby nectar now belongs to the NPC, and an actual failed delivery is saved.
	session.production.set_maintenance_due_day(hive,100)
	session.production.collect_outputs(hive,session.inventory)
	for cell in [near,third,fourth]:
		cell.crop_instance = null
		cell.state = GridCell.State.FARMLAND
	session.production.building_service.busy = true
	_batch(hive)
	_check(hive.producer_state.outputs.is_empty() and hive.producer_state.customer_outputs.get("farmer_ahe",{})=={"honey":1},"All-NPC flowers yield no honey for the player")
	# Restore test-only reservation to the real registry before whole-world save/load.
	session.grid._cell_reservations.erase(GridSystem.cell_key(31,33))
	session.production.advance_minutes(37)
	_check(hive.producer_state.beehive_cycle.elapsed_minutes==37,"New flower ownership starts a fresh timed batch")
	session.living_world.environment.advance_to(session.living_world.minute())
	var saved_output := hive.producer_state.to_dict()
	_check(session.save_game(),"Whole farm saves to isolated tmp path")
	_check(session.load_game(),"Whole farm restores through original validation")
	hive = session.buildings.get_building_at(32,31)
	_check(hive != null and hive.has_node("VisualRoot/Model") and hive.producer_state.to_dict()==saved_output,"Save/load retains modeled hive and all stored output")
	var npc_loaded := int(session.npc_economy.get_npc_state("farmer_ahe").inventory.get("honey",0))
	session.production.finish_daily_outputs(session.season.total_days)
	_check(hive.producer_state.to_dict()==saved_output,"Loading and replaying settlement cannot duplicate saved escrow")
	session.production.building_service.busy = false
	session.production.advance_minutes(1)
	_check(hive.producer_state.customer_outputs.is_empty() and int(session.npc_economy.get_npc_state("farmer_ahe").inventory.get("honey",0))==npc_loaded+1,"Saved escrow delivers exactly once after loading")
	_check(hive.producer_state.beehive_cycle.elapsed_minutes==38,"Saved in-progress batch resumes from its exact elapsed time")
	_check(not hive.has_node("ProductionYard"),"Loading does not restore the removed painted ground")
	# Real NPC farmland reservations also survive full save/load.
	var npc_cell: GridCell = session.agent_runtime.farm_registry.get_plot_cell("farmer_ahe",0)
	_check(npc_cell != null and session.production._flower_owner(npc_cell)=="farmer_ahe","Honey reads the actual persisted NPC land owner")
	if (OS.get_cmdline_args()+OS.get_cmdline_user_args()).has("--capture-beehive"):
		session.production.set_maintenance_due_day(hive,100)
		model = hive.get_node("VisualRoot/Model")
		for coordinates in [Vector2i(31,32),Vector2i(31,33),Vector2i(32,30),Vector2i(33,30)]:
			_flower(coordinates.x,coordinates.y,"lavender" if coordinates.y==33 else "rose")
		session.grid.reserve_cells("farmer_ahe",[Vector2i(31,33)])
		session.farming.rebuild_visuals()
		camera.position = hive.position+Vector3(3,2.6,4.5)
		camera.look_at(hive.position+Vector3.UP*.7)
		camera.make_current()
		hive._process(1.1)
		player.position = hive.position+Vector3(-2,0,1)
		await _frames(20)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/beehive-model.png")
		player.position = hive.position+Vector3.BACK*2
		interaction.open_windmill(hive)
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/beehive-panel.png")
		hud.close_panels()
	farm.queue_free()
	await _frames()
	print("3D BEEHIVE: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL "+str(failures), checks])
	quit(0 if failures.is_empty() else 1)
