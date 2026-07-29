extends RefCounted

const TerrainBuilderScript = preload("res://scripts/world/terrain_builder.gd")


func run(assertions: TestAssert) -> void:
	var texture_path := "res://assets/terrain/farmland-soil-hand-painted.png"
	var script_path := "res://scripts/visual/farmland_tile.gd"
	assertions.truthy(
		ResourceLoader.exists(texture_path),
		"farmland hand-painted texture exists"
	)
	assertions.truthy(
		ResourceLoader.exists(script_path),
		"farmland tile script exists"
	)
	if not ResourceLoader.exists(texture_path) or not ResourceLoader.exists(script_path):
		return

	var terrain = TerrainBuilderScript.new()
	assertions.truthy(terrain.build(), "farmland test terrain builds")
	var cell := GridCell.new()
	cell.gx = 4
	cell.gz = 6
	var tile_script = load(script_path)
	var tile = tile_script.new()
	assertions.truthy(
		tile.configure(cell, terrain, -18.0, -14.0, 1.0),
		"farmland tile configures"
	)
	assertions.equal(tile.get_meta("gx"), 4, "tile records grid x")
	assertions.equal(tile.get_meta("gz"), 6, "tile records grid z")
	assertions.truthy(tile.mesh is ArrayMesh, "tile uses an ArrayMesh")
	assertions.equal(tile.mesh.get_surface_count(), 1, "tile has one surface")
	assertions.truthy(
		tile.material_override is StandardMaterial3D,
		"tile uses a standard hand-painted material"
	)
	tile.free()
	terrain.free()
