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
