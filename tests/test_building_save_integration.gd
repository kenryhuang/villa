extends RefCounted

const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const GRID_SYSTEM_SCENE := preload("res://scenes/systems/grid_system.tscn")
const BUILDING_SYSTEM_SCENE := preload("res://scenes/systems/building_system.tscn")


class EconomyDouble:
	extends RefCounted
	var spend_calls := 0

	func has_resources(_cost: Dictionary) -> bool:
		return true

	func spend_resources(_cost: Dictionary) -> bool:
		spend_calls += 1
		return true


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var grid = GRID_SYSTEM_SCENE.instantiate()
	var system = BUILDING_SYSTEM_SCENE.instantiate()
	var manager = SaveManagerScript.new()
	tree.root.add_child(grid)
	tree.root.add_child(system)
	tree.root.add_child(manager)
	var economy := EconomyDouble.new()
	system.configure(grid, economy)
	grid.set_cell_state(6, 6, GridCell.State.FARMLAND)
	var placed = system.place_building_by_id("fence", 6, 6)
	assertions.truthy(placed is BuildingInstance, "save fixture places a building")
	assertions.equal(manager._get_building_system(), system, "save manager discovers the main-scene building system")
	placed.advance_construction(4.5)
	assertions.equal(placed.construction_stage, BuildingInstance.ConstructionStage.FRAME, "save fixture reaches frame stage")
	assertions.near(placed.construction_elapsed, 4.5, 0.001, "save fixture stores time inside frame stage")

	var records: Array = manager._serialize_buildings(system)
	assertions.equal(records.size(), system.get_building_count(), "save manager serializes every tracked building")
	assertions.truthy(records[0].has("occupied_cells"), "save record preserves occupied cell snapshots")
	assertions.truthy(not records[0].occupied_cells.is_empty(), "save record includes prior grid state")
	assertions.equal(
		records[0].construction_stage,
		BuildingInstance.ConstructionStage.FRAME,
		"save record preserves construction stage"
	)
	assertions.truthy(float(records[0].construction_elapsed) > 0.0, "save record preserves construction elapsed")

	var saved_grid: Dictionary = grid.to_dict()
	manager._apply_save_data({"grid": saved_grid, "buildings": records})
	assertions.equal(system.get_building_count(), 1, "load rebuilds one building instance")
	var restored = system.get_building_at(6, 6)
	assertions.truthy(restored is BuildingInstance, "loaded building is queryable at its occupied cell")
	assertions.equal(restored.occupied_cells[0].previous_state, GridCell.State.FARMLAND, "load preserves exact removal state")
	assertions.equal(restored.construction_stage, BuildingInstance.ConstructionStage.FRAME, "load restores construction stage")
	assertions.near(restored.construction_elapsed, 4.5, 0.001, "load restores partial frame elapsed time")
	restored.advance_construction(1.49)
	assertions.equal(restored.construction_stage, BuildingInstance.ConstructionStage.FRAME, "restored frame waits for remaining time")
	restored.advance_construction(0.01)
	assertions.equal(restored.construction_stage, BuildingInstance.ConstructionStage.HALF_BUILT, "restored frame advances at six seconds")
	assertions.equal(economy.spend_calls, 1, "load does not spend resources again")

	var short_duration_record: Dictionary = records[0].duplicate(true)
	short_duration_record.construction_stage = BuildingInstance.ConstructionStage.HALF_BUILT
	short_duration_record.construction_elapsed = 2.7
	short_duration_record.construction_duration = 4.0
	manager._apply_save_data({"grid": saved_grid, "buildings": [short_duration_record]})
	restored = system.get_building_at(6, 6)
	assertions.equal(restored.construction_stage, BuildingInstance.ConstructionStage.HALF_BUILT, "old save keeps authoritative stage")
	assertions.near(restored.construction_elapsed, 6.0, 0.001, "old short duration aligns to new half-built threshold")

	var legacy_record: Dictionary = records[0].duplicate(true)
	legacy_record.erase("construction_stage")
	legacy_record.erase("construction_elapsed")
	legacy_record.erase("construction_duration")
	manager._apply_save_data({"grid": saved_grid, "buildings": [legacy_record]})
	restored = system.get_building_at(6, 6)
	assertions.truthy(restored.is_construction_complete(), "legacy save restores building as complete")
	system.remove_building(restored)
	assertions.equal(grid.get_cell(6, 6).state, GridCell.State.FARMLAND, "loaded building removal restores the saved state")

	manager.free()
	system.free()
	grid.free()
