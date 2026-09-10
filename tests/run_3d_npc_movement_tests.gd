extends SceneTree

var checks := 0
var failures: Array[String] = []
var session: Farm3DSession
var runtime: Node
var simulation_minute := 0

func tick(frame: int) -> void:
	if frame % 15 == 0: simulation_minute += 1
	session.season.hour = 6 + simulation_minute / 60
	session.season.minute = simulation_minute % 60
	session.living_world.environment.advance_to(simulation_minute)
	runtime.executor.complete_due(simulation_minute)

func _initialize() -> void:
	create_timer(90, true, false, true).timeout.connect(func(): push_error("NPC movement timed out"); quit(1))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func action(actor: String, tool: String, args: Dictionary, key: String) -> Dictionary:
	return {"agent_id": actor, "decision_id": key, "request_id": key, "action_id": key, "idempotency_key": key, "tool_name": tool, "arguments": args}

func finish(key: String) -> bool:
	for frame in 1800:
		await physics_frame
		tick(frame)
		if runtime.executor._outcomes.get(key, {}).get("status") in ["completed", "failed", "rejected"]:
			if runtime.executor._outcomes[key].status != "completed": print("FAILED ACTION ", key, " ", runtime.executor._outcomes[key])
			return runtime.executor._outcomes[key].status == "completed"
	print("TIMEOUT ACTION ", key, " ", runtime.executor._outcomes.get(key), " activities=", runtime.activity_system.to_dict())
	return false

func _run() -> void:
	Engine.time_scale = 4.0
	var farm: Node3D = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.set_process(false)
	session = farm.get_node("FarmSession")
	session.save_path = "res://tmp/npc-movement-save.json"
	session.season.set_process(false)
	session.living_world.set_process(false)
	runtime = session.agent_runtime
	for id in ["farmer_ahe", "lao_li", "xuezhe_lin"]:
		check("move" in runtime._build_request(id, "schedule", 0, "").allowed_command_tools, id + " receives move")
		var body: Node3D = runtime.farm3d_actors[id]
		var start := body.position
		var target := start + Vector3(0, 0, 3)
		for offset in [Vector3(0, 0, 3), Vector3(3, 0, 0), Vector3(0, 0, -3), Vector3(-3, 0, 0)]:
			var candidate: Vector3 = start + offset
			if not session.living_world.work.paths.find_path_cells(session.grid.world_to_grid(start.x, start.z), session.grid.world_to_grid(candidate.x, candidate.z)).is_empty():
				target = candidate
				break
		var intent := action(id, "move", {"x": target.x, "z": target.z}, id + ":walk")
		check(runtime.validator._valid_arguments("move", intent.arguments), "Move coordinates pass Godot contract")
		var started: Dictionary = runtime.executor.execute(intent, 0)
		check(started.status == "in_progress" and body.position == start, id + " move starts a physical trip without teleporting: " + str(started))
		await physics_frame
		await physics_frame
		check(body.position.distance_to(start) > .01 and body.position.distance_to(target) > .65, "Actor actually walks through intermediate positions")
		check(await finish(intent.idempotency_key), "Move completes after arrival")
		check(Vector2(body.position.x, body.position.z).distance_to(Vector2(target.x, target.z)) <= .65, "Completed move is at the requested destination")
	var merchant: Node3D = runtime.farm3d_actors.lao_li
	var npc: NpcEconomyState = session.npc_economy.get_npc_state("lao_li")
	npc.gold = 10000
	var before := npc.to_dict()
	var one := action("lao_li", "buy", {"item_id": "grain", "quantity": 1}, "trip-buy-1")
	var two := action("lao_li", "buy", {"item_id": "carrot", "quantity": 1}, "trip-buy-2")
	var batch := {"agent_id": "lao_li", "decision_id": "shopping", "request_id": "shopping", "actions": [one, two]}
	check(runtime.executor.execute_batch(batch, 0)[0].status == "in_progress", "Shopping batch is accepted as a trip")
	check(npc.to_dict() == before, "Nothing is charged or delivered before arriving at market")
	var saved: Dictionary = runtime.activity_system.to_dict()
	var execution: Dictionary = runtime.executor.to_dict()
	check(runtime.activity_system.from_dict(saved) and runtime.executor.from_dict(execution), "Pending movement and batch continuation survive restore")
	check(session.save_game() and session.load_game(), "Full farm save restores a traveling action and remaining shopping batch")
	merchant = runtime.farm3d_actors.lao_li
	npc = session.npc_economy.get_npc_state("lao_li")
	merchant.stop_agent_work()
	check(await finish("trip-buy-1"), "Restored shopping trip reaches market")
	check(await finish("trip-buy-2"), "Second purchase continues automatically without another decision")
	check(int(npc.inventory.get("grain", 0)) == int(before.inventory.get("grain", 0)) + 1 and int(npc.inventory.get("carrot", 0)) == int(before.inventory.get("carrot", 0)) + 1, "Both purchases commit exactly once")
	var after := npc.to_dict()
	runtime.executor.execute_batch(batch, 0)
	check(npc.to_dict() == after, "Replaying the batch does not buy twice")
	var lake := Farm3DTerrainProfile.LAKE_CENTER
	var bad := action("lao_li", "move", {"x": lake.x, "z": lake.y}, "unreachable-lake")
	var position_before := merchant.position
	check(runtime.executor.execute(bad, 0).status in ["failed", "rejected"] and merchant.position == position_before, "Unreachable water destination fails without teleporting")
	check(not runtime.validator._valid_arguments("move", {"x": INF, "z": 0}) and not runtime.validator._valid_arguments("move", {"x": -999, "z": 0}), "Invalid coordinates are rejected")
	var stalled := action("lao_li", "move", {"x": merchant.position.x + 3, "z": merchant.position.z + 6}, "stalled-trip")
	check(runtime.executor.execute(stalled, simulation_minute).status == "in_progress", "A reachable trip starts before a later blockage")
	merchant.set_physics_process(false)
	simulation_minute += 31
	tick(1)
	check(runtime.executor._outcomes["stalled-trip"].get("failure_code") == "path_blocked", "A stalled trip fails instead of completing at a distance")
	merchant.set_physics_process(true)
	var explorer: NpcEconomyState = session.npc_economy.get_npc_state("xuezhe_lin")
	explorer.gold = 1000
	var supplies_before := explorer.to_dict()
	var supplies := action("xuezhe_lin", "prepare_supplies", {"item_id": "bread", "quantity": 1}, "explorer-supplies")
	check(runtime.executor.execute(supplies, simulation_minute).status == "in_progress" and explorer.to_dict() == supplies_before, "Explorer supply purchase also walks before spending")
	check(await finish("explorer-supplies"), "Supply purchase completes at the market")
	check(int(explorer.inventory.get("bread", 0)) == int(supplies_before.inventory.get("bread", 0)) + 1, "Explorer receives exactly the purchased supplies")
	session.player.position = session.grid.get_cell(32, 31).world_position_3d() + Vector3.LEFT * 1.2
	var placed: Dictionary = session.buildings.try_place_building("windmill", 32, 31)
	check(placed.placed, "Build a real processing destination")
	if placed.placed:
		var building: BuildingInstance = placed.instance
		building.restore_construction(3, 9.0)
		building.set_process(false)
		var farmer: NpcEconomyState = session.npc_economy.get_npc_state("farmer_ahe")
		farmer.gold = 1000
		farmer.inventory = {"grain": 10}
		var rent := action("farmer_ahe", "rent_production", {"building_id": building.instance_id, "recipe_id": "flour", "batches": 1, "max_fee": 50}, "physical-rent")
		var sale := action("farmer_ahe", "sell", {"item_id": "flour", "quantity": 1}, "after-rental-sale")
		check(runtime.executor.execute_batch({"agent_id": "farmer_ahe", "decision_id": "physical-rent", "actions": [rent, sale]}, simulation_minute)[0].status == "in_progress", "Rental includes a trip to the building")
		check(farmer.gold == 1000 and farmer.inventory.grain == 10 and building.producer_state.jobs.is_empty(), "Rental consumes no money, ingredients or queue capacity before arrival")
		for frame in 600:
			await physics_frame
			tick(frame)
			if not building.producer_state.jobs.is_empty(): break
		check(building.producer_state.jobs.size() == 1 and farmer.gold < 1000 and farmer.inventory.grain == 8, "Arriving places the paid processing order")
		check(runtime.executor._outcomes["physical-rent"].status == "in_progress", "Placed order remains pending until its goods are delivered")
		session.production.advance_minutes(60)
		check(runtime.executor._outcomes["physical-rent"].status == "completed", "Existing production callback completes the original action")
		check(await finish("after-rental-sale"), "After production, the same batch walks to market and sells its actual goods")
	print("NPC MOVEMENT: %d checks, %d failures" % [checks, failures.size()])
	farm.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
