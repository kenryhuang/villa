extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const BUILDING_SYSTEM_SCENE := preload("res://scenes/systems/building_system.tscn")
const BUILD_UI_SCENE := preload("res://scenes/ui/build_ui.tscn")


class EconomyDouble:
	extends RefCounted

	func has_resources(_cost: Dictionary) -> bool:
		return true

	func spend_resources(_cost: Dictionary) -> bool:
		return true


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var grid = GridSystemScript.new()
	var building_system = BUILDING_SYSTEM_SCENE.instantiate()
	var build_ui = BUILD_UI_SCENE.instantiate()
	tree.root.add_child(grid)
	tree.root.add_child(building_system)
	tree.root.add_child(build_ui)
	building_system.configure(grid, EconomyDouble.new())
	build_ui.configure(building_system)

	build_ui._on_build_pressed("well")
	assertions.truthy(building_system.is_in_build_mode(), "choosing a build card keeps preview mode active")
	assertions.equal(building_system.get_selected_building_id(), "well", "chosen card remains selected after the menu hides")
	assertions.equal(build_ui.visible, false, "build menu hides after choosing a building")

	build_ui.free()
	building_system.free()
	grid.free()
