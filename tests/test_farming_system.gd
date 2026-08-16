extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")
const SeasonSystemScript = preload("res://scripts/systems/season_system.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")

const FARMLAND = 1
const PLANTED = 2


class CropEventBus:
	extends Node

	signal crop_grew(gx: int, gz: int, stage: int)
	signal crop_matured(gx: int, gz: int)

	var grew_events: Array[Dictionary] = []
	var matured_events: Array[Vector2i] = []

	func _init() -> void:
		crop_grew.connect(_on_crop_grew)
		crop_matured.connect(_on_crop_matured)

	func _on_crop_grew(gx: int, gz: int, stage: int) -> void:
		grew_events.append({"gx": gx, "gz": gz, "stage": stage})

	func _on_crop_matured(gx: int, gz: int) -> void:
		matured_events.append(Vector2i(gx, gz))


func _make_crop_data(
	id: String,
	growth_days: int,
	lifecycle_type: String = "annual",
	environment: String = "outdoor_or_greenhouse",
	regrow_days: int = 0
) -> CropData:
	var crop = CropDataScript.new()
	crop.crop_id = id
	crop.plant_item_id = id + "_seed"
	crop.crop_name = id.capitalize()
	crop.growth_days = growth_days
	crop.lifecycle_type = lifecycle_type
	crop.environment = environment
	crop.regrow_days = regrow_days
	crop.growth_form = "annual" if lifecycle_type == "annual_regrow" else lifecycle_type
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

	# Withered annuals do not recover automatically in a later valid season.
	season.current_season = SeasonSystemScript.Season.SUMMER
	cell2.crop_instance.is_watered_today = true
	farming.on_day_changed(6)
	assertions.near(cell2.crop_instance.growth_progress, 0.0, 0.001, "withered annual remains inert in a later valid season")
	assertions.equal(cell2.crop_instance.lifecycle_state, CropInstance.LifecycleState.WITHERED, "withered annual does not self-revive")
	farming.free()
	season.free()
	grid.free()

	_test_stage_only_growth_change(assertions)
	_test_environment_lifecycle_transitions(assertions)
	_test_deterministic_harvest_transaction(assertions)


func _test_stage_only_growth_change(assertions: TestAssert) -> void:
	var crop_data = _make_crop_data("stage_only", 3)
	var direct_instance := CropInstance.new()
	direct_instance.crop_data = crop_data
	assertions.truthy(
		direct_instance.advance_growth(),
		"stage-only growth reports a change"
	)
	assertions.equal(
		direct_instance.lifecycle_state,
		CropInstance.LifecycleState.GROWING,
		"stage-only growth remains growing"
	)
	assertions.truthy(not direct_instance.is_mature(), "stage-only growth is not mature")
	direct_instance.is_watered_today = true
	direct_instance.advance_growth()
	assertions.truthy(direct_instance.is_watered_today, "isolated growth preserves water for coordinator")

	var grid = GridSystemScript.new()
	var farming = FarmingSystemScript.new()
	var season = SeasonSystemScript.new()
	var event_bus := CropEventBus.new()
	season.current_season = SeasonSystemScript.Season.SPRING
	farming.configure(grid, season, null)
	farming._event_bus = event_bus
	grid.set_cell_state(5, 5, FARMLAND)
	var cell = grid.get_cell(5, 5)
	farming.plant(cell, crop_data)

	farming.on_day_changed(2)

	assertions.equal(
		event_bus.grew_events,
		[{"gx": 5, "gz": 5, "stage": 1}],
		"stage-only day change keeps crop_grew event"
	)
	assertions.equal(event_bus.matured_events, [], "stage-only day change emits no crop_matured")
	assertions.truthy(not cell.crop_instance.is_watered_today, "daily coordinator clears crop water")
	cell.crop_instance = null
	cell.state = GridCell.State.FARMLAND

	var mature_crop = _make_crop_data("mature_event", 1)
	grid.set_cell_state(6, 6, FARMLAND)
	var mature_cell = grid.get_cell(6, 6)
	farming.plant(mature_cell, mature_crop)
	farming.on_day_changed(3)
	assertions.equal(event_bus.matured_events, [Vector2i(6, 6)], "growing to mature emits crop_matured once")
	farming.on_day_changed(4)
	assertions.equal(event_bus.matured_events, [Vector2i(6, 6)], "mature crop emits no duplicate crop_matured")
	event_bus.free()
	farming.free()
	season.free()
	grid.free()


func _test_environment_lifecycle_transitions(assertions: TestAssert) -> void:
	var grid = GridSystemScript.new()
	var farming = FarmingSystemScript.new()
	var season = SeasonSystemScript.new()
	season.current_season = SeasonSystemScript.Season.WINTER
	farming.configure(grid, season, null)

	grid.set_cell_state(11, 11, FARMLAND)
	var annual: CropData = _make_crop_data("summer_annual", 3)
	annual.seasons.assign([SeasonSystemScript.Season.SUMMER])
	var annual_cell := grid.get_cell(11, 11)
	var annual_instance: CropInstance = farming.plant(annual_cell, annual)
	annual_instance.is_watered_today = true
	annual_cell.watered = true
	farming.on_day_changed(2)
	assertions.equal(annual_instance.lifecycle_state, CropInstance.LifecycleState.WITHERED, "wrong-season annual withers before growth")
	assertions.near(annual_instance.growth_progress, 0.0, 0.001, "withering grants no invalid daily progress")
	assertions.truthy(not annual_cell.watered and not annual_instance.is_watered_today, "withered daily decision clears water")

	grid.set_cell_state(12, 12, FARMLAND)
	var bush: CropData = _make_crop_data("summer_bush", 4, "bush", "outdoor_or_greenhouse", 2)
	bush.seasons.assign([SeasonSystemScript.Season.SUMMER])
	var bush_cell := grid.get_cell(12, 12)
	var bush_instance: CropInstance = farming.plant(bush_cell, bush)
	bush_instance.set_growth_state(1.0, CropInstance.LifecycleState.GROWING)
	farming.on_day_changed(3)
	assertions.equal(bush_instance.lifecycle_state, CropInstance.LifecycleState.DORMANT, "wrong-season bush becomes dormant")
	assertions.near(bush_instance.growth_progress, 1.0, 0.001, "dormancy preserves progress")
	var dormant_visual := farming.get_crop_visual(bush_cell)
	assertions.equal(dormant_visual.get_meta("crop_stage", -1), 2, "dormant visual uses stage two")
	assertions.equal(dormant_visual.get_meta("lifecycle_state", -1), CropInstance.LifecycleState.DORMANT, "dormant visual records state treatment")
	season.current_season = SeasonSystemScript.Season.SUMMER
	farming.on_day_changed(4)
	assertions.equal(bush_instance.lifecycle_state, CropInstance.LifecycleState.GROWING, "in-season dormant bush restores active state")
	assertions.near(bush_instance.growth_progress, 2.0, 0.001, "restored bush grows on the same daily tick")

	grid.set_cell_state(13, 13, FARMLAND)
	var greenhouse_annual: CropData = _make_crop_data("greenhouse_annual", 3)
	greenhouse_annual.seasons.assign([SeasonSystemScript.Season.SPRING])
	var greenhouse_cell := grid.get_cell(13, 13)
	var greenhouse_instance: CropInstance = farming.plant(greenhouse_cell, greenhouse_annual)
	season.current_season = SeasonSystemScript.Season.WINTER
	farming.set_greenhouse_cells([], [Vector2i(13, 13)])
	greenhouse_instance.is_watered_today = true
	greenhouse_cell.watered = true
	farming.on_day_changed(5)
	assertions.equal(greenhouse_instance.lifecycle_state, CropInstance.LifecycleState.GROWING, "paused greenhouse freezes lifecycle")
	assertions.near(greenhouse_instance.growth_progress, 0.0, 0.001, "paused greenhouse freezes progress")
	assertions.truthy(not greenhouse_cell.watered and not greenhouse_instance.is_watered_today, "paused greenhouse clears daily water")
	farming.set_greenhouse_cells([Vector2i(13, 13)])
	farming.on_day_changed(6)
	assertions.near(greenhouse_instance.growth_progress, 1.0, 0.001, "active greenhouse ignores season")
	greenhouse_instance.set_growth_state(3.0, CropInstance.LifecycleState.MATURE)
	farming.set_greenhouse_cells([], [Vector2i(13, 13)])
	var paused_mature_preview: Dictionary = farming.preview_harvest(greenhouse_cell)
	assertions.truthy(not paused_mature_preview.is_empty(), "maintenance-paused greenhouse keeps mature crop harvestable")
	farming.on_day_changed(7)
	assertions.equal(greenhouse_instance.lifecycle_state, CropInstance.LifecycleState.MATURE, "paused mature crop remains stable")
	assertions.near(greenhouse_instance.growth_progress, 3.0, 0.001, "paused mature crop keeps progress")

	grid.set_cell_state(14, 14, FARMLAND)
	var lemon: CropData = _make_crop_data("lemon", 3, "tree", "greenhouse_only", 1)
	var lemon_cell := grid.get_cell(14, 14)
	farming.set_greenhouse_cells([Vector2i(14, 14)])
	assertions.equal(greenhouse_instance.lifecycle_state, CropInstance.LifecycleState.WITHERED, "ordinary annual is immediately reassessed after greenhouse removal")
	var lemon_instance: CropInstance = farming.plant(lemon_cell, lemon)
	farming.on_day_changed(8)
	assertions.near(lemon_instance.growth_progress, 1.0, 0.001, "greenhouse-only crop grows in active greenhouse")
	farming.set_greenhouse_cells([])
	assertions.equal(lemon_instance.lifecycle_state, CropInstance.LifecycleState.WITHERED, "greenhouse demolition immediately withers greenhouse-only crop")
	assertions.equal(farming.get_crop_visual(lemon_cell).get_meta("lifecycle_state", -1), CropInstance.LifecycleState.WITHERED, "withered visual records dry state treatment")
	assertions.truthy(farming.clear_withered(lemon_cell), "withered crop clears without harvest")
	assertions.equal(lemon_cell.state, GridCell.State.FARMLAND, "withered clearing restores farmland")
	assertions.truthy(lemon_cell.crop_instance == null, "withered clearing removes crop instance")
	assertions.truthy(not farming.clear_withered(lemon_cell), "clearing an empty plot is rejected")

	var family_index := 0
	for fixture in [
		{"id": "annual_regrow_transition", "lifecycle": "annual_regrow", "regrow": 1, "expected": CropInstance.LifecycleState.WITHERED},
		{"id": "tree_transition", "lifecycle": "tree", "regrow": 1, "expected": CropInstance.LifecycleState.DORMANT},
		{"id": "vine_transition", "lifecycle": "vine", "regrow": 1, "expected": CropInstance.LifecycleState.DORMANT},
	]:
		var gx := 16 + family_index
		var gz := 16
		family_index += 1
		grid.set_cell_state(gx, gz, FARMLAND)
		var family_crop: CropData = _make_crop_data(fixture.id, 4, fixture.lifecycle, "outdoor_or_greenhouse", fixture.regrow)
		family_crop.seasons.assign([SeasonSystemScript.Season.SUMMER])
		var family_instance: CropInstance = farming.plant(grid.get_cell(gx, gz), family_crop)
		family_instance.set_growth_state(1.0, CropInstance.LifecycleState.GROWING)
		season.current_season = SeasonSystemScript.Season.WINTER
		farming.on_day_changed(9)
		assertions.equal(family_instance.lifecycle_state, fixture.expected, "%s follows explicit wrong-season lifecycle" % fixture.lifecycle)
		assertions.near(family_instance.growth_progress, 1.0, 0.001, "%s transition preserves progress" % fixture.lifecycle)

	farming.free()
	season.free()
	grid.free()


func _test_deterministic_harvest_transaction(assertions: TestAssert) -> void:
	var grid = GridSystemScript.new()
	var farming = FarmingSystemScript.new()
	farming.configure(grid, null, null)
	grid.set_cell_state(15, 15, FARMLAND)
	var crop: CropData = _make_crop_data("preview_tomato", 4, "annual_regrow", "outdoor_or_greenhouse", 2)
	crop.yield_min = 2
	crop.yield_max = 3
	var cell := grid.get_cell(15, 15)
	var instance: CropInstance = farming.plant(cell, crop)
	instance.set_growth_state(4.0, CropInstance.LifecycleState.MATURE)
	var first: Dictionary = farming.preview_harvest(cell)
	var second: Dictionary = farming.preview_harvest(cell)
	assertions.equal(first, second, "unchanged harvest previews are exactly deterministic")
	assertions.equal(instance.harvest_count, 0, "preview and capacity-like rejection do not change harvest count")
	assertions.equal(first.get("post_growth_progress", -1.0), 2.0, "preview includes regrowth progress")
	assertions.equal(first.get("post_lifecycle_state", -1), CropInstance.LifecycleState.GROWING, "preview includes post lifecycle")
	assertions.equal(first.get("post_cell_state", -1), GridCell.State.PLANTED, "preview includes post cell state")
	assertions.truthy(first.get("before", {}).get("crop", null) is Dictionary, "preview includes a stable before snapshot")

	var altered := first.duplicate(true)
	altered.exp = int(altered.exp) + 1
	var before_altered: Dictionary = grid.get_crop_snapshot(15, 15)
	assertions.truthy(farming.commit_harvest(cell, altered).is_empty(), "altered preview is rejected")
	assertions.equal(grid.get_crop_snapshot(15, 15), before_altered, "altered preview rejection is atomic")
	var committed: Dictionary = farming.commit_harvest(cell, first)
	assertions.equal(committed.get("items", {}), first.items, "commit returns previewed items")
	assertions.equal(instance.harvest_count, 1, "successful commit increments harvest count")
	assertions.near(instance.growth_progress, 2.0, 0.001, "successful regrow commit applies previewed progress")
	assertions.equal(instance.lifecycle_state, CropInstance.LifecycleState.GROWING, "successful regrow commit applies previewed lifecycle")
	assertions.truthy(farming.commit_harvest(cell, first).is_empty(), "stale preview is rejected after state changes")
	assertions.truthy(not grid.has_method("preview_harvest"), "GridSystem exposes no harvest preview domain API")
	assertions.truthy(not grid.has_method("harvest_crop"), "GridSystem exposes no harvest commit domain API")

	farming.free()
	grid.free()
