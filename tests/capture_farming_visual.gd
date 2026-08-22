extends SceneTree

const CROPS := ["tomato", "potato", "rose", "lavender"]
const CROP_NAMES := ["番茄", "土豆", "玫瑰", "薰衣草"]
const OUTPUT_DIR := "res://output/farming"


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1600, 1000)
	var gallery := _build_gallery()
	root.add_child(gallery)
	current_scene = gallery
	var camera := gallery.get_node("Camera3D") as Camera3D
	for _frame in 8:
		await process_frame
	await _save_view(camera, Vector3(0.0, 4.7, 8.2), "two_stage_front.png")
	await _save_view(camera, Vector3(0.0, 4.7, -8.2), "two_stage_back.png")
	quit(0)


func _build_gallery() -> Node3D:
	var gallery := Node3D.new()
	gallery.name = "TwoStageCropGallery"
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.31, 0.48, 0.58)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.92, 0.82)
	environment.ambient_light_energy = 0.78
	environment_node.environment = environment
	gallery.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58.0, -30.0, 0.0)
	light.light_color = Color(1.0, 0.94, 0.8)
	light.light_energy = 1.0
	gallery.add_child(light)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.current = true
	gallery.add_child(camera)
	for crop_index in CROPS.size():
		for stage_index in 2:
			var stage := 0 if stage_index == 0 else 3
			var position := Vector3(-4.5 + crop_index * 3.0, 0.0, 1.45 - stage_index * 2.9)
			_add_plot(gallery, position)
			_add_crop(gallery, CROPS[crop_index], stage, position)
			_add_label(
				gallery,
				"%s · %s" % [CROP_NAMES[crop_index], "种子" if stage == 0 else "成熟"],
				position + Vector3(0.0, 1.55 if stage == 3 else 0.82, 0.0)
			)
	return gallery


func _add_plot(parent: Node3D, position: Vector3) -> void:
	var plot := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.35, 0.08, 2.15)
	plot.mesh = mesh
	plot.position = position - Vector3(0.0, 0.04, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.16, 0.075)
	material.roughness = 1.0
	plot.material_override = material
	parent.add_child(plot)


func _add_crop(parent: Node3D, crop_id: String, stage: int, position: Vector3) -> void:
	var suffix := "seed" if stage == 0 else "mature"
	var path := "res://assets/crops/%s/%s_stage_%d_%s.tscn" % [crop_id, crop_id, stage, suffix]
	var crop := (load(path) as PackedScene).instantiate() as Node3D
	crop.position = position + Vector3(0.0, 0.02, 0.0)
	parent.add_child(crop)


func _add_label(parent: Node3D, text: String, position: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 42
	label.outline_size = 9
	label.modulate = Color(1.0, 0.94, 0.72)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = position
	parent.add_child(label)


func _save_view(camera: Camera3D, position: Vector3, file_name: String) -> void:
	camera.position = position
	camera.look_at(Vector3.ZERO)
	for _frame in 4:
		await process_frame
	var directory := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	var output_path := "%s/%s" % [directory, file_name]
	var image := root.get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("failed to save crop gallery: %s" % error_string(error))
		quit(1)
		return
	print("CAPTURE: %s (%dx%d)" % [output_path, image.get_width(), image.get_height()])
