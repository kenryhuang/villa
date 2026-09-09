extends SceneTree

var scene: Node
var s: Farm3DSession
var w: Node
var observations: Array = []

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): finish(false, "Public AI test timed out"))
	run.call_deferred()

func finish(ok: bool, reason: String) -> void:
	if w != null:
		var file := FileAccess.open("res://tmp/living-world/P7-live.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok": ok, "reason": reason, "observations": observations, "world": w.to_dict(), "trace": s.agent_runtime.session_trace.get_requests()}, "  "))
	print("P7 real AI: %s · %s" % ["PASS" if ok else "FAIL", reason])
	quit(0 if ok else 1)

func decide(label: String) -> bool:
	var env: RefCounted = w.public_plans
	env.last_review = -1080
	if not env.scheduler._dispatch("village_public", "event", w.minute(), ""): return false
	while env.scheduler.is_in_flight("village_public"): await create_timer(.1).timeout
	observations.append({"scenario": label, "indicators": env.indicators(), "budget": env.budget(), "outcomes": env.observations.duplicate(true)})
	return true

func run() -> void:
	if "--living-world-live-agents" not in OS.get_cmdline_user_args() or "--living-world-scenario=P7" not in OS.get_cmdline_user_args(): finish(false, "Explicit isolated P7/live flags required"); return
	scene = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	s = scene.farm_session
	s.season.set_process(false)
	w = s.living_world
	w.set_process(false)
	s.save_path = "res://tmp/living-world/P7-live-save.json"
	s.inventory.add_item("bread", 12) # Explicit player supplier fixture, never injected on completion.
	if not s.agent_runtime.service_enabled or s.auto_save or s.auto_restore: finish(false, "Isolation/service unavailable"); return
	for id in s.agent_runtime.registry.get_agent_ids(): s.agent_runtime.scheduler.set_decision_interval_hours(id, 0)
	var env: RefCounted = w.public_plans
	env.bind_runtime()
	# Controlled purchasing-power shortage. Supplier has real existing stock and may decline.
	for resident in w.society.residents.values():
		var npc: NpcEconomyState = s.npc_economy.get_npc_state(resident.id)
		npc.inventory = {}
		npc.gold = 0
	s.npc_economy.get_npc_state("lao_li").inventory = {"bread": 20}
	if not await decide("真实基础食品短缺"): finish(false, "Could not dispatch public coordinator"); return
	if env.plans.is_empty(): finish(false, "Public agent chose no procurement; positive-loop evidence not obtained"); return
	var id: String = env.plans.keys()[0]
	# One voluntary supplier decision through the same existing private Agent service.
	if not s.agent_runtime.scheduler._dispatch("lao_li", "schedule", w.minute(), ""): finish(false, "Supplier not dispatched"); return
	while s.agent_runtime.scheduler.is_in_flight("lao_li"): await create_timer(.1).timeout
	w.projects.advance()
	if int(w.board.commissions[id].claimed) > 0 and int(w.board.commissions[id].delivered) == 0:
		var pending_count: int = env.plans.size()
		if not await decide("已有 NPC 接单补货正在履行"): finish(false, "Incoming supply observation failed"); return
		if env.plans.size() != pending_count: finish(false, "Existing supplier commitment duplicated"); return
	for n in 8: w.projects.advance()
	# The NPC may prefer a competing posted order. That is a legitimate independent choice.
	# The player can supply a public commission through the same official claim/delivery rules.
	if int(w.board.commissions[id].delivered) == 0:
		var c: Dictionary = w.board.commissions[id]
		var remaining := int(c.terms.quantity) - int(c.claimed) - int(c.delivered)
		if remaining <= 0: finish(false, "Supplier has committed work still pending; do not steal its claim"); return
		if not w.board.claim("player", "public-player-supply", id, remaining).ok: finish(false, "Player supply claim failed"); return
		var count_before: int = env.plans.size()
		if not await decide("已有真实接单补货待交付"): finish(false, "Incoming supply observation failed"); return
		if env.plans.size() != count_before: finish(false, "Existing supply duplicated"); return
		if not w.board.deliver("player", "public-player-receipt", "public-player-supply", remaining, int(c.version)).ok: finish(false, "Player real goods delivery failed"); return
		observations.append({"supplier": "player", "reason": "NPC freely chose its own project; player used the official public order"})
	else:
		observations.append({"supplier": "lao_li", "reason": "NPC independently supplied the public order"})
	env._distribute()
	if env.distributions.is_empty() or not s.save_game() or not s.load_game(): finish(false, "Actual public distribution or persistence failed"); return
	# Existing accepted supply is visible; repeated planning must not create duplicate spending.
	var count: int = env.plans.size()
	if not await decide("已有公共措施及补货承诺"): finish(false, "Second observation failed"); return
	if env.plans.size() != count: finish(false, "Duplicate public procurement"); return
	s.npc_economy.get_npc_state("village_public").gold = 0
	if not await decide("公共可用预算为零"): finish(false, "Budget observation failed"); return
	if env.plans.size() != count or s.npc_economy.get_npc_state("village_public").gold != 0: finish(false, "Budget limit bypassed"); return
	finish(true, "Public AI funded a real bread commission; voluntary supply transferred real goods and residents received food, save/reload retained accounts, and repeated/zero-budget observations created no extra spending.")
