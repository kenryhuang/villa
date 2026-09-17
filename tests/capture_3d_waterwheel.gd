extends SceneTree

func _initialize() -> void:
	if DisplayServer.get_name()=="headless" or not "--farm-test" in OS.get_cmdline_user_args(): quit(1); return
	create_timer(90).timeout.connect(func(): quit(1))
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1440,960)
	var farm: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	var s: Farm3DSession = farm.farm_session
	farm.set_process(false);s.season.set_process(false);s.living_world.set_process(false);s.agent_runtime.set_process(false)
	s.agent_runtime.service_enabled=false;s.player.set_physics_process(false);s.player.hide()
	var interaction = farm.get_node("FarmInteraction")
	interaction.set_process(false);interaction.hud.hide()
	s.player.position=s.grid.get_cell(52,39).world_position_3d()+Vector3.LEFT*1.2
	var result := s.buildings.try_place_building("waterwheel",52,39)
	if not result.placed: push_error(str(result));quit(1);return
	var wheel: BuildingInstance=result.instance;wheel.complete_construction()
	s.player.position=s.grid.get_cell(48,35).world_position_3d()+Vector3.LEFT*1.2
	result=s.buildings.try_place_building("greenhouse",48,35)
	if not result.placed:push_error(str(result));quit(1);return
	var building: BuildingInstance=result.instance;building.complete_construction()
	wheel._process(1.1)
	var camera := Camera3D.new()
	farm.add_child(camera);camera.make_current();camera.fov=40
	var target := (building.position+wheel.position)*.5+Vector3.UP*.8
	var crops := ["carrot","strawberry","rose","grain","lemon","tomato","blueberry","lavender"]
	var cells := s.production.get_greenhouse_cells(building)
	for i in cells.size():
		var cell := s.grid.get_cell(cells[i].x,cells[i].y)
		s.grid.set_cell_state(cell.gx,cell.gz,GridCell.State.FARMLAND)
		var definition: CropData = root.get_node("GameData").get_crop(crops[i])
		var crop := s.farming.plant(cell,definition)
		if crop != null:
			crop.set_growth_state(float(definition.growth_days),CropInstance.LifecycleState.MATURE)
			s.farming.visual_adapter.sync_cell(cell)
	DirAccess.make_dir_recursive_absolute("res://docs/validation/images")
	for shot in [["front",Vector3(10,8,12)],["rear",Vector3(-10,7,-10)]]:
		camera.position=target+shot[1];camera.look_at(target)
		await capture(shot[0])
	camera.position=target+Vector3(10,8,12);camera.look_at(target)
	interaction.hud.show();interaction.hud.open_windmill(wheel)
	await capture("panel")
	interaction.hud.close_panels();interaction.hud.hide()
	wheel.restore_construction(1,3)
	await capture("construction")
	print("WATERWHEEL CAPTURE: 4 views")
	quit(0)

func capture(suffix: String) -> void:
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/validation/images/waterwheel_3d_"+suffix+".png")
