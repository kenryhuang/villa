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

static func vertical_scale_for(texture_size: Vector2, target_size: Vector2) -> float:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 or target_size.x <= 0.0:
		return 1.0
	var pixel_size := target_size.x / texture_size.x
	return target_size.y / (texture_size.y * pixel_size)

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
		sprite.scale = Vector3(1.0, vertical_scale_for(sprite.texture.get_size(), Vector2(float(tree.width), float(tree.height))), 1.0)
		sprite.position = Vector3(float(tree.x), terrain.get_height_at(tree.x, tree.z) + float(tree.height) * 0.5, float(tree.z))
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sprite)
	return get_child_count()
