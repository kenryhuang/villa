extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(120, true, false, true).timeout.connect(func(): push_error("Yun NPC test timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func clip(actor: Node) -> String:
	return String(actor.character_animation.current_animation).get_file().to_lower()

func run() -> void:
	if "--living-world-scenario=P12" not in OS.get_cmdline_user_args():
		push_error("Use --farm-test --living-world-scenario=P12 for isolated Yun tests"); quit(1); return
	var farm: Node3D = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var session: Farm3DSession = farm.get_node("FarmSession")
	var runtime: Node = session.agent_runtime
	session.save_path = "res://tmp/sintel-yun-test-save.json"
	session.season.set_process(false); session.living_world.set_process(false); session.player.set_physics_process(false)
	check(not runtime.service_enabled, "Isolated test cannot call live Agent service")
	check(runtime.farm3d_actors.has("resident_yun"), "Existing focus resident has a physical actor")
	var actor: Node3D = runtime.farm3d_actors.resident_yun
	check(actor.villager_id == "resident_yun" and actor.nameplate.text == "云姐", "Cook keeps her original name and agent identity")
	check(actor.character_model != null and not actor.npc_visual.visible and not actor.placeholder_mesh.visible, "Sintel replaces the fallback male sprite")
	if actor.character_model == null: farm.queue_free(); quit(1); return
	var skeleton: Skeleton3D = actor.character_model.find_children("*", "Skeleton3D", true, false)[0]
	check(skeleton.get_bone_count() == 55, "Game rig contains only 55 deform bones")
	for bone in ["root", "pelvis", "spine", "head", "upper_arm.L", "forearm.R", "hand.L", "finger_index.02.R", "thigh.L", "shin.R"]:
		check(skeleton.find_bone(bone) >= 0, "Deform bone preserved: " + bone)
	var shapes := 0
	var textured := 0
	var triangles := 0
	for mesh: MeshInstance3D in actor.character_model.find_children("*", "MeshInstance3D", true, false):
		check(mesh.skin != null, mesh.name + " is skinned")
		shapes += mesh.mesh.get_blend_shape_count()
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(surface) as BaseMaterial3D
			check(mat != null, mesh.name + " has a supported Godot material")
			if mat != null and mat.albedo_texture != null: textured += 1
			var arrays := mesh.mesh.surface_get_arrays(surface)
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
	check(textured >= 7 and triangles < 85000, "Embedded albedo maps and bounded game geometry import")
	check(shapes == 6, "Selected facial expressions survive glTF import")
	var animator: AnimationPlayer = actor.character_animation
	for name in ["idle", "walk", "run", "work"]:
		check(Array(animator.get_animation_list()).any(func(value): return String(value).get_file().to_lower() == name), "Authored clip imported: " + name)
	actor.velocity = Vector3(0,0,2); actor._sync_visual_motion()
	check(clip(actor) == "walk", "Normal movement uses Walk")
	# Sample the authored clip without the normal 0.16 s transition from Idle.
	animator.play(animator.current_animation, 0)
	animator.seek(0, true)
	var thigh := skeleton.find_bone("thigh.L")
	var pose := skeleton.get_bone_pose_rotation(thigh)
	animator.seek(.25, true)
	check(pose.angle_to(skeleton.get_bone_pose_rotation(thigh)) > .1, "Walk changes the actual leg pose")
	actor.velocity = Vector3(0,0,4); actor._sync_visual_motion()
	check(clip(actor) == "run", "Faster movement uses authored Run")
	actor.velocity = Vector3.ZERO; actor.farm_action_visual.play("harvest"); actor._sync_visual_motion()
	check(clip(actor) == "work", "Work action uses the hand-working clip")
	actor.farm_action_visual.cancel(); actor._sync_visual_motion()
	check(clip(actor) == "idle", "Finished action returns to Idle")
	var start := actor.position
	var destination := start
	for offset in [Vector3(3,0,0), Vector3(0,0,3), Vector3(-3,0,0), Vector3(0,0,-3)]:
		if not session.living_world.work.paths.find_path_cells(session.grid.world_to_grid(start.x,start.z),session.grid.world_to_grid(start.x+offset.x,start.z+offset.z)).is_empty():
			destination=start+offset; break
	var intent := {"agent_id":"resident_yun", "decision_id":"yun-walk", "action_id":"yun-walk", "idempotency_key":"yun-walk", "tool_name":"move", "arguments":{"x":destination.x,"z":destination.z}}
	check(runtime.executor.execute(intent,0).status == "in_progress", "Existing Agent move starts a real trip")
	for frame in 600:
		await physics_frame
		runtime.executor.complete_due(1)
		if runtime.executor._outcomes["yun-walk"].status != "in_progress":break
	check(actor.position.distance_to(start)>1 and runtime.executor._outcomes["yun-walk"].status == "completed", "Female NPC physically walks to the destination")
	var inventory_before: Dictionary = session.npc_economy.get_npc_state("resident_yun").to_dict()
	check(session.save_game() and session.load_game(), "Existing save restores the new visual")
	actor=runtime.farm3d_actors.resident_yun
	check(actor.character_model != null and session.npc_economy.get_npc_state("resident_yun").to_dict() == inventory_before, "Reload keeps identity, resources and female model")
	var hud: Node = farm.get_node("FarmInteraction").hud
	session.player.position=actor.position+Vector3(0,0,1.5)
	hud.dialogue_ui.open_agent_dialogue(actor.villager_id, "云姐")
	check(hud.dialogue_ui.visible and paused and actor.is_player_in_dialogue_range(), "Existing dialogue opens for Yun and pauses walking")
	hud.dialogue_ui.close_button.pressed.emit()
	check(not paused and not hud.dialogue_ui.visible, "Closing dialogue resumes the game")
	if "--capture-yun" in OS.get_cmdline_user_args():await capture(farm,actor)
	print("SINTEL NPC: %d checks, %d failures" % [checks,failures])
	farm.queue_free(); await process_frame; quit(0 if failures==0 else 1)

func capture(farm: Node3D, actor: Node3D) -> void:
	for layer: CanvasLayer in farm.find_children("*", "CanvasLayer", true, false):layer.hide()
	for other in farm.farm_session.agent_runtime.farm3d_actors.values():other.set_physics_process(false)
	actor.position=Vector3(-5,0,4); actor.position.y=Farm3DTerrainProfile.surface_height(-5,4)
	actor.rotation=Vector3.ZERO
	farm.farm_session.player.position=Vector3(-8,0,4)
	var camera := Camera3D.new(); farm.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.9
	camera.position=actor.position+Vector3(.9,1.6,4);camera.look_at(actor.position+Vector3(0,1,0));camera.make_current()
	DirAccess.make_dir_recursive_absolute("res://tmp/sintel-yun")
	actor.character_animation.set_process(false)
	for view in ["front","back","walk","work"]:
		actor.rotation.y=PI if view=="back" else 0
		var desired: String = "idle" if view in ["front","back"] else view
		for name in actor.character_animation.get_animation_list():
			if String(name).get_file().to_lower()==desired:actor.character_animation.play(name);actor.character_animation.seek(.24,true)
		for frame in 4:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/sintel-yun/game-"+view+".png")
