extends RefCounted

const CropDataScript = preload("res://scripts/data/crop_data.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const SeasonSystemScript = preload("res://scripts/systems/season_system.gd")


func run(assertions: TestAssert) -> void:
	var crop: CropData = CropDataScript.new()
	crop.crop_id = "timed_crop"
	crop.plant_item_id = "timed_seed"
	crop.crop_name = "Timed"
	crop.growth_days = 3
	crop.lifecycle_type = "annual"
	crop.environment = "outdoor_or_greenhouse"
	crop.growth_form = "annual"
	crop.stage_textures.assign(["seed", "sprout", "growing", "mature"])
	var has_duration := _has_property(crop, "growth_duration_minutes")
	assertions.truthy(has_duration, "crop data exposes game-minute growth duration")
	if not has_duration:
		return
	crop.set("growth_duration_minutes", 108)

	var grid := GridSystemScript.new()
	var season := SeasonSystemScript.new()
	season.current_season = SeasonSystemScript.Season.SPRING
	var farming := FarmingSystemScript.new()
	farming.configure(grid, season, null)
	assertions.truthy(
		farming.has_method("advance_growth_minutes"),
		"farming exposes continuous minute growth"
	)
	if not farming.has_method("advance_growth_minutes"):
		farming.free()
		season.free()
		grid.free()
		return

	grid.set_cell_state(1, 1, GridCell.State.FARMLAND)
	var dry_cell := grid.get_cell(1, 1)
	var dry_crop: CropInstance = farming.plant(dry_cell, crop)
	farming.call("advance_growth_minutes", 0)
	assertions.near(dry_crop.growth_progress, 0.0, 0.0001, "zero elapsed minutes preserve growth")
	farming.call("advance_growth_minutes", 107)
	assertions.truthy(not dry_crop.is_mature(), "unwatered crop waits through minute 107")
	farming.call("advance_growth_minutes", 1)
	assertions.truthy(dry_crop.is_mature(), "unwatered crop matures at minute 108")

	grid.set_cell_state(2, 2, GridCell.State.FARMLAND)
	var wet_cell := grid.get_cell(2, 2)
	var wet_crop: CropInstance = farming.plant(wet_cell, crop)
	wet_cell.watered = true
	wet_crop.is_watered_today = true
	farming.call("advance_growth_minutes", 71)
	assertions.truthy(not wet_crop.is_mature(), "watered crop waits through minute 71")
	farming.call("advance_growth_minutes", 1)
	assertions.truthy(wet_crop.is_mature(), "watered crop matures at minute 72")

	assertions.truthy(
		farming.has_method("sync_growth_clock")
		and farming.has_method("advance_growth_to_absolute_minute"),
		"farming exposes an absolute game-minute cursor"
	)
	if farming.has_method("sync_growth_clock") and farming.has_method("advance_growth_to_absolute_minute"):
		grid.set_cell_state(3, 3, GridCell.State.FARMLAND)
		var clock_cell := grid.get_cell(3, 3)
		var clock_crop: CropInstance = farming.plant(clock_cell, crop)
		farming.call("sync_growth_clock", 500)
		farming.call("advance_growth_to_absolute_minute", 607)
		assertions.truthy(not clock_crop.is_mature(), "absolute cursor preserves minute 107")
		farming.call("advance_growth_to_absolute_minute", 608)
		assertions.truthy(clock_crop.is_mature(), "absolute cursor matures on minute 108")
		farming.call("advance_growth_to_absolute_minute", 100)
		assertions.near(clock_crop.growth_progress, 3.0, 0.0001, "backward clock resync does not rewind crop")

	var regrow: CropData = CropDataScript.new()
	regrow.crop_id = "timed_tomato"
	regrow.plant_item_id = "timed_tomato_seed"
	regrow.crop_name = "Timed Tomato"
	regrow.growth_days = 4
	regrow.lifecycle_type = "annual_regrow"
	regrow.environment = "outdoor_or_greenhouse"
	regrow.growth_form = "annual"
	regrow.regrow_days = 2
	regrow.growth_duration_minutes = 108
	regrow.regrow_duration_minutes = 108
	regrow.stage_textures.assign(["seed", "sprout", "growing", "mature"])
	grid.set_cell_state(4, 4, GridCell.State.FARMLAND)
	var regrow_cell := grid.get_cell(4, 4)
	var regrow_crop: CropInstance = farming.plant(regrow_cell, regrow)
	regrow_crop.set_growth_state(4.0, CropInstance.LifecycleState.MATURE)
	var preview := farming.preview_harvest(regrow_cell)
	assertions.truthy(bool(preview.get("regrowing", false)), "repeat crop harvest reports regrowth")
	assertions.equal(preview.get("post_cell_state", -1), GridCell.State.PLANTED, "repeat crop remains planted")
	assertions.truthy(preview.get("post_crop") is Dictionary, "repeat crop preserves a crop snapshot")
	var harvested := farming.harvest(regrow_cell, preview)
	assertions.truthy(not harvested.is_empty(), "repeat crop harvest commits")
	assertions.equal(regrow_cell.state, GridCell.State.PLANTED, "repeat crop cell stays planted after harvest")
	assertions.truthy(regrow_cell.crop_instance != null, "repeat crop instance survives harvest")
	if regrow_cell.crop_instance != null:
		assertions.near(regrow_cell.crop_instance.growth_progress, 0.0, 0.0001, "repeat cycle restarts at zero")
		assertions.equal(regrow_cell.crop_instance.harvest_count, 1, "repeat harvest count increments")

	farming.free()
	season.free()
	grid.free()


func _has_property(value: Object, property_name: String) -> bool:
	for record in value.get_property_list():
		if str(record.get("name", "")) == property_name:
			return true
	return false
