extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const GridCellScript = preload("res://scripts/data/grid_cell.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")

# GridCell.State enum values
const WASTELAND = 0
const FARMLAND = 1
const PLANTED = 2
const BUILDING = 3


func _make_crop_data(id: String, growth_days: int):
	var crop = CropDataScript.new()
	crop.crop_id = id
	crop.crop_name = id.capitalize()
	crop.growth_days = growth_days
	crop.exp_reward = 10
	crop.stage_textures.append("seed")
	crop.stage_textures.append("sprout")
	crop.stage_textures.append("growing")
	crop.stage_textures.append("mature")
	return crop


func run(assertions: TestAssert) -> void:
	var grid = GridSystemScript.new()
	var farming = FarmingSystemScript.new()
	farming.configure(grid, null, null)
	var crop_data = _make_crop_data("turnip", 3)

	# State transitions
	assertions.truthy(grid.set_cell_state(2, 2, FARMLAND), "cultivates wasteland")
	assertions.equal(grid.get_cell(2, 2).state, FARMLAND, "cell is farmland")
	assertions.truthy(not grid.set_cell_state(2, 2, PLANTED), "cannot skip planting")

	# Planting
	var crop = grid.plant_crop(2, 2, crop_data)
	assertions.truthy(crop != null, "planting returns instance")
	assertions.equal(grid.get_cell(2, 2).state, PLANTED, "cell remains planted")

	# Watering
	assertions.truthy(grid.water_cell(2, 2), "planting can be watered")
	assertions.truthy(grid.get_cell(2, 2).watered, "cell watered flag set")
	assertions.truthy(grid.get_cell(2, 2).crop_instance != null and grid.get_cell(2, 2).crop_instance.is_watered_today, "crop watered flag set")

	# Cannot plant on non-farmland
	assertions.truthy(grid.plant_crop(2, 2, crop_data) == null, "cannot plant on planted cell")
	assertions.truthy(grid.plant_crop(5, 5, crop_data) == null, "cannot plant on wasteland")

	# Invalid transitions
	assertions.truthy(not grid.set_cell_state(2, 2, WASTELAND), "planted cannot go to wasteland")
	assertions.truthy(not grid.set_cell_state(2, 2, BUILDING), "planted cannot go to building")

	# Harvest not mature
	var result: Dictionary = farming.harvest(grid.get_cell(2, 2))
	assertions.truthy(result.is_empty(), "cannot harvest immature crop")

	# Harvest mature crop
	if grid.get_cell(2, 2).crop_instance:
		grid.get_cell(2, 2).crop_instance.set_growth_state(3.0, CropInstance.LifecycleState.MATURE)
		result = farming.harvest(grid.get_cell(2, 2))
		assertions.truthy(not result.is_empty(), "harvest mature crop succeeds")
		assertions.equal(result.exp, 10, "harvest returns exp")
		assertions.equal(result.items, {"turnip": 1}, "harvest returns crop quantity")
		assertions.equal(grid.get_cell(2, 2).state, FARMLAND, "cell returns to farmland after harvest")
		assertions.truthy(grid.get_cell(2, 2).crop_instance == null, "crop instance cleared")

	# Water farmland
	assertions.truthy(grid.water_cell(2, 2), "farmland can be watered")
	assertions.truthy(not grid.water_cell(5, 5), "wasteland cannot be watered")
	farming.free()
	grid.free()
	_test_harvest_rollback_invariants(assertions)
	_test_harvest_mutation_receipt_identity(assertions)
	_test_state_replacement_settles_harvest_receipt(assertions)


func _test_harvest_rollback_invariants(assertions: TestAssert) -> void:
	var forged_fixture := _make_regrow_rollback_fixture()
	var forged_grid: GridSystem = forged_fixture.grid
	assertions.truthy(
		not forged_grid.rollback_crop_harvest_transaction(RefCounted.new(), forged_fixture.original),
		"rollback rejects a forged mutation receipt"
	)
	assertions.equal(forged_grid.get_crop_snapshot(6, 6), forged_fixture.committed, "forged receipt rejection is atomic")
	assertions.truthy(forged_fixture.cell.crop_instance == forged_fixture.original, "forged receipt keeps current regrow instance")
	forged_grid.free()

	var identity_fixture := _make_regrow_rollback_fixture()
	var identity_grid: GridSystem = identity_fixture.grid
	var impostor := CropInstance.new()
	impostor.crop_data = identity_fixture.data
	assertions.truthy(impostor.from_dict(identity_fixture.before.crop), "rollback impostor fixture restores crop data")
	assertions.truthy(
		not identity_grid.rollback_crop_harvest_transaction(identity_fixture.receipt, impostor),
		"regrow rollback rejects a different crop instance"
	)
	assertions.equal(identity_grid.get_crop_snapshot(6, 6), identity_fixture.committed, "instance identity rejection is atomic")
	assertions.truthy(identity_fixture.cell.crop_instance == identity_fixture.original, "identity rejection preserves original current instance")
	identity_grid.free()

	var valid_fixture := _make_regrow_rollback_fixture()
	var valid_grid: GridSystem = valid_fixture.grid
	assertions.truthy(
		valid_grid.rollback_crop_harvest_transaction(valid_fixture.receipt, valid_fixture.original),
		"valid regrow rollback restores"
	)
	assertions.equal(valid_grid.get_crop_snapshot(6, 6), valid_fixture.before, "valid regrow rollback restores exact snapshot")
	valid_grid.free()

	var annual_grid = GridSystemScript.new()
	var annual_data = _make_crop_data("grain", 3)
	annual_grid.set_cell_state(7, 7, FARMLAND)
	var annual_original: CropInstance = annual_grid.plant_crop(7, 7, annual_data)
	annual_original.set_growth_state(3.0, CropInstance.LifecycleState.MATURE)
	var annual_before := annual_grid.get_crop_snapshot(7, 7)
	var annual_after := {
		"gx": 7,
		"gz": 7,
		"cell_state": FARMLAND,
		"watered": false,
		"crop": null,
	}
	var annual_receipt := annual_grid.apply_crop_harvest_transaction(annual_before, annual_after)
	assertions.truthy(annual_receipt is RefCounted, "annual rollback fixture applies harvest")
	var annual_committed := annual_grid.get_crop_snapshot(7, 7)
	assertions.truthy(
		not annual_grid.rollback_crop_harvest_transaction(RefCounted.new(), annual_original),
		"annual rollback rejects a forged receipt"
	)
	assertions.equal(annual_grid.get_crop_snapshot(7, 7), annual_committed, "malformed annual rollback is atomic")
	assertions.truthy(annual_grid.get_cell(7, 7).crop_instance == null, "malformed annual rollback keeps crop removed")

	annual_grid.free()


func _test_harvest_mutation_receipt_identity(assertions: TestAssert) -> void:
	var grid = GridSystemScript.new()
	var data = _make_crop_data("grain", 3)
	grid.set_cell_state(8, 8, FARMLAND)
	var original: CropInstance = grid.plant_crop(8, 8, data)
	original.set_growth_state(3.0, CropInstance.LifecycleState.MATURE)
	var before := grid.get_crop_snapshot(8, 8)
	var after := {
		"gx": 8,
		"gz": 8,
		"cell_state": FARMLAND,
		"watered": false,
		"crop": null,
	}
	assertions.truthy(
		grid.has_method("apply_crop_harvest_transaction"),
		"grid exposes receipt-based harvest mutation"
	)
	if not grid.has_method("apply_crop_harvest_transaction"):
		grid.free()
		return
	var receipt: Variant = grid.call("apply_crop_harvest_transaction", before, after)
	assertions.truthy(receipt is RefCounted, "harvest apply returns an unforgeable receipt")
	var impostor := CropInstance.new()
	impostor.crop_data = data
	assertions.truthy(impostor.from_dict(before.crop), "annual impostor has serialized-identical state")
	assertions.truthy(
		not grid.call("rollback_crop_harvest_transaction", receipt, impostor),
		"annual rollback rejects serialized-identical impostor identity"
	)
	assertions.equal(grid.get_cell(8, 8).crop_instance, null, "impostor rejection leaves annual mutation unchanged")
	assertions.truthy(
		grid.call("rollback_crop_harvest_transaction", receipt, original),
		"exact receipt and original instance restore annual crop"
	)
	assertions.truthy(grid.get_cell(8, 8).crop_instance == original, "valid receipt restores original identity")
	assertions.equal(grid.get_crop_snapshot(8, 8), before, "valid receipt restores exact snapshot")
	var abandoned_receipt: Variant = grid.apply_crop_harvest_transaction(before, after)
	assertions.truthy(abandoned_receipt is RefCounted, "abandoned receipt fixture applies")
	abandoned_receipt = null
	var recovered_receipt: Variant = grid.apply_crop_harvest_transaction(before, after)
	assertions.truthy(recovered_receipt is RefCounted, "next mutation recovers an abandoned receipt")
	assertions.truthy(
		grid.rollback_crop_harvest_transaction(recovered_receipt, original),
		"transaction after receipt recovery rolls back"
	)
	assertions.equal(grid.get_crop_snapshot(8, 8), before, "receipt recovery restores exact annual snapshot")
	grid.free()


func _test_state_replacement_settles_harvest_receipt(assertions: TestAssert) -> void:
	for replacement in ["reset", "from_dict"]:
		var grid = GridSystemScript.new()
		var data = _make_crop_data("grain", 3)
		grid.set_cell_state(9, 9, FARMLAND)
		var original: CropInstance = grid.plant_crop(9, 9, data)
		original.set_growth_state(3.0, CropInstance.LifecycleState.MATURE)
		var before := grid.get_crop_snapshot(9, 9)
		var after := {
			"gx": 9,
			"gz": 9,
			"cell_state": FARMLAND,
			"watered": false,
			"crop": null,
		}
		var old_receipt: Variant = grid.apply_crop_harvest_transaction(before, after)
		assertions.truthy(old_receipt is RefCounted, "%s fixture retains a live receipt" % replacement)
		if replacement == "reset":
			grid.reset_state()
		else:
			assertions.truthy(
				grid.from_dict({
					"version": GridSystemScript.SERIALIZATION_VERSION,
					"cells": [{
						"gx": 9,
						"gz": 9,
						"state": FARMLAND,
						"watered": false,
					}],
				}),
				"from_dict replacement succeeds with a retained receipt"
			)
		assertions.truthy(
			not grid.owns_crop_harvest_transaction(old_receipt),
			"%s invalidates the old receipt" % replacement
		)
		grid.set_cell_state(9, 9, FARMLAND)
		var next: CropInstance = grid.plant_crop(9, 9, data)
		assertions.truthy(next != null, "%s replacement accepts a new crop" % replacement)
		next.set_growth_state(3.0, CropInstance.LifecycleState.MATURE)
		var next_before := grid.get_crop_snapshot(9, 9)
		var next_receipt: Variant = grid.apply_crop_harvest_transaction(next_before, after)
		assertions.truthy(next_receipt is RefCounted, "%s replacement accepts a new harvest transaction" % replacement)
		if next_receipt != null:
			assertions.truthy(
				grid.rollback_crop_harvest_transaction(next_receipt, next),
				"%s replacement leaves receipt lifecycle usable" % replacement
			)
		grid.free()


func _make_regrow_rollback_fixture() -> Dictionary:
	var grid = GridSystemScript.new()
	var data = _make_crop_data("tomato", 4)
	data.lifecycle_type = "annual_regrow"
	grid.set_cell_state(6, 6, FARMLAND)
	var cell := grid.get_cell(6, 6)
	var original: CropInstance = grid.plant_crop(6, 6, data)
	original.set_growth_state(4.0, CropInstance.LifecycleState.MATURE)
	var before := grid.get_crop_snapshot(6, 6)
	var post_crop: Dictionary = before.crop.duplicate(true)
	post_crop.growth_progress = 2.0
	post_crop.lifecycle_state = CropInstance.LifecycleState.GROWING
	post_crop.harvest_count = 1
	post_crop.is_watered_today = false
	var after := {
		"gx": 6,
		"gz": 6,
		"cell_state": PLANTED,
		"watered": false,
		"crop": post_crop,
	}
	var receipt := grid.apply_crop_harvest_transaction(before, after)
	return {
		"grid": grid,
		"data": data,
		"cell": cell,
		"original": original,
		"before": before,
		"after": after,
		"receipt": receipt,
		"committed": grid.get_crop_snapshot(6, 6),
	}
