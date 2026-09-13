extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	if "--farm-test" not in OS.get_cmdline_user_args(): quit(2);return
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error(label)

func run() -> void:
	var farm: Node3D = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm);farm.set_process(false)
	farm.farm_session.season.set_process(false)
	farm.farm_session.living_world.set_process(false)
	farm.player.set_physics_process(false)
	check(not farm.has_node("PhotorealGrassTrial"), "Grass trial stays disabled in the formal farm")
	var grass: Node3D = load("res://scripts/farm3d/photoreal_grass_trial.gd").new()
	farm.add_child(grass)
	grass.configure(farm.farm_session.grid)
	var grid: Farm3DFlatGrid = farm.farm_session.grid
	check(not farm.farm_session.auto_save and not farm.farm_session.agent_runtime.service_enabled,"Test stays isolated from saves and providers")
	check(grass.placements.size()>100 and grass.placements.size()<600,"Grass trial stays within a small instance budget")
	check(grass.get_child_count()<=12,"Two patches use at most twelve LOD batches")
	check(grass.find_children("*","CollisionObject3D",true,false).is_empty(),"Grass adds no player or camera obstacles")
	var patches := {}
	var valid_ground := true
	var bounded := true
	for p: Dictionary in grass.placements:
		patches[p.patch]=true
		var point := Vector2(p.position.x,p.position.z)
		valid_ground = valid_ground and grass.suitable(point) and absf(p.position.y-Farm3DTerrainProfile.surface_height(point.x,point.y)+.012)<.001
		var patch: Dictionary = grass.PATCHES[p.patch]
		bounded = bounded and ((point-patch.center)/patch.radii).length()<1.0
	check(patches.size()==2 and bounded,"Grass only occupies the two requested trial areas")
	check(valid_ground,"Tufts meet the ground and avoid roads, crops, buildings and tree blockers")
	for variant in 3:
		var near_mesh: Mesh = grass._meshes[Vector2i(variant,0)]
		var far_mesh: Mesh = grass._meshes[Vector2i(variant,1)]
		check(far_mesh.surface_get_array_index_len(0)<near_mesh.surface_get_array_index_len(0)/3,"Far grass reduces geometry by more than two thirds")
		var arrays := near_mesh.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_COLOR].size()==arrays[Mesh.ARRAY_VERTEX].size(),"Blade root/tip colours survive import")
		check(arrays[Mesh.ARRAY_TEX_UV].size()==arrays[Mesh.ARRAY_VERTEX].size(),"Root-fixed wind weights survive import")
	var original: Array = grass.placements.duplicate(true)
	var p: Vector3 = original[original.size()/2].position
	var cell := grid.world_to_grid(p.x,p.z)
	check(grid.set_cell_state(cell.x,cell.y,GridCell.State.BUILDING),"A building can occupy a trial grass cell")
	await process_frame;await process_frame
	check(grass.placements.size()<original.size(),"Building event clears affected grass")
	check(not grass.placements.any(func(item): return grid.world_to_grid(item.position.x,item.position.z)==cell),"No grass remains inside the building cell")
	check(grid.set_cell_state(cell.x,cell.y,GridCell.State.WASTELAND),"Building removal restores the ground state")
	await process_frame;await process_frame
	check(grass.placements==original,"Grass placement returns deterministically after removal")
	check(grid.set_cell_state(cell.x,cell.y,GridCell.State.FARMLAND),"Trial grass does not prevent tilling")
	await process_frame;await process_frame
	check(not grass.placements.any(func(item): return grid.world_to_grid(item.position.x,item.position.z)==cell),"Tilling event clears the new farmland")
	farm.queue_free();await process_frame;await process_frame
	print("Grass trial: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
