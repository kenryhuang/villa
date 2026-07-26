extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const TerrainBuilderScript = preload("res://scripts/world/terrain_builder.gd")


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
