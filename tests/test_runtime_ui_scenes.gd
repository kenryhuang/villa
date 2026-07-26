extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _check_scene(path: String, required_nodes: Array[String]) -> void:
	_check(ResourceLoader.exists(path), "missing scene: %s" % path)
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	_check(packed != null, "cannot load scene: %s" % path)
	if packed == null:
		return
	var instance := packed.instantiate()
	for node_path in required_nodes:
		_check(instance.has_node(node_path), "%s missing node %s" % [path, node_path])
	instance.free()


func _run() -> void:
	_check_scene("res://scenes/ui/hud.tscn", [
		"TopBar/StaminaBar",
		"TopBar/GoldLabel",
		"TopBar/LevelLabel",
		"TopBar/ExpBar",
		"TopBar/SeasonLabel",
		"TopBar/TimeLabel",
		"BottomBar/QuickBar",
		"BottomBar/ToolLabel",
	])
	_check_scene("res://scenes/ui/inventory_ui.tscn", ["Panel/VBox/GridContainer", "Panel/VBox/QuickBar"])
	_check_scene("res://scenes/ui/dialogue_ui.tscn", [
		"DialoguePanel/Margin/VBox/NameLabel",
		"DialoguePanel/Margin/VBox/TextContainer/TextLabel",
		"DialoguePanel/Margin/VBox/Choices",
	])
	_check_scene("res://scenes/ui/build_ui.tscn", ["ScrollContainer/GridContainer", "CloseButton"])
	_check_scene("res://scenes/ui/map_ui.tscn", ["MapTexture", "MapTexture/PlayerMarker"])
	_check_scene("res://scenes/ui/shop_ui.tscn", ["TopBar/GoldLabel", "ScrollContainer/GridContainer", "CloseButton"])
	_check_scene("res://scenes/main.tscn", ["InventoryUI", "DialogueUI", "BuildUI", "MapUI", "ShopUI"])
	await _check_map_resizes_with_window()

	if failures.is_empty():
		print("PASS: runtime UI scene contract")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FAIL: %d runtime UI scene contract errors" % failures.size())
	quit(1)


func _check_map_resizes_with_window() -> void:
	var packed := load("res://scenes/ui/map_ui.tscn") as PackedScene
	if packed == null:
		return

	var window := Control.new()
	window.size = Vector2(1280.0, 720.0)
	get_root().add_child(window)
	var map_ui := packed.instantiate() as Control
	window.add_child(map_ui)
	await process_frame
	var map_texture := map_ui.get_node("MapTexture") as TextureRect
	var initial_size := map_texture.size

	window.size = Vector2(1920.0, 1080.0)
	await process_frame
	var enlarged_size := map_texture.size
	_check(
		enlarged_size.x > initial_size.x and enlarged_size.y > initial_size.y,
		"map canvas must grow with its window: %s -> %s" % [initial_size, enlarged_size]
	)
	window.free()
