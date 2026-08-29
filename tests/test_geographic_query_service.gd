extends RefCounted

const GeographicQueryServiceScript = preload(
	"res://scripts/systems/geographic_query_service.gd"
)
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")
const CropInstanceScript = preload("res://scripts/data/crop_instance.gd")


func run(assertions: TestAssert) -> void:
	_test_shoreline_and_anchor(assertions)
	_test_mature_flower_radius(assertions)
	_test_cast_line(assertions)


func _test_shoreline_and_anchor(assertions: TestAssert) -> void:
	var grid := GridSystemScript.new()
	var geography := GeographicQueryServiceScript.new()
	assertions.truthy(geography.configure(grid), "geography accepts the authoritative grid")
	var origin := Vector2i(10, 10)
	var footprint := Vector2i(2, 2)
	assertions.truthy(
		not geography.footprint_borders_natural_water(origin, footprint),
		"land-only footprint has no shoreline"
	)
	grid.get_cell(9, 9).state = GridCell.State.WATER
	assertions.truthy(
		not geography.footprint_borders_natural_water(origin, footprint),
		"diagonal water does not satisfy shoreline"
	)
	grid.get_cell(12, 11).state = GridCell.State.WATER
	grid.get_cell(12, 10).state = GridCell.State.WATER
	assertions.truthy(
		geography.footprint_borders_natural_water(origin, footprint),
		"orthogonal natural water satisfies shoreline"
	)
	assertions.equal(
		geography.water_anchor(origin, footprint),
		Vector2i(12, 10),
		"equal-distance water anchors use stable z then x ordering"
	)
	grid.free()


func _test_mature_flower_radius(assertions: TestAssert) -> void:
	var grid := GridSystemScript.new()
	var geography := GeographicQueryServiceScript.new()
	geography.configure(grid)
	_add_flower(grid, Vector2i(10, 10), true)
	_add_flower(grid, Vector2i(14, 10), true)
	_add_flower(grid, Vector2i(10, 14), true)
	_add_flower(grid, Vector2i(13, 13), true)
	_add_flower(grid, Vector2i(9, 10), false)
	var flowers: Array[GridCell] = geography.mature_flowers_near(
		Vector2(10.0, 10.0), 4.0
	)
	assertions.equal(flowers.size(), 3, "flower query includes only mature Euclidean-radius cells")
	assertions.equal(
		flowers.map(func(cell: GridCell) -> Vector2i: return Vector2i(cell.gx, cell.gz)),
		[Vector2i(10, 10), Vector2i(14, 10), Vector2i(10, 14)],
		"flower query orders by distance then z and x"
	)
	assertions.equal(
		geography.mature_flowers_near(Vector2(10.0, 10.0), 4.0, 2).size(),
		2,
		"flower query applies a stable positive cap"
	)
	grid.free()


func _test_cast_line(assertions: TestAssert) -> void:
	var grid := GridSystemScript.new()
	var geography := GeographicQueryServiceScript.new()
	geography.configure(grid)
	assertions.truthy(
		geography.is_clear_cast_line(Vector2i(5, 5), Vector2i(5, 9)),
		"empty cast line is clear"
	)
	grid.get_cell(5, 7).state = GridCell.State.BUILDING
	assertions.truthy(
		not geography.is_clear_cast_line(Vector2i(5, 5), Vector2i(5, 9)),
		"building blocks cast line"
	)
	grid.get_cell(5, 7).state = GridCell.State.WASTELAND
	grid.get_cell(5, 9).state = GridCell.State.WATER
	assertions.truthy(
		geography.is_clear_cast_line(Vector2i(5, 5), Vector2i(5, 9)),
		"water target is allowed at the line endpoint"
	)
	grid.free()


func _add_flower(grid: GridSystem, position: Vector2i, mature: bool) -> void:
	var data := CropDataScript.new()
	data.crop_id = "flower_%d_%d" % [position.x, position.y]
	data.plant_item_id = "%s_seed" % data.crop_id
	data.category = "flower"
	data.tags.assign(["flower"])
	data.growth_days = 1
	data.stage_textures.assign(["seed", "mature"])
	var instance := CropInstanceScript.new()
	instance.crop_data = data
	if mature:
		instance.set_growth_state(1.0, CropInstance.LifecycleState.MATURE)
	var cell := grid.get_cell(position.x, position.y)
	cell.state = GridCell.State.PLANTED
	cell.crop_instance = instance
