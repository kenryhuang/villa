extends SceneTree

const Session = preload("res://scripts/farm3d/farm_session.gd")
var checks := 0
var failures: Array[String] = []
var test_path := "user://save_protection_%d.json" % OS.get_process_id()

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _session(player: Node3D, restore: bool) -> Farm3DSession:
	var session := Session.new()
	session.auto_restore = restore
	session.auto_save = false
	session.save_path = test_path
	root.add_child(session)
	return session

func _run() -> void:
	var player := Node3D.new()
	root.add_child(player)
	var source := _session(player, false)
	_check(source.configure(player), "New farm initializes when no save exists")
	source.season.set_process(false)
	for entry in [["barn",20,23],["windmill",25,24],["food_workshop",32,31]]:
		player.position = source.grid.get_cell(entry[1],entry[2]).world_position_3d()+Vector3.LEFT*1.2
		var result := source.buildings.try_place_building(entry[0],entry[1],entry[2])
		_check(result.placed,"Can build "+entry[0])
		if not result.placed:
			quit(1)
			return
		result.instance.complete_construction()
	_check(source.save_game(),"Three completed buildings save")
	var original := FileAccess.get_file_as_string(test_path)
	source.inventory.add_item("egg",1)
	_check(source.save_game(),"Save replaces the previous version")
	_check(FileAccess.get_file_as_string(test_path+".bak") == original,"First overwrite keeps the prior farm as a backup")
	source.inventory.add_item("egg",1)
	_check(source.save_game() and FileAccess.get_file_as_string(test_path+".bak") == original,"Repeated autosaves preserve the pre-overwrite backup")
	for damaged in ["not json",JSON.stringify({"version":999})]:
		var file := FileAccess.open(test_path,FileAccess.WRITE)
		file.store_string(damaged)
		file.close()
		var fresh := _session(player,true)
		_check(fresh.configure(player),"Unreadable/incompatible save starts a fresh farm")
		fresh.season.set_process(false)
		fresh.auto_save = true
		_check(fresh.auto_save and fresh.inventory.get_item_count("grain_seed") == 99,"Fresh startup restores initial inventory and normal saving")
		_check(fresh.buildings.get_all_buildings().is_empty(),"Fresh startup does not restore buildings from a damaged save")
		_check(fresh.save_game(),"Fresh startup can replace the damaged save")
		var rebuilt: Variant = JSON.parse_string(FileAccess.get_file_as_string(test_path))
		_check(rebuilt is Dictionary and int(rebuilt.get("version",0)) == 4 and rebuilt.buildings.is_empty(),"Replacement save is a valid fresh snapshot")
		fresh.free()
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path+suffix))
	source.free()
	player.free()
	print("3D SAVE PROTECTION: %s (%d checks)" % ["PASS" if failures.is_empty() else str(failures),checks])
	quit(0 if failures.is_empty() else 1)
