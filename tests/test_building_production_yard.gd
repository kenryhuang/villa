extends RefCounted

const YardScript = preload("res://scripts/buildings/building_production_yard.gd")
const GROUND_ASSETS := {
	"timber": "res://assets/buildings/yards/timber_yard_ground.png",
	"masonry": "res://assets/buildings/yards/masonry_yard_ground.png",
	"industrial": "res://assets/buildings/yards/industrial_yard_ground.png",
}
const GROUND_TEXTURE_SIZE := Vector2(1024.0, 1024.0)
const GROUND_SURFACE_LIFT := 0.028


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var terrain := TerrainBuilder.new()
	tree.root.add_child(terrain)
	assertions.truthy(terrain.build(), "terrain builds for painted-ground surface comparison")
	var terrain_mesh := terrain.get_node_or_null("TerrainMesh") as MeshInstance3D
	var missing_loader := YardScript.new()
	assertions.equal(
		missing_loader.call("_load_ground_texture", "missing_test_family"),
		null,
		"missing ground texture returns no visual resource without a fallback"
	)
	missing_loader.free()
	for style in GROUND_ASSETS:
		var path := str(GROUND_ASSETS[style])
		assertions.truthy(ResourceLoader.exists(path), "%s painted ground exists" % style)
		_validate_painted_ground(style, path, assertions)
		assertions.equal(
			str(YardScript.TEXTURES.get(style, "")),
			path,
			"%s yard runtime uses its painted ground texture" % style
		)

	var yard := YardScript.new()
	tree.root.add_child(yard)
	assertions.truthy(
		yard.configure(Vector2i(3, 3), "timber", Vector3(0.0, 0.0, -0.35)),
		"3x3 timber ground configures"
	)
	assertions.equal(_ground_meshes(yard).size(), 1, "yard creates one seamless compatibility ground mesh")
	assertions.equal(_decals(yard).size(), 0, "compatibility renderer yard creates no unsupported Decal")
	assertions.equal(_sprites(yard).size(), 0, "yard creates no fence sprite cards")
	assertions.equal(_static_bodies(yard).size(), 0, "yard creates no perimeter physics body")
	assertions.equal(yard.get_fence_segment_count(), 0, "legacy fence query reports no fence segments")
	assertions.equal(yard.get_output_slots().size(), 6, "3x3 yard preserves six collection slots")
	assertions.truthy(yard.all_output_slots_inside_bounds(), "3x3 collection slots stay inside the ground area")
	assertions.equal(yard.get_style(), "timber", "yard preserves its style")
	assertions.truthy(not yard.has_enabled_collisions(), "painted ground is always walkable")
	assertions.equal(yard.get_collision_layers(), [], "painted ground owns no physics layer")
	_assert_ground_contract(yard, Vector2i(3, 3), assertions, terrain_mesh)
	yard.global_position = Vector3(12.0, 0.0, 8.0)
	yard.force_update_transform()
	_assert_ground_contract(yard, Vector2i(3, 3), assertions, terrain_mesh)

	var original_ground := _first_ground_mesh(yard)
	var original_texture := _ground_texture(original_ground)
	for stage in 4:
		yard.set_construction_stage(stage)
		assertions.equal(yard.get_construction_stage(), stage, "yard stores construction stage %d" % stage)
		assertions.equal(_first_ground_mesh(yard), original_ground, "construction stage keeps the same ground mesh")
		assertions.equal(_ground_texture(original_ground), original_texture, "construction stage keeps the ground texture")
		assertions.equal(yard.get_transition_sprite_count(), 0, "ground has no construction crossfade sprites")

	yard.set_preview_state(true, false)
	assertions.equal(yard.get_visual_tint(), Color(1.0, 0.38, 0.38, 1.0), "invalid preview tints ground red without reducing texture alpha")
	yard.set_preview_state(true, true)
	assertions.equal(yard.get_visual_tint(), Color(0.48, 1.0, 0.52, 1.0), "valid preview tints ground green without reducing texture alpha")
	yard.set_preview_state(false, true)
	yard.set_maintenance_state("overdue")
	assertions.equal(yard.get_visual_tint(), Color.WHITE, "maintenance does not tint the painted ground")
	yard.set_interaction_enabled(true)
	assertions.truthy(not yard.has_enabled_collisions(), "interaction state never gives ground a collision")
	yard.free()

	var large := YardScript.new()
	tree.root.add_child(large)
	large.global_position = Vector3(-16.0, 0.0, -8.0)
	assertions.truthy(
		large.configure(Vector2i(4, 4), "industrial", Vector3(0.0, 0.0, -0.55)),
		"4x4 industrial ground configures"
	)
	assertions.equal(_ground_meshes(large).size(), 1, "4x4 yard still uses one seamless ground mesh")
	assertions.equal(large.get_output_slots().size(), 8, "4x4 yard preserves eight collection slots")
	assertions.truthy(large.all_output_slots_inside_bounds(), "4x4 collection slots stay inside the ground area")
	_assert_ground_contract(large, Vector2i(4, 4), assertions, terrain_mesh)
	assertions.truthy(not large.configure(Vector2i(2, 2), "timber", Vector3.ZERO), "unsupported yard size rejects")
	assertions.truthy(not large.configure(Vector2i(4, 4), "plastic", Vector3.ZERO), "unknown yard style rejects")
	large.clear_immediately()
	assertions.equal(_ground_meshes(large).size(), 0, "yard cleanup removes the painted ground immediately")
	assertions.equal(large.get_output_slots().size(), 0, "yard cleanup clears derived output slots")
	large.free()
	terrain.free()


func _assert_ground_contract(
	yard: Node3D,
	size: Vector2i,
	assertions: TestAssert,
	terrain_mesh: MeshInstance3D
) -> void:
	var ground := _first_ground_mesh(yard)
	if ground == null:
		return
	assertions.truthy(ground.mesh is ArrayMesh, "ground uses a compatibility-renderable array mesh")
	var bounds := ground.get_aabb()
	assertions.truthy(
		bounds.size.x >= float(size.x) and bounds.size.x <= float(size.x) + 0.2001,
		"ground width covers footprint with at most 0.1-cell overhang per side"
	)
	assertions.truthy(
		bounds.size.z >= float(size.y) and bounds.size.z <= float(size.y) + 0.2001,
		"ground depth covers footprint with at most 0.1-cell overhang per side"
	)
	var vertices := _ground_vertices(ground)
	assertions.truthy(vertices.size() >= 100, "ground mesh is subdivided enough to follow terrain")
	if terrain_mesh != null:
		for vertex in vertices:
			var sample := ground.to_global(vertex)
			var terrain_height := _rendered_terrain_height(terrain_mesh, sample.x, sample.z)
			assertions.near(sample.y, terrain_height + GROUND_SURFACE_LIFT, 0.001, "ground mesh follows the rendered terrain triangles")
			assertions.truthy(sample.y > terrain_height + 0.02, "ground mesh stays visibly above the rendered terrain")
		_assert_ground_triangle_interiors(ground, terrain_mesh, assertions)
	var material := ground.material_override as StandardMaterial3D
	assertions.truthy(material != null, "ground mesh has a standard compatibility material")
	if material != null:
		assertions.equal(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "ground material preserves smooth painted alpha")
		assertions.equal(material.albedo_texture.get_size(), GROUND_TEXTURE_SIZE, "ground mesh uses a 1024px texture")


func _validate_painted_ground(style: String, path: String, assertions: TestAssert) -> void:
	if not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	assertions.truthy(texture != null, "%s painted ground imports as Texture2D" % style)
	if texture == null:
		return
	assertions.equal(texture.get_size(), GROUND_TEXTURE_SIZE, "%s painted ground is 1024x1024" % style)
	var image := texture.get_image()
	assertions.truthy(image.detect_alpha(), "%s painted ground preserves alpha" % style)
	for corner in [Vector2i(0, 0), Vector2i(1023, 0), Vector2i(0, 1023), Vector2i(1023, 1023)]:
		assertions.truthy(image.get_pixelv(corner).a <= 0.01, "%s painted ground has transparent corners" % style)
	var painted := 0
	var translucent := 0
	var emphasized := 0
	var edge_painted := 0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var alpha := image.get_pixel(x, y).a
			if alpha > 0.05:
				painted += 1
				if alpha < 0.84:
					translucent += 1
				if alpha >= 0.85 and alpha <= 0.96:
					emphasized += 1
				if x < 80 or x > 943 or y < 80 or y > 943:
					edge_painted += 1
	assertions.truthy(painted > 3000, "%s ground contains a substantial painted surface" % style)
	assertions.truthy(translucent > painted / 2, "%s main ground surface remains semi-transparent" % style)
	assertions.truthy(emphasized > 20, "%s ground retains emphasized opaque details" % style)
	assertions.truthy(edge_painted > 0, "%s irregular ground edge reaches the feather zone" % style)


func _first_ground_mesh(root: Node) -> MeshInstance3D:
	var found := _ground_meshes(root)
	return found[0] if not found.is_empty() else null


func _ground_meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D and child.name == "GroundMesh":
			result.append(child as MeshInstance3D)
		result.append_array(_ground_meshes(child))
	return result


func _ground_texture(ground: MeshInstance3D) -> Texture2D:
	if ground == null:
		return null
	var material := ground.material_override as StandardMaterial3D
	return material.albedo_texture if material != null else null


func _ground_vertices(ground: MeshInstance3D) -> PackedVector3Array:
	if ground == null or not ground.mesh is ArrayMesh or ground.mesh.get_surface_count() == 0:
		return PackedVector3Array()
	var arrays := (ground.mesh as ArrayMesh).surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array


func _rendered_terrain_height(terrain_mesh: MeshInstance3D, world_x: float, world_z: float) -> float:
	var arrays := (terrain_mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var grid_x := clampf(world_x / TerrainBuilder.WORLD_SIZE.x + 0.5, 0.0, 1.0) * TerrainBuilder.SUBDIVISIONS
	var grid_z := clampf(world_z / TerrainBuilder.WORLD_SIZE.y + 0.5, 0.0, 1.0) * TerrainBuilder.SUBDIVISIONS
	var cell_x := mini(floori(grid_x), TerrainBuilder.SUBDIVISIONS - 1)
	var cell_z := mini(floori(grid_z), TerrainBuilder.SUBDIVISIONS - 1)
	var local_x := grid_x - float(cell_x)
	var local_z := grid_z - float(cell_z)
	var stride := TerrainBuilder.SUBDIVISIONS + 1
	var a := vertices[cell_z * stride + cell_x].y
	var b := vertices[cell_z * stride + cell_x + 1].y
	var c := vertices[(cell_z + 1) * stride + cell_x].y
	var d := vertices[(cell_z + 1) * stride + cell_x + 1].y
	if local_x + local_z <= 1.0:
		return a * (1.0 - local_x - local_z) + b * local_x + c * local_z
	return b * (1.0 - local_z) + c * (1.0 - local_x) + d * (local_x + local_z - 1.0)


func _assert_ground_triangle_interiors(
	ground: MeshInstance3D,
	terrain_mesh: MeshInstance3D,
	assertions: TestAssert
) -> void:
	var arrays := (ground.mesh as ArrayMesh).surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var worst_error := 0.0
	var minimum_clearance := INF
	for triangle_start in range(0, indices.size(), 3):
		var a := ground.to_global(vertices[indices[triangle_start]])
		var b := ground.to_global(vertices[indices[triangle_start + 1]])
		var c := ground.to_global(vertices[indices[triangle_start + 2]])
		for a_weight in range(7):
			for b_weight in range(7 - a_weight):
				var c_weight := 6 - a_weight - b_weight
				var sample := (
					a * (float(a_weight) / 6.0)
					+ b * (float(b_weight) / 6.0)
					+ c * (float(c_weight) / 6.0)
				)
				var terrain_height := _rendered_terrain_height(terrain_mesh, sample.x, sample.z)
				var clearance := sample.y - terrain_height
				worst_error = maxf(worst_error, absf(clearance - GROUND_SURFACE_LIFT))
				minimum_clearance = minf(minimum_clearance, clearance)
	assertions.truthy(worst_error <= 0.001, "every painted ground triangle follows the rendered terrain surface")
	assertions.truthy(minimum_clearance > 0.02, "painted ground triangle interiors never enter the terrain")


func _decals(root: Node) -> Array[Decal]:
	var result: Array[Decal] = []
	for child in root.get_children():
		if child is Decal:
			result.append(child as Decal)
		result.append_array(_decals(child))
	return result


func _sprites(root: Node) -> Array[Sprite3D]:
	var result: Array[Sprite3D] = []
	for child in root.get_children():
		if child is Sprite3D:
			result.append(child as Sprite3D)
		result.append_array(_sprites(child))
	return result


func _static_bodies(root: Node) -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	for child in root.get_children():
		if child is StaticBody3D:
			result.append(child as StaticBody3D)
		result.append_array(_static_bodies(child))
	return result
