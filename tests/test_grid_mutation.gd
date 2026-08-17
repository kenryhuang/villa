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


func _test_harvest_rollback_invariants(assertions: TestAssert) -> void:
	var malformed_fixture := _make_regrow_rollback_fixture()
	var malformed_grid: GridSystem = malformed_fixture.grid
	var malformed_before: Dictionary = malformed_fixture.before.duplicate(true)
	malformed_before.cell_state = FARMLAND
	assertions.truthy(
		not malformed_grid.rollback_crop_harvest(
			malformed_fixture.after,
			malformed_before,
			malformed_fixture.original
		),
		"rollback rejects non-null crop paired with non-planted before state"
	)
	assertions.equal(malformed_grid.get_crop_snapshot(6, 6), malformed_fixture.committed, "malformed before rejection is atomic")
	assertions.truthy(malformed_fixture.cell.crop_instance == malformed_fixture.original, "malformed before keeps current regrow instance")
	malformed_grid.free()

	var identity_fixture := _make_regrow_rollback_fixture()
	var identity_grid: GridSystem = identity_fixture.grid
	var impostor := CropInstance.new()
	impostor.crop_data = identity_fixture.data
	assertions.truthy(impostor.from_dict(identity_fixture.before.crop), "rollback impostor fixture restores crop data")
	assertions.truthy(
		not identity_grid.rollback_crop_harvest(identity_fixture.after, identity_fixture.before, impostor),
		"regrow rollback rejects a different crop instance"
	)
	assertions.equal(identity_grid.get_crop_snapshot(6, 6), identity_fixture.committed, "instance identity rejection is atomic")
	assertions.truthy(identity_fixture.cell.crop_instance == identity_fixture.original, "identity rejection preserves original current instance")
	identity_grid.free()

	var valid_fixture := _make_regrow_rollback_fixture()
	var valid_grid: GridSystem = valid_fixture.grid
	assertions.truthy(
		valid_grid.rollback_crop_harvest(valid_fixture.after, valid_fixture.before, valid_fixture.original),
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
	assertions.truthy(annual_grid.apply_crop_harvest(annual_before, annual_after), "annual rollback fixture applies harvest")
	var annual_committed := annual_grid.get_crop_snapshot(7, 7)
	var malformed_annual_before: Dictionary = annual_before.duplicate(true)
	malformed_annual_before.cell_state = FARMLAND
	assertions.truthy(
		not annual_grid.rollback_crop_harvest(annual_after, malformed_annual_before, annual_original),
		"annual rollback rejects malformed before state/crop pairing"
	)
	assertions.equal(annual_grid.get_crop_snapshot(7, 7), annual_committed, "malformed annual rollback is atomic")
	assertions.truthy(annual_grid.get_cell(7, 7).crop_instance == null, "malformed annual rollback keeps crop removed")

	annual_grid.free()


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
	grid.apply_crop_harvest(before, after)
	return {
		"grid": grid,
		"data": data,
		"cell": cell,
		"original": original,
		"before": before,
		"after": after,
		"committed": grid.get_crop_snapshot(6, 6),
	}
