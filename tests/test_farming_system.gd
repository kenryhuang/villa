extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")
const SeasonSystemScript = preload("res://scripts/systems/season_system.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")

const FARMLAND = 1
const PLANTED = 2


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
	var season = SeasonSystemScript.new()
	season.current_season = SeasonSystemScript.Season.SPRING
	farming.configure(grid, season, null)

	# Setup cell
	grid.set_cell_state(1, 1, FARMLAND)
	var crop_data = _make_crop_data("turnip", 3)

	# Plant
	var cell = grid.get_cell(1, 1)
	var instance = farming.plant(cell, crop_data)
	assertions.truthy(instance != null, "plant returns instance")
	assertions.equal(cell.state, PLANTED, "cell is planted")

	# Water and day change
	farming.water(cell)
	farming.on_day_changed(2)
	assertions.near(cell.crop_instance.growth_progress, 1.5, 0.001, "watered daily growth")
	assertions.truthy(not cell.watered, "cell water resets")

	# Second day - unwatered
	farming.on_day_changed(3)
	assertions.near(cell.crop_instance.growth_progress, 2.5, 0.001, "unwatered adds 1.0")

	# Third day - watered to mature
	farming.water(cell)
	farming.on_day_changed(4)
	assertions.near(cell.crop_instance.growth_progress, 3.0, 0.001, "watered growth clamps at maturity")
	assertions.truthy(cell.crop_instance.growth_progress >= crop_data.growth_days, "crop is mature")

	# Harvest
	var result = farming.harvest(cell)
	assertions.equal(result.exp, 10, "harvest returns xp")
	assertions.equal(cell.state, FARMLAND, "cell back to farmland")

	# Seasonal block test
	grid.set_cell_state(3, 3, FARMLAND)
	var winter_crop = _make_crop_data("summer_crop", 2)
	winter_crop.seasons.append(SeasonSystemScript.Season.SUMMER)
	var cell2 = grid.get_cell(3, 3)
	farming.plant(cell2, winter_crop)
	cell2.crop_instance.is_watered_today = true
	cell2.watered = true
	season.current_season = SeasonSystemScript.Season.WINTER
	farming.on_day_changed(5)
	assertions.equal(cell2.crop_instance.growth_progress, 0.0, "wrong season blocks growth")

	# Correct season allows growth
	season.current_season = SeasonSystemScript.Season.SUMMER
	cell2.crop_instance.is_watered_today = true
	farming.on_day_changed(6)
	assertions.near(cell2.crop_instance.growth_progress, 1.5, 0.001, "correct season allows growth")
	farming.free()
	season.free()
	grid.free()
