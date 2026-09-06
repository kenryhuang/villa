extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(40).timeout.connect(func(): push_error("Barn tests timed out"); quit(1))
	_run.call_deferred()

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func _frames(count: int) -> void:
	for index in count:
		await physics_frame
	await process_frame

func _check_art(barn: BuildingInstance) -> void:
	_check(barn.has_node("VisualRoot/Model"),"Barn has an imported Blender model")
	for sprite in barn.get_node("VisualRoot").find_children("*","Sprite3D",true,false):
		_check(not sprite.is_visible_in_tree(),"Legacy building sprites remain hidden")
	for mesh: MeshInstance3D in barn.get_node("VisualRoot/Model").find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			_check(material != null and material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED,"Native building surfaces never billboard")

func _run() -> void:
	var farm := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	farm.set_process(false)
	farm.get_node("FarmInteraction").set_process(false)
	var session: Farm3DSession = farm.get_node("FarmSession")
	var player: Farm3DPlayer = farm.get_node("Player")
	player.set_physics_process(false)
	session.season.set_process(false)
	var cell := session.grid.get_cell(32,31)
	player.position = cell.world_position_3d()+Vector3.LEFT*1.2
	var original := BuildingData.from_dictionary(load("res://scripts/core/game_data.gd").get_building("barn"))
	var resolved := session.buildings._resolve_data(original)
	_check(original.scene_path == "res://scenes/buildings/barn.tscn","Shared catalogue retains the original game's scene")
	_check(resolved.scene_path == "res://scenes/farm3d/buildings/barn.tscn","3D building resolver selects the modeled barn")
	_check(resolved.footprint == Vector2i(2,2) and resolved.cost == original.cost,"Original footprint and construction cost are preserved")
	_check(session.buildings.enter_preview_mode("barn"),"Barn placement preview opens")
	_check(session.buildings.update_preview_grid(32,31),"Barn preview accepts a valid ground target")
	var preview: BuildingInstance = session.buildings._visual_proxy.get_child(0)
	_check_art(preview)
	_check(preview.get_node("Collision").collision_layer == 0 and preview.get_node("ModelCameraCollision").collision_layer == 0,"Ghost preview has no player or camera collision")
	var mesh: MeshInstance3D = preview.get_node("VisualRoot/Model/Frame").get_child(0)
	var preview_material := mesh.get_active_material(0) as StandardMaterial3D
	var valid_tint := preview_material.albedo_color
	preview.set_preview_valid(false)
	_check(preview_material.albedo_color != valid_tint,"Invalid placement changes native model tint")
	session.buildings.exit_preview_mode()
	var before := session.inventory.get_item_count("plank")
	var placed := session.buildings.try_place_building("barn",32,31)
	_check(placed.placed,"Actual menu building system places the modeled barn")
	if not placed.placed:
		quit(1)
		return
	var barn: BuildingInstance = placed.instance
	barn.set_process(false)
	_check(session.inventory.get_item_count("plank") == before-8,"Placement pays the original eight planks")
	var model: Node3D = barn.get_node("VisualRoot/Model")
	for stage in 4:
		barn.restore_construction(stage,stage*3.0)
		_check_art(barn)
		_check(model.get_node("Foundation").visible,"Every construction stage rests on the stone foundation")
		_check(model.get_node("Frame").visible == (stage >= 1),"Timber frame appears at the frame stage")
		_check(model.get_node("Walls").visible == (stage >= 2),"Cedar walls appear at the half-built stage")
		_check(model.get_node("Roof").visible == (stage == 3),"Slate roof appears on completion")
		_check(model.get_node("Details").visible == (stage == 3),"Doors and fittings appear on completion")
	var bounds := AABB()
	var initialized := false
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		var local: Transform3D = model.global_transform.affine_inverse()*part.global_transform
		var box := local*part.get_aabb()
		bounds = bounds.merge(box) if initialized else box
		initialized = true
	_check(bounds.size.x > 2 and bounds.size.z > 2 and bounds.size.y > 3,"Barn has genuine width, depth and roof height")
	_check(bounds.position.y < 0 and bounds.position.y > -.3,"Foundation slightly penetrates the ground rather than floating")
	_check(bounds.size.x < 2.6 and bounds.size.z < 2.6,"Roof overhang remains close to the original two-metre footprint")
	var model_transform := model.global_transform
	var camera: Camera3D = farm.get_node("OverviewCamera")
	for offset in [Vector3(4,2,5),Vector3(-4,2,-5),Vector3(5,.3,-4)]:
		camera.position = barn.position+offset
		camera.look_at(barn.position+Vector3.UP)
		camera.current = true
		await _frames(2)
		_check(model.global_transform.is_equal_approx(model_transform),"Orbiting the camera leaves the barn's transform unchanged")
	var space: PhysicsDirectSpaceState3D = farm.get_world_3d().direct_space_state
	var center := barn.position+Vector3.UP
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(center+Vector3.FORWARD*3,center,16))
	_check(hit.get("collider") == barn.get_node("Collision"),"Barn walls block the player")
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(center+Vector3.BACK*4,center,32))
	_check(hit.get("collider") == barn.get_node("ModelCameraCollision"),"Native camera collision prevents entering the building")
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(barn.position+Vector3.UP*5,barn.position,16))
	_check(not hit.is_empty() and hit.position.y-barn.position.y > 3,"Roof collision follows the model's ridge")
	_check(barn.economy_effect_type() == "farm_storage" and barn.data.effect_value == 200,"Barn retains its storage effect")
	# Construction record has the original schema: older saves need no migration.
	barn.restore_construction(BuildingInstance.ConstructionStage.FRAME,3.5)
	session.save_path = "user://barn_3d_integration_test.json"
	_check(session.save_game(),"Modeled barn saves with shared building records")
	_check(session.load_game(),"Existing building records restore through the 3D scene resolver")
	barn = session.buildings.get_building_at(32,31)
	barn.set_process(false)
	_check(barn.scene_file_path == resolved.scene_path and barn.construction_stage == BuildingInstance.ConstructionStage.FRAME,"Restored in-progress barn uses the model and correct stage")
	barn.advance_construction(100)
	_check(barn.is_construction_complete() and barn.get_node("VisualRoot/Model/Roof").visible,"Restored construction completes into the full Blender model")
	_check(session.save_game() and session.load_game(),"Completed modeled barn saves and reloads")
	barn = session.buildings.get_building_at(32,31)
	_check_art(barn)
	barn.deactivate()
	_check(barn.get_node("ModelCameraCollision").collision_layer == 0,"Removed barn releases its additional camera collision")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(session.save_path))
	farm.queue_free()
	await process_frame
	print("3D BARN: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
