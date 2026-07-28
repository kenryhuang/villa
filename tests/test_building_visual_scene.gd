extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := "res://tests/visual/building_system_verification.tscn"
	if not ResourceLoader.exists(path):
		push_error("missing building visual verification scene")
		quit(1)
		return
	var scene := load(path) as PackedScene
	var instance := scene.instantiate()
	if instance.get_script() == null:
		push_error("building visual verification root script failed to load")
		instance.free()
		quit(1)
		return
	for node_path in [
		"World",
		"GridSystem",
		"BuildingSystem",
		"GalleryLabels",
		"Camera3D",
		"DirectionalLight3D",
		"UI/StatusPanel/StatusLabel",
		"UI/BuildingInspector/InspectorLabel",
		"UI/Instructions",
	]:
		if not instance.has_node(node_path):
			push_error("building visual scene missing node: %s" % node_path)
			instance.free()
			quit(1)
			return
	var constants: Dictionary = instance.get_script().get_script_constant_map()
	if not constants.has("BUILDING_IDS") or constants.BUILDING_IDS.size() != 9:
		push_error("building visual verifier must expose nine building IDs")
		instance.free()
		quit(1)
		return
	if not constants.has("GALLERY_ORIGINS") or constants.GALLERY_ORIGINS.size() != 9:
		push_error("building visual verifier must expose nine gallery origins")
		instance.free()
		quit(1)
		return
	root.add_child(instance)
	await process_frame
	var building_system := instance.get_node("BuildingSystem") as BuildingSystem
	if building_system.get_building_count() != 9:
		push_error("building visual verifier must place all nine buildings")
		instance.free()
		quit(1)
		return
	for building in building_system.get_all_buildings():
		if not building is BuildingInstance:
			push_error("gallery entry is not a BuildingInstance")
			instance.free()
			quit(1)
			return
		for required_path in ["VisualRoot/BackLayer", "VisualRoot/FrontLayer", "Collision", "InteractionArea", "CameraOccluder"]:
			if not building.has_node(required_path):
				push_error("%s missing %s" % [building.building_id, required_path])
				instance.free()
				quit(1)
				return
	if not bool(instance.call("verification_contract_passes")):
		push_error("building visual verification status contract failed")
		instance.free()
		quit(1)
		return
	instance.free()
	print("PASS: building visual verification scene contract")
	quit(0)

