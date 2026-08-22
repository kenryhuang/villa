extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const OUTPUT_DIR := "res://output/hud"
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]


func _init() -> void:
	call_deferred("_capture_all")


func _capture_all() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("HUD capture requires the Windows display driver")
		quit(1)
		return
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("cannot create HUD capture directory")
		quit(1)
		return
	var capture_count := 0
	for viewport_size in SIZES:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		for collapsed in [false, true]:
			var main = MainScene.instantiate()
			main.load_save_on_start = false
			root.add_child(main)
			for _frame in range(4):
				await process_frame
			main.hud_message_bus.publish("farming", "success", "已播种薰衣草", {"timestamp_msec": 1000})
			main.hud_message_bus.publish("building", "warning", "此处空间不足", {"timestamp_msec": 2100})
			main.hud_message_bus.publish("debug", "debug", "推进了 3 株作物，其中 1 株成熟", {"timestamp_msec": 3200})
			main.hud.message_stream.call("set_collapsed", collapsed)
			for _frame in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var state := "collapsed" if collapsed else "expanded"
			var file_name := "hud_%s_%dx%d.png" % [state, viewport_size.x, viewport_size.y]
			var save_error := image.save_png(output_path.path_join(file_name))
			if save_error != OK:
				push_error("cannot save %s: %s" % [file_name, error_string(save_error)])
				quit(1)
				return
			print("CAPTURED: %s" % file_name)
			capture_count += 1
			main.free()
			await process_frame
	print("PASS: %d HUD shell captures" % capture_count)
	quit(0)
