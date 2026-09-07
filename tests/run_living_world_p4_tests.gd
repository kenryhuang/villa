extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): quit(1))
	run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var s: Farm3DSession = scene.farm_session
	s.season.set_process(false)
	check(preload("res://scripts/farm3d/living_world_scenarios.gd").setup(scene, "P4"), "P4 formal fixture")
	var w: Node = s.living_world
	var c: RefCounted = w.construction
	var sites: Array = c.sites("lao_li")
	check(not sites.is_empty(), "Can survey real legal public land without sufficient materials")
	if sites.is_empty(): quit(1); return
	var site: Dictionary = sites[0]
	check(c.reserve("lao_li", "lease", site.gx, site.gz).ok, "Exclusive expiring site lease")
	check(not c.reserve("farmer_ahe", "race", site.gx, site.gz).ok, "Second actor cannot reserve same footprint")
	check(not s.buildings.diagnose_placement("windmill", site.gx, site.gz, "player", false).allowed, "Player placement also respects NPC lease")
	check(not c.reserve("lao_li", "water", -10000, -10000).ok, "Invalid protected land rejected")
	check(not c.start("lao_li", "build", "lease").ok, "Cannot build with insufficient materials")
	var npc: NpcEconomyState = s.npc_economy.get_npc_state("lao_li")
	npc.inventory = {"plank": 12, "stone_brick": 8, "rope": 2}
	var body: Node3D = w.actor("lao_li")
	body.position = Vector3(60, 0, 60)
	var cell: GridCell = s.grid.get_cell(site.gx, site.gz)
	s.player.position = cell.world_position_3d() + Vector3.LEFT * 1.2
	check(not c.start("lao_li", "build", "lease").ok, "Nearby player cannot substitute for faraway NPC")
	body.position = Vector3(site.approach.x, cell.world_position_3d().y, site.approach.z)
	s.player.position = Vector3(60, 0, 60)
	var inventory_before: Array = s.inventory.slots.duplicate(true)
	var result: Dictionary = c.start("lao_li", "build", "lease")
	check(result.ok, "NPC uses original 3D placement at own position")
	if not result.ok: quit(1); return
	var building: BuildingInstance = w.building(result.building_id)
	check(building.owner_id == "lao_li" and not building.is_construction_complete() and not building.service_policy.open, "Real owned construction starts closed")
	check(npc.inventory.get("plank", 0) == 0 and s.inventory.slots == inventory_before, "Only NPC materials spent")
	check(c.start("lao_li", "build", "lease").ok and s.buildings.get_all_buildings().size() == 2, "Build retry cannot create free duplicate")
	check(s.save_game() and s.load_game(), "Physical construction and lease persist")
	building = w.building(result.building_id)
	check(building != null and building.owner_id == "lao_li", "Reload keeps physical owner")
	check(c.cancel("lao_li", "build").ok, "Unfinished construction cancellation allowed")
	npc = s.npc_economy.get_npc_state("lao_li")
	check(int(npc.inventory.plank) == 12 and c.cancel("lao_li", "build").ok and int(npc.inventory.plank) == 12, "Cancellation refunds materials once")
	check(c.reserve("lao_li", "second", site.gx, site.gz).ok, "Cancelled construction frees site")
	result = c.start("lao_li", "complete", "second")
	check(result.ok, "Can rebuild using returned materials")
	building = w.building(result.building_id)
	building.advance_construction(9)
	c.advance()
	check(building.is_construction_complete() and c.builds.complete.status == "completed", "Original construction stages finish")
	check(not c.cancel("lao_li", "complete").ok, "Finished construction cannot refund")
	var policy: Dictionary = building.service_policy.duplicate(true)
	policy.open = true
	policy.fees = {"flour": 7}
	check(s.production.building_service.set_policy(building, "lao_li", policy, int(policy.version)).ok, "Owner opens real fee-bearing business")
	check(not s.production.building_service.set_policy(building, "farmer_ahe", policy, int(policy.version)).ok, "Others cannot set owner prices")
	check(s.save_game() and s.load_game(), "Completed business persists")
	building = w.building(result.building_id)
	check(s.buildings.remove_building(building, "lao_li"), "Owner may demolish unused finished business")
	check(s.save_game() and s.load_game(), "Historical construction records tolerate lawful demolition")
	print("P4: %d checks, %d failures" % [checks, failures])
	scene.free()
	quit(0 if failures == 0 else 1)
