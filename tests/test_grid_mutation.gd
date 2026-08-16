extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const GridCellScript = preload("res://scripts/data/grid_cell.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")

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
	var result = grid.harvest_crop(2, 2)
	assertions.truthy(result.is_empty(), "cannot harvest immature crop")

	# Harvest mature crop
	if grid.get_cell(2, 2).crop_instance:
		grid.get_cell(2, 2).crop_instance.growth_progress = 3.0
		grid.get_cell(2, 2).crop_instance.set_lifecycle_state(CropInstance.LifecycleState.MATURE)
		result = grid.harvest_crop(2, 2)
		assertions.truthy(not result.is_empty(), "harvest mature crop succeeds")
		assertions.equal(result.exp, 10, "harvest returns exp")
		assertions.equal(result.items, {"turnip": 1}, "harvest returns crop quantity")
		assertions.equal(grid.get_cell(2, 2).state, FARMLAND, "cell returns to farmland after harvest")
		assertions.truthy(grid.get_cell(2, 2).crop_instance == null, "crop instance cleared")

	# Water farmland
	assertions.truthy(grid.water_cell(2, 2), "farmland can be watered")
	assertions.truthy(not grid.water_cell(5, 5), "wasteland cannot be watered")
	grid.free()
