extends RefCounted

const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const GRID_SYSTEM_SCENE := preload("res://scenes/systems/grid_system.tscn")
const BUILDING_SYSTEM_SCENE := preload("res://scenes/systems/building_system.tscn")


class EconomyDouble:
	extends RefCounted

	func has_resources(_cost: Dictionary) -> bool:
		return true

	func spend_resources(_cost: Dictionary) -> bool:
		return true


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var grid = GRID_SYSTEM_SCENE.instantiate()
	var system = BUILDING_SYSTEM_SCENE.instantiate()
	var manager = SaveManagerScript.new()
	tree.root.add_child(grid)
	tree.root.add_child(system)
	tree.root.add_child(manager)
	system.configure(grid, EconomyDouble.new())
	grid.set_cell_state(6, 6, GridCell.State.FARMLAND)
	var placed = system.place_building_by_id("fence", 6, 6)
	assertions.truthy(placed is BuildingInstance, "save fixture places a building")
	assertions.equal(manager._get_building_system(), system, "save manager discovers the main-scene building system")

	var records: Array = manager._serialize_buildings(system)
	assertions.equal(records.size(), system.get_building_count(), "save manager serializes every tracked building")
	assertions.truthy(records[0].has("occupied_cells"), "save record preserves occupied cell snapshots")
	assertions.truthy(not records[0].occupied_cells.is_empty(), "save record includes prior grid state")

	var saved_grid: Dictionary = grid.to_dict()
	manager._apply_save_data({"grid": saved_grid, "buildings": records})
	assertions.equal(system.get_building_count(), 1, "load rebuilds one building instance")
	var restored = system.get_building_at(6, 6)
	assertions.truthy(restored is BuildingInstance, "loaded building is queryable at its occupied cell")
	assertions.equal(restored.occupied_cells[0].previous_state, GridCell.State.FARMLAND, "load preserves exact removal state")
	system.remove_building(restored)
	assertions.equal(grid.get_cell(6, 6).state, GridCell.State.FARMLAND, "loaded building removal restores the saved state")

	manager.free()
	system.free()
	grid.free()
