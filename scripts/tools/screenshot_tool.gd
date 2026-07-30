extends Node

var _frames_waited := 0

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	_frames_waited += 1
	if _frames_waited >= 10:
		var viewport = get_viewport()
		await RenderingServer.frame_post_draw
		var image = viewport.get_texture().get_image()
		var err = image.save_png("/tmp/villa_screenshot.png")
		if err == OK:
			print("SCREENSHOT_OK: /tmp/villa_screenshot.png")
		else:
			print("SCREENSHOT_FAILED: error %d" % err)
		get_tree().quit()
