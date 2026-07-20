extends RefCounted

const PlayerScript = preload("res://scripts/actors/player.gd")

func run(assertions) -> void:
	var forward := Vector3(0.0, 0.0, -1.0)
	var right := Vector3(1.0, 0.0, 0.0)
	assertions.equal(PlayerScript.movement_from_input(Vector2(0.0, -1.0), forward, right), forward, "forward input follows camera")
	assertions.equal(PlayerScript.movement_from_input(Vector2(1.0, 0.0), forward, right), right, "right input follows camera")
	var player = PlayerScript.new()
	player.take_damage(10)
	assertions.equal(player.health, 0, "player health clamps at zero")
	player.free()
