extends RefCounted

## The map labels and agent navigation share one place vocabulary.
const Terrain = preload("res://scripts/farm3d/terrain_profile.gd")
const PLACES := [
	{"id":"farm", "name":"中央农庄", "aliases":["农庄","农场","中央农场"], "point":Vector2(0,-17), "label":true},
	{"id":"village", "name":"村庄", "aliases":["村里","村中心"], "point":Vector2(12,-8)},
	{"id":"forest", "name":"西北林地", "aliases":["森林","林地"], "point":Vector2(-32.5,-18.5), "label":true},
	{"id":"hills", "name":"西部丘陵", "aliases":["丘陵","西山"], "point":Vector2(-45.5,32.5), "label":true},
	{"id":"mountains", "name":"北部山地", "aliases":["山地","北山","山脚"], "point":Vector2(-15,-36), "label_point":Vector2(-15,-56), "label":true},
	{"id":"canyon", "name":"东北峡谷", "aliases":["峡谷","河谷"], "point":Vector2(26,-28), "label_point":Vector2(53,-45), "label":true},
	{"id":"plain", "name":"东部平原", "aliases":["平原","草原","东岸"], "point":Vector2(60,40), "label":true},
	{"id":"creek", "name":"东部河岸", "aliases":["河岸","溪边","河边","河流"], "point":Vector2(28.5,18.5), "label_point":Vector2(58,-9), "label":true},
	{"id":"bridge", "name":"东河木桥", "aliases":["木桥","桥头","桥"], "point":Vector2(40,18)},
	{"id":"sand", "name":"南部沙地", "aliases":["沙地","沙漠","沙丘"], "point":Vector2(-48,83), "label":true},
	{"id":"lake", "name":"南湖", "aliases":["湖","南部湖泊","湖边","南边湖边","南边湖泊","湖畔"], "point":Vector2(-6,84), "label_point":Vector2(-6,108), "label":true},
	{"id":"lake_north", "name":"南湖北岸", "aliases":["湖泊北岸","北岸","北钓点"], "point":Vector2(-6,84)},
	{"id":"lake_west", "name":"南湖西岸", "aliases":["湖泊西岸","西岸","钓鱼点","钓鱼","垂钓"], "point":Vector2(-39.5,106.5)},
	{"id":"lake_south", "name":"南湖南岸", "aliases":["湖泊南岸","南岸","南钓点"], "point":Vector2(-6,132)},
	{"id":"golf", "name":"湖西高尔夫球场", "aliases":["golf_course","高尔夫","球场","七洞球场"], "point":Terrain.Golf.ENTRANCE, "label_point":Vector2(-137,40), "label":true},
]

static func entries(world: Node, actor: String) -> Array:
	var result: Array = []
	for place in PLACES:
		var row := {"id": place.id, "name": place.name, "aliases": place.aliases.duplicate()}
		var point: Vector2 = place.point
		if world.knowledge.SITES.has(place.id):
			row.merge(world.knowledge.field_status(actor, place.id))
			var site: Vector3 = world.knowledge.site(place.id)
			if site.is_finite(): point = Vector2(site.x,site.z)
		row.merge(navigation(world,actor,point),true)
		if str(place.id).begins_with("lake"): row.description = "坐标是可步行的岸边落点，不是湖水中央。可散步、陪伴；钓鱼/集体活动按 social 规则执行。"
		result.append(row)
	var market: Vector2 = world.session.market_site
	result.append({"id":"market", "name":"村庄市集", "aliases":["市集","市场","商行"]}.merged(navigation(world,actor,market)))
	var inn: Vector3 = world.work.location("village_inn",actor)
	result.append({"id":"village_inn", "name":"村庄旅店", "aliases":["旅店","客栈","水站"], "description":"旅店饮水服务目前在市集服务点办理；start_leisure(drink,village_inn)自动前往。"}.merged(navigation(world,actor,Vector2(inn.x,inn.z))))
	if world.society.cooperative != null:
		var cell: GridCell = world.society.cooperative.get_plot_cell("village_coop",40)
		if cell != null: result.append({"id":"village_coop", "name":"村庄合作社", "aliases":["合作社","公田"]}.merged(navigation(world,actor,cell.world_position())))
	# Keep major destinations on page one; detailed shore sites follow them.
	var major := ["farm","market","lake","golf","forest","hills","creek","mountains","sand","village"]
	return result.filter(func(p): return p.id in major) + result.filter(func(p): return p.id not in major)

static func navigation(world: Node, actor: String, base: Vector2) -> Dictionary:
	var grid: GridSystem = world.session.grid
	var body: Node3D = world.actor(actor)
	var center := grid.world_to_grid(base.x,base.y)
	var destination := base if grid.is_navigation_cell_walkable(center) else Vector2.INF
	for radius in range(5):
		if destination.is_finite(): break
		for dx in range(-radius,radius+1):
			for dz in range(-radius,radius+1):
				if radius > 0 and maxi(absi(dx),absi(dz)) != radius: continue
				var cell := center + Vector2i(dx,dz)
				if grid.is_navigation_cell_walkable(cell):
					destination = grid.grid_to_world(cell.x,cell.y)
					break
			if destination.is_finite(): break
		if destination.is_finite(): break
	var reachable := destination.is_finite() and body != null
	if reachable: reachable = not world.work.paths.find_path_cells(grid.world_to_grid(body.position.x,body.position.z),grid.world_to_grid(destination.x,destination.y)).is_empty()
	var distance := Vector2(body.position.x,body.position.z).distance_to(destination) if body != null and destination.is_finite() else -1.0
	return {"position": {"x":destination.x,"z":destination.y} if destination.is_finite() else {}, "reachable":reachable,
		"distance":distance, "arrived":reachable and distance <= 2.5,
		"navigation_action":{"tool_name":"move","arguments":{"x":destination.x,"z":destination.y}} if reachable else {},
		"navigation_rule":"Use this live move action; querying does not move the actor." if reachable else "No current route from the actor to this landing. Query self/activity and retry after the obstruction changes."}
