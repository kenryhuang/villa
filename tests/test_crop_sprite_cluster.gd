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
	_test_sprite_only_missing_asset_fallback(assertions, tree)
	_test_painted_scene_keeps_hidden_fallback_resources(assertions, tree)
	_test_real_scene_fallback_tint_is_per_instance(assertions, tree)


func _test_sprite_only_missing_asset_fallback(assertions: TestAssert, tree: SceneTree) -> void:
	var cluster := ClusterScript.new() as CropSpriteCluster
	cluster.back_texture_paths.assign(["res://assets/crops/missing_back.png"])
	cluster.front_texture_paths.assign(["res://assets/crops/missing_front.png"])
	var received := {"reason": ""}
	cluster.painted_asset_failed.connect(func(reason: String) -> void: received.reason = reason)
	tree.root.add_child(cluster)
	var fallback := cluster.get_node_or_null("FallbackLayer") as Sprite3D
	assertions.truthy(fallback != null and fallback.visible, "sprite-only crop exposes a checker fallback")
	assertions.truthy(fallback != null and fallback.texture != null, "checker fallback owns a generated texture")
	assertions.truthy(not str(received.reason).is_empty(), "missing painted asset emits a diagnostic signal")
	cluster.free()


func _test_painted_scene_keeps_hidden_fallback_resources(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var painted := GRAIN_STAGE_SCENE.instantiate() as CropSpriteCluster
	var other := GRAIN_STAGE_SCENE.instantiate() as CropSpriteCluster
	tree.root.add_child(painted)
	tree.root.add_child(other)
	var painted_mesh := _first_mesh(painted)
	var other_mesh := _first_mesh(other)
	assertions.truthy(painted_mesh != null and not painted_mesh.visible, "painted crop hides its Mesh fallback")
	assertions.truthy(other_mesh != null and not other_mesh.visible, "second painted crop hides its Mesh fallback")
	var shared_mesh := painted_mesh.mesh
	var shared_material := _mesh_material(painted_mesh)
	assertions.truthy(shared_mesh == other_mesh.mesh, "painted instances initially share the fallback Mesh resource")
	assertions.truthy(shared_material == _mesh_material(other_mesh), "painted instances initially share the fallback material")
	var back := painted.get_node("BackLayer") as Sprite3D
	var front := painted.get_node("FrontLayer") as Sprite3D
	var back_modulate := back.modulate
	var front_modulate := front.modulate
	var farming = FarmingSystemScript.new()
	farming.call("_apply_visual_state", painted, CropInstance.LifecycleState.GROWING)
	assertions.truthy(painted_mesh.mesh == shared_mesh, "normal painted crop keeps the shared hidden Mesh")
	assertions.truthy(_mesh_material(painted_mesh) == shared_material, "normal painted crop keeps the shared hidden material")
	assertions.truthy(not painted_mesh.has_meta("crop_state_base_surface_colors"), "normal painted crop creates no Mesh tint metadata")
	assertions.truthy(not painted_mesh.has_meta("crop_state_base_override_color"), "normal painted crop creates no override tint metadata")
	farming.call("_apply_visual_state", painted, CropInstance.LifecycleState.DORMANT)
	assertions.truthy(painted_mesh.mesh == shared_mesh, "dormant painted crop does not duplicate a hidden Mesh fallback")
	assertions.truthy(_mesh_material(painted_mesh) == shared_material, "dormant painted crop does not duplicate a hidden fallback material")
	assertions.truthy(not painted_mesh.has_meta("crop_state_base_surface_colors"), "hidden fallback remains free of tint metadata")
	assertions.equal(back.modulate, back_modulate * Color(0.68, 0.72, 0.65, 1.0), "dormant tint still reaches painted back sprite")
	assertions.equal(front.modulate, front_modulate * Color(0.68, 0.72, 0.65, 1.0), "dormant tint still reaches painted front sprite")
	assertions.truthy(other_mesh.mesh == shared_mesh, "painted tint leaves another instance's Mesh shared")
	assertions.truthy(_mesh_material(other_mesh) == shared_material, "painted tint leaves another instance's material shared")
	farming.free()
	painted.free()
	other.free()


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
	var shared_mesh := dormant_mesh.mesh
	var shared_material := _mesh_material(dormant_mesh)
	assertions.truthy(shared_mesh == normal_mesh.mesh, "fallback instances initially share their Mesh resource")
	assertions.truthy(shared_material == _mesh_material(normal_mesh), "fallback instances initially share their material")
	var farming = FarmingSystemScript.new()
	farming.call("_apply_visual_state", dormant, CropInstance.LifecycleState.DORMANT)
	assertions.equal((dormant.get_node("BackLayer") as Sprite3D).modulate, Color(0.68, 0.72, 0.65, 1.0), "dormant tint reaches the back sprite")
	assertions.equal((dormant.get_node("FrontLayer") as Sprite3D).modulate, Color(0.68, 0.72, 0.65, 1.0), "dormant tint reaches the front sprite")
	assertions.equal(_mesh_color(dormant_mesh), base_color * Color(0.68, 0.72, 0.65, 1.0), "dormant tint reaches visible Mesh fallback")
	assertions.truthy(dormant_mesh.mesh != shared_mesh, "visible tinted fallback receives a private Mesh")
	assertions.truthy(_mesh_material(dormant_mesh) != shared_material, "visible tinted fallback receives a private material")
	assertions.equal(_mesh_color(normal_mesh), normal_color, "dormant tint does not mutate a second instance's shared material")
	var owned_mesh := dormant_mesh.mesh
	var owned_material := _mesh_material(dormant_mesh)
	farming.call("_apply_visual_state", dormant, CropInstance.LifecycleState.WITHERED)
	assertions.equal((dormant.get_node("BackLayer") as Sprite3D).modulate, Color(0.82, 0.68, 0.38, 1.0), "withered tint replaces the back sprite tint")
	assertions.equal((dormant.get_node("FrontLayer") as Sprite3D).modulate, Color(0.82, 0.68, 0.38, 1.0), "withered tint replaces the front sprite tint")
	assertions.equal(_mesh_color(dormant_mesh), base_color * Color(0.82, 0.68, 0.38, 1.0), "withered Mesh tint derives from the untinted base")
	assertions.truthy(dormant_mesh.mesh == owned_mesh, "changing tint reuses the private Mesh")
	assertions.truthy(_mesh_material(dormant_mesh) == owned_material, "changing tint reuses the private material")
	assertions.equal(_mesh_color(normal_mesh), normal_color, "withered tint keeps the second instance material unchanged")
	dormant_mesh.visible = false
	farming.call("_apply_visual_state", dormant, CropInstance.LifecycleState.GROWING)
	assertions.equal(_mesh_color(dormant_mesh), base_color, "white state restores the untinted fallback color while hidden")
	assertions.truthy(dormant_mesh.mesh == owned_mesh, "white restore does not duplicate the private Mesh")
	assertions.truthy(_mesh_material(dormant_mesh) == owned_material, "white restore does not duplicate the private material")
	assertions.equal((dormant.get_node("BackLayer") as Sprite3D).modulate, Color.WHITE, "white state restores the back sprite")
	assertions.equal((dormant.get_node("FrontLayer") as Sprite3D).modulate, Color.WHITE, "white state restores the front sprite")
	farming.free()
	dormant.free()
	normal.free()


func _first_mesh(root: Node) -> MeshInstance3D:
	for child in root.get_children():
		if child is MeshInstance3D:
			return child
	return null


func _mesh_color(mesh_instance: MeshInstance3D) -> Color:
	var material := _mesh_material(mesh_instance)
	return material.albedo_color if material is StandardMaterial3D else Color.TRANSPARENT


func _mesh_material(mesh_instance: MeshInstance3D) -> Material:
	if mesh_instance == null or mesh_instance.mesh == null:
		return null
	var material := mesh_instance.material_override
	if material == null and mesh_instance.mesh.get_surface_count() > 0:
		material = mesh_instance.mesh.surface_get_material(0)
	return material
