extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const SYSTEM_SCENE := "res://scenes/systems/building_system.tscn"


class EconomyDouble:
	extends RefCounted
	var available := true
	var spend_succeeds := true
	var spend_calls := 0

	func has_resources(_cost: Dictionary) -> bool:
		return available

	func spend_resources(_cost: Dictionary) -> bool:
		spend_calls += 1
		return spend_succeeds


func run(assertions: TestAssert, tree: SceneTree) -> void:
	assertions.truthy(ResourceLoader.exists(SYSTEM_SCENE), "reusable building system scene exists")
	if not ResourceLoader.exists(SYSTEM_SCENE):
		return

	var game_data = GameDataScript.new()
	var grid = GridSystemScript.new()
	var economy := EconomyDouble.new()
	var container := Node3D.new()
	var system = (load(SYSTEM_SCENE) as PackedScene).instantiate()
	tree.root.add_child(grid)
	tree.root.add_child(container)
	tree.root.add_child(system)
	system.configure(grid, economy, container)

	var barn = BuildingDataScript.from_dictionary(game_data.get_building("barn"))
	grid.set_cell_state(3, 3, GridCell.State.FARMLAND)
	grid.set_cell_state(4, 4, GridCell.State.FARMLAND)
	assertions.truthy(system.can_place(barn, 3, 3), "mixed wasteland and farmland footprint is valid")
	var placed = system.place_building(barn, 3, 3)
	assertions.truthy(placed is BuildingInstance, "placement returns typed BuildingInstance")
	assertions.equal(system.get_building_count(), 1, "placement tracks one building")
	assertions.equal(container.get_child_count(), 1, "placement uses configured container")
	assertions.equal(economy.spend_calls, 1, "successful placement spends once")
	for z in range(3, 5):
		for x in range(3, 5):
			assertions.equal(grid.get_cell(x, z).state, GridCell.State.BUILDING, "footprint cell %d,%d is occupied" % [x, z])
	assertions.equal(placed.position, Vector3(-14.0, 0.0, -10.0), "building is centered over footprint")

	assertions.equal(system.can_place(barn, 3, 3), false, "occupied footprint is rejected")
	assertions.equal(system.can_place(barn, 35, 27), false, "out-of-bounds footprint is rejected")

	system.remove_building(placed)
	assertions.equal(grid.get_cell(3, 3).state, GridCell.State.FARMLAND, "removal restores first farmland cell")
	assertions.equal(grid.get_cell(4, 4).state, GridCell.State.FARMLAND, "removal restores second farmland cell")
	assertions.equal(grid.get_cell(4, 3).state, GridCell.State.WASTELAND, "removal restores wasteland cell")
	assertions.equal(system.get_building_count(), 0, "removal untracks building")

	var well = BuildingDataScript.from_dictionary(game_data.get_building("well"))
	economy.spend_succeeds = false
	var failed = system.place_building(well, 8, 8)
	assertions.equal(failed, null, "failed spend returns no building")
	assertions.equal(grid.get_cell(8, 8).state, GridCell.State.WASTELAND, "failed spend rolls grid back")
	assertions.equal(system.get_building_count(), 0, "failed spend leaves no tracked building")

	economy.spend_succeeds = true
	economy.available = false
	assertions.equal(system.place_building(well, 9, 9), null, "insufficient resources reject placement")
	assertions.equal(economy.spend_calls, 2, "resource precheck avoids a spend call")

	economy.available = true
	system.enter_preview_mode(well)
	system.update_preview_grid(10, 10)
	assertions.truthy(system.is_in_build_mode(), "preview mode is active")
	assertions.equal(system.get_preview_grid(), Vector2i(10, 10), "preview stores grid coordinate")
	assertions.equal(system.get_preview_marker_count(), 1, "preview has one marker per footprint cell")
	assertions.truthy(system.get_preview_can_place(), "preview reports valid placement")
	grid.set_cell_state(10, 10, GridCell.State.BUILDING)
	system.update_preview_grid(10, 10)
	assertions.equal(system.get_preview_can_place(), false, "preview reports occupied placement")
	system.exit_preview_mode()
	assertions.equal(system.is_in_build_mode(), false, "preview exits cleanly")

	var windmill = BuildingDataScript.from_dictionary(game_data.get_building("windmill"))
	var workbench = BuildingDataScript.from_dictionary(game_data.get_building("workbench"))
	var windmill_instance = system.place_building(windmill, 12, 12)
	var workbench_instance = system.place_building(workbench, 16, 12)
	assertions.equal(system.get_buildings_by_effect("crafting").size(), 2, "effect query returns matching buildings")
	assertions.equal(system.get_building_at(12, 12), windmill_instance, "origin query finds building")
	assertions.equal(system.get_building_at(13, 13), windmill_instance, "footprint query finds building")
	system.clear_buildings()
	assertions.equal(system.get_building_count(), 0, "clear removes every building")
	assertions.equal(is_instance_valid(workbench_instance), true, "queued instance remains valid until frame end")

	system.queue_free()
	container.queue_free()
	grid.queue_free()
	game_data.free()

