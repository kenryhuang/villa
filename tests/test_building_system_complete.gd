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
	var configure_result: Variant = system.configure(grid, economy, container)
	assertions.equal(configure_result, true, "configure reports a usable system")
	assertions.truthy(system.has_method("get_preview_data"), "preview data API is available")
	assertions.truthy(system.has_method("update_preview"), "grid preview API is available")
	assertions.truthy(system.has_method("place_building_by_id"), "id placement API is available")
	assertions.truthy(system.has_method("get_buildings_of_type"), "effect query API is available")
	var signal_shapes := {}
	for signal_info in system.get_signal_list():
		signal_shapes[signal_info.name] = signal_info.args.size()
	assertions.equal(signal_shapes.get("building_placed", -1), 3, "compatibility placement signal keeps three arguments")
	assertions.equal(signal_shapes.get("building_removed", -1), 1, "compatibility removal signal keeps one argument")
	assertions.equal(signal_shapes.get("building_preview_moved", -1), 3, "preview movement signal is available")
	assertions.equal(signal_shapes.get("building_instance_placed", -1), 1, "typed placement signal is available")
	assertions.equal(signal_shapes.get("building_instance_removed", -1), 1, "typed removal signal is available")
	assertions.equal(signal_shapes.get("building_construction_started", -1), 1, "construction start signal is available")
	assertions.equal(signal_shapes.get("building_construction_stage_changed", -1), 2, "construction stage signal is available")
	assertions.equal(signal_shapes.get("building_construction_completed", -1), 1, "construction completion signal is available")
	var construction_started_events: Array[BuildingInstance] = []
	var construction_stage_events: Array[int] = []
	var construction_completed_events: Array[BuildingInstance] = []
	system.building_construction_started.connect(
		func(instance: BuildingInstance) -> void:
			construction_started_events.append(instance)
	)
	system.building_construction_stage_changed.connect(
		func(_instance: BuildingInstance, stage: int) -> void:
			construction_stage_events.append(stage)
	)
	system.building_construction_completed.connect(
		func(instance: BuildingInstance) -> void:
			construction_completed_events.append(instance)
	)

	var barn = BuildingDataScript.from_dictionary(game_data.get_building("barn"))
	assertions.equal(system.configure(grid, null, container), false, "configure rejects a missing economy")
	system.economy_ref = null
	assertions.equal(system.can_place(barn, 3, 3), false, "missing economy rejects free placement")
	system.economy_ref = economy
	grid.get_cell(3, 3).terrain_height = NAN
	assertions.equal(system.can_place(barn, 3, 3), false, "non-finite terrain height rejects placement")
	grid.get_cell(3, 3).terrain_height = 0.0
	var invalid_scene_data := barn.duplicate(true) as BuildingData
	invalid_scene_data.scene_path = "res://assets/buildings/painted/barn/barn_back.png"
	assertions.equal(system.can_place(invalid_scene_data, 3, 3), false, "non-scene resource rejects placement")
	assertions.equal(system.enter_preview_mode(invalid_scene_data), false, "non-scene resource rejects preview mode")
	grid.set_cell_state(3, 3, GridCell.State.FARMLAND)
	grid.set_cell_state(4, 4, GridCell.State.FARMLAND)
	assertions.truthy(system.can_place(barn, 3, 3), "mixed wasteland and farmland footprint is valid")
	var placed = system.place_building(barn, 3, 3)
	assertions.truthy(placed is BuildingInstance, "placement returns typed BuildingInstance")
	assertions.equal(system.get_building_count(), 1, "placement tracks one building")
	assertions.equal(container.get_child_count(), 1, "placement uses configured container")
	assertions.equal(economy.spend_calls, 1, "successful placement spends once")
	assertions.equal(placed.construction_stage, BuildingInstance.ConstructionStage.FOUNDATION, "placement starts at foundation")
	assertions.equal(construction_started_events, [placed], "successful placement emits one construction start")
	placed.advance_construction_stage()
	assertions.equal(
		construction_stage_events,
		[BuildingInstance.ConstructionStage.FRAME],
		"system forwards construction stage"
	)
	placed.complete_construction()
	assertions.equal(construction_completed_events, [placed], "system forwards construction completion")
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
	assertions.equal(system.get_preview_data(), well, "preview exposes selected typed data")
	assertions.truthy(system.update_preview(10, 10), "grid preview returns placement validity")
	assertions.truthy(system.is_in_build_mode(), "preview mode is active")
	assertions.equal(system.get_preview_grid(), Vector2i(10, 10), "preview stores grid coordinate")
	assertions.equal(system.get_preview_marker_count(), 1, "preview has one marker per footprint cell")
	assertions.truthy(system.get_preview_can_place(), "preview reports valid placement")
	var preview_instance := system.get_node("BuildingPreview/VisualProxy").get_child(0) as BuildingInstance
	assertions.truthy(preview_instance.is_construction_complete(), "preview never starts construction")
	assertions.equal(preview_instance.get_node("Collision").collision_layer, 0, "preview construction collision stays disabled")
	var preview_marker := system.get_node("BuildingPreview/FootprintMarkers").get_child(0) as MeshInstance3D
	var valid_material := preview_marker.material_override as StandardMaterial3D
	assertions.truthy(valid_material.albedo_color.g > valid_material.albedo_color.r, "valid preview markers are green")
	grid.set_cell_state(10, 10, GridCell.State.BUILDING)
	system.update_preview_grid(10, 10)
	assertions.equal(system.get_preview_can_place(), false, "preview reports occupied placement")
	var invalid_material := preview_marker.material_override as StandardMaterial3D
	assertions.truthy(invalid_material.albedo_color.r > invalid_material.albedo_color.g, "invalid preview markers are red")
	system.exit_preview_mode()
	assertions.equal(system.is_in_build_mode(), false, "preview exits cleanly")

	var windmill = BuildingDataScript.from_dictionary(game_data.get_building("windmill"))
	var workbench = BuildingDataScript.from_dictionary(game_data.get_building("workbench"))
	var windmill_instance = system.place_building(windmill, 12, 12)
	var workbench_instance = system.place_building(workbench, 16, 12)
	assertions.equal(system.get_buildings_of_type("crafting").size(), 2, "effect query returns matching buildings")
	assertions.equal(system.get_building_at(12, 12), windmill_instance, "origin query finds building")
	assertions.equal(system.get_building_at(13, 13), windmill_instance, "footprint query finds building")
	system.clear_buildings()
	assertions.equal(system.get_building_count(), 0, "clear removes every building")
	assertions.equal(is_instance_valid(workbench_instance), true, "queued instance remains valid until frame end")

	var fence = system.place_building_by_id("fence", 20, 12)
	assertions.truthy(fence is BuildingInstance, "id placement creates a typed building")
	var saved_fence: Dictionary = fence.to_dict()
	system.clear_buildings(false)
	assertions.equal(grid.get_cell(20, 12).state, GridCell.State.BUILDING, "clear can preserve saved grid occupancy")
	assertions.equal(fence.is_in_group("building_instance"), false, "clear deactivates removed instances immediately")
	var restored_count: Variant = system.restore_buildings([saved_fence])
	assertions.equal(restored_count, 1, "saved building records reconstruct instances without spending")
	assertions.equal(system.get_building_at(20, 12).occupied_cells[0].previous_state, GridCell.State.WASTELAND, "restore preserves prior cell state")
	assertions.equal(economy.spend_calls, 5, "restore does not spend resources")

	system.free()
	container.free()
	grid.free()
	game_data.free()
