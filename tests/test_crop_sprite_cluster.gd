extends RefCounted

const ClusterScript = preload("res://scripts/visual/crop_sprite_cluster.gd")


func _paths(stage: int, layer: String) -> Array[String]:
	var result: Array[String] = []
	for variant in 3:
		result.append(
			"res://assets/crops/grain/painted/stage_%d/variant_%d_%s.png"
			% [stage, variant, layer]
		)
	return result


func run(assertions: TestAssert, tree: SceneTree) -> void:
	assertions.equal(
		ClusterScript.variant_index_for_seed(4, 3),
		1,
		"seed selects variant by positive modulo"
	)
	assertions.equal(
		ClusterScript.variant_index_for_seed(-1, 3),
		2,
		"negative seed is normalized"
	)
	var cluster := ClusterScript.new()
	cluster.back_texture_paths = _paths(2, "back")
	cluster.front_texture_paths = _paths(2, "front")
	cluster.configure_variant_seed(4)
	tree.root.add_child(cluster)
	assertions.equal(cluster.get_variant_index(), 1, "configured seed is applied on ready")
	var back := cluster.get_node("BackLayer") as Sprite3D
	var front := cluster.get_node("FrontLayer") as Sprite3D
	assertions.truthy(back.texture != null, "back texture is loaded")
	assertions.truthy(front.texture != null, "front texture is loaded")
	assertions.equal(
		back.billboard,
		BaseMaterial3D.BILLBOARD_ENABLED,
		"back layer billboards"
	)
	assertions.equal(
		front.alpha_cut,
		SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS,
		"front alpha uses opaque prepass"
	)
	cluster.free()
