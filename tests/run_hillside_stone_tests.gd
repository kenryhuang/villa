extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	if "--farm-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var farm = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var stones = farm.get_node("HillsideStones")
	var shrubs = farm.get_node("LandscapeShrubs")
	var profile = load("res://scripts/farm3d/terrain_profile.gd")
	check(not farm.farm_session.auto_save,"Validation does not touch saves")
	check(stones.placements.size()==36,"Exactly 36 stones in a fresh farm")
	var counts := {"hills":0,"mountains":0}
	var species := {}
	var buried := true
	var visible := true
	var clear := true
	for p in stones.placements:
		counts[p.region] += 1
		species[p.species] = true
		var point := Vector2(p.position.x,p.position.z)
		clear = clear and shrubs.suitable(point,p.region,farm.farm_session.grid)
		clear = clear and not shrubs.placements.any(func(s): return point.distance_to(Vector2(s.position.x,s.position.z))<1.4)
		for base in stones._bases[p.species]:
			var v: Vector3 = p.basis*base+p.position
			buried = buried and v.y <= profile.surface_height(v.x,v.z)+.001
		var top := -INF
		for v: Vector3 in stones._meshes[p.species].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var world: Vector3 = p.basis*v+p.position
			top = maxf(top,world.y-profile.surface_height(world.x,world.z))
		visible = visible and top>.06
	check(counts.hills==24 and counts.mountains==12,"Sparse scatter stays in the two slope regions")
	check(species.size()==4,"All four scans are represented")
	check(clear,"Avoids water, trees, shrubs, roads, crops and buildings")
	check(buried and visible,"Stone bases meet the slope and tops remain exposed")
	var instances := 0
	for batch in stones.get_children(): instances += batch.multimesh.instance_count
	check(instances==36,"Batches draw every stone exactly once")
	var repeat = load("res://scripts/farm3d/hillside_stones.gd").new()
	farm.add_child(repeat)
	repeat.configure(farm.farm_session.grid,shrubs)
	check(repeat.placements==stones.placements,"Seed keeps the layout stable across reloads")
	check(not farm.has_node("PhotorealGrassTrial"),"Withdrawn grass stays disabled")
	print("Hillside stones: %d checks, %d failures"%[checks,failures])
	farm.queue_free()
	await process_frame
	quit(1 if failures else 0)
