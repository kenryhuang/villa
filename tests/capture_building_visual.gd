extends SceneTree

const OUTPUT_PATH := "res://.godot/villa-building-system-verification.png"
const CLOSEUP_OUTPUT_PATH := "res://.godot/villa-building-construction-closeup.png"
const ROTATED_CLOSEUP_OUTPUT_PATH := "res://.godot/villa-building-construction-rotated-closeup.png"


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1600, 1000)
	var scene := load("res://tests/visual/building_system_verification.tscn") as PackedScene
	var instance := scene.instantiate()
	root.add_child(instance)
	current_scene = instance
	for _frame in 10:
		await process_frame
	if not bool(instance.call("_construction_contract_passes")):
		push_error("building verification capture has no valid staged construction")
		quit(1)
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not _save_capture(image, OUTPUT_PATH):
		quit(1)
		return

	var active := instance.get("_active_construction") as BuildingInstance
	var camera := instance.get_node("Camera3D") as Camera3D
	var feedback := active.get_node("ConstructionFeedback") as ConstructionFeedback
	active.set_process(false)
	feedback.set("_phase", 0.48)
	feedback.advance_animation(0.0001)
	instance.get_node("UI").visible = false
	var focus := active.global_position + Vector3(0.0, active.data.visual_size.y * 0.45, 0.0)
	camera.size = 4.2
	camera.position = focus + Vector3(5.0, 5.8, 5.0)
	camera.look_at(focus)
	for _frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var closeup := root.get_texture().get_image()
	if not _save_capture(closeup, CLOSEUP_OUTPUT_PATH):
		quit(1)
		return

	camera.position = focus + Vector3(-5.0, 5.8, 5.0)
	camera.look_at(focus)
	for _frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var rotated_closeup := root.get_texture().get_image()
	if not _save_capture(rotated_closeup, ROTATED_CLOSEUP_OUTPUT_PATH):
		quit(1)
		return
	quit(0)


func _save_capture(image: Image, path: String) -> bool:
	var absolute_output_path := ProjectSettings.globalize_path(path)
	var error := image.save_png(absolute_output_path)
	if error != OK:
		push_error("failed to save building verification capture: %s" % error_string(error))
		return false
	print("CAPTURE: %s (%dx%d)" % [absolute_output_path, image.get_width(), image.get_height()])
	return true
