extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func bone_point(skeleton: Skeleton3D, name: String) -> Vector3:
	return skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin

func run() -> void:
	var model := load("res://assets/models/farm3d/player_farmer.glb").instantiate() as Node3D
	root.add_child(model)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var animator: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	animator.stop()
	skeleton.reset_bone_poses()
	var bounds := AABB()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		bounds = bounds.merge(mesh.get_aabb())
	var hip_height := skeleton.get_bone_global_rest(skeleton.find_bone("thigh.L")).origin.y
	var waist_height := skeleton.get_bone_global_rest(skeleton.find_bone("spine")).origin.y
	var rest_chest_forward := (bone_point(skeleton,"chest")-(bone_point(skeleton,"thigh.L")+bone_point(skeleton,"thigh.R"))*.5).z
	check(hip_height / bounds.size.y >= .43 and hip_height / bounds.size.y <= .51, "Hip height follows the concept instead of the previous long-legged proportions")
	check(waist_height / bounds.size.y >= .51 and waist_height / bounds.size.y <= .57, "Waist leaves enough length for the torso")
	print("Player proportions: height=%.3f hip=%.3f waist=%.3f" % [bounds.size.y, hip_height, waist_height])
	var sole_vertices := 0
	var soles_bound_to_feet := true
	var sole_points := {"L": [], "R": []}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(surface)
			if not "boot" in mat.resource_name.to_lower(): continue
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for index in vertices.size():
				if vertices[index].y > .10: continue
				sole_vertices += 1
				var foot_weight := 0.0
				for influence in 4:
					var bind := joints[index*4+influence]
					var bone_name := String(mesh.skin.get_bind_name(bind))
					if bone_name.begins_with("foot."): foot_weight += weights[index*4+influence]
					if bone_name.begins_with("foot.") and weights[index*4+influence] > .999:
						sole_points[bone_name.get_slice(".",1)].append(vertices[index])
				if foot_weight < .999: soles_bound_to_feet = false
	check(sole_vertices > 100 and soles_bound_to_feet, "Actual sole vertices are bound to foot bones, not shins")
	for expected in ["walk", "run"]:
		for clip in animator.get_animation_list():
			if String(clip).get_file().to_lower() != expected: continue
			var duration := animator.get_animation(clip).length
			animator.play(clip)
			var max_knee_forward := 0.0
			var first_pose: Array[Vector3] = []
			var flat_support_start := Vector3.ZERO
			var min_chest_advance := INF
			var hip_yaw_span := 0.0
			var first_body: Array[Vector3] = []
			var min_pelvis := INF
			var max_pelvis := -INF
			for frame in 33:
				animator.seek(duration * frame / 32.0, true)
				skeleton.force_update_all_bone_transforms()
				if expected == "walk":
					var left := bone_point(skeleton,"thigh.L")
					var right := bone_point(skeleton,"thigh.R")
					var torso := bone_point(skeleton,"chest")
					var pelvis_y := bone_point(skeleton,"pelvis").y
					min_pelvis=minf(min_pelvis,pelvis_y)
					max_pelvis=maxf(max_pelvis,pelvis_y)
					min_chest_advance=minf(min_chest_advance,(torso-(left+right)*.5).z-rest_chest_forward)
					hip_yaw_span=maxf(hip_yaw_span,absf(left.z-right.z))
					if frame == 8:check(left.y-right.y>.005,"Left support hip rises with weight transfer")
					if frame == 24:check(right.y-left.y>.005,"Right support hip rises with weight transfer")
					if frame == 0:first_body=[left,right,torso]
					if frame == 32:
						check(left.distance_to(first_body[0])<.002 and right.distance_to(first_body[1])<.002 and torso.distance_to(first_body[2])<.002,"Pelvis and torso loop continuously together")
				for side in ["L", "R"]:
					var hip := bone_point(skeleton, "thigh." + side)
					var knee := bone_point(skeleton, "shin." + side)
					var ankle := bone_point(skeleton, "foot." + side)
					var line := ankle - hip
					var projection := hip + line * ((knee - hip).dot(line) / line.length_squared())
					# The imported player faces +Z. Knees must project forward of the hip-ankle line.
					var forward_bend := (knee - projection).z
					var phase := fposmod(frame / 32.0 + (0.0 if side == "L" else .5),1.0)
					if expected == "walk":
						check(hip.y >= hip_height-.045, "Walk keeps the pelvis within 4.5 cm of standing height")
						if is_equal_approx(phase,.25):
							var flexion := rad_to_deg((knee-hip).angle_to(ankle-knee))
							print("Midstance %s knee flexion: %.2f degrees; hip drop: %.3f m" % [side,flexion,hip_height-hip.y])
							check(flexion < 35, "Light jog permits weight acceptance without a deeply crouched support knee")
						var foot := skeleton.find_bone("foot."+side)
						var deformation := skeleton.get_bone_global_pose(foot) * skeleton.get_bone_global_rest(foot).affine_inverse()
						var ground_height := INF
						for sole: Vector3 in sole_points[side]: ground_height = minf(ground_height,(deformation*sole).y)
						check(ground_height >= -.008, "Walk shoe geometry stays above the ground")
						if phase < .4: check(ground_height < .016, "Light jog has heel, sole or toe contact throughout its support interval")
					max_knee_forward = maxf(max_knee_forward, forward_bend)
					check(forward_bend >= -.004, "%s %s frame %d: knee bends forward, never backward" % [expected, side, frame])
					check(ankle.y >= .095, "%s %s frame %d: ankle does not sink below the boot sole clearance" % [expected, side, frame])
					if frame == 0: first_pose.append(ankle)
					if frame == 32: check(ankle.distance_to(first_pose[0 if side == "L" else 1]) < .002, expected + " loops without a foot-position jump")
				var foot_index := skeleton.find_bone("foot.L")
				var rest := skeleton.get_bone_global_rest(foot_index)
				var contact := bone_point(skeleton,"foot.L")
				if expected=="run":
					# Sprint rolls over the forefoot; measure its fixed toe contact,
					# rather than the ankle which rises and rotates about that contact.
					contact=skeleton.get_bone_global_pose(foot_index)*rest.affine_inverse()*Vector3(rest.origin.x,0,rest.origin.z+.205)
				if frame == 2: flat_support_start=contact
				var support_end := 4 if expected=="walk" else 6
				if frame == support_end:
					var support_speed := absf(contact.z-flat_support_start.z)/(duration*(support_end-2)/32.0)
					print(expected+" measured contact speed: %.3f m/s"%support_speed)
					check(absf(support_speed-(Farm3DPlayer.WALK_REFERENCE_SPEED if expected=="walk" else Farm3DPlayer.RUN_REFERENCE_SPEED)) < .15, expected + " support contact travel matches the runtime cadence reference")
			check(max_knee_forward > .08, expected + " has a visible natural knee bend during swing")
			if expected == "walk":
				check(max_pelvis-min_pelvis<.035,"Light jog keeps vertical pelvis excursion below 3.5 cm to avoid exaggerated bouncing")
				print("Pelvis vertical excursion: %.3f m"%(max_pelvis-min_pelvis))
				check(min_chest_advance>.010,"Walking carries the chest forward over the pelvis instead of keeping a vertical rigid torso")
				check(hip_yaw_span>.008,"The advancing hip moves with the stride instead of remaining fixed")
				print("Body coupling: minimum chest advance %.3f m; hip forward separation %.3f m"%[min_chest_advance,hip_yaw_span])
	validate_motion_continuity(skeleton, animator)
	model.queue_free()
	await process_frame
	await validate_locomotion()
	print("Player gait tests: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func physics_steps(count: int) -> void:
	for frame in count: await physics_frame
	await process_frame

func validate_motion_continuity(skeleton: Skeleton3D, animator: AnimationPlayer) -> void:
	# Position continuity alone misses the visible hitch when velocity changes
	# abruptly at an IK clamp, a sparse keyframe or the loop boundary.
	var limits := {"pelvis": .4, "hand.L": .65, "hand.R": .65,
		"shin.L": 1.5, "shin.R": 1.5, "foot.L": 1.5, "foot.R": 1.5}
	for clip in animator.get_animation_list():
		var name := String(clip).get_file().to_lower()
		if name not in ["walk", "run"]: continue
		var duration := animator.get_animation(clip).length
		var playback := 3.0/Farm3DPlayer.WALK_REFERENCE_SPEED if name=="walk" else 6.0/Farm3DPlayer.RUN_REFERENCE_SPEED
		var dt := duration / (480.0*playback)
		var positions := {}
		for bone in limits: positions[bone]=[]
		animator.play(clip)
		for frame in 480:
			animator.seek(duration*frame/480.0,true)
			skeleton.force_update_all_bone_transforms()
			for bone in limits: positions[bone].append(bone_point(skeleton,bone))
		for bone in limits:
			var points: Array=positions[bone]
			var peak := 0.0
			var seam := 0.0
			for frame in 480:
				var incoming: Vector3=(points[frame]-points[(frame+479)%480])/dt
				var outgoing: Vector3=(points[(frame+1)%480]-points[frame])/dt
				var change := incoming.distance_to(outgoing)
				peak=maxf(peak,change)
				if frame==0: seam=change
			check(peak<float(limits[bone]), "%s %s avoids abrupt within-cycle velocity changes"%[name,bone])
			check(seam<.65, "%s %s crosses the loop without a velocity hitch"%[name,bone])

func validate_locomotion() -> void:
	# Isolated physical floor: no farm session, save files or NPC simulation.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(30,.2,30)
	floor_shape.position.y = -.1
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	var player := Farm3DPlayer.new()
	player.position = Vector3(0,0,5)
	var capsule := CollisionShape3D.new()
	capsule.shape = CapsuleShape3D.new()
	capsule.shape.radius = .3
	capsule.shape.height = 1.9
	capsule.position.y = .95
	player.add_child(capsule)
	player.add_child(load("res://assets/models/farm3d/player_farmer.glb").instantiate())
	root.add_child(player)
	await physics_steps(5)
	Input.action_press("move_forward")
	await physics_steps(10)
	check(is_equal_approx(Vector2(player.velocity.x,player.velocity.z).length(),3.0),"Ordinary movement is 3 m/s")
	check(is_equal_approx(player._animation_player.speed_scale,3.0/Farm3DPlayer.WALK_REFERENCE_SPEED),"Walking cadence follows actual stride speed")
	Input.action_press("sprint")
	await physics_steps(5)
	check(is_equal_approx(Vector2(player.velocity.x,player.velocity.z).length(),6.0),"Shift runs at 6 m/s")
	check(is_equal_approx(player._animation_player.speed_scale,6.0/Farm3DPlayer.RUN_REFERENCE_SPEED),"Run animation and travel speed agree")
	Input.action_press("move_right")
	await physics_steps(5)
	check(is_equal_approx(Vector2(player.velocity.x,player.velocity.z).length(),6.0),"Diagonal running remains normalized")
	Input.action_release("move_right")
	Input.action_release("sprint")
	await physics_steps(5)
	check(is_equal_approx(Vector2(player.velocity.x,player.velocity.z).length(),3.0),"Releasing Shift returns to walking")
	Input.action_release("move_forward")
	await physics_steps(5)
	check(is_zero_approx(player.velocity.x) and is_zero_approx(player.velocity.z) and is_equal_approx(player._animation_player.speed_scale,1.0),"Stopping restores a stationary idle")
	player.queue_free()
	floor_body.queue_free()
	await process_frame
