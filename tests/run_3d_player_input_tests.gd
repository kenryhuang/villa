extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)

func key(code: Key, pressed: bool, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed;event.echo=echo
	return event

func run() -> void:
	var player := Farm3DPlayer.new()
	root.add_child(player);player.set_physics_process(false)
	player.position=Vector3(0,2,0)
	# A GUI-consumed event can update the global action map without reaching
	# the player's _input. Closing the dialog must still require a new press.
	player.set_dialogue_input_blocked(true)
	player.set_dialogue_input_blocked(false)
	Input.action_press("move_right")
	player._physics_process(.016)
	check(is_zero_approx(player.velocity.x),"Reasserted D action cannot bypass dialogue rearm in physics")
	Input.action_release("move_right")
	player.filter_dialogue_input(key(KEY_D,true))
	Input.action_press("move_right")
	player._physics_process(.016)
	check(player.velocity.x>0,"Fresh movement key still works")
	# Generic panels must apply the same release boundary as dialogue.
	player.ui_blocked=true
	player.ui_blocked=false
	player._physics_process(.016)
	check(is_zero_approx(player.velocity.x),"Closing another panel does not restore held right movement")
	Input.action_release("move_right")
	player.set_window_focused(false)
	Input.action_press("move_right")
	player._physics_process(.016)
	check(is_zero_approx(player.velocity.x),"Unfocused window cannot move the player")
	player.set_window_focused(true)
	Input.action_press("move_right")
	player.filter_dialogue_input(key(KEY_D,true,true))
	check(player.get_movement_input()==Vector2.ZERO,"Focus return and held-key echo cannot rearm movement")
	Input.action_press("move_right") # Residual right input cannot cancel fresh left.
	player.filter_dialogue_input(key(KEY_A,true))
	Input.action_press("move_left")
	check(player.get_movement_input()==Vector2.LEFT,"Each movement direction rearms independently")
	Input.action_release("move_left");Input.action_release("move_right")
	var entry := TextEdit.new();root.add_child(entry);entry.grab_focus()
	Input.parse_input_event(key(KEY_D,true))
	await process_frame
	check(player.get_movement_input()==Vector2.ZERO,"Focused text entry blocks movement without requiring a dialogue modal")
	entry.release_focus();entry.queue_free()
	check(player.get_movement_input()==Vector2.ZERO,"Leaving text entry does not activate the last typed movement letter")
	Input.parse_input_event(key(KEY_D,false))
	await process_frame
	Input.parse_input_event(key(KEY_D,true))
	await process_frame
	check(player.get_movement_input()==Vector2.RIGHT,"Real fresh key event restores normal controls")
	Input.parse_input_event(key(KEY_D,false))
	await process_frame
	player.golf_locked=true
	Input.parse_input_event(key(KEY_D,true))
	await process_frame
	check(Input.is_action_pressed("move_right") and player.get_movement_input()==Vector2.ZERO,"Golf can use direction keys for aim without moving the player")
	player.golf_locked=false
	check(not Input.is_action_pressed("move_right") and player.get_movement_input()==Vector2.ZERO,"Leaving golf clears its held aim key")
	for action in player.MOVEMENT_ACTIONS:Input.action_release(action)
	player.queue_free();await process_frame
	print("3D PLAYER INPUT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
