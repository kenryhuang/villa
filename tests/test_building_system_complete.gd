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
	var refund_calls := 0
	var holdings := {
		"wood": 10000,
		"stone": 10000,
		"glass": 10000,
		"plank": 10000,
		"stone_brick": 10000,
		"wooden_crate": 10000,
		"rope": 10000,
		"brick": 10000,
		"charcoal": 10000,
		"iron_ingot": 10000,
		"machine_parts": 10000,
		"farm_tools": 10000,
		"steel": 10000,
		"lamp": 10000,
	}

	func get_resource_report(cost: Dictionary) -> Dictionary:
		var report := {}
		for item_id in cost:
			var required := int(cost[item_id])
			var held := int(holdings.get(item_id, 0))
			report[item_id] = {
				"required": required,
				"available": held,
				"missing": maxi(required - held, 0),
			}
		return report

	func has_resources(cost: Dictionary) -> bool:
		if not available:
			return false
		for entry in get_resource_report(cost).values():
			if int(entry.missing) > 0:
				return false
		return true

	func spend_resources(_cost: Dictionary) -> bool:
		spend_calls += 1
		return spend_succeeds

	func refund_resources(_cost: Dictionary) -> void:
		refund_calls += 1


class ProgressionDouble:
	extends RefCounted
	var unlocked := {"workbench": true, "stone_kiln": true, "beehive": true}

	func is_blueprint_managed(building_id: String) -> bool:
		return not building_id.is_empty()

	func is_blueprint_unlocked(building_id: String) -> bool:
		return bool(unlocked.get(building_id, false))

	func get_blueprint_lock_info(building_id: String) -> Dictionary:
		return {
			"unlocked": is_blueprint_unlocked(building_id),
			"reason": "需要第8天" if not is_blueprint_unlocked(building_id) else "",
			"service_id": "blueprint_%s" % building_id,
		}


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
	var locked_grid = GridSystemScript.new()
	var locked_economy := EconomyDouble.new()
	var locked_container := Node3D.new()
	var locked_system = (load(SYSTEM_SCENE) as PackedScene).instantiate()
	var progression := ProgressionDouble.new()
	tree.root.add_child(locked_grid)
	tree.root.add_child(locked_container)
	tree.root.add_child(locked_system)
	assertions.truthy(
		locked_system.configure(locked_grid, locked_economy, locked_container, progression),
		"building system accepts optional progression enforcement"
	)
	var locked_windmill = BuildingDataScript.from_dictionary(game_data.get_building("windmill"))
	var locked_cell_state := locked_grid.get_cell(6, 6).state
	var locked_result: Dictionary = locked_system.try_place_building(locked_windmill, 6, 6)
	assertions.equal(locked_result.diagnostic.code, "blueprint_locked", "locked blueprint placement is rejected")
	assertions.equal(locked_grid.get_cell(6, 6).state, locked_cell_state, "locked placement leaves grid untouched")
	assertions.equal(locked_economy.spend_calls, 0, "locked placement spends no resources")
	assertions.truthy(locked_system.has_method("diagnose_availability"), "building availability API exists")
	if locked_system.has_method("diagnose_availability"):
		var furnace_locked: Dictionary = locked_system.call("diagnose_availability", "furnace")
		assertions.equal(furnace_locked.code, "blueprint_locked", "locked furnace availability is explicit")
		assertions.equal(furnace_locked.unlock_service_id, "blueprint_furnace", "locked furnace links its service")
		assertions.truthy(not locked_system.enter_preview_mode("furnace"), "locked furnace cannot enter preview")
		assertions.truthy(not locked_system.is_in_build_mode(), "locked selection leaves preview inactive")
		progression.unlocked.furnace = true
		var furnace_cost: Dictionary = game_data.get_building("furnace").cost
		for item_id in furnace_cost:
			locked_economy.holdings[item_id] = 0
		var furnace_missing: Dictionary = locked_system.call("diagnose_availability", "furnace")
		assertions.equal(furnace_missing.code, "insufficient_resources", "unlocked furnace reports missing materials")
		assertions.truthy(not locked_system.enter_preview_mode("furnace"), "unfunded furnace cannot enter preview")
		assertions.truthy(not locked_system.is_in_build_mode(), "unfunded selection leaves preview inactive")
		for item_id in furnace_cost:
			locked_economy.holdings[item_id] = int(furnace_cost[item_id])
		assertions.equal(
			locked_system.call("diagnose_availability", "furnace").code,
			"ok",
			"funded furnace availability is ready"
		)
		assertions.truthy(locked_system.enter_preview_mode("furnace"), "funded furnace enters preview")
		locked_system.exit_preview_mode()
	var tier_zero = BuildingDataScript.from_dictionary(game_data.get_building("workbench"))
	assertions.truthy(locked_system.place_building(tier_zero, 8, 8) is BuildingInstance, "tier-zero blueprint remains placeable")
	locked_system.free()
	locked_container.free()
	locked_grid.free()
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
	var invalid_diagnostic: Dictionary = system.diagnose_placement("missing", 3, 3)
	assertions.equal(invalid_diagnostic.code, "invalid_building", "invalid building diagnostic is specific")
	var bounds_diagnostic: Dictionary = system.diagnose_placement(barn, 35, 27)
	assertions.equal(bounds_diagnostic.code, "out_of_bounds", "out-of-bounds diagnostic is specific")
	assertions.equal(
		bounds_diagnostic.blocked_cell.grid,
		Vector2i(36, 27),
		"out-of-bounds diagnostic identifies first missing footprint cell"
	)
	grid.get_cell(3, 3).terrain_height = NAN
	assertions.equal(system.can_place(barn, 3, 3), false, "non-finite terrain height rejects placement")
	var terrain_diagnostic: Dictionary = system.diagnose_placement(barn, 3, 3)
	assertions.equal(terrain_diagnostic.code, "invalid_terrain", "terrain diagnostic is specific")
	assertions.equal(terrain_diagnostic.blocked_cell.grid, Vector2i(3, 3), "terrain diagnostic identifies cell")
	grid.get_cell(3, 3).terrain_height = 0.0
	var invalid_scene_data := barn.duplicate(true) as BuildingData
	invalid_scene_data.scene_path = "res://assets/buildings/painted/barn/barn_back.png"
	assertions.equal(system.can_place(invalid_scene_data, 3, 3), false, "non-scene resource rejects placement")
	assertions.equal(system.enter_preview_mode(invalid_scene_data), false, "non-scene resource rejects preview mode")
	var well = BuildingDataScript.from_dictionary(game_data.get_building("well"))
	var blocked_states := {
		GridCell.State.ROAD: "road",
		GridCell.State.BUILDING: "occupied",
		GridCell.State.PLANTED: "planted",
		GridCell.State.WATER: "water",
		GridCell.State.DECORATION: "decoration",
	}
	var blocked_index := 0
	for state in blocked_states:
		var gx := 24 + blocked_index
		var gz := 4
		grid.get_cell(gx, gz).state = state
		var blocked_diagnostic: Dictionary = system.diagnose_placement(well, gx, gz)
		assertions.equal(
			blocked_diagnostic.code,
			blocked_states[state],
			"state %d diagnostic is specific" % state
		)
		assertions.equal(
			blocked_diagnostic.blocked_cell.grid,
			Vector2i(gx, gz),
			"state %d diagnostic identifies cell" % state
		)
		grid.get_cell(gx, gz).state = GridCell.State.WASTELAND
		blocked_index += 1
	economy.holdings.plank = 3
	var resource_diagnostic: Dictionary = system.diagnose_placement(barn, 8, 8)
	assertions.equal(
		resource_diagnostic.code,
		"insufficient_resources",
		"resource diagnostic is specific"
	)
	assertions.equal(
		resource_diagnostic.missing_resources.plank.required,
		8,
		"resource report includes requirement"
	)
	assertions.equal(
		resource_diagnostic.missing_resources.plank.available,
		3,
		"resource report includes inventory"
	)
	assertions.equal(
		resource_diagnostic.missing_resources.plank.missing,
		5,
		"resource report includes shortage"
	)
	assertions.equal(
		system.can_place(barn, 8, 8),
		resource_diagnostic.allowed,
		"can_place wraps placement diagnostic"
	)
	economy.holdings.plank = 10000
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

	economy.spend_succeeds = false
	var failed_result: Dictionary = system.try_place_building(well, 8, 8)
	var failed = failed_result.instance
	assertions.equal(failed, null, "failed spend returns no building")
	assertions.equal(failed_result.placed, false, "failed transaction reports rejection")
	assertions.equal(
		failed_result.diagnostic.code,
		"resource_commit_failed",
		"failed spend reports commit code"
	)
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

	grid.set_cell_state(22, 20, GridCell.State.FARMLAND)
	grid.set_cell_state(23, 21, GridCell.State.FARMLAND)
	var unfinished_barn = system.place_building(barn, 22, 20)
	assertions.equal(
		unfinished_barn.construction_stage,
		BuildingInstance.ConstructionStage.FOUNDATION,
		"multi-cell cancellation fixture remains unfinished"
	)
	var spend_calls_before_cancel := economy.spend_calls
	assertions.truthy(system.remove_building(unfinished_barn), "unfinished multi-cell building can be cancelled")
	assertions.equal(grid.get_cell(22, 20).state, GridCell.State.FARMLAND, "cancel restores first farmland snapshot")
	assertions.equal(grid.get_cell(23, 21).state, GridCell.State.FARMLAND, "cancel restores second farmland snapshot")
	assertions.equal(grid.get_cell(23, 20).state, GridCell.State.WASTELAND, "cancel restores first wasteland snapshot")
	assertions.equal(grid.get_cell(22, 21).state, GridCell.State.WASTELAND, "cancel restores second wasteland snapshot")
	assertions.equal(economy.spend_calls, spend_calls_before_cancel, "cancel does not alter spent-resource count")
	assertions.equal(economy.refund_calls, 0, "cancel does not refund resources")

	system.free()
	container.free()
	grid.free()
	game_data.free()
