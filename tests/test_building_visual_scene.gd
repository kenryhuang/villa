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
			"ConstructionFeedback",
			"ConstructionFeedback/HammerPivot",
			"ConstructionFeedback/Progress",
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
			var feedback := building.get_node("ConstructionFeedback") as ConstructionFeedback
			var hammer := feedback.get_node("HammerPivot") as Node3D
			var hammer_sprite := hammer.get_node("HammerSprite") as Sprite3D
			var progress := feedback.get_node("Progress") as Sprite3D
			if not feedback.visible:
				push_error("frame construction demo must show strike feedback")
				instance.free()
				quit(1)
				return
			var hammer_height := clampf(
				minf(building.data.visual_size.x, building.data.visual_size.y) * 0.32,
				0.38,
				0.72
			)
			if not hammer.position.is_equal_approx(Vector3.ZERO):
				push_error("construction hammer pivot must stay at its configured foundation anchor")
				instance.free()
				quit(1)
				return
			var hammer_material := hammer_sprite.material_override as ShaderMaterial
			if hammer_material == null or hammer_material.shader == null:
				push_error("construction hammer must use its screen-space offset shader material")
				instance.free()
				quit(1)
				return
			var screen_offset: Vector2 = hammer_material.get_shader_parameter("screen_offset")
			var expected_lever := hammer_height * 0.72
			var expected_head_from_pivot := Vector2(
				-sin(ConstructionFeedback.IMPACT_ANGLE) * expected_lever,
				cos(ConstructionFeedback.IMPACT_ANGLE) * expected_lever
			)
			var expected_screen_offset := (
				Vector2(
					building.data.visual_size.x * 0.34,
					building.data.visual_size.y * 0.10
				)
				- expected_head_from_pivot
			)
			if (
				not screen_offset.is_equal_approx(expected_screen_offset)
				or screen_offset.x <= building.data.visual_size.x * 0.30
				or screen_offset.y <= 0.0
			):
				push_error("construction hammer screen offset must back-solve its impact head contact")
				instance.free()
				quit(1)
				return
			if not is_equal_approx(
				hammer_sprite.extra_cull_margin,
				expected_screen_offset.length() + hammer_height
			):
				push_error("construction hammer cull margin must cover its screen offset and height")
				instance.free()
				quit(1)
				return
			if progress.position.x <= 0.0 or progress.position.y < building.data.visual_size.y:
				push_error("construction progress must sit at the building upper-right")
				instance.free()
				quit(1)
				return
			var progress_material := progress.material_override as ShaderMaterial
			if progress_material == null or not is_equal_approx(
				float(progress_material.get_shader_parameter("progress")),
				building.get_construction_progress()
			):
				push_error("construction progress disk must show total elapsed progress")
				instance.free()
				quit(1)
				return
			feedback.visible = false
			if bool(instance.call("_construction_contract_passes")):
				push_error("building visual contract must reject hidden construction feedback")
				instance.free()
				quit(1)
				return
			feedback.visible = true
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
