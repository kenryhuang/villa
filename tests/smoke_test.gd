extends RefCounted

const MainScene = preload("res://scenes/main.tscn")

func run(assertions) -> void:
	var main = MainScene.instantiate()
	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.add_child(main)
	assertions.truthy(main.has_node("World"), "main contains world")
	assertions.truthy(main.has_node("Actors/Player"), "main contains player")
	assertions.truthy(main.has_node("CameraRig"), "main contains camera rig")
	assertions.truthy(main.has_node("HUD"), "main contains HUD")
	assertions.equal(scene_tree.get_nodes_in_group("tree_instance").size(), 28, "main world builds 28 runtime tree instances")
	main.free()
