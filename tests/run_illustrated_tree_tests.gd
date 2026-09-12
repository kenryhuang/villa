extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	var report: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/vegetation/illustrated_trees/model_report.json"))
	for spec in report:
		var previous := 1000000
		for level in 3:
			var packed = load("res://assets/models/vegetation/illustrated_trees/%s_lod%d.glb" % [spec.id, level]) as PackedScene
			check(packed != null, "%s LOD%d imports" % [spec.id, level])
			if packed == null: continue
			var model := packed.instantiate() as Node3D
			var meshes := model.find_children("*", "MeshInstance3D", true, false)
			check(meshes.size() == 2, "Only trunk and leaves exported; no studio floor or construction helpers")
			var triangles := 0
			for mesh: MeshInstance3D in meshes:
				var box := mesh.get_aabb()
				check(box.size.y > .1 and box.size.y < 10.0, "Metre scale, upright 3D geometry")
				for surface in mesh.mesh.get_surface_count():
					var arrays := mesh.mesh.surface_get_arrays(surface)
					var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
					triangles += indices.size() / 3
					var material := mesh.get_active_material(surface) as BaseMaterial3D
					check(material != null and material.vertex_color_use_as_albedo, "Authored brush pigments survive Godot import")
					check(material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Opaque leaf geometry needs no transparent floor/card")
					if str(mesh.name).begins_with("Leaves"):
						check(material.albedo_texture != null, "Original foliage texture imported")
			check(triangles <= 40000 and triangles < previous, "Each LOD reduces geometry within the per-tree budget")
			previous = triangles
			model.free()
	var preview: Node3D = load("res://scenes/preview/illustrated_tree_preview.tscn").instantiate()
	root.add_child(preview)
	for index in 5:
		var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_1 + index
		preview._unhandled_input(key)
		check(preview.selected_tree == index and is_instance_valid(preview.model), "Tree selection changes the actual model")
	var bare := InputEventKey.new(); bare.pressed = true; bare.keycode = KEY_B
	preview._unhandled_input(bare)
	check(not preview.show_leaves and preview.model.find_children("Leaves*", "MeshInstance3D", true, false).all(func(mesh): return not mesh.visible), "B exposes the actual trunk")
	var lod := InputEventKey.new(); lod.pressed = true; lod.keycode = KEY_L
	preview._unhandled_input(lod)
	check(preview.selected_lod == 1 and not preview.show_leaves, "LOD switches while retaining trunk-only review")
	for i in 8: await process_frame
	preview.queue_free(); await process_frame
	print("Illustrated trees: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
