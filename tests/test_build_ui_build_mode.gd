extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const BUILDING_SYSTEM_SCENE := preload("res://scenes/systems/building_system.tscn")
const BUILD_UI_SCENE := preload("res://scenes/ui/build_ui.tscn")
const BuildingCatalogScript = preload("res://scripts/core/building_catalog.gd")


class EconomyDouble:
	extends RefCounted

	func has_resources(_cost: Dictionary) -> bool:
		return true

	func spend_resources(_cost: Dictionary) -> bool:
		return true


class ProgressionDouble:
	extends RefCounted
	var unlocked := {"well": true}

	func is_blueprint_managed(_building_id: String) -> bool:
		return true

	func is_blueprint_unlocked(building_id: String) -> bool:
		return bool(unlocked.get(building_id, false))

	func get_blueprint_lock_info(building_id: String) -> Dictionary:
		return {
			"unlocked": is_blueprint_unlocked(building_id),
			"reason": "需要第8天",
			"service_id": "blueprint_%s" % building_id,
		}


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var grid = GridSystemScript.new()
	var building_system = BUILDING_SYSTEM_SCENE.instantiate()
	var build_ui = BUILD_UI_SCENE.instantiate()
	tree.root.add_child(grid)
	tree.root.add_child(building_system)
	tree.root.add_child(build_ui)
	building_system.configure(grid, EconomyDouble.new(), null, ProgressionDouble.new())
	build_ui.configure(building_system)

	build_ui.open()
	var card_ids: Array[String] = []
	for card in build_ui.grid_container.get_children():
		card_ids.append(str(card.get_meta("building_id", "")))
	assertions.equal(card_ids, BuildingCatalogScript.all_building_ids(), "BuildUI follows the shared catalog order")
	build_ui._on_build_pressed("windmill")
	assertions.truthy(not building_system.is_in_build_mode(), "locked card does not enter preview")
	assertions.truthy(build_ui.visible, "locked card keeps the catalog open for feedback")

	build_ui._on_build_pressed("well")
	assertions.truthy(building_system.is_in_build_mode(), "choosing a build card keeps preview mode active")
	assertions.equal(building_system.get_selected_building_id(), "well", "chosen card remains selected after the menu hides")
	assertions.equal(build_ui.visible, false, "build menu hides after choosing a building")

	build_ui.free()
	building_system.free()
	grid.free()
