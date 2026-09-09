extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate(); root.add_child(scene)
	var s: Farm3DSession = scene.farm_session
	if s.auto_save or s.auto_restore or s.living_world.society.residents.size() != 12: quit(1); return
	if not preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P8"): quit(1); return
	s.save_path = "res://tmp/living-world/P12-legacy-fixture.json"
	if not s.save_game(): quit(1); return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(s.save_path))
	data.version = 12; data.living_world.society.version = 1; data.living_world.society.erase("focus"); data.living_world.society.erase("feeding"); data.living_world.society.erase("cooperative"); data.living_world.society.erase("minute_batch")
	var f := FileAccess.open(s.save_path, FileAccess.WRITE); f.store_string(JSON.stringify(data, "  ")); f.close()
	print("P12 legacy 12-person fixture saved in tmp")
	scene.queue_free(); await process_frame; quit(0)
