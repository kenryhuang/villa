extends RefCounted

const CameraMath = preload("res://scripts/camera/camera_math.gd")

func run(assertions) -> void:
	assertions.near(CameraMath.clamp_size(2.0), 5.0, 0.001, "camera enforces minimum zoom")
	assertions.near(CameraMath.clamp_size(20.0), 12.0, 0.001, "camera enforces maximum zoom")
	assertions.near(CameraMath.clamp_size(8.0), 8.0, 0.001, "camera preserves in-range zoom")
