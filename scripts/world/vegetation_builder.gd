class_name VegetationBuilder
extends Node3D

const TreeScatterScript = preload("res://scripts/world/tree_scatter.gd")
const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")

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
		var tree_instance = TreeInstanceScript.new()
		tree_instance.name = str(tree.id)
		tree_instance.configure(tree, texture, terrain.get_height_at(tree.x, tree.z))
		add_child(tree_instance)
	return get_child_count()
