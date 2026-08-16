extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")
const SeasonSystemScript = preload("res://scripts/systems/season_system.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")
const FarmStorageSystemScript = preload("res://scripts/systems/farm_storage_system.gd")

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


class HarvestEventBus:
	extends Node

	signal cell_state_changed(gx: int, gz: int, new_state: int)
	signal crop_planted(gx: int, gz: int, crop_id: String)
	signal crop_harvested(gx: int, gz: int, crop_id: String)

	var cell_events: Array[Dictionary] = []
	var harvest_events: Array[Dictionary] = []

	func _init() -> void:
		cell_state_changed.connect(_on_cell_state_changed)
		crop_harvested.connect(_on_crop_harvested)

	func _on_cell_state_changed(gx: int, gz: int, new_state: int) -> void:
		cell_events.append({"gx": gx, "gz": gz, "state": new_state})

	func _on_crop_harvested(gx: int, gz: int, crop_id: String) -> void:
		harvest_events.append({"gx": gx, "gz": gz, "crop_id": crop_id})


class HarvestSeedState:
	extends RefCounted

	var harvest_seed := 1
	var exp_total := 0

	func add_exp(amount: int) -> bool:
		exp_total += amount
		return true


class ReentrantHarvestObserver:
	extends RefCounted

	var farming: FarmingSystem
	var cell: GridCell
	var replacement: CropData
	var state: HarvestSeedState
	var observed_exp := -1
	var observed_cell_state := -1
	var observed_visual_state := -1
	var replanted: CropInstance

	func on_harvested(_gx: int, _gz: int, _crop_id: String) -> void:
		observed_exp = state.exp_total
		observed_cell_state = cell.state
		var visual := farming.get_crop_visual(cell)
		observed_visual_state = int(visual.get_meta("lifecycle_state", -1)) if visual else -1
		replanted = farming.plant(cell, replacement)


class ZeroCapacity:
	extends RefCounted

	func provide() -> int:
		return 0


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
	_test_save_seed_controls_deterministic_yield(assertions)
	_test_exact_harvest_post_states(assertions)
	_test_deterministic_harvest_transaction(assertions)
	_test_reentrant_harvest_observes_final_state(assertions)


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
	assertions.equal(
		_fallback_color(dormant_visual),
		Color(0.6, 0.8, 0.2) * Color(0.68, 0.72, 0.65, 1.0),
		"dormant fallback material is visibly desaturated and dimmed"
	)
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
	assertions.equal(
		_fallback_color(farming.get_crop_visual(lemon_cell)),
		Color(0.2, 0.7, 0.2) * Color(0.82, 0.68, 0.38, 1.0),
		"withered fallback material uses the dry yellow modulation"
	)
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


func _test_save_seed_controls_deterministic_yield(assertions: TestAssert) -> void:
	var grid = GridSystemScript.new()
	var farming = FarmingSystemScript.new()
	var state := HarvestSeedState.new()
	farming.configure(grid, null, state)
	grid.set_cell_state(15, 15, FARMLAND)
	var crop: CropData = _make_crop_data("tomato", 4, "annual_regrow", "outdoor_or_greenhouse", 2)
	crop.yield_min = 1
	crop.yield_max = 20
	var cell := grid.get_cell(15, 15)
	var instance: CropInstance = farming.plant(cell, crop)
	instance.set_growth_state(4.0, CropInstance.LifecycleState.MATURE)

	state.harvest_seed = 1
	var first_seed_preview: Dictionary = farming.preview_harvest(cell)
	var repeated_preview: Dictionary = farming.preview_harvest(cell)
	assertions.equal(first_seed_preview, repeated_preview, "same save seed repeats an exact preview")
	assertions.equal(first_seed_preview.get("harvest_seed", 0), 1, "preview records the authoritative save seed")
	assertions.equal(
		first_seed_preview.get("items", {}),
		{"tomato": instance.calculate_yield(15, 15, 1)},
		"farming yield uses the configured save seed"
	)

	state.harvest_seed = 2
	var second_seed_preview: Dictionary = farming.preview_harvest(cell)
	assertions.equal(second_seed_preview.get("harvest_seed", 0), 2, "changed save seed changes the preview token")
	assertions.equal(
		second_seed_preview.get("items", {}),
		{"tomato": instance.calculate_yield(15, 15, 2)},
		"changed save seed reaches deterministic yield input"
	)
	assertions.truthy(
		first_seed_preview.items != second_seed_preview.items,
		"chosen seed fixture produces different deterministic yields"
	)

	farming.free()
	grid.free()


func _test_exact_harvest_post_states(assertions: TestAssert) -> void:
	var grid = GridSystemScript.new()
	var farming = FarmingSystemScript.new()
	farming.configure(grid, null, HarvestSeedState.new())

	grid.set_cell_state(20, 20, FARMLAND)
	var annual := _make_crop_data("grain", 3)
	var annual_cell := grid.get_cell(20, 20)
	var annual_instance: CropInstance = farming.plant(annual_cell, annual)
	annual_instance.set_growth_state(3.0, CropInstance.LifecycleState.MATURE)
	var annual_preview: Dictionary = farming.preview_harvest(annual_cell)
	assertions.equal(annual_preview.get("post_crop", "missing"), null, "annual preview removes the crop")
	assertions.equal(annual_preview.get("post_lifecycle_state", "missing"), null, "annual preview explicitly has no post lifecycle")
	assertions.equal(annual_preview.get("post_cell_state", -1), GridCell.State.FARMLAND, "annual preview returns farmland")
	assertions.equal(annual_preview.get("post_growth_progress", -1.0), 0.0, "annual preview has zero post progress")

	grid.set_cell_state(21, 20, FARMLAND)
	var regrow := _make_crop_data("tomato", 4, "annual_regrow", "outdoor_or_greenhouse", 2)
	var regrow_cell := grid.get_cell(21, 20)
	var regrow_instance: CropInstance = farming.plant(regrow_cell, regrow)
	regrow_instance.set_growth_state(4.0, CropInstance.LifecycleState.MATURE)
	var regrow_preview: Dictionary = farming.preview_harvest(regrow_cell)
	assertions.truthy(regrow_preview.get("post_crop") is Dictionary, "regrow preview retains a crop snapshot")
	assertions.equal(regrow_preview.get("post_lifecycle_state", -1), CropInstance.LifecycleState.GROWING, "regrow preview explicitly returns to growing")
	assertions.equal(regrow_preview.get("post_cell_state", -1), GridCell.State.PLANTED, "regrow preview keeps planted state")
	assertions.equal(regrow_preview.get("post_growth_progress", -1.0), 2.0, "regrow preview resumes at authored progress")

	farming.free()
	grid.free()


func _test_deterministic_harvest_transaction(assertions: TestAssert) -> void:
	var grid = GridSystemScript.new()
	var farming = FarmingSystemScript.new()
	var event_bus := HarvestEventBus.new()
	grid._event_bus = event_bus
	farming.configure(grid, null, HarvestSeedState.new())
	grid.set_cell_state(15, 15, FARMLAND)
	var crop: CropData = _make_crop_data("tomato", 4, "annual_regrow", "outdoor_or_greenhouse", 2)
	crop.yield_min = 2
	crop.yield_max = 3
	var cell := grid.get_cell(15, 15)
	var instance: CropInstance = farming.plant(cell, crop)
	instance.set_growth_state(4.0, CropInstance.LifecycleState.MATURE)
	farming.call("_update_visual", cell, instance)
	event_bus.cell_events.clear()
	event_bus.harvest_events.clear()
	var first: Dictionary = farming.preview_harvest(cell)
	var capacity := ZeroCapacity.new()
	var storage = FarmStorageSystemScript.new()
	assertions.truthy(storage.configure(capacity.provide), "capacity rejection fixture configures real farm storage")
	assertions.truthy(not storage.can_add(first.items), "real farm storage preflight rejects harvest output")
	assertions.truthy(not storage.add_items(first.items), "real farm storage capacity preflight rejects harvest output")
	assertions.equal(storage.get_used_capacity(), 0, "capacity rejection leaves farm storage unchanged")
	var second: Dictionary = farming.preview_harvest(cell)
	assertions.equal(first, second, "preview remains byte-for-byte equal after capacity rejection")
	assertions.equal(instance.harvest_count, 0, "real capacity rejection does not change harvest count")
	assertions.equal(first.get("post_growth_progress", -1.0), 2.0, "preview includes regrowth progress")
	assertions.equal(first.get("post_lifecycle_state", -1), CropInstance.LifecycleState.GROWING, "preview includes post lifecycle")
	assertions.equal(first.get("post_cell_state", -1), GridCell.State.PLANTED, "preview includes post cell state")
	assertions.truthy(first.get("before", {}).get("crop", null) is Dictionary, "preview includes a stable before snapshot")
	var mature_visual := farming.get_crop_visual(cell)
	var mature_color := _fallback_color(mature_visual)
	assertions.equal(mature_visual.get_meta("lifecycle_state", -1), CropInstance.LifecycleState.MATURE, "caller-rejected mature crop keeps mature visual state")
	assertions.equal(mature_color, Color(1.0, 0.84, 0.0), "caller-rejected crop keeps the normal mature material")

	var altered := first.duplicate(true)
	altered.exp = int(altered.exp) + 1
	var before_altered: Dictionary = grid.get_crop_snapshot(15, 15)
	assertions.truthy(farming.commit_harvest(cell, altered).is_empty(), "altered preview is rejected")
	assertions.equal(grid.get_crop_snapshot(15, 15), before_altered, "altered preview rejection is atomic")
	assertions.equal(event_bus.harvest_events, [], "altered preview emits no harvest event")
	assertions.equal(event_bus.cell_events, [], "altered preview emits no cell event")
	assertions.truthy(farming.get_crop_visual(cell) == mature_visual, "altered preview does not replace the visual")
	assertions.equal(_fallback_color(mature_visual), mature_color, "altered preview does not mutate visual color")
	assertions.equal(instance.lifecycle_state, CropInstance.LifecycleState.MATURE, "altered preview leaves lifecycle mature")
	assertions.equal(instance.harvest_count, 0, "altered preview leaves harvest count unchanged")
	var committed: Dictionary = farming.commit_harvest(cell, first)
	assertions.equal(committed.get("items", {}), first.items, "commit returns previewed items")
	assertions.equal(instance.harvest_count, 1, "successful commit increments harvest count")
	assertions.near(instance.growth_progress, 2.0, 0.001, "successful regrow commit applies previewed progress")
	assertions.equal(instance.lifecycle_state, CropInstance.LifecycleState.GROWING, "successful regrow commit applies previewed lifecycle")
	assertions.equal(event_bus.harvest_events.size(), 1, "successful commit emits one harvest event")
	assertions.equal(event_bus.cell_events.size(), 1, "successful commit emits one cell event")
	var after_commit := grid.get_crop_snapshot(15, 15)
	var visual_after_commit := farming.get_crop_visual(cell)
	var color_after_commit := _fallback_color(visual_after_commit)
	assertions.truthy(farming.commit_harvest(cell, first).is_empty(), "stale preview is rejected after state changes")
	assertions.equal(grid.get_crop_snapshot(15, 15), after_commit, "stale preview leaves crop snapshot unchanged")
	assertions.equal(event_bus.harvest_events.size(), 1, "stale preview emits no extra harvest event")
	assertions.equal(event_bus.cell_events.size(), 1, "stale preview emits no extra cell event")
	assertions.truthy(farming.get_crop_visual(cell) == visual_after_commit, "stale preview does not replace the visual")
	assertions.equal(_fallback_color(visual_after_commit), color_after_commit, "stale preview does not mutate visual color")
	assertions.truthy(not grid.has_method("preview_harvest"), "GridSystem exposes no harvest preview domain API")
	assertions.truthy(not grid.has_method("harvest_crop"), "GridSystem exposes no harvest commit domain API")

	storage.free()
	event_bus.free()
	farming.free()
	grid.free()


func _fallback_color(visual: Node3D) -> Color:
	if visual is MeshInstance3D:
		var material := (visual as MeshInstance3D).material_override as StandardMaterial3D
		if material != null:
			return material.albedo_color
	return Color.TRANSPARENT


func _test_reentrant_harvest_observes_final_state(assertions: TestAssert) -> void:
	var grid = GridSystemScript.new()
	var farming = FarmingSystemScript.new()
	var event_bus := HarvestEventBus.new()
	var state := HarvestSeedState.new()
	grid._event_bus = event_bus
	farming.configure(grid, null, state)
	farming._event_bus = event_bus

	grid.set_cell_state(24, 20, FARMLAND)
	var annual := _make_crop_data("grain", 3)
	var replacement := _make_crop_data("turnip", 2)
	var annual_cell := grid.get_cell(24, 20)
	var annual_instance: CropInstance = farming.plant(annual_cell, annual)
	annual_instance.set_growth_state(3.0, CropInstance.LifecycleState.MATURE)
	farming.call("_update_visual", annual_cell, annual_instance)
	var annual_observer := ReentrantHarvestObserver.new()
	annual_observer.farming = farming
	annual_observer.cell = annual_cell
	annual_observer.replacement = replacement
	annual_observer.state = state
	event_bus.crop_harvested.connect(annual_observer.on_harvested)

	assertions.truthy(not farming.harvest(annual_cell).is_empty(), "annual harvest commits before reentrant notification")
	assertions.equal(annual_observer.observed_exp, annual.exp_reward, "annual harvest listener observes committed experience")
	assertions.equal(annual_observer.observed_cell_state, GridCell.State.FARMLAND, "annual harvest listener observes committed farmland")
	assertions.truthy(annual_observer.replanted != null, "annual harvest listener can replant the committed farmland")
	assertions.equal(annual_cell.state, GridCell.State.PLANTED, "reentrant annual replant remains planted")
	assertions.equal(annual_cell.crop_instance.crop_data.crop_id, "turnip", "reentrant annual replant owns the final crop")
	var replacement_visual := farming.get_crop_visual(annual_cell)
	assertions.truthy(replacement_visual != null, "reentrant annual replant keeps its visual")
	if replacement_visual != null:
		assertions.equal(replacement_visual.get_meta("crop_id", ""), "turnip", "reentrant annual replant keeps the replacement visual")
	event_bus.crop_harvested.disconnect(annual_observer.on_harvested)

	grid.set_cell_state(25, 20, FARMLAND)
	var regrow := _make_crop_data("tomato", 4, "annual_regrow", "outdoor_or_greenhouse", 2)
	var regrow_cell := grid.get_cell(25, 20)
	var regrow_instance: CropInstance = farming.plant(regrow_cell, regrow)
	regrow_instance.set_growth_state(4.0, CropInstance.LifecycleState.MATURE)
	farming.call("_update_visual", regrow_cell, regrow_instance)
	var regrow_observer := ReentrantHarvestObserver.new()
	regrow_observer.farming = farming
	regrow_observer.cell = regrow_cell
	regrow_observer.replacement = replacement
	regrow_observer.state = state
	event_bus.crop_harvested.connect(regrow_observer.on_harvested)

	assertions.truthy(not farming.harvest(regrow_cell).is_empty(), "regrow harvest commits before notification")
	assertions.equal(regrow_observer.observed_exp, annual.exp_reward + regrow.exp_reward, "regrow listener observes committed experience")
	assertions.equal(regrow_observer.observed_cell_state, GridCell.State.PLANTED, "regrow listener observes planted post-state")
	assertions.equal(regrow_observer.observed_visual_state, CropInstance.LifecycleState.GROWING, "regrow listener observes updated growing visual")
	assertions.truthy(regrow_observer.replanted == null, "regrow listener cannot replace the retained crop")
	assertions.truthy(farming.get_crop_visual(regrow_cell) != null, "regrow crop keeps its visual after reentrant callback")
	assertions.equal(regrow_cell.crop_instance.harvest_count, 1, "regrow crop keeps committed harvest count")

	event_bus.free()
	farming.free()
	grid.free()
