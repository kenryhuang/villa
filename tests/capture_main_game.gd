extends SceneTree

const OUTPUT_PATH := "/tmp/villa-main-game.png"


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1600, 1000)
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("failed to load main scene")
		quit(1)
		return
	var instance = scene.instantiate()
	root.add_child(instance)
	current_scene = instance
	# Wait for systems to initialize
	for _frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("failed to save capture: %s" % error_string(error))
		quit(1)
		return
	print("CAPTURE: %s (%dx%d)" % [OUTPUT_PATH, image.get_width(), image.get_height()])
	quit(0)
