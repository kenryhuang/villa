extends SceneTree

const FlatGridScript = preload("res://scripts/farm3d/flat_grid.gd")
const MeadowScript = preload("res://scripts/farm3d/painted_meadow.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var grid = FlatGridScript.new()
	_check(grid.configure_flat(), "Flat 3D grid configures for meadow ownership")
	var meadow = MeadowScript.new()
	root.add_child(meadow)
	meadow.configure(grid)
	var mapped_positions := true
	for key in meadow._by_cell:
		for record_index in meadow._by_cell[key]:
			var record: Dictionary = meadow._instances[int(record_index)]
			var origin: Vector3 = record.transform.origin
			mapped_positions = mapped_positions and meadow._grid_key(Vector2(origin.x, origin.z)) == key
	_check(mapped_positions, "Every generated grid clump remains in the grid cell that owns its mask")
	var cultivated := Vector2i(18, 13)
	var cell := grid.get_cell(cultivated.x, cultivated.y)
	_check(cell != null and grid.set_cell_state(cultivated.x, cultivated.y, GridCell.State.FARMLAND), "A central wasteland cell cultivates")
	meadow.refresh_cell(cultivated.x, cultivated.y)
	var masked := true
	for record_index in meadow._by_cell[cultivated]:
		var record: Dictionary = meadow._instances[int(record_index)]
		masked = masked and bool(record.hidden)
	_check(masked, "Cultivating a cell masks every grass clump owned by that cell")
	meadow.queue_free()
	await process_frame
	grid.free()
	print("3D MEADOW: %s" % ("PASS (%d checks)" % checks if failures.is_empty() else "FAIL (%d/%d checks)" % [failures.size(), checks]))
	quit(0 if failures.is_empty() else 1)
