extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var s: Farm3DSession = scene.farm_session
	s.season.set_process(false)
	var w: Node = s.living_world
	var society: RefCounted = w.society
	DirAccess.make_dir_recursive_absolute("res://tmp/living-world")
	s.save_path = "res://tmp/living-world/P2.json"
	check(society.residents.size() == 12 and s.npc_economy._states.size() == 14, "12 residents and two organizations use original accounts")
	check(s.npc_economy._population_profiles.size() == 1 and s.npc_economy._population_profiles[0].id == "tourists", "No duplicated internal demand")
	check(s.npc_economy._agent_managed.size() == 14, "All internal shortcut production disabled")
	var baseline: int = society.total_gold()
	for day in 7:
		s.season.advance_game_minutes(1080)
		check(society.total_gold() + society.wage_escrow() + escrow(w) == baseline + society.external_gold_net, "Day %d conserves money including external market" % (day + 1))
		check(society.day_reports.has(str(day + 1)), "Daily food report exists")
		check(s.save_game() and s.load_game(), "Daily save resumes without resets")
	var before: Dictionary = society.to_dict()
	w.advance()
	check(society.to_dict() == before, "Repeated simulation cannot pay wages or consume twice")
	var paid := 0
	for shift in society.shifts.values():
		if shift.status == "completed":
			paid += 1
			check(int(shift.worked_minutes) == 180 and int(shift.escrow) == 0, "Wages require completed attendance")
	check(paid == 21, "Finite three shifts per day")
	var inn: NpcEconomyState = s.npc_economy.get_npc_state("village_inn")
	inn.gold = 0
	var count: int = society.shifts.size()
	s.season.advance_game_minutes(121)
	check(society.shifts.size() == count, "No employer money means no funded shift")
	var broken: Dictionary = w.to_dict()
	broken.society.shifts.values()[0].escrow = 90
	check(not w.validate(broken), "Corrupted wage escrow rejected")
	check(w.resident_visuals.size() == 3, "Visible background residents reflect simulation")
	var poor: NpcEconomyState = s.npc_economy.get_npc_state("resident_mei")
	poor.gold = 0
	poor.inventory = {}
	society._feed_day(8)
	society.advance_to(society.last_minute)
	check(society.residents.resident_mei.food_reason == "unaffordable", "Hunger from purchasing power distinguished")
	var damaged: Dictionary = w.to_dict()
	damaged.society.ledger[0].items = []
	check(not w.validate(damaged), "Malformed ledger rejected")
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tmp/living-world/P2.json"))
	legacy.version = 6
	legacy.erase("living_world")
	legacy.npc_economy.npc_states = legacy.npc_economy.npc_states.filter(func(state): return state.npc_id in ["farmer_ahe", "lao_li", "xiao_hua", "tiejiang_zhang", "afu_shui", "xuezhe_lin"])
	var old_li_gold: int = legacy.npc_economy.npc_states.filter(func(state): return state.npc_id == "lao_li")[0].gold
	s.save_path = "res://tmp/living-world/P2-legacy.json"
	var file := FileAccess.open(s.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy, "  "))
	file.close()
	poor.gold = 99999
	check(s.load_game(), "Version 6 original six-resident save migrates")
	check(s.npc_economy.get_npc_state("resident_mei").gold == 180 and s.npc_economy.get_npc_state("lao_li").gold == old_li_gold, "Only new residents receive configured endowment; old wallet preserved")
	check(s.save_game() and s.load_game() and s.npc_economy.get_npc_state("resident_mei").gold == 180, "Migrated save does not endow twice")
	print("P2: %d checks, %d failures" % [checks, failures])
	scene.free()
	quit(0 if failures == 0 else 1)

func escrow(w: Node) -> int:
	var total := 0
	for c in w.board.commissions.values(): total += int(c.escrow)
	return total
