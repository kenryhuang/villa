extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("Character tests timed out"); quit(1))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func validate_model(model: Node3D, label: String) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	check(skeletons.size() == 1, label + " has a real skinned skeleton")
	if skeletons.is_empty(): return
	var skeleton := skeletons[0] as Skeleton3D
	for bone in ["root", "pelvis", "spine", "head", "upper_arm.L", "upper_arm.R", "forearm.L", "forearm.R", "thigh.L", "thigh.R", "shin.L", "shin.R"]:
		check(skeleton.find_bone(bone) >= 0, label + " retains gameplay bone " + bone)
	check(skeleton.get_bone_count() == 55, label + " uses Yun's full deform rig including wrists and fingers")
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() == 2, label + " separates expressive face from joined clothing")
	var shapes := 0
	var triangles := 0
	var textured := 0
	var surfaces := 0
	for mesh_node: MeshInstance3D in meshes:
		check(mesh_node.skin != null, label + " mesh is skinned")
		shapes += mesh_node.mesh.get_blend_shape_count()
		for surface in mesh_node.mesh.get_surface_count():
			surfaces += 1
			var material := mesh_node.get_active_material(surface) as BaseMaterial3D
			check(material != null, label + " uses an imported game material")
			if material != null and material.albedo_texture != null:
				textured += 1
				check(material.albedo_texture.get_width() >= 512, label + " retains detailed painted textures")
			var arrays := mesh_node.mesh.surface_get_arrays(surface)
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
			check(arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size(), label + " preserves garment and facial UVs")
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var valid := true
			for vertex in arrays[Mesh.ARRAY_VERTEX].size():
				var total := 0.0
				for index in 4: total += weights[vertex * 4 + index]
				# Imported weights are quantized to 16 bits by Godot.
				if absf(total - 1.0) > .0001: valid = false; break
			check(valid, label + " has no unweighted or partially weighted garment vertices")
	check(shapes == 6, label + " retains Yun-style facial expression topology")
	check(textured >= 6 and surfaces <= 8, label + " shares skin, fabric and leather maps with bounded draw calls")
	check(triangles < 120000, label + " stays within the detailed character geometry budget")
	var players := model.find_children("*", "AnimationPlayer", true, false)
	check(players.size() == 1, label + " has an animation player")
	if players.is_empty(): return
	var animator := players[0] as AnimationPlayer
	for expected in ["idle", "walk", "run", "work"]:
		var found := false
		for clip in animator.get_animation_list():
			if String(clip).get_file().to_lower() == expected:
				found = true
				var duration := 3.0 if expected == "idle" else .8 if expected == "run" else 1.2 if label == "player" and expected == "walk" else 1.0
				check(is_equal_approx(animator.get_animation(clip).length, duration), label + " clip has authored timing: " + expected)
		check(found, label + " has " + expected)
	for clip in animator.get_animation_list():
		if String(clip).get_file().to_lower() != "walk": continue
		animator.play(clip)
		animator.advance(0.0)
		var thigh := skeleton.find_bone("thigh.L")
		var rest_pose := skeleton.get_bone_pose_rotation(thigh)
		var max_swing := 0.0
		for quarter in 4:
			animator.advance(0.25)
			max_swing = maxf(max_swing, rest_pose.angle_to(skeleton.get_bone_pose_rotation(thigh)))
		check(max_swing > 0.1, label + " walking actually deforms the leg skeleton through the cycle")

func clip_name(animator: AnimationPlayer) -> String:
	return String(animator.current_animation).get_file().to_lower()

func _run() -> void:
	root.size = Vector2i(1600, 960)
	var farm := load("res://scenes/farm3d/main.tscn").instantiate() as Node3D
	root.add_child(farm)
	farm.set_process(false)
	var session: Farm3DSession = farm.get_node("FarmSession")
	session.season.set_process(false)
	var player: Farm3DPlayer = session.player
	player.set_physics_process(false)
	validate_model(player.get_node("FarmerModel"), "player")
	player.begin_farm_action(player.global_position + Vector3.FORWARD)
	check(clip_name(player._animation_player) == "work" and player._animation_player.speed_scale == 2.0, "Player farm action performs a complete half-second work swing")
	player._animation_player.advance(0.12)
	player.begin_farm_action(player.global_position + Vector3.FORWARD)
	check(is_zero_approx(player._animation_player.current_animation_position), "A consecutive farm action restarts its work gesture")
	player.cancel_farm_action()
	check(clip_name(player._animation_player) == "idle", "Cancelling work returns player to idle")
	Input.action_press("sprint")
	player.play_motion_animation(true)
	check(clip_name(player._animation_player) == "run" and is_equal_approx(player._animation_player.speed_scale, player.walk_speed * player.SPRINT_MULTIPLIER / player.RUN_REFERENCE_SPEED), "Sprint cadence matches the authored running stride distance")
	Input.action_release("sprint")
	player.set_dialogue_input_blocked(true)
	check(clip_name(player._animation_player) == "idle", "Dialogue clears active locomotion")
	player.set_dialogue_input_blocked(false)
	var actors: Array[Node3D] = [player]
	for id in ["farmer_ahe", "lao_li", "xuezhe_lin"]:
		var actor: Node3D = session.agent_runtime.farm3d_actors[id]
		actor.set_physics_process(false)
		actors.append(actor)
		check(actor.character_model != null, id + " uses its Blender model in the formal scene")
		if actor.character_model == null: continue
		validate_model(actor.character_model, id)
		check(not actor.npc_visual.visible and not actor.placeholder_mesh.visible, id + " replaces old billboard and capsule")
		check(actor.nameplate.position.y > 2.0 and actor.dialogue_prompt.position.y > actor.nameplate.position.y, id + " labels clear the model")
		actor.velocity = Vector3(0, 0, 2)
		actor._sync_visual_motion()
		check(clip_name(actor.character_animation) == "walk", id + " walking drives animation")
		actor.velocity = Vector3.ZERO
		actor.farm_action_visual.play("harvest")
		actor._sync_visual_motion()
		check(clip_name(actor.character_animation) == "work", id + " farm action drives work animation")
		actor.farm_action_visual.cancel()
		actor._sync_visual_motion()
		check(clip_name(actor.character_animation) == "idle", id + " completed work returns to idle")
	validate_tool_poses(farm, player)
	# Original scene still uses its existing directional sprite when not in 3D.
	var legacy: Node3D = load("res://scenes/actors/npc.tscn").instantiate()
	root.add_child(legacy)
	legacy.configure_agent(player, "farmer_ahe", "阿禾")
	check(legacy.configure_agent_visual(load("res://assets/characters/npcs/farmer_ahe/farmer_ahe_directions.png")), "Original scene atlas configuration still works")
	check(legacy.character_model == null and legacy.npc_visual.visible, "Original game retains sprite visual")
	legacy.queue_free()
	if "--capture-characters" in OS.get_cmdline_user_args():
		if session.agent_runtime.farm3d_actors.has("resident_yun"):
			var yun: Node3D = session.agent_runtime.farm3d_actors["resident_yun"]
			yun.set_physics_process(false)
			actors.append(yun)
		await capture(farm, actors)
	print("3D character tests: %d checks, %d failures" % [checks, failures.size()])
	farm.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func palm_position(skeleton: Skeleton3D, side: String) -> Vector3:
	return skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("hand." + side)) * Vector3(0, .05, 0))

func validate_tool_poses(farm: Node3D, player: Farm3DPlayer) -> void:
	var skeleton: Skeleton3D = player.find_children("*", "Skeleton3D", true, false)[0]
	var golf := preload("res://scripts/farm3d/golf_visual.gd").new()
	farm.add_child(golf)
	golf.configure(player)
	player.golf_locked = true
	golf.set_equipped(true)
	golf.set_contact(player.to_global(Vector3(0, .065, .8)), Vector3.FORWARD, 0)
	for left_handed in [false, true]:
		golf.left_handed = left_handed
		for angle in [0.0, -.8, .8]:
			golf.pose(angle, 0)
			var leading := "L" if left_handed else "R"
			var grip := Vector3(-.09 if left_handed else .09, 1.20 + absf(angle) * .08, .28)
			check(palm_position(skeleton, leading).distance_to(player.to_global(grip)) < .035, "Golf palm stays on the grip through both handed swings")
			var pose := skeleton.get_bone_pose_rotation(skeleton.find_bone("finger_index.02." + leading))
			for frame in 20: golf.pose(angle, 0)
			check(pose.is_equal_approx(skeleton.get_bone_pose_rotation(skeleton.find_bone("finger_index.02." + leading))), "Repeated tool poses do not accumulate finger rotations")
	golf.set_equipped(false)
	player.golf_locked = false
	golf.queue_free()
	var fishing := preload("res://scripts/farm3d/fishing_visual.gd").new()
	farm.add_child(fishing)
	fishing.configure(player)
	player.fishing_locked = true
	fishing.set_equipped(true)
	for state in ["READY", "CASTING", "BITE", "REELING", "LANDING"]:
		fishing.update_pose(state, .6, 1.2, player.global_position + Vector3(0, 0, 3), "carp")
		check(palm_position(skeleton, "R").distance_to(fishing.rod.global_position) < .035, "Fishing palm holds the rod while " + state)
	fishing.set_equipped(false)
	player.fishing_locked = false
	fishing.queue_free()
	player.play_motion_animation(false)

func capture(farm: Node3D, actors: Array[Node3D]) -> void:
	for layer: CanvasLayer in farm.find_children("*", "CanvasLayer", true, false):
		layer.hide()
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.0 if actors.size() == 5 else 10.0
	camera.global_position = Vector3(3.2, 4.2, 16)
	camera.look_at(Vector3(0, 1.0, 4))
	camera.make_current()
	for i in actors.size():
		var actor := actors[i]
		actor.global_position = Vector3(-4.4 + i * 2.2 if actors.size() == 5 else -3.6 + i * 2.4, 0, 4)
		actor.global_position.y = Farm3DTerrainProfile.surface_height(actor.position.x, actor.position.z)
		actor.rotation = Vector3.ZERO
		if actor.has_method("set_dialogue_busy"): actor.set_dialogue_busy(true)
	DirAccess.make_dir_recursive_absolute("res://docs/validation/character-rebuild")
	for view in ["front", "back", "motion", "work"]:
		for actor in actors:
			actor.rotation.y = PI if view == "back" else 0.0
			if view == "motion":
				if actor is Farm3DPlayer:
					actor.play_motion_animation(true)
				else:
					actor.velocity = Vector3(0, 0, 2)
					actor._sync_visual_motion()
		for frame in 16: await process_frame
		if view == "motion":
			for actor in actors:
				var animator: AnimationPlayer = actor._animation_player if actor is Farm3DPlayer else actor.character_animation
				animator.seek(0.25, true)
				animator.pause()
			await process_frame
		if view == "work":
			for actor in actors:
				var animator: AnimationPlayer = actor._animation_player if actor is Farm3DPlayer else actor.character_animation
				for clip in animator.get_animation_list():
					if String(clip).get_file().to_lower() == "work": animator.play(clip)
				animator.seek(0.5, true)
				animator.pause()
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/validation/character-rebuild/in-game-%s.png" % view)
	for i in actors.size():
		var actor := actors[i]
		var animator: AnimationPlayer = actor._animation_player if actor is Farm3DPlayer else actor.character_animation
		for clip in animator.get_animation_list():
			if String(clip).get_file().to_lower() == "idle": animator.play(clip)
		animator.seek(0.0, true)
		animator.pause()
		camera.size = 2.3
		camera.global_position = actor.global_position + Vector3(1.0, 1.8, 5.0)
		camera.look_at(actor.global_position + Vector3.UP * 1.1)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/validation/character-rebuild/in-game-portrait-%d.png" % i)
		if i == 0:
			camera.size = .58
			camera.global_position = actor.global_position + Vector3(.20, 1.76, 3.0)
			camera.look_at(actor.global_position + Vector3.UP * 1.69)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/validation/character-rebuild/player-face.png")
	for i in range(1, actors.size()): actors[i].hide()
	var player := actors[0] as Farm3DPlayer
	camera.size = 4.0
	camera.global_position = player.global_position + Vector3(3, 2.3, 4.8)
	camera.look_at(player.global_position + Vector3.UP * 1.0)
	var golf := preload("res://scripts/farm3d/golf_visual.gd").new()
	farm.add_child(golf)
	golf.configure(player)
	player.golf_locked = true
	golf.set_equipped(true)
	var ball := player.to_global(Vector3(0, 0.065, 0.8))
	golf.set_contact(ball, Vector3.FORWARD, 0)
	golf.update_ball(ball, false, false)
	for handed in [false, true]:
		golf.left_handed = handed
		golf.pose(0, 0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/validation/character-rebuild/in-game-golf-%s.png" % ("left" if handed else "right"))
	golf.set_equipped(false)
	golf.hide()
	player.golf_locked = false
	var fishing := preload("res://scripts/farm3d/fishing_visual.gd").new()
	farm.add_child(fishing)
	fishing.configure(player)
	player.fishing_locked = true
	fishing.set_equipped(true)
	fishing.update_pose("REELING", 0.7, 1.6, player.global_position + Vector3(0, 0, 3), "carp")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/validation/character-rebuild/in-game-fishing.png")
