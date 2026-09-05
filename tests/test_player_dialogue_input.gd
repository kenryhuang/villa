extends RefCounted

const PlayerScene = preload("res://scenes/actors/player.tscn")


class CameraDouble:
	extends Node

	func get_planar_forward() -> Vector3:
		return Vector3.FORWARD

	func get_planar_right() -> Vector3:
		return Vector3.RIGHT


func run(assertions, tree: SceneTree) -> void:
	var root_node := Node.new()
	tree.root.add_child(root_node)
	var camera := CameraDouble.new()
	var player := PlayerScene.instantiate()
	root_node.add_child(camera)
	root_node.add_child(player)
	player.camera_rig = camera
	await tree.process_frame

	player.set_movement_input_blocked(true)
	Input.parse_input_event(_key_event(KEY_D, true))
	await tree.process_frame
	assertions.truthy(
		not Input.is_action_pressed("move_right"),
		"dialogue text input never enters the gameplay move-right action"
	)

	player.set_movement_input_blocked(false)
	Input.parse_input_event(_key_event(KEY_D, true, true))
	await tree.process_frame
	assertions.equal(
		player.filter_movement_input(Input.get_vector("move_left", "move_right", "move_forward", "move_back")),
		Vector2.ZERO,
		"held-key echo after dialogue cannot rearm movement"
	)

	Input.parse_input_event(_key_event(KEY_D, false))
	await tree.process_frame
	Input.parse_input_event(_key_event(KEY_D, true))
	await tree.process_frame
	assertions.equal(
		player.filter_movement_input(Input.get_vector("move_left", "move_right", "move_forward", "move_back")),
		Vector2.RIGHT,
		"a fresh D press after release rearms movement"
	)
	Input.parse_input_event(_key_event(KEY_D, false))
	await tree.process_frame
	root_node.queue_free()
	await tree.process_frame


func _key_event(keycode: Key, pressed: bool, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.unicode = keycode if pressed else 0
	event.pressed = pressed
	event.echo = echo
	return event
