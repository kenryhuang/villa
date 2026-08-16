extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const TerrainBuilderScript = preload("res://scripts/world/terrain_builder.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")


func run(assertions: TestAssert) -> void:
	var grid = GridSystemScript.new()

	# World to grid conversion
	assertions.equal(grid.world_to_grid(-18.0, -14.0), Vector2i(0, 0), "world origin maps first cell")
	assertions.equal(grid.world_to_grid(17.999, 13.999), Vector2i(35, 27), "upper edge maps final cell")
	assertions.equal(grid.grid_to_world(0, 0), Vector2(-17.5, -13.5), "grid center maps world")
	assertions.equal(grid.grid_to_world(35, 27), Vector2(17.5, 13.5), "last cell center")

	# Cell key uniqueness
	assertions.truthy(GridSystemScript.cell_key(0, 0) != GridSystemScript.cell_key(0, 1), "keys differ for adjacent z")
	assertions.truthy(GridSystemScript.cell_key(0, 0) != GridSystemScript.cell_key(1, 0), "keys differ for adjacent x")
	assertions.equal(GridSystemScript.cell_key(3, 4), 3004, "cell key formula")

	# Rect bounds
	assertions.equal(grid.get_cells_in_rect(34, 26, 2, 2).size(), 4, "rect includes valid corner cells")
	assertions.equal(grid.get_cells_in_rect(35, 27, 2, 2).size(), 1, "rect clips to bounds")
	assertions.equal(grid.get_cells_in_rect(0, 0, 1, 1).size(), 1, "single cell rect")

	# Out of bounds
	assertions.truthy(grid.get_cell(-1, 0) == null, "negative x is null")
	assertions.truthy(grid.get_cell(36, 0) == null, "beyond width is null")
	assertions.truthy(grid.get_cell(0, 28) == null, "beyond depth is null")

	# Rect order (gz then gx)
	var rect_cells := grid.get_cells_in_rect(0, 0, 2, 2)
	assertions.equal(rect_cells.size(), 4, "2x2 rect has 4 cells")
	assertions.equal(rect_cells[0].gz, 0, "first row first")
	assertions.equal(rect_cells[2].gz, 1, "second row after first")
	grid.free()

	_test_lifecycle_serialization_version(assertions)


func _test_lifecycle_serialization_version(assertions: TestAssert) -> void:
	var grid = GridSystemScript.new()
	var crop = CropDataScript.new()
	crop.crop_id = "grid_lifecycle_crop"
	crop.growth_days = 3
	grid.set_cell_state(2, 2, GridCell.State.FARMLAND)
	var instance = grid.plant_crop(2, 2, crop)
	var saved: Dictionary = grid.to_dict()

	assertions.equal(instance.lifecycle_state, CropInstance.LifecycleState.GROWING, "new grid plant is explicitly growing")
	assertions.equal(saved.get("version", -1), 2, "grid serialization uses canonical version two")
	assertions.equal(
		saved.cells[0].crop.get("lifecycle_state", -1),
		0,
		"grid serialization includes growing lifecycle state"
	)
	var json_saved: Variant = JSON.parse_string(JSON.stringify(saved))
	assertions.equal(
		json_saved.cells[0].crop.get("lifecycle_state", -1),
		0.0,
		"grid JSON round trip preserves lifecycle state"
	)

	var missing_lifecycle: Dictionary = saved.duplicate(true)
	missing_lifecycle.cells[0].crop.erase("lifecycle_state")
	assertions.truthy(
		not grid.validate_dict(missing_lifecycle),
		"current grid data missing lifecycle state is rejected"
	)
	assertions.truthy(
		not grid.validate_dict({"version": 1, "cells": []}),
		"version one grid data is rejected for deferred SaveManager migration"
	)
	for invalid_version in [
		true,
		2.5,
		EconomyLimitsScript.MAX_SAFE_INTEGER + 1,
		-EconomyLimitsScript.MAX_SAFE_INTEGER - 1,
		EconomyLimitsScript.MAX_SAFE_INTEGER + 1.0,
		-float(EconomyLimitsScript.MAX_SAFE_INTEGER) - 1.0,
	]:
		assertions.truthy(
			not grid.validate_dict({"version": invalid_version, "cells": []}),
			"unsafe or non-integral grid version rejects"
		)
	var base_entry := {"gx": 0, "gz": 0, "state": GridCell.State.FARMLAND, "watered": false}
	for field in ["gx", "gz", "state"]:
		for invalid_integer in [
			true,
			1.5,
			EconomyLimitsScript.MAX_SAFE_INTEGER + 1,
			-EconomyLimitsScript.MAX_SAFE_INTEGER - 1,
			EconomyLimitsScript.MAX_SAFE_INTEGER + 1.0,
			-float(EconomyLimitsScript.MAX_SAFE_INTEGER) - 1.0,
		]:
			var invalid_entry: Dictionary = base_entry.duplicate(true)
			invalid_entry[field] = invalid_integer
			assertions.truthy(
				not grid.validate_dict({"version": 2, "cells": [invalid_entry]}),
				"unsafe or non-integral grid %s rejects" % field
			)
	assertions.truthy(instance != null, "lifecycle serialization fixture plants")
	grid.free()
