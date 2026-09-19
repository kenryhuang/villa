extends SceneTree

func _initialize() -> void:
	if DisplayServer.get_name()=="headless" or not "--farm-test" in OS.get_cmdline_user_args():quit(1);return
	create_timer(90).timeout.connect(func():quit(1))
	run.call_deferred()

func run() -> void:
	root.size=Vector2i(1440,960)
	var farm: Node=load("res://scenes/farm3d/main.tscn").instantiate();root.add_child(farm)
	var s: Farm3DSession=farm.farm_session
	farm.set_process(false);s.season.set_process(false);s.living_world.set_process(false);s.agent_runtime.set_process(false)
	s.agent_runtime.service_enabled=false;s.player.set_physics_process(false);s.player.hide()
	var interaction=farm.get_node("FarmInteraction")
	interaction.set_process(false);interaction.hud.hide()
	var placed: Array[BuildingInstance]=[]
	for entry in [["well",34,31],["waterwheel",32,31],["greenhouse",27,32]]:
		s.player.position=s.grid.get_cell(entry[1],entry[2]).world_position_3d()+Vector3.LEFT*1.2
		var result:=s.buildings.try_place_building(entry[0],entry[1],entry[2])
		if not result.placed:push_error(str(result));quit(1);return
		var building: BuildingInstance=result.instance;building.complete_construction();placed.append(building)
	placed[1]._process(1.1)
	var crops: Array[String]=["carrot","strawberry","rose","grain","lemon","tomato","blueberry","lavender"]
	var cells:=s.production.get_greenhouse_cells(placed[2])
	for i in cells.size():
		var cell:=s.grid.get_cell(cells[i].x,cells[i].y)
		s.grid.set_cell_state(cell.gx,cell.gz,GridCell.State.FARMLAND)
		var definition: CropData=root.get_node("GameData").get_crop(crops[i])
		var crop:=s.farming.plant(cell,definition)
		if crop!=null:
			crop.set_growth_state(float(definition.growth_days),CropInstance.LifecycleState.MATURE)
			s.farming.visual_adapter.sync_cell(cell)
	var camera:=Camera3D.new();farm.add_child(camera);camera.make_current();camera.fov=36
	var target:=placed[0].position+Vector3.UP*.9
	camera.position=target+Vector3(2.5,1.6,3.5);camera.look_at(target)
	await capture("detail")
	target=(placed[0].position+placed[2].position)*.5+Vector3.UP*.7
	camera.position=target+Vector3(8,10,13);camera.look_at(target)
	await capture("system")
	s.player.position=placed[0].position+Vector3.RIGHT*1.5
	interaction.hud.show();interaction.hud.open_windmill(placed[0])
	await capture("panel")
	interaction.hud.close_panels();interaction.hud.hide()
	placed[0].restore_construction(1,3)
	target=placed[0].position+Vector3.UP*.8
	camera.position=target+Vector3(2.5,1.6,3.5);camera.look_at(target)
	await capture("construction")
	print("WELL CAPTURE: 4 views");quit(0)

func capture(suffix: String) -> void:
	for i in 10:await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://docs/validation/images")
	root.get_texture().get_image().save_png("res://docs/validation/images/well_3d_"+suffix+".png")
