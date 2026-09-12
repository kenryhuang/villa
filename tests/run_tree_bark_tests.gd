extends SceneTree
## Validate imported textures survive wind overrides and every LOD switch.
const TreeModel = preload("res://scripts/vegetation/diverse_tree.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	for species: String in TreeModel.TREE_SPECIES:
		var tree := TreeModel.new()
		tree.species = species
		tree.forced_lod = 0
		root.add_child(tree)
		var albedo: Texture2D
		var normal: Texture2D
		for lod in 3:
			tree.forced_lod = lod
			tree.update_lod(0)
			var model: Node3D = tree.lod_nodes[lod]
			var trunk: MeshInstance3D = model.find_children("Trunk*", "MeshInstance3D", true, false)[0]
			var arrays := trunk.mesh.surface_get_arrays(0)
			check(arrays[Mesh.ARRAY_TEX_UV] != null and arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size(), species+": trunk UVs present")
			check(arrays[Mesh.ARRAY_TANGENT] != null and not arrays[Mesh.ARRAY_TANGENT].is_empty(), species+": tangent space for normal map")
			var mat := trunk.material_override as ShaderMaterial
			check(mat != null and mat.get_shader_parameter("textured_bark") == true, species+": wind retains bark textures")
			var current_albedo: Texture2D = mat.get_shader_parameter("bark_albedo")
			var current_normal: Texture2D = mat.get_shader_parameter("bark_normal")
			check(current_albedo != null and current_albedo.get_size() == Vector2(1024,1024), species+": albedo imported")
			check(current_normal != null and current_normal.get_size() == Vector2(1024,1024), species+": normal imported")
			if lod == 0:
				albedo = current_albedo
				normal = current_normal
				check(albedo.get_image().has_mipmaps() and normal.get_image().has_mipmaps(), species+": mipmaps prevent distant grain shimmer")
			check(current_albedo == albedo and current_normal == normal, species+": all LODs share texture resources")
			var leaves: MeshInstance3D = model.find_children("Leaves*", "MeshInstance3D", true, false)[0]
			check(leaves.material_override != mat and leaves.material_override.get_shader_parameter("foliage") == true, species+": leaves keep original material behavior")
		tree.free()
	print("Tree bark: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
