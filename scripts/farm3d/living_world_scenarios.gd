extends RefCounted

## Explicit test-world seeds only. Never loaded into an existing player save.
static func setup(scene: Node, stage: String) -> bool:
	if stage not in ["P0", "P1", "P2", "P3", "P4", "P5"]: return false
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
		var cell := session.grid.get_cell(32 + index * 6, 31)
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
	if stage in ["P2", "P3", "P4", "P5"]:
		session.living_world.society.reset(session.living_world.minute())
		session.living_world.board.daily(1)
	if not runtime.service_enabled:
		var command := {"agent_id": "lao_li", "tool_name": "propose_trade", "idempotency_key": "scenario-offer", "decision_id": "scenario-request", "action_id": "scenario-action", "arguments": {
			"target_actor_id": "player", "give": {"items": {"salt": 1}, "gold": 0}, "receive": {"items": {"carrot": 2}, "gold": 0}, "expires_in_minutes": 120, "note": "一份盐换两根胡萝卜，可以还价。"}}
		if not runtime.interaction_system.execute(command, runtime._absolute_game_minute()).ok: return false
	scene.camera_rig.global_position = session.player.global_position + Vector3.UP * 1.2
	return true
