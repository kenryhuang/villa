extends RefCounted

const MainScene = preload("res://scenes/main.tscn")

func run(assertions) -> void:
	var main = MainScene.instantiate()
	assertions.truthy(main.has_node("World"), "main contains world")
	assertions.truthy(main.has_node("Actors/Player"), "main contains player")
	assertions.truthy(main.has_node("CameraRig"), "main contains camera rig")
	assertions.truthy(main.has_node("HUD"), "main contains HUD")
	main.free()
