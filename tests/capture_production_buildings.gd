extends SceneTree

const SCENE_PATH := "res://tests/visual/production_building_gallery.tscn"
const CAPTURES := {
	"complete": "res://.godot/production-buildings-complete.png",
	"construction": "res://.godot/production-buildings-construction.png",
	"idle": "res://.godot/production-buildings-idle.png",
	"active": "res://.godot/production-buildings-active.png",
}


func _init() -> void:
	call_deferred("_capture_all")


func _capture_all() -> void:
	root.size = Vector2i(1600, 1000)
	var packed := load(SCENE_PATH) as PackedScene
	var gallery := packed.instantiate()
	root.add_child(gallery)
	current_scene = gallery
	for _frame in 8:
		await process_frame
	if not bool(gallery.call("gallery_contract_passes")):
		_fail("production building gallery contract failed")
		return
	for mode in CAPTURES:
		gallery.call("set_capture_mode", mode)
		for _frame in 5:
			await process_frame
		if mode == "idle" and not bool(gallery.call("idle_activity_is_hidden")):
			_fail("idle activity layers must be hidden")
			return
		if mode == "active" and not bool(gallery.call("active_activity_is_visible")):
			_fail("active activity layers must show a nonzero frame")
			return
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path: String = CAPTURES[mode]
		var error := image.save_png(ProjectSettings.globalize_path(path))
		if error != OK:
			_fail("cannot save %s: %s" % [mode, error_string(error)])
			return
		print("CAPTURE: %s" % ProjectSettings.globalize_path(path))
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
