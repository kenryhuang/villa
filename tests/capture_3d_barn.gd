extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not "--farm-test" in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(1440,960)
	var farm := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var player: Node3D = farm.get_node("Player")
	player.set_physics_process(false)
	player.hide()
	farm.get_node("FarmInteraction").set_process(false)
	farm.get_node("FarmInteraction").hud.hide()
	var session: Farm3DSession = farm.get_node("FarmSession")
	session.season.set_process(false)
	var cell := session.grid.get_cell(32,31)
	player.position = cell.world_position_3d()+Vector3.LEFT*1.2
	var result := session.buildings.try_place_building("barn",32,31)
	if not result.placed:
		push_error(str(result))
		quit(1)
		return
	var barn: BuildingInstance = result.instance
	barn.set_process(false)
	barn.complete_construction()
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.current = true
	camera.fov = 43
	var target := barn.position+Vector3.UP*1.4
	for shot in [["front",Vector3(4,1.8,6)],["rear",Vector3(-4,1.3,-6)],["low",Vector3(3,-.8,6)]]:
		camera.position = target+shot[1]
		camera.look_at(target)
		await _capture(str(shot[0]))
	camera.position = target+Vector3(4,2.0,6)
	camera.look_at(target)
	for stage in 3:
		barn.restore_construction(stage,stage*3.0)
		await _capture("stage_%d" % stage)
	barn.complete_construction()
	barn.set_preview_mode(true)
	barn.set_preview_valid(true)
	await _capture("preview_valid")
	barn.set_preview_valid(false)
	await _capture("preview_invalid")
	farm.queue_free()
	await process_frame
	print("BARN CAPTURE: 8 views")
	quit(0)

func _capture(suffix: String) -> void:
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png("res://docs/validation/images/barn_3d_"+suffix+".png") != OK:
		push_error("Barn screenshot failed")
		quit(1)
