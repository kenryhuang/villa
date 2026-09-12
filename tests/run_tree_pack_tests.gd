extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Tree sample tests timed out"); quit(1))
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func ray(world: World3D, from: Vector3, to: Vector3, mask: int) -> Dictionary:
	return world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))

func stem_width(mesh: Mesh, low: float, high: float) -> float:
	var min_x := INF
	var max_x := -INF
	for vertex: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if vertex.y >= low and vertex.y <= high:
			min_x = minf(min_x,vertex.x); max_x = maxf(max_x,vertex.x)
	return maxf(0,max_x-min_x)

func run() -> void:
	for species in ["golden_broadleaf", "green_columnar", "open_green"]:
		var tree: Node3D = load("res://scenes/vegetation/%s.tscn" % species).instantiate()
		root.add_child(tree)
		tree.set_process(false)
		var height := 6.0 if species == "golden_broadleaf" else (6.4 if species == "green_columnar" else 6.2)
		var previous_triangles := 1000000
		for level in range(3):
			tree.forced_lod = level; tree.update_lod(0)
			var triangles := 0
			var meshes: Array[Node] = tree.lod_nodes[level].find_children("*", "MeshInstance3D", true, false)
			check(meshes.size() == 2, species + " has only trunk and foliage meshes")
			var bounds := AABB()
			var first := true
			for mesh: MeshInstance3D in meshes:
				var local_bounds: AABB = mesh.transform * mesh.get_aabb()
				bounds = local_bounds if first else bounds.merge(local_bounds)
				first = false
				check(mesh.material_override is ShaderMaterial, "Wind shader assigned")
				for surface in mesh.mesh.get_surface_count():
					var arrays := mesh.mesh.surface_get_arrays(surface)
					triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
					check(arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_COLOR].size() > 0, "Vertex paint survives GLB import")
			check(triangles < previous_triangles * 0.65, "Each LOD significantly reduces geometry")
			check(triangles <= [71000, 38000, 16500][level], "Detailed small-leaf LOD stays within geometry budget")
			check(absf(bounds.position.y) < 0.12 and absf(bounds.end.y - height) < 0.75, "Tree stays rooted at ground and preserves crown height")
			var leaf_mesh: MeshInstance3D = meshes.filter(func(n): return str(n.name).begins_with("Leaves"))[0]
			var crown := leaf_mesh.get_aabb()
			check(maxf(crown.size.x,crown.size.z) > crown.size.y*1.4, "Canopy is broader than tall, not a narrow diamond")
			previous_triangles = triangles
			var trunk_mesh: MeshInstance3D = meshes.filter(func(n): return str(n.name).begins_with("Trunk"))[0]
			check(trunk_mesh.get_aabb().size.x > .75, "Natural root flare survives each LOD")
			var lower_width := stem_width(trunk_mesh.mesh,.3,.7)
			var upper_width := stem_width(trunk_mesh.mesh,1.3,1.8)
			check(lower_width > .45 and upper_width > lower_width*.65 and upper_width < lower_width*1.1, "Stem tapers gradually instead of narrowing sharply above its base")
		tree.forced_lod = -1
		var collider: StaticBody3D = tree.get_node("TrunkCollision")
		for pair in [[0, 0], [21, 0], [23, 1], [21, 1], [48, 2], [44, 2], [42, 1], [17, 0], [60, 2], [0, 0]]:
			tree.update_lod(float(pair[0]))
			check(tree.current_lod == pair[1], "Distance transition with hysteresis: %s" % str(pair))
			var visible_count := 0
			for lod in tree.lod_nodes:
				if lod != null and lod.visible: visible_count += 1
			check(visible_count == 1, "Exactly one LOD visible")
		check(tree.get_node("TrunkCollision") == collider, "LOD changes preserve collision identity")
		tree.forced_lod = 0
		tree.update_lod(100.0)
		check(tree.current_lod == 0, "Forced LOD overrides distance")
		tree.set_wind_enabled(false)
		check(tree.wind_materials[1].get_shader_parameter("wind_strength") == 0.0, "Wind can be disabled")
		tree.set_wind_enabled(true)
		check(tree.wind_materials[1].get_shader_parameter("wind_strength") > 0.0, "Wind can resume")
		await physics_frame
		await physics_frame
		var world := tree.get_world_3d()
		var trunk_hit := ray(world, Vector3(-1, 1, 0), Vector3(1, 1, 0), 1)
		check(not trunk_hit.is_empty() and trunk_hit.collider == collider, "Player physically hits trunk")
		check(ray(world, Vector3(-3, 4, 0), Vector3(3, 4, 0), 1).is_empty(), "Canopy does not block player layer")
		var crown_hit := ray(world, Vector3(-3, 4, 0), Vector3(3, 4, 0), 4)
		check(not crown_hit.is_empty() and crown_hit.collider.get_meta("golf_obstacle", false), "Camera/golf ray hits canopy")
		tree.free()
	for species in ["meadow_shrub","sage_shrub"]:
		var previous := 100000
		for level in 3:
			var model: Node3D = load("res://assets/models/vegetation/tree_pack/%s_lod%d.glb" % [species,level]).instantiate()
			var meshes := model.find_children("*","MeshInstance3D",true,false)
			check(meshes.size() == 2, "Shrub contains only branches and foliage, no source floor")
			var triangles := 0
			for mesh: MeshInstance3D in meshes:
				for surface in mesh.mesh.get_surface_count():
					var arrays := mesh.mesh.surface_get_arrays(surface)
					triangles += arrays[Mesh.ARRAY_INDEX].size()/3
					check(arrays[Mesh.ARRAY_COLOR].size() > 0, "Shrub keeps authored colors")
			check(triangles <= [2700,1150,450][level] and triangles < previous*.65, "Shrub LOD respects density budget")
			previous = triangles
			model.free()
	var preview: Node3D = load("res://scenes/preview/tree_pack_preview.tscn").instantiate()
	root.add_child(preview)
	check(preview.samples.size() == 3 and preview.shrubs.size() == 2 and preview.get_node_or_null("FarmerReference") != null, "Preview shows three trees and two shrubs with a character scale reference")
	for key in [KEY_L, KEY_W]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = true
		preview._unhandled_input(event)
	check(preview.selected_lod == 0 and preview.samples[0].forced_lod == 0, "L switches preview LOD")
	check(not preview.wind and not preview.samples[1].wind_enabled, "W switches preview wind")
	preview.free()
	print("Tree pack samples: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
