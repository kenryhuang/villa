extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const OUTPUT_DIR := "res://output/seed-selector"
const SIZES := [Vector2i(1920, 1080), Vector2i(640, 960)]


func _init() -> void:
	call_deferred("_capture_all")


func _capture_all() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("seed selector capture requires the Windows display driver")
		quit(1)
		return
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("cannot create seed selector capture directory")
		quit(1)
		return
	for viewport_size in SIZES:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		var main = MainScene.instantiate()
		main.load_save_on_start = false
		root.add_child(main)
		for _frame in range(4):
			await process_frame
		for item_id in ["carrot_seed", "tomato_seed", "rose_seed", "lavender_seed"]:
			main.inventory_system.add_item(item_id, 6)
		var target_cell: GridCell = null
		for cell_value in main.grid_system._cells.values():
			var cell := cell_value as GridCell
			if main.grid_system.can_farm_at(cell.gx, cell.gz):
				target_cell = cell
				break
		if target_cell != null:
			main.grid_system.set_cell_state(target_cell.gx, target_cell.gz, GridCell.State.FARMLAND)
		main.seed_selector_panel.open_for_cell(target_cell)
		for _frame in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var file_name := "seed_selector_%dx%d.png" % [viewport_size.x, viewport_size.y]
		var save_error := image.save_png(output_path.path_join(file_name))
		if save_error != OK:
			push_error("cannot save %s: %s" % [file_name, error_string(save_error)])
			quit(1)
			return
		print("CAPTURED: %s" % file_name)
		main.seed_selector_panel.close()
		main.free()
		await process_frame
	print("PASS: 2 seed selector card captures")
	quit(0)
