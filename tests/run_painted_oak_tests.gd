extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for _frame in count:
		await process_frame

func _run() -> void:
	var oak_path := "res://scenes/vegetation/painted_oak.tscn"
	var preview_path := "res://scenes/preview/tree_3d_preview.tscn"
	_check(ResourceLoader.exists(oak_path), "Reusable painted-oak scene exists")
	_check(ResourceLoader.exists(preview_path), "Single-tree preview scene exists")
	if not failures.is_empty():
		quit(1)
		return
	var oak := (load(oak_path) as PackedScene).instantiate()
	root.add_child(oak)
	await _frames(3)
	var meshes := oak.find_children("*", "MeshInstance3D", true, false)
	_check(not meshes.is_empty(), "Imported oak contains real render meshes")
	var material_surfaces := 0
	var textured_surfaces := 0
	var vertex_colored_surfaces := 0
	var color_surfaces := 0
	var varied_color_surfaces := 0
	var non_white_color_surfaces := 0
	var trunk_bounds := AABB()
	for mesh_node in meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh != null:
			if mesh_instance.name.to_lower().contains("trunk"):
				trunk_bounds = mesh_instance.get_aabb()
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface)
				if material != null:
					material_surfaces += 1
					if material is StandardMaterial3D and material.albedo_texture != null:
						textured_surfaces += 1
					if material is StandardMaterial3D and material.vertex_color_use_as_albedo:
						vertex_colored_surfaces += 1
				var colors := mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR] as PackedColorArray
				if not colors.is_empty():
					color_surfaces += 1
					var first_color := colors[0]
					var midpoint_color := colors[colors.size() / 2]
					var last_color := colors[colors.size() - 1]
					var is_varied := first_color != midpoint_color or first_color != last_color
					if is_varied:
						varied_color_surfaces += 1
					if first_color.r < 0.97 or first_color.g < 0.97 or first_color.b < 0.97 or midpoint_color.r < 0.97 or midpoint_color.g < 0.97 or midpoint_color.b < 0.97 or last_color.r < 0.97 or last_color.g < 0.97 or last_color.b < 0.97:
						non_white_color_surfaces += 1
					print("OAK IMPORT mesh=%s surface=%d material=%s vertex_color_use_as_albedo=%s colors=%d first=%s middle=%s last=%s" % [mesh_instance.name, surface, material.resource_name if material != null else "none", material.vertex_color_use_as_albedo if material is StandardMaterial3D else false, colors.size(), first_color, midpoint_color, last_color])
	_check(material_surfaces >= 2, "Oak mesh imports separate authored trunk and foliage surfaces")
	_check(textured_surfaces > 0, "Oak mesh imports a textured StandardMaterial3D surface")
	_check(vertex_colored_surfaces >= 2, "Oak trunk and foliage materials use imported painterly vertex colors")
	_check(color_surfaces >= 2 and varied_color_surfaces >= 2, "Oak trunk and foliage preserve varied COLOR_0 data")
	_check(non_white_color_surfaces >= 2, "Oak COLOR_0 samples are not flat white")
	_check(trunk_bounds.size.y > 4.5 and trunk_bounds.position.y < 0.15, "Trunk mesh keeps roots at the ground and rises into the crown")
	var trunk := oak.get_node("TrunkCollision") as StaticBody3D
	var canopy := oak.get_node("CanopyCameraCollision") as StaticBody3D
	_check(trunk.collision_layer == 1, "Trunk collision is on world layer 1")
	_check(canopy.collision_layer == 4, "Canopy collision is camera-only layer 4")
	oak.queue_free()

	var preview := (load(preview_path) as PackedScene).instantiate()
	root.add_child(preview)
	await _frames(3)
	var camera := preview.get_node("Camera3D") as Camera3D
	var view_rect := preview.get_viewport().get_visible_rect()
	_check(view_rect.has_point(camera.unproject_position(Vector3.ZERO)) and view_rect.has_point(camera.unproject_position(Vector3(0, 6, 0))), "Default view frames both the roots and tree crown")
	var start_position := camera.global_position
	preview._set_view(PI * 0.5)
	_check(camera.global_position.distance_to(start_position) > 5.0, "Side view moves the camera around the tree")
	_check(preview.get_node("FarmerReference").find_children("*", "MeshInstance3D", true, false).size() > 0, "Preview imports the actual farmer model as a scale reference")
	preview.queue_free()
	await process_frame
	print("PAINTED OAK: %s" % ("PASS (%d checks)" % checks if failures.is_empty() else "FAIL (%d/%d checks)" % [failures.size(), checks]))
	quit(0 if failures.is_empty() else 1)
