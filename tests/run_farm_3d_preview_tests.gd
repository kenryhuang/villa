extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame

func _run() -> void:
	var path := "res://scenes/preview/farm_3d_preview.tscn"
	_check(ResourceLoader.exists(path), "Standalone 3D preview scene exists")
	if not failures.is_empty():
		quit(1)
		return
	var packed := load(path) as PackedScene
	var preview := packed.instantiate()
	root.add_child(preview)
	await _frames(45)
	_check(preview.get_node("EnvironmentModel").find_children("*", "MeshInstance3D", true, false).size() > 0, "Environment contains an imported native mesh")
	var player := preview.get_node("Player") as CharacterBody3D
	_check(player.find_children("*", "MeshInstance3D", true, false).size() > 0, "Farmer contains an imported native mesh")
	var animation_players := player.find_children("*", "AnimationPlayer", true, false)
	_check(not animation_players.is_empty(), "Farmer imports its animation player")
	if not animation_players.is_empty():
		var farmer_animations := animation_players.front() as AnimationPlayer
		_check(farmer_animations.has_animation("Idle") and farmer_animations.has_animation("Walk"), "Farmer imports Idle and Walk animations")
		_check(farmer_animations.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR, "Farmer Idle animation loops")
		_check(farmer_animations.get_animation("Walk").loop_mode == Animation.LOOP_LINEAR, "Farmer Walk animation loops")
	_check(player.is_on_floor(), "Farmer rests on the terrain after physical settling")
	var start := player.global_position
	Input.action_press("move_forward")
	await _frames(30)
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(start) > 0.7, "Movement input moves the farmer in the real scene")
	Input.action_press("jump")
	await _frames(5)
	Input.action_release("jump")
	_check(player.global_position.y > 0.2, "Jump lifts the farmer from the terrain")
	await _frames(80)
	_check(player.is_on_floor(), "Farmer lands after jumping")
	player.global_position = Vector3(2.35, 0.8, -1.7)
	player.velocity = Vector3.ZERO
	await _frames(50)
	_check(player.is_on_floor(), "Farmer can stand on the modeled field")
	_check(absf(player.global_position.y - 0.13) < 0.035, "Field collision matches the visible furrow height")
	player.reset_position()
	await _frames(3)
	var arm := preview.get_node("CameraRig/Pitch/SpringArm3D") as SpringArm3D
	var obstacle := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 0.5)
	collision.shape = box
	obstacle.add_child(collision)
	root.add_child(obstacle)
	obstacle.global_transform = arm.global_transform
	obstacle.global_position += arm.global_basis.z * 2.5
	await _frames(10)
	_check(arm.get_hit_length() < arm.spring_length - 1.0, "Third-person camera retracts before a world obstacle")
	obstacle.queue_free()
	await _frames(10)
	_check(arm.get_hit_length() > arm.spring_length - 0.2, "Camera returns to its requested distance when the obstacle clears")
	preview.set_overview(true)
	_check(preview.get_node("OverviewCamera").current, "Overview selects the wide camera")
	preview.set_overview(false)
	_check(arm.get_node("Camera3D").current, "Overview toggle returns to the follow camera")
	player.global_position = Vector3(0, -11, 0)
	await _frames(3)
	_check(player.global_position.distance_to(Vector3(-2, 0, 4)) < 0.5, "Out-of-world farmer resets safely")
	preview.queue_free()
	await process_frame
	print("3D FARM PREVIEW: %s" % ("PASS (%d checks)" % checks if failures.is_empty() else "FAIL (%d/%d checks)" % [failures.size(), checks]))
	quit(0 if failures.is_empty() else 1)
