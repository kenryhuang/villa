extends SceneTree


func _init() -> void:
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
	instance.free()
	print("PASS: farming visual verification scene contract")
	quit(0)
