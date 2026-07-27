extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const SeasonSystemScript = preload("res://scripts/systems/season_system.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")


func _make_crop(id: String, growth_days: int, seasons: Array[int] = []) -> CropData:
	var crop := CropDataScript.new() as CropData
	crop.crop_id = id
	crop.name = id.capitalize()
	crop.growth_days = growth_days
	crop.exp_reward = 7
	crop.seasons.assign(seasons)
	crop.stage_textures.assign(["seed", "sprout", "growing", "mature"])
	return crop


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var path := "res://scenes/systems/farming_system.tscn"
	assertions.truthy(ResourceLoader.exists(path), "reusable FarmingSystem scene exists")
	if not ResourceLoader.exists(path):
		return

	var grid := GridSystemScript.new()
	var season := SeasonSystemScript.new()
	var farming = load(path).instantiate()
	tree.root.add_child(grid)
	tree.root.add_child(season)
	tree.root.add_child(farming)
	season.current_season = SeasonSystemScript.Season.WINTER
	farming.configure(grid, season, null)

	assertions.truthy(farming.has_node("CropVisuals"), "FarmingSystem owns CropVisuals")
	grid.set_cell_state(10, 10, GridCell.State.FARMLAND)
	var cell := grid.get_cell(10, 10)
	var crop := _make_crop("winter_test", 2, [SeasonSystemScript.Season.SUMMER])
	var instance: CropInstance = farming.plant(cell, crop)
	assertions.truthy(instance != null, "complete system plants a crop")
	assertions.equal(farming.get_visual_count(), 1, "plant creates one visual")

	farming.water(cell)
	farming.on_day_changed(2)
	assertions.equal(instance.growth_progress, 0.0, "wrong season blocks non-greenhouse crop")
	assertions.truthy(not cell.watered, "blocked growth still clears daily water")

	farming.set_greenhouse_cells([Vector2i(10, 10)])
	farming.water(cell)
	farming.on_day_changed(3)
	assertions.near(instance.growth_progress, 1.5, 0.001, "greenhouse crop ignores season")
	farming.on_day_changed(4)
	assertions.near(instance.growth_progress, 2.0, 0.001, "growth clamps at maturity")
	assertions.truthy(instance.is_mature(), "crop reports mature")
	farming.on_day_changed(5)
	assertions.near(instance.growth_progress, 2.0, 0.001, "mature crop stops advancing")

	var visual := farming.get_crop_visual(cell) as MeshInstance3D
	assertions.truthy(visual != null, "crop visual can be queried")
	if visual and visual.mesh is BoxMesh:
		assertions.truthy(visual.mesh.size.y > 0.5, "mature visual is taller than seed")

	farming.clear_visuals()
	assertions.equal(farming.get_visual_count(), 0, "visuals can be cleared")
	farming.rebuild_visuals()
	assertions.equal(farming.get_visual_count(), 1, "visuals rebuild from grid crop data")

	var result: Dictionary = farming.harvest(cell)
	assertions.equal(result.get("exp", 0), 7, "mature harvest returns experience")
	assertions.equal(cell.state, GridCell.State.FARMLAND, "harvest returns cell to farmland")
	assertions.equal(farming.get_visual_count(), 0, "harvest removes crop visual")

	farming.free()
	season.free()
	grid.free()
