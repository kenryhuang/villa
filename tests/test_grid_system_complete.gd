extends RefCounted

const TerrainBuilderScript = preload("res://scripts/world/terrain_builder.gd")
const RoadBuilderScript = preload("res://scripts/world/road_builder.gd")


func run(assertions: TestAssert) -> void:
	assertions.truthy(
		ResourceLoader.exists("res://scenes/systems/grid_system.tscn"),
		"reusable GridSystem scene exists"
	)
	if not ResourceLoader.exists("res://scenes/systems/grid_system.tscn"):
		return

	var terrain = TerrainBuilderScript.new()
	assertions.truthy(terrain.build(), "real terrain builds for grid contract")
	var grid = load("res://scenes/systems/grid_system.tscn").instantiate()
	var road_route: Array[Dictionary] = []
	for point in RoadBuilderScript.MAIN_ROUTE:
		road_route.append(point.duplicate())
	var blocked_regions: Array[Dictionary] = [
		{"state": GridCell.State.WATER, "rect": Rect2(-17.8, 10.0, 2.0, 2.0)},
		{"state": GridCell.State.DECORATION, "rect": Rect2(14.0, -13.5, 2.0, 2.0)},
	]
	assertions.truthy(
		grid.configure(terrain, road_route, blocked_regions),
		"GridSystem configures with terrain and world features"
	)
	assertions.equal(grid._cells.size(), 1008, "configure initializes every grid cell")
	assertions.equal(grid.get_cell_at_world(-17.0, 11.0).state, GridCell.State.WATER, "water region is classified")
	assertions.equal(grid.get_cell_at_world(15.0, -12.5).state, GridCell.State.DECORATION, "decoration region is classified")

	var road_cell: GridCell = null
	for cell in grid._cells.values():
		if cell.state == GridCell.State.ROAD:
			road_cell = cell
			break
	assertions.truthy(road_cell != null, "road route classifies at least one cell")
	if road_cell:
		assertions.truthy(
			not grid.set_cell_state(road_cell.gx, road_cell.gz, GridCell.State.FARMLAND),
			"road cell cannot become farmland"
		)

	var overlay := grid.get_node_or_null("GridOverlay") as MeshInstance3D
	assertions.truthy(overlay != null and overlay.mesh is ArrayMesh, "grid overlay uses one ArrayMesh")
	assertions.truthy(
		overlay != null and overlay.mesh != null and overlay.mesh.get_surface_count() == 1,
		"grid overlay has one rendered surface"
	)
	assertions.truthy(grid.highlight_cell(18, 14, Color.YELLOW), "valid cell can be highlighted")
	var highlight := grid.get_node_or_null("GridCells/CellHighlight") as MeshInstance3D
	assertions.truthy(highlight != null and highlight.visible, "highlight visual becomes visible")
	grid.clear_highlights()
	assertions.truthy(highlight != null and not highlight.visible, "clear hides the highlight")
	assertions.truthy(not grid.highlight_cell(-1, 0, Color.YELLOW), "out-of-bounds highlight is rejected")

	var farm_cell = grid.get_cell(18, 14)
	if farm_cell.state == GridCell.State.WASTELAND and grid.can_farm_at(18, 14):
		assertions.truthy(grid.set_cell_state(18, 14, GridCell.State.FARMLAND), "farmable cell cultivates")
		farm_cell.watered = true
	var saved: Dictionary = grid.to_dict()
	assertions.truthy(saved.has("cells"), "grid serializes changed cells")

	var restored = load("res://scenes/systems/grid_system.tscn").instantiate()
	assertions.truthy(
		restored.configure(terrain, road_route, blocked_regions),
		"second GridSystem configures before restore"
	)
	assertions.truthy(restored.from_dict(saved), "serialized grid restores")
	assertions.equal(restored.get_cell(18, 14).state, farm_cell.state, "restored cell state matches")
	assertions.equal(restored.get_cell(18, 14).watered, farm_cell.watered, "restored watered flag matches")

	var steep_terrain = TerrainBuilderScript.new()
	var steep_image := Image.create(64, 64, false, Image.FORMAT_L8)
	for y in 64:
		for x in 64:
			steep_image.set_pixel(x, y, Color.WHITE if x >= 32 else Color.BLACK)
	steep_terrain.height_image = steep_image
	var steep_grid = load("res://scenes/systems/grid_system.tscn").instantiate()
	var empty_route: Array[Dictionary] = []
	var empty_regions: Array[Dictionary] = []
	assertions.truthy(steep_grid.configure(steep_terrain, empty_route, empty_regions), "synthetic steep terrain configures")
	var steep_cell: GridCell = null
	for candidate in steep_grid._cells.values():
		if candidate.slope > GridSystem.SLOPE_THRESHOLD:
			steep_cell = candidate
			break
	assertions.truthy(steep_cell != null, "synthetic terrain contains a steep cell")
	if steep_cell:
		assertions.truthy(
			not steep_grid.set_cell_state(steep_cell.gx, steep_cell.gz, GridCell.State.FARMLAND),
			"steep cell cannot become farmland"
		)

	steep_grid.free()
	steep_terrain.free()
	grid.free()
	restored.free()
	terrain.free()
