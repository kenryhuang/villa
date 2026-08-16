extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := "res://tests/visual/farming_system_verification.tscn"
	if not ResourceLoader.exists(path):
		push_error("missing farming visual verification scene")
		quit(1)
		return
	var scene := load(path) as PackedScene
	var instance := scene.instantiate()
	if instance.get_script() == null:
		push_error("farming visual verification root script failed to load")
		instance.free()
		quit(1)
		return
	for node_path in [
		"World",
		"GridSystem",
		"FarmingSystem",
		"SeasonSystem",
		"FarmPlotOverlay",
		"Camera3D",
		"DirectionalLight3D",
		"UI/StatusPanel/StatusLabel",
		"UI/CropInspector/InspectorLabel",
		"UI/Instructions",
	]:
		if not instance.has_node(node_path):
			push_error("farming visual scene missing node: %s" % node_path)
			instance.free()
			quit(1)
			return
	var constants: Dictionary = instance.get_script().get_script_constant_map()
	if not constants.has("PLOT_COORDS") or constants.PLOT_COORDS.size() != 12:
		push_error("farming visual verifier must contain twelve crop plots")
		instance.free()
		quit(1)
		return
	if not constants.has("STAGE_NAMES") or constants.STAGE_NAMES.size() != 4:
		push_error("farming visual verifier must label four growth stages")
		instance.free()
		quit(1)
		return
	root.add_child(instance)
	await process_frame
	var cells: Array = instance.get("_cells")
	var farming_system := instance.get_node("FarmingSystem") as FarmingSystem
	for index in cells.size():
		var crop: CropInstance = cells[index].crop_instance
		var expected_state := (
			CropInstance.LifecycleState.MATURE
			if index % constants.STAGE_NAMES.size() == constants.STAGE_NAMES.size() - 1
			else CropInstance.LifecycleState.GROWING
		)
		if crop == null or crop.lifecycle_state != expected_state:
			push_error("growth stage %d has non-canonical lifecycle state" % (index % constants.STAGE_NAMES.size()))
			instance.free()
			quit(1)
			return
	for stage in constants.STAGE_NAMES.size():
		var variants := {}
		for index in range(stage, cells.size(), constants.STAGE_NAMES.size()):
			var visual := farming_system.get_crop_visual(cells[index])
			if visual and visual.has_method("get_variant_index"):
				variants[visual.call("get_variant_index")] = true
		if variants.size() != 3:
			push_error("growth stage %d must display three visual variants" % stage)
			instance.free()
			quit(1)
			return
	instance.free()
	print("PASS: farming visual verification scene contract")
	quit(0)
