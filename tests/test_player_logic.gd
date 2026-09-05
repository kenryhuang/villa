extends RefCounted

const PlayerScript = preload("res://scripts/actors/player.gd")

func run(assertions) -> void:
	var forward := Vector3(0.0, 0.0, -1.0)
	var right := Vector3(1.0, 0.0, 0.0)
	assertions.equal(PlayerScript.movement_from_input(Vector2(0.0, -1.0), forward, right), forward, "forward input follows camera")
	assertions.equal(PlayerScript.movement_from_input(Vector2(1.0, 0.0), forward, right), right, "right input follows camera")
	assertions.near(
		PlayerScript.movement_from_input(Vector2(1.0, -1.0), forward, right).length(),
		1.0,
		0.000001,
		"diagonal movement is normalized"
	)
	var player = PlayerScript.new()
	var has_speed_scale := player.has_method("movement_speed_scale")
	assertions.truthy(has_speed_scale, "player exposes camera-relative movement speed scaling")
	if has_speed_scale:
		assertions.near(
			float(player.call("movement_speed_scale", Vector3.RIGHT, Vector3.RIGHT)),
			0.67,
			0.000001,
			"pure lateral movement uses the approved reduced speed"
		)
		assertions.near(
			float(player.call("movement_speed_scale", Vector3.FORWARD, Vector3.RIGHT)),
			1.0,
			0.000001,
			"pure forward movement keeps full speed"
		)
		var diagonal_scale := float(player.call(
			"movement_speed_scale",
			Vector3(1.0, 0.0, -1.0).normalized(),
			Vector3.RIGHT
		))
		assertions.truthy(
			diagonal_scale > 0.67 and diagonal_scale < 1.0,
			"diagonal movement blends lateral and forward speed"
		)
		assertions.near(
			float(player.call("movement_speed_scale", Vector3.ZERO, Vector3.RIGHT)),
			1.0,
			0.000001,
			"stationary input keeps a neutral speed scale"
		)
		assertions.near(
			float(player.call("movement_speed_scale", Vector3.RIGHT, Vector3.ZERO)),
			1.0,
			0.000001,
			"missing camera-right data keeps a neutral speed scale"
		)

	var has_dialogue_movement_gate := (
		player.has_method("set_movement_input_blocked")
		and player.has_method("filter_movement_input")
	)
	assertions.truthy(has_dialogue_movement_gate, "player exposes a dialogue-safe movement input gate")
	if has_dialogue_movement_gate:
		player.velocity = Vector3(2.0, 0.0, 1.0)
		assertions.truthy(player.start_auto_path([Vector3(3.0, 0.0, 0.0)]), "dialogue movement gate fixture starts auto movement")
		player.call("set_movement_input_blocked", true)
		assertions.equal(player.call("filter_movement_input", Vector2.RIGHT), Vector2.ZERO, "dialogue blocks held D movement input")
		assertions.truthy(not player.has_auto_movement(), "dialogue stops active automatic movement")
		assertions.equal(Vector2(player.velocity.x, player.velocity.z), Vector2.ZERO, "dialogue immediately stops planar velocity")
		Input.action_press("jump")
		Input.action_press("sprint")
		player.call("set_movement_input_blocked", false)
		assertions.equal(player.call("filter_movement_input", Vector2.RIGHT), Vector2.ZERO, "held dialogue movement stays suppressed after close")
		assertions.equal(player.call("filter_movement_input", Vector2.ZERO), Vector2.ZERO, "held jump and sprint keep input rearm pending")
		Input.action_release("jump")
		assertions.equal(player.call("filter_movement_input", Vector2.ZERO), Vector2.ZERO, "held sprint alone keeps input rearm pending")
		Input.action_release("sprint")
		assertions.equal(player.call("filter_movement_input", Vector2.ZERO), Vector2.ZERO, "neutral polling alone does not rearm movement")
		var fresh_move := InputEventAction.new()
		fresh_move.action = "move_right"
		fresh_move.pressed = true
		Input.action_press("move_right")
		player.call("_input", fresh_move)
		assertions.equal(player.call("filter_movement_input", Vector2.RIGHT), Vector2.RIGHT, "a fresh movement press is accepted after rearm")
		Input.action_release("move_right")

	var finished := []
	var blocked := []
	var manual := []
	player.auto_path_finished.connect(func() -> void: finished.append(true))
	player.auto_path_blocked.connect(func() -> void: blocked.append(true))
	player.manual_movement_requested.connect(func() -> void: manual.append(true))
	assertions.truthy(not player.start_auto_path([]), "auto movement rejects an empty path")
	assertions.truthy(player.start_auto_path([
		Vector3(1.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 0.0),
	]), "auto movement accepts an ordered world path")
	assertions.truthy(player.has_auto_movement(), "accepted path becomes active")
	player._is_sprinting = true
	assertions.equal(player._update_auto_movement(0.1), Vector3.RIGHT, "auto movement points at first waypoint")
	assertions.truthy(not player._is_sprinting, "auto movement always uses normal walking speed")
	player.position = Vector3(1.0, 0.0, 0.0)
	assertions.equal(player._update_auto_movement(0.1), Vector3.RIGHT, "reaching first waypoint advances to second")
	player.position = Vector3(2.0, 0.0, 0.0)
	assertions.equal(player._update_auto_movement(0.1), Vector3.ZERO, "reaching final waypoint stops movement")
	assertions.equal(finished.size(), 1, "auto path completion emits exactly once")
	assertions.truthy(not player.has_auto_movement(), "completed path is inactive")

	assertions.truthy(player.start_auto_path([Vector3(5.0, 0.0, 0.0)]), "blocked fixture starts")
	player._update_auto_movement(0.3)
	player._update_auto_movement(0.3)
	player._update_auto_movement(0.3)
	assertions.equal(blocked.size(), 1, "no progress for half a second emits blocked once")
	assertions.truthy(not player.has_auto_movement(), "blocked path is stopped")

	assertions.truthy(player.start_auto_path([Vector3(3.0, 0.0, 0.0)]), "manual-cancel fixture starts")
	player.velocity = Vector3(2.0, 0.0, 2.0)
	player._cancel_auto_for_manual_input()
	assertions.equal(manual.size(), 1, "manual input emits a cancellation request")
	assertions.truthy(not player.has_auto_movement(), "manual input cancels auto movement")
	assertions.equal(Vector2(player.velocity.x, player.velocity.z), Vector2.ZERO, "cancelled auto movement stops planar velocity")
	player.free()
