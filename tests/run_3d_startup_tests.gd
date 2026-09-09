extends SceneTree

const Cache = preload("res://scripts/farm3d/terrain_cache.gd")
const Minimap = preload("res://scripts/farm3d/farm_minimap.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(100).timeout.connect(func(): push_error("Startup regression timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	Cache.directory = "res://tmp/startup-tests/%d" % OS.get_process_id()
	Minimap._shared_terrain = null
	var scene = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	var s: Farm3DSession = scene.farm_session
	s.season.set_process(false)
	s.living_world.set_process(false)
	s.player.set_physics_process(false)
	check(not s.auto_save and not s.auto_restore and not s.agent_runtime.service_enabled, "Startup regression is isolated from player save and remote service")
	var map: Control = scene.get_node("FarmInteraction").hud.minimap
	var debug_map: Control = scene.get_node("FarmInteraction").hud.debug_panel.teleport_map
	check(map._terrain == debug_map._terrain, "HUD and teleport map share one generated texture")
	var pixels: PackedByteArray = map._terrain.get_image().get_data()
	Minimap._shared_terrain = null
	var disk_map := Minimap.new()
	check(disk_map._make_terrain().get_image().get_data() == pixels, "Disk minimap cache reproduces every pixel exactly")
	disk_map.free()
	var grid := Farm3DFlatGrid.new()
	root.add_child(grid)
	check(grid.configure_flat(), "Cached static grid loads")
	var identical := grid._cells.size() == s.grid._cells.size()
	for key in grid._cells:
		var a: GridCell = grid._cells[key]
		var b: GridCell = s.grid._cells[key]
		if a.terrain_height != b.terrain_height or a.slope != b.slope or a.state != s._market_reserved.get(key, s.grid._base_states[key]): identical = false; break
	check(identical, "Cached grid preserves exact heights, slopes and base states across the entire expanded map")
	var signature: String = Cache._signature
	Cache._signature = "changed-terrain-version"
	check(Cache.read("grid").is_empty(), "A different terrain source signature invalidates disk data")
	Cache._signature = signature
	var file := FileAccess.open(Cache.directory.path_join("grid.cache"), FileAccess.READ_WRITE)
	file.seek(file.get_length() - 1)
	var byte := file.get_8()
	file.seek(file.get_length() - 1); file.store_8(byte ^ 1); file.close()
	check(Cache.read("grid").is_empty(), "Checksum rejects a damaged terrain cache")
	check(grid.configure_flat() and not Cache.read("grid").is_empty(), "Damaged cache rebuilds from authored terrain")
	var cell: GridCell = s.grid.get_cell(-2, 0)
	s.player.position = cell.world_position_3d() + Vector3.LEFT * 1.2
	var placed := s.buildings.try_place_building("beehive", -2, 0)
	check(placed.placed, "Building can be placed on valid negative map coordinates")
	s.save_path = Cache.directory.path_join("negative-building-save.json")
	check(s.save_game(), "Negative-coordinate building saves to isolated fixture")
	check(s.load_game(), "Full farm with negative-coordinate building loads successfully")
	check(s.buildings.get_building_at(-2, 0) != null, "Reload preserves the beehive instead of falling back to an empty farm")
	check(s.agent_runtime._prepared_restore.is_empty() and not s.agent_runtime._restore_preparation_active, "Successful full load releases its prepared Agent state")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(s.save_path))
	var invalid := saved.duplicate(true)
	invalid.buildings[0].gx = -10000000
	check(not s._valid_save(invalid), "Out-of-bounds negative coordinates remain invalid")
	var invalid_file := FileAccess.open(s.save_path, FileAccess.WRITE)
	invalid_file.store_string("broken JSON"); invalid_file.close()
	check(not s.load_game() and s.agent_runtime._prepared_restore.is_empty() and not s.agent_runtime._restore_preparation_active, "Failed full load also releases preparation scope")
	check(s.buildings.get_building_at(-2, 0) != null, "Failed load leaves existing in-memory buildings intact")
	grid.queue_free(); scene.queue_free(); await process_frame
	print("3D startup: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
