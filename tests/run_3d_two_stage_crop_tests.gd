extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Two-stage crop test timed out"); quit(1))
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _crop_node(session: Farm3DSession, cell: GridCell) -> Node3D:
	var holder: Node3D = session.visuals._visuals[GridSystem.cell_key(cell.gx, cell.gz)]
	return holder.get_node("Crop_" + str(cell.crop_instance.crop_data.crop_id))

func _check_geometry(crop: Node3D, mature: bool) -> void:
	_check(crop.find_children("*", "Sprite3D", true, false).is_empty(), "Modeled crop has no sprites")
	var bounds := AABB()
	var first := true
	for mesh_node in crop.find_children("*", "MeshInstance3D", true, false):
		var local_bounds: AABB = (crop.global_transform.affine_inverse() * mesh_node.global_transform) * mesh_node.get_aabb()
		bounds = local_bounds if first else bounds.merge(local_bounds)
		first = false
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(surface) as StandardMaterial3D
			var colors := mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR] as PackedColorArray
			_check(material != null and material.vertex_color_use_as_albedo and not colors.is_empty() and colors[0] != Color.WHITE, "Imported mesh retains visible paint colors")
			_check(material != null and material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED, "Imported mesh never faces the camera")
	_check(not first and bounds.position.y < 0 and bounds.end.y > 0, "Roots or seeds intersect the soil origin")
	_check(bounds.size.x > .08 and bounds.size.z > .08, "Plant has real width and depth")
	_check(bounds.size.y > .20 if mature else bounds.size.y < .45, "Mature foliage and seeds or saplings have appropriate heights")
	_check(is_equal_approx(crop.position.y, .045), "Crop origin rests at field height")

func _run() -> void:
	var player := Node3D.new()
	root.add_child(player)
	var session := Farm3DSession.new()
	session.auto_restore = false
	session.auto_save = false
	session.save_path = "user://two_stage_crop_test_%d.json" % OS.get_process_id()
	root.add_child(session)
	session.configure(player)
	session.season.set_process(false)
	var definitions: Array[CropData] = []
	for definition in CropCatalog.default_crop_definitions():
		_check(definition.crop_id in ["grain", "rose"] or Farm3DCropVisualSystem.TWO_STAGE_CROPS.has(definition.crop_id), definition.crop_id + " has an authored 3D visual")
		if Farm3DCropVisualSystem.TWO_STAGE_CROPS.has(definition.crop_id):
			definitions.append(definition)
	_check(definitions.size() == 13, "All thirteen two-stage crops are covered")
	for index in definitions.size():
		var player_state: PlayerState = root.get_node("GameState").player_state
		player_state.set_stamina(player_state.max_stamina)
		var definition := definitions[index]
		var crop_id: String = definition.crop_id
		var maturity := float(definition.growth_days)
		session.season.current_season = definition.seasons[0] if not definition.seasons.is_empty() else SeasonSystem.Season.SPRING
		var gx := 19 + index % 3
		var gz := 18 + (index / 3) * 2
		var cell: GridCell = session.grid.get_cell(gx, gz)
		session.farming.set_greenhouse_cells([Vector2i(cell.gx,cell.gz)] if definition.environment == "greenhouse_only" else [])
		player.position = cell.world_position_3d() + Vector3(0,0,1.2)
		_check(session.apply_target(cell,"farmland","dry").ok, crop_id + " plot cultivates")
		_check(session.apply_target(cell,"seed",definition.plant_item_id).ok, crop_id + " plants through original seed action")
		if cell.crop_instance == null:
			quit(1)
			return
		var seed := _crop_node(session,cell)
		var orientation := seed.basis
		var seed_path := seed.scene_file_path
		_check_geometry(seed,false)
		for progress in [maturity*.25,maturity*.75,maturity-.01]:
			cell.crop_instance.set_growth_state(progress,CropInstance.LifecycleState.GROWING)
			session.visuals.sync_cell(cell)
			_check(_crop_node(session,cell).scene_file_path == seed_path, "No intermediate model before maturity")
		cell.crop_instance.set_growth_state(maturity,CropInstance.LifecycleState.MATURE)
		session.visuals.sync_cell(cell)
		var grown := _crop_node(session,cell)
		_check_geometry(grown,true)
		_check(grown.basis.is_equal_approx(orientation), "Stage swap preserves world orientation")
		_check(grown.scene_file_path != seed_path, "Maturity switches to full plant")
		var mature_path := grown.scene_file_path
		_check(session.save_game() and session.load_game(), "Crop model survives save and restore")
		cell = session.grid.get_cell(gx,gz)
		# The isolated greenhouse fixture is not a saved building; restore test coverage.
		session.farming.set_greenhouse_cells([Vector2i(cell.gx,cell.gz)] if definition.environment == "greenhouse_only" else [])
		if definition.environment == "greenhouse_only":
			# Loading without a real greenhouse correctly withers this isolated fixture.
			# Re-establish maturity after coverage for the separate harvest assertion.
			cell.crop_instance.set_growth_state(maturity,CropInstance.LifecycleState.MATURE)
			session.visuals.sync_cell(cell)
		_check(_crop_node(session,cell).scene_file_path == mature_path, "Restored mature crop selects the same model")
		var before: int = session.inventory.get_item_count(crop_id)
		_check(session.apply_target(cell,"","").ok, "Mature model harvests normally")
		_check(session.inventory.get_item_count(crop_id) > before, "%s harvest reaches backpack (%d -> %d)" % [crop_id,before,session.inventory.get_item_count(crop_id)])
		_check(cell.crop_instance == null, "Original harvest rule removes the plant, including tomato")
		_check(session.apply_target(cell,"seed",definition.plant_item_id).ok, "Crop can be replanted")
		cell.crop_instance.set_growth_state(maturity,CropInstance.LifecycleState.MATURE)
		# Both seed-stage and mature-stage withering reuse the authored assets.
		for progress in [maturity,0.0]:
			cell.crop_instance.set_growth_state(progress,CropInstance.LifecycleState.WITHERED)
			session.visuals.sync_cell(cell)
			for mesh_node in _crop_node(session,cell).find_children("*", "MeshInstance3D", true, false):
				_check(mesh_node.material_override != null, "Withering recolors existing geometry")
		before = session.inventory.get_item_count(crop_id)
		_check(session.apply_target(cell,"","").ok and session.inventory.get_item_count(crop_id) == before, "Withered crop clears without adding yield")
		var old := (load("res://assets/crops/%s/%s_stage_3_mature.tscn" % [crop_id,crop_id]) as PackedScene).instantiate()
		root.add_child(old)
		_check(not old.find_children("*", "Sprite3D", true, false).is_empty(), "Old 2D scene remains intact")
		old.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(session.save_path))
	session.queue_free()
	player.queue_free()
	await process_frame
	print("TWO STAGE CROPS: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
