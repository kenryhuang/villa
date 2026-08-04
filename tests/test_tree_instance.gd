extends RefCounted

const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")
const TreeFellingCatalogScript = preload("res://scripts/world/tree_felling_catalog.gd")

func run(assertions) -> void:
	var expected := {
		"pine-small": true,
		"pine-tall": true,
		"canopy-small": true,
		"canopy-medium": true,
		"round-small": true,
		"fruit": false,
		"oak-large": false,
		"pine-large": false,
		"round-medium": false,
		"yellow": false,
	}
	for variant in expected:
		assertions.equal(
			TreeFellingCatalogScript.is_variant_choppable(variant),
			expected[variant],
			"eligibility is variant-driven for %s" % variant
		)
	for variant in TreeFellingCatalogScript.CHOPPABLE_VARIANTS:
		var path := TreeFellingCatalogScript.atlas_path(variant)
		assertions.truthy(ResourceLoader.exists(path), "%s has a felling atlas" % variant)
		if ResourceLoader.exists(path):
			var atlas := load(path) as Texture2D
			assertions.truthy(atlas != null, "%s atlas loads as a texture" % variant)
			if atlas != null:
				assertions.truthy(TreeFellingCatalogScript.is_valid_atlas(atlas), "%s atlas has four equal cells" % variant)
				assertions.truthy(atlas.get_image().detect_alpha() != Image.ALPHA_NONE, "%s atlas keeps transparency" % variant)
				for frame in range(4):
					var used_rect := TreeInstanceScript.felling_frame_used_rect(atlas, frame)
					assertions.truthy(used_rect.has_area(), "%s frame %d contains painted art" % [variant, frame])
					assertions.truthy(used_rect.end.x < atlas.get_width() / 4, "%s frame %d keeps right padding" % [variant, frame])
	assertions.near(TreeInstanceScript.trunk_radius_for(0.5), 0.24, 0.001, "small trunks clamp to minimum radius")
	assertions.near(TreeInstanceScript.trunk_radius_for(2.0), 0.46, 0.001, "large trunks clamp to maximum radius")
	assertions.near(TreeInstanceScript.trunk_height_for(2.0), 0.84, 0.001, "trunk height follows authored height")
	var occluder := TreeInstanceScript.occluder_dimensions(Vector2(2.0, 3.0))
	assertions.near(occluder.x, 0.92, 0.001, "occluder follows canopy width")
	assertions.near(occluder.y, 2.7, 0.001, "occluder follows canopy height")
	assertions.near(TreeInstanceScript.opacity_step(1.0, 0.3, 0.1), 0.5575, 0.001, "occluded opacity approaches target")
	var texture_size := Vector2(448.0, 768.0)
	var target_size := Vector2(3.0, 4.0)
	var pixel_size := target_size.x / texture_size.x
	var vertical_scale := TreeInstanceScript.vertical_scale_for(texture_size, target_size)
	assertions.near(vertical_scale, 4.0 / (768.0 * pixel_size), 0.0001, "tree corrects texture aspect ratio")
	assertions.near(texture_size.y * pixel_size * vertical_scale, target_size.y, 0.0001, "tree renders authored height")
