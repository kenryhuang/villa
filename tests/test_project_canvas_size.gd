extends SceneTree


func _init() -> void:
	var viewport_size := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)
	if viewport_size != Vector2i(3000, 2000):
		push_error("project canvas must be 3000x2000, got %s" % viewport_size)
		quit(1)
		return

	var window_size := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/window_width_override")),
		int(ProjectSettings.get_setting("display/window/size/window_height_override"))
	)
	if window_size != Vector2i(3000, 2000):
		push_error("project window override must be 3000x2000, got %s" % window_size)
		quit(1)
		return

	print("PASS: project canvas and window override are 3000x2000")
	quit(0)
