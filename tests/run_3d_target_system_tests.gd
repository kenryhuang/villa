extends SceneTree

const SessionScript = preload("res://scripts/farm3d/farm_session.gd")
const Crops = preload("res://scripts/core/crop_catalog.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Target system test timed out"); quit(1))
	_run.call_deferred()

func _check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		push_error(text)

func _run() -> void:
	var player := Node3D.new()
	root.add_child(player)
	var session := SessionScript.new()
	session.auto_restore = false
	session.auto_save = false
	root.add_child(session)
	session.configure(player)
	session.season.set_process(false)
	var cell: GridCell = session.grid.get_cell(19, 17)
	player.position = cell.world_position_3d() + Vector3(0, 0, 1.2)
	_check(session.apply_target(cell, "farmland", "paddy").ok, "Create water paddy with target selection")
	var key := GridSystem.cell_key(cell.gx, cell.gz)
	_check(session.paddy_cells.has(key) and session.farming.is_automatically_irrigated_cell(cell), "Paddy registers continuous irrigation")
	_check(session.visuals._visuals[key].has_node("PaddyWater"), "Paddy has visible shallow water")
	var stamina: int = root.get_node("GameState").player_state.stamina
	_check(not session.apply_target(cell, "farmland", "paddy").ok, "Repeated placement is rejected")
	_check(root.get_node("GameState").player_state.stamina == stamina, "Rejected placement costs no stamina")
	_check(session.apply_target(cell, "seed", "grain_seed").ok, "Paddy can plant original grain")
	cell.watered = false
	cell.crop_instance.is_watered_today = false
	session.rest()
	_check(session.farming.is_automatically_irrigated_cell(cell), "Paddy irrigation persists across days")
	_check(cell.crop_instance.lifecycle_state != CropInstance.LifecycleState.WITHERED, "Paddy crop survives a day without manual watering")
	cell.crop_instance.set_growth_state(3, CropInstance.LifecycleState.MATURE)
	_check(session.apply_target(cell, "", "").ok, "Paddy crops harvest without a tool selection")
	_check(session.apply_target(cell, "farmland", "dry").ok, "Empty paddy can convert to dry soil")
	_check(not session.farming.is_automatically_irrigated_cell(cell), "Dry soil no longer auto-irrigates")
	# Every imported seed must preserve original season, identity, visual and harvest yield.
	for crop in Crops.default_crop_definitions():
		if cell.crop_instance != null:
			cell.crop_instance.set_growth_state(0, CropInstance.LifecycleState.WITHERED)
			session.apply_target(cell, "", "")
		session.season.current_season = crop.seasons[0] if not crop.seasons.is_empty() else SeasonSystem.Season.SPRING
		session.farming.set_greenhouse_cells([Vector2i(cell.gx, cell.gz)] if crop.environment == "greenhouse_only" else [])
		var count: int = session.inventory.get_item_count(crop.plant_item_id)
		var planted := session.apply_target(cell, "seed", crop.plant_item_id)
		_check(planted.ok, "%s plants in its supported environment" % crop.crop_id)
		if not planted.ok:
			continue
		_check(cell.crop_instance.crop_data.crop_id == crop.crop_id, "%s retains original crop identity" % crop.crop_id)
		_check(session.inventory.get_item_count(crop.plant_item_id) == count - 1, "%s consumes its own seed" % crop.crop_id)
		cell.crop_instance.set_growth_state(crop.growth_days, CropInstance.LifecycleState.MATURE)
		session.visuals.sync_cell(cell)
		var before: int = session.inventory.get_item_count(crop.crop_id)
		_check(session.apply_target(cell, "", "").ok, "%s harvests directly" % crop.crop_id)
		_check(session.inventory.get_item_count(crop.crop_id) >= before + crop.yield_min, "%s harvest reaches backpack" % crop.crop_id)
	if cell.crop_instance != null:
		cell.crop_instance.set_growth_state(0, CropInstance.LifecycleState.WITHERED)
		session.apply_target(cell, "", "")
	session.farming.set_greenhouse_cells([])
	session.season.current_season = SeasonSystem.Season.WINTER
	var seeds: int = session.inventory.get_item_count("grain_seed")
	_check(session.apply_target(cell, "seed", "grain_seed").reason == "wrong_season", "Winter forbids grain without guessing season numbers")
	_check(session.inventory.get_item_count("grain_seed") == seeds, "Out-of-season planting spends no seeds")
	_check(session.apply_target(cell, "seed", "lemon_sapling").reason == "greenhouse_required", "Lemon retains greenhouse requirement")
	# A real building spends resources, constructs, restores, and registers greenhouse coverage.
	var building_cell: GridCell = session.grid.get_cell(26, 23)
	player.position = building_cell.world_position_3d() + Vector3(-1.2, 0, 0)
	var planks: int = session.inventory.get_item_count("plank")
	_check(session.apply_target(building_cell, "building", "greenhouse").ok, "Original greenhouse can be placed from target menu")
	_check(session.inventory.get_item_count("plank") == planks - 15, "Building pays original material cost")
	var greenhouse: BuildingInstance = session.buildings.get_building_at(26, 23)
	if greenhouse != null:
		greenhouse.advance_construction(100)
		var locations: Array = session.production.get_greenhouse_cells(greenhouse)
		_check(locations.size() == 8, "Original greenhouse exposes eight planting cells")
		var plot: GridCell = session.grid.get_cell(locations[0].x, locations[0].y)
		player.position = plot.world_position_3d() + Vector3(-1.2, 0, 0)
		_check(session.farming.is_greenhouse_cell(plot), "Construction activates original greenhouse coverage")
		_check(session.apply_target(plot, "farmland", "dry").ok, "Greenhouse garden can be cultivated")
		_check(session.apply_target(plot, "seed", "lemon_sapling").ok, "Lemon can be planted beside a completed greenhouse")
	var distant: GridCell = session.grid.get_cell(2, 22)
	_check(session.apply_target(distant, "building", "fence").reason == "out_of_range", "Remote building cannot bypass player reach")
	player.position = cell.world_position_3d() + Vector3(0, 0, 1.2)
	_check(session.apply_target(cell, "farmland", "paddy").ok, "Recreate paddy for persistence")
	session.save_path = "user://target_menu_test.json"
	_check(session.save_game(), "Target state saves atomically")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.save_path))
	_check(session._valid_save(saved), "Save containing buildings and paddy validates")
	var inventory_before := session.inventory.slots.duplicate(true)
	_check(session.load_game(), "Building and paddy save restores")
	_check(session.inventory.slots == inventory_before, "Loading current save does not replenish supplies")
	_check(session.paddy_cells.has(key) and session.buildings.get_building_count() == 1, "Paddy type and placed building persist")
	var bad := saved.duplicate(true)
	bad.paddy_cells = ["outside_grid"]
	_check(not session._valid_save(bad), "Invalid paddy positions rejected before restoration")
	# Legacy v1 farm remains intact and receives catalog supplies just once.
	var legacy := saved.duplicate(true)
	legacy.version = 1
	legacy.erase("paddy_cells")
	legacy.erase("gold")
	legacy.erase("buildings")
	legacy.erase("production")
	for field in ["market", "npc_economy", "market_site", "golf"]:
		legacy.erase(field)
	for entry in legacy.grid.cells:
		if int(entry.state) == GridCell.State.BUILDING:
			entry.state = GridCell.State.WASTELAND
	var file := FileAccess.open(session.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	_check(session.load_game(), "Legacy v1 save migrates successfully")
	_check(session.inventory.get_item_count("carrot") > 0, "Legacy migration preserves harvest items")
	_check(session.save_game(), "Migrated save writes current version")
	var migrated_seeds: int = session.inventory.get_item_count("carrot_seed")
	_check(session.load_game() and session.inventory.get_item_count("carrot_seed") == migrated_seeds, "Migration supplies are never duplicated on reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(session.save_path))
	session.queue_free()
	player.queue_free()
	await process_frame
	print("3D TARGET SYSTEM: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
