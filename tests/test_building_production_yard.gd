extends RefCounted

const YardScript = preload("res://scripts/buildings/building_production_yard.gd")
const GROUND_ASSETS := {
	"timber": "res://assets/buildings/yards/timber_yard_ground.png",
	"masonry": "res://assets/buildings/yards/masonry_yard_ground.png",
	"industrial": "res://assets/buildings/yards/industrial_yard_ground.png",
}
const GROUND_TEXTURE_SIZE := Vector2(1024.0, 1024.0)
const TERRAIN_ONLY_CULL_MASK := 1 << 7


func run(assertions: TestAssert, tree: SceneTree) -> void:
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
	assertions.equal(_decals(yard).size(), 1, "yard creates one seamless ground decal")
	assertions.equal(_sprites(yard).size(), 0, "yard creates no fence sprite cards")
	assertions.equal(_static_bodies(yard).size(), 0, "yard creates no perimeter physics body")
	assertions.equal(yard.get_fence_segment_count(), 0, "legacy fence query reports no fence segments")
	assertions.equal(yard.get_output_slots().size(), 6, "3x3 yard preserves six collection slots")
	assertions.truthy(yard.all_output_slots_inside_bounds(), "3x3 collection slots stay inside the ground area")
	assertions.equal(yard.get_style(), "timber", "yard preserves its style")
	assertions.truthy(not yard.has_enabled_collisions(), "painted ground is always walkable")
	assertions.equal(yard.get_collision_layers(), [], "painted ground owns no physics layer")
	_assert_ground_contract(yard, Vector2i(3, 3), assertions)

	var original_decal: Decal = _first_decal(yard)
	var original_texture: Texture2D = original_decal.texture_albedo if original_decal != null else null
	for stage in 4:
		yard.set_construction_stage(stage)
		assertions.equal(yard.get_construction_stage(), stage, "yard stores construction stage %d" % stage)
		assertions.equal(_first_decal(yard), original_decal, "construction stage keeps the same ground decal")
		if original_decal != null:
			assertions.equal(original_decal.texture_albedo, original_texture, "construction stage keeps the ground texture")
		assertions.equal(yard.get_transition_sprite_count(), 0, "ground has no construction crossfade sprites")

	yard.set_preview_state(true, false)
	assertions.equal(yard.get_visual_tint(), Color(1.0, 0.38, 0.38, 0.68), "invalid preview tints ground red")
	yard.set_preview_state(true, true)
	assertions.equal(yard.get_visual_tint(), Color(0.48, 1.0, 0.52, 0.68), "valid preview tints ground green")
	yard.set_preview_state(false, true)
	yard.set_maintenance_state("overdue")
	assertions.equal(yard.get_visual_tint(), Color.WHITE, "maintenance does not tint the painted ground")
	yard.set_interaction_enabled(true)
	assertions.truthy(not yard.has_enabled_collisions(), "interaction state never gives ground a collision")
	yard.free()

	var large := YardScript.new()
	tree.root.add_child(large)
	assertions.truthy(
		large.configure(Vector2i(4, 4), "industrial", Vector3(0.0, 0.0, -0.55)),
		"4x4 industrial ground configures"
	)
	assertions.equal(_decals(large).size(), 1, "4x4 yard still uses one seamless decal")
	assertions.equal(large.get_output_slots().size(), 8, "4x4 yard preserves eight collection slots")
	assertions.truthy(large.all_output_slots_inside_bounds(), "4x4 collection slots stay inside the ground area")
	_assert_ground_contract(large, Vector2i(4, 4), assertions)
	assertions.truthy(not large.configure(Vector2i(2, 2), "timber", Vector3.ZERO), "unsupported yard size rejects")
	assertions.truthy(not large.configure(Vector2i(4, 4), "plastic", Vector3.ZERO), "unknown yard style rejects")
	large.clear_immediately()
	assertions.equal(_decals(large).size(), 0, "yard cleanup removes the painted ground immediately")
	assertions.equal(large.get_output_slots().size(), 0, "yard cleanup clears derived output slots")
	large.free()


func _assert_ground_contract(
	yard: Node3D,
	size: Vector2i,
	assertions: TestAssert
) -> void:
	var decal := _first_decal(yard)
	if decal == null:
		return
	assertions.equal(decal.cull_mask, TERRAIN_ONLY_CULL_MASK, "ground projects only onto terrain receiver layer")
	assertions.truthy(
		decal.size.x >= float(size.x) and decal.size.x <= float(size.x) + 0.2,
		"ground width covers footprint with at most 0.1-cell overhang per side"
	)
	assertions.truthy(
		decal.size.z >= float(size.y) and decal.size.z <= float(size.y) + 0.2,
		"ground depth covers footprint with at most 0.1-cell overhang per side"
	)
	assertions.truthy(decal.size.y > 0.0, "ground decal has a terrain projection depth")
	assertions.equal(decal.texture_albedo.get_size(), GROUND_TEXTURE_SIZE, "ground decal uses a 1024px texture")


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


func _first_decal(root: Node) -> Decal:
	var found := _decals(root)
	return found[0] if not found.is_empty() else null


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
