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
	if not constants.has("CONSTRUCTION_DEMO_ORIGIN"):
		push_error("building visual verifier must expose construction demo origin")
		instance.free()
		quit(1)
		return
	for method_name in ["_advance_active_construction", "_construction_contract_passes"]:
		if not instance.has_method(method_name):
			push_error("building visual verifier missing method: %s" % method_name)
			instance.free()
			quit(1)
			return
	root.add_child(instance)
	await process_frame
	var building_system := instance.get_node("BuildingSystem") as BuildingSystem
	if building_system.get_building_count() != 10:
		push_error("building visual verifier must place nine gallery buildings plus one construction demo")
		instance.free()
		quit(1)
		return
	var completed_count := 0
	var frame_count := 0
	for building in building_system.get_all_buildings():
		if not building is BuildingInstance:
			push_error("gallery entry is not a BuildingInstance")
			instance.free()
			quit(1)
			return
		for required_path in [
			"VisualRoot/BackLayer",
			"VisualRoot/FrontLayer",
			"VisualRoot/ConstructionLayer",
			"VisualRoot/ConstructionHammer",
			"Collision",
			"InteractionArea",
			"CameraOccluder",
		]:
			if not building.has_node(required_path):
				push_error("%s missing %s" % [building.building_id, required_path])
				instance.free()
				quit(1)
				return
		if building.construction_stage == BuildingInstance.ConstructionStage.COMPLETE:
			completed_count += 1
		elif building.construction_stage == BuildingInstance.ConstructionStage.FRAME:
			frame_count += 1
			var construction_layer := building.get_node("VisualRoot/ConstructionLayer") as Sprite3D
			var collision := building.get_node("Collision") as StaticBody3D
			var interaction := building.get_node("InteractionArea") as Area3D
			if construction_layer.texture == null or not construction_layer.visible:
				push_error("frame construction demo must show dedicated stage art")
				instance.free()
				quit(1)
				return
			if collision.collision_layer == 0 or interaction.collision_layer != 0:
				push_error("frame construction demo must block movement and disable interaction")
				instance.free()
				quit(1)
				return
			var hammer := building.get_node("VisualRoot/ConstructionHammer") as Node3D
			if not hammer.visible:
				push_error("frame construction demo must show swinging hammer")
				instance.free()
				quit(1)
				return
			hammer.visible = false
			if bool(instance.call("_construction_contract_passes")):
				push_error("building visual contract must reject a hidden construction hammer")
				instance.free()
				quit(1)
				return
			hammer.visible = true
	if completed_count != 9 or frame_count != 1:
		push_error("building visual verifier must expose nine complete buildings and one frame construction")
		instance.free()
		quit(1)
		return
	if not bool(instance.call("_construction_contract_passes")):
		push_error("building visual construction contract failed")
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
