extends RefCounted

## Explicit test-world seeds only. Never loaded into an existing player save.
static func setup(scene: Node, stage: String, walkthrough := false) -> bool:
	if stage not in ["P0", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10", "P11", "P12"]: return false
	var session: Farm3DSession = scene.farm_session
	if session.auto_save or session.auto_restore: return false
	DirAccess.make_dir_recursive_absolute("res://tmp/living-world")
	session.save_path = "res://tmp/living-world/%s.json" % stage
	session.inventory.add_item("grain", 40)
	session.inventory.add_item("carrot", 10)
	for id in ["lao_li", "farmer_ahe"]:
		var npc := session.npc_economy.get_npc_state(id)
		npc.inventory = {"grain": 40, "salt": 10, "wood": 10, "stone": 10}
		npc.gold = 1000
	for index in (2 if stage == "P1" else 1):
		var cell := session.grid.get_cell((42 if stage == "P12" else 32) + index * 6, 31)
		session.player.position = cell.world_position_3d() + Vector3.LEFT * 1.2
		var placed: Dictionary = session.buildings.try_place_building("windmill", cell.gx, cell.gz)
		if not placed.placed: return false
		var building: BuildingInstance = placed.instance
		building.restore_construction(3, 9.0)
		building.set_process(false)
		building.owner_id = "player" if index == 0 else "lao_li"
		building.instance_id = "living-world-%s-%d" % [stage, index]
	session.player.position = session.grid.get_cell(32, 31).world_position_3d() + Vector3.LEFT * 1.2
	var runtime: Node = session.agent_runtime
	if stage in ["P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10", "P11", "P12"]:
		session.living_world.society.reset(session.living_world.minute())
		session.living_world.board.daily(1)
	if not runtime.service_enabled:
		var command := {"agent_id": "lao_li", "tool_name": "propose_trade", "idempotency_key": "scenario-offer", "decision_id": "scenario-request", "action_id": "scenario-action", "arguments": {
			"target_actor_id": "player", "give": {"items": {"salt": 1}, "gold": 0}, "receive": {"items": {"carrot": 2}, "gold": 0}, "expires_in_minutes": 120, "note": "一份盐换两根胡萝卜，可以还价。"}}
		if not runtime.interaction_system.execute(command, runtime._absolute_game_minute()).ok: return false
	if walkthrough and stage == "P6":
		var mill: BuildingInstance = session.buildings.get_all_buildings()[0]
		var plan := {"goal": "加工一份面粉再销售", "budget": 4, "deadline_minutes": 500, "materials": {"grain": 2}, "steps": [
			{"id": "mill", "capability": "rent", "depends_on": [], "arguments": {"building_id": mill.instance_id, "recipe_id": "flour", "batches": 1, "max_fee": 4}},
			{"id": "ready", "capability": "wait_production", "depends_on": ["mill"], "arguments": {"order_step": "mill"}},
			{"id": "sale", "capability": "sell", "depends_on": ["ready"], "arguments": {"item_id": "flour", "quantity": 1, "limit": 1}}]}
		if not session.living_world.projects.submit("lao_li", "P6-walkthrough", plan).ok: return false
		session.living_world.projects.advance()
		session.living_world.projects.advance()
		session.player.position = session.living_world.actor("lao_li").position + Vector3(1.5, 0, 1.5)
	if walkthrough and stage == "P7":
		for resident in session.living_world.society.residents.values():
			var npc: NpcEconomyState = session.npc_economy.get_npc_state(resident.id)
			npc.inventory = {}
			npc.gold = 0
		session.npc_economy.get_npc_state("lao_li").inventory = {"bread": 20}
		session.inventory.add_item("bread", 12)
	if stage == "P12": session.living_world.society.paths._ensure_built()
	scene.camera_rig.global_position = session.player.global_position + Vector3.UP * 1.2
	return true
