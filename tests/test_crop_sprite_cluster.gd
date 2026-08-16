extends RefCounted

const ClusterScript = preload("res://scripts/visual/crop_sprite_cluster.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")
const GRAIN_STAGE_SCENE := preload("res://assets/crops/grain/grain_stage_2_growing.tscn")


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
	_test_real_scene_fallback_tint_is_per_instance(assertions, tree)


func _test_real_scene_fallback_tint_is_per_instance(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var dormant := GRAIN_STAGE_SCENE.instantiate() as CropSpriteCluster
	var normal := GRAIN_STAGE_SCENE.instantiate() as CropSpriteCluster
	var missing_back: Array[String] = ["res://assets/crops/missing_back.png"]
	var missing_front: Array[String] = ["res://assets/crops/missing_front.png"]
	for value in [dormant, normal]:
		var instance := value as CropSpriteCluster
		instance.back_texture_paths = missing_back
		instance.front_texture_paths = missing_front
		tree.root.add_child(instance)
	var dormant_mesh := _first_mesh(dormant)
	var normal_mesh := _first_mesh(normal)
	assertions.truthy(dormant_mesh != null and dormant_mesh.visible, "missing painted texture exposes real Mesh fallback")
	assertions.truthy(normal_mesh != null and normal_mesh.visible, "second crop instance exposes its Mesh fallback")
	var base_color := _mesh_color(dormant_mesh)
	var normal_color := _mesh_color(normal_mesh)
	var farming = FarmingSystemScript.new()
	farming.call("_apply_visual_state", dormant, CropInstance.LifecycleState.DORMANT)
	assertions.equal((dormant.get_node("BackLayer") as Sprite3D).modulate, Color(0.68, 0.72, 0.65, 1.0), "dormant tint reaches the back sprite")
	assertions.equal((dormant.get_node("FrontLayer") as Sprite3D).modulate, Color(0.68, 0.72, 0.65, 1.0), "dormant tint reaches the front sprite")
	assertions.equal(_mesh_color(dormant_mesh), base_color * Color(0.68, 0.72, 0.65, 1.0), "dormant tint reaches visible Mesh fallback")
	assertions.equal(_mesh_color(normal_mesh), normal_color, "dormant tint does not mutate a second instance's shared material")
	farming.call("_apply_visual_state", dormant, CropInstance.LifecycleState.WITHERED)
	assertions.equal((dormant.get_node("BackLayer") as Sprite3D).modulate, Color(0.82, 0.68, 0.38, 1.0), "withered tint replaces the back sprite tint")
	assertions.equal((dormant.get_node("FrontLayer") as Sprite3D).modulate, Color(0.82, 0.68, 0.38, 1.0), "withered tint replaces the front sprite tint")
	assertions.equal(_mesh_color(dormant_mesh), base_color * Color(0.82, 0.68, 0.38, 1.0), "withered Mesh tint derives from the untinted base")
	assertions.equal(_mesh_color(normal_mesh), normal_color, "withered tint keeps the second instance material unchanged")
	farming.free()
	dormant.free()
	normal.free()


func _first_mesh(root: Node) -> MeshInstance3D:
	for child in root.get_children():
		if child is MeshInstance3D:
			return child
	return null


func _mesh_color(mesh_instance: MeshInstance3D) -> Color:
	if mesh_instance == null or mesh_instance.mesh == null:
		return Color.TRANSPARENT
	var material := mesh_instance.material_override
	if material == null and mesh_instance.mesh.get_surface_count() > 0:
		material = mesh_instance.mesh.surface_get_material(0)
	return material.albedo_color if material is StandardMaterial3D else Color.TRANSPARENT
