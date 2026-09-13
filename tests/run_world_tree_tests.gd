extends SceneTree

const TreeScript = preload("res://scripts/vegetation/diverse_tree.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	if "--farm-test" not in OS.get_cmdline_user_args(): quit(2); return
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	var farm: Node3D = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var session: Node = farm.farm_session
	session.season.set_process(false)
	session.living_world.set_process(false)
	session.player.set_physics_process(false)
	check(not session.auto_save and not session.agent_runtime.service_enabled, "Isolated scene does not save player data or contact providers")
	var all_trees := get_nodes_in_group("farm_world_trees")
	var trial_trees := get_nodes_in_group("mawais_trial_trees")
	var pines := get_nodes_in_group("t1_trial_trees")
	var trees := all_trees.filter(func(tree): return not tree.is_in_group("mawais_trial_trees") and not tree.is_in_group("t1_trial_trees"))
	check(all_trees.size() == 34 and trees.size() == 28 and trial_trees.size() == 3 and pines.size() == 3, "Two sets of three trial trees replace existing core sites; total stays 34")
	var trial_positions := [Vector2(-8,-5),Vector2(10,5),Vector2(5,-14)]
	var trial_mesh: Mesh = null
	await physics_frame; await physics_frame
	for tree: Node3D in trial_trees:
		var point := Vector2(tree.global_position.x,tree.global_position.z)
		check(point in trial_positions, "Imported tree occupies an existing reserved core site")
		check(absf(tree.global_position.y-Farm3DTerrainProfile.surface_height(point.x,point.y))<.01, "Trial tree base meets terrain")
		var cell := session.grid.world_to_grid(point.x,point.y) as Vector2i
		check(not session.grid.is_navigation_cell_walkable(cell), "NPC navigation avoids imported trunk")
		check(session.grid.get_cell(cell.x,cell.y).state == GridCell.State.DECORATION, "Tree site remains reserved against planting/building")
		check(tree.get_node("TrunkCollision").collision_layer == 1, "Imported trunk blocks player")
		check(tree.get_node("CanopyCollision").collision_layer == 4, "Imported crown uses camera/golf collision layer")
		var meshes := tree.get_node("Model").find_children("*","MeshInstance3D",true,false)
		check(meshes.size()==1 and meshes[0].mesh.get_surface_count()==2, "Trial uses one mesh with bark and foliage surfaces")
		if trial_mesh != null: check(meshes[0].mesh==trial_mesh, "Trial instances share the imported mesh")
		trial_mesh=meshes[0].mesh
		var bark_found := false
		for surface in 2:
			var material := meshes[0].get_active_material(surface) as ShaderMaterial
			check(material != null, "Imported tree uses its material-preserving wind shader")
			if material != null and material.get_shader_parameter("textured"):
				bark_found=material.get_shader_parameter("albedo_map") is Texture2D
		check(bark_found, "Wind keeps the original bark texture")
		var query := PhysicsRayQueryParameters3D.create(tree.global_position+Vector3(-2,1,0),tree.global_position+Vector3(2,1,0),1)
		var hit := tree.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider==tree.get_node("TrunkCollision"), "Physics ray hits imported trunk")
	var pine_positions := [Vector2(-10,2),Vector2(12,-9),Vector2(-5,-12)]
	var pine_meshes := {}
	for tree: Node3D in pines:
		var point := Vector2(tree.global_position.x,tree.global_position.z)
		check(point in pine_positions, "Pine occupies an existing core tree site")
		check(absf(tree.global_position.y-Farm3DTerrainProfile.surface_height(point.x,point.y))<.01, "Pine base meets terrain")
		var cell := session.grid.world_to_grid(point.x,point.y) as Vector2i
		check(not session.grid.is_navigation_cell_walkable(cell), "NPC navigation avoids pine trunk")
		check(session.grid.get_cell(cell.x,cell.y).state in [GridCell.State.DECORATION, GridCell.State.ROAD], "Existing pine site stays on non-farmable terrain")
		check(tree.get_node("TrunkCollision").collision_layer == 1, "Pine trunk blocks player")
		check(tree.get_node("CanopyCollision").collision_layer == 4, "Pine crown uses camera/golf layer")
		var meshes := tree.get_node("Model").find_children("*","MeshInstance3D",true,false)
		check(meshes.size() == 2, "Pine has bark and needle meshes")
		var needles_found := false
		var bark_found := false
		for mesh: MeshInstance3D in meshes:
			if pine_meshes.has(mesh.name): check(mesh.mesh == pine_meshes[mesh.name], "Pine instances share imported geometry")
			pine_meshes[mesh.name] = mesh.mesh
			var material := mesh.get_active_material(0)
			if material is ShaderMaterial:
				needles_found = material.shader.code.contains("COLOR.rgb") and mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR].size() > 0
			elif material is BaseMaterial3D:
				bark_found = material.albedo_texture != null and material.normal_texture != null and material.roughness_texture != null
		check(needles_found, "Pine retains needle colours and imported shader")
		check(bark_found, "Pine retains three bark PBR maps")
		var query := PhysicsRayQueryParameters3D.create(tree.global_position+Vector3(-2,1,0),tree.global_position+Vector3(2,1,0),1)
		var hit := tree.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider == tree.get_node("TrunkCollision"), "Physics ray hits pine trunk")
	print("Trial tree checks: %d checks, %d failures" % [checks,failures])
	if "--trial-trees-only" in OS.get_cmdline_user_args():
		farm.queue_free(); await process_frame; await process_frame
		quit(0 if failures == 0 else 1)
		return
	var distribution := {}
	var positions := {}
	for tree: Node3D in trees:
		tree.set_process(false)
		check(tree.species_index == TreeScript.choose_world_species(tree.global_position), "Species is stable for each world position")
		distribution[tree.species] = int(distribution.get(tree.species, 0)) + 1
		positions[Vector2(tree.global_position.x, tree.global_position.z)] = true
		var cell: Vector2i = session.grid.world_to_grid(tree.global_position.x, tree.global_position.z)
		check(not session.grid.is_navigation_cell_walkable(cell), "NPC navigation still avoids trunk at " + str(tree.global_position))
		var body: Node = tree.get_node("TrunkCollision")
		check(body.collision_layer == 1 and body.has_meta("golf_obstacle"), "Solid trunk remains a golf and player obstacle")
		check(tree.get_node("CanopyCollision").collision_layer == 4, "Crown is on camera/golf layer, not player layer")
		var model: Node = tree.lod_nodes[tree.current_lod]
		var trunk_mesh: MeshInstance3D = model.find_children("*","MeshInstance3D",true,false).filter(func(n): return str(n.name).begins_with("Trunk"))[0]
		var tips := {}
		for vertex: Vector3 in trunk_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if vertex.y > .85: continue
			var radius := Vector2(vertex.x,vertex.z).length()
			var angle := floori((atan2(vertex.z,vertex.x)+PI)/TAU*12)
			if radius > .42 and (not tips.has(angle) or radius > Vector2(tips[angle].x,tips[angle].z).length()): tips[angle] = vertex
		check(not tips.is_empty(), "Tree has shallow root tips")
		for vertex: Vector3 in tips.values():
			var tip := trunk_mesh.to_global(vertex)
			check(tip.y <= Farm3DTerrainProfile.surface_height(tip.x,tip.z)+.04, "Root tip follows slope instead of floating")
	check(distribution.size() == 6, "All six original Blender tree species occur in the current map")
	check(positions.size() == 28, "Retained trees have unique placements")
	for tree: Node3D in trial_trees + pines:
		positions[Vector2(tree.global_position.x,tree.global_position.z)]=true
	check(positions.size() == 34, "Trial replacements introduce no duplicate placements")
	var course_obstacles := farm.find_children("CourseObstacles","Node3D",true,false)
	check(course_obstacles.size() == 1 and course_obstacles[0].get_child_count() == Farm3DTerrainProfile.Golf.TREES.size(), "Golf trees have no leftover mulch ring meshes")
	var sample: Node3D = trees[0]
	var scale_factor: float = sample.global_basis.get_scale().x
	var trunk := sample.get_node("TrunkCollision")
	for pair in [[10, 0], [21, 0], [23, 1], [20, 1], [48, 2], [44, 2], [42, 1], [17, 0]]:
		sample.update_lod(float(pair[0]) * scale_factor)
		check(sample.current_lod == pair[1], "LOD switches with hysteresis: " + str(pair))
		check(sample.lod_nodes.filter(func(n): return n != null and n.visible).size() == 1, "Exactly one visual LOD, no duplicate foliage")
		check(sample.get_node("TrunkCollision") == trunk, "LOD changes preserve physical collision")
	await physics_frame; await physics_frame
	var start: Vector3 = sample.global_position
	var query := PhysicsRayQueryParameters3D.create(start + Vector3(-2, 1, 0), start + Vector3(2, 1, 0), 1)
	var hit := sample.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.collider == trunk, "Physics ray actually hits the replaced tree trunk")
	var replacement: Node3D = load("res://scenes/vegetation/tree_pack_world.tscn").instantiate()
	replacement.position = sample.global_position
	root.add_child(replacement)
	check(replacement.species == sample.species, "Recreating a tree after reload chooses the same species")
	replacement.free()
	var shrubs: Node3D = farm.get_node("LandscapeShrubs")
	var regions := {}
	var shrub_species := {}
	for placement in shrubs.placements:
		var point := Vector2(placement.position.x,placement.position.z)
		check(shrubs.suitable(point,placement.region,session.grid), "Shrub stays on suitable unoccupied ground away from golf routes")
		check(absf(placement.position.y - Farm3DTerrainProfile.surface_height(point.x,point.y)) < .15, "Shrub root follows terrain")
		regions[placement.region] = int(regions.get(placement.region,0))+1
		shrub_species[placement.species] = true
	check(regions.get("hills",0) == 64 and regions.get("mountains",0) == 36 and regions.get("golf",0) == 32, "132 shrubs across hills, mountains, and golf")
	check(shrub_species.size() == 2, "Both shrub species appear")
	check(shrubs.find_children("*","CollisionObject3D",true,false).is_empty(), "Low decorative shrubs add no invisible physics barriers")
	var twin := shrubs.get_script().new() as Node3D
	root.add_child(twin); twin.configure(session.grid)
	check(twin.placements == shrubs.placements, "Shrub placement is reproducible after reload")
	twin.free()
	print("SHRUB REGIONS ", JSON.stringify(regions), " BATCHES ", shrubs.batch_count)
	print("WORLD TREE DISTRIBUTION ", JSON.stringify(distribution))
	for i in 8: await process_frame
	farm.queue_free(); await process_frame; await process_frame
	print("World trees: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
