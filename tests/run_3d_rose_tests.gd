extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var player := Node3D.new()
	root.add_child(player)
	var session := Farm3DSession.new()
	session.auto_restore = false
	session.auto_save = false
	root.add_child(session)
	session.configure(player)
	session.season.set_process(false)
	session.season.current_season = SeasonSystem.Season.SPRING
	var cell: GridCell = session.grid.get_cell(19, 18)
	player.position = cell.world_position_3d() + Vector3(0, 0, 1.2)
	_check(session.apply_target(cell, "farmland", "dry").ok, "Rose plot can be cultivated")
	_check(session.apply_target(cell, "seed", "rose_seed").ok, "Original rose seed plants through the real action system")
	if cell.crop_instance == null:
		quit(1)
		return
	var camera := Camera3D.new()
	root.add_child(camera)
	var heights: Array[float] = []
	var stage_paths: Array[String] = []
	var orientation := Basis.IDENTITY
	for index in 5:
		var crop: CropInstance = cell.crop_instance
		crop.set_growth_state([0.0, 1.5, 3.0, 4.0, 4.0][index], CropInstance.LifecycleState.WITHERED if index == 4 else (CropInstance.LifecycleState.MATURE if index == 3 else CropInstance.LifecycleState.GROWING))
		session.visuals.sync_cell(cell)
		var holder: Node3D = session.visuals._visuals[GridSystem.cell_key(cell.gx, cell.gz)]
		var rose := holder.get_node("Crop_rose") as Node3D
		stage_paths.append(rose.scene_file_path)
		_check(rose.find_children("*", "Sprite3D", true, false).is_empty(), "Stage %d has no flat sprites" % index)
		var meshes := rose.find_children("*", "MeshInstance3D", true, false)
		_check(not meshes.is_empty(), "Stage %d has imported geometry" % index)
		var bounds := AABB()
		var first := true
		for mesh_node in meshes:
			var local_bounds: AABB = (rose.global_transform.affine_inverse() * mesh_node.global_transform) * mesh_node.get_aabb()
			bounds = local_bounds if first else bounds.merge(local_bounds)
			first = false
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.get_active_material(surface) as StandardMaterial3D
				_check(material != null and material.vertex_color_use_as_albedo, "Stage %d enables imported paint colors" % index)
				_check(material != null and material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED, "Stage %d material does not face camera" % index)
				var colors := mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR] as PackedColorArray
				_check(not colors.is_empty() and colors[0] != Color.WHITE, "Stage %d retains non-white paint data" % index)
		_check(bounds.position.y < 0.0 and bounds.end.y > 0.0, "Stage %d roots/seeds straddle the soil origin" % index)
		_check(is_equal_approx(rose.position.y, 0.045), "Stage %d uses the field surface instead of an image pivot" % index)
		_check(bounds.size.x > 0.15 and bounds.size.z > 0.15 and bounds.size.y > 0.01, "Stage %d has volume in every axis" % index)
		heights.append(bounds.end.y)
		if index == 0:
			orientation = rose.basis
		_check(rose.basis.is_equal_approx(orientation), "Growth stages preserve orientation")
		var before := rose.global_transform
		camera.position = rose.global_position + Vector3(2.0, 0.05, 0.0)
		camera.look_at(rose.global_position + Vector3.UP * 0.1)
		await process_frame
		camera.position = rose.global_position + Vector3(0.0, 2.0, -2.0)
		camera.look_at(rose.global_position)
		await process_frame
		_check(rose.global_transform.is_equal_approx(before), "Orbiting camera leaves stage %d fixed in the world" % index)
	_check(heights[0] < heights[1] and heights[1] < heights[2] and heights[2] < heights[3], "Seed, sprout, bud and bloom have distinct growing silhouettes")
	_check(stage_paths[0] != stage_paths[1] and stage_paths[1] != stage_paths[2] and stage_paths[3] != stage_paths[4], "Growth and withering use distinct assets")
	var before: int = session.inventory.get_item_count("rose")
	_check(session.apply_target(cell, "", "").ok, "Withered 3D rose clears normally")
	_check(session.inventory.get_item_count("rose") == before, "Clearing the withered model adds no inventory")
	_check(session.apply_target(cell, "seed", "rose_seed").ok, "Cleared plot accepts another rose")
	cell.crop_instance.set_growth_state(4.0, CropInstance.LifecycleState.MATURE)
	session.visuals.sync_cell(cell)
	_check(session.apply_target(cell, "", "").ok and session.inventory.get_item_count("rose") > before, "Mature modeled rose harvest reaches the backpack")
	var old := (load("res://assets/crops/rose/rose_stage_3_mature.tscn") as PackedScene).instantiate()
	root.add_child(old)
	_check(not old.find_children("*", "Sprite3D", true, false).is_empty(), "Original 2D rose remains available to the old game")
	old.queue_free()
	session.queue_free()
	player.queue_free()
	camera.queue_free()
	await process_frame
	print("3D ROSE: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
