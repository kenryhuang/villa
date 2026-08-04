class_name VegetationBuilder
extends Node3D

const TreeScatterScript = preload("res://scripts/world/tree_scatter.gd")
const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")
const TreeFellingCatalogScript = preload("res://scripts/world/tree_felling_catalog.gd")

const TEXTURES := {
	"canopy-medium": "res://assets/vegetation/tree-canopy-medium.png",
	"canopy-small": "res://assets/vegetation/tree-canopy-small.png",
	"fruit": "res://assets/vegetation/tree-fruit.png",
	"oak-large": "res://assets/vegetation/tree-oak-large.png",
	"pine-large": "res://assets/vegetation/tree-pine-large.png",
	"pine-small": "res://assets/vegetation/tree-pine-small.png",
	"pine-tall": "res://assets/vegetation/tree-pine-tall.png",
	"round-medium": "res://assets/vegetation/tree-round-medium.png",
	"round-small": "res://assets/vegetation/tree-round-small.png",
	"yellow": "res://assets/vegetation/tree-yellow.png",
}

func build(terrain: TerrainBuilder, route: Array[Dictionary]) -> int:
	var placements := TreeScatterScript.generate(route)
	if placements.size() < 40:
		push_warning("Tree scatter placed %d of 40 trees" % placements.size())
	for tree in placements:
		var texture := load(TEXTURES[tree.variant]) as Texture2D
		if texture == null:
			push_warning("Missing tree texture: %s" % TEXTURES[tree.variant])
			continue
		var felling_atlas: Texture2D
		if TreeFellingCatalogScript.is_variant_choppable(str(tree.variant)):
			var atlas_path := TreeFellingCatalogScript.atlas_path(str(tree.variant))
			felling_atlas = load(atlas_path) as Texture2D
			if not TreeFellingCatalogScript.is_valid_atlas(felling_atlas):
				push_warning("Tree variant %s is ineligible: missing or invalid felling atlas %s" % [tree.variant, atlas_path])
				felling_atlas = null
		var tree_instance = TreeInstanceScript.new()
		tree_instance.name = str(tree.id)
		tree_instance.configure(tree, texture, terrain.get_height_at(tree.x, tree.z), felling_atlas)
		add_child(tree_instance)
	return get_child_count()
