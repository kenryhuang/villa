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
