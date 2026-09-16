extends SceneTree

const Society = preload("res://scripts/systems/resident_society_system.gd")
var failures := 0
var checks := 0
var session: Node
var runtime: Node

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Startup action test timed out"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func command(actor: String, key: String, actions: Array) -> Dictionary:
	var rows := []
	for i in actions.size():
		rows.append({"action_id": "%s:%d" % [key, i], "idempotency_key": "%s:%d" % [key, i], "tool_version": 1, "tool_name": actions[i][0], "arguments": actions[i][1]})
	return {"protocol_version": 2, "request_id": key, "decision_id": key, "agent_id": actor, "expected_revision": runtime.executor.world_revision, "decision_summary": "startup verification", "actions": rows}

func finish_action(actor: String, key: String) -> void:
	for frame in 1600:
		var minute: int = session.living_world.minute() + 1
		session.season.total_days = minute / 1080 + 1
		session.season.hour = 6 + (minute % 1080) / 60
		session.season.minute = minute % 60
		runtime.executor.complete_due(minute)
		var result: Dictionary = runtime.executor._outcomes.get(key, {})
		if result.get("status") in ["completed", "rejected", "failed"]:
			check(result.status == "completed", actor + " actual completion: " + str(result.get("failure_code", "")))
			return
		await physics_frame
	check(false, actor + " physical action did not finish")

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	session = scene.farm_session; runtime = session.agent_runtime
	scene.set_process(false); session.season.set_process(false); session.living_world.set_process(false)
	runtime.service_enabled = false; runtime.set_process(false)
	check(not session.auto_save and not session.auto_restore, "Headless new world never touches player save")
	var profiles: Array = Society.economy_profiles()
	check(profiles == Society.economy_profiles(), "Starter profile generation is repeatable and does not accumulate")
	for id in ["lao_li", "afu_shui", "xuezhe_lin", "tiejiang_zhang", "resident_yun"]:
		var state: NpcEconomyState = session.npc_economy.get_npc_state(id)
		check(state.gold >= 5000 and int(state.inventory.get("bread", 0)) >= 12, id + " starts with working capital and actual food")
		var resources: Dictionary = runtime.loop_state.snapshot(runtime, id)
		check(resources.gold == state.gold and resources.inventory == state.inventory, id + " context uses authoritative starter assets")
		if runtime.farm3d_actors.has(id): runtime.farm3d_actors[id].move_speed = 40
	check(session.npc_economy.get_npc_state("village_public").gold == 5000, "Public funding is not inflated")
	var smith: NpcEconomyState = session.npc_economy.get_npc_state("tiejiang_zhang")
	var before_gold := smith.gold
	var before_iron := int(smith.inventory.iron_ingot)
	runtime.executor.execute_batch(command("tiejiang_zhang", "starter-smith", [["sell", {"item_id": "iron_ingot", "quantity": 2}]]), session.living_world.minute())
	await finish_action("tiejiang_zhang", "starter-smith:0")
	check(smith.gold > before_gold and smith.inventory.iron_ingot == before_iron - 2, "Smith walks and earns money from real starting stock")
	for actor in ["afu_shui", "xuezhe_lin"]:
		var state: NpcEconomyState = session.npc_economy.get_npc_state(actor)
		var bread_before := int(state.inventory.bread)
		var batch := command(actor, "starter-" + actor, [["travel", {"region_id": "creek", "duration_minutes": 10}], ["survey", {"region_id": "creek"}]])
		var validated: Dictionary = runtime.validator.validate(batch, runtime.registry, runtime.executor.world_revision, runtime.role_system)
		check(validated.ok, actor + " travel/survey is authorized")
		if not validated.ok: continue
		runtime.executor.execute_batch(validated.value, session.living_world.minute())
		await finish_action(actor, "starter-%s:1" % actor)
		check(int(state.inventory.bread) == bread_before - 1, actor + " survey consumes real starting bread")
		check(not session.living_world.knowledge._private.get(actor, {}).is_empty(), actor + " obtains actual field evidence")
	# A consumed balance restored from a save is never silently topped up again.
	var saved: Dictionary = session.npc_economy.to_dict()
	var low: NpcEconomyState = session.npc_economy.get_npc_state("lao_li")
	low.gold = 5; low.inventory = {}
	var spent: Dictionary = session.npc_economy.to_dict()
	check(session.npc_economy.from_dict(spent) and low.gold == 5, "Loading spent assets does not grant initial funds again")
	check(session.npc_economy.get_npc_state("lao_li").gold == 5 and session.npc_economy.get_npc_state("lao_li").inventory.is_empty(), "Loaded canonical inventory remains spent")
	check(session.npc_economy.from_dict(saved), "New endowment state round-trips through existing save schema")
	print("NPC startup resources: %d checks, %d failures" % [checks, failures])
	scene.queue_free(); await process_frame
	quit(1 if failures else 0)
