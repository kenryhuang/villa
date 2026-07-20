class_name VegetationBuilder
extends Node3D

const TreeScatterScript = preload("res://scripts/world/tree_scatter.gd")

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
	if placements.size() < 28:
		push_warning("Tree scatter placed %d of 28 trees" % placements.size())
	for tree in placements:
		var sprite := Sprite3D.new()
		sprite.name = str(tree.id)
		sprite.texture = load(TEXTURES[tree.variant]) as Texture2D
		if sprite.texture == null:
			push_warning("Missing tree texture: %s" % TEXTURES[tree.variant])
			continue
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.pixel_size = float(tree.width) / float(sprite.texture.get_width())
		sprite.position = Vector3(float(tree.x), terrain.get_height_at(tree.x, tree.z) + float(tree.height) * 0.5, float(tree.z))
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sprite)
	return get_child_count()
